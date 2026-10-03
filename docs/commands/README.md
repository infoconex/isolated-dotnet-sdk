# Commands

These pages define the product-level behavior of each operation. They intentionally do not repeat complete PowerShell and Bash invocation syntax.

- [Install](install.md) — install one exact SDK under the isolated SDK root
- [List](list.md) — show Isolated SDKs and read-only System SDKs
- [Verify](verify.md) — perform a read-only health check of one isolated SDK
- [Remove](remove.md) — remove one SDK managed under the isolated SDK root
- [Interactive mode](interactive.md) — persistent sessions, navigation, and SDK selection

For exact commands and copy/paste examples, use the supported platform guide:

- [Windows / PowerShell 7](../getting-started/windows-powershell.md)
- [Linux or macOS / Bash](../getting-started/linux-macos-bash.md)

## Shared command model

Starting the tool without an action or exact version opens the persistent interactive session. Explicit actions and exact-version requests are one-shot and exit after the requested operation completes, is cancelled normally, or fails.

The tool owns SDKs only under the current user's `dotnet-sdks` directory. System SDKs are supplemental read-only inventory and never become removable merely because the tool can see them.

For detailed cross-shell behavior and intentional platform differences, see [PowerShell and Bash behavioral parity](../contracts/behavioral-parity.md).