# Testing and validation

- [Testing](testing.md) — frameworks, test taxonomy, local commands, CI overview, and deterministic-versus-live validation
- [CI validation architecture](ci-validation.md) — workflow responsibility split, setup scripts, caches, and timing expectations
- [Real end-to-end validation](e2e-testing.md) — live Microsoft/.NET lifecycle coverage
- [Interactive lifecycle testing](interactive-testing.md) — deterministic menu/navigation coverage
- [Static analysis](static-analysis.md) — PSScriptAnalyzer and ShellCheck scope and policy

Product behavioral authority remains in the [command documentation](../../commands/README.md) and [behavioral contracts](../../contracts/README.md); tests protect those contracts rather than redefining them.