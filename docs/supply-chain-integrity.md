# Supply-chain integrity and trust boundaries

This document inventories remote code, tooling, artifacts, and metadata consumed by `isolated-dotnet-sdk` and its repository validation workflows. It distinguishes reproducibility controls from integrity/authenticity guarantees and records the residual trust that remains after Issue #22.

## Principles

- Remote executable code is higher risk than remote data and should be immutably identified where practical.
- A downloaded executable or archive should be verified before execution or extraction when a repository-owned digest is available.
- Version pinning improves reproducibility but is not, by itself, an independent integrity check.
- A checksum served from the same trust domain as the artifact detects corruption and mismatches but does not create an independent publisher identity.
- Platform controls such as GitHub immutable releases and release attestations are preferred over custom cryptographic machinery when they address the relevant risk.

## Inventory

| Surface | Kind / impact | Source and mutability | Control | Residual trust |
| --- | --- | --- | --- | --- |
| `actions/checkout` | Executable CI action | GitHub Actions marketplace/repository | Full 40-character commit SHA in workflow | GitHub action distribution and runner platform |
| Bats-core | Executable CI test framework | `bats-core/bats-core` Git repository | Exact Git commit plus reported-version check | GitHub Git transport/object serving and the pinned upstream commit |
| ShellCheck | Executable downloaded CI binary | GitHub release archive | Exact version plus repository-pinned SHA-256 verified before extraction | GitHub release hosting and the repository-reviewed digest |
| Pester | Executable PowerShell test module | PowerShell Gallery | Exact module version; `-SkipPublisherCheck` remains required by the existing install path | PowerShell Gallery, PowerShellGet/NuGet transport/package infrastructure, and runner trust |
| PSScriptAnalyzer | Executable PowerShell analysis module | PowerShell Gallery | Exact module version | PowerShell Gallery, PowerShellGet/NuGet transport/package infrastructure, and runner trust |
| Microsoft `dotnet-install.sh` / `.ps1` | Remote executable product dependency | `dotnet/install-scripts` | Official upstream commit `da3ce11ba63f3dbb0fb835d41bda2665d5c48e84`; Git blob provenance and repository-pinned SHA-256 recorded in `.config/remote-artifacts.json`; downloaded from the commit-qualified raw URL and SHA-256 verified before execution | GitHub serving the pinned upstream object and the repository-reviewed digest |
| Microsoft release index and per-channel release metadata | Remote data influencing SDK selection | `builds.dotnet.microsoft.com` mutable metadata endpoints | Structural validation, deterministic error handling, and exact-version selection | Microsoft metadata service/CDN/TLS; metadata can influence which exact versions are offered but is not directly executed |
| .NET SDK payload archive | Executable product payload | Downloaded by the pinned Microsoft install helper from Microsoft distribution infrastructure | Exact requested SDK version; transactional staging; post-install exact-version verification before promotion | **Accepted Issue #22 boundary:** Microsoft payload distribution remains trusted. Independent archive checksum verification is intentionally deferred and can be added later without changing the helper pinning model. |
| Stable `isolated-dotnet-sdk` release scripts | Remote executable product source | Explicit GitHub Release tag | Explicit published tag, deterministic `SHA256SUMS` release asset, checksum verification before execution, and GitHub immutable-release policy for future releases | GitHub release/tag/asset hosting; checksum and script are in the same GitHub trust domain, while immutable releases also provide GitHub release attestations |
| Development `main` bootstrap | Remote executable development source | Mutable repository `main` | Explicitly documented as development-only; never described as the stable channel | Current repository `main` and GitHub raw-content delivery |

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
4. `SHA256SUMS` is attached before publication;
5. the draft is published only after all intended assets are present; and
6. repository release immutability is enabled so the published tag and assets cannot subsequently be moved, replaced, or deleted while the release exists.

Stable bootstrap downloads both the explicitly selected tagged script and that release's `SHA256SUMS`, verifies the selected script before execution, and then relies on the existing file-based bootstrap to preserve the exact verified source. Update and rollback remain explicit selections of another published tag.

GitHub's immutable-release attestation strengthens platform provenance, but the SHA-256 manifest is deliberately not described as an independent signature: both script source and release asset are hosted by GitHub.

`v0.1.0` predates this policy. It has no checksum release asset and was published without release immutability; its existing bytes and publication state are retained as legacy history rather than rewritten retroactively.

## CI/framework boundaries

The existing checkout SHA pin and ShellCheck checksum remain required controls. Bats is already fetched by exact Git commit and checked for its expected version. Pester and PSScriptAnalyzer are installed by exact version from PowerShell Gallery; Issue #22 records that ecosystem/platform trust instead of introducing a bespoke package-signing mechanism or changing framework versions without a demonstrated, practical improvement.
