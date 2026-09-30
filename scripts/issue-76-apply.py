from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file_path = Path(path)
    text = file_path.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected one match, found {count}: {old[:100]!r}")
    file_path.write_text(text.replace(old, new, 1), encoding="utf-8")


# PowerShell public contract and help.
replace_once(
    "isolated-dotnet-sdk.ps1",
    "Supported product actions are Install, Remove, and List.",
    "Supported product actions are Install, Remove, List, and Verify.",
)
replace_once(
    "isolated-dotnet-sdk.ps1",
    "Explicit actions and exact-version requests remain one-shot. Explicit List with Version is invalid. Install or Remove without a resolved version may require interactive selection.",
    "Explicit actions and exact-version requests remain one-shot. Explicit List with Version is invalid. Verify requires an exact Version and remains direct-command-only; it does not appear on the persistent Main menu. Install or Remove without a resolved version may require interactive selection.",
)
replace_once(
    "isolated-dotnet-sdk.ps1",
    "Specifies the operation to perform: Install, Remove, or List. When omitted, the script starts the persistent interactive session unless Version is supplied, in which case Install is selected.",
    "Specifies the operation to perform: Install, Remove, List, or Verify. When omitted, the script starts the persistent interactive session unless Version is supplied, in which case Install is selected.",
)
replace_once(
    "isolated-dotnet-sdk.ps1",
    "Specifies an exact .NET SDK version. When omitted for Install or Remove, the script provides an interactive version selection workflow. Version is invalid with an explicit List action.",
    "Specifies an exact .NET SDK version. When omitted for Install or Remove, the script provides an interactive version selection workflow. Verify requires Version. Version is invalid with an explicit List action.",
)
replace_once(
    "isolated-dotnet-sdk.ps1",
    ".EXAMPLE\n.\\isolated-dotnet-sdk.ps1 -Action Install -Version 10.0.100\n\nInstalls .NET SDK 10.0.100 in an isolated directory.\n\n.EXAMPLE\n.\\isolated-dotnet-sdk.ps1 -Action Remove -Version 10.0.100 -Yes",
    ".EXAMPLE\n.\\isolated-dotnet-sdk.ps1 -Action Install -Version 10.0.100\n\nInstalls .NET SDK 10.0.100 in an isolated directory.\n\n.EXAMPLE\n.\\isolated-dotnet-sdk.ps1 -Action Verify -Version 10.0.100\n\nVerifies that the existing isolated .NET SDK 10.0.100 has a launchable host that reports the requested exact version.\n\n.EXAMPLE\n.\\isolated-dotnet-sdk.ps1 -Action Remove -Version 10.0.100 -Yes",
)
replace_once(
    "isolated-dotnet-sdk.ps1",
    "if ($script:Action -notin @('Install', 'Remove', 'List')) {",
    "if ($script:Action -notin @('Install', 'Remove', 'List', 'Verify')) {",
)
replace_once(
    "isolated-dotnet-sdk.ps1",
    "function Assert-ActionParameterUsage {\n    if ($script:Action -eq 'List' -and $script:VersionWasSpecified) {\n        throw '-Version is supported only with -Action Install or Remove.'\n    }\n\n    if ($script:Action -eq 'Remove') {",
    "function Assert-ActionParameterUsage {\n    if ($script:Action -eq 'List' -and $script:VersionWasSpecified) {\n        throw '-Version is supported only with -Action Install, Remove, or Verify.'\n    }\n\n    if ($script:Action -eq 'Verify' -and [string]::IsNullOrWhiteSpace($script:Version)) {\n        throw '-Version is required with -Action Verify.'\n    }\n\n    if ($script:Action -eq 'Remove') {",
)

verify_ps = r'''function Verify-IsolatedSdk {
    if ([string]::IsNullOrWhiteSpace($script:Version)) {
        throw '-Version is required with -Action Verify.'
    }

    Assert-ValidVersion

    $InstallDir = Join-Path $SdkRoot $Version
    $IsolatedDotNet = Get-IsolatedDotNetPath -SdkVersion $Version

    if (-not (Test-Path -LiteralPath $InstallDir -PathType Container)) {
        throw "Isolated SDK $Version is not installed under $SdkRoot."
    }

    if (-not (Test-Path -LiteralPath $IsolatedDotNet -PathType Leaf)) {
        throw "Isolated SDK $Version is incomplete: expected dotnet host was not found at $IsolatedDotNet."
    }

    try {
        $IsolatedSdks = & $IsolatedDotNet --list-sdks
        $ExitCode = $LASTEXITCODE
    }
    catch {
        throw "Unable to launch isolated SDK $Version host at ${IsolatedDotNet}: $($_.Exception.Message)"
    }

    if ($ExitCode -ne 0) {
        throw "Unable to verify isolated SDK $Version with exit code $ExitCode."
    }

    $IsolatedVersions = @($IsolatedSdks | ForEach-Object { ($_ -split '\s+')[0] })
    if ($IsolatedVersions -notcontains $Version) {
        throw "Isolated SDK $Version failed verification: the host did not report SDK $Version."
    }

    Write-ToolSuccess "Isolated SDK $Version is healthy."
    Write-ToolInfo "Location: $InstallDir"
}

'''
replace_once(
    "isolated-dotnet-sdk.ps1",
    "function Invoke-IsolatedSdkBuildServerShutdown {",
    verify_ps + "function Invoke-IsolatedSdkBuildServerShutdown {",
)
replace_once(
    "isolated-dotnet-sdk.ps1",
    "        'List' { Show-IsolatedSdk }\n    }",
    "        'List' { Show-IsolatedSdk }\n        'Verify' { Verify-IsolatedSdk }\n    }",
)

# Bash verifier, dispatch, help, and parser.
verify_bash = r'''verify_isolated_sdk() {
    [[ -n "$VERSION" ]] || tool_fail "An exact SDK version is required with verify."
    validate_version

    local install_dir="$SDK_ROOT/$VERSION"
    local isolated_dotnet="$install_dir/dotnet"
    local isolated_sdks=""
    local status=0

    if [[ ! -d "$install_dir" ]]; then
        tool_fail "Isolated SDK $VERSION is not installed under $SDK_ROOT."
    fi

    if [[ ! -e "$isolated_dotnet" && ! -L "$isolated_dotnet" ]]; then
        tool_fail "Isolated SDK $VERSION is incomplete: expected dotnet host was not found at $isolated_dotnet."
    fi

    if [[ ! -x "$isolated_dotnet" ]]; then
        tool_fail "Isolated SDK $VERSION host is not executable: $isolated_dotnet"
    fi

    if isolated_sdks="$("$isolated_dotnet" --list-sdks)"; then
        :
    else
        status=$?
        tool_fail "Unable to verify isolated SDK $VERSION with exit code $status."
    fi

    if ! printf "%s\n" "$isolated_sdks" | awk '{print $1}' | grep -Fxq "$VERSION"; then
        tool_fail "Isolated SDK $VERSION failed verification: the host did not report SDK $VERSION."
    fi

    tool_success "Isolated SDK $VERSION is healthy."
    tool_info "Location: $install_dir"
}

'''
replace_once(
    "isolated-dotnet-sdk.sh",
    "remove_isolated_sdk() {",
    verify_bash + "remove_isolated_sdk() {",
)
replace_once(
    "isolated-dotnet-sdk.sh",
    "        list)\n            list_isolated_sdks\n            ;;",
    "        list)\n            list_isolated_sdks\n            ;;\n        verify)\n            verify_isolated_sdk\n            ;;",
)
replace_once(
    "isolated-dotnet-sdk.sh",
    "  isolated-dotnet-sdk.sh list\n  isolated-dotnet-sdk.sh [version] [--yes|-y]",
    "  isolated-dotnet-sdk.sh list\n  isolated-dotnet-sdk.sh verify <version>\n  isolated-dotnet-sdk.sh [version] [--yes|-y]",
)
replace_once(
    "isolated-dotnet-sdk.sh",
    "  list               List isolated SDKs under ~/dotnet-sdks. A version is invalid with list.",
    "  list               List isolated SDKs under ~/dotnet-sdks. A version is invalid with list.\n  verify <version>   Read-only health check for one exact installed isolated SDK.",
)
replace_once(
    "isolated-dotnet-sdk.sh",
    "  Explicit actions   Run once and exit without entering the persistent Main loop.\n  Exact-version installs bypass release-metadata discovery.",
    "  Explicit actions   Run once and exit without entering the persistent Main loop.\n  Verify <version>   Requires one exact version and checks only the existing isolated installation.\n  Exact-version installs bypass release-metadata discovery.",
)
replace_once(
    "isolated-dotnet-sdk.sh",
    "        install|remove|list)",
    "        install|remove|list|verify)",
)

# Existing boundary/help tests follow the expanded action set.
replace_once(
    "tests/powershell/behavior.Tests.ps1",
    "        ($failureOutput -join [Environment]::NewLine) | Should -Match 'Version.*supported only with.*Install or Remove'",
    "        ($failureOutput -join [Environment]::NewLine) | Should -Match 'Version.*supported only with.*Install, Remove, or Verify'",
)
replace_once(
    "tests/powershell/help.Tests.ps1",
    "        $script:HelpText | Should -Match 'Explicit List with Version is invalid'\n        $script:HelpText | Should -Match 'WhatIf and Confirm are supported only for Remove'",
    "        $script:HelpText | Should -Match 'Explicit List with Version is invalid'\n        $script:HelpText | Should -Match 'Verify requires an exact Version and remains direct-command-only'\n        $script:HelpText | Should -Match 'WhatIf and Confirm are supported only for Remove'",
)
replace_once(
    "tests/bash/help.bats",
    '  [[ "$output" == *"not added to PATH"* ]]\n  [[ "$output" == *"does not choose a missing action or version"* ]]',
    '  [[ "$output" == *"not added to PATH"* ]]\n  [[ "$output" == *"verify <version>"* ]]\n  [[ "$output" == *"Read-only health check for one exact installed isolated SDK."* ]]\n  [[ "$output" == *"does not choose a missing action or version"* ]]',
)

# Real direct E2E proves the public verifier against a real installed SDK.
replace_once(
    "tests/e2e/bash/direct.sh",
    '''if [[ "$actual_version" != "$sdk_version" ]]; then
  printf 'Expected isolated SDK version %s but dotnet reported %s.\\n' \\
    "$sdk_version" "$actual_version" >&2
  exit 1
fi

list_output="$(bash "$saved_tool" list)"''',
    '''if [[ "$actual_version" != "$sdk_version" ]]; then
  printf 'Expected isolated SDK version %s but dotnet reported %s.\\n' \\
    "$sdk_version" "$actual_version" >&2
  exit 1
fi

verify_output="$(bash "$saved_tool" verify "$sdk_version")"
printf '%s\\n' "$verify_output"
if ! grep -Fq "Isolated SDK $sdk_version is healthy." <<<"$verify_output"; then
  printf 'Verify output did not report SDK %s healthy.\\n' "$sdk_version" >&2
  exit 1
fi

list_output="$(bash "$saved_tool" list)"''',
)
replace_once(
    "tests/e2e/powershell/direct.ps1",
    '''    if ($actualVersion -ne $sdkVersion) {
        throw "Expected isolated SDK version $sdkVersion but dotnet reported $actualVersion."
    }

    $list = Invoke-E2EProcess `''',
    '''    if ($actualVersion -ne $sdkVersion) {
        throw "Expected isolated SDK version $sdkVersion but dotnet reported $actualVersion."
    }

    $verify = Invoke-E2EProcess `
        -FilePath 'pwsh' `
        -Arguments @('-NoProfile', '-File', $savedTool, '-Action', 'Verify', '-Version', $sdkVersion)
    Assert-Success -Result $verify -Operation 'Direct verify'
    Write-Host $verify.Output
    if ($verify.Output -notmatch [regex]::Escape("Isolated SDK $sdkVersion is healthy.")) {
        throw "Verify output did not report SDK $sdkVersion healthy."
    }

    $list = Invoke-E2EProcess `''',
)

# README documents the narrow direct-command-only health contract.
replace_once(
    "README.md",
    "Explicit Install, List, Remove, or exact-version invocations remain one-shot for automation and scripting.",
    "Explicit Install, List, Remove, Verify, or exact-version invocations remain one-shot for automation and scripting.",
)
verify_readme = r'''## Verify an Isolated SDK

`Verify` / `verify` is a direct-command-only, read-only health check for one exact installed isolated SDK. It is intentionally not on the persistent Main menu.

PowerShell:

```powershell
& "$HOME\dotnet-sdks\isolated-dotnet-sdk.ps1" `
    -Action Verify `
    -Version '10.0.401'
```

Bash:

```bash
"$HOME/dotnet-sdks/isolated-dotnet-sdk.sh" verify 10.0.401
```

A healthy result means the selected version directory exists, its platform-specific `dotnet` host is present and launchable/executable, `dotnet --list-sdks` succeeds, and that host reports the requested exact SDK version. Healthy verification returns zero. A missing installation or host, a non-runnable host, native host failure, or exact-version mismatch returns nonzero with operation-specific context.

Verification does not repair, reinstall, upgrade, delete, or otherwise mutate the isolated SDK. It does not change the normal `PATH` or system `dotnet` installation, does not re-hash every installed SDK file, and does not check or update helper/tool freshness in this initial contract.

'''
replace_once(
    "README.md",
    "## Use an Isolated SDK\n",
    verify_readme + "## Use an Isolated SDK\n",
)

# Shared vocabulary and parity documentation.
replace_once(
    "docs/coding-consistency.md",
    "The stable product actions are install, remove, and list.\n\n- PowerShell exposes them through `-Action Install`, `-Action Remove`, and `-Action List`.\n- Bash exposes the corresponding lowercase `install`, `remove`, and `list` subcommands.",
    "The stable product actions are install, remove, list, and verify.\n\n- PowerShell exposes them through `-Action Install`, `-Action Remove`, `-Action List`, and `-Action Verify`.\n- Bash exposes the corresponding lowercase `install`, `remove`, `list`, and `verify` subcommands.",
)
replace_once(
    "docs/coding-consistency.md",
    "- `remove_isolated_sdk` for the isolated-SDK remove operation.",
    "- `remove_isolated_sdk` for the isolated-SDK remove operation;\n- `verify_isolated_sdk` for the read-only exact-version health check.",
)
replace_once(
    "docs/behavioral-parity.md",
    "| Explicit List plus Version | Reject the version instead of silently ignoring it. |\n| Remove without a version |",
    "| Explicit List plus Version | Reject the version instead of silently ignoring it. |\n| Verify with an exact version | Run a direct-command-only, read-only health check against that version directory under the isolated SDK root. Require the platform host to be present/runnable, require `--list-sdks` to succeed, and require the host to report the requested exact SDK version. |\n| Unhealthy Verify result | Return nonzero with repository-owned context for not-installed, missing/non-runnable host, native host failure, or exact-version mismatch. Verification never repairs or mutates the installation. |\n| Remove without a version |",
)
replace_once(
    "docs/behavioral-parity.md",
    "Automation should provide both the action and exact version when a version is required. `-Yes` and `--yes` are confirmation controls, not selection controls.",
    "Automation should provide both the action and exact version when a version is required. `Verify <exact-version>` / `verify <exact-version>` is always one-shot and never enters the persistent Main menu. `-Yes` and `--yes` are confirmation controls, not selection controls.",
)

# Verify adds a correctness-significant host-execution boundary.
replace_once(
    "docs/native-command-failures.md",
    "| Post-extraction isolated host `--list-sdks` | Check `$LASTEXITCODE` | Capture the command status explicitly | Report host-command failure separately from a successful inventory that omits the requested SDK |\n| Removal build-server shutdown |",
    "| Post-extraction isolated host `--list-sdks` | Check `$LASTEXITCODE` | Capture the command status explicitly | Report host-command failure separately from a successful inventory that omits the requested SDK |\n| Standalone Verify isolated host `--list-sdks` | Catch host-launch failure and check `$LASTEXITCODE` | Require the host to be executable and capture command status explicitly | Fail nonzero without mutation when the host cannot run, exits nonzero, or succeeds without reporting the requested exact SDK |\n| Removal build-server shutdown |",
)
replace_once(
    "docs/native-command-failures.md",
    "Keeping those cases separate prevents a corrupt/mismatched archive from reaching extraction and prevents a broken staged host process from being misreported as a valid inventory that simply lacks the requested SDK.",
    "Keeping those cases separate prevents a corrupt/mismatched archive from reaching extraction and prevents a broken staged host process from being misreported as a valid inventory that simply lacks the requested SDK. Standalone Verify reuses the host-inventory proof for an already-installed exact version, but it is diagnostic only: it does not repair, reacquire, promote, delete, or update anything.",
)
replace_once(
    "docs/e2e-testing.md",
    "3. execute that isolated SDK and require its reported version to equal the configured version;\n4. list isolated SDKs and require the configured version to appear;\n5. remove the configured SDK;\n6. require the isolated SDK directory to be absent afterward.",
    "3. execute that isolated SDK and require its reported version to equal the configured version;\n4. run the public standalone Verify action and require a healthy result;\n5. list isolated SDKs and require the configured version to appear;\n6. remove the configured SDK;\n7. require the isolated SDK directory to be absent afterward.",
)
