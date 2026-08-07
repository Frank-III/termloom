# Plan 004: Enforce native-scrollback backend semantics

> **Executor instructions**: Execute after lifecycle/transaction hardening. Do not silently substitute visual scrolling for native history. Update `plans/README.md` when complete.
>
> **Drift check**: `Sources/Ratatui/Backend.swift` SHA-256 was `4c29c4dfe3bef32ac6fd9198727b7243b0c75cf1bd995fa5110d19b1c87e93bf`. Confirm the extension still forwards `scrollRegionUpIntoScrollback` to `scrollRegionUp`; otherwise STOP and reassess.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: MED
- **Depends on**: plans 001–003
- **Category**: correctness / API
- **Planned at**: source archive without Git metadata, 2026-08-06

## Why this matters

The protocol explicitly distinguishes native-scrollback retention from visual CSI scrolling, but its default implementation calls the visual operation. A conformer can therefore compile and silently discard displaced history on affected terminals.

## Current state

- `Sources/Ratatui/Backend.swift:93-96` documents the semantic guarantee.
- `Sources/Ratatui/Backend.swift:151-155` violates it by forwarding to `scrollRegionUp`.
- `Terminal.insertBefore` relies on the stronger operation for generic inline insertion.
- ANSIBackend and TestBackend already provide explicit implementations; the test-only `RecordingNativeHistoryBackend` also declares the method.

## Scope

**In scope**:

- `Sources/Ratatui/Backend.swift`
- `Sources/Ratatui/Terminal.swift` only if unsupported handling needs clarification
- Ratatui backend/history tests
- API stability/change docs and baseline

**Out of scope**:

- adding another production backend in this plan
- changing Ghostty/Supaterm history strategy
- moving history into base `Backend`
- application-specific transcript behavior

## Steps

### 1. Replace the unsafe default

Prefer a source-compatible default that throws `BackendOperationError.unsupported("native scrollback insertion")`. Alternatively remove the default only if all external consumer migration and API review support the source break. Never forward to visual `scrollRegionUp`.

**Verify**:

```sh
rg -n 'scrollRegionUpIntoScrollback' Sources Tests Packages Examples
```

Expected: every backend claiming support either implements the semantic operation or intentionally receives the throwing default.

### 2. Test the contract

Add a minimal `InlineHistoryBackend` that implements visual region scrolling but not native-scrollback scrolling. Trigger generic `Terminal.insertBefore` and assert it throws unsupported instead of recording a visual scroll as history.

Keep existing independent batch-position model tests passing.

**Verify**:

```sh
swift test --filter BackendTests
swift test --filter HistoryPreparationTests
swift test --filter InlineInsertionTests
```

Expected: all pass.

### 3. Document provisional behavior

Clarify that conforming to `InlineHistoryBackend` does not imply every optional fast path succeeds, but generic fallback requires a real native-scrollback implementation. Keep the protocol provisional pending a second production backend.

**Verify**:

```sh
Scripts/check-api.sh
```

Expected: zero pending additions; any intentional default-implementation relationship change is reviewed and recorded.

## Done criteria

- [ ] No default maps native-scrollback semantics to visual scrolling.
- [ ] Unsupported conformers fail explicitly.
- [ ] ANSIBackend and TestBackend keep their intended behavior.
- [ ] Batch and insertion tests pass.
- [ ] API migration is documented.

## STOP conditions

- A consumer depends on silently discarding history.
- The fix would require moving native history into base `Backend`.
- The only proposed implementation uses synchronized-output-wrapped CRLF history.

## Maintenance notes

When a second production backend arrives, compare actual transaction vocabulary before stabilizing `InlineHistoryBackend`; do not weaken this semantic guarantee for easier conformance.
