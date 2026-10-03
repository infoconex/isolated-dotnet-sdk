# Release, bootstrap, and update policy

This document defines the product contract for installing and refreshing released versions of `isolated-dotnet-sdk`.

## Stable versus development usage

Stable usage is version-pinned. A stable bootstrap downloads the tool script from an explicit published Git tag, verifies the downloaded bytes against that release's `SHA256SUMS` asset, and only then executes the temporary file.

Executing a downloaded file is important: the tool's existing file-based bootstrap preserves the exact executing script when it installs or replaces the saved copy under `~/dotnet-sdks`. Stable bootstrap must therefore not pipe released source directly into PowerShell or Bash, because piped execution has no source file and the tool's remote fallback is the development `main` source.

Development usage is separate and opt-in. Commands that execute the script directly from the repository's mutable `main` branch are development commands, not stable installation commands.

## Stable installation

The current checksum-policy-compliant stable release is `v0.2.0`. The commands below explicitly select that tag and require its `SHA256SUMS` release asset before executing either platform script.

To install another checksum-policy-compliant release, replace `v0.2.0` with that exact published tag. Stable version selection remains explicit; the tool does not resolve a moving latest-release alias.

### PowerShell

```powershell
$release = 'v0.2.0'
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

```bash
release='v0.2.0'
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

These commands preserve the existing explicit-tag, file-based bootstrap semantics while adding a pre-execution integrity gate: the user explicitly selects `v0.2.0`, the downloaded source must match the checksum material for that release, and file-based bootstrap then preserves the exact verified source.

### Legacy `v0.1.0`

`v0.1.0` predates the checksum-verifying stable-release policy and has no `SHA256SUMS` release asset. Its historical release is not modified retroactively. The checksum-verifying stable-bootstrap commands above apply to `v0.2.0` and later releases published under the current policy.

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

Checksum-policy-compliant stable releases are published through the manually triggered [`Publish Release`](../.github/workflows/publish-release.yml) workflow. Release publication is never triggered automatically by a push or merge to `main`; starting that workflow is the maintainer's intentional publication action.

Before dispatching the workflow:

1. the complete intended release state, including `.github/release-notes/<tag>.md`, must already be merged to `main`;
2. the exact intended `main` commit must have successful post-merge Validate and E2E push runs;
3. when a Pages push run exists for that exact commit, it must also be successful; and
4. the intended stable tag and GitHub Release must not already exist.

Dispatch `Publish Release` from `main` with the explicit stable tag. The workflow derives the release commit from the exact `main` commit selected by the manual dispatch and then fails closed unless all of the following remain true:

1. the dispatch SHA, checked-out SHA, and current `main` tip are identical;
2. the supplied tag uses stable `vMAJOR.MINOR.PATCH` form;
3. the version-controlled release-notes file exists and is non-empty;
4. the required landed-state Validate/E2E evidence is green for that exact commit, with Pages also green when a Pages run exists;
5. `scripts/New-ReleaseChecksums.ps1` generates exactly the two expected checksum entries from that exact release tree;
6. an independent SHA-256 calculation matches both generated script entries and the manifest has the expected deterministic text format;
7. a lightweight Git tag points directly to the derived release commit;
8. a GitHub Release is created as a **draft**, with the version-controlled notes as its exact body and only the intended `SHA256SUMS` asset;
9. the draft tag target, release metadata, asset set, and uploaded checksum bytes all match the reviewed local state; and
10. only after those draft checks pass, the workflow publishes the release and reads the public release, tag, and checksum asset back again to verify they are unchanged.

If the workflow fails before publication, it removes only the incomplete draft/tag state created by that run when it can establish that doing so is safe. Once a release has become public, automated cleanup is intentionally disabled; later verification failures are reported for maintainer review rather than deleting public release state.

After publication, `Publish Release` invokes the read-only [`Verify Release`](../.github/workflows/verify-release.yml) workflow. `Verify Release` can also be manually dispatched later with only the published stable tag; it resolves the commit directly from that lightweight tag, verifies the public release metadata and checksum asset, runs the supported Windows/PowerShell and Linux/Bash stable bootstrap paths, and confirms that each saved tool is byte-identical to the checksum-verified tagged source. This makes post-release verification independently rerunnable without asking maintainers to duplicate the tag-to-commit mapping by hand.

The publication workflow records the published release URL, exact commit SHA, checksum-manifest SHA-256, both script SHA-256 values, and the final manifest in the workflow summary. That evidence should be retained as the publication record.

Repository-level immutable releases are intentionally not part of this policy. Maintainers may retire/delete prior releases according to normal GitHub administration needs. That flexibility means GitHub release/tag/asset administration remains an accepted trust boundary: the `SHA256SUMS` manifest detects mismatched or corrupted acquired bytes, but it is not an independent signature and cannot protect against an authorized administrator deliberately replacing both the tagged source and matching checksum material.

For that reason, release review should record the intended tag target and checksum asset at publication time. The bootstrap contract relies on the release state the repository presents for the explicitly selected tag; it does not claim that GitHub itself prevents later administrative mutation.

See [`supply-chain-integrity.md`](supply-chain-integrity.md) for the complete remote-dependency inventory and residual trust assumptions.
