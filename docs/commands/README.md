# Commands

These pages define the product-level behavior of each operation. They intentionally do not repeat complete PowerShell and Bash invocation syntax.

- [Install](install.md) — install one exact SDK under the isolated SDK root
- [List](list.md) — show Isolated SDKs and read-only System SDKs
- [Audit](audit.md) — assess installed SDK servicing and lifecycle state against current Microsoft metadata
- [Verify](verify.md) — perform a read-only health check of one isolated SDK
- [Remove](remove.md) — remove one SDK managed under the isolated SDK root
- [Tool version](tool-version.md) — identify the running tool release or development source
- [Interactive mode](interactive.md) — persistent sessions, navigation, and SDK selection

For exact commands and copy/paste examples, use the supported platform guide:

- [Windows / PowerShell 7](../getting-started/windows-powershell.md)
- [Linux or macOS / Bash](../getting-started/linux-macos-bash.md)

## Shared command model

Starting the tool without an action or exact version opens the persistent interactive session. Explicit actions and exact-version requests are one-shot and exit after the requested operation completes, is cancelled normally, or fails.

The tool-version query is also one-shot, but it identifies `isolated-dotnet-sdk` itself rather than selecting a .NET SDK. It exits before bootstrap, SDK discovery, release-metadata access, prompting, or mutation. PowerShell uses `-Version` and Bash uses `--version` for tool identity. Exact SDK selection is `-SdkVersion <version>` in PowerShell and `--sdk-version <version>` in Bash, and both shells also accept the exact SDK version positionally.

The tool owns SDKs only under the current user's `dotnet-sdks` directory. System SDKs are supplemental read-only inventory and never become removable merely because the tool can see them. List and Verify stay local; Audit is the explicit online read-only operation for servicing and lifecycle assessment.

For detailed cross-shell behavior and intentional platform differences, see [PowerShell and Bash behavioral parity](../contracts/behavioral-parity.md).