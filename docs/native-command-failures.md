# Native command failure boundaries

The tool treats an external command's exit status as correctness-significant when later work depends on that command having completed successfully. A nonzero exit at one of these boundaries must stop the dependent operation and must not be converted into absence, an empty result, or success.

## Correctness-significant boundaries

| Boundary | PowerShell | Bash | Required behavior |
| --- | --- | --- | --- |
| Bootstrapped saved-tool execution | Explicitly propagate the saved child tool's nonzero exit | `exec` naturally replaces the bootstrap process and preserves the child status | Bootstrap must not return success when the saved tool fails |
| System `dotnet --list-sdks` inventory | Check `$LASTEXITCODE` | Capture the command status explicitly | Fail instead of treating a failed inventory as empty or continuing installation |
| Existing isolated host `--list-sdks` | Check `$LASTEXITCODE` | Separate command execution from version matching | Fail instead of treating a broken isolated host as an absent SDK |
| Microsoft `dotnet-install` execution | Check `$LASTEXITCODE` | Capture the installer status explicitly | Stop before verification and success output when the installer fails |
| Post-install isolated host `--list-sdks` | Check `$LASTEXITCODE` | Capture the command status explicitly | Report host-command failure separately from a successful inventory that omits the requested SDK |
| Removal build-server shutdown | Protected by the removal contract from Issue #11 | Standalone command failure is propagated by `set -e` | Do not remove the SDK after shutdown failure |

Diagnostics at these boundaries identify the failed operation and, where applicable, the SDK version and native exit code.

## Related boundaries owned by other issues

Release-index and channel-metadata transport/shape failures are governed by Issue #16. Supplying an exact SDK version remains independent of release-metadata discovery.

Filesystem ownership, bootstrap staging cleanup, and removal safety are governed by Issue #15. Native-command hardening must not widen the set of paths the tool may remove.

Installer rollback, partial-install cleanup, transactional staging, retry policy, and download transactionality belong to Issue #18. A native installer failure is reported immediately, but Issue #17 does not attempt to undo files the installer may already have created.

## Verification distinction

Post-install verification has two distinct failure contracts:

1. If the isolated host command itself exits nonzero, the tool reports that verification could not be performed and includes the exit code.
2. If the isolated host command succeeds but its SDK inventory does not contain the requested exact version, the existing `SDK <version> was not found after installation.` contract applies.

Keeping those cases separate prevents a broken host process from being misreported as a valid inventory that simply lacks the requested SDK.
