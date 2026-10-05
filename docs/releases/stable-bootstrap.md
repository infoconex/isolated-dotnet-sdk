# Stable bootstrap, update, and rollback

Stable use has two supported bootstrap modes:

- **latest stable** — the normal installation/update path, which resolves the latest published stable release at bootstrap time;
- **pinned stable** — an explicit release tag used for reproducibility, controlled rollout, or rollback.

Both modes ultimately execute a tagged `isolated-dotnet-sdk` product script only after verifying it against that release's `SHA256SUMS`. Mutable `main` remains a separate development-only source.

For releases published with embedded tool identity, the tagged script reports that exact tag through `-Version` on PowerShell or `--version` on Bash, and Main displays the same stable identity. Because file-based bootstrap preserves the verified tagged bytes, the saved tool keeps that same identity without querying GitHub later.

## Latest stable bootstrap

Windows / PowerShell 7:

```powershell
irm https://infoconex.github.io/isolated-dotnet-sdk/install.ps1 | iex
```

Linux or macOS / Bash:

```bash
curl -fsSL https://infoconex.github.io/isolated-dotnet-sdk/install.sh | bash
```

The small Pages-hosted bootstrap:

1. queries GitHub for the latest published, non-prerelease release;
2. validates the resolved stable release tag;
3. downloads that tag's platform-specific product script;
4. downloads the same release's `SHA256SUMS` asset;
5. requires exactly one valid checksum entry for the selected platform script;
6. verifies the downloaded product script's SHA-256; and
7. executes only the verified temporary product script.

The released product script then uses its existing file-based bootstrap behavior to preserve those exact verified bytes under `~/dotnet-sdks`. For releases that include embedded identity, that same tagged identity therefore survives latest-stable handoff and later saved-tool execution without a second version lookup or source.

### Trust boundary for the short command

A command piped directly from the project Pages site necessarily begins executing before it can verify its own bytes. The Pages-hosted `install.ps1` / `install.sh` bootstrap is therefore trusted through HTTPS delivery from `infoconex.github.io` plus the project/repository administration and Pages publication path.

The bootstrap does **not** claim to verify itself. Its checksum guarantee starts at the released product script it downloads: that tagged script must match the selected release's `SHA256SUMS` entry before the product script executes.

The checksum and tagged product script are both distributed through the project's GitHub trust domain. The checksum detects corruption and mismatched acquired bytes; it is not an independent publisher signature.

## Pinned stable bootstrap

Use a pinned release when the exact product version must be explicit rather than resolved through latest stable. The current checksum-policy-compliant stable release is `v0.3.0`.

### Windows / PowerShell 7

```powershell
$release = 'v0.3.0'
$temp = Join-Path ([System.IO.Path]::GetTempPath()) ("isolated-dotnet-sdk-$release.ps1")
$checksums = Join-Path ([System.IO.Path]::GetTempPath()) ("isolated-dotnet-sdk-$release-SHA256SUMS")
try {
    Invoke-WebRequest "https://raw.githubusercontent.com/infoconex/isolated-dotnet-sdk/$release/isolated-dotnet-sdk.ps1" -OutFile $temp
    Invoke-WebRequest "https://github.com/infoconex/isolated-dotnet-sdk/releases/download/$release/SHA256SUMS" -OutFile $checksums

    $checksumMatches = @(Select-String -LiteralPath $checksums -Pattern '^([0-9a-fA-F]{64})  isolated-dotnet-sdk\.ps1$')
    if ($checksumMatches.Count -ne 1) {
        throw 'SHA256SUMS does not contain exactly one valid isolated-dotnet-sdk.ps1 entry.'
    }

    $expected = $checksumMatches[0].Matches[0].Groups[1].Value
    $actual = (Get-FileHash -LiteralPath $temp -Algorithm SHA256).Hash
    if ($actual -ine $expected) {
        throw "Checksum verification failed for isolated-dotnet-sdk.ps1. Expected $expected, got $actual."
    }

    & $temp
}
finally {
    Remove-Item -LiteralPath $temp, $checksums -Force -ErrorAction SilentlyContinue
}
```

### Linux or macOS / Bash

```bash
release='v0.3.0'
temp="$(mktemp "${TMPDIR:-/tmp}/isolated-dotnet-sdk.XXXXXX.sh")"
checksums="$(mktemp "${TMPDIR:-/tmp}/isolated-dotnet-sdk.XXXXXX.SHA256SUMS")"
trap 'rm -f "$temp" "$checksums"' EXIT

curl -fsSL "https://raw.githubusercontent.com/infoconex/isolated-dotnet-sdk/$release/isolated-dotnet-sdk.sh" -o "$temp"
curl -fsSL "https://github.com/infoconex/isolated-dotnet-sdk/releases/download/$release/SHA256SUMS" -o "$checksums"

expected="$(awk '$2 == "isolated-dotnet-sdk.sh" && $1 ~ /^[0-9a-fA-F]{64}$/ { print tolower($1) }' "$checksums")"
[[ "$expected" =~ ^[0-9a-f]{64}$ ]] || {
    printf '%s\n' 'SHA256SUMS does not contain exactly one valid isolated-dotnet-sdk.sh entry.' >&2
    exit 1
}

if command -v sha256sum >/dev/null 2>&1; then
    actual="$(sha256sum "$temp" | awk '{print tolower($1)}')"
elif command -v shasum >/dev/null 2>&1; then
    actual="$(shasum -a 256 "$temp" | awk '{print tolower($1)}')"
else
    printf '%s\n' 'SHA-256 verification requires sha256sum or shasum.' >&2
    exit 1
fi

[[ "$actual" == "$expected" ]] || {
    printf 'Checksum verification failed for isolated-dotnet-sdk.sh. Expected %s, got %s.\n' "$expected" "$actual" >&2
    exit 1
}

chmod +x "$temp"
"$temp"
```

Pinned bootstrap deliberately downloads a real tagged product-script file, verifies it before execution, and relies on file-based bootstrap to save those exact verified bytes. For releases with embedded identity, pinning or rolling back to a tag also pins the tool-version value reported by that saved copy.

## Historical release boundaries

`v0.1.0` predates the checksum-verifying stable-release policy and has no `SHA256SUMS` release asset. Its published history is retained rather than rewritten retroactively.

`v0.2.0` is checksum-policy-compliant but predates the embedded tool-version identity model. It also remains historically unchanged rather than being rewritten solely to add version metadata.

The verified stable bootstrap contract applies to `v0.2.0` and later checksum-policy-compliant releases. Embedded stable identity applies to releases published after the tool-version model was introduced; the release verifier deliberately preserves compatibility with older published history.

## Updates

Normal execution of the saved tool does not query GitHub for updates, replace itself, or resolve a moving latest-stable release.

To explicitly update to the latest published stable release, rerun the short Pages bootstrap command for your platform. The latest-stable lookup happens only during that bootstrap operation.

To update to a specifically chosen release, use the pinned stable procedure with that exact policy-compliant tag.

The tool-version query itself never checks for updates. It reports only the identity already embedded in the copy being executed.

## Rollback

Rollback uses the pinned stable procedure with an older checksum-policy-compliant published tag. The selected tag is authoritative.

If the selected release includes embedded tool identity, the rollback copy reports that selected tag when run later. No latest-release lookup is performed to reinterpret it.

If release discovery, acquisition, checksum verification, staging, or final saved-tool replacement fails, unverified product source is not executed. Existing saved-tool state remains recovery state where the product's bootstrap replacement contract can preserve it.

## Development `main`

Mutable `main` is an explicit development source, not a stable channel. The getting-started guides show the corresponding development one-liner for each shell.

Current `main` product scripts carry `development` source identity. Their direct tool-version query reports `isolated-dotnet-sdk development (main)`, and the persistent Main menu displays the development source rather than inventing or looking up a stable version.

Rerunning a development command may refresh the saved tool from newer `main` source. It does not receive the stable-release checksum guarantee and must not be presented as stable installation or update behavior.

## Related documentation

- [Tool version](../commands/tool-version.md)
- [Bootstrap source preservation and reproducibility](../concepts/bootstrap-reproducibility.md)
- [Supply-chain integrity and trust boundaries](../concepts/supply-chain-integrity.md)
- [Stable release publication and verification](../maintainers/releases/release-process.md) — maintainer-only publication procedure
