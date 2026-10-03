# Behavioral contracts

These documents define detailed product behavior and implementation boundaries beyond the task-oriented command pages.

- [PowerShell and Bash behavioral parity](behavioral-parity.md) — shared observable behavior and intentional runtime differences
- [Native-command failure boundaries](native-command-failures.md) — external-command results that are correctness-significant
- [PowerShell removal contract](powershell-removal.md) — PowerShell `ShouldProcess`, `-WhatIf`, `-Confirm`, and removal confirmation semantics

For normal user tasks, start with [Commands](../commands/README.md). Platform-specific syntax belongs in the [getting-started guides](../getting-started/README.md).