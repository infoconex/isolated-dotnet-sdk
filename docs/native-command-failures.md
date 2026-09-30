# Native command failure boundaries

The tool treats an external command's exit status as correctness-significant when later work depends on that command having completed successfully. A nonzero exit at one of these boundaries must stop the dependent operation and must not be converted into absence, an empty result, or success.

## Correctness-significant boundaries

| Boundary | PowerShell | Bash | Required behavior |
| --- | --- | --- | --- |
| Bootstrapped saved-tool execution | Explicitly propagate the saved child tool's nonzero exit | `exec` naturally replaces the bootstrap process and preserves the child status | Bootstrap must not return success when the saved tool fails |
| System `dotnet --list-sdks` inventory | Check `$LASTEXITCODE` | Capture the command status explicitly | Fail instead of treating a failed inventory as empty or continuing installation |
| Existing isolated host `--list-sdks` | Check `$LASTEXITCODE` | Separate command execution from version matching | Fail instead of treating a broken isolated host as an absent SDK |
| SDK payload download | PowerShell web-request failure is caught with SDK/version context | `curl` status is captured explicitly | Stop before checksum verification, extraction, and success output when the payload cannot be acquired |
| SDK payload hash verification | `Get-FileHash -Algorithm SHA512` must complete and match authoritative metadata | The selected SHA-512 utility must complete and match authoritative metadata | Stop before extraction when hashing fails or the digest does not match |
| Verified payload extraction | `Expand-Archive` failure is caught with SDK/version context | Archive extraction status is captured explicitly | Stop before staged-host verification and promotion when extraction fails |
| Post-extraction isolated host `--list-sdks` | Check `$LASTEXITCODE` | Capture the command status explicitly | Report host-command failure separately from a successful inventory that omits the requested SDK |
| Standalone Verify isolated host `--list-sdks` | Catch host-launch failure and check `$LASTEXITCODE` | Require the host to be executable and capture command status explicitly | Fail nonzero without mutation when the host cannot run, exits nonzero, or succeeds without reporting the requested exact SDK |
| Removal build-server shutdown | Check `$LASTEXITCODE` and report SDK/exit context | Capture the command status and report SDK/exit context | Do not remove the SDK after shutdown failure and do not report removal success |

Diagnostics at these boundaries identify the failed operation and, where applicable, the SDK version and native exit code. Runtime-specific details may differ, but a shared product failure should not depend only on shell-native failure text when repository-owned context can identify the operation.

## Related product boundaries

Release-index and channel-metadata transport/shape failures for interactive discovery follow the interactive discovery contract. Supplying an exact SDK version bypasses interactive version discovery, but installation still retrieves exact-version Microsoft release metadata to resolve the supported payload artifact and its checksum.

Filesystem ownership, bootstrap staging cleanup, and removal safety are specified in [`filesystem-safety.md`](filesystem-safety.md). Native-command hardening must not widen the set of paths the tool may remove.

The transactional installation contract requires each install to use operation-owned metadata, payload, and staging state; verify the archive before extraction; verify the staged host before promotion; preserve pre-existing destinations; clean transaction-owned state when possible; and support deterministic retry after a clean-start failure. Acquisition, hashing, extraction, or verification failure must preserve that transaction contract rather than writing directly into or replacing the final destination.

Cross-shell observable behavior and intentional runtime differences are specified in [`behavioral-parity.md`](behavioral-parity.md).

## Verification distinction

Payload integrity verification and post-extraction exact-version verification are separate boundaries:

1. Before extraction, the downloaded archive must match the SHA-512 from the exact Microsoft release-metadata artifact entry. Missing/malformed checksum metadata, hash-command failure, or mismatch fails closed before executable payload is exposed.
2. After extraction, if the isolated host command itself exits nonzero, the tool reports that staged SDK verification could not be performed and includes the exit code.
3. If the isolated host command succeeds but its SDK inventory does not contain the requested exact version, the existing `SDK <version> was not found after installation.` contract applies.

Keeping those cases separate prevents a corrupt/mismatched archive from reaching extraction and prevents a broken staged host process from being misreported as a valid inventory that simply lacks the requested SDK. Standalone Verify reuses the host-inventory proof for an already-installed exact version, but it is diagnostic only: it does not repair, reacquire, promote, delete, or update anything.
