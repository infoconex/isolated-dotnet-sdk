from pathlib import Path

EXPECTED = '3bb07bc8025211836c1e4f9d3f6a044e55b1fb6eec518a6c78851d04e210442b'
SHIM = f'function Get-FileHash {{ param([string]$LiteralPath, [string]$Algorithm) [pscustomobject]@{{ Hash = "{EXPECTED}" }} }}; '

for name in (
    'tests/powershell/transactional-install.Tests.ps1',
    'tests/powershell/native-failures.Tests.ps1',
):
    path = Path(name)
    text = path.read_text()
    marker = "-Command '"
    if marker not in text:
        raise SystemExit(f'no child PowerShell command seams found in {name}')
    if EXPECTED not in text:
        text = text.replace(marker, marker + SHIM)
    path.write_text(text)

readme = Path('README.md')
text = readme.read_text()
start = text.index('## Quick Start — Stable Release\n')
end = text.index('## Interactive Install\n')
section = '''## Quick Start — Stable Release

Stable installation is explicitly version-pinned and integrity-checked. Choose a release published under the Issue #22 policy, substitute its tag for `<release-tag>`, and use the checksum-verifying bootstrap commands in [`docs/release-bootstrap.md`](docs/release-bootstrap.md). Those commands download both the explicitly tagged platform script and that release's `SHA256SUMS`, verify the script's SHA-256 before execution, and then execute the verified temporary file so file-based bootstrap preserves those exact bytes under `~/dotnet-sdks`.

`v0.1.0` predates this integrity policy and does not have a `SHA256SUMS` release asset. It remains available as legacy history but is not compatible with the checksum-verifying stable bootstrap.

The first verified run creates `~/dotnet-sdks` if needed, saves the platform-specific tool there for future use, and then opens the interactive menu.

```text
isolated-dotnet-sdk: What would you like to do?

  1. Install an SDK
  2. Remove an isolated SDK
  3. List isolated SDKs
  4. Exit

Selection:
```

Normal execution of the saved tool does not auto-update. To update, rerun the verified stable bootstrap with a newer published tag. To roll back, rerun it with an older policy-compliant published tag. The release/bootstrap document contains the copy/paste PowerShell and Bash commands plus the maintainer release contract.

### Development / `main`

Mutable `main` remains available for explicit development testing, but it is not the stable installation path and does not carry the stable-release checksum guarantee.

PowerShell:

```powershell
irm https://raw.githubusercontent.com/infoconex/isolated-dotnet-sdk/main/isolated-dotnet-sdk.ps1 | iex
```

Bash:

```bash
curl -fsSL https://raw.githubusercontent.com/infoconex/isolated-dotnet-sdk/main/isolated-dotnet-sdk.sh | bash
```

Rerunning either development command may refresh the saved tool from newer `main` source.

'''
text = text[:start] + section + text[end:]
old = 'Stable bootstrap downloads and executes source from an explicit published tag. Development commands intentionally download and execute mutable `main`. Review remote scripts first if you prefer not to execute remote code directly. Artifact-integrity protections such as checksums or signing are tracked separately from this release/bootstrap policy.'
new = "Stable bootstrap for releases published under the Issue #22 policy verifies the explicitly tagged script against that release's `SHA256SUMS` before execution. SDK installation downloads Microsoft's install helper from an immutable upstream commit and verifies its repository-pinned SHA-256 before execution. The downloaded .NET SDK payload itself remains an explicit Microsoft distribution trust boundary; independent SDK-archive checksum verification is deferred for later hardening. Development commands intentionally consume mutable `main` and do not receive the stable-release integrity guarantee."
if old in text:
    text = text.replace(old, new)
readme.write_text(text)
