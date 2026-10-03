# Install

Install creates an isolated copy of one exact .NET SDK version under the current user's isolated SDK root.

For exact shell syntax, see [Windows / PowerShell](../getting-started/windows-powershell.md#install-an-sdk) or [Linux and macOS / Bash](../getting-started/linux-macos-bash.md#install-an-sdk).

## Selecting a version

Install can resolve a version in three ways:

- a direct exact-version request;
- the interactive channel and SDK picker; or
- manual exact-version entry from the picker.

A bare version with no explicit action is treated as an Install request.

Supplying an exact version bypasses interactive release-index/channel discovery, but it does **not** bypass the Microsoft release metadata required to identify the exact platform archive and its published SHA-512.

## Existing installations

Before downloading a new SDK, Install checks the selected version in both ownership domains and presents Isolated SDK status before System SDK status.

If a valid matching Isolated SDK already exists, Install reports it as already installed and succeeds without downloading or reinstalling it.

If the version exists as a System SDK but not as an Isolated SDK, the tool asks before creating a separate isolated copy unless the supported confirmation-bypass option was supplied.

A pre-existing version destination under the isolated root that is not a valid matching isolated installation is preserved and causes a destination-conflict failure. Install does not automatically delete, merge into, repair, or adopt that state.

## Payload integrity and promotion

A new installation is transactional:

1. resolve the exact platform artifact and SHA-512 from Microsoft release metadata;
2. download the SDK archive into operation-owned temporary state;
3. verify the archive SHA-512 before extraction;
4. extract into an operation-owned staging directory;
5. require the staged host to run successfully and report the requested exact SDK version;
6. promote staging to the final version directory only while that destination remains absent; and
7. clean operation-owned metadata, payload, and staging state where possible.

A failed download, checksum, extraction, staged-host verification, or promotion must not be reported as installation success. Clean-start failures do not promote a partial final installation.

## Confirmation bypass

PowerShell `-Yes` and Bash `--yes` bypass supported confirmation prompts only. They do not invent a missing SDK version or turn an unresolved picker into a non-interactive request.

## Interactive versus one-shot

Install selected from the persistent Main menu returns to Main after normal completion or cancellation. An explicit Install invocation is one-shot; if it opens a picker, normal cancellation ends that one-shot command rather than entering Main.

See [Interactive mode](interactive.md) for channel/version picker and navigation behavior.

## Related contracts

- [SDK discovery and release metadata](../concepts/sdk-discovery.md)
- [Filesystem safety](../concepts/filesystem-safety.md)
- [Supply-chain integrity](../concepts/supply-chain-integrity.md)
- [Native-command failure boundaries](../contracts/native-command-failures.md)
