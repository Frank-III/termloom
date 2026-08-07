# Plan 001: Main-actor isolate terminal-session lifecycle

> **Executor instructions**: Follow every step and verification gate. Do not broaden this into a general concurrency rewrite. Update `plans/README.md` when complete.
>
> **Drift check**: run:
>
> ```sh
> cd /Users/new/projects/learn_swift/ratetui-swift
> shasum -a 256 Sources/Ratatui/TerminalSession.swift Sources/Ratatui/Application.swift Documentation/APIStability.md
> ```
>
> Expected first hash: `6c3076bb5f93034c0b93077bcd23e9ec4be5604695b20287b32891cb41e45c0f`. If it differs, compare the current declarations below and STOP if lifecycle isolation was already redesigned or new cross-actor callers exist.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: HIGH — public concurrency contract
- **Depends on**: none
- **Category**: correctness / API
- **Planned at**: source archive without Git metadata, 2026-08-06

## Why this matters

`TerminalSession` promises `Sendable` through `@unchecked Sendable`, but only its output buffer is locked. Viewport, lifecycle, termios, prefetched input, and size state are mutable and unsynchronized. `Documentation/APIStability.md` already says terminal lifecycle is main-actor isolated, so the implementation and compiler contract must agree before `0.2`.

## Current state

- `Sources/Ratatui/TerminalSession.swift:85` declares `public final class TerminalSession: @unchecked Sendable`.
- Mutable fields at lines 89–100 include `viewport`, `lifecycleState`, `prefetchedInput`, `lastWindowSize`, and `viewportOrigin`.
- Lifecycle/session methods are synchronous and unisolated.
- `Sources/Ratatui/Application.swift` already runs `TerminalApplication` on `@MainActor`; blocking input is isolated in `AsyncInputPump` and must remain there.
- The redesigned `Widget`/`Frame` architecture is unrelated and must not change.

## Scope

**In scope**:

- `Sources/Ratatui/TerminalSession.swift`
- `Sources/Ratatui/Application.swift` only for compiler-required call-site isolation
- terminal/session tests under `Tests/RatatuiTests/`
- `Documentation/APIStability.md`, `Documentation/APIChanges.md`
- `Documentation/API/Ratatui.json` only through reviewed baseline update

**Out of scope**:

- `Widget`, `StatefulWidget`, `Frame`, `Buffer`, or rendering APIs
- changing `TerminalInput` away from a detached blocking pump
- locking every session field instead of choosing one actor owner
- Codex, Herdr, KWWK, or example product behavior except compiler-required migration

## Steps

### 1. Establish compiler-enforced ownership

Make `TerminalSession` main-actor isolated and remove `@unchecked Sendable`. Mark both public `withTerminalSession` helpers consistently so they cannot manufacture an unisolated session. Preserve `TransactionalTerminalOutput` as the separately lock-isolated Sendable output primitive.

If Swift 6.2 requires explicit isolated deinitialization, use the supported language form. Do not bypass isolation with `nonisolated(unsafe)` or another unchecked conformance.

**Verify**:

```sh
swift build --disable-default-traits --product Ratatui
```

Expected: exit 0 with no concurrency warnings/errors.

### 2. Repair only required call sites

Keep application state and session lifecycle on `@MainActor`. Keep `TerminalInput` inside `AsyncInputPump`; do not move blocking `poll`/`read` onto the main actor. Any synchronization helper accepting `TerminalSession` must be called from main-actor code even if it locks the input value internally.

**Verify**:

```sh
swift test --filter PTYIntegrationTests
```

Expected: all PTY integration tests pass.

### 3. Record the public concurrency migration

Update API stability/change docs to state that `TerminalSession` lifecycle is compiler-enforced main-actor state, while terminal input polling/output sink synchronization remain explicitly isolated implementation pieces. Update the API baseline only after reviewing the symbol change.

**Verify**:

```sh
Scripts/check-api.sh
```

Expected: zero pending additions and no unreviewed breaking change.

## Test plan

- Preserve existing real-PTY session lifecycle tests.
- Add a focused runtime test proving main-actor session creation/use still supports inline, fullscreen, and fixed viewports.
- Rely on Swift 6 compilation of Codex/Herdr for cross-actor contract verification; do not add tests that use unsafe concurrency escape hatches.

## Done criteria

- [ ] `TerminalSession` is not `@unchecked Sendable`.
- [ ] Mutable session lifecycle is compiler-isolated to `@MainActor`.
- [ ] `AsyncInputPump` still performs blocking input away from the main actor.
- [ ] Ratatui, ecosystem, Codex, and Herdr compile and test.
- [ ] API migration is documented and baseline reviewed.

## STOP conditions

- Swift 6.2 cannot express an isolated deinitializer without an unsafe escape.
- A production consumer intentionally mutates one `TerminalSession` concurrently from multiple actors.
- Fixing compilation appears to require moving `poll` or `read` onto the main actor.
- KWWK would need modification.

## Maintenance notes

Reviewers should reject any replacement `@unchecked Sendable` or scattered-lock solution. The ownership rule should be simple: session lifecycle on the main actor; blocking input and locked output are separate transport primitives.
