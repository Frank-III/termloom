import RatatuiTestSupport
import Testing

@testable import Ratatui

@Suite struct BrandWidgetTests {
  @Test func logosRenderBothCanonicalSizesAndClipSafely() {
    assertWidget(RatatuiLogo.tiny, size: Size(width: 15, height: 2)) {
      """
      │▛▚▗▀▖▜▘▞▚▝▛▐ ▌▌│
      │▛▚▐▀▌▐ ▛▜ ▌▝▄▘▌│
      """
    }
    assertWidget(RatatuiLogo.small, size: Size(width: 27, height: 2)) {
      """
      │█▀▀▄ ▄▀▀▄▝▜▛▘▄▀▀▄▝▜▛▘█  █ █│
      │█▀▀▄ █▀▀█ ▐▌ █▀▀█ ▐▌ ▀▄▄▀ █│
      """
    }
    assertWidget(RatatuiLogo.small, size: Size(width: 1, height: 1)) {
      """
      │█│
      """
    }
  }

  @Test func mascotUsesHalfBlocksAndSupportsBlinkColor() {
    let standard = assertWidget(RatatuiMascot(), size: Size(width: 32, height: 16)) {
      """
      │             ▄▄███              │
      │           ▄███████             │
      │         ▄█████████             │
      │        ████████████            │
      │        ▀███████████▀   ▄▄██████│
      │              ▀███▀▄█▀▀████████ │
      │            ▄▄▄▄▀▄████████████  │
      │           ████████████████     │
      │           ▀███▀██████████      │
      │         ▄▀▀▄   █████████       │
      │       ▄▀ ▄  ▀▄▀█████████       │
      │     ▄▀  ▀▀    ▀▄▀███████       │
      │   ▄▀      ▄▄    ▀▄▀█████████   │
      │ ▄▀         ▀▀     ▀▄▀██▀  ███  │
      │█                    ▀▄▀  ▄██   │
      │ ▀▄                    ▀▄▀█     │
      """
    }
    #expect(standard.cell(at: Position(x: 21, y: 5))?.style.background == .indexed(236))

    let blinking = assertWidget(
      RatatuiMascot(eyeColor: .red),
      size: Size(width: 32, height: 16)
    ) {
      """
      │             ▄▄███              │
      │           ▄███████             │
      │         ▄█████████             │
      │        ████████████            │
      │        ▀███████████▀   ▄▄██████│
      │              ▀███▀▄█▀▀████████ │
      │            ▄▄▄▄▀▄████████████  │
      │           ████████████████     │
      │           ▀███▀██████████      │
      │         ▄▀▀▄   █████████       │
      │       ▄▀ ▄  ▀▄▀█████████       │
      │     ▄▀  ▀▀    ▀▄▀███████       │
      │   ▄▀      ▄▄    ▀▄▀█████████   │
      │ ▄▀         ▀▀     ▀▄▀██▀  ███  │
      │█                    ▀▄▀  ▄██   │
      │ ▀▄                    ▀▄▀█     │
      """
    }
    #expect(blinking.cell(at: Position(x: 21, y: 5))?.style.background == .indexed(196))
  }
}
