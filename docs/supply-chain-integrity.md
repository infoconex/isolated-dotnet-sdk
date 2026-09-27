# Supply-chain integrity and trust boundaries

This document inventories remote code, tooling, artifacts, and metadata consumed by `isolated-dotnet-sdk` and its repository validation workflows. It distinguishes reproducibility controls from integrity/authenticity guarantees and records the residual trust that remains after Issue #22.

## Principles

- Remote executable code is higher risk than remote data and should be immutably identified where practical.
- A downloaded executable or archive should be verified before execution or extraction when a repository-owned digest is available.
- Version pinning improves reproducibility but is not, by itself, an independent integrity check.
- A checksum served from the same trust domain as the artifact detects corruption and mismatches but does not create an independent publisher identity.
- Platform controls are useful when they fit the repository's operational policy, but stronger controls are not adopted automatically when they impose tradeoffs the repository owner does not want.

## Inventory and risk classification

| Surface | Risk and execution context | Source / mutability | Current control | Practical upstream/platform verification options | Residual trust |
| --- | --- | --- | --- | --- | --- |
| `actions/checkout` | High: third-party action code executes with the validation job's GitHub Actions permissions | GitHub action repository; tags are mutable references | Full 40-character commit SHA in workflow | Immutable commit reference; GitHub action distribution controls | GitHub action distribution and hosted-runner platform |
| Bats-core | Medium: test framework code executes on Ubuntu/macOS validation runners | `bats-core/bats-core` Git repository; branch/tag names can move | Exact Git commit plus reported-version check | Exact Git object/commit pin; upstream release/tag metadata | GitHub Git transport/object serving and the reviewed pinned upstream commit |
| ShellCheck | Medium: downloaded native binary executes on the Ubuntu validation runner | GitHub release archive; release asset URL is versioned but remotely hosted | Exact version plus repository-pinned SHA-256 verified before extraction | Upstream GitHub release plus repository-reviewed digest | GitHub release hosting and the repository-reviewed digest |
| Pester | Medium: downloaded PowerShell module executes the Windows behavioral test suite | PowerShell Gallery; package is selected by version | Exact module version; the current install command uses `-SkipPublisherCheck` | Gallery/NuGet package metadata and PowerShellGet publisher/package mechanisms | PowerShell Gallery, PowerShellGet/NuGet transport/package infrastructure, and hosted-runner trust |
| PSScriptAnalyzer | Medium: downloaded PowerShell module executes static analysis on the Windows runner | PowerShell Gallery; package is selected by version | Exact module version | Gallery/NuGet package metadata and PowerShellGet package mechanisms | PowerShell Gallery, PowerShellGet/NuGet transport/package infrastructure, and hosted-runner trust |
| Microsoft `dotnet-install.sh` / `.ps1` | High: downloaded code executes in the user's account and controls SDK acquisition/staging | Official `dotnet/install-scripts` repository; moving entry points exist, but this repository selects a fixed commit | Official upstream commit `da3ce11ba63f3dbb0fb835d41bda2665d5c48e84`; Git blob provenance and repository-pinned SHA-256 recorded in `.config/remote-artifacts.json`; commit-qualified raw URL and SHA-256 verification before execution | Upstream Git commit/blob identity, release/tag metadata, and upstream signature material where available | GitHub serving the pinned upstream object and the repository-reviewed digest |
| Microsoft release index and per-channel release metadata | Medium: remote data controls which exact SDK versions are offered interactively but is not executed | `builds.dotnet.microsoft.com` mutable metadata endpoints | Structural validation, deterministic error handling, and exact-version selection | Microsoft HTTPS/CDN and published release metadata schema/artifact information | Microsoft metadata service/CDN/TLS; a compromised metadata response could influence offered versions but is not directly executed |
| .NET SDK payload archive | High: downloaded executable payload ultimately becomes the installed SDK | Downloaded by the pinned Microsoft helper from Microsoft distribution infrastructure | Exact requested SDK version; transaction-scoped staging; post-install exact-version verification before promotion | Microsoft publishes per-artifact checksum data that could support independent payload verification in a later hardening step | **Accepted Issue #22 boundary:** Microsoft payload distribution remains trusted. Independent archive checksum verification is intentionally deferred and can be added later without changing the helper pinning model. |
| Stable `isolated-dotnet-sdk` release scripts | High: downloaded product source executes in the user's account and can replace the saved tool | Explicit GitHub Release tag; tag and release assets remain administratively mutable because repository-level immutable releases are intentionally not required | Explicit published tag, deterministic `SHA256SUMS` release asset, checksum verification before execution, draft-first release review | GitHub immutable releases/attestations remain available as an optional stronger platform control, but are not part of the approved repository policy | GitHub release/tag/asset hosting and repository administration; checksum and script share the GitHub trust domain, so coordinated authorized mutation of both is not prevented by the checksum alone |
| Development `main` bootstrap | High but explicitly opt-in: mutable repository source executes and may replace the saved development copy | Mutable repository `main` | Explicitly documented as development-only; never described as the stable channel | Review the selected source/commit manually or use the stable release path instead | Current repository `main` and GitHub raw-content delivery |

The highest-impact baseline gaps were the moving Microsoft installer helper and stable released source executed without an integrity check. Issue #22 adds immutable source selection plus a repository-owned digest for the helper and checksum verification for future stable tool releases. The repository intentionally accepts GitHub release/tag/asset administration as a residual trust boundary rather than requiring repository-level immutable releases. Lower-value CI/framework surfaces retain existing exact-version/object controls where stronger machinery would add dependency or signing complexity without a demonstrated material reduction in this repository's risk.

## Microsoft installer provenance

The current installer-helper trust anchors are stored in `.config/remote-artifacts.json` so review can compare the upstream commit, Git blob IDs, raw URLs, and SHA-256 digests together. The product scripts embed the commit-qualified URL and SHA-256 needed at runtime because each script must remain standalone after bootstrap.

The Git commit and blob IDs record immutable upstream provenance. The SHA-256 value is the execution gate: after the helper is downloaded, the product computes the digest of the downloaded bytes and refuses to execute the helper when verification fails.

Updating the Microsoft helper is therefore an explicit repository change. Review should confirm the intended upstream release/commit, blob ID, downloaded-byte SHA-256, product constants, provenance config, and deterministic tests together. Later dependency monitoring may surface newer upstream versions, but it must not silently change the runtime dependency.

## SDK payload boundary

Issue #22 intentionally does not redesign SDK acquisition to independently download and verify each SDK archive. The pinned Microsoft helper still downloads the selected SDK payload from Microsoft infrastructure. The repository protects that path with an integrity-checked helper, exact requested version, transaction-scoped staging, and post-install exact-version verification.

A later hardening issue can consume Microsoft's per-artifact checksum metadata and independently verify the SDK archive before extracted code is executed. That would strengthen end-to-end payload integrity without undoing the helper controls introduced here.

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

The existing checkout SHA pin and ShellCheck checksum remain required controls. Bats is already fetched by exact Git commit and checked for its expected version. Pester and PSScriptAnalyzer are installed by exact version from PowerShell Gallery; Issue #22 records that ecosystem/platform trust instead of introducing a bespoke package-signing mechanism or changing framework versions without a demonstrated, practical improvement.
