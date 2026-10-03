# List

List is a read-only inventory view. It reports SDKs in two ownership domains and always shows Isolated SDKs first.

For exact shell syntax, see [Windows / PowerShell](../getting-started/windows-powershell.md#list-installed-sdks) or [Linux and macOS / Bash](../getting-started/linux-macos-bash.md#list-installed-sdks).

## Isolated SDKs

Isolated SDKs are recognized SDK installations under the current user's `dotnet-sdks` root. Each entry includes the SDK version and its concrete version directory.

An empty isolated inventory is shown as `None`.

## System SDKs

System SDKs are the SDKs reported by the normally resolved system `dotnet --list-sdks` host. This is supplemental read-only inventory, not an exhaustive filesystem scan.

Each entry includes the version and concrete version directory derived from the host's inventory output. Seeing a System SDK does not make it owned or removable by `isolated-dotnet-sdk`.

If no normal `dotnet` host is available, the System SDK group is empty. If a host resolves but its inventory command fails, List fails rather than silently presenting that failure as an empty inventory.

## Duplicate versions

The same exact SDK version can appear in both groups. The tool preserves that overlap because the entries represent separate installations with different ownership.

## Arguments and execution mode

List does not accept an SDK version. Supplying a version with an explicit List action is invalid input rather than a filter request.

List selected from a persistent interactive session returns to Main after completion. Explicit List is one-shot.

## Ownership boundary

List never installs, repairs, updates, or removes a System SDK. Remove remains limited to recognized SDKs under the isolated root.

See [Cross-platform support](../concepts/cross-platform-support.md) and [PowerShell and Bash behavioral parity](../contracts/behavioral-parity.md) for deeper inventory and failure semantics.
