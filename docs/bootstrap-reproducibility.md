# Tagged-source bootstrap reproducibility

Implemented for `v0.1.0`.

Direct execution of a repository or tagged copy of either platform script preserves that exact script when installing the helper under `~/dotnet-sdks`.

The one-line bootstrap experience remains unchanged:

- `irm .../main/isolated-dotnet-sdk.ps1 | iex` downloads the current `main` PowerShell script and installs it.
- `curl .../main/isolated-dotnet-sdk.sh | bash` downloads the current `main` Bash script and installs it.

For file-based execution, the behavior is:

1. Detect that the script is running from a real file path.
2. If that path is already the installed helper path, run normally.
3. Otherwise copy the current script file to the installed helper path instead of downloading `main`.
4. Re-execute the installed helper with the original arguments.

The validation workflow covers this contract on Windows, Linux, and macOS by executing a marked temporary source copy and verifying that the installed helper preserves the marker.

This keeps tagged releases reproducible while retaining the convenient refresh-from-main quick start.
