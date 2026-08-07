# Plan 016: Gate a smaller TerminalApplication protocol

## Status

- **Priority**: P2
- **Effort**: M spike; implementation conditional
- **Risk**: HIGH
- **Depends on**: plans 012–015
- **Category**: API design gate
- **Planned at**: commit `f282d0a`, 2026-08-07
- **Status**: REJECTED — associated-type capability requires identity erasure or separate runners

## Scope

Spike a minimal body/update/redraw lifecycle plus explicit inline-document, inline-sizing, and suspension capabilities. Test Swift associated-type ergonomics against every existing application. Implement only if clients migrate without rendering type erasure, generic action propagation, or more glue than the current contract.

## Rejection criteria

Reject implementation if capability discovery is ambiguous, associated types spread through widgets, or simple fullscreen applications become harder to express. Preserve the existing protocol and record the evidence instead.

## Result

Rejected for 0.2. The inline runtime must retain one concrete `InlineDocumentRuntime<ID>` across frames, but dynamically
discovering a capability with an associated ID opens an existential whose type cannot be stored across the event loop.
The alternatives require document/identity boxing, separate fullscreen and inline run entry points, or generic propagation.
All add more glue than the current defaulted `InlineDocumentID == Never` contract. Capability-free fullscreen applications
already implement only body/update policy, while Codex is the sole production inline-document and suspension client.
See `Documentation/TerminalApplicationCapabilityGate.md` for the client matrix and evaluated design.
