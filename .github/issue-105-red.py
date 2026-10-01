from pathlib import Path

bash_presentation = Path('tests/bash/presentation.bats')
text = bash_presentation.read_text()
text += r'''

@test "bootstrap output is separated from invocation and saved-tool output" {
  run env HOME="$test_home" "$source_copy" list

  [ "$status" -eq 0 ]
  [[ "$output" == $'\nInstalling tool to '* ]]
  [[ "$output" == *$'Tool installed.\n\nInstalled .NET SDKs'* ]]
}

@test "presentation source defines semantic accent and stderr-aware error roles" {
  grep -Fq 'tool_label_value() {' "$repo_root/isolated-dotnet-sdk.sh"
  grep -Fq 'tool_metadata() {' "$repo_root/isolated-dotnet-sdk.sh"
  grep -Fq 'if [[ -t 2 ]]; then' "$repo_root/isolated-dotnet-sdk.sh"
  grep -Fq "RED='\\033[0;31m'" "$repo_root/isolated-dotnet-sdk.sh"
}
'''
bash_presentation.write_text(text)

bash_lifecycle = Path('tests/bash/interactive-lifecycle.bats')
text = bash_lifecycle.read_text()
text += r'''

@test "Main retry distinguishes blank and nonblank invalid selections" {
  prepare_source

  run bash -c 'printf "\n6\ne\n" | env HOME="$1" "$2" 2>&1' _ "$test_home" "$source_copy"

  [ "$status" -eq 0 ]
  [[ "$output" == *"A selection is required. Choose 1, 2, 3, or E."* ]]
  [[ "$output" == *"Invalid selection: 6. Choose 1, 2, 3, or E."* ]]
  [[ "$output" == *$'A selection is required. Choose 1, 2, 3, or E.\n\nWhat would you like to do?'* ]]
  [[ "$output" == *$'Invalid selection: 6. Choose 1, 2, 3, or E.\n\nWhat would you like to do?'* ]]
}

@test "Remove retry reports active choices and separates feedback from redraw" {
  bootstrap_tool
  version='99.0.100'
  mkdir -p "$tool_root/$version"
  cat > "$tool_root/$version/dotnet" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$tool_root/$version/dotnet"

  run bash -c 'printf "2\n\n6\nb\ne\n" | env HOME="$1" "$2" 2>&1' _ "$test_home" "$tool_path"

  [ "$status" -eq 0 ]
  [[ "$output" == *"A selection is required. Choose 1, B, or E."* ]]
  [[ "$output" == *"Invalid selection: 6. Choose 1, B, or E."* ]]
  [[ "$output" == *$'A selection is required. Choose 1, B, or E.\n\nSelect an isolated SDK to remove:'* ]]
  [[ "$output" == *$'Invalid selection: 6. Choose 1, B, or E.\n\nSelect an isolated SDK to remove:'* ]]
}
'''
bash_lifecycle.write_text(text)

bash_global = Path('tests/bash/global-exit.bats')
text = bash_global.read_text().replace(
    '[[ "$output" == *"Please choose 1, 2, 3, or E."* ]]',
    '[[ "$output" == *"Invalid selection: 4. Choose 1, 2, 3, or E."* ]]')
text = text.replace(
    '[[ "$output" == *"Invalid selection."* ]]',
    '[[ "$output" == *"Invalid selection: a. Choose 1, S, B, M, or E."* ]]')
bash_global.write_text(text)

ps_presentation = Path('tests/powershell/presentation.Tests.ps1')
text = ps_presentation.read_text()
insert = r'''

    It 'separates bootstrap output from invocation and saved-tool output' {
        $output = @(& pwsh -NoProfile -File $script:SourceCopy -Action List 6>&1 | ForEach-Object { [string]$_ })

        $LASTEXITCODE | Should -Be 0
        $text = $output -join [Environment]::NewLine
        $text | Should -Match '^\r?\nInstalling tool to '
        $text | Should -Match 'Tool installed\.\r?\n\r?\nInstalled \.NET SDKs'
    }

    It 'defines a semantic accent role for labels and picker metadata' {
        $source = Get-Content -LiteralPath $script:SourceCopy -Raw

        $source | Should -Match "ValidateSet\('Heading', 'Accent', 'Success'\)"
        $source | Should -Match 'function Write-ToolLabelValue'
        $source | Should -Match 'function Write-ToolMetadata'
    }
'''
text = text.rsplit('\n}', 1)[0] + insert + '\n}\n'
ps_presentation.write_text(text)

ps_lifecycle = Path('tests/powershell/interactive-lifecycle.Tests.ps1')
text = ps_lifecycle.read_text()
insert = r'''

    It 'distinguishes blank and nonblank invalid Main selections' {
        $result = Invoke-InteractiveToolProcess `
            -ToolPath $script:ToolPath `
            -InputLines @('', '6', 'e') `
            -Command '& $env:ISOLATED_DOTNET_SDK_TOOL_PATH *>&1'

        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'A selection is required\. Choose 1, 2, 3, or E\.'
        $result.Output | Should -Match 'Invalid selection: 6\. Choose 1, 2, 3, or E\.'
        $result.Output | Should -Match 'A selection is required\. Choose 1, 2, 3, or E\.\r?\n\r?\nWhat would you like to do\?'
        $result.Output | Should -Match 'Invalid selection: 6\. Choose 1, 2, 3, or E\.\r?\n\r?\nWhat would you like to do\?'
    }

    It 'reports Remove choices and separates retry feedback from redraw' {
        $version = '99.0.100'
        $installDirectory = Join-Path $script:ToolRoot $version
        New-Item -ItemType Directory -Path $installDirectory -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $installDirectory 'dotnet.exe') -Force | Out-Null

        $result = Invoke-InteractiveToolProcess `
            -ToolPath $script:ToolPath `
            -InputLines @('2', '', '6', 'b', 'e') `
            -Command '& $env:ISOLATED_DOTNET_SDK_TOOL_PATH *>&1'

        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'A selection is required\. Choose 1, B, or E\.'
        $result.Output | Should -Match 'Invalid selection: 6\. Choose 1, B, or E\.'
        $result.Output | Should -Match 'A selection is required\. Choose 1, B, or E\.\r?\n\r?\nSelect an isolated SDK to remove:'
        $result.Output | Should -Match 'Invalid selection: 6\. Choose 1, B, or E\.\r?\n\r?\nSelect an isolated SDK to remove:'
    }
'''
text = text.rsplit('\n}', 1)[0] + insert + '\n}\n'
ps_lifecycle.write_text(text)

ps_global = Path('tests/powershell/global-exit.Tests.ps1')
text = ps_global.read_text().replace(
    "$result.Output | Should -Match 'Please choose 1, 2, 3, or E\\.'",
    "$result.Output | Should -Match 'Invalid selection: 4\\. Choose 1, 2, 3, or E\\.'")
text = text.replace(
    "$result.Output | Should -Match 'Invalid selection\\.'",
    "$result.Output | Should -Match 'Invalid selection: a\\. Choose 1, S, B, M, or E\\.'")
ps_global.write_text(text)
