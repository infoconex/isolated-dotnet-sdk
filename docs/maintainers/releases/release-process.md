# Stable release publication and verification

This document defines the maintainer procedure for integrating, publishing, and independently re-verifying checksum-policy-compliant stable releases.

User installation, update, rollback, and tool-identity behavior are intentionally separate: see [Stable bootstrap, update, and rollback](../../releases/stable-bootstrap.md) and [Tool version](../../commands/tool-version.md). General development principles and decision authority are defined in the [development operating model](../development/operating-model.md).

## Branch roles

`main` is the released-production source line. Normal work for the next release does not merge directly to `main` while an active next-release integration branch exists.

For a release such as v0.4.0:

1. create `release/0.4` from the released `main` state;
2. create focused issue branches from `release/0.4`;
3. merge reviewed issue pull requests back to `release/0.4`;
4. evaluate and validate the integrated release candidate on `release/0.4`;
5. prepare all release documentation on that integration branch;
6. open one final release-candidate pull request from `release/0.4` to `main`;
7. after explicit approval, merge that release candidate to `main`;
8. validate the exact landed `main` commit and publish the stable release from that commit; and
9. delete the temporary release integration branch after publication and verification are complete.

The release integration branch is temporary. Do not add a permanent `develop` branch or adopt full GitFlow unless a separately approved architectural/process decision establishes a need.

Merging an individual issue into the release integration branch is not a stable release and does not imply that the integrated candidate is ready for `main`.

## Released-line hotfixes during an active next-release cycle

An urgent fix to the currently released production line is handled from `main`, not from the future release integration branch:

1. create a focused hotfix branch from `main`;
2. review and merge the hotfix back to `main` through the normal approval process;
3. validate and publish the appropriate patch release when required; and
4. forward-port the landed hotfix into the active next-release integration branch before the next stable release.

Do not allow a future release to lose a production fix merely because the release integration branch diverged before the hotfix landed.

## Publication is an intentional manual action

Stable releases are published through the manually triggered [`Publish Release`](../../../.github/workflows/publish-release.yml) workflow. Publication is never triggered automatically by a push, merge, or pull request. Starting the workflow from `main` with an explicit stable tag is the maintainer's publication decision.

Mutable source on `main` carries the development tool identity. A stable tag is never produced by manually editing independent PowerShell and Bash version strings on `main`.

Under the release-integration model, next-release work remains off `main` until the integrated candidate is explicitly approved. The final candidate merge to `main` and stable publication should be treated as one controlled release transaction: do not begin unrelated next-release work on `main` between those steps.

## Release documentation authorities

Release documentation has four distinct responsibilities:

- `CHANGELOG.md` is the chronological, categorized record of notable project changes by release.
- `.github/release-notes/<tag>.md` is the version-controlled publication body consumed by `Publish Release` for that exact stable tag.
- the GitHub Release is the published copy of those version-controlled release notes plus the release's checksum asset.
- `docs/releases/history/<tag>.md` is the concise user-facing historical summary published on the documentation site. It must be linked from the Releases overview and site navigation.

Do not duplicate the full changelog into each history page. The history page should summarize the stable release and link to the changelog and relevant durable documentation for deeper detail.

The Pages validation path checks every version-controlled stable release-notes file for a corresponding release-history page, Releases overview link, navigation entry, generated page, and search-index entry. A release documentation set that fails this consistency check is incomplete and must not be published.

## Release-candidate review before `main`

Before the final integration-branch -> `main` pull request is approved:

1. all intended release work must already be integrated into the release branch;
2. the hardening/release tracker must accurately reflect completed or intentionally deferred work;
3. release notes, changelog, release history, and navigation for the intended tag must be present on the release branch;
4. the integrated candidate must receive the full review appropriate to the release, including cross-shell behavior, tests, documentation, architecture/maintainability implications, and known follow-ups;
5. required integration-branch validation must be green, using explicit/manual full branch validation where normal PR triggers do not provide the required release-level signal; and
6. no known blocking release finding may remain.

The final PR to `main` is the release-candidate review boundary, not a container for new feature work. Any material finding should be fixed on the integration branch and included in the reviewed candidate before merge.

## Before publication dispatch

Before starting `Publish Release`:

1. the complete intended release state, including `.github/release-notes/<tag>.md`, `docs/releases/history/<tag>.md`, the Releases overview link, and the Pages navigation entry, must already be merged to `main` through the approved release-candidate PR;
2. the exact intended `main` commit must have successful post-merge Validate and E2E runs;
3. the Pages push run for that release-documentation commit must be successful, including the release-history consistency checks;
4. the intended stable tag and GitHub Release must not already exist; and
5. no unrelated commit may have landed on `main` after the reviewed release candidate.

## Release identity derivation

The explicit stable tag supplied to `Publish Release` is the authoritative stable identity for that publication.

After validating the landed `main` SHA, the workflow uses `scripts/Set-ReleaseToolVersion.ps1` to replace the single development identity marker in each product script with that same stable tag. The workflow verifies that stamping changed exactly these two files and nothing else:

- `isolated-dotnet-sdk.ps1`
- `isolated-dotnet-sdk.sh`

Checksums are generated from those stamped bytes. Publication then creates one derived release commit whose only parent is the already-validated `main` SHA and whose only tree differences from that parent are the two stamped product scripts. The lightweight stable tag points to that derived release commit.

This keeps the mutable source line visibly distinguishable from tagged stable bytes while making the tagged product scripts self-identifying. Latest-stable bootstrap, pinned bootstrap/rollback, and file-based saved-tool bootstrap all consume those same tagged bytes rather than inventing a second version source.

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

If final publication cannot be completed, do not resume unrelated development on `main` as though the release transaction finished. Investigate and either complete the release or make an explicit corrective decision.

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

## Publication evidence and integration cleanup

The publication workflow records the published release URL, validated `main` commit SHA, derived release commit SHA, checksum-manifest SHA-256, both script SHA-256 values, and final manifest in the workflow summary. Retain that evidence as the publication record together with the landed Validate/E2E/Pages evidence required by the release issue.

The completed release record should also leave the corresponding user-facing history page discoverable from the Releases overview and Pages navigation.

After publication and public verification succeed:

1. confirm the release tag and GitHub Release represent the intended stable version;
2. confirm latest-stable bootstrap resolves the new release;
3. reconcile the release/hardening tracker and release issue;
4. delete the completed next-release integration branch; and
5. begin a future release integration branch only when there is justified work for another release.

## Administrative trust boundary

Repository-level immutable releases are intentionally not required. Maintainers retain the ability to retire or delete prior releases through normal GitHub administration.

That flexibility means GitHub release/tag/asset administration remains an accepted trust boundary. `SHA256SUMS` detects mismatched or corrupted acquired bytes, but it is not an independent signature and cannot prevent an authorized administrator from replacing both source and matching checksum material.

Release review should therefore record the intended tag target and checksum asset at publication time. The bootstrap contract relies on the release state presented for the explicitly selected tag; it does not claim that GitHub prevents later administrative mutation.

See [Supply-chain integrity and trust boundaries](../../concepts/supply-chain-integrity.md) for the complete remote-dependency and residual-trust model.
