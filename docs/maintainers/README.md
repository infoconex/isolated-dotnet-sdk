# Maintainer documentation

These documents are for repository development, validation, dependency maintenance, issue execution, and release publication. User-facing installation and command guidance lives outside this section.

## Development standards

- [Development operating model](development/operating-model.md)
- [Post-v0.3.0 project retrospective — October 2026](development/retrospective-2026-10.md)
- [Coding and naming consistency](development/coding-consistency.md)
- [Source formatting](development/source-formatting.md)
- [List enrichment evaluation](development/list-enrichment-evaluation.md)

The operating model is the durable authority for development principles, decision authority, the current hardening posture, context discipline, and next-release integration. The retrospective records the reasoning that led to those rules.

## Testing and validation

- [Testing index](testing/README.md)
- [Testing](testing/testing.md)
- [CI validation architecture](testing/ci-validation.md)
- [Real end-to-end validation](testing/e2e-testing.md)
- [Interactive lifecycle testing](testing/interactive-testing.md)
- [Static analysis](testing/static-analysis.md)

## Dependencies

- [Dependency update monitoring](dependencies/dependency-update-monitoring.md)

## Releases

- [Stable release publication and verification](releases/release-process.md)

User-facing stable installation/update/rollback policy is separate: [Stable bootstrap, update, and rollback](../releases/stable-bootstrap.md).

## Issue lifecycle

- [Issue execution workflow](issues/issue-workflow.md)
- [Issue and pull request conventions](issues/issue-conventions.md)
