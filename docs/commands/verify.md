# Verify

Verify performs a read-only health check of one exact SDK already installed under the isolated SDK root.

For exact direct-command syntax, see [Windows / PowerShell](../getting-started/windows-powershell.md#verify-an-isolated-sdk) or [Linux and macOS / Bash](../getting-started/linux-macos-bash.md#verify-an-isolated-sdk).

## Invocation modes

Verify can be reached in two ways:

- an explicit one-shot Verify command requires an exact SDK version; or
- persistent interactive mode exposes `V. Verify an isolated SDK` on Main and lets you choose from the installed isolated SDK inventory.

Both paths run the same underlying health check. Interactive Verify does not define a second verification algorithm.

The interactive picker lists isolated SDKs only. System SDKs are never Verify targets. If no isolated SDKs are installed, the tool reports that state and returns to Main without changing anything.

## Healthy result

A healthy result establishes that:

- the selected isolated version directory exists;
- the platform-specific `dotnet` host is present and runnable;
- that host's `--list-sdks` command succeeds; and
- the host reports the requested exact SDK version.

Healthy direct verification exits successfully. Healthy interactive verification returns to Main.

## Failure results

Verify returns nonzero with operation-specific context when the isolated installation is missing, the host is missing or non-runnable, the host command fails, or the successful inventory does not contain the requested exact version.

In a persistent interactive session, an operational Verify failure terminates the session nonzero rather than returning to Main, so a later successful Exit cannot hide the failure.

## What Verify does not do

Verify does not:

- reinstall, repair, upgrade, downgrade, or remove an SDK;
- target SDKs that are available only through the system `dotnet` installation;
- change the normal `PATH` or system `dotnet` installation;
- re-hash every file in an installed SDK; or
- check or update the saved `isolated-dotnet-sdk` tool.

Payload checksum verification occurs during installation and is a separate integrity boundary from this installed-SDK health check.

See [Interactive mode](interactive.md) for Main-menu lifecycle and navigation, [Native-command failure boundaries](../contracts/native-command-failures.md) for the host-execution distinction, and [Supply-chain integrity](../concepts/supply-chain-integrity.md) for the install-time checksum model.
