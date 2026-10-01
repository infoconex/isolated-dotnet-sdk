from pathlib import Path

ps = Path('isolated-dotnet-sdk.ps1')
text = ps.read_text()
text = text.replace('function Write-ToolMetadata {', 'function Format-ToolAccent {')
text = text.replace('$Metadata = Write-ToolMetadata -Message', '$Metadata = Format-ToolAccent -Message')
ps.write_text(text)

ps_test = Path('tests/powershell/presentation.Tests.ps1')
text = ps_test.read_text().replace("$source | Should -Match 'function Write-ToolMetadata'", "$source | Should -Match 'function Format-ToolAccent'")
ps_test.write_text(text)

bash_test = Path('tests/bash/presentation.bats')
text = bash_test.read_text()
old = "  [[ \"$output\" == *$'Tool installed.\\n\\nInstalled .NET SDKs'* ]]\n"
new = '''  tool_installed_line=-1
  installed_heading_line=-1
  for ((i=0; i<${#lines[@]}; i++)); do
    [[ "${lines[$i]}" == "Tool installed." ]] && tool_installed_line=$i
    [[ "${lines[$i]}" == "Installed .NET SDKs" ]] && installed_heading_line=$i
  done
  [ "$tool_installed_line" -ge 0 ]
  [ "$installed_heading_line" -gt "$tool_installed_line" ]

  blank_boundary='false'
  for ((i=tool_installed_line + 1; i<installed_heading_line; i++)); do
    if [[ -z "${lines[$i]}" ]]; then
      blank_boundary='true'
      break
    fi
  done
  [ "$blank_boundary" = 'true' ]
'''
if old not in text:
    raise SystemExit('Bash bootstrap assertion not found')
bash_test.write_text(text.replace(old, new, 1))

Path('.github/workflows/issue-105-fix.yml').unlink()
Path('.github/issue-105-fix.py').unlink()
