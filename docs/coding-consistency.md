# Coding and naming consistency

This repository shares one product vocabulary across the PowerShell and Bash implementations while preserving normal conventions for each language. Consistency is judged by clarity of concepts and public behavior, not by forcing source-level symmetry.

## Public vocabulary

The stable product actions are install, remove, and list.

- PowerShell exposes them through `-Action Install`, `-Action Remove`, and `-Action List`.
- Bash exposes the corresponding lowercase `install`, `remove`, and `list` subcommands.
- `Version` / version, isolated SDK, SDK root, confirmation, release metadata, and install transaction use the same product terminology where the concepts are shared.

PowerShell parameter casing and Bash positional/option syntax are intentional language idioms. PowerShell-only `-WhatIf` and `-Confirm` remain part of native `ShouldProcess` behavior rather than cross-shell naming targets. Public command, action, parameter, and option names should not be renamed for source-style symmetry.

## PowerShell conventions

Internal PowerShell functions use normal Verb-Noun naming and established PSScriptAnalyzer guidance.

Collection-returning helpers such as `Get-SystemSdkVersion`, `Get-IsolatedSdkVersion`, and `Get-ChannelSdkVersion` intentionally retain singular nouns. PSScriptAnalyzer's command-naming guidance favors singular nouns even when a function can return multiple values. These names are therefore deliberate conventions, not inconsistencies that justify analyzer suppressions or cosmetic plural renames.

Use PascalCase for PowerShell parameters and local variables, and keep script-scoped state explicit with the `script:` scope where that state is intentionally shared across functions.

## Bash conventions

Internal Bash functions use descriptive `snake_case` names. Global configuration/state uses uppercase names; function-local variables use lowercase `snake_case`.

Where a Bash helper represents a specific product concept, prefer the more specific product term over a generic verb. The current consistency pass standardizes these internal names:

- `confirm_action` for tool-owned confirmation;
- `format_support_phase` for release support-phase presentation;
- `install_isolated_sdk` for the isolated-SDK install operation;
- `remove_isolated_sdk` for the isolated-SDK remove operation.

Plural Bash helpers such as `get_system_sdk_versions` and `get_isolated_sdk_versions` remain idiomatic because Bash function names are not subject to PowerShell's singular-noun analyzer convention.

## Cross-shell boundaries

The two implementations do not need identical helper names, control-flow structure, stream mechanics, or casing. Use shared terminology when both sides represent the same product concept, but preserve language-native conventions when they improve readability.

Behavioral parity remains governed by [`behavioral-parity.md`](behavioral-parity.md). Naming cleanup must not change CLI behavior, exit behavior, transaction semantics, confirmation semantics, or platform-specific capabilities.

## Tests, documentation, and enforcement

Tests and user documentation should describe the stable public vocabulary unless a test intentionally targets an internal helper seam. Internal renames should update only those direct references and should not cause public help or documentation churn.

PSScriptAnalyzer and ShellCheck remain the repository-owned static-analysis tools. PowerShell formatting remains governed by [`source-formatting.md`](source-formatting.md); no Bash formatter is added for naming consistency. Analyzer suppressions must not be introduced merely to preserve weak naming choices.

When a difference is only aesthetic and does not materially improve readability, maintainability, parity, or review quality, leave it unchanged.