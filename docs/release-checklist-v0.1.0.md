# v0.1.0 Release Checklist

- [x] Define initial semantic version as `v0.1.0`.
- [x] Add changelog entry.
- [x] Add release notes.
- [x] Add cross-platform validation workflow.
- [x] Confirm validation workflow passes on Linux, macOS, and Windows.
- [x] Make tagged-source bootstrap reproducible so a script executed from a tagged checkout installs that same script rather than refreshing from `main`.
- [ ] Merge the release preparation changes to `main`.
- [ ] Create tag `v0.1.0` from the verified release commit.
- [ ] Publish the GitHub Release using `docs/release-notes/v0.1.0.md`.
