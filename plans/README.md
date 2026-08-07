# Ratatui Swift Runtime-Hardening Plans

Generated 2026-08-06 after the single-pass `Widget`/`Frame` redesign and `Viewport.fixed(Rect)` migration. Git was initialized after these plans were prepared; the recorded SHA-256 values remain the authoritative pre-implementation drift checks for plans 001–005.

Execute in order. Keep one writer in the workspace. Each executor must read its plan completely, honor STOP conditions, and update the status below.

## Execution order and status

| Plan | Title | Priority | Effort | Depends on | Status |
|---|---|---:|---:|---|---|
| 001 | Main-actor isolate terminal-session lifecycle | P1 | M | — | DONE |
| 002 | Propagate scoped restoration and resume failures | P1 | S–M | 001 | DONE |
| 003 | Recover terminal modes after transaction commit failure | P1 | M | 001, 002 | DONE |
| 004 | Enforce native-scrollback backend semantics | P1 | S | 001–003 | DONE |
| 005 | Honor mapped buffer origins in ANSI history output | P1 | S | 004 | DONE |
| 006 | Preserve fragmented input and suppress stale semantic events | P1 | S | 001–005 | DONE (`85319e1`) |
| 007 | Remove proven text and block construction workarounds | P1 | S–M | 006 | DONE |
| 008 | Migrate public terminal geometry to Swift-native `Int` | P0 | XL | 006, 007 | DONE |
| 009 | Add terminal-column fitting and top-origin row viewport geometry | P0 | M | 008 | DONE |
| 010 | Add lazy, action-aware fixed-height selectable rows | P1 | M | 008, 009 | DONE |
| 011 | Add overflow-aware interactive tabs | P1 | M | 009, 010 | DONE |
| 012 | Pre-0.2 correctness freeze | P0 | M | 008–011 | DONE |
| 013 | Consolidate collection interaction descriptors | P1 | M | 012 | DONE |
| 014 | Adopt stabilized collections in Herdr | P1 | M | 012, 013 | DONE |
| 015 | Bound fitting and viewport work | P1 | M | 012 | DONE |
| 016 | Gate a smaller `TerminalApplication` protocol | P2 | M spike | 012–015 | TODO |
| 017 | Prepare the 0.2 release candidate | P1 | M | 012–016 | TODO |

Status values: `TODO`, `IN PROGRESS`, `DONE`, `BLOCKED: reason`, `REJECTED: reason`.

## Dependency notes

- 001 settles the concurrency owner before lifecycle error paths are rewritten.
- 002 establishes one cleanup/error-precedence policy used by 003.
- 003 hardens the host-level write transaction before backend behavior changes.
- 004 and 005 then tighten the provisional history backend without mixing lifecycle and backend failures in one change.
- 006 is an independent correctness pass over input routing and Observation wakeups.
- 007 follows 006 so its consumer matrix validates on the corrected runtime baseline.
- 008 is the dedicated source-breaking geometry milestone after the lower-risk correctness and ergonomics work.
- 009 adds additive Unicode-safe fitting and viewport projection before larger interactive collection work.
- 010 uses those foundations for visible-only row rendering and exact same-pass interactions.
- 011 applies the same immediate-mode interaction boundary to variable-width horizontal tabs.
- 012 freezes correctness across the recent framework and consumer migrations before further API changes.
- 013 removes duplicate provisional interaction vocabulary rather than adding another abstraction.
- 014 makes Herdr the independent fullscreen adoption proof for the stabilized collection APIs.
- 015 optimizes only measured internal work after semantics are fixed.
- 016 is a design gate, not an assumed implementation; rejection is an acceptable result.
- 017 reconciles documentation and evidence before a 0.2 candidate is tagged.

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

- slim `TerminalApplication` into core requirements plus explicit inline-history and suspended-operation capabilities;
- lazy/full-row-styled large collections exposed by DiffScope;
- fixed-height/top-offset viewport convenience APIs;
- input queue and indexed-color micro-optimizations;
- physical terminal soak and second production native-history backend.

## Findings considered and rejected

- Retained widgets, Ratatui-specific `@State`, and subtree repainting: conflict with the established immediate-mode architecture.
- Moving Git, transcript, HTTP, provider, or Markdown policy into core: application-specific.
- Reverting the single-pass `Frame` redesign: independent review found it coherent and its migrations/tests complete.
