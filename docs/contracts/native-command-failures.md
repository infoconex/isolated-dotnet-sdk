# Native command failure boundaries

The tool treats an external command's exit status as correctness-significant when later work depends on that command having completed successfully. A nonzero exit at one of these boundaries must stop the dependent operation and must not be converted into absence, an empty result, or success.

## Correctness-significant boundaries

| Boundary | PowerShell | Bash | Required behavior |
| --- | --- | --- | --- |
| Bootstrapped saved-tool execution | Propagate the saved PowerShell child script's failed invocation; do not treat a stale `$LASTEXITCODE` from optional native diagnostics as child failure | `exec` naturally replaces the bootstrap process and preserves the child status | Bootstrap must not return success when the saved tool fails |
| System `dotnet --list-sdks` inventory | Check `$LASTEXITCODE` | Capture the command status explicitly | Fail instead of treating a failed inventory as empty or continuing installation |
| Existing isolated host SDK proof | For newer hosts, check `--list-sdks` and `$LASTEXITCODE`; for historical 1.x/early 2.x use pinned `--version` and `--info` SDK Base Path | Equivalent modern inventory versus private legacy host proof | An unverified local host is never treated as an already-installed matching SDK; never trust system fallback |
| SDK payload download | PowerShell web-request failure is caught with SDK/version context | `curl` status is captured explicitly | Stop before checksum verification, extraction, and success output when the payload cannot be acquired |
| SDK payload hash verification | `Get-FileHash` must use the metadata-selected SHA-512 (or historical 1.x SHA-256) | The selected supported hashing utility must complete and match authoritative metadata | Stop before extraction when hashing fails or the digest does not match |
| Verified payload extraction | `Expand-Archive` failure is caught with SDK/version context | Archive extraction status is captured explicitly | Stop before staged-host verification and promotion when extraction fails |
| Post-extraction isolated host SDK proof | For newer hosts, check `--list-sdks` exit and inventory; for historical 1.x/early 2.x require exact `--version` plus `--info` SDK Base Path inside staging | Same version-dependent behavior | Fail before promotion when host invocation, exact SDK resolution, or origin verification fails |
| Standalone Verify isolated host `--list-sdks` | Catch host-launch failure and check `$LASTEXITCODE` | Require the host to be executable and capture command status explicitly | Fail nonzero without mutation when the host cannot run, exits nonzero, or succeeds without reporting the requested exact SDK |
| Removal build-server shutdown | Check `$LASTEXITCODE` and report SDK/exit context | Capture the command status and report SDK/exit context | Do not remove the SDK after shutdown failure and do not report removal success |

Diagnostics at these boundaries identify the failed operation and, where applicable, the SDK version and native exit code. Runtime-specific details may differ, but a shared product failure should not depend only on shell-native failure text when repository-owned context can identify the operation.

Optional component diagnostics (such as `dotnet --list-runtimes` on unsupported or incomplete hosts) must not turn an otherwise successful local Verify operation into a nonzero bootstrap exit. Original 1.x and early 2.x hosts skip unsupported runtime-inventory probes. This exception does not weaken the correctness-significant SDK version and origin proof.

## Related product boundaries

Release-index and channel-metadata transport/shape failures for interactive discovery follow the [SDK discovery and release metadata](../concepts/sdk-discovery.md) contract. Supplying an exact SDK version bypasses interactive version discovery, but installation still retrieves exact-version Microsoft release metadata to resolve the supported payload artifact and its checksum.

Filesystem ownership, bootstrap staging cleanup, and removal safety are specified in [Filesystem safety](../concepts/filesystem-safety.md). Native-command hardening must not widen the set of paths the tool may remove.

The transactional installation contract requires each install to use operation-owned metadata, payload, and staging state; verify the archive before extraction; verify the staged host before promotion; preserve pre-existing destinations; clean transaction-owned state when possible; and support deterministic retry after a clean-start failure. Acquisition, hashing, extraction, or verification failure must preserve that transaction contract rather than writing directly into or replacing the final destination.

Cross-shell observable behavior and intentional runtime differences are specified in [PowerShell and Bash behavioral parity](behavioral-parity.md).

## Verification distinction

Payload integrity verification and post-extraction exact-version verification are separate boundaries:

1. Before extraction, the downloaded archive must match the supported published checksum from the exact Microsoft release-metadata artifact entry (SHA-512 for all 2.x+ SDKs; historical 1.x SHA-256-only artifacts are the sole exception). Missing/malformed checksum metadata, hash-command failure, or mismatch fails closed before executable payload is exposed.
2. After extraction, a failed modern SDK inventory command or unsuccessful historical host version/origin proof prevents promotion; the tool reports an operation-specific failure without accepting SDKs from another root.
3. For modern hosts that support inventory, if the command succeeds but omits the requested exact version, the existing `SDK <version> was not found after installation.` contract applies. For older hosts, exact version and isolated SDK Base Path substitute for unsupported inventory.

Keeping those cases separate prevents a corrupt/mismatched archive from reaching extraction and prevents a broken staged host process from being misreported as a valid inventory that simply lacks the requested SDK. Standalone Verify reuses the host-inventory proof for an already-installed exact version, but it is diagnostic only: it does not repair, reacquire, promote, delete, or update anything.
