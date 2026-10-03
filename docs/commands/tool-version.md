# Tool version

The tool exposes its own release/source identity separately from the .NET SDK versions it installs and manages.

## Direct query

PowerShell uses a dedicated switch because `-Version` already selects a .NET SDK:

```powershell
& "$HOME\dotnet-sdks\isolated-dotnet-sdk.ps1" -ToolVersion
```

Bash uses the conventional version option:

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

These are separate concepts:

- **tool version/source identity** identifies the `isolated-dotnet-sdk` script being executed;
- **SDK version** identifies the .NET SDK selected for Install, Verify, or Remove.

PowerShell `-Version <sdk-version>` keeps its existing SDK-selection meaning. It is not an alias for `-ToolVersion`.

## Stable and development identity

Stable releases published under this identity model embed the exact release tag into both supported product scripts during release publication. The checksum manifest is generated from those stamped release bytes, so tagged source, latest-stable bootstrap, pinned bootstrap/rollback, and the saved copy all retain the same identity.

Mutable `main` carries an explicit development identity and never derives or claims the latest published stable version.

Historical releases are not rewritten solely to add embedded identity metadata. A release published before this model remains historically unchanged.

The persistent [Main menu](interactive.md) displays the same underlying identity in a friendlier heading.
