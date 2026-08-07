# Ratatui Swift 0.2 release checklist

Candidate: `0.2.0-rc.1`  
Source: `main` at the commit recorded immediately before tagging

## Freeze and metadata

- [x] Plans 012–015 are complete; Plan 016 has a recorded rejection decision.
- [x] No new framework API or feature is included in Plan 017.
- [x] Architecture, migration, performance, ecosystem, parity, testing, and access-control documents describe the
  single-pass `Frame` design and current viewport/capability boundaries.
- [x] `Package.swift` parses with Swift tools 6.2, declares Swift 6 mode and macOS 14, and exposes the intended three
  libraries and five executables.
- [ ] Select and configure the public repository remote, then replace the placeholder owner in `README.md`.
- [ ] Add the project license selected by the owner. No license file is currently present, so public distribution must
  not be tagged as final until this is resolved.
- [ ] Create the annotated candidate tag only after every item below is checked.

## API and automated validation

- [x] `swift format lint --strict --recursive Package.swift Sources Tests`
- [x] `swift test`: 269 Ratatui tests in 27 suites plus 8 syntax-highlighting tests.
- [x] `Scripts/check-api.sh`: 1,540 reviewed symbols and zero additions.
- [x] `Scripts/test-ecosystem.sh`
- [x] `Scripts/test-consumers.sh`: Codex 156 tests, Motel 14 tests, and Herdr 91 tests.
- [x] Targeted Thread Sanitizer run passes concurrent syntax-highlight cache misses.
- [x] Release benchmark JSON smoke parses with 26 unique registered scenarios.

## Terminal validation

- [x] PTY lifecycle and application-loop tests pass as part of the root suite.
- [ ] Inline smoke on a real terminal: render, resize, input, normal quit, and cursor/raw-mode restoration.
- [ ] Fullscreen smoke on a real terminal: alternate screen and mouse mode balance after normal quit and interruption.
- [ ] Fixed-region smoke on a real terminal: absolute placement, region-scoped clearing, surrounding content/cursor
  preservation, and explicit resize.
- [ ] Record terminal host, tool version, date, and concise observations below.

## Workspace integrity

- [x] `ratetui-swift` is clean after the release-preparation commit is recorded.
- [x] `codex-swift`, `motel-swift`, and `herdr-swift` are clean after the complete consumer matrix.
- [x] KWWK has no new changes. Its intentional protected baseline remains:
  - `Sources/KWWKCli/CodingTUI.swift` file SHA-256:
    `a9991f75c26e6388b80be2d0b8754f93d98aca5e15219ce95663af7be9e09851`
  - diff SHA-256:
    `08ad62999ee3160ef1b4d8d8285973312671fb3d56d9349dc12498b27a01d3f2`

## Recorded evidence

- Date: 2026-08-07
- Toolchain: Apple Swift 6.4 (`swift-tools-version: 6.2`), arm64 macOS.
- Automated matrix log: `/tmp/ratatui-0.2-highlight-cache-matrix.log`.
- Benchmark smoke: `/tmp/ratatui-0.2-benchmark-smoke.json` (26 unique scenarios).
- `terminal-control` 0.4.1 supplemental smokes exercised the built inline counter, fullscreen Observation demo, and a
  temporary fixed-region program with explicit resize. Captures are in `/tmp/ratatui-0.2-termctrl-*.txt`; these are
  PTY/emulator evidence and do not replace the unchecked physical-terminal items above.
- Supaterm physical automation was attempted but synthetic text/key injection did not reach its terminal surface.
  Previous Ghostty-family history evidence remains useful, but the 0.2 candidate requires a fresh manual attestation.

## Tagging

```sh
git status --short --branch
git tag -s 0.2.0-rc.1 -m "Ratatui Swift 0.2.0 release candidate 1"
git tag -v 0.2.0-rc.1
git show --stat 0.2.0-rc.1
```

Do not push or publish the tag until the repository URL, license, and unchecked validation items are resolved.
