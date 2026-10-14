# Install

Install creates an isolated copy of one exact .NET SDK version under the current user's isolated SDK root.

For exact shell syntax, see [Windows / PowerShell](../getting-started/windows-powershell.md#install-an-sdk) or [Linux and macOS / Bash](../getting-started/linux-macos-bash.md#install-an-sdk).

## Selecting a version

Install can resolve a version in three ways:

- a direct exact-version request;
- the interactive channel and SDK picker; or
- manual exact-version entry from the picker.

Displayed SDK version choices use the shared SDK-aware newest-to-oldest ordering; the compact picker still promotes the current latest SDK and newest feature-band representatives before the expanded full list.

A bare version with no explicit action is treated as an Install request.

Supplying an exact version bypasses interactive release-index/channel discovery, but it does **not** bypass the Microsoft release metadata required to identify the exact platform archive and its published checksum.

Historical SDK numbers do not always match the Microsoft .NET release channel. In particular, SDKs `2.1.4`, `2.1.105`, and `2.1.202` are in Microsoft's **2.0** release channel; SDK `2.1.300` and later 2.1.* builds belong to **2.1**. Direct exact-version installation resolves the correct published channel before selecting the archive, and Audit/Verify lifecycle lookups use the same historical SDK-to-channel mapping.

Historical SDK releases may publish archive names such as `dotnet-dev-win-x64.1.1.14.zip` instead of the modern `dotnet-sdk-<version>-<rid>.zip` layout. Install selects only an exact SDK-version and platform/RID archive from Microsoft's structured SDK release metadata. Historical distribution-specific Linux archives are not treated as interchangeable with generic Linux RIDs. The installer verifies the Microsoft-published SHA-512 whenever provided. Historical .NET 1.x SDKs with a published SHA-256 instead (including SDK 1.0.4) use SHA-256 verification before extraction. Modern SDKs still require SHA-512. Missing, malformed, ambiguous, or mismatched checksums fail closed; historical checksum support does not guarantee a legacy host will execute on a modern operating system.

## Existing installations

Before downloading a new SDK, Install checks the selected version in both ownership domains and presents Isolated SDK status before System SDK status.

If a valid matching Isolated SDK already exists, Install reports it as already installed and succeeds without downloading or reinstalling it.

If the version exists as a System SDK but not as an Isolated SDK, the tool asks before creating a separate isolated copy unless the supported confirmation-bypass option was supplied.

A pre-existing version destination under the isolated root that is not a valid matching isolated installation is preserved and causes a destination-conflict failure. Install does not automatically delete, merge into, repair, or adopt that state.

## Payload integrity and promotion

A new installation is transactional:

1. resolve the exact platform artifact and its supported published checksum algorithm (SHA-512, or SHA-256 for historical .NET 1.x SDKs only) from Microsoft release metadata;
2. download the SDK archive into operation-owned temporary state;
3. verify the archive using that Microsoft-published checksum before extraction;
4. extract into an operation-owned staging directory;
5. require the staged host to run successfully and prove the requested exact SDK version. Historical .NET Core 1.x and early 2.x SDK hosts (2.0.* and 2.1.* before 2.1.300) cannot reliably support `--list-sdks`. Instead, they must report the exact requested `--version` and an SDK `Base Path` inside the staged SDK's own `sdk/<version>` directory with `--info`. These checks use a private pinned `global.json` and disabled multilevel lookup to prevent accepting a system SDK; temporary verification files are removed. SDK 2.1.300+ and later hosts retain `--list-sdks` verification;
6. promote staging to the final version directory only while that destination remains absent; and
7. clean operation-owned metadata, payload, and staging state where possible.

A failed download, checksum, extraction, staged-host verification, or promotion must not be reported as installation success. Clean-start failures do not promote a partial final installation.

## Confirmation bypass

PowerShell `-Yes` and Bash `--yes` bypass supported confirmation prompts only. They do not invent a missing SDK version or turn an unresolved picker into a non-interactive request.

## Interactive versus one-shot

Install selected from a terminal-backed persistent Main session keeps a normal completed or cancellation/no-change result visible until Enter acknowledgement. A result launched from a selected channel's SDK picker returns to that same SDK list (`Press Enter to return to SDK selection...`); manual exact-version entry launched from the channel list returns to the channel list. Redirected or captured persistent execution skips the pause but follows the same parent navigation. An explicit Install invocation is one-shot; if it opens a picker, normal cancellation ends that one-shot command rather than entering Main or waiting for persistent-session acknowledgement.

For a currently prerelease channel, the SDK picker initially shows all discovered Preview/RC versions in newest-first order. Stable channels retain the compact featured default; `S` switches views only when they differ. See [Interactive mode](interactive.md) for complete channel/version picker and navigation behavior.

## Related contracts

- [SDK discovery and release metadata](../concepts/sdk-discovery.md)
- [Filesystem safety](../concepts/filesystem-safety.md)
- [Supply-chain integrity](../concepts/supply-chain-integrity.md)
- [Native-command failure boundaries](../contracts/native-command-failures.md)
