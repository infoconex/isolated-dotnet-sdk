from pathlib import Path
import re

root = Path('.')


def read(path: Path) -> str:
    return path.read_text(encoding='utf-8')


def write(path: Path, text: str) -> None:
    path.write_text(text, encoding='utf-8', newline='\n')


def require(text: str, needle: str, path: Path) -> None:
    if needle not in text:
        raise SystemExit(f"Expected pattern not found in {path}: {needle!r}")


# PowerShell: -Version identifies the tool; -SdkVersion selects an SDK and is
# the only positional parameter.
ps = root / 'isolated-dotnet-sdk.ps1'
text = read(ps)
require(text, '[string]$Version,', ps)
require(text, '[switch]$ToolVersion', ps)
require(text, 'if ($ToolVersion) {', ps)

text = text.replace('When Action and Version are both omitted', 'When Action and SdkVersion are both omitted')
text = text.replace('When Action is omitted and Version is supplied', 'When Action is omitted and SdkVersion is supplied')
text = text.replace('Explicit List with Version is invalid.', 'Explicit List with SdkVersion is invalid.')
text = text.replace('Verify requires an exact Version', 'Verify requires an exact SdkVersion')
text = text.replace('unless Version is supplied, in which case Install is selected.', 'unless SdkVersion is supplied, in which case Install is selected.')
text = text.replace(
    '.PARAMETER Version\nSpecifies an exact .NET SDK version. When omitted for Install or Remove, the script provides an interactive version selection workflow. Verify requires Version. Version is invalid with an explicit List action.',
    '.PARAMETER SdkVersion\nSpecifies an exact .NET SDK version. When omitted for Install or Remove, the script provides an interactive version selection workflow. Verify requires SdkVersion. SdkVersion is invalid with an explicit List action. The parameter is positional, so a bare exact SDK version has the same meaning as -SdkVersion.'
)
text = text.replace(
    '.PARAMETER ToolVersion\nShows the isolated-dotnet-sdk release/source identity and exits without bootstrap, network access, SDK discovery, prompting, or mutation. This is distinct from Version, which remains the .NET SDK selector.',
    '.PARAMETER Version\nShows the isolated-dotnet-sdk release/source identity and exits without bootstrap, network access, SDK discovery, prompting, or mutation. This is distinct from SdkVersion, which selects the .NET SDK to install, verify, or remove.'
)

# All existing -Version spellings are SDK-selector uses at this point.
text = text.replace('-Version', '-SdkVersion')
text = text.replace('-ToolVersion', '-Version')
text = text.replace('$script:VersionWasSpecified', '$script:SdkVersionWasSpecified')
text = text.replace('$script:Version', '$script:SdkVersion')
text = re.sub(r'(?<![A-Za-z0-9_:])\$Version\b', '$SdkVersion', text)
text = text.replace("$PSBoundParameters.ContainsKey('Version')", "$PSBoundParameters.ContainsKey('SdkVersion')")
text = text.replace('$Arguments.Version = $SdkVersion', '$Arguments.SdkVersion = $SdkVersion')
text = text.replace('Assert-ValidVersion', 'Assert-ValidSdkVersion')

old_param = """[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [string]$Action,
    [string]$SdkVersion,
    [switch]$Yes,
    [switch]$ToolVersion
)"""
new_param = """[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', PositionalBinding = $false)]
param(
    [string]$Action,
    [Parameter(Position = 0)]
    [string]$SdkVersion,
    [switch]$Yes,
    [switch]$Version
)"""
require(text, old_param, ps)
text = text.replace(old_param, new_param, 1)
text = text.replace('$ToolVersion', '$Version')
write(ps, text)

# PowerShell tests and real E2E use -SdkVersion for SDK selection and -Version
# for tool identity.
powershell_test_paths = list((root / 'tests' / 'powershell').glob('*.ps1'))
powershell_test_paths += list((root / 'tests' / 'e2e' / 'powershell').glob('*.ps1'))
for path in powershell_test_paths:
    value = read(path)
    value = value.replace('-Version', '-SdkVersion')
    value = value.replace('-ToolVersion', '-Version')
    write(path, value)

tool_tests = root / 'tests' / 'powershell' / 'tool-version.Tests.ps1'
value = read(tool_tests)
value = value.replace(
    "It 'preserves -SdkVersion as the SDK selector'",
    "It 'supports -SdkVersion as the explicit SDK selector'"
)
marker = "    It 'stamps both product scripts from one stable tag' {"
require(value, marker, tool_tests)
positional_tests = r'''    It 'supports a positional SDK version with the same semantics' {
        $toolRoot = Join-Path $script:TestHome 'dotnet-sdks'
        $savedTool = Join-Path $toolRoot 'isolated-dotnet-sdk.ps1'
        New-Item -ItemType Directory -Path $toolRoot -Force | Out-Null
        Copy-Item -LiteralPath $script:ToolScript -Destination $savedTool -Force

        $result = Invoke-ToolProcess `
            -ToolPath $savedTool `
            -Arguments @('bad/version') `
            -HomePath $script:TestHome

        $result.ExitCode | Should -Not -Be 0
        $result.Output | Should -Match 'Invalid SDK version: bad/version'
        $result.Output | Should -Not -Match 'isolated-dotnet-sdk development \(main\)'
    }

    It 'rejects combining the tool version query with an SDK selector without bootstrapping' {
        $result = Invoke-ToolProcess `
            -ToolPath $script:ToolScript `
            -Arguments @('-Version', '-SdkVersion', '10.0.100') `
            -HomePath $script:TestHome

        $result.ExitCode | Should -Not -Be 0
        $result.Output | Should -Match '-Version cannot be combined'
        Test-Path -LiteralPath (Join-Path $script:TestHome 'dotnet-sdks') | Should -BeFalse
    }

'''
value = value.replace(marker, positional_tests + marker, 1)
write(tool_tests, value)

# Bash: --version identifies the tool; --sdk-version explicitly selects an SDK;
# the same SDK can still be supplied positionally.
sh = root / 'isolated-dotnet-sdk.sh'
bash = read(sh)
require(bash, '  isolated-dotnet-sdk.sh --version', sh)
require(bash, 'if [[ "${1:-}" == "--version" ]]; then', sh)

bash = bash.replace(
    '  isolated-dotnet-sdk.sh [version] [--yes|-y]\n  isolated-dotnet-sdk.sh --version',
    '  isolated-dotnet-sdk.sh --sdk-version <version> [--yes|-y]\n  isolated-dotnet-sdk.sh [version] [--yes|-y]\n  isolated-dotnet-sdk.sh --version'
)
bash = bash.replace(
    '  --yes, -y          Skip supported confirmation prompts. It does not choose a missing action or version.\n  --version          Show the tool release/source identity and exit.',
    '  --yes, -y          Skip supported confirmation prompts. It does not choose a missing action or version.\n  --sdk-version <v>  Select the exact .NET SDK version. Without an action, Install is selected.\n  --version          Show the tool release/source identity and exit.'
)
bash = bash.replace(
    '  Bare version       Treat the version as a one-shot install request.',
    '  SDK version        --sdk-version <version> and a bare positional version select the same exact SDK.\n  Bare version       Treat the positional version as a one-shot install request.'
)

old_guard = '''if [[ "${1:-}" == "--version" ]]; then
    if [[ $# -ne 1 ]]; then
        printf '%s\\n' '--version cannot be combined with other arguments.' >&2
        exit 1
    fi
    tool_version_text
    printf '\\n'
    exit 0
fi

bootstrap_if_needed "$@"'''
new_guard = '''for argument in "$@"; do
    if [[ "$argument" == "--version" ]]; then
        if [[ $# -ne 1 ]]; then
            printf '%s\\n' '--version cannot be combined with other arguments.' >&2
            exit 1
        fi
        tool_version_text
        printf '\\n'
        exit 0
    fi
done

bootstrap_if_needed "$@"'''
require(bash, old_guard, sh)
bash = bash.replace(old_guard, new_guard, 1)

old_parser = '''ACTION=""
VERSION=""
YES="false"
INTERACTIVE_SESSION="false"
EXIT_REQUESTED="false"

if [[ $# -gt 0 ]]; then
    case "$1" in
        install|remove|list|verify)
            ACTION="$1"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --yes|-y)
            ;;
        *)
            ACTION="install"
            VERSION="$1"
            shift
            ;;
    esac
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        --yes|-y)
            YES="true"
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            if [[ "$ACTION" != "list" && -z "$VERSION" ]]; then
                VERSION="$1"
            else
                tool_fail "Unknown argument: $1"
            fi
            ;;
    esac
    shift
done

if [[ -z "$ACTION" && -z "$VERSION" ]]; then
    INTERACTIVE_SESSION="true"
fi'''
new_parser = '''ACTION=""
VERSION=""
YES="false"
INTERACTIVE_SESSION="false"
EXIT_REQUESTED="false"

while [[ $# -gt 0 ]]; do
    case "$1" in
        install|remove|list|verify)
            if [[ -n "$ACTION" ]]; then
                tool_fail "Only one action may be specified."
            fi
            ACTION="$1"
            ;;
        --sdk-version)
            shift
            if [[ $# -eq 0 ]]; then
                tool_fail "--sdk-version requires an exact SDK version."
            fi
            if [[ -n "$VERSION" ]]; then
                tool_fail "Only one SDK version may be specified."
            fi
            VERSION="$1"
            ;;
        --yes|-y)
            YES="true"
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --version)
            tool_fail "--version cannot be combined with other arguments."
            ;;
        --*)
            tool_fail "Unknown argument: $1"
            ;;
        *)
            if [[ -n "$VERSION" ]]; then
                tool_fail "Only one SDK version may be specified."
            fi
            VERSION="$1"
            ;;
    esac
    shift
done

if [[ "$ACTION" == "list" && -n "$VERSION" ]]; then
    tool_fail "An SDK version cannot be combined with list."
fi

if [[ -z "$ACTION" && -n "$VERSION" ]]; then
    ACTION="install"
fi

if [[ -z "$ACTION" && -z "$VERSION" ]]; then
    INTERACTIVE_SESSION="true"
fi'''
require(bash, old_parser, sh)
bash = bash.replace(old_parser, new_parser, 1)
write(sh, bash)

bash_tests = root / 'tests' / 'bash' / 'tool-version.bats'
value = read(bash_tests)
marker = '@test "bare SDK version remains an install selector" {'
require(value, marker, bash_tests)
extra_tests = r'''@test "--sdk-version explicitly selects the SDK with the same semantics" {
  tool_root="$test_home/dotnet-sdks"
  saved_tool="$tool_root/isolated-dotnet-sdk.sh"
  mkdir -p "$tool_root"
  cp "$tool" "$saved_tool"
  chmod +x "$saved_tool"

  run env HOME="$test_home" "$saved_tool" --sdk-version 'bad/version'

  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid SDK version: bad/version"* ]]
  [[ "$output" != *"isolated-dotnet-sdk development (main)"* ]]
}

@test "--version cannot be combined with an SDK selector and remains side-effect free" {
  run env HOME="$test_home" "$bash_path" "$tool" --version --sdk-version 10.0.100

  [ "$status" -ne 0 ]
  [[ "$output" == *"--version cannot be combined with other arguments."* ]]
  [ ! -e "$test_home/dotnet-sdks" ]
}

'''
value = value.replace(marker, extra_tests + marker, 1)
write(bash_tests, value)

# Release verification uses the canonical PowerShell tool-version switch.
for path in list((root / '.github').rglob('*.yml')) + list((root / '.github').rglob('*.yaml')) + list((root / '.github').rglob('*.js')):
    value = read(path)
    value = value.replace('-ToolVersion', '-Version')
    write(path, value)

print('Issue #114 CLI contract migration applied successfully.')
