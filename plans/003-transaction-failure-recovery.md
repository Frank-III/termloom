# Plan 003: Recover terminal modes after frame transaction commit failure

> **Executor instructions**: Execute after plans 001–002. Keep native-scrollback-producing line feeds outside synchronized-output mode. Update `plans/README.md` when complete.
>
> **Drift check**: `TransactionalTerminalOutput.withTransaction` must still commit buffered data through one `FileHandle.write(contentsOf:)` and clear only memory in its catch path. `ANSIBackend.insertHistory` must still finalize history state after its buffered writer returns. Otherwise STOP.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: plans 001, 002
- **Category**: correctness
- **Planned at**: source archive without Git metadata, 2026-08-06

## Why this matters

The host-level frame transaction buffers viewport mutation, native history, and final draw. If the final physical write partially succeeds and throws, the current catch only discards memory. The terminal may remain in synchronized output, scoped margins, disabled autowrap, or active styling, while in-memory viewport/history state may already have advanced.

## Current state

- `Sources/TermLoom/TerminalSession.swift:54-76` commits the complete buffered frame at the end of `withTransaction`.
- `Sources/TermLoom/ANSIBackend.swift:286-357` can buffer margin, autowrap, history, synchronized-output, and origin changes.
- Normal `restoreSequence` does not defensively end synchronized output, reset margins, enable wrapping, and reset SGR.
- Native history line feeds intentionally remain outside `CSI ?2026`; preserve this.

## Scope

**In scope**:

- `Sources/TermLoom/TerminalSession.swift`
- `Sources/TermLoom/Application.swift` only if state publication must move after physical commit
- `Sources/TermLoom/ANSIBackend.swift` only for rollback/publication coordination
- `Tests/TermLoomTests/PTYIntegrationTests.swift`
- `Tests/TermLoomTests/BackendTests.swift`
- architecture/API-change documentation

**Out of scope**:

- wrapping native history in synchronized output
- changing ordinary successful terminal bytes
- retrying arbitrary application renders automatically
- changing Widget/Frame APIs

## Steps

### 1. Add an unbuffered emergency epilogue

When the final transaction write throws, make one best-effort direct write that cannot be appended back into the failed buffer. It must at least:

- end synchronized output (`CSI ?2026l`);
- reset scrolling margins (`CSI r`);
- reset SGR (`CSI 0m`);
- enable autowrap (`CSI ?7h`);
- restore cursor visibility/protocol balance as appropriate to the session cleanup path.

Preserve and throw the original commit error; cleanup failure is secondary and follows plan 002’s error policy where representable.

**Verify**: add a deterministic sink test where the first commit writes a prefix then throws and the emergency write succeeds. Assert the epilogue is attempted outside the buffered payload.

### 2. Prevent premature logical publication

Audit state mutated during the buffered operation: `Terminal` diff buffers/backend origin, `TerminalSession.viewportOrigin`, dynamic viewport height, and ANSI history batch state. Ensure state that claims physical commit is published only after the outer write succeeds, or restore a pre-transaction value snapshot on failure.

Do not invent a generic retained transaction framework. Keep rollback scoped to terminal/session value state.

**Verify**: a failed transaction followed by a successful retry must emit a complete valid frame/history operation and must not skip rows based on the failed logical origin.

### 3. Make final restoration defensive

Add the safe terminal-mode epilogue to final restoration as defense in depth, without altering fixed/fullscreen/inline cursor placement semantics.

**Verify**:

```sh
swift test --filter PTYIntegrationTests
swift test --filter BackendTests
```

Expected: all pass, including new failure/retry tests.

### 4. Re-run the flicker invariants

Ensure ordinary successful frame transactions still use one host write and that scrollback-producing CRLF bytes remain outside synchronized output.

**Verify**:

```sh
swift test --filter frameOutputTransactionCommitsViewportChangeAndReplacementDrawTogether
swift test --filter terminalRestoresLiveViewportInTheFinalHistoryWrite
```

Expected: both pass.

## Done criteria

- [x] Commit failure attempts an unbuffered defensive epilogue.
- [x] Original commit error remains authoritative.
- [x] Failed logical terminal/history state is not treated as committed.
- [x] A subsequent retry is complete and valid.
- [x] Successful byte ordering and native-scrollback invariants are unchanged.

## STOP conditions

- The proposed fix requires putting native history line feeds inside synchronized output.
- Rollback requires retained widget/application state.
- A retry can only work by rendering the widget twice during successful frames.
- KWWK or Codex semantic state would need modification.

## Maintenance notes

Any future escape sequence that opens a scoped terminal mode must be represented in the emergency epilogue or proven self-contained before physical commit.
