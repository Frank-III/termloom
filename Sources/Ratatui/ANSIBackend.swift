import Foundation

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(Musl)
  import Musl
#endif

public enum ANSIBackendError: Error {
  case sizeUnavailable
}

public enum CursorAddressing: Hashable, Sendable {
  case absolute
  case savedOrigin
  case savedBottom(viewportHeight: UInt16)
  case absoluteOrigin(Position)
}

public enum ANSIColorProfile: Hashable, Sendable {
  case ansi16
  case indexed256
  case trueColor
}

public enum ANSIHistoryInsertionStrategy: Hashable, Sendable {
  /// Fast DECSTBM insertion for terminals that retain top-margin CRLF rows as scrollback.
  case scrollingRegion
  /// Whole-screen terminal output followed by a live-viewport redraw. This is more expensive but
  /// preserves history in multiplexers and Supaterm's Ghostty host, which discard margin-scrolled rows.
  case terminalOutput
}

public struct ANSIBackendConfiguration: Hashable, Sendable {
  public var colorProfile: ANSIColorProfile
  public var supportsUnderlineColor: Bool
  public var supportsSynchronizedOutput: Bool
  public var historyInsertionStrategy: ANSIHistoryInsertionStrategy

  public init(
    colorProfile: ANSIColorProfile = .trueColor,
    supportsUnderlineColor: Bool = true,
    supportsSynchronizedOutput: Bool = true,
    historyInsertionStrategy: ANSIHistoryInsertionStrategy = .scrollingRegion
  ) {
    self.colorProfile = colorProfile
    self.supportsUnderlineColor = supportsUnderlineColor
    self.supportsSynchronizedOutput = supportsSynchronizedOutput
    self.historyInsertionStrategy = historyInsertionStrategy
  }

  public static let full = Self()

  public static func detected(
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> Self {
    let term = environment["TERM", default: ""].lowercased()
    let colorTerm = environment["COLORTERM", default: ""].lowercased()
    if term == "dumb" {
      return Self(
        colorProfile: .ansi16,
        supportsUnderlineColor: false,
        supportsSynchronizedOutput: false
      )
    }
    let colorProfile: ANSIColorProfile
    if colorTerm.contains("truecolor") || colorTerm.contains("24bit") {
      colorProfile = .trueColor
    } else if term.contains("256color") {
      colorProfile = .indexed256
    } else {
      colorProfile = .ansi16
    }
    let requiresTerminalOutputHistory =
      environment["SUPATERM_SOCKET_PATH"] != nil || environment["ZELLIJ"] != nil
      || environment["TMUX"] != nil
    return Self(
      colorProfile: colorProfile,
      historyInsertionStrategy: requiresTerminalOutputHistory ? .terminalOutput : .scrollingRegion)
  }
}

public struct ANSIBackend: Backend, LineAppendingBackend, InlineHistoryBackend, @unchecked Sendable
{
  private var output: FileHandle
  var outputWriter: (Data) throws -> Void
  private var fallbackSize: Size?
  private var viewportHeight: UInt16?
  private var effectiveViewportHeight: UInt16?
  private var reportedViewportOrigin: Position?
  private var cursorAddressing: CursorAddressing
  private var historyBatchOrigin: Position?
  private var historyBatchRowCount = 0
  public var configuration: ANSIBackendConfiguration

  public var capabilities: BackendCapabilities {
    var result: BackendCapabilities = [.windowPixelSize, .regionalClears]
    if configuration.supportsSynchronizedOutput { result.insert(.synchronizedOutput) }
    if configuration.supportsUnderlineColor { result.insert(.underlineColor) }
    if configuration.colorProfile != .ansi16 { result.insert(.indexedColor) }
    if configuration.colorProfile == .trueColor { result.insert(.trueColor) }
    if case .absoluteOrigin = cursorAddressing { result.insert(.inlineViewport) }
    return result
  }

  public var viewportOrigin: Position {
    if case .absoluteOrigin(let origin) = cursorAddressing { return origin }
    return reportedViewportOrigin ?? Position(x: 0, y: 0)
  }

  public init(
    output: FileHandle = .standardOutput,
    fallbackSize: Size? = nil,
    viewportHeight: UInt16? = nil,
    viewportOrigin: Position? = nil,
    cursorAddressing: CursorAddressing = .absolute,
    configuration: ANSIBackendConfiguration = .full
  ) {
    self.output = output
    outputWriter = { data in try output.write(contentsOf: data) }
    self.fallbackSize = fallbackSize
    self.viewportHeight = viewportHeight
    effectiveViewportHeight =
      viewportHeight.map {
        min($0, fallbackSize?.height ?? $0)
      } ?? fallbackSize?.height
    reportedViewportOrigin = viewportOrigin
    self.cursorAddressing = cursorAddressing
    self.configuration = configuration
  }

  public mutating func size() throws -> Size {
    #if os(macOS) || os(Linux)
      var window = winsize()
      if ioctl(output.fileDescriptor, UInt(TIOCGWINSZ), &window) == 0,
        window.ws_col > 0,
        window.ws_row > 0
      {
        let height = viewportHeight.map { min($0, window.ws_row) } ?? window.ws_row
        effectiveViewportHeight = height
        if case .absoluteOrigin(let origin) = cursorAddressing {
          let clamped = Position(
            x: 0,
            y: min(origin.y, UInt16(clamping: max(0, Int(window.ws_row) - Int(height)))))
          cursorAddressing = .absoluteOrigin(clamped)
          reportedViewportOrigin = clamped
        }
        return Size(width: window.ws_col, height: height)
      }
    #endif
    if let fallbackSize {
      let height = viewportHeight.map { min($0, fallbackSize.height) } ?? fallbackSize.height
      effectiveViewportHeight = height
      if case .absoluteOrigin(let origin) = cursorAddressing {
        let clamped = Position(
          x: 0,
          y: min(origin.y, UInt16(clamping: max(0, Int(fallbackSize.height) - Int(height)))))
        cursorAddressing = .absoluteOrigin(clamped)
        reportedViewportOrigin = clamped
      }
      return Size(width: fallbackSize.width, height: height)
    }
    throw ANSIBackendError.sizeUnavailable
  }

  public mutating func windowSize() throws -> WindowSize {
    #if os(macOS) || os(Linux)
      var window = winsize()
      if ioctl(output.fileDescriptor, UInt(TIOCGWINSZ), &window) == 0,
        window.ws_col > 0,
        window.ws_row > 0
      {
        let cells = Size(width: window.ws_col, height: window.ws_row)
        let pixels =
          window.ws_xpixel > 0 && window.ws_ypixel > 0
          ? Size(width: window.ws_xpixel, height: window.ws_ypixel)
          : nil
        return WindowSize(cells: cells, pixels: pixels)
      }
    #endif
    if let fallbackSize { return WindowSize(cells: fallbackSize) }
    return WindowSize(cells: try size())
  }

  public mutating func draw(_ updates: [CellUpdate]) throws {
    guard !updates.isEmpty else { return }
    var bytes: [UInt8] = []
    bytes.reserveCapacity(updates.count * 16)
    var activeStyle: Style?
    var expectedPosition: Position?

    if configuration.supportsSynchronizedOutput {
      bytes.append(contentsOf: "\u{1B}[?2026h".utf8)
    }
    for update in updates where !update.cell.isContinuation {
      if expectedPosition != update.position {
        bytes.append(contentsOf: cursor(position: update.position).utf8)
      }
      if activeStyle != update.cell.style {
        bytes.append(contentsOf: style(update.cell.style).utf8)
        activeStyle = update.cell.style
      }
      bytes.append(contentsOf: update.cell.symbol.utf8)
      expectedPosition = Position(
        x: UInt16(clamping: Int(update.position.x) + max(1, Int(update.cell.width))),
        y: update.position.y
      )
    }
    bytes.append(contentsOf: "\u{1B}[0m".utf8)
    if configuration.supportsSynchronizedOutput {
      bytes.append(contentsOf: "\u{1B}[?2026l".utf8)
    }
    try outputWriter(Data(bytes))
  }

  public mutating func clear() throws {
    try outputWriter(Data(clearSequence().utf8))
  }

  public mutating func clear(_ region: ClearRegion) throws {
    if region == .all { return try clear() }
    let sequence: String
    switch region {
    case .all: return try clear()
    case .afterCursor: sequence = "\u{1B}[0J"
    case .beforeCursor: sequence = "\u{1B}[1J"
    case .currentLine: sequence = "\u{1B}[2K"
    case .untilNewLine: sequence = "\u{1B}[0K"
    }
    try outputWriter(Data(sequence.utf8))
  }

  public mutating func setCursor(_ position: Position?) throws {
    let sequence = position.map { "\(cursor(position: $0))\u{1B}[?25h" } ?? "\u{1B}[?25l"
    try outputWriter(Data(sequence.utf8))
  }

  public mutating func setCursorStyle(_ style: CursorStyle) throws {
    let parameter =
      switch style {
      case .defaultUserShape: 0
      case .blinkingBlock: 1
      case .steadyBlock: 2
      case .blinkingUnderline: 3
      case .steadyUnderline: 4
      case .blinkingBar: 5
      case .steadyBar: 6
      }
    try outputWriter(Data("\u{1B}[\(parameter) q".utf8))
  }

  public mutating func setViewportOrigin(_ origin: Position) throws {
    guard case .absoluteOrigin = cursorAddressing else {
      throw BackendOperationError.unsupported("viewport origin")
    }
    cursorAddressing = .absoluteOrigin(origin)
  }

  public mutating func appendLines(_ count: UInt16) throws {
    guard count > 0 else { return }
    try outputWriter(Data(String(repeating: "\n", count: Int(count)).utf8))
  }

  public mutating func insertHistory(_ buffer: Buffer) throws -> Bool {
    try insertHistory(buffer, batchPosition: .single)
  }

  public mutating func insertHistory(
    _ buffer: Buffer, batchPosition: HistoryInsertionBatchPosition
  ) throws -> Bool {
    try insertHistory(buffer, batchPosition: batchPosition, restoring: nil)
  }

  public mutating func insertHistory(
    _ buffer: Buffer,
    batchPosition: HistoryInsertionBatchPosition,
    restoring viewport: Buffer?
  ) throws -> Bool {
    guard configuration.historyInsertionStrategy == .terminalOutput,
      case .absoluteOrigin(let currentOrigin) = cursorAddressing,
      buffer.area.height > 0
    else { return false }

    var operationSucceeded = false
    defer {
      if !operationSucceeded {
        historyBatchOrigin = nil
        historyBatchRowCount = 0
        // A failed chunk must not leak scoped margins, styles, or disabled wrapping into the caller's
        // terminal session. The original error remains authoritative if this cleanup also fails.
        try? outputWriter(Data("\u{1B}[r\u{1B}[0m\u{1B}[?7h".utf8))
      }
    }

    let requestedStart = batchPosition == .single || batchPosition == .first
    let startsBatch = requestedStart || historyBatchOrigin == nil
    let finishesBatch = batchPosition == .single || batchPosition == .last
    let origin: Position
    if startsBatch {
      origin = currentOrigin
      historyBatchOrigin = origin
      historyBatchRowCount = 0
      // Clear the retained pane once before whole-screen line feeds can move composer/status cells into
      // scrollback. When a retained viewport is available, its clear is emitted with the history and
      // restoration bytes so Supaterm cannot paint the intermediate blank surface.
      if viewport == nil { try clear() }
    } else {
      origin = historyBatchOrigin ?? currentOrigin
    }

    let screen = try windowSize().cells
    let liveHeight = min(
      max(1, effectiveViewportHeight ?? viewportHeight ?? buffer.area.height), max(1, screen.height)
    )

    // Scrolling while synchronized-output mode is active is not consistently committed to native
    // scrollback by Ghostty-family hosts. Chunks remain outside CSI ?2026, while wrap restoration and
    // live-row reservation are deferred until the final chunk.
    var bytes: [UInt8] = []
    if startsBatch {
      if viewport != nil { bytes.append(contentsOf: clearSequence().utf8) }
      bytes.append(contentsOf: "\u{1B}[r\u{1B}[?7l\u{1B}[\(Int(origin.y) + 1);1H".utf8)
    } else {
      bytes.append(contentsOf: "\r\n".utf8)
    }
    for row in 0..<Int(buffer.area.height) {
      if row > 0 { bytes.append(contentsOf: "\r\n".utf8) }
      bytes.append(contentsOf: "\u{1B}[2K".utf8)
      appendHistoryRow(row, from: buffer, to: &bytes)
    }
    historyBatchRowCount += Int(buffer.area.height)

    var completedOrigin: Position?
    if finishesBatch {
      for _ in 0..<Int(liveHeight) {
        bytes.append(contentsOf: "\r\n\u{1B}[2K".utf8)
      }
      bytes.append(contentsOf: "\u{1B}[0m\u{1B}[?7h".utf8)
      let nextY = min(
        Int(origin.y) + historyBatchRowCount, max(0, Int(screen.height) - Int(liveHeight)))
      let nextOrigin = Position(x: 0, y: UInt16(clamping: nextY))
      completedOrigin = nextOrigin
      if let viewport {
        appendViewportRestoration(viewport, at: nextOrigin, to: &bytes)
      }
    }
    try outputWriter(Data(bytes))

    if let completedOrigin {
      cursorAddressing = .absoluteOrigin(completedOrigin)
      reportedViewportOrigin = completedOrigin
      historyBatchOrigin = nil
      historyBatchRowCount = 0
    }
    operationSucceeded = true
    return true
  }

  public mutating func scrollRegionUp(_ rows: Range<UInt16>, by count: UInt16) throws {
    try scrollRegion(rows, by: count, command: "S")
  }

  public mutating func scrollRegionUpIntoScrollback(
    _ rows: Range<UInt16>, by count: UInt16
  ) throws {
    guard cursorAddressing != .savedOrigin else {
      throw BackendOperationError.unsupported("scrollback insertion from a saved origin")
    }
    guard !rows.isEmpty, count > 0 else { return }
    let top = Int(rows.lowerBound) + 1
    let bottom = Int(rows.upperBound)
    // CSI S is a visual region transform, not a history operation: Ghostty-family terminals discard
    // rows it displaces. Codex Rust instead emits CRLF at the bottom margin so those rows retain native
    // scrollback metadata.
    let lineFeeds = String(repeating: "\r\n", count: Int(count))
    let sequence =
      "\u{1B}7\u{1B}[\(top);\(bottom)r\u{1B}[\(bottom);1H\(lineFeeds)\u{1B}[r\u{1B}8"
    try outputWriter(Data(sequence.utf8))
  }

  public mutating func scrollRegionDown(_ rows: Range<UInt16>, by count: UInt16) throws {
    try scrollRegion(rows, by: count, command: "T")
  }

  private mutating func scrollRegion(
    _ rows: Range<UInt16>,
    by count: UInt16,
    command: Character
  ) throws {
    guard cursorAddressing != .savedOrigin else {
      throw BackendOperationError.unsupported("region scrolling from a saved origin")
    }
    guard !rows.isEmpty, count > 0 else { return }
    let top = Int(rows.lowerBound) + 1
    let bottom = Int(rows.upperBound)
    let sequence = "\u{1B}7\u{1B}[\(top);\(bottom)r\u{1B}[\(count)\(command)\u{1B}[r\u{1B}8"
    try outputWriter(Data(sequence.utf8))
  }

  private func appendViewportRestoration(
    _ viewport: Buffer,
    at origin: Position,
    to bytes: inout [UInt8]
  ) {
    if configuration.supportsSynchronizedOutput {
      bytes.append(contentsOf: "\u{1B}[?2026h".utf8)
    }
    for row in 0..<Int(viewport.area.height) {
      bytes.append(
        contentsOf: "\u{1B}[\(Int(origin.y) + row + 1);\(Int(origin.x) + 1)H\u{1B}[2K".utf8)
      appendHistoryRow(row, from: viewport, to: &bytes)
    }
    if configuration.supportsSynchronizedOutput {
      bytes.append(contentsOf: "\u{1B}[?2026l".utf8)
    }
  }

  private func clearSequence() -> String {
    switch cursorAddressing {
    case .absolute:
      "\u{1B}[2J\u{1B}[H"
    case .savedOrigin, .savedBottom, .absoluteOrigin:
      (0..<Int(max(1, effectiveViewportHeight ?? fallbackSize?.height ?? 1))).map { row in
        "\(cursor(position: Position(x: 0, y: UInt16(clamping: row))))\u{1B}[2K"
      }.joined()
    }
  }

  private func cursor(position: Position) -> String {
    switch cursorAddressing {
    case .absolute:
      return "\u{1B}[\(Int(position.y) + 1);\(Int(position.x) + 1)H"
    case .savedOrigin:
      let vertical = position.y == 0 ? "" : "\u{1B}[\(position.y)B"
      return "\u{1B}8\(vertical)\u{1B}[\(Int(position.x) + 1)G"
    case .savedBottom(let viewportHeight):
      let rowsUp = max(0, Int(viewportHeight) - 1 - Int(position.y))
      let vertical = rowsUp == 0 ? "" : "\u{1B}[\(rowsUp)A"
      return "\u{1B}8\(vertical)\u{1B}[\(Int(position.x) + 1)G"
    case .absoluteOrigin(let origin):
      return "\u{1B}[\(Int(origin.y) + Int(position.y) + 1);\(Int(origin.x) + Int(position.x) + 1)H"
    }
  }

  private func appendHistoryRow(_ row: Int, from buffer: Buffer, to bytes: inout [UInt8]) {
    let cells = (0..<Int(buffer.area.width)).compactMap { column in
      buffer.cell(
        at: Position(
          x: UInt16(clamping: Int(buffer.area.x) + column),
          y: UInt16(clamping: Int(buffer.area.y) + row)
        ))
    }
    let lastMeaningful = cells.lastIndex {
      !$0.isContinuation && ($0.symbol != " " || $0.style != .plain)
    }
    guard let lastMeaningful else { return }

    var activeStyle: Style?
    for cell in cells[...lastMeaningful] where !cell.isContinuation {
      if activeStyle != cell.style {
        bytes.append(contentsOf: style(cell.style).utf8)
        activeStyle = cell.style
      }
      bytes.append(contentsOf: cell.symbol.utf8)
    }
    bytes.append(contentsOf: "\u{1B}[0m".utf8)
  }

  private func style(_ style: Style) -> String {
    var codes = ["0"]
    if style.modifiers.contains(.bold) { codes.append("1") }
    if style.modifiers.contains(.dim) { codes.append("2") }
    if style.modifiers.contains(.italic) { codes.append("3") }
    if style.modifiers.contains(.underlined) { codes.append("4") }
    if style.modifiers.contains(.reversed) { codes.append("7") }
    if style.modifiers.contains(.hidden) { codes.append("8") }
    if style.modifiers.contains(.crossedOut) { codes.append("9") }
    if let foreground = style.foreground {
      codes.append(contentsOf: color(foreground, foreground: true))
    }
    if let background = style.background {
      codes.append(contentsOf: color(background, foreground: false))
    }
    if configuration.supportsUnderlineColor, let underlineColor = style.underlineColor {
      codes.append(contentsOf: underlineColorCodes(underlineColor))
    }
    return "\u{1B}[\(codes.joined(separator: ";"))m"
  }

  private func underlineColorCodes(_ color: Color) -> [String] {
    if case .reset = color { return ["59"] }
    let index: UInt8
    switch configuration.colorProfile {
    case .trueColor:
      if case .rgb(let red, let green, let blue) = color {
        return ["58", "2", String(red), String(green), String(blue)]
      }
      index = indexedColor(color)
    case .indexed256:
      index = indexedColor(color)
    case .ansi16:
      index = nearestANSI16Index(rgbColor(color))
    }
    return ["58", "5", String(index)]
  }

  private func indexedColor(_ color: Color) -> UInt8 {
    switch color {
    case .reset, .black: return 0
    case .red: return 1
    case .green: return 2
    case .yellow: return 3
    case .blue: return 4
    case .magenta: return 5
    case .cyan: return 6
    case .gray: return 7
    case .darkGray: return 8
    case .lightRed: return 9
    case .lightGreen: return 10
    case .lightYellow: return 11
    case .lightBlue: return 12
    case .lightMagenta: return 13
    case .lightCyan: return 14
    case .white: return 15
    case .indexed(let value): return value
    case .rgb(let red, let green, let blue):
      return nearestXtermIndex((red, green, blue))
    }
  }

  private func color(_ color: Color, foreground: Bool) -> [String] {
    if case .reset = color { return [String(foreground ? 39 : 49)] }
    switch configuration.colorProfile {
    case .trueColor:
      break
    case .indexed256:
      switch color {
      case .rgb:
        return [foreground ? "38" : "48", "5", String(indexedColor(color))]
      default:
        break
      }
    case .ansi16:
      return ansi16Color(nearestANSI16Index(rgbColor(color)), foreground: foreground)
    }
    let offset = foreground ? 30 : 40
    switch color {
    case .reset: return [String(foreground ? 39 : 49)]
    case .black: return [String(offset)]
    case .red: return [String(offset + 1)]
    case .green: return [String(offset + 2)]
    case .yellow: return [String(offset + 3)]
    case .blue: return [String(offset + 4)]
    case .magenta: return [String(offset + 5)]
    case .cyan: return [String(offset + 6)]
    case .gray: return [String(offset + 7)]
    case .darkGray: return [String(offset + 60)]
    case .lightRed: return [String(offset + 61)]
    case .lightGreen: return [String(offset + 62)]
    case .lightYellow: return [String(offset + 63)]
    case .lightBlue: return [String(offset + 64)]
    case .lightMagenta: return [String(offset + 65)]
    case .lightCyan: return [String(offset + 66)]
    case .white: return [String(offset + 67)]
    case .indexed(let value):
      return [foreground ? "38" : "48", "5", String(value)]
    case .rgb(let red, let green, let blue):
      return [
        foreground ? "38" : "48",
        "2",
        String(red),
        String(green),
        String(blue),
      ]
    }
  }

  private func ansi16Color(_ index: UInt8, foreground: Bool) -> [String] {
    let base = foreground ? 30 : 40
    let code = index < 8 ? base + Int(index) : base + 60 + Int(index - 8)
    return [String(code)]
  }

  private func rgbColor(_ color: Color) -> (UInt8, UInt8, UInt8) {
    switch color {
    case .reset, .black: return (0, 0, 0)
    case .red: return (128, 0, 0)
    case .green: return (0, 128, 0)
    case .yellow: return (128, 128, 0)
    case .blue: return (0, 0, 128)
    case .magenta: return (128, 0, 128)
    case .cyan: return (0, 128, 128)
    case .gray: return (192, 192, 192)
    case .darkGray: return (128, 128, 128)
    case .lightRed: return (255, 0, 0)
    case .lightGreen: return (0, 255, 0)
    case .lightYellow: return (255, 255, 0)
    case .lightBlue: return (0, 0, 255)
    case .lightMagenta: return (255, 0, 255)
    case .lightCyan: return (0, 255, 255)
    case .white: return (255, 255, 255)
    case .indexed(let index): return xtermRGB(index)
    case .rgb(let red, let green, let blue): return (red, green, blue)
    }
  }

  private func xtermRGB(_ index: UInt8) -> (UInt8, UInt8, UInt8) {
    if index < 16 { return ansi16Palette[Int(index)] }
    if index < 232 {
      let offset = Int(index) - 16
      let levels: [UInt8] = [0, 95, 135, 175, 215, 255]
      return (levels[offset / 36], levels[(offset / 6) % 6], levels[offset % 6])
    }
    let level = UInt8(8 + 10 * (Int(index) - 232))
    return (level, level, level)
  }

  private func nearestXtermIndex(_ rgb: (UInt8, UInt8, UInt8)) -> UInt8 {
    var best: UInt8 = 0
    var bestDistance = Int.max
    for candidate in UInt16(0)...255 {
      let palette = xtermRGB(UInt8(candidate))
      let distance = colorDistance(rgb, palette)
      if distance < bestDistance {
        bestDistance = distance
        best = UInt8(candidate)
      }
    }
    return best
  }

  private func nearestANSI16Index(_ rgb: (UInt8, UInt8, UInt8)) -> UInt8 {
    UInt8(
      ansi16Palette.indices.min { lhs, rhs in
        colorDistance(rgb, ansi16Palette[lhs]) < colorDistance(rgb, ansi16Palette[rhs])
      } ?? 0
    )
  }

  private func colorDistance(
    _ lhs: (UInt8, UInt8, UInt8),
    _ rhs: (UInt8, UInt8, UInt8)
  ) -> Int {
    let red = Int(lhs.0) - Int(rhs.0)
    let green = Int(lhs.1) - Int(rhs.1)
    let blue = Int(lhs.2) - Int(rhs.2)
    return red * red + green * green + blue * blue
  }

  private var ansi16Palette: [(UInt8, UInt8, UInt8)] {
    [
      (0, 0, 0), (128, 0, 0), (0, 128, 0), (128, 128, 0),
      (0, 0, 128), (128, 0, 128), (0, 128, 128), (192, 192, 192),
      (128, 128, 128), (255, 0, 0), (0, 255, 0), (255, 255, 0),
      (0, 0, 255), (255, 0, 255), (0, 255, 255), (255, 255, 255),
    ]
  }
}
