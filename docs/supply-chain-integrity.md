# Supply-chain integrity and trust boundaries

This document inventories remote code, tooling, artifacts, and metadata consumed by `isolated-dotnet-sdk` and its repository validation workflows. It distinguishes reproducibility controls from integrity/authenticity guarantees and records the residual trust that remains after the repository's supply-chain hardening work.

## Principles

- Remote executable code is higher risk than remote data and should be immutably identified where practical.
- A downloaded executable or archive should be verified before execution or extraction when an authoritative digest is available.
- Version pinning improves reproducibility but is not, by itself, an independent integrity check.
- A checksum served by the same publisher/trust domain as the artifact detects corruption and mismatches but does not create an independent publisher identity.
- Platform controls are useful when they fit the repository's operational policy, but stronger controls are not adopted automatically when they impose tradeoffs the repository owner does not want.

## Inventory and risk classification

| Surface | Risk and execution context | Source / mutability | Current control | Practical upstream/platform verification options | Residual trust |
| --- | --- | --- | --- | --- | --- |
| `actions/checkout` | High: third-party action code executes with the validation job's GitHub Actions permissions | GitHub action repository; tags are mutable references | Full 40-character commit SHA in workflow | Immutable commit reference; GitHub action distribution controls | GitHub action distribution and hosted-runner platform |
| Bats-core | Medium: test framework code executes on Ubuntu/macOS validation runners | `bats-core/bats-core` Git repository; branch/tag names can move | Exact Git commit plus reported-version check | Exact Git object/commit pin; upstream release/tag metadata | GitHub Git transport/object serving and the reviewed pinned upstream commit |
| ShellCheck | Medium: downloaded native binary executes on the Ubuntu validation runner | GitHub release archive; release asset URL is versioned but remotely hosted | Exact version plus repository-pinned SHA-256 verified before extraction | Upstream GitHub release plus repository-reviewed digest | GitHub release hosting and the repository-reviewed digest |
| Pester | Medium: downloaded PowerShell module executes the Windows behavioral test suite | PowerShell Gallery; package is selected by version | Exact module version; the current install command uses `-SkipPublisherCheck` | Gallery/NuGet package metadata and PowerShellGet publisher/package mechanisms | PowerShell Gallery, PowerShellGet/NuGet transport/package infrastructure, and hosted-runner trust |
| PSScriptAnalyzer | Medium: downloaded PowerShell module executes static analysis on the Windows runner | PowerShell Gallery; package is selected by version | Exact module version | Gallery/NuGet package metadata and PowerShellGet package mechanisms | PowerShell Gallery, PowerShellGet/NuGet transport/package infrastructure, and hosted-runner trust |
| Microsoft release index and per-channel release metadata | Medium: remote data controls interactive version discovery and supplies the exact SDK artifact URL and SHA-512 used for installation | `builds.dotnet.microsoft.com` mutable metadata endpoints | Structural validation, exact-version/RID matching, fail-closed checksum validation, and deterministic error handling | Microsoft HTTPS/CDN and published release metadata schema/artifact information | Microsoft metadata service/CDN/TLS; metadata and artifact are controlled by the same publisher, so the checksum is not independent publisher authentication |
| .NET SDK payload archive | High: downloaded executable payload ultimately becomes the installed SDK | Exact artifact URL selected from Microsoft release metadata | Archive SHA-512 is verified against the matching Microsoft metadata before extraction; transaction-scoped staging; post-extraction exact-version verification before promotion | Microsoft release metadata and distribution infrastructure; stronger independent signing/attestation could be evaluated separately if needed | Microsoft metadata/CDN/TLS remain trusted. A coordinated compromise of both Microsoft metadata and payload distribution is outside the checksum's protection |
| Stable `isolated-dotnet-sdk` release scripts | High: downloaded product source executes in the user's account and can replace the saved tool | Explicit GitHub Release tag; tag and release assets remain administratively mutable because repository-level immutable releases are intentionally not required | Explicit published tag, deterministic `SHA256SUMS` release asset, checksum verification before execution, draft-first release review | GitHub immutable releases/attestations remain available as an optional stronger platform control, but are not part of the approved repository policy | GitHub release/tag/asset hosting and repository administration; checksum and script share the GitHub trust domain, so coordinated authorized mutation of both is not prevented by the checksum alone |
| Development `main` bootstrap | High but explicitly opt-in: mutable repository source executes and may replace the saved development copy | Mutable repository `main` | Explicitly documented as development-only; never described as the stable channel | Review the selected source/commit manually or use the stable release path instead | Current repository `main` and GitHub raw-content delivery |

The repository's product install path no longer downloads or executes Microsoft's `dotnet-install.sh` / `.ps1` helper. The standalone product scripts now perform only the narrowly required acquisition steps themselves: resolve the exact SDK artifact from Microsoft's release metadata, download that archive, verify its published SHA-512 before extraction, extract into transaction-owned staging, verify the requested exact SDK version, and then promote the staging directory atomically.

This change removes a downloaded-code execution boundary and closes the previously documented unverified SDK-payload gap. It does not turn Microsoft's checksum into third-party authentication: the release metadata, checksum, and SDK artifact remain Microsoft-controlled surfaces delivered through Microsoft infrastructure.

## SDK payload verification boundary

For a new SDK installation, the tool resolves the selected exact SDK version and supported runtime identifier to one matching artifact entry in Microsoft's release metadata. That entry must contain an HTTPS artifact URL and a well-formed SHA-512 digest. Missing matching artifact metadata, a missing or malformed checksum, payload download failure, or digest mismatch fails closed before extraction.

The downloaded archive is operation-owned temporary state under the isolated SDK root. PowerShell uses `Get-FileHash -Algorithm SHA512`; Bash uses an available SHA-512 utility appropriate to the supported platform. Extraction starts only after the computed digest matches the Microsoft-published digest.

Checksum verification and post-extraction version verification are separate controls. The checksum constrains the archive bytes before executable payload is exposed. The staged host is then executed only after extraction to confirm that its SDK inventory contains the exact requested version. Neither check substitutes for the other, and promotion occurs only after both have succeeded.

The residual trust boundary remains Microsoft release metadata, Microsoft payload hosting/CDN, TLS, and the local platform primitives used to download, hash, and extract the archive. Because the checksum and artifact originate from the same publisher/trust domain, this control detects corruption, stale/mismatched artifacts, and one-sided payload tampering but does not protect against a coordinated compromise that can alter both authoritative metadata and the hosted payload.

## Stable release integrity

For releases after the Issue #22 policy is adopted:

1. the release commit must pass repository validation;
2. release checksum material is generated deterministically from the reviewed release tree;
3. the GitHub Release is created as a draft;
4. `SHA256SUMS` and all intended assets are attached before publication; and
5. the draft, tag target, checksum file, and assets are reviewed before publication.

Stable bootstrap downloads both the explicitly selected tagged script and that release's `SHA256SUMS`, verifies the selected script before execution, and then relies on the existing file-based bootstrap to preserve the exact verified source. Update and rollback remain explicit selections of another published tag.

Repository-level immutable releases are intentionally not required. This preserves the owner's preferred ability to retire/delete prior releases, but it also means GitHub release/tag/asset administration remains a material trust boundary. `SHA256SUMS` is deliberately not described as an independent signature: both script source and checksum asset are hosted by GitHub, and the checksum does not prevent an authorized administrator from changing both in coordination.

`v0.1.0` predates the checksum policy and has no checksum release asset; its existing bytes and publication state are retained as legacy history rather than rewritten retroactively.

## CI/framework boundaries

The existing checkout SHA pin and ShellCheck checksum remain required controls. Bats is fetched by exact Git commit and checked for its expected version. Pester and PSScriptAnalyzer are installed by exact version from PowerShell Gallery; the repository records that ecosystem/platform trust instead of introducing bespoke package-signing machinery or changing framework versions without a demonstrated, practical improvement.
