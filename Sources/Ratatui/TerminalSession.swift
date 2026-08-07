import Foundation

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(Musl)
  import Musl
#endif

public enum Viewport: Hashable, Sendable {
  /// A retained full-width region embedded in normal terminal output.
  case inline(height: UInt16)
  /// The terminal's alternate screen, automatically following the physical window size.
  case fullscreen
  /// An exact region in terminal coordinates. It never follows physical resizes automatically.
  case fixed(Rect)
}

public enum TerminalResizeDisposition: Hashable, Sendable {
  case unchanged
  case viewportChanged
  case historyReset
}

public enum TerminalSessionError: Error {
  case inputIsNotATerminal
  case outputIsNotATerminal
  case cannotReadTerminalAttributes
  case cannotSetTerminalAttributes
  case cannotReadInput
}

/// Reports a failed scoped operation whose terminal cleanup also failed.
public struct TerminalScopeError: Error {
  public let operationError: any Error
  public let cleanupError: any Error

  public init(operationError: any Error, cleanupError: any Error) {
    self.operationError = operationError
    self.cleanupError = cleanupError
  }
}

extension TerminalScopeError: LocalizedError {
  public var errorDescription: String? {
    "The terminal operation and its required cleanup both failed."
  }
}

func completeTerminalScope<Value>(
  _ outcome: Result<Value, any Error>,
  cleanup: () throws -> Void
) throws -> Value {
  let cleanupOutcome = Result { try cleanup() }
  switch (outcome, cleanupOutcome) {
  case (.success(let value), .success):
    return value
  case (.success, .failure(let cleanupError)):
    throw cleanupError
  case (.failure(let operationError), .success):
    throw operationError
  case (.failure(let operationError), .failure(let cleanupError)):
    throw TerminalScopeError(operationError: operationError, cleanupError: cleanupError)
  }
}

func withTerminalCleanup<Value>(
  operation: () throws -> Value,
  cleanup: () throws -> Void
) throws -> Value {
  try completeTerminalScope(Result { try operation() }, cleanup: cleanup)
}

@MainActor
func withTerminalCleanup<Value>(
  operation: () async throws -> Value,
  cleanup: () throws -> Void
) async throws -> Value {
  let outcome: Result<Value, any Error>
  do {
    outcome = .success(try await operation())
  } catch {
    outcome = .failure(error)
  }
  return try completeTerminalScope(outcome, cleanup: cleanup)
}

final class TransactionalTerminalOutput: @unchecked Sendable {
  static let emergencyRecoverySequence = Data(
    "\u{1B}[?2026l\u{1B}[r\u{1B}[0m\u{1B}[?7h\u{1B}[?25h".utf8)

  private let directWrite: (Data) throws -> Void
  private let lock = NSLock()
  private var isBuffering = false
  private var buffer = Data()

  convenience init(output: FileHandle) {
    self.init { data in try output.write(contentsOf: data) }
  }

  init(directWrite: @escaping (Data) throws -> Void) {
    self.directWrite = directWrite
  }

  func write(_ data: Data) throws {
    try lock.withLock {
      if isBuffering {
        buffer.append(data)
      } else {
        try directWrite(data)
      }
    }
  }

  func withTransaction<Result>(_ operation: () throws -> Result) throws -> Result {
    lock.withLock {
      precondition(!isBuffering, "nested terminal output transactions are unsupported")
      isBuffering = true
      buffer.removeAll(keepingCapacity: true)
    }

    let result: Result
    do {
      result = try operation()
    } catch {
      lock.withLock {
        isBuffering = false
        buffer.removeAll(keepingCapacity: true)
      }
      throw error
    }

    do {
      try lock.withLock {
        isBuffering = false
        let completed = buffer
        buffer.removeAll(keepingCapacity: true)
        if !completed.isEmpty { try directWrite(completed) }
      }
    } catch {
      let commitError = error
      do {
        try lock.withLock {
          try directWrite(Self.emergencyRecoverySequence)
        }
      } catch {
        throw TerminalScopeError(operationError: commitError, cleanupError: error)
      }
      throw commitError
    }
    return result
  }
}

/// Owns raw-mode and viewport escape sequences for the lifetime of an application.
///
/// Keep this value alive until the application loop exits. `restore()` is idempotent and is also
/// called from `deinit`, while `withTerminalSession` provides deterministic restoration on throws.
@MainActor
public final class TerminalSession {
  private let inputDescriptor: Int32
  private let output: FileHandle
  var terminalOutput: TransactionalTerminalOutput
  private var viewport: Viewport
  public let capturesMouse: Bool
  private let fallbackSize: Size
  private let backendConfiguration: ANSIBackendConfiguration?
  private enum LifecycleState: Equatable { case active, suspended, restored }

  private var savedAttributes: termios
  private var rawAttributes: termios
  private var lifecycleState: LifecycleState = .active
  private var prefetchedInput = Data()
  private var lastWindowSize: Size
  public private(set) var viewportOrigin = Position(x: 0, y: 0)

  private struct FrameTransactionSnapshot {
    var viewport: Viewport
    var prefetchedInput: Data
    var lastWindowSize: Size
    var viewportOrigin: Position
  }

  public init(
    viewport: Viewport = .inline(height: 10),
    capturesMouse: Bool = false,
    inputDescriptor: Int32 = STDIN_FILENO,
    output: FileHandle = .standardOutput,
    fallbackSize: Size = Size(width: 80, height: 24),
    backendConfiguration: ANSIBackendConfiguration? = nil
  ) throws {
    guard isatty(inputDescriptor) == 1 else {
      throw TerminalSessionError.inputIsNotATerminal
    }
    guard isatty(output.fileDescriptor) == 1 else {
      throw TerminalSessionError.outputIsNotATerminal
    }

    self.inputDescriptor = inputDescriptor
    self.output = output
    terminalOutput = TransactionalTerminalOutput(output: output)
    self.viewport = viewport
    self.capturesMouse = capturesMouse
    self.fallbackSize = fallbackSize
    self.backendConfiguration = backendConfiguration
    lastWindowSize = fallbackSize
    if case .fixed(let area) = viewport {
      viewportOrigin = Position(x: area.x, y: area.y)
    }

    var attributes = termios()
    guard tcgetattr(inputDescriptor, &attributes) == 0 else {
      throw TerminalSessionError.cannotReadTerminalAttributes
    }
    savedAttributes = attributes

    attributes.c_lflag &= ~tcflag_t(ICANON | ECHO | IEXTEN | ISIG)
    attributes.c_iflag &= ~tcflag_t(IXON | ICRNL | BRKINT | INPCK | ISTRIP)
    attributes.c_oflag &= ~tcflag_t(OPOST)
    attributes.c_cflag |= tcflag_t(CS8)
    rawAttributes = attributes
    guard tcsetattr(inputDescriptor, TCSANOW, &rawAttributes) == 0 else {
      throw TerminalSessionError.cannotSetTerminalAttributes
    }

    do {
      try activateTerminal()
    } catch {
      // Setup writes protocol enables before cursor probing/reservation. If a later step fails, make a
      // best-effort attempt to balance those modes as well as restoring termios.
      try? terminalOutput.write(Data(restoreSequence.utf8))

      _ = tcsetattr(inputDescriptor, TCSANOW, &savedAttributes)
      throw error
    }
  }

  isolated deinit {
    // Deinitialization cannot report failure; deterministic public scopes use `withTerminalCleanup`.
    try? restore()
  }

  public var configuredViewport: Viewport { viewport }

  public var supportsInlineHistory: Bool {
    if case .inline = viewport { return true }
    return false
  }

  public func makeBackend() -> ANSIBackend {
    var backend: ANSIBackend
    switch viewport {
    case .inline(let height):
      backend = ANSIBackend(
        output: output,
        fallbackSize: fallbackSize,
        viewportHeight: max(1, height),
        viewportOrigin: viewportOrigin,
        cursorAddressing: .absoluteOrigin(viewportOrigin),
        configuration: backendConfiguration ?? .detected()
      )
    case .fullscreen:
      backend = ANSIBackend(
        output: output, fallbackSize: fallbackSize,
        configuration: backendConfiguration ?? .detected())
    case .fixed(let area):
      backend = ANSIBackend(
        output: output,
        fallbackSize: fallbackSize,
        viewportOrigin: Position(x: area.x, y: area.y),
        cursorAddressing: .absolute,
        configuration: backendConfiguration ?? .detected()
      )
    }
    backend.outputWriter = { [terminalOutput] data in
      try terminalOutput.write(data)
    }
    return backend
  }

  /// Buffer one complete viewport mutation and emit it as a single terminal write.
  ///
  /// Codex Rust similarly groups viewport resizing, history insertion, and the final draw in one host
  /// update. We use write coalescing rather than an outer synchronized-output scope because native
  /// scrollback-producing line feeds must remain outside synchronized output on Ghostty-family hosts.
  func withFrameOutputTransaction<Result>(_ operation: () throws -> Result) throws -> Result {
    let snapshot = FrameTransactionSnapshot(
      viewport: viewport,
      prefetchedInput: prefetchedInput,
      lastWindowSize: lastWindowSize,
      viewportOrigin: viewportOrigin)
    do {
      return try terminalOutput.withTransaction(operation)
    } catch {
      viewport = snapshot.viewport
      prefetchedInput = snapshot.prefetchedInput
      lastWindowSize = snapshot.lastWindowSize
      viewportOrigin = snapshot.viewportOrigin
      throw error
    }
  }

  public func makeInput() -> TerminalInput {
    let initialData = takePrefetchedInput()
    let coordinateOrigin =
      switch viewport {
      case .inline: viewportOrigin
      case .fixed, .fullscreen: Position(x: 0, y: 0)
      }
    return TerminalInput(
      inputDescriptor: inputDescriptor,
      outputDescriptor: output.fileDescriptor,
      initialData: initialData,
      coordinateOrigin: coordinateOrigin
    )
  }

  /// Rebase an existing input stream after the inline viewport moves.
  ///
  /// Keeping the same stream preserves partially parsed escape sequences, queued events, and its last
  /// observed terminal size. Any bytes read while querying the cursor are transferred exactly once.
  func synchronizeInput(_ input: inout TerminalInput) {
    let coordinateOrigin =
      switch viewport {
      case .inline: viewportOrigin
      case .fixed, .fullscreen: Position(x: 0, y: 0)
      }
    input.rebase(to: coordinateOrigin, initialData: takePrefetchedInput())
  }

  private func takePrefetchedInput() -> Data {
    let data = prefetchedInput
    prefetchedInput.removeAll(keepingCapacity: true)
    return data
  }

  /// Reanchor an inline viewport after the host reports a physical terminal resize.
  ///
  /// Terminal emulators reflow existing rows when their width changes. Absolute coordinates from the
  /// previous width no longer identify the old inline viewport after that reflow, so trying to clear
  /// it row-by-row can leave duplicated borders and fragments behind. Ratatui Rust clears the whole
  /// visible screen on horizontal shrink for the same reason. We do so for every width change, then
  /// establish a known column-zero origin for the next complete redraw. Height-only changes keep the
  /// existing origin when it still fits.
  ///
  /// Distinguishes a viewport-only move from a destructive history reset so applications do not
  /// replay semantic history after a height-only clamp.
  @discardableResult
  public func reanchorAfterResize(_ size: Size) throws -> TerminalResizeDisposition {
    guard lifecycleState == .active else { return .unchanged }
    defer { lastWindowSize = size }
    guard case .inline(let requestedHeight) = viewport else { return .unchanged }

    let height = min(max(1, requestedHeight), max(1, size.height))
    if size.width != lastWindowSize.width {
      viewportOrigin = Position(x: 0, y: 0)
      // Width reflow can move owned rows into scrollback before the resize event is observed, then
      // pull those fragments back into view on a later grow. Codex Rust's resize-reflow recovery
      // similarly purges both scrollback and the visible screen before rebuilding from source.
      try terminalOutput.write(Data("\u{1B}[?25l\u{1B}[3J\u{1B}[2J\u{1B}[H".utf8))
      return .historyReset
    }

    let clampedY = min(
      viewportOrigin.y, UInt16(clamping: max(0, Int(size.height) - Int(height))))
    guard clampedY != viewportOrigin.y else { return .unchanged }
    viewportOrigin = Position(x: 0, y: clampedY)
    return .viewportChanged
  }

  /// Keep terminal restoration and future resize backends aligned with an inline viewport that moved
  /// while committed history rows were inserted above it.
  public func synchronizeViewportOrigin(_ origin: Position) {
    guard case .inline = viewport else { return }
    viewportOrigin = Position(x: 0, y: origin.y)
  }

  /// Resize a caller-owned fixed terminal and keep this session's lifecycle region synchronized.
  ///
  /// The terminal clears its previous region before adopting the replacement. Session reset, backend
  /// reconstruction, and restoration state use the new rectangle only after that resize succeeds.
  public func resizeFixedViewport(
    to area: Rect,
    terminal: inout Terminal<ANSIBackend>
  ) throws {
    guard case .fixed = viewport, case .fixed = terminal.viewport else {
      throw TerminalViewportError.requiresFixedViewport
    }
    try terminal.resize(to: area)
    try terminal.withBackend { backend in
      try backend.setViewportOrigin(Position(x: area.x, y: area.y))
    }
    viewport = .fixed(area)
    viewportOrigin = Position(x: area.x, y: area.y)
  }

  /// Resize the retained inline viewport without reserving a fixed-height pane up front.
  ///
  /// The origin remains attached to the preceding terminal output. Growing beyond the physical
  /// bottom scrolls only the missing rows into existence; shrinking clears rows that are no longer
  /// owned. The caller must recreate its backend so buffer dimensions and input coordinates use the
  /// new viewport.
  @discardableResult
  public func updateInlineViewportHeight(_ requestedHeight: UInt16) throws -> Bool {
    guard lifecycleState == .active, case .inline(let previousRequestedHeight) = viewport else {
      return false
    }
    let screen = terminalWindowSize()
    let previousHeight = min(max(1, previousRequestedHeight), max(1, screen.height))
    let height = min(max(1, requestedHeight), max(1, screen.height))
    guard height != previousHeight else { return false }

    let overflowingRows = max(
      0, Int(viewportOrigin.y) + Int(height) - Int(max(1, screen.height)))
    if overflowingRows > 0 {
      let bottomRow = max(1, screen.height)
      let lineFeeds = String(repeating: "\r\n", count: overflowingRows)
      try terminalOutput.write(Data("\u{1B}[\(bottomRow);1H\(lineFeeds)".utf8))
      viewportOrigin.y = UInt16(clamping: max(0, Int(viewportOrigin.y) - overflowingRows))
    }

    let rowsToClear = max(Int(previousHeight), Int(height))
    if rowsToClear > 0 {
      var sequence = "\u{1B}[?25l"
      for offset in 0..<rowsToClear {
        let row = Int(viewportOrigin.y) + offset + 1
        sequence += "\u{1B}[\(row);1H\u{1B}[2K"
      }
      try terminalOutput.write(Data(sequence.utf8))
    }

    viewport = .inline(height: height)
    lastWindowSize = screen
    return true
  }

  /// Purge terminal scrollback and establish a fresh retained viewport for the next draw.
  public func clearScrollbackAndResetViewport() throws {
    guard lifecycleState == .active else { return }
    if case .fixed(let area) = viewport {
      try terminalOutput.write(Data(Self.clearFixedRegionSequence(area).utf8))
      return
    }
    try terminalOutput.write(Data("\u{1B}[?25l\u{1B}[3J\u{1B}[2J\u{1B}[H".utf8))
    guard case .inline(let requestedHeight) = viewport else { return }

    // ED2 + CUP above leaves the cursor at the known home position. Re-probing it here races the
    // application's asynchronous input pump, which can consume the CPR and leave the screen blank for
    // the probe timeout. Rebuild the same Ratatui inline reservation deterministically from row zero.
    let screen = terminalWindowSize()
    let height = min(max(1, requestedHeight), max(1, screen.height))
    viewportOrigin = Position(x: 0, y: 0)
    let linesAfterCursor = height - 1
    if linesAfterCursor > 0 {
      try terminalOutput.write(
        Data(String(repeating: "\n", count: Int(linesAfterCursor)).utf8))
    }
    lastWindowSize = screen
  }

  /// Temporarily restore the user's terminal so an interactive child process can own it.
  public func suspend() throws {
    guard lifecycleState == .active else { return }
    let attributeResult = tcsetattr(inputDescriptor, TCSANOW, &savedAttributes)
    try terminalOutput.write(Data(restoreSequence.utf8))
    if attributeResult != 0 { throw TerminalSessionError.cannotSetTerminalAttributes }
    lifecycleState = .suspended
  }

  /// Re-enter raw mode and establish a fresh viewport after a suspended process exits.
  public func resume() throws {
    guard lifecycleState == .suspended else { return }
    guard tcsetattr(inputDescriptor, TCSANOW, &rawAttributes) == 0 else {
      throw TerminalSessionError.cannotSetTerminalAttributes
    }
    do {
      try activateTerminal()
      lifecycleState = .active
    } catch {
      try? terminalOutput.write(Data(restoreSequence.utf8))
      _ = tcsetattr(inputDescriptor, TCSANOW, &savedAttributes)
      lifecycleState = .suspended
      throw error
    }
  }

  /// Run an operation with normal terminal settings, then always resume the TUI.
  @MainActor
  public func withRestoredTerminal<Result>(
    _ operation: () async throws -> Result
  ) async throws -> Result {
    try suspend()
    return try await withTerminalCleanup(operation: operation) {
      try resume()
    }
  }

  public func restore() throws {
    guard lifecycleState != .restored else { return }
    if lifecycleState == .active { try suspend() }
    lifecycleState = .restored
  }

  private var setupSequence: String {
    let mouse =
      capturesMouse ? "\u{1B}[?1002h\u{1B}[?1006h" : "\u{1B}[?1006l\u{1B}[?1002l"
    switch viewport {
    case .inline:
      return "\u{1B}[?25l\u{1B}[?2004h\(mouse)\u{1B}[?1004h\u{1B}[?u\u{1B}[>1u"
    case .fullscreen:
      return
        "\u{1B}[?1049h\u{1B}[2J\u{1B}[H\u{1B}[?25l\u{1B}[?2004h\(mouse)\u{1B}[?1004h\u{1B}[?u\u{1B}[>1u"
    case .fixed:
      return "\u{1B}7\u{1B}[?25l\u{1B}[?2004h\(mouse)\u{1B}[?1004h\u{1B}[?u\u{1B}[>1u"
    }
  }

  /// Mirrors Ratatui Rust's `compute_inline_size`: observe the cursor before reserving rows,
  /// append the rows below it, then compensate if that append scrolls at the screen bottom.
  private func activateTerminal(enableProtocols: Bool = true) throws {
    if enableProtocols {
      try terminalOutput.write(Data(setupSequence.utf8))
    }
    if case .fixed(let area) = viewport {
      try terminalOutput.write(Data(Self.clearFixedRegionSequence(area).utf8))
      return
    }
    guard case .inline(let requestedHeight) = viewport else { return }

    try terminalOutput.write(Data("\r\u{1B}[6n".utf8))
    let report = Self.readCursorReport(from: inputDescriptor)
    prefetchedInput.append(report.remainingInput)
    let screen = terminalWindowSize()
    lastWindowSize = screen
    let height = min(max(1, requestedHeight), max(1, screen.height))
    let linesAfterCursor = height - 1

    guard let observed = report.position else {
      // Cursor save/restore state is not reliably preserved by every terminal while scrolling.
      // When CPR is unavailable, force a known physical bottom anchor and use absolute CUP for
      // every draw. This may reserve the viewport at the bottom of the window, but cannot drift
      // horizontally or overwrite earlier shell output as relative saved-origin fallbacks can.
      viewportOrigin = Position(x: 0, y: screen.height - height)
      try terminalOutput.write(Data("\r\u{1B}[999B".utf8))
      if linesAfterCursor > 0 {
        try terminalOutput.write(
          Data(String(repeating: "\n", count: Int(linesAfterCursor)).utf8))
      }
      return
    }

    let availableLines = UInt16(
      clamping: max(0, Int(screen.height) - Int(observed.y) - 1))
    let missingLines = UInt16(clamping: max(0, Int(linesAfterCursor) - Int(availableLines)))
    viewportOrigin = Position(
      x: 0, y: UInt16(clamping: max(0, Int(observed.y) - Int(missingLines))))

    if linesAfterCursor > 0 {
      try terminalOutput.write(
        Data(String(repeating: "\n", count: Int(linesAfterCursor)).utf8))
    }
  }

  private func terminalWindowSize() -> Size {
    var window = winsize()
    guard ioctl(output.fileDescriptor, UInt(TIOCGWINSZ), &window) == 0,
      window.ws_col > 0, window.ws_row > 0
    else { return fallbackSize }
    return Size(width: window.ws_col, height: window.ws_row)
  }

  private var restoreSequence: String {
    let defensiveModeReset = "\u{1B}[?2026l\u{1B}[r\u{1B}[0m\u{1B}[?7h"
    switch viewport {
    case .inline(let requestedHeight):
      let screen = terminalWindowSize()
      let height = min(max(1, requestedHeight), max(1, screen.height))
      let bottom = min(
        max(1, screen.height), UInt16(clamping: Int(viewportOrigin.y) + Int(height)))
      let positionAfterViewport = "\u{1B}[\(bottom);1H"
      return defensiveModeReset
        + "\u{1B}[<u\u{1B}[?1004l\u{1B}[?1006l\u{1B}[?1002l\u{1B}[?2004l\(positionAfterViewport)\u{1B}[0 q\u{1B}[?25h\r\n"
    case .fullscreen:
      return defensiveModeReset
        + "\u{1B}[<u\u{1B}[?1004l\u{1B}[?1006l\u{1B}[?1002l\u{1B}[?2004l\u{1B}[0 q\u{1B}[?25h\u{1B}[?1049l"
    case .fixed:
      return defensiveModeReset
        + "\u{1B}[<u\u{1B}[?1004l\u{1B}[?1006l\u{1B}[?1002l\u{1B}[?2004l\u{1B}[0 q\u{1B}[?25h\u{1B}8"
    }
  }

  private static func clearFixedRegionSequence(_ area: Rect) -> String {
    guard !area.isEmpty else { return "" }
    return "\u{1B}[0m"
      + (0..<Int(area.height)).map { offset in
        let row = Int(area.y) + offset + 1
        let column = Int(area.x) + 1
        return "\u{1B}[\(row);\(column)H\u{1B}[\(area.width)X"
      }.joined()
  }

  private static func readCursorReport(
    from descriptor: Int32
  ) -> (position: Position?, remainingInput: Data) {
    let deadline = Date().addingTimeInterval(0.25)
    var accumulated: [UInt8] = []

    while Date() < deadline {
      let timeout = Int32(clamping: max(1, Int(deadline.timeIntervalSinceNow * 1_000)))
      var pollDescriptor = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
      let pollResult: Int32
      #if canImport(Darwin)
        pollResult = Darwin.poll(&pollDescriptor, 1, timeout)
      #elseif canImport(Glibc)
        pollResult = Glibc.poll(&pollDescriptor, 1, timeout)
      #elseif canImport(Musl)
        pollResult = Musl.poll(&pollDescriptor, 1, timeout)
      #else
        pollResult = -1
      #endif
      guard pollResult > 0 else { break }

      var chunk = [UInt8](repeating: 0, count: 256)
      let count: Int
      #if canImport(Darwin)
        count = Darwin.read(descriptor, &chunk, chunk.count)
      #elseif canImport(Glibc)
        count = Glibc.read(descriptor, &chunk, chunk.count)
      #elseif canImport(Musl)
        count = Musl.read(descriptor, &chunk, chunk.count)
      #else
        count = -1
      #endif
      guard count > 0 else { break }
      accumulated.append(contentsOf: chunk.prefix(count))

      if let report = cursorReport(in: accumulated) {
        accumulated.removeSubrange(report.range)
        return (report.position, Data(accumulated))
      }
    }
    return (nil, Data(accumulated))
  }

  private static func cursorReport(
    in bytes: [UInt8]
  ) -> (position: Position, range: Range<Int>)? {
    for start in bytes.indices where start + 3 < bytes.count {
      guard bytes[start] == 0x1B, bytes[start + 1] == 0x5B else { continue }
      var cursor = start + 2
      if bytes[cursor] == 0x3F { cursor += 1 }
      let rowStart = cursor
      while cursor < bytes.count, bytes[cursor].isASCIIDigit { cursor += 1 }
      guard cursor > rowStart, cursor < bytes.count, bytes[cursor] == 0x3B else { continue }
      let row = Int(String(decoding: bytes[rowStart..<cursor], as: UTF8.self)) ?? 0
      cursor += 1
      let columnStart = cursor
      while cursor < bytes.count, bytes[cursor].isASCIIDigit { cursor += 1 }
      guard cursor > columnStart, cursor < bytes.count, bytes[cursor] == 0x52 else { continue }
      let column = Int(String(decoding: bytes[columnStart..<cursor], as: UTF8.self)) ?? 0
      guard row > 0, column > 0 else { continue }
      return (
        Position(
          x: UInt16(clamping: column - 1),
          y: UInt16(clamping: row - 1)
        ),
        start..<(cursor + 1)
      )
    }
    return nil
  }
}

extension UInt8 {
  fileprivate var isASCIIDigit: Bool { (0x30...0x39).contains(self) }
}

@MainActor
public func withTerminalSession<Result>(
  viewport: Viewport = .inline(height: 10),
  capturesMouse: Bool = false,
  _ operation: (TerminalSession) throws -> Result
) throws -> Result {
  let session = try TerminalSession(viewport: viewport, capturesMouse: capturesMouse)
  return try withTerminalCleanup {
    try operation(session)
  } cleanup: {
    try session.restore()
  }
}

@MainActor
public func withTerminalSession<Result>(
  viewport: Viewport = .inline(height: 10),
  capturesMouse: Bool = false,
  _ operation: (TerminalSession) async throws -> Result
) async throws -> Result {
  let session = try TerminalSession(viewport: viewport, capturesMouse: capturesMouse)
  return try await withTerminalCleanup {
    try await operation(session)
  } cleanup: {
    try session.restore()
  }
}

final class TerminalWakeup: @unchecked Sendable {
  private(set) var readDescriptor: Int32 = -1
  private var writeDescriptor: Int32 = -1

  init() {
    var descriptors: [Int32] = [-1, -1]
    guard pipe(&descriptors) == 0 else { return }
    readDescriptor = descriptors[0]
    writeDescriptor = descriptors[1]
    _ = fcntl(readDescriptor, F_SETFL, fcntl(readDescriptor, F_GETFL) | O_NONBLOCK)
    _ = fcntl(writeDescriptor, F_SETFL, fcntl(writeDescriptor, F_GETFL) | O_NONBLOCK)
    _ = fcntl(readDescriptor, F_SETFD, fcntl(readDescriptor, F_GETFD) | FD_CLOEXEC)
    _ = fcntl(writeDescriptor, F_SETFD, fcntl(writeDescriptor, F_GETFD) | FD_CLOEXEC)
  }

  deinit {
    if readDescriptor >= 0 { close(readDescriptor) }
    if writeDescriptor >= 0 { close(writeDescriptor) }
  }

  func signal() {
    guard writeDescriptor >= 0 else { return }
    var byte: UInt8 = 1
    _ = withUnsafeBytes(of: &byte) { bytes in
      write(writeDescriptor, bytes.baseAddress, bytes.count)
    }
  }

  func drain() {
    guard readDescriptor >= 0 else { return }
    var bytes = [UInt8](repeating: 0, count: 64)
    while read(readDescriptor, &bytes, bytes.count) > 0 {}
  }
}

public struct TerminalInput {
  private var parser = InputParser()
  private var queuedEvents: [TerminalEvent] = []
  private var lastSize: Size?
  private let inputDescriptor: Int32
  private let outputDescriptor: Int32
  private var coordinateOrigin: Position

  public init(
    inputDescriptor: Int32 = STDIN_FILENO,
    outputDescriptor: Int32 = STDOUT_FILENO,
    initialData: Data = Data(),
    coordinateOrigin: Position = Position(x: 0, y: 0)
  ) {
    self.inputDescriptor = inputDescriptor
    self.outputDescriptor = outputDescriptor
    self.coordinateOrigin = coordinateOrigin
    lastSize = terminalSize()
    queuedEvents = parser.feed(initialData).map(localize)
  }

  /// Update the physical-to-local coordinate transform without discarding parser state or queued input.
  /// Bytes captured by a terminal cursor query are appended after already-buffered bytes and localized
  /// against the new viewport origin.
  mutating func rebase(to origin: Position, initialData: Data = Data()) {
    coordinateOrigin = origin
    guard !initialData.isEmpty else { return }
    queuedEvents.append(contentsOf: parser.feed(initialData).map(localize))
  }

  public mutating func readEvent(timeoutMilliseconds: Int32 = 50) throws -> TerminalEvent? {
    try readEvent(timeoutMilliseconds: timeoutMilliseconds, wakeup: nil)
  }

  mutating func readEvent(
    timeoutMilliseconds: Int32 = 50,
    wakeup: TerminalWakeup?
  ) throws -> TerminalEvent? {
    if !queuedEvents.isEmpty {
      return queuedEvents.removeFirst()
    }

    if let size = terminalSize() {
      defer { lastSize = size }
      if let lastSize, size != lastSize {
        return .resize(size)
      }
    }

    var descriptors = [pollfd(fd: inputDescriptor, events: Int16(POLLIN), revents: 0)]
    if let wakeup, wakeup.readDescriptor >= 0 {
      descriptors.append(pollfd(fd: wakeup.readDescriptor, events: Int16(POLLIN), revents: 0))
    }
    let result = systemPoll(&descriptors, timeout: timeoutMilliseconds)
    guard result >= 0 else { throw TerminalSessionError.cannotReadInput }
    let input = descriptors[0]
    let wakeupFired =
      descriptors.count > 1 && descriptors[1].revents & Int16(POLLIN) != 0
    if wakeupFired { wakeup?.drain() }
    if result == 0 { return parser.flushEscape().map(localize) }
    if input.revents & Int16(POLLHUP) != 0,
      input.revents & Int16(POLLIN) == 0
    {
      return .endOfInput
    }
    guard input.revents & Int16(POLLIN) != 0 else { return nil }

    var buffer = [UInt8](repeating: 0, count: 4096)
    let count = systemRead(inputDescriptor, into: &buffer)
    guard count >= 0 else { throw TerminalSessionError.cannotReadInput }
    guard count > 0 else { return parser.flushEscape().map(localize) ?? .endOfInput }
    queuedEvents = parser.feed(Data(buffer.prefix(count))).map(localize)
    return queuedEvents.isEmpty ? nil : queuedEvents.removeFirst()
  }

  private func localize(_ event: TerminalEvent) -> TerminalEvent {
    guard case .mouse(var mouse) = event else { return event }
    mouse.position = Position(
      x: UInt16(clamping: max(0, Int(mouse.position.x) - Int(coordinateOrigin.x))),
      y: UInt16(clamping: max(0, Int(mouse.position.y) - Int(coordinateOrigin.y)))
    )
    return .mouse(mouse)
  }

  private func terminalSize() -> Size? {
    var window = winsize()
    guard ioctl(outputDescriptor, UInt(TIOCGWINSZ), &window) == 0 else { return nil }
    guard window.ws_col > 0, window.ws_row > 0 else { return nil }
    return Size(width: window.ws_col, height: window.ws_row)
  }

  private func systemPoll(_ descriptors: inout [pollfd], timeout: Int32) -> Int32 {
    descriptors.withUnsafeMutableBufferPointer { buffer in
      #if canImport(Darwin)
        return Darwin.poll(buffer.baseAddress, nfds_t(buffer.count), timeout)
      #elseif canImport(Glibc)
        return Glibc.poll(buffer.baseAddress, nfds_t(buffer.count), timeout)
      #elseif canImport(Musl)
        return Musl.poll(buffer.baseAddress, nfds_t(buffer.count), timeout)
      #else
        return -1
      #endif
    }
  }

  private func systemRead(_ descriptor: Int32, into buffer: inout [UInt8]) -> Int {
    #if canImport(Darwin)
      return Darwin.read(descriptor, &buffer, buffer.count)
    #elseif canImport(Glibc)
      return Glibc.read(descriptor, &buffer, buffer.count)
    #elseif canImport(Musl)
      return Musl.read(descriptor, &buffer, buffer.count)
    #else
      return -1
    #endif
  }
}
