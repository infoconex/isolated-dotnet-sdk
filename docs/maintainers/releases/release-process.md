# Stable release publication and verification

This document defines the maintainer procedure for publishing and independently re-verifying checksum-policy-compliant stable releases.

User installation, update, rollback, and tool-identity behavior are intentionally separate: see [Stable bootstrap, update, and rollback](../../releases/stable-bootstrap.md) and [Tool version](../../commands/tool-version.md).

## Publication is an intentional manual action

Stable releases are published through the manually triggered [`Publish Release`](../../../.github/workflows/publish-release.yml) workflow. Publication is never triggered automatically by a push, merge, or pull request. Starting the workflow from `main` with an explicit stable tag is the maintainer's publication decision.

Mutable `main` always carries the development tool identity. A stable tag is never produced by manually editing independent PowerShell and Bash version strings on `main`.

## Before dispatch

Before starting `Publish Release`:

1. the complete intended release state, including `.github/release-notes/<tag>.md`, must already be merged to `main`;
2. the exact intended `main` commit must have successful post-merge Validate and E2E push runs;
3. when a Pages push run exists for that exact commit, it must also be successful; and
4. the intended stable tag and GitHub Release must not already exist.

## Release identity derivation

The explicit stable tag supplied to `Publish Release` is the authoritative stable identity for that publication.

After validating the landed `main` SHA, the workflow uses `scripts/Set-ReleaseToolVersion.ps1` to replace the single development identity marker in each product script with that same stable tag. The workflow verifies that stamping changed exactly these two files and nothing else:

- `isolated-dotnet-sdk.ps1`
- `isolated-dotnet-sdk.sh`

Checksums are generated from those stamped bytes. Publication then creates one derived release commit whose only parent is the already-validated `main` SHA and whose only tree differences from that parent are the two stamped product scripts. The lightweight stable tag points to that derived release commit.

This keeps `main` visibly development source while making the tagged product-script bytes self-identifying. Latest-stable bootstrap, pinned bootstrap/rollback, and file-based saved-tool bootstrap all consume those same tagged bytes rather than inventing a second version source.

Historical releases are not rewritten to retrofit identity metadata. Public-release verification recognizes older releases that predate the embedded identity model.

## Publication transaction

Dispatch `Publish Release` from `main` with the explicit stable tag. The workflow derives the release commit from the exact `main` commit selected by that dispatch and fails closed unless all of the following remain true:

1. the dispatch SHA, checked-out SHA, and current `main` tip are identical;
2. the tag uses stable `vMAJOR.MINOR.PATCH` form;
3. the version-controlled release-notes file exists and is non-empty;
4. required landed-state Validate/E2E evidence is green for that exact commit, with Pages also green when a Pages run exists;
5. both product scripts contain exactly one development identity marker before release stamping;
6. one release-tag input stamps both product scripts and no other working-tree path changes;
7. `scripts/New-ReleaseChecksums.ps1` generates exactly the two expected checksum entries from the stamped release tree;
8. an independent SHA-256 calculation matches both generated script entries and the manifest has the expected deterministic text format;
9. the derived release commit has the validated `main` SHA as its sole parent and differs from it only by the two stamped product scripts;
10. a lightweight Git tag points directly to that derived release commit;
11. a GitHub Release is created as a **draft**, with the version-controlled notes as its exact body and only the intended `SHA256SUMS` asset;
12. the draft tag target, release metadata, asset set, uploaded checksum bytes, and derived release commit all match the reviewed state; and
13. only after those draft checks pass, the workflow publishes the release and reads the public release, tag, checksum asset, and derived commit back again to verify they are unchanged.

The draft stage is a transactional safety gate inside the workflow, not a separate manual publication approval.

## Failure and cleanup

If the workflow fails before publication, it removes only incomplete draft/tag state created by that run when it can establish that doing so is safe.

A derived Git commit object may already have been created before a later pre-publication failure. Until a tag or other ref points to it, that object is not published release state and requires no ref cleanup.

Once a release has become public, automated cleanup is intentionally disabled. A later verification failure is reported for maintainer investigation rather than deleting public release state.

## Read-only release verification

After publication, `Publish Release` invokes the read-only [`Verify Release`](../../../.github/workflows/verify-release.yml) workflow.

`Verify Release` can also be manually dispatched later with only the published stable tag. It:

1. requires stable `vMAJOR.MINOR.PATCH` tag form;
2. resolves the release commit directly from the lightweight tag;
3. verifies the public release metadata and requires exactly one uploaded `SHA256SUMS` asset;
4. runs the supported Windows/PowerShell stable bootstrap against the public tag;
5. runs the supported Linux/Bash stable bootstrap against the public tag;
6. confirms on both paths that the saved tool is byte-identical to the checksum-verified tagged source; and
7. for releases carrying embedded identity, verifies that both the tagged source and saved copy report the exact release tag through the direct tool-version query without creating SDK state first.

A historical release with no embedded identity assignment remains verifiable under its original published contract. If a release does contain an identity assignment, however, verification fails if that identity does not match the tag.

This verification is independently rerunnable without asking a maintainer to duplicate the tag-to-commit mapping manually.

## Publication evidence

The publication workflow records the published release URL, validated `main` commit SHA, derived release commit SHA, checksum-manifest SHA-256, both script SHA-256 values, and final manifest in the workflow summary. Retain that evidence as the publication record together with the landed Validate/E2E/Pages evidence required by the release issue.

## Administrative trust boundary

Repository-level immutable releases are intentionally not required. Maintainers retain the ability to retire or delete prior releases through normal GitHub administration.

That flexibility means GitHub release/tag/asset administration remains an accepted trust boundary. `SHA256SUMS` detects mismatched or corrupted acquired bytes, but it is not an independent signature and cannot prevent an authorized administrator from replacing both source and matching checksum material.

Release review should therefore record the intended tag target and checksum asset at publication time. The bootstrap contract relies on the release state presented for the explicitly selected tag; it does not claim that GitHub prevents later administrative mutation.

See [Supply-chain integrity and trust boundaries](../../concepts/supply-chain-integrity.md) for the complete remote-dependency and residual-trust model.
