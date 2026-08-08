# Plan 017: Prepare the 0.2 release candidate

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MEDIUM
- **Depends on**: plans 012–016
- **Category**: documentation / release

## Scope

Reconcile architecture, performance, ecosystem, API stability, and API change documents with the single-pass `Frame` design and capability facets. Remove stale multi-pass claims. Run the complete framework, package, consumer, PTY, and physical-terminal matrix. Review every public symbol addition/removal and prepare a 0.2 candidate tag only after clean evidence.

## Non-goals

No new major feature, sixth demo, retained reconciliation, generic menu, or inline/fullscreen transition implementation.

## Progress

- Architecture, API, migration, performance, ecosystem, parity, testing, macro, changelog, and release-checklist text is
  reconciled with the single-pass `Frame` implementation.
- Strict formatting, 269 core tests plus 3 syntax tests, the complete ecosystem matrix, Codex's 160 tests, Motel's 14
  tests, Herdr's 91 tests, the 1,540-symbol API baseline with zero additions, and all 26 benchmark-smoke scenarios pass.
- Automated PTY and `terminal-control` 0.4.1 supplemental inline/fullscreen/fixed smokes pass.
- Public repository and MIT license metadata are resolved. The remaining release blocker is a fresh physical-terminal
  attestation; synthetic Supaterm input did not reach the terminal surface during automated smoke setup.

## Done criteria

Documents describe the shipped system, API baseline has no unreviewed additions, all repositories are clean, physical evidence is recorded, and the candidate is ready to tag.
