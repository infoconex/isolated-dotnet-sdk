from pathlib import Path


def replace_once(path, old, new):
    p = Path(path)
    text = p.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"expected exactly one match in {path}, found {count}: {old!r}")
    p.write_text(text.replace(old, new, 1))


def replace_all(path, old, new, minimum=1):
    p = Path(path)
    text = p.read_text()
    count = text.count(old)
    if count < minimum:
        raise SystemExit(f"expected at least {minimum} matches in {path}, found {count}: {old!r}")
    p.write_text(text.replace(old, new))

# Product menus and accepted Main commands.
replace_once('isolated-dotnet-sdk.ps1', "        Write-ToolDisplay '  1. Install an SDK'", "        Write-ToolDisplay '  I. Install an SDK'")
replace_once('isolated-dotnet-sdk.ps1', "        Write-ToolDisplay '  2. Remove an isolated SDK'", "        Write-ToolDisplay '  R. Remove an isolated SDK'")
replace_once('isolated-dotnet-sdk.ps1', "        Write-ToolDisplay '  3. List installed SDKs'", "        Write-ToolDisplay '  L. List installed SDKs'")
replace_once('isolated-dotnet-sdk.ps1', "            '1' { $script:Action = 'Install'; return $true }", "            'i' { $script:Action = 'Install'; return $true }\n            'I' { $script:Action = 'Install'; return $true }")
replace_once('isolated-dotnet-sdk.ps1', "            '2' { $script:Action = 'Remove'; return $true }", "            'r' { $script:Action = 'Remove'; return $true }\n            'R' { $script:Action = 'Remove'; return $true }")
replace_once('isolated-dotnet-sdk.ps1', "            '3' { $script:Action = 'List'; return $true }", "            'l' { $script:Action = 'List'; return $true }\n            'L' { $script:Action = 'List'; return $true }")
replace_all('isolated-dotnet-sdk.ps1', 'Choose 1, 2, 3, or E.', 'Choose I, R, L, or E.')

replace_once('isolated-dotnet-sdk.sh', '        echo "  1. Install an SDK"', '        echo "  I. Install an SDK"')
replace_once('isolated-dotnet-sdk.sh', '        echo "  2. Remove an isolated SDK"', '        echo "  R. Remove an isolated SDK"')
replace_once('isolated-dotnet-sdk.sh', '        echo "  3. List installed SDKs"', '        echo "  L. List installed SDKs"')
replace_once('isolated-dotnet-sdk.sh', '            1) ACTION="install"; return 0 ;;', '            i|I) ACTION="install"; return 0 ;;')
replace_once('isolated-dotnet-sdk.sh', '            2) ACTION="remove"; return 0 ;;', '            r|R) ACTION="remove"; return 0 ;;')
replace_once('isolated-dotnet-sdk.sh', '            3) ACTION="list"; return 0 ;;', '            l|L) ACTION="list"; return 0 ;;')
replace_all('isolated-dotnet-sdk.sh', 'Choose 1, 2, 3, or E.', 'Choose I, R, L, or E.')

# Current README menu example.
for old, new in [
    ('  1. Install an SDK', '  I. Install an SDK'),
    ('  2. Remove an isolated SDK', '  R. Remove an isolated SDK'),
    ('  3. List installed SDKs', '  L. List installed SDKs'),
]:
    replace_once('README.md', old, new)

# PowerShell global-exit coverage: reject all former numeric Main aliases and use mnemonics elsewhere.
path = 'tests/powershell/global-exit.Tests.ps1'
replace_once(path, "It 'advertises E Exit at Main and rejects numeric 4 as an Exit alias'", "It 'advertises mnemonic Main commands and rejects numeric aliases'")
replace_once(path, "-InputLines @('4', 'e')", "-InputLines @('1', '2', '3', '4', 'e')")
replace_once(path, '(Get-GlobalExitMainPromptCount $result.Output) | Should -Be 2', '(Get-GlobalExitMainPromptCount $result.Output) | Should -Be 5')
replace_once(path, "$result.Output | Should -Not -Match '4\\. Exit'", "$result.Output | Should -Match 'I\\. Install an SDK'\n        $result.Output | Should -Match 'R\\. Remove an isolated SDK'\n        $result.Output | Should -Match 'L\\. List installed SDKs'\n        $result.Output | Should -Not -Match '1\\. Install an SDK'\n        $result.Output | Should -Not -Match '2\\. Remove an isolated SDK'\n        $result.Output | Should -Not -Match '3\\. List installed SDKs'\n        $result.Output | Should -Not -Match '4\\. Exit'")
replace_once(path, "$result.Output | Should -Match 'Invalid selection: 4\\. Choose 1, 2, 3, or E\\.'", "$result.Output | Should -Match 'Invalid selection: 1\\. Choose I, R, L, or E\\.'\n        $result.Output | Should -Match 'Invalid selection: 2\\. Choose I, R, L, or E\\.'\n        $result.Output | Should -Match 'Invalid selection: 3\\. Choose I, R, L, or E\\.'\n        $result.Output | Should -Match 'Invalid selection: 4\\. Choose I, R, L, or E\\.'")
for old, new in [
    ("-InputLines @('1', 'e')", "-InputLines @('i', 'e')"),
    ("-InputLines @('1', 's', 'e')", "-InputLines @('i', 's', 'e')"),
    ("-InputLines @('1', 's', 's', 'e')", "-InputLines @('i', 's', 's', 'e')"),
    ("-InputLines @('1', 'a', 'e')", "-InputLines @('i', 'a', 'e')"),
    ("-InputLines @('1', '1', 'e')", "-InputLines @('i', '1', 'e')"),
    ("-InputLines @('1', '1', 's', 'e')", "-InputLines @('i', '1', 's', 'e')"),
    ("-InputLines @('2', 'e')", "-InputLines @('r', 'e')"),
]:
    replace_once(path, old, new)

# Bash global-exit coverage mirrors PowerShell.
path = 'tests/bash/global-exit.bats'
replace_once(path, '@test "Main advertises E Exit and rejects numeric 4 as an Exit alias"', '@test "Main advertises mnemonic commands and rejects numeric aliases"')
replace_once(path, 'printf "4\\ne\\n"', 'printf "1\\n2\\n3\\n4\\ne\\n"')
replace_once(path, '[ "$(count_main_prompts "$output")" -eq 2 ]', '[ "$(count_main_prompts "$output")" -eq 5 ]')
replace_once(path, '  [[ "$output" != *"4. Exit"* ]]', '  [[ "$output" == *"I. Install an SDK"* ]]\n  [[ "$output" == *"R. Remove an isolated SDK"* ]]\n  [[ "$output" == *"L. List installed SDKs"* ]]\n  [[ "$output" != *"1. Install an SDK"* ]]\n  [[ "$output" != *"2. Remove an isolated SDK"* ]]\n  [[ "$output" != *"3. List installed SDKs"* ]]\n  [[ "$output" != *"4. Exit"* ]]')
replace_once(path, '  [[ "$output" == *"Invalid selection: 4. Choose 1, 2, 3, or E."* ]]', '  [[ "$output" == *"Invalid selection: 1. Choose I, R, L, or E."* ]]\n  [[ "$output" == *"Invalid selection: 2. Choose I, R, L, or E."* ]]\n  [[ "$output" == *"Invalid selection: 3. Choose I, R, L, or E."* ]]\n  [[ "$output" == *"Invalid selection: 4. Choose I, R, L, or E."* ]]')
for old, new in [
    ('printf "1\\ne\\n"', 'printf "i\\ne\\n"'),
    ('printf "1\\ns\\ne\\n"', 'printf "i\\ns\\ne\\n"'),
    ('printf "1\\ns\\ns\\ne\\n"', 'printf "i\\ns\\ns\\ne\\n"'),
    ('printf "1\\na\\ne\\n"', 'printf "i\\na\\ne\\n"'),
    ('printf "1\\n1\\ne\\n"', 'printf "i\\n1\\ne\\n"'),
    ('printf "1\\n1\\ns\\ne\\n"', 'printf "i\\n1\\ns\\ne\\n"'),
    ('printf "2\\ne\\n"', 'printf "r\\ne\\n"'),
]:
    replace_once(path, old, new)

# Persistent lifecycle tests: only change inputs that address the Main menu.
path = 'tests/powershell/interactive-lifecycle.Tests.ps1'
for old, new in [
    ("-InputLines @('3', 'e')", "-InputLines @('l', 'e')"),
    ("-InputLines @('2', 'e')", "-InputLines @('r', 'e')"),
    ("-InputLines @('1', 'e')", "-InputLines @('i', 'e')"),
    ("-InputLines @('1', 'b', 'e')", "-InputLines @('i', 'b', 'e')"),
    ("-InputLines @('2', 'b', 'e')", "-InputLines @('r', 'b', 'e')"),
    ("-InputLines @('2', '', '6', 'b', 'e')", "-InputLines @('r', '', '6', 'b', 'e')"),
]:
    replace_once(path, old, new)
replace_once(path, "$result.Output | Should -Match '3\\. List installed SDKs'", "$result.Output | Should -Match 'L\\. List installed SDKs'")
replace_all(path, 'Choose 1, 2, 3, or E.', 'Choose I, R, L, or E.')

path = 'tests/bash/interactive-lifecycle.bats'
for old, new in [
    ('printf "3\\ne\\n"', 'printf "l\\ne\\n"'),
    ('printf "2\\ne\\n"', 'printf "r\\ne\\n"'),
    ('printf "1\\ne\\n"', 'printf "i\\ne\\n"'),
    ('printf "1\\nb\\ne\\n"', 'printf "i\\nb\\ne\\n"'),
    ('printf "2\\nb\\ne\\n"', 'printf "r\\nb\\ne\\n"'),
    ('printf "1\\n1\\n1\\n3\\n2\\n1\\ny\\ne\\n"', 'printf "i\\n1\\n1\\nl\\nr\\n1\\ny\\ne\\n"'),
    ('printf "2\\n\\n6\\nb\\ne\\n"', 'printf "r\\n\\n6\\nb\\ne\\n"'),
]:
    replace_once(path, old, new)
replace_all(path, 'Choose 1, 2, 3, or E.', 'Choose I, R, L, or E.')

# Real interactive E2E inputs.
replace_once(
    'tests/e2e/bash/interactive.sh',
    "interactive_input=\"$(printf '1\\n%s\\nB\\n%s\\nM\\n%s\\n3\\n2\\n1\\ne\\n' \\",
    "interactive_input=\"$(printf 'i\\n%s\\nB\\n%s\\nM\\n%s\\nl\\nr\\n1\\ne\\n' \\")

path = 'tests/e2e/powershell/interactive.ps1'
replace_once(path, "        '1',\n        $channelSelection,", "        'i',\n        $channelSelection,")
replace_once(path, "        '3',\n        '2',\n        '1',", "        'l',\n        'r',\n        '1',")

# Guard against stale current Main-menu presentation/guidance outside historical release notes.
for stale in [
    '  1. Install an SDK',
    '  2. Remove an isolated SDK',
    '  3. List installed SDKs',
    'Choose 1, 2, 3, or E.',
]:
    offenders = []
    for root in [Path('README.md'), Path('isolated-dotnet-sdk.ps1'), Path('isolated-dotnet-sdk.sh'), Path('tests')]:
        paths = [root] if root.is_file() else [p for p in root.rglob('*') if p.is_file()]
        for p in paths:
            try:
                text = p.read_text()
            except UnicodeDecodeError:
                continue
            if stale in text:
                offenders.append(str(p))
    if offenders:
        raise SystemExit(f"stale Main-menu text {stale!r} remains in: {', '.join(offenders)}")
