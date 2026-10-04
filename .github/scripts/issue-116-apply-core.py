from pathlib import Path


def replace_exact(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text(encoding="utf-8")
    if old not in text:
        raise SystemExit(f"expected text not found in {path}: {old[:120]!r}")
    p.write_text(text.replace(old, new), encoding="utf-8")


def insert_before(path: str, anchor: str, insertion: str) -> None:
    p = Path(path)
    text = p.read_text(encoding="utf-8")
    if anchor not in text:
        raise SystemExit(f"anchor not found in {path}: {anchor!r}")
    p.write_text(text.replace(anchor, insertion + anchor, 1), encoding="utf-8")


# PowerShell action surface and Main menu.
replace_exact(
    "isolated-dotnet-sdk.ps1",
    "if ($script:Action -notin @('Install', 'Remove', 'List', 'Verify')) {",
    "if ($script:Action -notin @('Install', 'Remove', 'List', 'Verify', 'Audit')) {",
)
replace_exact(
    "isolated-dotnet-sdk.ps1",
    "        Write-ToolDisplay '  V. Verify an isolated SDK'\n        Write-ToolDisplay\n        Write-ToolDisplay '  E. Exit'",
    "        Write-ToolDisplay '  V. Verify an isolated SDK'\n        Write-ToolDisplay '  A. Audit installed SDKs'\n        Write-ToolDisplay\n        Write-ToolDisplay '  E. Exit'",
)
replace_exact(
    "isolated-dotnet-sdk.ps1",
    "            'v' { $script:Action = 'Verify'; return $true }\n            'V' { $script:Action = 'Verify'; return $true }\n            'e' { Write-ToolExit; return $false }",
    "            'v' { $script:Action = 'Verify'; return $true }\n            'V' { $script:Action = 'Verify'; return $true }\n            'a' { $script:Action = 'Audit'; return $true }\n            'A' { $script:Action = 'Audit'; return $true }\n            'e' { Write-ToolExit; return $false }",
)
replace_exact(
    "isolated-dotnet-sdk.ps1",
    "Write-InvalidSelection -Selection $Selection -Choices 'Choose I, R, L, V, or E.'",
    "Write-InvalidSelection -Selection $Selection -Choices 'Choose I, R, L, V, A, or E.'",
)
replace_exact(
    "isolated-dotnet-sdk.ps1",
    "    if ($script:Action -eq 'List' -and $script:SdkVersionWasSpecified) {\n        throw '-SdkVersion is supported only with -Action Install, Remove, or Verify.'\n    }",
    "    if ($script:Action -in @('List', 'Audit') -and $script:SdkVersionWasSpecified) {\n        throw '-SdkVersion is supported only with -Action Install, Remove, or Verify.'\n    }",
)
replace_exact(
    "isolated-dotnet-sdk.ps1",
    "        'List' { Show-InstalledSdk }\n        'Verify' {",
    "        'List' { Show-InstalledSdk }\n        'Audit' { Show-SdkAudit }\n        'Verify' {",
)

powershell_audit = r'''function Get-SdkChannelFromVersion {
    param([string]$Version)

    $Match = [regex]::Match($Version, '^(?<major>[0-9]+)\.(?<minor>[0-9]+)\.')
    if (-not $Match.Success) {
        return $null
    }

    return "$($Match.Groups['major'].Value).$($Match.Groups['minor'].Value)"
}

function Compare-SdkVersion {
    param(
        [string]$Left,
        [string]$Right
    )

    return [string]::CompareOrdinal(
        (Get-SdkVersionSortKey -SdkVersion $Left),
        (Get-SdkVersionSortKey -SdkVersion $Right))
}

function Get-AuditReleaseSdkVersion {
    param($Release)

    $Versions = [System.Collections.Generic.List[string]]::new()
    if ($Release.sdk -and -not [string]::IsNullOrWhiteSpace([string]$Release.sdk.version)) {
        $Versions.Add([string]$Release.sdk.version)
    }
    foreach ($Sdk in @($Release.sdks)) {
        if ($Sdk -and -not [string]::IsNullOrWhiteSpace([string]$Sdk.version)) {
            $Versions.Add([string]$Sdk.version)
        }
    }

    return @($Versions | Select-Object -Unique)
}

function Test-AuditSecurityUpdate {
    param(
        $ChannelMetadata,
        [string]$InstalledVersion
    )

    foreach ($Release in @($ChannelMetadata.releases)) {
        $SecurityText = [string]$Release.security
        $IsSecurityRelease = $Release.security -eq $true -or
            $SecurityText.Equals('true', [System.StringComparison]::OrdinalIgnoreCase)
        if (-not $IsSecurityRelease) {
            continue
        }

        foreach ($CandidateVersion in @(Get-AuditReleaseSdkVersion -Release $Release)) {
            if ((Compare-SdkVersion -Left $CandidateVersion -Right $InstalledVersion) -gt 0) {
                return $true
            }
        }
    }

    return $false
}

function Get-SdkAuditStatus {
    param(
        [string]$InstalledVersion,
        $ChannelEntry,
        $ChannelMetadata
    )

    $LatestSdk = [string]$ChannelEntry.'latest-sdk'
    $SupportPhase = [string]$ChannelEntry.'support-phase'

    if ($SupportPhase -eq 'eol') {
        return 'End of life'
    }

    if ($SupportPhase -notin @('active', 'maintenance', 'preview', 'go-live')) {
        return 'Unsupported'
    }

    $Comparison = Compare-SdkVersion -Left $InstalledVersion -Right $LatestSdk
    if ($Comparison -gt 0) {
        return 'Newer than known metadata'
    }

    $Lifecycle = switch ($SupportPhase) {
        'maintenance' { 'Maintenance' }
        'preview' { 'Preview' }
        'go-live' { 'Go Live' }
        default { '' }
    }

    if ($Comparison -eq 0) {
        if (-not [string]::IsNullOrWhiteSpace($Lifecycle)) {
            return $Lifecycle
        }
        return 'Current'
    }

    $Servicing = 'Update available'
    if ($SupportPhase -ne 'preview' -and
        (Test-AuditSecurityUpdate -ChannelMetadata $ChannelMetadata -InstalledVersion $InstalledVersion)) {
        $Servicing = 'Security update available'
    }

    $Status = "$Servicing -> $LatestSdk"
    if (-not [string]::IsNullOrWhiteSpace($Lifecycle)) {
        $Status = "$Status  $Lifecycle"
    }
    return $Status
}

function Show-SdkAudit {
    $IsolatedVersions = @(Get-IsolatedSdkVersion)
    $SystemSdks = @(Get-SystemSdkInventory)
    $InstalledVersions = @(
        $IsolatedVersions
        $SystemSdks | ForEach-Object { $_.Version }
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }

    if ($InstalledVersions.Count -eq 0) {
        Write-ToolHeading '.NET SDK audit'
        Write-ToolDisplay
        Write-ToolHeading 'Isolated SDKs:'
        Write-ToolDisplay '  None'
        Write-ToolDisplay
        Write-ToolHeading 'System SDKs:'
        Write-ToolDisplay '  None'
        return
    }

    $ReleaseIndex = Get-ReleaseIndex
    $ChannelEntries = @{}
    foreach ($Entry in @($ReleaseIndex.'releases-index')) {
        $Channel = [string]$Entry.'channel-version'
        if (-not [string]::IsNullOrWhiteSpace($Channel)) {
            $ChannelEntries[$Channel] = $Entry
        }
    }
    if ($ChannelEntries.Count -eq 0) {
        throw 'Invalid .NET release metadata from Microsoft.'
    }

    $ChannelMetadata = @{}
    foreach ($InstalledVersion in @($InstalledVersions | Select-Object -Unique)) {
        $Channel = Get-SdkChannelFromVersion -Version ([string]$InstalledVersion)
        if ([string]::IsNullOrWhiteSpace($Channel) -or -not $ChannelEntries.ContainsKey($Channel)) {
            continue
        }
        if ($ChannelMetadata.ContainsKey($Channel)) {
            continue
        }

        $Entry = $ChannelEntries[$Channel]
        $LatestSdk = [string]$Entry.'latest-sdk'
        $SupportPhase = [string]$Entry.'support-phase'
        $MetadataUrl = [string]$Entry.'releases.json'
        if ([string]::IsNullOrWhiteSpace($LatestSdk) -or
            [string]::IsNullOrWhiteSpace($SupportPhase) -or
            [string]::IsNullOrWhiteSpace($MetadataUrl)) {
            throw "Invalid release metadata index entry for .NET $Channel."
        }

        try {
            $Metadata = Invoke-RestMethod -Uri $MetadataUrl
        }
        catch {
            throw "Unable to load release metadata for .NET $Channel."
        }
        if ($null -eq $Metadata -or $null -eq $Metadata.releases) {
            throw "Invalid release metadata for .NET $Channel."
        }
        $ChannelMetadata[$Channel] = $Metadata
    }

    Write-ToolHeading '.NET SDK audit'
    Write-ToolDisplay
    Write-ToolHeading 'Isolated SDKs:'
    if ($IsolatedVersions.Count -eq 0) {
        Write-ToolDisplay '  None'
    }
    else {
        foreach ($InstalledVersion in $IsolatedVersions) {
            $Channel = Get-SdkChannelFromVersion -Version $InstalledVersion
            if ([string]::IsNullOrWhiteSpace($Channel) -or -not $ChannelEntries.ContainsKey($Channel)) {
                $Status = 'Unknown channel'
            }
            else {
                $Status = Get-SdkAuditStatus `
                    -InstalledVersion $InstalledVersion `
                    -ChannelEntry $ChannelEntries[$Channel] `
                    -ChannelMetadata $ChannelMetadata[$Channel]
            }
            Write-ToolDisplay "  $InstalledVersion  $Status"
        }
    }

    Write-ToolDisplay
    Write-ToolHeading 'System SDKs:'
    if ($SystemSdks.Count -eq 0) {
        Write-ToolDisplay '  None'
    }
    else {
        foreach ($Sdk in $SystemSdks) {
            $InstalledVersion = [string]$Sdk.Version
            $Channel = Get-SdkChannelFromVersion -Version $InstalledVersion
            if ([string]::IsNullOrWhiteSpace($Channel) -or -not $ChannelEntries.ContainsKey($Channel)) {
                $Status = 'Unknown channel'
            }
            else {
                $Status = Get-SdkAuditStatus `
                    -InstalledVersion $InstalledVersion `
                    -ChannelEntry $ChannelEntries[$Channel] `
                    -ChannelMetadata $ChannelMetadata[$Channel]
            }
            Write-ToolDisplay "  $InstalledVersion  $Status"
        }
    }
}

'''
insert_before(
    "isolated-dotnet-sdk.ps1",
    "function Invoke-IsolatedSdkBuildServerShutdown {",
    powershell_audit,
)

# Bash action surface and Main menu.
replace_exact(
    "isolated-dotnet-sdk.sh",
    '        echo "  V. Verify an isolated SDK"\n        echo\n        echo "  E. Exit"',
    '        echo "  V. Verify an isolated SDK"\n        echo "  A. Audit installed SDKs"\n        echo\n        echo "  E. Exit"',
)
replace_exact(
    "isolated-dotnet-sdk.sh",
    '            v|V) ACTION="verify"; return 0 ;;\n            e|E) tool_exit; return 1 ;;',
    '            v|V) ACTION="verify"; return 0 ;;\n            a|A) ACTION="audit"; return 0 ;;\n            e|E) tool_exit; return 1 ;;',
)
replace_exact(
    "isolated-dotnet-sdk.sh",
    'warn_invalid_selection "$selection" "Choose I, R, L, V, or E."',
    'warn_invalid_selection "$selection" "Choose I, R, L, V, A, or E."',
)
replace_exact(
    "isolated-dotnet-sdk.sh",
    '        list)\n            list_installed_sdks\n            ;;\n        verify)',
    '        list)\n            list_installed_sdks\n            ;;\n        audit)\n            audit_installed_sdks\n            ;;\n        verify)',
)
replace_exact(
    "isolated-dotnet-sdk.sh",
    '  isolated-dotnet-sdk.sh list\n  isolated-dotnet-sdk.sh verify <version>',
    '  isolated-dotnet-sdk.sh list\n  isolated-dotnet-sdk.sh audit\n  isolated-dotnet-sdk.sh verify <version>',
)
replace_exact(
    "isolated-dotnet-sdk.sh",
    '  list               List isolated SDKs and SDKs visible through the normal dotnet host. A version is invalid with list.\n  verify <version>   Read-only health check for one exact installed isolated SDK.',
    '  list               List isolated SDKs and SDKs visible through the normal dotnet host. A version is invalid with list.\n  audit              Online lifecycle and servicing assessment for installed isolated and System SDKs.\n  verify <version>   Read-only health check for one exact installed isolated SDK.',
)
replace_exact(
    "isolated-dotnet-sdk.sh",
    '        install|remove|list|verify)',
    '        install|remove|list|verify|audit)',
)
replace_exact(
    "isolated-dotnet-sdk.sh",
    'if [[ "$ACTION" == "list" && -n "$VERSION" ]]; then\n    tool_fail "An SDK version cannot be combined with list."\nfi',
    'if [[ "$ACTION" == "list" && -n "$VERSION" ]]; then\n    tool_fail "An SDK version cannot be combined with list."\nfi\n\nif [[ "$ACTION" == "audit" && -n "$VERSION" ]]; then\n    tool_fail "An SDK version cannot be combined with audit."\nfi',
)

bash_audit = r'''sdk_channel_from_version() {
    local version="$1"
    local core="${version%%-*}"
    local major=""
    local minor=""
    local patch=""

    IFS='.' read -r major minor patch <<< "$core"
    if [[ ! "$major" =~ ^[0-9]+$ || ! "$minor" =~ ^[0-9]+$ || ! "$patch" =~ ^[0-9]+$ ]]; then
        return 1
    fi

    printf '%s.%s' "$major" "$minor"
}

compare_sdk_versions() {
    local left_key=""
    local right_key=""

    left_key="$(sdk_version_sort_key "$1")"
    right_key="$(sdk_version_sort_key "$2")"
    if [[ "$left_key" == "$right_key" ]]; then
        printf '%s' '0'
    elif [[ "$left_key" > "$right_key" ]]; then
        printf '%s' '1'
    else
        printf '%s' '-1'
    fi
}

parse_audit_release_index() {
    tr ',' '\n' | parse_release_index
}

extract_security_sdk_versions() {
    tr ',' '\n' | awk '
        /"release-date"[[:space:]]*:/ { security="false" }
        /"security"[[:space:]]*:[[:space:]]*true/ { security="true" }
        /"security"[[:space:]]*:[[:space:]]*false/ { security="false" }
        /\/dotnet\/Sdk\// {
            value=$0
            sub(/^.*\/dotnet\/Sdk\//, "", value)
            sub(/\/.*$/, "", value)
            if (value != "") {
                print value "|" security
            }
        }
    ' | awk '!seen[$0]++'
}

audit_status_for_version() {
    local version="$1"
    local channel_data="$2"
    local channel_summaries="$3"
    local channel=""
    local summary=""
    local latest_sdk=""
    local phase=""
    local security_versions=""
    local comparison=0
    local servicing=""
    local lifecycle=""
    local candidate=""

    if ! channel="$(sdk_channel_from_version "$version")"; then
        printf '%s' 'Unknown channel'
        return
    fi

    if ! printf '%s\n' "$channel_data" | awk -F '|' -v channel="$channel" '$1 == channel { found=1; exit } END { exit !found }'; then
        printf '%s' 'Unknown channel'
        return
    fi

    summary="$(printf '%s\n' "$channel_summaries" | awk -F '|' -v channel="$channel" '$1 == channel { print; exit }')"
    if [[ -z "$summary" ]]; then
        printf '%s' 'Unknown channel'
        return
    fi

    IFS='|' read -r _ latest_sdk phase security_versions <<< "$summary"

    if [[ "$phase" == "eol" ]]; then
        printf '%s' 'End of life'
        return
    fi

    case "$phase" in
        active) lifecycle="" ;;
        maintenance) lifecycle="Maintenance" ;;
        preview) lifecycle="Preview" ;;
        go-live) lifecycle="Go Live" ;;
        *) printf '%s' 'Unsupported'; return ;;
    esac

    comparison="$(compare_sdk_versions "$version" "$latest_sdk")"
    if (( comparison > 0 )); then
        printf '%s' 'Newer than known metadata'
        return
    fi

    if (( comparison == 0 )); then
        if [[ -n "$lifecycle" ]]; then
            printf '%s' "$lifecycle"
        else
            printf '%s' 'Current'
        fi
        return
    fi

    servicing="Update available"
    if [[ "$phase" != "preview" && -n "$security_versions" ]]; then
        IFS=',' read -r -a security_array <<< "$security_versions"
        for candidate in "${security_array[@]}"; do
            [[ -n "$candidate" ]] || continue
            if (( $(compare_sdk_versions "$candidate" "$version") > 0 )); then
                servicing="Security update available"
                break
            fi
        done
    fi

    printf '%s -> %s' "$servicing" "$latest_sdk"
    if [[ -n "$lifecycle" ]]; then
        printf '  %s' "$lifecycle"
    fi
}

audit_installed_sdks() {
    local isolated_versions=""
    local system_inventory=""
    local installed_versions=""
    local index_json=""
    local channel_data=""
    local channel_summaries=""
    local known_channels=""
    local version=""
    local channel=""
    local entry=""
    local latest_sdk=""
    local phase=""
    local release_type=""
    local releases_url=""
    local metadata_json=""
    local security_versions=""
    local status=""

    isolated_versions="$(get_isolated_sdk_versions)"
    system_inventory="$(get_system_sdk_inventory)"
    installed_versions="$(
        {
            [[ -n "$isolated_versions" ]] && printf '%s\n' "$isolated_versions"
            [[ -n "$system_inventory" ]] && printf '%s\n' "$system_inventory" | awk '{print $1}'
        } | awk 'NF && !seen[$0]++'
    )"

    if [[ -z "$installed_versions" ]]; then
        tool_heading ".NET SDK audit"
        echo
        tool_heading "Isolated SDKs:"
        printf '  %s\n' 'None'
        echo
        tool_heading "System SDKs:"
        printf '  %s\n' 'None'
        return
    fi

    tool_info "Loading available .NET SDK releases from Microsoft..."
    index_json="$(curl -fsSL "$RELEASE_INDEX_URL")" || \
        tool_fail "Unable to load .NET release metadata from Microsoft."
    if ! looks_like_json_object "$index_json" || [[ "$index_json" != *'"releases-index"'* ]]; then
        tool_fail "Invalid .NET release metadata from Microsoft."
    fi

    channel_data="$(printf '%s\n' "$index_json" | parse_audit_release_index)"
    [[ -n "$channel_data" ]] || tool_fail "Invalid .NET release metadata from Microsoft."

    while IFS= read -r version; do
        [[ -n "$version" ]] || continue
        if ! channel="$(sdk_channel_from_version "$version")"; then
            continue
        fi
        if contains_line "$known_channels" "$channel"; then
            continue
        fi

        entry="$(printf '%s\n' "$channel_data" | awk -F '|' -v channel="$channel" '$1 == channel { print; exit }')"
        [[ -n "$entry" ]] || continue
        IFS='|' read -r _ latest_sdk phase release_type releases_url <<< "$entry"
        if [[ -z "$latest_sdk" || -z "$phase" || -z "$releases_url" ]]; then
            tool_fail "Invalid release metadata index entry for .NET $channel."
        fi

        if metadata_json="$(curl -fsSL "$releases_url")"; then
            :
        else
            tool_fail "Unable to load release metadata for .NET $channel."
        fi
        if ! looks_like_json_object "$metadata_json" || [[ "$metadata_json" != *'"releases"'* ]]; then
            tool_fail "Invalid release metadata for .NET $channel."
        fi

        security_versions="$(
            printf '%s\n' "$metadata_json" |
                extract_security_sdk_versions |
                awk -F '|' '$2 == "true" { print $1 }' |
                awk '!seen[$0]++' |
                paste -sd, -
        )"
        channel_summaries="${channel_summaries}${channel}|${latest_sdk}|${phase}|${security_versions}"$'\n'
        known_channels="${known_channels}${channel}"$'\n'
    done <<< "$installed_versions"

    tool_heading ".NET SDK audit"
    echo
    tool_heading "Isolated SDKs:"
    if [[ -z "$isolated_versions" ]]; then
        printf '  %s\n' 'None'
    else
        while IFS= read -r version; do
            [[ -n "$version" ]] || continue
            status="$(audit_status_for_version "$version" "$channel_data" "$channel_summaries")"
            printf '  %s  %s\n' "$version" "$status"
        done <<< "$isolated_versions"
    fi

    echo
    tool_heading "System SDKs:"
    if [[ -z "$system_inventory" ]]; then
        printf '  %s\n' 'None'
    else
        while IFS= read -r version; do
            [[ -n "$version" ]] || continue
            status="$(audit_status_for_version "$version" "$channel_data" "$channel_summaries")"
            printf '  %s  %s\n' "$version" "$status"
        done < <(printf '%s\n' "$system_inventory" | awk '{print $1}')
    fi
}

'''
insert_before(
    "isolated-dotnet-sdk.sh",
    "cleanup_install_transaction() {",
    bash_audit,
)

# Keep deterministic tests aligned with the new Main choice and make malformed
# PowerShell metadata distinguishable from a transport exception.
for path in (
    "tests/bash/interactive-lifecycle.bats",
    "tests/bash/global-exit.bats",
    "tests/powershell/interactive-lifecycle.Tests.ps1",
    "tests/powershell/global-exit.Tests.ps1",
):
    p = Path(path)
    text = p.read_text(encoding="utf-8")
    text = text.replace("Choose I, R, L, V, or E.", "Choose I, R, L, V, A, or E.")
    text = text.replace("Choose I, R, L, V, or E\\.", "Choose I, R, L, V, A, or E\\.")
    p.write_text(text, encoding="utf-8")

replace_exact(
    "tests/powershell/audit.Tests.ps1",
    "Set-Content -LiteralPath (Join-Path $script:MetadataRoot '10.0.json') -Value 'not-json'",
    "Set-Content -LiteralPath (Join-Path $script:MetadataRoot '10.0.json') -Value '{}'",
)
replace_exact(
    "tests/bash/audit.bats",
    "printf '%s\\n' 'not-json' > \"$metadata_root/10.0.json\"",
    "printf '%s\\n' '{}' > \"$metadata_root/10.0.json\"",
)
