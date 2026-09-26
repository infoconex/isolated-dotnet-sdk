# Release-metadata discovery

This document records the release-metadata discovery contract shared by the PowerShell and Bash implementations.

## Scope

Interactive SDK installation uses Microsoft's release index to choose a .NET channel and then uses that channel's release metadata to enumerate exact SDK versions. An install that already supplies an exact SDK version does not need release-metadata discovery.

This contract covers discovery only. It does not define retry/backoff, stable bootstrap source policy, or transaction/rollback behavior for the later SDK installer.

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

When the caller supplies an exact SDK version, release-index and selected-channel discovery are bypassed. A later failure to download or run the SDK installer belongs to the installation boundary rather than being reported as a release-metadata discovery failure.

## Filesystem safety

The filesystem ownership rules in [`filesystem-safety.md`](filesystem-safety.md) remain authoritative. In particular, Bash channel metadata uses an operation-owned temporary file under the isolated SDK root, removes that exact file after normal or failed processing, and does not broaden cleanup to similarly named pre-existing files.

## Cross-shell behavior

PowerShell and Bash may parse and retrieve metadata differently, but their observable discovery contract is shared:

- required discovery failures are nonzero;
- diagnostics provide repository-owned release/channel context;
- failed discovery is never followed by success output;
- unusable empty selections are rejected;
- optional display metadata does not become an accidental hard requirement;
- exact-version installation remains independent from release metadata.
