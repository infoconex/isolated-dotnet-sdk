#!/usr/bin/env python3
import argparse
import json
import os
import pathlib
import shutil
import statistics
import subprocess
import sys
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
IS_WINDOWS = os.name == "nt"
TOOL_SOURCE = REPO_ROOT / ("isolated-dotnet-sdk.ps1" if IS_WINDOWS else "isolated-dotnet-sdk.sh")
TOOL_NAME = TOOL_SOURCE.name
SIZES = [1, 3, 5, 10, 20]

def percentile(values, p):
    values = sorted(values)
    if not values:
        return None
    idx = int(round((len(values) - 1) * p))
    return round(values[idx], 2)

def stats_ms(values):
    return {
        "median_ms": round(statistics.median(values), 2),
        "min_ms": round(min(values), 2),
        "p95_ms": percentile(values, 0.95),
    }

def run(cmd, env, input_text=None, check=False):
    started = time.perf_counter()
    proc = subprocess.run(
        cmd,
        env=env,
        input=input_text,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    elapsed_ms = (time.perf_counter() - started) * 1000
    if check and proc.returncode != 0:
        raise RuntimeError(
            f"Command failed ({proc.returncode}): {cmd}\nSTDOUT:\n{proc.stdout}\nSTDERR:\n{proc.stderr}"
        )
    return proc, elapsed_ms

def tool_cmd(tool_path, action=None):
    if IS_WINDOWS:
        cmd = ["pwsh", "-NoLogo", "-NoProfile", "-File", str(tool_path)]
        if action:
            cmd += ["-Action", action.capitalize()]
        return cmd
    cmd = ["bash", str(tool_path)]
    if action:
        cmd.append(action.lower())
    return cmd

def parse_system_versions(dotnet_path, env):
    proc, _ = run([dotnet_path, "--list-sdks"], env, check=True)
    versions = []
    for line in proc.stdout.splitlines():
        line = line.strip()
        if line:
            versions.append(line.split()[0])
    if not versions:
        raise RuntimeError("System dotnet reported no SDKs; benchmark requires at least one installed SDK.")
    return versions

def synthetic_versions(actual_versions, count):
    result = []
    for v in actual_versions:
        if v not in result:
            result.append(v)
        if len(result) >= count:
            return result[:count]
    channels = ["10.0", "9.0", "8.0", "11.0"]
    i = 0
    while len(result) < count:
        channel = channels[i % len(channels)]
        candidate = f"{channel}.{100 + i}"
        if candidate not in result:
            result.append(candidate)
        i += 1
    return result

def prepare_tool(home):
    sdk_root = home / "dotnet-sdks"
    sdk_root.mkdir(parents=True, exist_ok=True)
    tool_path = sdk_root / TOOL_NAME
    shutil.copy2(TOOL_SOURCE, tool_path)
    if not IS_WINDOWS:
        tool_path.chmod(0o755)
    return sdk_root, tool_path

def clear_isolated_dirs(sdk_root):
    for child in sdk_root.iterdir():
        if child.name == TOOL_NAME:
            continue
        if child.is_symlink() or child.is_file():
            child.unlink()
        elif child.is_dir():
            shutil.rmtree(child)

def make_placeholder_inventory(sdk_root, versions):
    clear_isolated_dirs(sdk_root)
    for version in versions:
        target_dir = sdk_root / version
        target_dir.mkdir(parents=True)
        host = target_dir / ("dotnet.exe" if IS_WINDOWS else "dotnet")
        if IS_WINDOWS:
            host.write_bytes(b"")
        else:
            host.write_text("#!/usr/bin/env bash\nexit 0\n", encoding="utf-8")
            host.chmod(0o755)

def measure_tool(tool_path, action, env, iterations=7, input_text=None):
    warm, _ = run(tool_cmd(tool_path, action), env, input_text=input_text)
    if warm.returncode != 0:
        raise RuntimeError(
            f"Warm-up failed for {action}: {warm.returncode}\n{warm.stdout}\n{warm.stderr}"
        )
    durations = []
    for _ in range(iterations):
        proc, elapsed = run(tool_cmd(tool_path, action), env, input_text=input_text)
        if proc.returncode != 0:
            raise RuntimeError(
                f"{action} failed during measurement: {proc.returncode}\n{proc.stdout}\n{proc.stderr}"
            )
        durations.append(elapsed)
    return stats_ms(durations)

def verify_sweep(dotnet_path, actual_versions, count, env, mixed=False):
    expected = []
    for i in range(count):
        if mixed and i % 3 == 0:
            expected.append(f"99.0.{100+i}")
        else:
            expected.append(actual_versions[i % len(actual_versions)])
    healthy = 0
    started = time.perf_counter()
    for version in expected:
        proc = subprocess.run(
            [dotnet_path, "--list-sdks"],
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        if proc.returncode != 0:
            continue
        versions = {line.split()[0] for line in proc.stdout.splitlines() if line.strip()}
        if version in versions:
            healthy += 1
    return (time.perf_counter() - started) * 1000, healthy

def measure_verify_proxy(dotnet_path, actual_versions, count, env, mixed=False, iterations=5):
    durations = []
    healthy_counts = []
    for _ in range(iterations):
        elapsed, healthy = verify_sweep(dotnet_path, actual_versions, count, env, mixed=mixed)
        durations.append(elapsed)
        healthy_counts.append(healthy)
    result = stats_ms(durations)
    result["healthy_checks"] = int(statistics.median(healthy_counts))
    result["total_checks"] = count
    return result

def write_system_wrapper(wrapper_dir, real_dotnet, count):
    wrapper_dir.mkdir(parents=True, exist_ok=True)
    versions = [f"10.0.{100+i}" for i in range(count)]
    if IS_WINDOWS:
        path = wrapper_dir / "dotnet.cmd"
        lines = ["@echo off", 'if "%1"=="--list-sdks" (']
        for v in versions:
            lines.append(f"  echo {v} [C:\\fake\\dotnet\\sdk]")
        lines += ["  exit /b 0", ")", f'"{real_dotnet}" %*']
        path.write_text("\r\n".join(lines) + "\r\n", encoding="utf-8")
    else:
        path = wrapper_dir / "dotnet"
        body = [
            "#!/usr/bin/env bash",
            'if [[ "${1:-}" == "--list-sdks" ]]; then',
        ]
        for v in versions:
            body.append(f"  printf '%s\\n' '{v} [/fake/dotnet/sdk]'")
        body += ["  exit 0", "fi", f"exec {json.dumps(real_dotnet)} \"$@\""]
        path.write_text("\n".join(body) + "\n", encoding="utf-8")
        path.chmod(0o755)
    return path

class MetadataServer:
    def __init__(self, mode):
        self.mode = mode
        self.request_paths = []
        outer = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, fmt, *args):
                return

            def do_GET(self):
                outer.request_paths.append(self.path)
                if outer.mode == "slow":
                    time.sleep(0.25)
                if outer.mode == "unavailable_index" and self.path == "/releases-index.json":
                    self.send_response(503)
                    self.end_headers()
                    return
                if outer.mode == "unavailable_channel" and self.path == "/10.0.json":
                    self.send_response(503)
                    self.end_headers()
                    return
                if outer.mode == "malformed_index" and self.path == "/releases-index.json":
                    self._json({})
                    return
                if outer.mode == "malformed_channel" and self.path == "/10.0.json":
                    self._json({})
                    return
                if self.path == "/releases-index.json":
                    self._json(outer.release_index())
                    return
                if self.path == "/10.0.json":
                    self._json(outer.channel_metadata("10.0", "10.0.401", "10.0.300"))
                    return
                if self.path == "/8.0.json":
                    self._json(outer.channel_metadata("8.0", "8.0.425", "8.0.400"))
                    return
                self.send_response(404)
                self.end_headers()

            def _json(self, payload):
                data = json.dumps(payload, indent=2).encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.port = self.server.server_address[1]
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)

    def release_index(self):
        base = f"http://127.0.0.1:{self.port}"
        return {
            "releases-index": [
                {
                    "channel-version": "10.0",
                    "latest-sdk": "10.0.401",
                    "support-phase": "active",
                    "release-type": "lts",
                    "releases.json": f"{base}/10.0.json",
                },
                {
                    "channel-version": "8.0",
                    "latest-sdk": "8.0.425",
                    "support-phase": "maintenance",
                    "release-type": "lts",
                    "releases.json": f"{base}/8.0.json",
                },
            ]
        }

    @staticmethod
    def channel_metadata(channel, latest, security_version):
        return {
            "channel-version": channel,
            "releases": [
                {
                    "release-date": "2026-09-01",
                    "security": False,
                    "sdk": {
                        "version": latest,
                        "files": [{"url": f"https://example.test/dotnet/Sdk/{latest}/archive.zip"}],
                    },
                },
                {
                    "release-date": "2026-08-01",
                    "security": True,
                    "sdk": {
                        "version": security_version,
                        "files": [{"url": f"https://example.test/dotnet/Sdk/{security_version}/archive.zip"}],
                    },
                },
            ],
        }

    def __enter__(self):
        self.thread.start()
        return self

    def __exit__(self, exc_type, exc, tb):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=2)

def patch_release_index(tool_path, url):
    text = TOOL_SOURCE.read_text(encoding="utf-8")
    old = "https://builds.dotnet.microsoft.com/dotnet/release-metadata/releases-index.json"
    if old not in text:
        raise RuntimeError("Release index URL not found in tool source.")
    text = text.replace(old, url, 1)
    tool_path.write_text(text, encoding="utf-8")
    if not IS_WINDOWS:
        tool_path.chmod(0o755)

def controlled_audit(sdk_root, tool_path, base_env, mode, interactive=False):
    make_placeholder_inventory(
        sdk_root,
        ["10.0.100", "10.0.200", "8.0.100", "8.0.200", "10.0.300"],
    )
    with MetadataServer(mode) as server:
        patch_release_index(tool_path, f"http://127.0.0.1:{server.port}/releases-index.json")
        if interactive:
            cmd = tool_cmd(tool_path, None)
            input_text = "A\nA\nE\n"
        else:
            cmd = tool_cmd(tool_path, "audit")
            input_text = None
        proc, elapsed = run(cmd, base_env, input_text=input_text)
        return {
            "status": proc.returncode,
            "elapsed_ms": round(elapsed, 2),
            "request_count": len(server.request_paths),
            "request_paths": server.request_paths,
            "stdout_tail": proc.stdout[-500:],
            "stderr_tail": proc.stderr[-500:],
        }

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    real_dotnet = shutil.which("dotnet")
    if not real_dotnet:
        raise RuntimeError("dotnet is required on the benchmark runner.")

    base_env = os.environ.copy()
    base_env["NO_COLOR"] = "1"
    actual_versions = parse_system_versions(real_dotnet, base_env)

    result = {
        "platform": sys.platform,
        "runner_os": os.environ.get("RUNNER_OS", sys.platform),
        "real_dotnet": real_dotnet,
        "system_sdk_count": len(actual_versions),
        "system_sdk_versions": actual_versions,
        "methodology": {
            "list": "Runs the production List command from its installed per-user path. Isolated inventories are synthetic recognized directories; system inventory is the runner's real dotnet --list-sdks output unless the system-scaling scenario says otherwise.",
            "verify_proxy": "Measures the dominant existing Verify cost by launching the runner's real dotnet --list-sdks once per isolated SDK and applying exact-version membership checks in-process. This intentionally avoids repeated tool-script startup, approximating a folded-into-List implementation.",
            "audit_live": "Runs the production Audit command against live Microsoft release metadata.",
            "audit_controlled": "Runs an unmodified Audit algorithm against a temporary local metadata endpoint by replacing only the release-index URL in a temporary installed copy. This measures request count and deterministic slow/unavailable/malformed behavior.",
        },
    }

    with tempfile.TemporaryDirectory(prefix="issue117-") as td:
        home = pathlib.Path(td)
        env = base_env.copy()
        env["HOME"] = str(home)
        env["USERPROFILE"] = str(home)
        sdk_root, tool_path = prepare_tool(home)

        list_isolated = {}
        for count in SIZES:
            versions = synthetic_versions(actual_versions, count)
            make_placeholder_inventory(sdk_root, versions)
            list_isolated[str(count)] = measure_tool(tool_path, "list", env)
        result["list_isolated_scaling"] = list_isolated

        system_scaling = {}
        clear_isolated_dirs(sdk_root)
        wrapper_root = home / "path-wrappers"
        for count in [1, 5, 20]:
            case_dir = wrapper_root / f"system-{count}"
            write_system_wrapper(case_dir, real_dotnet, count)
            case_env = env.copy()
            case_env["PATH"] = str(case_dir) + os.pathsep + base_env.get("PATH", "")
            system_scaling[str(count)] = measure_tool(tool_path, "list", case_env)
        result["list_system_scaling"] = system_scaling

        verify_healthy = {}
        verify_mixed = {}
        for count in SIZES:
            verify_healthy[str(count)] = measure_verify_proxy(real_dotnet, actual_versions, count, base_env, mixed=False)
            verify_mixed[str(count)] = measure_verify_proxy(real_dotnet, actual_versions, count, base_env, mixed=True)
        result["verify_proxy_healthy_scaling"] = verify_healthy
        result["verify_proxy_mixed_scaling"] = verify_mixed

        make_placeholder_inventory(sdk_root, synthetic_versions(actual_versions, 5))
        shutil.copy2(TOOL_SOURCE, tool_path)
        if not IS_WINDOWS:
            tool_path.chmod(0o755)
        live_durations = []
        live_statuses = []
        for _ in range(3):
            proc, elapsed = run(tool_cmd(tool_path, "audit"), env)
            live_durations.append(elapsed)
            live_statuses.append(proc.returncode)
        result["audit_live"] = {
            **stats_ms(live_durations),
            "statuses": live_statuses,
        }

        controlled = {}
        for mode in ["normal", "slow", "unavailable_index", "unavailable_channel", "malformed_index", "malformed_channel"]:
            samples = []
            for _ in range(3 if mode in ("normal", "slow") else 1):
                shutil.copy2(TOOL_SOURCE, tool_path)
                if not IS_WINDOWS:
                    tool_path.chmod(0o755)
                samples.append(controlled_audit(sdk_root, tool_path, env, mode))
            controlled[mode] = {
                "samples": samples,
                "median_ms": round(statistics.median([s["elapsed_ms"] for s in samples]), 2),
                "request_counts": [s["request_count"] for s in samples],
                "statuses": [s["status"] for s in samples],
            }
        result["audit_controlled"] = controlled

        shutil.copy2(TOOL_SOURCE, tool_path)
        if not IS_WINDOWS:
            tool_path.chmod(0o755)
        result["audit_repeated_interactive"] = controlled_audit(
            sdk_root, tool_path, env, "normal", interactive=True
        )

        shutil.copy2(TOOL_SOURCE, tool_path)
        if not IS_WINDOWS:
            tool_path.chmod(0o755)
        make_placeholder_inventory(sdk_root, ["10.0.100", "8.0.100"])
        list_proc, list_elapsed = run(tool_cmd(tool_path, "list"), env)
        result["list_after_audit_failure_boundary"] = {
            "status": list_proc.returncode,
            "elapsed_ms": round(list_elapsed, 2),
            "contains_inventory_heading": "Installed .NET SDKs" in list_proc.stdout,
        }

    out = pathlib.Path(args.output)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")

    print(json.dumps(result, indent=2))
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as f:
            f.write(f"## Issue 117 evaluation — {result['runner_os']}\n\n")
            f.write(f"- Real system SDK count: {result['system_sdk_count']}\n")
            f.write(f"- List isolated scaling median (1 → 20): {list_isolated['1']['median_ms']} ms → {list_isolated['20']['median_ms']} ms\n")
            f.write(f"- Verify proxy median (1 → 20): {verify_healthy['1']['median_ms']} ms → {verify_healthy['20']['median_ms']} ms\n")
            f.write(f"- Live Audit median: {result['audit_live']['median_ms']} ms; statuses: {live_statuses}\n")
            f.write(f"- Controlled Audit requests (normal): {controlled['normal']['request_counts']}\n")
            f.write(f"- Controlled slow Audit median: {controlled['slow']['median_ms']} ms\n")
            f.write(f"- Repeated interactive Audit request count: {result['audit_repeated_interactive']['request_count']}\n")
            f.write(f"- List after Audit failure boundary: status {result['list_after_audit_failure_boundary']['status']}\n")

if __name__ == "__main__":
    main()
