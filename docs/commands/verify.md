# Verify

Verify performs a read-only health check of one exact SDK already installed under the isolated SDK root.

For exact shell syntax, see [Windows / PowerShell](../getting-started/windows-powershell.md#verify-an-isolated-sdk) or [Linux and macOS / Bash](../getting-started/linux-macos-bash.md#verify-an-isolated-sdk).

## Required version

Verify requires an exact SDK version and is always a direct, one-shot command. It is intentionally not an action on the persistent Main menu.

## Healthy result

A healthy result establishes that:

- the selected isolated version directory exists;
- the platform-specific `dotnet` host is present and runnable;
- that host's `--list-sdks` command succeeds; and
- the host reports the requested exact SDK version.

Healthy verification returns success.

## Failure results

Verify returns nonzero with operation-specific context when the isolated installation is missing, the host is missing or non-runnable, the host command fails, or the successful inventory does not contain the requested exact version.

## What Verify does not do

Verify does not:

- reinstall, repair, upgrade, downgrade, or remove an SDK;
- change the normal `PATH` or system `dotnet` installation;
- re-hash every file in an installed SDK; or
- check or update the saved `isolated-dotnet-sdk` tool.

Payload checksum verification occurs during installation and is a separate integrity boundary from this installed-SDK health check.

See [Native-command failure boundaries](../contracts/native-command-failures.md) for the host-execution distinction and [Supply-chain integrity](../concepts/supply-chain-integrity.md) for the install-time checksum model.
