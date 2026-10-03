from pathlib import Path

root = Path('.')


def read(path: Path) -> str:
    return path.read_text(encoding='utf-8')


def write(path: Path, text: str) -> None:
    path.write_text(text, encoding='utf-8', newline='\n')


def replace_required(text: str, old: str, new: str, path: Path) -> str:
    if old not in text:
        raise SystemExit(f'Expected text not found in {path}: {old!r}')
    return text.replace(old, new)


# Clean up the internal function name that was shortened by the mechanical
# public-switch rename. This is not a public contract change.
ps = root / 'isolated-dotnet-sdk.ps1'
text = read(ps)
text = replace_required(text, 'Get-VersionText', 'Get-ToolVersionText', ps)
write(ps, text)

# Current documentation should consistently reserve Version/version for the
# tool itself and SdkVersion/sdk-version for explicit SDK selection. Preserve
# historical release-note/changelog text by limiting the sweep to live docs.
doc_paths = [root / 'README.md'] + list((root / 'docs').rglob('*.md'))
for path in doc_paths:
    text = read(path)
    sentinel = '__ISOLATED_DOTNET_TOOL_VERSION_SWITCH__'
    text = text.replace('-ToolVersion', sentinel)
    text = text.replace('-Version', '-SdkVersion')
    text = text.replace(sentinel, '-Version')
    write(path, text)

# Rewrite the focused tool-version page to make parity explicit.
tool_doc = root / 'docs' / 'commands' / 'tool-version.md'
write(tool_doc, '''# Tool version

The tool exposes its own release/source identity separately from the .NET SDK versions it installs and manages.

## Direct query

Both supported shells use their native `version` switch for the tool itself:

```powershell
& "$HOME\\dotnet-sdks\\isolated-dotnet-sdk.ps1" -Version
```

```bash
"$HOME/dotnet-sdks/isolated-dotnet-sdk.sh" --version
```

A stable copy published with embedded identity reports its exact release tag, for example:

```text
isolated-dotnet-sdk v1.2.3
```

A copy sourced from mutable `main` reports development identity instead:

```text
isolated-dotnet-sdk development (main)
```

The version query exits successfully after printing that identity. It does not bootstrap or replace the saved tool, create the isolated SDK root, query release metadata, enumerate SDKs, prompt for input, or check whether a newer release exists.

## Tool version versus SDK version

The supported shells expose the same version-selection capabilities with native switch spelling:

| Purpose | PowerShell | Bash |
| --- | --- | --- |
| Tool release/source identity | `-Version` | `--version` |
| Explicit exact SDK selector | `-SdkVersion <version>` | `--sdk-version <version>` |
| Positional exact SDK selector | `<version>` | `<version>` |

The explicit and positional SDK forms are equivalent. With no explicit action, an SDK version is a one-shot Install request. With Install, Verify, or Remove, it selects the SDK for that action.

`-Version` / `--version` never selects a .NET SDK. It identifies the `isolated-dotnet-sdk` tool itself.

## Stable and development identity

Stable releases published under this identity model embed the exact release tag into both supported product scripts during release publication. The checksum manifest is generated from those stamped release bytes, so tagged source, latest-stable bootstrap, pinned bootstrap/rollback, and the saved copy all retain the same identity.

Mutable `main` carries an explicit development identity and never derives or claims the latest published stable version.

Historical releases are not rewritten solely to add embedded identity metadata. A release published before this model remains historically unchanged.

The persistent [Main menu](interactive.md) displays the same underlying identity in a friendlier heading.
''')

commands = root / 'docs' / 'commands' / 'README.md'
text = read(commands)
old = 'PowerShell keeps `-SdkVersion` exclusively for the existing SDK-selection behavior and uses `-Version` for tool identity; Bash uses `--version`.'
new = 'PowerShell uses `-Version` and Bash uses `--version` for tool identity. Exact SDK selection is `-SdkVersion <version>` in PowerShell and `--sdk-version <version>` in Bash, and both shells also accept the exact SDK version positionally.'
text = replace_required(text, old, new, commands)
write(commands, text)

readme = root / 'README.md'
text = read(readme)
old = 'PowerShell `-Version` identifies the tool itself; the existing `-SdkVersion <sdk-version>` parameter remains the .NET SDK selector. See [Tool version](docs/commands/tool-version.md).'
new = 'PowerShell `-Version` and Bash `--version` identify the tool itself. For explicit SDK selection, use PowerShell `-SdkVersion <sdk-version>` or Bash `--sdk-version <sdk-version>`; both shells also accept the exact SDK version positionally. See [Tool version](docs/commands/tool-version.md).'
text = replace_required(text, old, new, readme)
write(readme, text)

win = root / 'docs' / 'getting-started' / 'windows-powershell.md'
text = read(win)
old = '`-Version` identifies the `isolated-dotnet-sdk` tool. The existing `-SdkVersion <sdk-version>` parameter remains the .NET SDK selector used by Install, Verify, and Remove. See [Tool version](../commands/tool-version.md).'
new = '`-Version` identifies the `isolated-dotnet-sdk` tool. `-SdkVersion <sdk-version>` explicitly selects the .NET SDK used by Install, Verify, and Remove, and the same exact SDK version can be supplied positionally. See [Tool version](../commands/tool-version.md).'
text = replace_required(text, old, new, win)
old = '''A version without `-Action` is the Install convenience form:

```powershell
& "$HOME\\dotnet-sdks\\isolated-dotnet-sdk.ps1" -SdkVersion '10.0.401'
```'''
new = '''Without `-Action`, the explicit SDK selector implies Install:

```powershell
& "$HOME\\dotnet-sdks\\isolated-dotnet-sdk.ps1" -SdkVersion '10.0.401'
```

The equivalent positional convenience form is also supported:

```powershell
& "$HOME\\dotnet-sdks\\isolated-dotnet-sdk.ps1" '10.0.401'
```'''
text = replace_required(text, old, new, win)
write(win, text)

bash = root / 'docs' / 'getting-started' / 'linux-macos-bash.md'
text = read(bash)
old = 'This identifies the `isolated-dotnet-sdk` tool itself. A bare value such as `10.0.401` remains the existing .NET SDK Install selector. See [Tool version](../commands/tool-version.md).'
new = 'This identifies the `isolated-dotnet-sdk` tool itself. `--sdk-version <sdk-version>` explicitly selects a .NET SDK, and a bare value such as `10.0.401` is the equivalent positional selector. See [Tool version](../commands/tool-version.md).'
text = replace_required(text, old, new, bash)
old = '''Install a known exact version directly:

```bash
"$HOME/dotnet-sdks/isolated-dotnet-sdk.sh" install 10.0.401
```

A bare version is the Install convenience form:

```bash
"$HOME/dotnet-sdks/isolated-dotnet-sdk.sh" 10.0.401
```'''
new = '''Install a known exact version directly with the explicit SDK selector:

```bash
"$HOME/dotnet-sdks/isolated-dotnet-sdk.sh" install --sdk-version 10.0.401
```

Without an explicit action, `--sdk-version` implies Install:

```bash
"$HOME/dotnet-sdks/isolated-dotnet-sdk.sh" --sdk-version 10.0.401
```

The equivalent positional convenience form is also supported:

```bash
"$HOME/dotnet-sdks/isolated-dotnet-sdk.sh" 10.0.401
```'''
text = replace_required(text, old, new, bash)
write(bash, text)

# Ensure no live documentation still names the retired public switch.
stale = []
for path in doc_paths:
    if '-ToolVersion' in read(path):
        stale.append(str(path))
if stale:
    raise SystemExit('Stale -ToolVersion references remain: ' + ', '.join(stale))

print('CLI documentation reconciliation applied successfully.')
