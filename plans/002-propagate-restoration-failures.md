# Plan 002: Propagate scoped restoration and resume failures

> **Executor instructions**: Execute after plan 001. Preserve the original operation error and make cleanup failure observable. Update `plans/README.md` when complete.
>
> **Drift check**: verify `Sources/TermLoom/TerminalSession.swift` still contains `defer { try? session.restore() }` in both `withTerminalSession` overloads and `try? resume()` in `withRestoredTerminal`. If not, STOP and reassess.

## Status

- **Priority**: P1
- **Effort**: S–M
- **Risk**: MED
- **Depends on**: `plans/001-main-actor-terminal-session.md`
- **Category**: correctness
- **Planned at**: source archive without Git metadata, 2026-08-06

## Why this matters

A successful scoped operation can currently return success even if terminal restoration fails, leaving raw mode or protocols active. When both the operation and cleanup fail, the cleanup failure is discarded entirely. Terminal ownership needs one deterministic, documented error-precedence policy.

## Current state

- `Sources/TermLoom/TerminalSession.swift:567-585` suppresses `restore()` errors in both public scope helpers.
- `withRestoredTerminal` suppresses `resume()` failure when its body throws.
- `suspend()` can fail in termios restoration or protocol output, so these are real error paths.

## Scope

**In scope**:

- `Sources/TermLoom/TerminalSession.swift`
- `Tests/TermLoomTests/PTYIntegrationTests.swift` or a new focused lifecycle test file
- `Documentation/APIChanges.md`, `Documentation/Architecture.md`
- API baseline only if a public error wrapper is added

**Out of scope**:

- transaction commit recovery (plan 003)
- backend/history behavior
- Widget/Frame APIs
- swallowing errors merely to preserve old behavior

## Steps

### 1. Define one cleanup policy

Implement shared synchronous and asynchronous scoped-cleanup helpers with these semantics:

1. body succeeds, cleanup succeeds → return body result;
2. body succeeds, cleanup fails → throw cleanup error;
3. body fails, cleanup succeeds → throw body error;
4. body fails, cleanup fails → throw an error that preserves both failures.

Use a small public lifecycle/scope error only if callers need to inspect both errors; otherwise use an internal wrapper that still exposes both through `LocalizedError`. Do not erase one failure.

**Verify**:

```sh
swift test --filter PTYIntegrationTests
```

Expected: all tests pass.

### 2. Route every scoped lifecycle through the policy

Apply it to:

- synchronous `withTerminalSession`;
- asynchronous `withTerminalSession`;
- `withRestoredTerminal` using `resume` as cleanup.

Keep `deinit` best-effort because it cannot throw; deterministic public scopes must not be best-effort.

**Verify**:

```sh
rg -n 'defer \{ try\? session\.restore\(\) \}|try\? resume\(\)' Sources/TermLoom/TerminalSession.swift
```

Expected: no matches in public scoped helpers; a best-effort deinit or failure-recovery path may remain with an explanatory comment.

### 3. Add deterministic failure tests

Add an internal generic cleanup helper or injectable test seam so tests can synthesize body and cleanup failures without depending on nondeterministic PTY write failure. Cover all four cases and assert both errors survive case 4.

**Verify**:

```sh
swift test --filter TerminalSession
```

Expected: all matching tests pass, including four new precedence cases.

### 4. Document behavior and review API

Record the error policy in API changes and session documentation. If the public symbol graph changes, update it deliberately.

**Verify**:

```sh
swift format lint --strict --recursive Package.swift Sources Tests
Scripts/check-api.sh
```

Expected: both exit 0; zero pending additions.

## Done criteria

- [x] Successful bodies cannot conceal failed restoration.
- [x] Dual failures retain both errors.
- [x] Sync, async, and suspended-action scopes share one policy.
- [x] Deinit remains explicitly best-effort.
- [x] Tests cover all four body/cleanup outcomes.

## STOP conditions

- The implementation would expose terminal-control bytes or secret data in errors.
- Testing requires changing public initializers solely for injection.
- Plan 001 actor ownership has not landed.

## Maintenance notes

Future lifecycle operations must use the same policy. Reviewers should search for new `try? restore`, `try? resume`, or cleanup-only `defer` blocks in throwing public scopes.
