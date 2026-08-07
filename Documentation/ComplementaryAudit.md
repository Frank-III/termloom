# Ratatui Swift + Codex Swift complementary audit

Behavioral baselines:

- OpenAI Codex: `e428a12d2235fe2bc10b10bc45d245d1f491f3c7`
- Ratatui Rust: local `ratatui-core` terminal/inline/resize implementations
- Installed Codex CLI: `0.146.0`
- Terminal hosts: PTY transport plus attested Supaterm/Ghostty-family behavior

The audit treats Codex Swift as a stress client, not an API template. A defect belongs in Ratatui only
when it is reusable terminal, rendering, editing, focus, geometry, or lifecycle mechanics.

## Fixed findings

| Severity | Finding | Ownership | Resolution and evidence |
| --- | --- | --- | --- |
| High | Backend/viewport rebuilds discarded queued input and replayed cursor-probe leftovers | Ratatui runtime | One input pump is rebased in place; probe leftovers transfer once and consecutive probes append. Real application-loop PTY tests send burst input across a history reset. |
| High | History reset repeatedly pushed Kitty keyboard enhancement state | Ratatui terminal lifecycle | Protocol enablement is session/resume scoped; reanchoring does not push again. PTY output asserts one push and one pop across reset. |
| High | Observable values first read inside `Widget.render` did not invalidate frames | Ratatui runtime | The full terminal draw transaction is Observation-tracked. A PTY application mutates render-only observable state while idle and emits the new frame. |
| High | Large-paste labels were editable strings and payload expansion depended on label equality | Ratatui editing mechanics + Codex policy | `TextFieldState` now owns identified atomic elements; Codex associates paste payloads with IDs. Motion skips interiors, deletion is whole-element, unrelated mention/Vim edits preserve ranges, and payload boundary whitespace is exact. |
| High | A local `!command` could mark an active model turn idle | Codex semantics | Local process activity no longer overwrites agent working state; cancellation remains available after the shell cell completes. |
| Medium | Mouse coordinates used the original inline origin after history insertion | Ratatui input/viewport mechanics | Input localization rebases whenever insertion, resize, or dynamic sizing moves the viewport. PTY tests preserve already-queued coordinates and localize future mouse reports against the new origin. |
| Medium | Dynamic sizing/reset recreated focus state | Ratatui interaction mechanics | Stable `InteractionRouter` state survives backend reconstruction. An integrated PTY trace tabs to the second control, resets history, and retains that focus. |
| Medium | Updates returned from synthetic focus events were ignored | Ratatui application effects | Focus-reconciliation updates now interpret clear/reset/suspend/quit effects like ordinary routed events. A PTY application quits from its initial focus event. |
| Medium | Stateful widgets could not derive cursor style from state | Ratatui rendering API | `StatefulWidget` has a state-aware cursor-style hook and `Frame.render(state:)` forwards it. |
| Medium | ANSI fallback sizing ignored inline viewport height | Ratatui backend | Drawable fallback height is clamped while `windowSize()` retains physical fallback dimensions. |
| Medium | Cursor reports split across reads caused fallback anchoring and leaked CPR events | Ratatui terminal lifecycle | Cursor probing accumulates fragments to a deadline and preserves only unrelated input. |
| Medium | Model selection persisted before reasoning confirmation | Codex semantics | Candidate model and effort commit together through one driver operation only after final confirmation; Escape leaves runtime state unchanged. |
| Medium | Active-turn settings appeared accepted although the driver rejected them | Codex semantics | Menus remain open and display an explicit active-turn rejection. |
| Medium | `/status` always used a stale default context percentage | Codex semantics | Status reads the live driver/compactor usage snapshot. |
| Medium | Editable replacement overlays hid the hardware caret | Codex presentation | Freeform/notes, model/theme/keymap/session search, rename, and history search expose steady-bar cursor geometry with terminal-width-aware columns. |
| Medium | Skill/file picker behavior diverged in ranking and keys | Codex interaction using Ratatui geometry | Fuzzy ranking, wrapping Up/Down, Ctrl-P/Ctrl-N, Tab acceptance, cursor-on-sigil recognition, measured popup height, and variable-row visibility are covered. |

## Boundary decisions

- `InlineDocument` remains framework-owned because append tracking, width replay, rewrite detection, and
  viewport reset coordination are terminal/document lifecycle mechanics. Markdown stability and canonical
  transcript source remain in Codex.
- `SelectionViewport` remains framework-owned pure geometry. Filtering, fuzzy ranking, item identity,
  insertion text, and footer wording remain in Codex.
- Atomic text elements are framework editing mechanics. Ratatui does not know what a paste, attachment,
  mention, or hidden payload means.
- `InlineViewportSizing` remains opt-in rather than enlarging every `TerminalApplication`.
- Native history insertion remains distinct from visual CSI `S` scrolling.

## Intentional or deferred work

1. **Full-terminal transcript pager:** Ctrl-T currently occupies the retained inline surface and is capped
   at 22 rows. A safe inline-to-alternate-screen transition belongs in Ratatui lifecycle work.
2. **Mention dismissal policy:** Swift currently reopens after cursor re-entry, matching the prior product
   requirement. Upstream retains a dismissed-token sentinel. This is an intentional documented divergence.
3. **Menu/popup presenter:** `SelectionViewport` is proven, but a complete policy-free presenter should be
   validated by a second client before becoming public framework API.
4. **Backend capability facets:** Core drawing, cursor control, alternate screen, inline viewport, and native
   history remain combined in `Backend`; splitting them is major-version work.
5. **One-pass rendering:** Cells, interactions, cursor position, and cursor style still use separate
   traversals. Containers are tested for forwarding, but a single render context is the long-term design.
6. **Explicit scrollback destruction:** `.resetTerminalHistory` deliberately uses CSI `3J`; ordinary
   `.clearViewport` cannot trigger it, but explicit reset still removes unrelated shell scrollback.
7. **Unsupported insertion outcome:** `Terminal.insertBefore` still silently no-ops without required backend
   capabilities. A typed handled/unsupported result should precede capability-protocol extraction.
8. **Terminal matrix:** PTYs validate bytes, termios, origins, modes, and application lifecycle but do not
   emulate native scrollback or reflow. Standard terminals, Ghostty-family hosts, and tmux/Zellij still need
   ongoing physical smoke coverage. `terminal-control` 0.4.1 is usable; 0.6.0 currently fails in its
   `libghostty-vt` Zig/macOS SDK build.

## Verification

Automated coverage includes:

- Ratatui core and syntax suites under strict Swift formatting.
- Codex Swift full suite under strict Swift formatting.
- Real `openpty` application-loop traces for Observation, focus effects, burst input across reset, cursor
  probe fragmentation, resume/reset prefetched input, dynamic viewport overflow, mouse rebasing, protocol
  balance, raw-mode restoration, and resize handling.
- Atomic-element editing, multiple paste identity, exact whitespace payloads, Vim deletion, mention editing,
  popup selection/ranking/measurement, overlay cursors, active-shell state, and model/reasoning cancellation.
- Protected KWWK diff SHA-256 remains
  `08ad62999ee3160ef1b4d8d8285973312671fb3d56d9349dc12498b27a01d3f2`.

Physical Supaterm checks performed during this goal retained `PRESERVE-01…PRESERVE-80` in native
scrollback and rendered `INLINE-001…INLINE-060` exactly once during a real streaming turn. These attest
the host-specific history strategy; automated PTY tests cover the deterministic protocol invariants.
