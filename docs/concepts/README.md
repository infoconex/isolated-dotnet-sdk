# Concepts

These documents explain the technical model behind the user-facing commands.

- [Cross-platform support](cross-platform-support.md) — supported OS/shell mappings and platform mechanics
- [Filesystem safety](filesystem-safety.md) — isolated-root ownership, staging, cleanup, and recovery boundaries
- [SDK discovery and release metadata](sdk-discovery.md) — channel/version discovery and exact-version metadata responsibilities
- [Bootstrap source preservation and reproducibility](bootstrap-reproducibility.md) — how file-based bootstrap preserves source identity
- [Supply-chain integrity and trust boundaries](supply-chain-integrity.md) — remote artifacts, checksums, and residual trust

For operation semantics, start with [Commands](../commands/README.md). For stricter implementation-independent behavior, see [Behavioral contracts](../contracts/README.md).