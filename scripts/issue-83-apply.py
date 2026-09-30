from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file_path = Path(path)
    text = file_path.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"Expected exactly one match in {path}, found {count}: {old[:80]!r}")
    file_path.write_text(text.replace(old, new), encoding="utf-8")


# Bash: preserve the existing version-only install marker helper while adding a
# richer read-only inventory seam for List.
replace_once(
    "isolated-dotnet-sdk.sh",
    '''get_system_sdk_versions() {
    if command -v dotnet >/dev/null 2>&1; then
        local sdk_output=""
        if sdk_output="$(dotnet --list-sdks)"; then
            printf "%s\\n" "$sdk_output" | awk '{print $1}'
        else
            local status=$?
            tool_fail "Unable to list SDKs through the system dotnet host with exit code $status."
        fi
    fi
}
''',
    '''get_system_sdk_inventory() {
    if command -v dotnet >/dev/null 2>&1; then
        local sdk_output=""
        if sdk_output="$(dotnet --list-sdks)"; then
            [[ -n "$sdk_output" ]] && printf "%s\\n" "$sdk_output"
        else
            local status=$?
            tool_fail "Unable to list SDKs through the system dotnet host with exit code $status."
        fi
    fi
}

get_system_sdk_versions() {
    local sdk_output=""
    sdk_output="$(get_system_sdk_inventory)"
    [[ -n "$sdk_output" ]] && printf "%s\\n" "$sdk_output" | awk '{print $1}'
}
''',
)
replace_once(
    "isolated-dotnet-sdk.sh",
    '        echo "  3. List isolated SDKs"\n',
    '        echo "  3. List installed SDKs"\n',
)
replace_once(
    "isolated-dotnet-sdk.sh",
    '''list_isolated_sdks() {
    local versions
    local line
    versions="$(get_isolated_sdk_versions)"

    tool_info "Isolated SDKs under $SDK_ROOT:"

    if [[ -z "$versions" ]]; then
        printf "  %s\\n" "None"
        return
    fi

    while IFS= read -r line; do
        [[ -n "$line" ]] && printf "  %s\\n" "$line"
    done <<< "$versions"
}
''',
    '''list_installed_sdks() {
    local isolated_versions=""
    local system_inventory=""
    local line=""
    local version=""
    local sdk_path=""

    isolated_versions="$(get_isolated_sdk_versions)"
    system_inventory="$(get_system_sdk_inventory)"

    tool_info "Installed .NET SDKs"
    echo
    echo "Isolated SDKs:"

    if [[ -z "$isolated_versions" ]]; then
        printf "  %s\\n" "None"
    else
        while IFS= read -r line; do
            [[ -n "$line" ]] && printf "  %s  %s\\n" "$line" "$SDK_ROOT/$line"
        done <<< "$isolated_versions"
    fi

    echo
    echo "System SDKs:"

    if [[ -z "$system_inventory" ]]; then
        printf "  %s\\n" "None"
        return
    fi

    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        if [[ "$line" =~ ^([^[:space:]]+)[[:space:]]+\\[(.*)\\]$ ]]; then
            version="${BASH_REMATCH[1]}"
            sdk_path="${BASH_REMATCH[2]}"
            printf "  %s  %s\\n" "$version" "$sdk_path"
        else
            printf "  %s\\n" "$line"
        fi
    done <<< "$system_inventory"
}
''',
)
replace_once(
    "isolated-dotnet-sdk.sh",
    '''        list)
            list_isolated_sdks
            ;;
''',
    '''        list)
            list_installed_sdks
            ;;
''',
)
replace_once(
    "isolated-dotnet-sdk.sh",
    '  list               List isolated SDKs under ~/dotnet-sdks. A version is invalid with list.\n',
    '  list               List isolated SDKs and SDKs visible through the normal dotnet host. A version is invalid with list.\n',
)
replace_once(
    "isolated-dotnet-sdk.sh",
    '''  Explicit actions   Run once and exit without entering the persistent Main loop.
  Verify <version>   Requires one exact version and checks only the existing isolated installation.
''',
    '''  Explicit actions   Run once and exit without entering the persistent Main loop.
  List               Shows isolated ownership first, then read-only SDKs reported by the normal dotnet --list-sdks host.
  Verify <version>   Requires one exact version and checks only the existing isolated installation.
''',
)

# PowerShell: keep install marker behavior via Get-SystemSdkVersion, backed by
# the richer inventory objects needed by the combined List presentation.
replace_once(
    "isolated-dotnet-sdk.ps1",
    '''function Get-SystemSdkVersion {
    if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
        return @()
    }

    $InstalledSdks = dotnet --list-sdks
    $ExitCode = $LASTEXITCODE
    if ($ExitCode -ne 0) {
        throw "Unable to list SDKs through the system dotnet host with exit code $ExitCode."
    }

    return @($InstalledSdks | ForEach-Object { ($_ -split '\\s+')[0] })
}
''',
    '''function Get-SystemSdkInventory {
    if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
        return @()
    }

    $InstalledSdks = dotnet --list-sdks
    $ExitCode = $LASTEXITCODE
    if ($ExitCode -ne 0) {
        throw "Unable to list SDKs through the system dotnet host with exit code $ExitCode."
    }

    return @(
        $InstalledSdks |
            ForEach-Object {
                $Line = [string]$_
                if ([string]::IsNullOrWhiteSpace($Line)) {
                    return
                }

                $Match = [regex]::Match($Line, '^(?<Version>\\S+)\\s+\\[(?<Path>.*)\\]$')
                if ($Match.Success) {
                    [pscustomobject]@{
                        Version = $Match.Groups['Version'].Value
                        Path = $Match.Groups['Path'].Value
                    }
                }
                else {
                    [pscustomobject]@{
                        Version = ($Line -split '\\s+')[0]
                        Path = ''
                    }
                }
            }
    )
}

function Get-SystemSdkVersion {
    return @(
        Get-SystemSdkInventory |
            ForEach-Object { $_.Version }
    )
}
''',
)
replace_once(
    "isolated-dotnet-sdk.ps1",
    '''function Show-IsolatedSdk {
    Write-ToolInfo "Isolated SDKs under ${SdkRoot}:"
    $Versions = @(Get-IsolatedSdkVersion)

    if (-not $Versions) {
        Write-ToolDisplay '  None'
        return
    }

    foreach ($SdkVersion in $Versions) {
        Write-ToolDisplay "  $SdkVersion"
    }
}
''',
    '''function Show-InstalledSdk {
    $IsolatedVersions = @(Get-IsolatedSdkVersion)
    $SystemSdks = @(Get-SystemSdkInventory)

    Write-ToolInfo 'Installed .NET SDKs'
    Write-ToolDisplay
    Write-ToolDisplay 'Isolated SDKs:'

    if (-not $IsolatedVersions) {
        Write-ToolDisplay '  None'
    }
    else {
        foreach ($SdkVersion in $IsolatedVersions) {
            Write-ToolDisplay "  $SdkVersion  $(Join-Path $SdkRoot $SdkVersion)"
        }
    }

    Write-ToolDisplay
    Write-ToolDisplay 'System SDKs:'

    if (-not $SystemSdks) {
        Write-ToolDisplay '  None'
        return
    }

    foreach ($Sdk in $SystemSdks) {
        if ([string]::IsNullOrWhiteSpace($Sdk.Path)) {
            Write-ToolDisplay "  $($Sdk.Version)"
        }
        else {
            Write-ToolDisplay "  $($Sdk.Version)  $($Sdk.Path)"
        }
    }
}
''',
)
replace_once(
    "isolated-dotnet-sdk.ps1",
    "        Write-ToolDisplay '  3. List isolated SDKs'\n",
    "        Write-ToolDisplay '  3. List installed SDKs'\n",
)
replace_once(
    "isolated-dotnet-sdk.ps1",
    "        'List' { Show-IsolatedSdk }\n",
    "        'List' { Show-InstalledSdk }\n",
)
replace_once(
    "isolated-dotnet-sdk.ps1",
    'Lists SDKs installed in the isolated SDK directory once and exits.\n',
    'Lists recognized isolated SDKs and SDKs reported by the normally resolved system dotnet host once and exits.\n',
)
replace_once(
    "isolated-dotnet-sdk.ps1",
    '''Exact-version installs bypass release-metadata discovery. Interactive install selection uses Microsoft's published .NET release metadata.
''',
    '''Exact-version installs bypass release-metadata discovery. Interactive install selection uses Microsoft's published .NET release metadata. List reports recognized isolated SDKs first and then the read-only SDK inventory returned by the normally resolved dotnet --list-sdks host. System SDK discovery is supplemental rather than an exhaustive filesystem inventory, and system SDKs are never managed by Remove.
''',
)

# Existing deterministic tests that intentionally asserted the old presentation.
replace_once(
    "tests/bash/behavior.bats",
    '  [[ "$output" == *"Isolated SDKs under"* ]]\n',
    '  [[ "$output" == *"Installed .NET SDKs"* ]]\n',
)
replace_once(
    "tests/bash/cross-platform.bats",
    '''  [[ "$output" == *"Isolated SDKs under $tool_root:"* ]]
  [[ "$output" == *"None"* ]]
''',
    '''  [[ "$output" == *"Isolated SDKs:"* ]]
  [[ "$output" == *"System SDKs:"* ]]
  [[ "$output" == *"None"* ]]
''',
)
replace_once(
    "tests/bash/cross-platform.bats",
    '  [[ "$output" == *"Isolated SDKs under $tool_root:"* ]]\n',
    '  [[ "$output" == *"Isolated SDKs:"* ]]\n',
)
replace_once(
    "tests/bash/interactive-lifecycle.bats",
    '''  [[ "$output" == *"Isolated SDKs under"* ]]
  [[ "$output" == *$'  None\\n\\nisolated-dotnet-sdk: What would you like to do?'* ]]
  [[ "$output" != *$'  None\\n\\n\\nisolated-dotnet-sdk: What would you like to do?'* ]]
''',
    '''  [[ "$output" == *"Isolated SDKs:"* ]]
  [[ "$output" == *"System SDKs:"* ]]
''',
)
replace_once(
    "tests/bash/interactive-lifecycle.bats",
    '  [[ "$output" == *"Isolated SDKs under"* ]]\n',
    '  [[ "$output" == *"Installed .NET SDKs"* ]]\n',
)
replace_once(
    "tests/powershell/behavior.Tests.ps1",
    "        ($listOutput -join [Environment]::NewLine) | Should -Match 'Isolated SDKs under'\n",
    "        ($listOutput -join [Environment]::NewLine) | Should -Match 'Installed \\.NET SDKs'\n",
)
replace_once(
    "tests/powershell/behavior.Tests.ps1",
    "        $listInformationOutput | Should -Match 'Isolated SDKs under'\n",
    "        $listInformationOutput | Should -Match 'Isolated SDKs:'\n        $listInformationOutput | Should -Match 'System SDKs:'\n",
)
replace_once(
    "tests/powershell/interactive-lifecycle.Tests.ps1",
    '''        $result.Output | Should -Match 'Isolated SDKs under'
        $result.Output | Should -Match '  None\\r?\\n\\r?\\nisolated-dotnet-sdk: What would you like to do\\?'
        $result.Output | Should -Not -Match '  None\\r?\\n(?:\\r?\\n){2,}isolated-dotnet-sdk: What would you like to do\\?'
''',
    '''        $result.Output | Should -Match 'Isolated SDKs:'
        $result.Output | Should -Match 'System SDKs:'
''',
)
replace_once(
    "tests/powershell/interactive-lifecycle.Tests.ps1",
    "        $result.Output | Should -Match 'Isolated SDKs under'\n",
    "        $result.Output | Should -Match 'Installed \\.NET SDKs'\n",
)
replace_once(
    "tests/powershell/interactive-lifecycle.Tests.ps1",
    "        (Get-MainPromptCount $result.Output) | Should -Be 2\n        $result.Output | Should -Match 'Isolated SDKs:'\n",
    "        (Get-MainPromptCount $result.Output) | Should -Be 2\n        $result.Output | Should -Match '3\\. List installed SDKs'\n        $result.Output | Should -Match 'Isolated SDKs:'\n",
)

# Real E2E continues to validate List but now asserts both ownership domains.
replace_once(
    "tests/e2e/bash/interactive.sh",
    '''  "Isolated SDKs under"
  "$sdk_version"
''',
    '''  "Isolated SDKs:"
  "System SDKs:"
  "$sdk_version"
''',
)
replace_once(
    "tests/e2e/powershell/interactive.ps1",
    '''        'Isolated SDKs under',
        $sdkVersion,
''',
    '''        'Isolated SDKs:',
        'System SDKs:',
        $sdkVersion,
''',
)

# Public behavioral specification.
replace_once(
    "docs/behavioral-parity.md",
    '| List | Report the isolated SDK root and recognized installed version directories; report `None` when empty. |\n',
    '| List | Report two ordered ownership groups: recognized isolated SDKs under the isolated root first, then read-only SDKs returned by the normally resolved `dotnet --list-sdks` host. Preserve same-version overlap across groups and report `None` for each empty group. |\n',
)
replace_once(
    "docs/behavioral-parity.md",
    '| Existing SDK detection | Distinguish SDKs already available from the system `dotnet` host from SDKs already present under the isolated root. |\n',
    '| Existing SDK detection | Distinguish SDKs already available from the system `dotnet` host from SDKs already present under the isolated root. An unavailable normal host is an empty system inventory; a resolved host whose `--list-sdks` command fails is an operational failure. |\n',
)

# README wording and visual: install/direct-host visuals remain normalized E2E;
# the combined List visual is explicitly representative because system-host SDKs
# vary by machine and runner image.
replace_once(
    "README.md",
    '  3. List isolated SDKs\n',
    '  3. List installed SDKs\n',
)
replace_once(
    "README.md",
    'The three visuals below use the supported Linux/Bash mapping and current real-E2E behavior. CI-only home-directory prefixes and timestamps are normalized so the isolated root is readable as `~/dotnet-sdks`; the product output itself is not invented. Windows uses PowerShell and `dotnet.exe`, while macOS uses Bash. See [`docs/cross-platform-support.md`](docs/cross-platform-support.md) for the supported platform mapping.\n',
    'The install and direct-host visuals below use the supported Linux/Bash mapping and current real-E2E behavior. CI-only home-directory prefixes and timestamps are normalized so the isolated root is readable as `~/dotnet-sdks`. The List visual is a representative ownership example because the SDKs visible through the normal system `dotnet` host vary by machine and runner image. Windows uses PowerShell and `dotnet.exe`, while macOS uses Bash. See [`docs/cross-platform-support.md`](docs/cross-platform-support.md) for the supported platform mapping.\n',
)
replace_once(
    "README.md",
    '### 2. List the isolated installation\n',
    '### 2. List installed SDKs by ownership domain\n',
)
replace_once(
    "README.md",
    '![Linux Bash E2E-validated transcript listing .NET SDK 10.0.100 under the isolated ~/dotnet-sdks root.](docs/images/isolation-list.svg)\n',
    'The List action shows recognized SDKs managed under the isolated root first, followed by read-only **System SDKs** reported by the normally resolved `dotnet --list-sdks` host. System SDK discovery is not an exhaustive filesystem scan and does not make those SDKs removable. If the same version exists in both domains, it appears in both groups; an unavailable normal `dotnet` host is shown as an empty System group, while a resolved host whose inventory command fails causes List to fail.\n\n![Representative Linux Bash installed-SDK listing showing isolated and system ownership groups, including the same SDK version in both domains.](docs/images/isolation-list.svg)\n',
)

Path("docs/images/isolation-list.svg").write_text(
    '''<svg xmlns="http://www.w3.org/2000/svg" width="1050" height="360" viewBox="0 0 1050 360" role="img" aria-labelledby="title desc">
  <title id="title">Linux Bash installed SDK ownership example</title>
  <desc id="desc">Representative list output showing .NET SDK 10.0.100 in both the isolated SDK root and the normal system dotnet host inventory.</desc>
  <rect width="1050" height="360" rx="10" fill="#14161a"/>
  <g font-family="ui-monospace, SFMono-Regular, Menlo, Consolas, 'Liberation Mono', monospace" fill="#e2e4e8">
    <text x="28" y="46" font-size="24" font-weight="700">Linux/Bash — representative ownership view</text>
    <text x="28" y="88" font-size="21">$ ~/dotnet-sdks/isolated-dotnet-sdk.sh list</text>
    <text x="28" y="126" font-size="21">isolated-dotnet-sdk: Installed .NET SDKs</text>
    <text x="28" y="168" font-size="21">Isolated SDKs:</text>
    <text x="56" y="202" font-size="20">10.0.100  ~/dotnet-sdks/10.0.100</text>
    <text x="28" y="246" font-size="21">System SDKs:</text>
    <text x="56" y="280" font-size="20">10.0.100  /usr/share/dotnet/sdk</text>
    <text x="28" y="326" font-size="16" fill="#a5aab2">Representative output; system inventory varies with the normally resolved dotnet host.</text>
  </g>
</svg>
''',
    encoding="utf-8",
)
