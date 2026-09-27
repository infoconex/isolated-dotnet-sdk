# Release, bootstrap, and update policy

This document defines the product contract for installing and refreshing released versions of `isolated-dotnet-sdk`.

## Stable versus development usage

Stable usage is version-pinned. A stable bootstrap downloads the tool script from an explicit published Git tag such as `v0.1.0`, writes that exact released source to a temporary file, and executes the temporary file.

Executing a downloaded file is important: the tool's existing file-based bootstrap preserves the exact executing source when it installs or replaces the saved copy under `~/dotnet-sdks`. A stable bootstrap must therefore not pipe the released tool directly into PowerShell or Bash, because piped execution has no source file and the current tool's remote fallback is the development `main` source.

Development usage is separate and opt-in. Commands that execute the script directly from the repository's mutable `main` branch are development commands, not stable installation commands.

## Stable installation

Choose an explicit published release tag from GitHub Releases.

### PowerShell

Replace `<release-tag>` with the desired published tag:

```powershell
$release = '<release-tag>'
$temp = Join-Path ([System.IO.Path]::GetTempPath()) ("isolated-dotnet-sdk-$release.ps1")
try {
    Invoke-WebRequest "https://raw.githubusercontent.com/infoconex/isolated-dotnet-sdk/$release/isolated-dotnet-sdk.ps1" -OutFile $temp
    & $temp
}
finally {
    Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
}
```

### Bash

Replace `<release-tag>` with the desired published tag:

```bash
release='<release-tag>'
temp="$(mktemp "${TMPDIR:-/tmp}/isolated-dotnet-sdk.XXXXXX.sh")"
trap 'rm -f "$temp"' EXIT
curl -fsSL "https://raw.githubusercontent.com/infoconex/isolated-dotnet-sdk/$release/isolated-dotnet-sdk.sh" -o "$temp"
chmod +x "$temp"
"$temp"
```

These commands are deterministic with respect to tool source: the release tag in the URL identifies the source that is downloaded and subsequently preserved by file-based bootstrap.

## Updates

Updates are explicit. Normal execution of the saved tool does not check GitHub, replace itself, or move to another release channel.

To update, choose a newer published release tag and rerun the stable bootstrap command with that tag. The newly downloaded tagged source replaces the saved tool through the existing staged bootstrap replacement path.

No background updater, startup update check, or automatic latest-version discovery is part of the stable contract.

## Rollback

Rollback is the same operation as update, but with an older published release tag. Rerun the stable bootstrap command with the desired older tag. The existing staged bootstrap replacement behavior applies in both directions.

If acquisition or final replacement fails, the previously saved tool remains the authoritative installed copy where the existing bootstrap recovery contract can preserve it.

## Development / `main`

For explicit development testing, the mutable `main` source may still be used directly:

PowerShell:

```powershell
irm https://raw.githubusercontent.com/infoconex/isolated-dotnet-sdk/main/isolated-dotnet-sdk.ps1 | iex
```

Bash:

```bash
curl -fsSL https://raw.githubusercontent.com/infoconex/isolated-dotnet-sdk/main/isolated-dotnet-sdk.sh | bash
```

Because these commands intentionally consume mutable `main`, rerunning them may replace the saved tool with newer development source. They must not be described as the stable installation path.

## Version discovery

Stable version discovery is intentionally outside the tool runtime. Users choose a published version from the repository's GitHub Releases page or from release documentation and use that exact tag in the bootstrap command.

The tool does not query the GitHub Releases API, follow a latest-stable channel, or silently resolve a moving version alias.

## PowerShell and Bash parity

PowerShell and Bash follow the same product-level policy:

- stable source is an explicit published tag;
- stable bootstrap executes a downloaded file so exact source is preserved;
- normal saved-tool execution does not auto-update;
- update and rollback are explicit tag selections;
- `main` is development-only.

Shell-native temporary-file and invocation mechanics may differ.

## Release-maintenance contract

A newly published version becomes available for stable installation when all of the following are true:

1. the intended release commit has passed repository validation;
2. a Git tag for the release version points to that reviewed release commit;
3. a GitHub Release is published for that tag;
4. the tagged repository contains both platform tool scripts at their documented paths;
5. release documentation identifies the published tag users should substitute into the stable bootstrap command.

This issue intentionally does not add release assets, checksums, signatures, attestations, or other artifact-integrity mechanisms. Those protections are tracked separately by Issue #22.
