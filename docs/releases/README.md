# Releases

## Stable bootstrap

The normal stable installation/update path resolves the latest published stable release at bootstrap time:

```powershell
irm https://infoconex.github.io/isolated-dotnet-sdk/install.ps1 | iex
```

```bash
curl -fsSL https://infoconex.github.io/isolated-dotnet-sdk/install.sh | bash
```

Use [Stable bootstrap, update, and rollback](stable-bootstrap.md) for the trust model, explicit pinned-version procedure, update behavior, and rollback guidance. Platform-specific usage continues in:

- [Windows / PowerShell 7](../getting-started/windows-powershell.md#install-or-update-the-stable-tool)
- [Linux or macOS / Bash](../getting-started/linux-macos-bash.md#install-or-update-the-stable-tool)

## Release history

Release-history pages summarize each published stable release for users. For the chronological categorized change log, see the project [CHANGELOG](../../CHANGELOG.md).

- [v0.2.0 release history](history/v0.2.0.md) — first stable release under the checksum-verifying release policy.
- [v0.1.0 release history](history/v0.1.0.md) — initial release and legacy pre-checksum-policy behavior.

The [v0.1.0 release checklist](history/v0.1.0-checklist.md) remains available as legacy release-process history.

## Maintainers

Publication and post-publication verification procedure is intentionally separate from user bootstrap guidance. Maintainers should use [Stable release publication and verification](../maintainers/releases/release-process.md).
