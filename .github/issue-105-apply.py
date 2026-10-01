from pathlib import Path


def replace_once(text, old, new, label):
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f'{label}: expected exactly one match, found {count}')
    return text.replace(old, new, 1)


# PowerShell implementation.
ps_path = Path('isolated-dotnet-sdk.ps1')
ps = ps_path.read_text()
ps = replace_once(
    ps,
    "        [ValidateSet('Heading', 'Success')]",
    "        [ValidateSet('Heading', 'Accent', 'Success')]",
    'PowerShell presentation roles')

old = '''function Write-ToolInfo {
    param([string]$Message)
    Write-ToolDisplay $Message
}

function Write-ToolHeading {
'''
new = '''function Write-ToolInfo {
    param([string]$Message)
    Write-ToolDisplay $Message
}

function Write-ToolLabelValue {
    param(
        [string]$Label,
        [AllowEmptyString()]
        [string]$Value = ''
    )

    $AccentLabel = Format-ToolMessage -Kind Accent -Message $Label
    if ([string]::IsNullOrEmpty($Value)) {
        Write-ToolDisplay $AccentLabel
        return
    }

    Write-ToolDisplay "$AccentLabel $Value"
}

function Write-ToolMetadata {
    param([string]$Message)
    return Format-ToolMessage -Kind Accent -Message $Message
}

function Format-ToolInput {
    param(
        [AllowEmptyString()]
        [string]$Value = ''
    )

    return [regex]::Replace($Value, '[^\\x20-\\x7E]', '?')
}

function Get-SelectionRange {
    param([int]$Count)

    if ($Count -le 1) {
        return '1'
    }

    return "1-$Count"
}

function Write-InvalidSelection {
    param(
        [AllowEmptyString()]
        [string]$Selection = '',
        [string]$Choices
    )

    Write-ToolDisplay
    if ([string]::IsNullOrWhiteSpace($Selection)) {
        Write-ToolWarning "A selection is required. $Choices"
        return
    }

    $SafeSelection = Format-ToolInput $Selection.Trim()
    Write-ToolWarning "Invalid selection: $SafeSelection. $Choices"
}

function Write-ToolHeading {
'''
ps = replace_once(ps, old, new, 'PowerShell helper insertion')

ps = replace_once(
    ps,
    '    Write-ToolInfo "Installing tool to $ToolPath"',
    '    Write-ToolDisplay\n    Write-ToolInfo "Installing tool to $ToolPath"',
    'PowerShell bootstrap leading spacing')
ps = replace_once(
    ps,
    "    Write-ToolSuccess 'Tool installed.'\n\n    $Arguments = @{}",
    "    Write-ToolSuccess 'Tool installed.'\n    Write-ToolDisplay\n\n    $Arguments = @{}",
    'PowerShell bootstrap trailing spacing')

ps = replace_once(
    ps,
    "            default { Write-ToolWarning 'Please choose 1, 2, 3, or E.' }",
    "            default {\n                Write-InvalidSelection -Selection $Selection -Choices 'Choose 1, 2, 3, or E.'\n                Write-ToolDisplay\n            }",
    'PowerShell Main invalid selection')

old = '''        $Number = 0
        if (-not [int]::TryParse($Selection, [ref]$Number) -or
            $Number -lt 1 -or
            $Number -gt $Channels.Count) {
            Write-ToolWarning 'Invalid selection.'
            continue
        }
'''
new = '''        $Number = 0
        if (-not [int]::TryParse($Selection, [ref]$Number) -or
            $Number -lt 1 -or
            $Number -gt $Channels.Count) {
            $SelectionRange = Get-SelectionRange -Count $Channels.Count
            $Choices = if ($script:InteractiveSession) {
                "Choose $SelectionRange, S, B, M, or E."
            }
            else {
                "Choose $SelectionRange, S, M, or Q."
            }
            Write-InvalidSelection -Selection $Selection -Choices $Choices
            continue
        }
'''
ps = replace_once(ps, old, new, 'PowerShell channel invalid selection')

old = '''                if ($Markers.Count -gt 0) {
                    Write-ToolDisplay ("  {0}. {1} ({2})" -f ($Index + 1), $SdkVersion, ($Markers -join ', '))
                }
'''
new = '''                if ($Markers.Count -gt 0) {
                    $Metadata = Write-ToolMetadata -Message ("({0})" -f ($Markers -join ', '))
                    Write-ToolDisplay ("  {0}. {1} {2}" -f ($Index + 1), $SdkVersion, $Metadata)
                }
'''
ps = replace_once(ps, old, new, 'PowerShell picker metadata')

old = '''            Write-ToolWarning 'Invalid selection.'
        done
'''
# Bash-only sentinel; do not apply to PowerShell.

old = '''            Write-ToolWarning 'Invalid selection.'
        }
    }
}

function Select-RemoveVersion'''
new = '''            $SelectionRange = Get-SelectionRange -Count $SdkVersions.Count
            $HasViewToggle = $FeaturedSdkVersions.Count -lt $AllSdkVersions.Count
            if ($script:InteractiveSession) {
                $Choices = if ($HasViewToggle) {
                    "Choose $SelectionRange, S, B, M, or E."
                }
                else {
                    "Choose $SelectionRange, B, M, or E."
                }
            }
            else {
                $Choices = if ($HasViewToggle) {
                    "Choose $SelectionRange, S, B, M, or Q."
                }
                else {
                    "Choose $SelectionRange, B, M, or Q."
                }
            }
            Write-InvalidSelection -Selection $Selection -Choices $Choices
        }
    }
}

function Select-RemoveVersion'''
ps = replace_once(ps, old, new, 'PowerShell SDK invalid selection')

old = '''        Write-ToolWarning 'Invalid selection.'
    }
}

function Resolve-InstallVersion'''
new = '''        $SelectionRange = Get-SelectionRange -Count $SdkVersions.Count
        $Choices = if ($script:InteractiveSession) {
            "Choose $SelectionRange, B, or E."
        }
        else {
            "Choose $SelectionRange or Q."
        }
        Write-InvalidSelection -Selection $Selection -Choices $Choices
        Write-ToolDisplay
    }
}

function Resolve-InstallVersion'''
ps = replace_once(ps, old, new, 'PowerShell Remove invalid selection')

label_replacements = {
    '    Write-ToolInfo "Target SDK: $Version"': "    Write-ToolLabelValue -Label 'Target SDK:' -Value $Version",
    '    Write-ToolInfo "Isolated install directory: $InstallDir"': "    Write-ToolLabelValue -Label 'Isolated install directory:' -Value $InstallDir",
    "        Write-ToolInfo 'System SDK: Already installed'": "        Write-ToolLabelValue -Label 'System SDK:' -Value 'Already installed'",
    "        Write-ToolInfo 'System SDK: Not installed'": "        Write-ToolLabelValue -Label 'System SDK:' -Value 'Not installed'",
    "        Write-ToolInfo 'Isolated SDK: Already installed'": "        Write-ToolLabelValue -Label 'Isolated SDK:' -Value 'Already installed'",
    "        Write-ToolInfo 'Isolated SDK: Not installed'": "        Write-ToolLabelValue -Label 'Isolated SDK:' -Value 'Not installed'",
}
for old, new in label_replacements.items():
    ps = replace_once(ps, old, new, f'PowerShell label: {old.strip()}')

# There are four user-facing Location label/value lines in install/verify paths.
ps = ps.replace('            Write-ToolInfo "Location: $($SystemSdk.Path)"', "            Write-ToolLabelValue -Label 'Location:' -Value $SystemSdk.Path")
ps = ps.replace('        Write-ToolInfo "Location: $InstallDir"', "        Write-ToolLabelValue -Label 'Location:' -Value $InstallDir")
ps = ps.replace('    Write-ToolInfo "Location: $InstallDir"', "    Write-ToolLabelValue -Label 'Location:' -Value $InstallDir")

ps_path.write_text(ps)


# Bash implementation.
bash_path = Path('isolated-dotnet-sdk.sh')
bash = bash_path.read_text()
old = '''if [[ -t 1 ]]; then
    CYAN='\\033[0;36m'
    YELLOW='\\033[0;33m'
    GREEN='\\033[0;32m'
    RESET='\\033[0m'
else
    CYAN=''
    YELLOW=''
    GREEN=''
    RESET=''
fi
'''
new = '''if [[ -t 1 ]]; then
    CYAN='\\033[0;36m'
    YELLOW='\\033[0;33m'
    GREEN='\\033[0;32m'
    RESET='\\033[0m'
else
    CYAN=''
    YELLOW=''
    GREEN=''
    RESET=''
fi

if [[ -t 2 ]]; then
    RED='\\033[0;31m'
    ERROR_RESET='\\033[0m'
else
    RED=''
    ERROR_RESET=''
fi
'''
bash = replace_once(bash, old, new, 'Bash stderr color state')

old = '''tool_info() {
    printf "%s\\n" "$1"
}

tool_heading() {
'''
new = '''tool_info() {
    printf "%s\\n" "$1"
}

tool_label_value() {
    local label="$1"
    local value="$2"
    printf "%b%s%b %s\\n" "$CYAN" "$label" "$RESET" "$value"
}

tool_metadata() {
    printf "%b%s%b" "$CYAN" "$1" "$RESET"
}

format_tool_input() {
    local value="$1"
    printf '%s' "$value" | LC_ALL=C tr -c '[:print:]' '?'
}

selection_range() {
    local count="$1"
    if (( count <= 1 )); then
        printf '%s' '1'
    else
        printf '1-%d' "$count"
    fi
}

warn_invalid_selection() {
    local selection="$1"
    local choices="$2"
    local safe_selection=""

    echo
    if [[ "$selection" =~ ^[[:space:]]*$ ]]; then
        tool_warn "A selection is required. $choices"
        return
    fi

    safe_selection="$(format_tool_input "$selection")"
    tool_warn "Invalid selection: $safe_selection. $choices"
}

tool_heading() {
'''
bash = replace_once(bash, old, new, 'Bash presentation helper insertion')
bash = replace_once(
    bash,
    '''tool_fail() {
    printf "%s\\n" "$1" >&2
    exit 1
}
''',
    '''tool_fail() {
    printf "%b%s%b\\n" "$RED" "$1" "$ERROR_RESET" >&2
    exit 1
}
''',
    'Bash error role')

bash = replace_once(
    bash,
    '    tool_info "Installing tool to $TOOL_PATH"',
    '    echo\n    tool_info "Installing tool to $TOOL_PATH"',
    'Bash bootstrap leading spacing')
bash = replace_once(
    bash,
    '    tool_success "Tool installed."\n\n    if tty -s </dev/tty 2>/dev/null; then',
    '    tool_success "Tool installed."\n    echo\n\n    if tty -s </dev/tty 2>/dev/null; then',
    'Bash bootstrap trailing spacing')

bash = replace_once(
    bash,
    '            *) tool_warn "Please choose 1, 2, 3, or E." ;;',
    '''            *)
                warn_invalid_selection "$selection" "Choose 1, 2, 3, or E."
                echo
                ;;''',
    'Bash Main invalid selection')

bash = replace_once(
    bash,
    '''        else
            tool_warn "Invalid selection."
            continue
        fi

        metadata_file=''',
    '''        else
            local channel_range
            local channel_choices
            channel_range="$(selection_range "${#channels[@]}")"
            if [[ "$INTERACTIVE_SESSION" == "true" ]]; then
                channel_choices="Choose $channel_range, S, B, M, or E."
            else
                channel_choices="Choose $channel_range, S, M, or Q."
            fi
            warn_invalid_selection "$selection" "$channel_choices"
            continue
        fi

        metadata_file=''',
    'Bash channel invalid selection')

bash = replace_once(
    bash,
    '''                if [[ -n "$markers" ]]; then
                    printf "  %d. %s (%s)\\n" "$((i + 1))" "$line" "$markers"
                else
''',
    '''                if [[ -n "$markers" ]]; then
                    printf "  %d. %s %s\\n" "$((i + 1))" "$line" "$(tool_metadata "($markers)")"
                else
''',
    'Bash picker metadata')

bash = replace_once(
    bash,
    '''            tool_warn "Invalid selection."
        done
    done
}

select_remove_version()''',
    '''            local sdk_range
            local sdk_choices
            sdk_range="$(selection_range "${#sdk_versions[@]}")"
            if [[ "$INTERACTIVE_SESSION" == "true" ]]; then
                if [[ "$compact_versions" != "$all_versions" ]]; then
                    sdk_choices="Choose $sdk_range, S, B, M, or E."
                else
                    sdk_choices="Choose $sdk_range, B, M, or E."
                fi
            else
                if [[ "$compact_versions" != "$all_versions" ]]; then
                    sdk_choices="Choose $sdk_range, S, B, M, or Q."
                else
                    sdk_choices="Choose $sdk_range, B, M, or Q."
                fi
            fi
            warn_invalid_selection "$selection" "$sdk_choices"
        done
    done
}

select_remove_version()''',
    'Bash SDK invalid selection')

bash = replace_once(
    bash,
    '''        tool_warn "Invalid selection."
    done
}

resolve_install_version()''',
    '''        local remove_range
        local remove_choices
        remove_range="$(selection_range "${#sdk_versions[@]}")"
        if [[ "$INTERACTIVE_SESSION" == "true" ]]; then
            remove_choices="Choose $remove_range, B, or E."
        else
            remove_choices="Choose $remove_range or Q."
        fi
        warn_invalid_selection "$selection" "$remove_choices"
        echo
    done
}

resolve_install_version()''',
    'Bash Remove invalid selection')

bash_label_replacements = {
    '    tool_info "Target SDK: $VERSION"': '    tool_label_value "Target SDK:" "$VERSION"',
    '    tool_info "Isolated install directory: $install_dir"': '    tool_label_value "Isolated install directory:" "$install_dir"',
    '        tool_info "System SDK: Already installed"': '        tool_label_value "System SDK:" "Already installed"',
    '        tool_info "System SDK: Not installed"': '        tool_label_value "System SDK:" "Not installed"',
    '        tool_info "Isolated SDK: Already installed"': '        tool_label_value "Isolated SDK:" "Already installed"',
    '        tool_info "Isolated SDK: Not installed"': '        tool_label_value "Isolated SDK:" "Not installed"',
}
for old, new in bash_label_replacements.items():
    bash = replace_once(bash, old, new, f'Bash label: {old.strip()}')

bash = bash.replace('            tool_info "Location: $system_sdk_path"', '            tool_label_value "Location:" "$system_sdk_path"')
bash = bash.replace('        tool_info "Location: $install_dir"', '        tool_label_value "Location:" "$install_dir"')
bash = bash.replace('    tool_info "Location: $install_dir"', '    tool_label_value "Location:" "$install_dir"')

bash_path.write_text(bash)


# Reconcile source-oriented presentation tests with the new explicit label role.
bash_test = Path('tests/bash/presentation.bats')
text = bash_test.read_text().replace(
    '  grep -Fq \'tool_info "Target SDK: $VERSION"\' "$repo_root/isolated-dotnet-sdk.sh"',
    '  grep -Fq \'tool_label_value "Target SDK:" "$VERSION"\' "$repo_root/isolated-dotnet-sdk.sh"')
# Add safe invalid-input representation coverage.
text += r'''

@test "invalid input formatting replaces terminal control characters" {
  source "$repo_root/isolated-dotnet-sdk.sh" --help >/dev/null 2>&1 || true
  result="$(format_tool_input $'x\t')"
  [ "$result" = 'x?' ]
}
'''
bash_test.write_text(text)

ps_test = Path('tests/powershell/presentation.Tests.ps1')
text = ps_test.read_text()
insert = r'''

    It 'replaces terminal control characters in invalid-input feedback values' {
        $source = Get-Content -LiteralPath $script:SourceCopy -Raw
        $source | Should -Match "\[regex\]::Replace\(\$Value, '\[\^\\x20-\\x7E\]', '\?'\)"
    }
'''
text = text.rsplit('\n}', 1)[0] + insert + '\n}\n'
ps_test.write_text(text)

# Refine documented presentation contract.
doc_path = Path('docs/static-analysis.md')
doc = doc_path.read_text()
old = '''Presentation color is selected by explicit semantic role at the call site rather than inferred from punctuation. Interactive/menu and section headings use a restrained cyan accent, success messages use green, and ordinary informational text, values, choices, and paths remain neutral. PowerShell warning and error colors remain owned by their semantic streams; Bash warnings retain their warning presentation while failures stay on stderr. `PlainText`/`NO_COLOR` PowerShell execution is not decorated, and redirected/captured output from both implementations must not contain ANSI escape sequences.'''
new = '''Presentation color is selected by explicit semantic role at the call site rather than inferred from punctuation. Interactive/menu and section headings, short structural labels, and SDK-picker metadata use the same restrained cyan accent while their associated values remain neutral. Completed-success messages use green; ordinary informational/progress text, values, choices, shortcut keys, versions, and paths remain neutral. PowerShell warning and error colors remain owned by their semantic streams. Bash warnings retain their yellow warning presentation, while failures remain on stderr and use red only when stderr is attached to a terminal. `PlainText`/`NO_COLOR` PowerShell execution is not decorated, and redirected/captured output from both implementations must not contain ANSI escape sequences. Interactive retry flows, rather than generic warning helpers, own the blank-line separation around recoverable validation feedback.'''
doc = replace_once(doc, old, new, 'presentation documentation')
doc_path.write_text(doc)
