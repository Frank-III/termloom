# Plan 016: Gate a smaller TerminalApplication protocol

## Status

- **Priority**: P2
- **Effort**: M spike; implementation conditional
- **Risk**: HIGH
- **Depends on**: plans 012–015
- **Category**: API design gate

## Scope

Spike a minimal body/update/redraw lifecycle plus explicit inline-document, inline-sizing, and suspension capabilities. Test Swift associated-type ergonomics against every existing application. Implement only if clients migrate without rendering type erasure, generic action propagation, or more glue than the current contract.

## Rejection criteria

Reject implementation if capability discovery is ambiguous, associated types spread through widgets, or simple fullscreen applications become harder to express. Preserve the existing protocol and record the evidence instead.
