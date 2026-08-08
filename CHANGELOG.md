# Changelog

All notable public and observable changes are recorded here. Detailed pre-release migration evidence remains in
[`Documentation/APIChanges.md`](Documentation/APIChanges.md).

## 0.2.0-rc.1 — Unreleased

### Highlights

- Replaced separate cell, interaction, and cursor traversals with one immediate `Widget` presentation pass into
  `Frame`.
- Made `StatefulWidget` independent from `Widget` and preserved ordinary modifiers for types that intentionally
  conform to both.
- Migrated public terminal geometry to Swift-native `Int` values with normalization and saturating arithmetic.
- Completed fullscreen, retained-inline, and exact fixed-region viewport ownership, resize, clearing, input, and
  restoration behavior.
- Added Unicode-aware fitting, top- and end-origin viewport geometry, visible-only selectable rows, and
  overflow-aware interactive tabs.
- Hardened terminal-session isolation, cleanup error propagation, failed frame-transaction recovery, fragmented
  input continuity, Observation wakeups, and native-scrollback capability semantics.
- Kept optional syntax highlighting, test support, overlays, multiline editing, DevTools, and macro ergonomics behind
  traits or independent packages.

### Breaking migrations

- Implement `Widget.render(in:into: inout Frame)` and emit cells, interactions, and cursor metadata from that pass.
- Use Swift `Int` directly for public positions, sizes, rectangles, constraints, offsets, and viewport heights.
- Replace provisional `RowInteraction` and `TabInteraction` values with `InteractionDescriptor`.
- Treat `StatefulWidget` as an independent protocol; add `Widget` conformance only when stateless presentation is
  meaningful.
- Create and operate `TerminalSession` from main-actor code.
- Resize session-owned fixed terminals through `TerminalSession.resizeFixedViewport(to:terminal:)`; reserve
  `Terminal.resize(to:)` for manually owned fixed terminals.

### Validation target

The candidate is gated by strict formatting, the complete TermLoom/ecosystem/consumer suites, an exact public API
baseline, release benchmark JSON smoke, PTY lifecycle coverage, and inline/fullscreen/fixed real-terminal smokes. See
[`Documentation/ReleaseChecklist-0.2.md`](Documentation/ReleaseChecklist-0.2.md).
