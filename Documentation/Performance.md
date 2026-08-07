# Performance benchmarks

`ratatui-benchmark` measures immediate-mode frame construction, changed-cell output, public primitives, and real
ANSI byte volume. Run benchmarks in release mode:

```sh
swift run -c release ratatui-benchmark -- --suite all --iterations 1000
swift run -c release ratatui-benchmark -- --suite all --iterations 1000 --json > benchmark.json
```

Available suites are `frames`, `primitives`, `output`, and `all`. The default remains `frames`, and a bare integer
continues to set the iteration count.

## Upstream methodology

The primitive suite follows the shape of Ratatui Rust's Criterion benchmarks in:

- `guided/ratatui/ratatui/benches/main/buffer.rs`
- `guided/ratatui/ratatui/benches/main/constraints.rs`
- `guided/ratatui/ratatui/benches/main/paragraph.rs`
- `guided/ratatui/ratatui/benches/main/table.rs`

The Swift benchmark uses deterministic text instead of random fixtures and adds application-loop concerns that the
core Rust microbenchmarks do not measure: buffer diff density, cursor-only frames, interaction collection, Swift
Observation tracking, and bytes written by `ANSIBackend`.

## Metrics

Each result reports:

- elapsed nanoseconds and iterations per second;
- changed cells per frame where a terminal is involved;
- bytes written per frame for ANSI scenarios;
- retained allocator bytes before versus after the scenario on Darwin;
- process peak RSS on Darwin.

Retained bytes are not total allocation traffic, and peak RSS is cumulative for the process. Use them to catch
large retention regressions, not as exact allocation counts. Run suites in separate processes when comparing peak
memory. Timing is hardware- and toolchain-specific; compare repeated runs on the same machine rather than treating
these values as API guarantees. The machine-readable run discussed below is retained at
`Documentation/Benchmarks/macos-arm64-swift-6.4.json`.

## Current release baseline

Apple Swift 6.4, arm64 macOS, 120×40 frames, 1,000 requested iterations:

| Scenario | Time/iteration | Cell updates | ANSI bytes |
| --- | ---: | ---: | ---: |
| Dashboard diff | 78.7 µs | 236.64 | — |
| Dashboard with Observation | 78.0 µs | 236.64 | — |
| Static full buffer | 55.0 µs | 0 | — |
| One-cell change | 26.1 µs | 1 | — |
| Full-frame churn | 85.4 µs | 4,800 | — |
| Cursor-only frame | 55.3 µs | 0 | — |
| Zero interaction regions | 26.5 µs | 0.01 initial average | — |
| 100 interaction regions | 30.3 µs | 0.01 initial average | — |
| ANSI static frame | 63.7 µs | 0 | 11 |
| ANSI one-cell change | 41.2 µs | 1 | 42 |
| ANSI full-frame churn | 127.5 µs | 4,800 | 5,109 |

Primitive highlights:

| Scenario | Time/iteration |
| --- | ---: |
| Empty 16×16 buffer | 0.68 µs |
| Empty 64×64 buffer | 9.77 µs |
| Empty 255×255 buffer | 154 µs |
| Ten-way fill layout | 0.19 µs |
| Wrapped 64-line paragraph into 100×50 | 0.51 ms |
| Wrapped 2,048-line paragraph into 100×50 | 0.52 ms |
| Wrapped 2,048-line paragraph scrolled to row 1,024 | 6.98 ms |
| 64-row table into 120×50 | 43.2 µs |
| 2,048-row table into 120×50 | 44.8 µs |

The table and an unscrolled paragraph are effectively viewport-bounded. Paragraph rendering now composes source
lines incrementally and stops after the visible rows; its word and character wrappers also stop consuming a long
source line after producing the requested visual rows. This reduced the 2,048-line top-of-document case from about
14.0 ms to 0.52 ms on the baseline machine, approximately 27× faster.

A vertical scroll still has to compose preceding wrapped rows to locate its starting point, matching Ratatui Rust's
streaming composer. The 1,024-row benchmark records that cost explicitly. Avoiding it would require a width-dependent
layout index owned by the application or a separate cache, rather than hidden retained widget state in core.
`Paragraph.lineCount(width:)` intentionally consumes the complete document because its result is the complete
height.

Collecting 100 interaction regions adds about 3.8 µs over the otherwise identical zero-region widget, so current
evidence does not justify an invasive one-pass metadata API. Codex additionally avoids repeated paragraph work for
stable transcript history through application-level rendered-document caches.

## Decision gate for one-pass metadata

Do not replace `Widget`'s render/cursor/interaction contracts solely because they traverse composition separately.
First compare `frame/0-interactions`, `frame/100-interactions`, cursor-only frames, and real Herdr/Codex profiles.
A one-pass API is justified only if metadata traversal is a material share of frame time after ordinary allocation
and rendering hot spots are addressed. Any design must preserve pure immediate-mode rendering and whole-frame
buffer diffing; it must not introduce retained widget identity or subtree repainting.
