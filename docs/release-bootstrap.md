# Release, bootstrap, and update policy

This document defines the product contract for installing and refreshing released versions of `isolated-dotnet-sdk`.

## Stable versus development usage

Stable usage is version-pinned. A stable bootstrap downloads the tool script from an explicit published Git tag, verifies the downloaded bytes against that release's `SHA256SUMS` asset, and only then executes the temporary file.

Executing a downloaded file is important: the tool's existing file-based bootstrap preserves the exact executing script when it installs or replaces the saved copy under `~/dotnet-sdks`. Stable bootstrap must therefore not pipe released source directly into PowerShell or Bash, because piped execution has no source file and the tool's remote fallback is the development `main` source.

Development usage is separate and opt-in. Commands that execute the script directly from the repository's mutable `main` branch are development commands, not stable installation commands.

## Stable installation

Choose an explicit published release tag from GitHub Releases. Releases published under the Issue #22 policy include a `SHA256SUMS` release asset containing entries for both platform scripts.

### PowerShell

Replace `<release-tag>` with the desired published tag:

```powershell
$release = '<release-tag>'
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

### Bash

Replace `<release-tag>` with the desired published tag:

```bash
release='<release-tag>'
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

These commands preserve the Issue #21 semantics while adding a pre-execution integrity gate: the user explicitly chooses a published tag, the downloaded source must match the checksum material for that release, and file-based bootstrap then preserves the exact verified source.

### Legacy `v0.1.0`

`v0.1.0` predates the Issue #22 integrity policy. It has no `SHA256SUMS` release asset and was published without release immutability. Its historical release is not modified retroactively. The checksum-verifying stable-bootstrap commands above apply to releases published under the new policy.

## Updates

Updates are explicit. Normal execution of the saved tool does not check GitHub, replace itself, or move to another release channel.

To update, choose a newer published release tag and rerun the verified stable-bootstrap command with that tag. The newly downloaded and verified tagged source replaces the saved tool through the existing staged bootstrap replacement path.

No background updater, startup update check, or automatic latest-version discovery is part of the stable contract.

## Rollback

Rollback is the same operation as update, but with an older published release tag that supplies the required checksum material. Rerun the stable-bootstrap command with the desired older tag. The existing staged bootstrap replacement behavior applies in both directions.

If acquisition, checksum verification, or final replacement fails, unverified source is never executed and the previously saved tool remains the authoritative installed copy where the existing bootstrap recovery contract can preserve it.

## Development / `main`

For explicit development testing, mutable `main` may still be used directly:

PowerShell:

```powershell
irm https://raw.githubusercontent.com/infoconex/isolated-dotnet-sdk/main/isolated-dotnet-sdk.ps1 | iex
```

Bash:

```bash
curl -fsSL https://raw.githubusercontent.com/infoconex/isolated-dotnet-sdk/main/isolated-dotnet-sdk.sh | bash
```

Because these commands intentionally consume mutable `main`, rerunning them may replace the saved tool with newer development source. They must not be described as the stable installation path and do not receive the stable-release checksum guarantee.

## Version discovery

Stable version discovery is intentionally outside the tool runtime. Users choose a published version from the repository's GitHub Releases page or release documentation and use that exact tag in the bootstrap command.

The tool does not query the GitHub Releases API, follow a latest-stable channel, or silently resolve a moving version alias.

## PowerShell and Bash parity

PowerShell and Bash follow the same product-level policy:

- stable source is an explicit published tag;
- stable bootstrap downloads checksum material and verifies the selected script before execution;
- stable bootstrap executes a downloaded file so exact verified source is preserved;
- normal saved-tool execution does not auto-update;
- update and rollback are explicit tag selections; and
- `main` is development-only.

Shell-native temporary-file and SHA-256 mechanics may differ.

## Release-maintenance contract

For releases after Issue #22, a version becomes available for stable installation only when all of the following are true:

1. the intended release commit has passed repository validation;
2. a Git tag for the release version points to that reviewed release commit;
3. `pwsh -NoProfile -File ./scripts/New-ReleaseChecksums.ps1 -OutputPath <path>/SHA256SUMS` is run against that exact release tree;
4. the generated `SHA256SUMS` contains SHA-256 entries for `isolated-dotnet-sdk.ps1` and `isolated-dotnet-sdk.sh` and is retained unchanged for publication;
5. a GitHub Release is created as a **draft** for that tag;
6. `SHA256SUMS` and every other intended release asset are attached while the release is still a draft;
7. the draft is reviewed and then published; and
8. repository release immutability is enabled so publication locks the release tag and assets.

GitHub recommends attaching all assets to a draft before publishing an immutable release. Under GitHub's immutable-release behavior, the published release's tag cannot be moved and its assets cannot be replaced or deleted while the release exists; GitHub also creates a release attestation. The checksum file remains useful as the direct cross-platform bootstrap verification input, while the GitHub attestation provides platform provenance.

Release immutability applies only to future releases, which is why `v0.1.0` remains a documented legacy trust boundary rather than being rewritten.

See [`supply-chain-integrity.md`](supply-chain-integrity.md) for the complete remote-dependency inventory and residual trust assumptions.
