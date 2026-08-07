# Ratatui Swift Runtime-Hardening Plans

Generated 2026-08-06 after the single-pass `Widget`/`Frame` redesign and `Viewport.fixed(Rect)` migration. Git was initialized after these plans were prepared; the recorded SHA-256 values remain the authoritative pre-implementation drift checks for plans 001–005.

Execute in order. Keep one writer in the workspace. Each executor must read its plan completely, honor STOP conditions, and update the status below.

## Execution order and status

| Plan | Title | Priority | Effort | Depends on | Status |
|---|---|---:|---:|---|---|
| 001 | Main-actor isolate terminal-session lifecycle | P1 | M | — | DONE |
| 002 | Propagate scoped restoration and resume failures | P1 | S–M | 001 | DONE |
| 003 | Recover terminal modes after transaction commit failure | P1 | M | 001, 002 | DONE |
| 004 | Enforce native-scrollback backend semantics | P1 | S | 001–003 | TODO |
| 005 | Honor mapped buffer origins in ANSI history output | P1 | S | 004 | TODO |

Status values: `TODO`, `IN PROGRESS`, `DONE`, `BLOCKED: reason`, `REJECTED: reason`.

## Dependency notes

- 001 settles the concurrency owner before lifecycle error paths are rewritten.
- 002 establishes one cleanup/error-precedence policy used by 003.
- 003 hardens the host-level write transaction before backend behavior changes.
- 004 and 005 then tighten the provisional history backend without mixing lifecycle and backend failures in one change.

## Required final matrix

After plan 005, run from `/Users/new/projects/learn_swift/ratetui-swift`:

```sh
swift format lint --strict --recursive Package.swift Sources Tests
swift test
Scripts/check-api.sh
Scripts/test-ecosystem.sh
Scripts/test-consumers.sh
```

Expected: every command exits 0; API baseline reports zero pending additions. Also verify the protected KWWK checkout remains unchanged:

```sh
cd /Users/new/projects/learn_swift/kwwk
shasum -a 256 Sources/KWWKCli/CodingTUI.swift
git diff -- Sources/KWWKCli/CodingTUI.swift | shasum -a 256
```

Expected hashes:

- file: `a9991f75c26e6388b80be2d0b8754f93d98aca5e15219ce95663af7be9e09851`
- diff: `08ad62999ee3160ef1b4d8d8285973312671fb3d56d9349dc12498b27a01d3f2`

## Deferred follow-ups

These are not part of plans 001–005:

- synchronize `Terminal.resize(to:)` with a caller-owned `TerminalSession` fixed viewport;
- lazy/full-row-styled large collections exposed by DiffScope;
- fixed-height/top-offset viewport convenience APIs;
- input queue and indexed-color micro-optimizations;
- physical terminal soak and second production native-history backend.

## Findings considered and rejected

- Retained widgets, Ratatui-specific `@State`, and subtree repainting: conflict with the established immediate-mode architecture.
- Moving Git, transcript, HTTP, provider, or Markdown policy into core: application-specific.
- Reverting the single-pass `Frame` redesign: independent review found it coherent and its migrations/tests complete.
