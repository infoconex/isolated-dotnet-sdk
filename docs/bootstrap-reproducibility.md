# Tagged-source bootstrap reproducibility

Before publishing `v0.1.0`, direct execution of a repository or tagged copy of either platform script should preserve that exact script when installing the helper under `~/dotnet-sdks`.

The one-line bootstrap experience should remain unchanged:

- `irm .../main/isolated-dotnet-sdk.ps1 | iex` downloads the current `main` PowerShell script and installs it.
- `curl .../main/isolated-dotnet-sdk.sh | bash` downloads the current `main` Bash script and installs it.

For file-based execution, the desired behavior is:

1. Detect that the script is running from a real file path.
2. If that path is already the installed helper path, run normally.
3. Otherwise copy the current script file to the installed helper path instead of downloading `main`.
4. Re-execute the installed helper with the original arguments.

This keeps tagged releases reproducible while retaining the convenient refresh-from-main quick start.
