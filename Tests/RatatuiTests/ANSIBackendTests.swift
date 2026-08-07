import CustomDump
import Foundation
import RatatuiTestSupport
import Testing

@testable import Ratatui

@Suite struct ANSIBackendTests {
  @Test func fallbackSizeStillRespectsInlineViewportHeight() throws {
    let pipe = Pipe()
    var backend = ANSIBackend(
      output: pipe.fileHandleForWriting,
      fallbackSize: Size(width: 80, height: 24),
      viewportHeight: 5,
      viewportOrigin: Position(x: 0, y: 22),
      cursorAddressing: .absoluteOrigin(Position(x: 0, y: 22))
    )

    #expect(try backend.size() == Size(width: 80, height: 5))
    #expect(try backend.windowSize().cells == Size(width: 80, height: 24))
    #expect(backend.viewportOrigin == Position(x: 0, y: 19))
  }

  @Test func adjacentUpdatesShareOneCursorMovement() throws {
    let pipe = Pipe()
    var backend = ANSIBackend(
      output: pipe.fileHandleForWriting,
      fallbackSize: Size(width: 10, height: 1)
    )

    try backend.draw([
      CellUpdate(position: Position(x: 2, y: 0), cell: Cell(symbol: "A")),
      CellUpdate(position: Position(x: 3, y: 0), cell: Cell(symbol: "B")),
      CellUpdate(position: Position(x: 4, y: 0), cell: Cell(symbol: "C")),
    ])
    try pipe.fileHandleForWriting.close()

    let output = String(
      decoding: pipe.fileHandleForReading.readDataToEndOfFile(),
      as: UTF8.self
    )
    #expect(output.contains("\u{1B}[1;3H\u{1B}[0mABC"))
    #expect(!output.contains("\u{1B}[1;4H"))
    #expect(!output.contains("\u{1B}[1;5H"))
  }

  @Test func savedOriginAddressingKeepsWidgetCoordinatesLocal() throws {
    let pipe = Pipe()
    var backend = ANSIBackend(
      output: pipe.fileHandleForWriting,
      fallbackSize: Size(width: 10, height: 4),
      viewportHeight: 4,
      cursorAddressing: .savedOrigin
    )

    try backend.draw([
      CellUpdate(position: Position(x: 3, y: 2), cell: Cell(symbol: "X"))
    ])
    try pipe.fileHandleForWriting.close()

    let output = String(
      decoding: pipe.fileHandleForReading.readDataToEndOfFile(),
      as: UTF8.self
    )
    #expect(output.contains("\u{1B}8\u{1B}[2B\u{1B}[4G\u{1B}[0mX"))
  }

  @Test func savedBottomAddressingSurvivesViewportReservationScrolling() throws {
    let pipe = Pipe()
    var backend = ANSIBackend(
      output: pipe.fileHandleForWriting,
      fallbackSize: Size(width: 10, height: 5),
      viewportHeight: 5,
      cursorAddressing: .savedBottom(viewportHeight: 5)
    )

    try backend.draw([
      CellUpdate(position: Position(x: 0, y: 0), cell: Cell(symbol: "T")),
      CellUpdate(position: Position(x: 2, y: 4), cell: Cell(symbol: "B")),
    ])
    pipe.fileHandleForWriting.closeFile()
    let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)

    #expect(output.contains("\u{1B}8\u{1B}[4A\u{1B}[1G"))
    #expect(output.contains("\u{1B}8\u{1B}[3G"))
  }

  @Test func absoluteOriginTranslatesLocalCoordinatesToThePhysicalScreen() throws {
    let pipe = Pipe()
    var backend = ANSIBackend(
      output: pipe.fileHandleForWriting,
      fallbackSize: Size(width: 10, height: 8),
      viewportHeight: 2,
      cursorAddressing: .absoluteOrigin(Position(x: 2, y: 4))
    )

    #expect(backend.capabilities.contains(.inlineViewport))
    #expect(backend.viewportOrigin == Position(x: 2, y: 4))

    try backend.draw([
      CellUpdate(position: Position(x: 3, y: 1), cell: Cell(symbol: "X"))
    ])
    try pipe.fileHandleForWriting.close()

    let output = String(
      decoding: pipe.fileHandleForReading.readDataToEndOfFile(),
      as: UTF8.self
    )
    #expect(output.contains("\u{1B}[6;6H\u{1B}[0mX"))
  }

  @Test func inlineClearDoesNotEraseTheWholeTerminal() throws {
    let pipe = Pipe()
    var backend = ANSIBackend(
      output: pipe.fileHandleForWriting,
      fallbackSize: Size(width: 10, height: 2),
      viewportHeight: 2,
      cursorAddressing: .savedOrigin
    )

    try backend.clear()
    try pipe.fileHandleForWriting.close()

    let output = String(
      decoding: pipe.fileHandleForReading.readDataToEndOfFile(),
      as: UTF8.self
    )
    #expect(!output.contains("\u{1B}[2J"))
    #expect(output == "\u{1B}8\u{1B}[1G\u{1B}[2K\u{1B}8\u{1B}[1B\u{1B}[1G\u{1B}[2K")
  }

  @Test func emitsUnderlineColorsAndExplicitColorResets() throws {
    let pipe = Pipe()
    var backend = ANSIBackend(
      output: pipe.fileHandleForWriting,
      fallbackSize: Size(width: 2, height: 1)
    )

    try backend.draw([
      CellUpdate(
        position: Position(x: 0, y: 0),
        cell: Cell(
          symbol: "X",
          style: Style(
            foreground: .red,
            underlineColor: .indexed(42),
            modifiers: [.underlined]
          )
        )
      ),
      CellUpdate(
        position: Position(x: 1, y: 0),
        cell: Cell(
          symbol: "Y",
          style: Style(foreground: .reset, background: .reset, underlineColor: .reset)
        )
      ),
    ])
    try pipe.fileHandleForWriting.close()

    let output = String(
      decoding: pipe.fileHandleForReading.readDataToEndOfFile(),
      as: UTF8.self
    )
    #expect(output.contains("\u{1B}[0;4;31;58;5;42mX"))
    #expect(output.contains("\u{1B}[0;39;49;59mY"))
  }

  @Test func emitsTheCompleteBrightANSIColorRange() throws {
    let pipe = Pipe()
    var backend = ANSIBackend(
      output: pipe.fileHandleForWriting,
      fallbackSize: Size(width: 2, height: 1)
    )
    try backend.draw([
      CellUpdate(
        position: Position(x: 0, y: 0),
        cell: Cell(
          symbol: "R",
          style: Style(
            foreground: .lightRed,
            background: .lightBlue,
            underlineColor: .white
          )
        )
      ),
      CellUpdate(
        position: Position(x: 1, y: 0),
        cell: Cell(symbol: "G", style: Style(foreground: .gray, background: .darkGray))
      ),
    ])
    try pipe.fileHandleForWriting.close()

    let output = String(
      decoding: pipe.fileHandleForReading.readDataToEndOfFile(),
      as: UTF8.self
    )
    assertTerminalCodes(output) {
      """
      <ESC>[?2026h<ESC>[1;1H<ESC>[0;91;104;58;5;15mR<ESC>[0;37;100mG<ESC>[0m<ESC>[?2026l
      """
    }
  }

  @Test func ansi16ProfileFallsBackWithoutUnsupportedProtocols() throws {
    let pipe = Pipe()
    var backend = ANSIBackend(
      output: pipe.fileHandleForWriting,
      fallbackSize: Size(width: 1, height: 1),
      configuration: ANSIBackendConfiguration(
        colorProfile: .ansi16,
        supportsUnderlineColor: false,
        supportsSynchronizedOutput: false
      )
    )

    #expect(!backend.capabilities.contains(.indexedColor))
    #expect(!backend.capabilities.contains(.trueColor))
    #expect(!backend.capabilities.contains(.underlineColor))
    #expect(!backend.capabilities.contains(.synchronizedOutput))
    try backend.draw([
      CellUpdate(
        position: Position(x: 0, y: 0),
        cell: Cell(
          symbol: "X",
          style: Style(
            foreground: .rgb(255, 0, 0),
            background: .indexed(21),
            underlineColor: .rgb(0, 255, 0),
            modifiers: [.underlined]
          )
        )
      )
    ])
    try pipe.fileHandleForWriting.close()

    let output = String(
      decoding: pipe.fileHandleForReading.readDataToEndOfFile(),
      as: UTF8.self
    )
    #expect(!output.contains("?2026"))
    #expect(!output.contains(";58;"))
    #expect(!output.contains(";38;"))
    assertTerminalCodes(output) {
      """
      <ESC>[1;1H<ESC>[0;4;91;104mX<ESC>[0m
      """
    }
  }

  @Test func indexedProfileQuantizesTrueColor() throws {
    let pipe = Pipe()
    var backend = ANSIBackend(
      output: pipe.fileHandleForWriting,
      fallbackSize: Size(width: 1, height: 1),
      configuration: ANSIBackendConfiguration(colorProfile: .indexed256)
    )

    #expect(backend.capabilities.contains(.indexedColor))
    #expect(!backend.capabilities.contains(.trueColor))
    #expect(backend.capabilities.contains(.underlineColor))
    try backend.draw([
      CellUpdate(
        position: Position(x: 0, y: 0),
        cell: Cell(
          symbol: "X",
          style: Style(
            foreground: .rgb(95, 135, 175),
            background: .rgb(215, 95, 0),
            underlineColor: .rgb(8, 8, 8)
          )
        )
      )
    ])
    try pipe.fileHandleForWriting.close()

    let output = String(
      decoding: pipe.fileHandleForReading.readDataToEndOfFile(),
      as: UTF8.self
    )
    #expect(!output.contains(";2;"))
    assertTerminalCodes(output) {
      """
      <ESC>[?2026h<ESC>[1;1H<ESC>[0;38;5;67;48;5;166;58;5;232mX<ESC>[0m<ESC>[?2026l
      """
    }
  }

  @Test func trueColorProfileAdvertisesItsProtocols() {
    let backend = ANSIBackend()
    #expect(backend.capabilities.contains(.indexedColor))
    #expect(backend.capabilities.contains(.trueColor))
    #expect(backend.capabilities.contains(.underlineColor))
    #expect(backend.capabilities.contains(.synchronizedOutput))
  }

  @Test func environmentDetectionSelectsConservativeColorProfiles() {
    #expect(
      ANSIBackendConfiguration.detected(environment: ["COLORTERM": "truecolor"])
        .colorProfile == .trueColor
    )
    #expect(
      ANSIBackendConfiguration.detected(environment: ["TERM": "xterm-256color"])
        .colorProfile == .indexed256
    )
    let dumb = ANSIBackendConfiguration.detected(environment: ["TERM": "dumb"])
    #expect(dumb.colorProfile == .ansi16)
    #expect(!dumb.supportsUnderlineColor)
    #expect(!dumb.supportsSynchronizedOutput)
  }

  @Test func drawsExplicitVS16TrailingCellCleanupFromBufferDiffs() throws {
    var previous = Buffer(area: Rect(x: 0, y: 0, width: 2, height: 1))
    previous.setString("ab", at: Position(x: 0, y: 0))
    var next = Buffer(area: previous.area)
    next.setString("⌨️", at: Position(x: 0, y: 0))

    let pipe = Pipe()
    var backend = ANSIBackend(
      output: pipe.fileHandleForWriting,
      fallbackSize: previous.area.size
    )
    try backend.draw(next.diff(from: previous))
    try pipe.fileHandleForWriting.close()

    let output = String(
      decoding: pipe.fileHandleForReading.readDataToEndOfFile(),
      as: UTF8.self
    )
    assertTerminalCodes(output) {
      """
      <ESC>[?2026h<ESC>[1;1H<ESC>[0m⌨️<ESC>[1;2H <ESC>[0m<ESC>[?2026l
      """
    }
  }
}
