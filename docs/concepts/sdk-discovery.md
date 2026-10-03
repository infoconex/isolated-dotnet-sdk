# SDK discovery and release metadata

This document records the release-metadata discovery contract shared by the PowerShell and Bash implementations.

## Scope

Interactive SDK version selection uses Microsoft's release index to choose a .NET channel and then uses that channel's release metadata to enumerate exact SDK versions. An install that already supplies an exact SDK version bypasses that release-index/channel discovery path.

Once an exact SDK version has been resolved, installation separately retrieves Microsoft's exact-version release metadata to identify the supported platform archive and its published SHA-512. Supplying an exact version therefore bypasses interactive discovery, not the metadata required for payload acquisition and integrity verification.

This contract covers interactive version discovery only. It does not define retry/backoff, stable bootstrap source policy, or the later transactional SDK payload acquisition, verification, extraction, staging, and promotion behavior.

## Release index

A transport failure while loading the Microsoft release index is an operation failure. The tool exits nonzero with repository-owned context and does not present discovery success.

The index must contain usable channel entries. A selectable channel requires:

- `channel-version`;
- `support-phase`;
- `releases.json`.

Display-only metadata such as `latest-sdk` and `release-type` may be absent without invalidating an otherwise selectable channel.

Malformed, structurally unusable, missing, null, or empty index data must fail before the tool presents an empty or misleading channel picker.

## Selected-channel metadata

A transport failure while loading the selected channel's `releases.json` is an operation failure and identifies the selected channel in the diagnostic.

Malformed or structurally unusable channel metadata fails nonzero. A channel that yields no SDK versions also fails rather than presenting an empty SDK picker.

Duplicate SDK versions are removed while preserving first-seen order. PowerShell metadata normalization accepts SDK versions exposed through either the `sdk` member or the `sdks` collection.

## Explicit-version installs

When the caller supplies an exact SDK version, release-index and selected-channel discovery are bypassed. Installation still retrieves the exact version's Microsoft release metadata to resolve the supported platform archive and SHA-512. Failure to retrieve or validate that required artifact metadata, download the payload, or verify its checksum belongs to the installation/payload-integrity boundary rather than being reported as an interactive release-metadata discovery failure.

## Filesystem safety

The filesystem ownership rules in [Filesystem safety](filesystem-safety.md) remain authoritative. In particular, Bash channel metadata uses an operation-owned temporary file under the isolated SDK root, removes that exact file after normal or failed processing, and does not broaden cleanup to similarly named pre-existing files.

## Cross-shell behavior

PowerShell and Bash may parse and retrieve metadata differently, but their observable discovery contract is shared:

- required discovery failures are nonzero;
- diagnostics provide repository-owned release/channel context;
- failed discovery is never followed by success output;
- unusable empty selections are rejected;
- optional display metadata does not become an accidental hard requirement;
- exact-version installation remains independent from release-index/channel discovery while still using exact-version release metadata for payload integrity.

For Microsoft's upstream release metadata and release-note structure, see [.NET release metadata](https://github.com/dotnet/core/tree/main/release-notes).
