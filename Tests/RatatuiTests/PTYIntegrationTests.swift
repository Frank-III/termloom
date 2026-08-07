#if canImport(Darwin)
  import Darwin
  import Foundation
  import Observation
  import Testing

  @testable import Ratatui

  private final class PTYOutputCapture: @unchecked Sendable {
    private let descriptor: Int32
    private let source: DispatchSourceRead
    private let lock = NSLock()
    private let cancelled = DispatchSemaphore(value: 0)
    private var bytes: [UInt8] = []

    init(descriptor: Int32) {
      self.descriptor = descriptor
      source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: .global())
      source.setEventHandler { [weak self] in self?.readAvailable() }
      source.setCancelHandler { [cancelled] in cancelled.signal() }
      source.resume()
    }

    func finish() -> [UInt8] {
      source.cancel()
      cancelled.wait()
      readAvailable()
      return lock.withLock { bytes }
    }

    private func readAvailable() {
      var buffer = [UInt8](repeating: 0, count: 16_384)
      while true {
        let count = read(descriptor, &buffer, buffer.count)
        guard count > 0 else { return }
        lock.withLock { bytes.append(contentsOf: buffer.prefix(count)) }
      }
    }
  }

  @Observable private final class RenderObservationModel {
    var value = "A"
  }

  private struct RenderObservationWidget: Widget {
    let model: RenderObservationModel

    func render(in area: Rect, into frame: inout Frame) {
      frame.buffer.setString(model.value, at: Position(x: area.x, y: area.y))
    }
  }

  @MainActor private final class RenderObservationApplication: TerminalApplication {
    let model = RenderObservationModel()
    let automaticallyTracksObservableState: Bool
    var body: RenderObservationWidget { RenderObservationWidget(model: model) }

    init(automaticallyTracksObservableState: Bool = true) {
      self.automaticallyTracksObservableState = automaticallyTracksObservableState
    }

    func update(_ event: TerminalEvent) async -> ApplicationUpdate {
      if case .key(let key) = event, key.key == .character("q") { return .quit }
      if case .key(let key) = event, key.key == .character("x") {
        try? await Task.sleep(for: .milliseconds(20))
        model.value = "B"
      }
      return .ignore
    }

  }

  @MainActor
  private final class PeriodicRedrawApplication: TerminalApplication,
    PeriodicallyRedrawingTerminalApplication
  {
    var value = "A"
    var needsPeriodicRedraw = true
    var body: Paragraph { Paragraph(value) }

    func update(_ event: TerminalEvent) async -> ApplicationUpdate {
      if case .key(let key) = event, key.key == .character("q") { return .quit }
      return .ignore
    }
  }

  @MainActor private final class LargeHistoryApplication: TerminalApplication {
    var draft = ""

    var body: Paragraph { Paragraph("READY \(draft)") }

    func inlineDocument(size: Size) -> InlineDocument<String>? {
      InlineDocument(
        id: "large", revision: 1,
        blocks: (0..<600).map { index in
          InlineDocumentBlock(id: "row-\(index)", text: Text([Line("HISTORY-\(index)\u{20}")]))
        })
    }

    func update(_ event: TerminalEvent) async -> ApplicationUpdate {
      guard case .key(let key) = event else { return .ignore }
      if key.key == .character("q") { return .quit }
      if case .character(let character) = key.key {
        draft.append(character)
        return .redraw
      }
      return .ignore
    }
  }

  @MainActor private final class PendingHistoryResetApplication: TerminalApplication {
    var resetPending = false
    var body: Paragraph { Paragraph("READY") }

    func inlineDocument(size: Size) -> InlineDocument<String>? {
      InlineDocument(
        id: "resettable", revision: 1,
        blocks: [InlineDocumentBlock(id: "history", text: Text("REPLAY-ME"))])
    }

    func takePendingHistoryInsertions(size: Size) -> [TerminalHistoryInsertion] {
      guard resetPending else { return [] }
      resetPending = false
      return [
        TerminalHistoryInsertion(text: Text("STALE-BEFORE-RESET")),
        .reset,
        TerminalHistoryInsertion(text: Text("AFTER-RESET")),
      ]
    }

    func update(_ event: TerminalEvent) async -> ApplicationUpdate {
      guard case .key(let key) = event else { return .ignore }
      if key.key == .character("r") {
        resetPending = true
        return .redraw
      }
      if key.key == .character("q") { return .quit }
      return .ignore
    }
  }

  @MainActor private final class FocusEffectApplication: TerminalApplication {
    var receivedEvents: [TerminalEvent] = []
    var body: Button { Button("Quit", id: "quit", action: "quit") }

    func update(_ event: TerminalEvent) async -> ApplicationUpdate {
      receivedEvents.append(event)
      if case .focusChanged = event { return .quit }
      if case .key(let key) = event, key.key == .character("q") { return .quit }
      return .ignore
    }
  }

  @MainActor private final class ResetInputApplication: TerminalApplication {
    var receivedEvents: [TerminalEvent] = []

    var body: some Widget {
      VStack {
        Button("First", id: "first", action: "first").frame(.length(1))
        Button("Second", id: "second", action: "second").frame(.length(1))
      }
    }

    func update(_ event: TerminalEvent) async -> ApplicationUpdate {
      receivedEvents.append(event)
      if case .key(let key) = event {
        if key.key == .character("g") { return .resetTerminalHistory }
        if key.key == .character("q") { return .quit }
      }
      return .ignore
    }
  }

  @MainActor
  @Suite(.serialized) struct PTYIntegrationTests {
    @Test func fixedSessionUsesAbsoluteCoordinatesWithoutOwningTheScreen() throws {
      var master: Int32 = -1
      var slave: Int32 = -1
      var window = winsize()
      window.ws_col = 20
      window.ws_row = 10
      #expect(openpty(&master, &slave, nil, nil, &window) == 0)
      guard master >= 0, slave >= 0 else { return }
      defer {
        close(master)
        close(slave)
      }
      _ = fcntl(master, F_SETFL, fcntl(master, F_GETFL) | O_NONBLOCK)

      let area = Rect(x: 3, y: 2, width: 5, height: 2)
      let session = try TerminalSession(
        viewport: .fixed(area),
        inputDescriptor: slave,
        output: FileHandle(fileDescriptor: slave, closeOnDealloc: false)
      )
      #expect(session.viewportOrigin == Position(x: 3, y: 2))
      #expect(session.configuredViewport == .fixed(area))
      #expect(!session.supportsInlineHistory)

      let setup = String(decoding: drain(master), as: UTF8.self)
      #expect(setup.contains("\u{1B}7"))
      #expect(setup.contains("\u{1B}[3;4H\u{1B}[5X"))
      #expect(setup.contains("\u{1B}[4;4H\u{1B}[5X"))
      #expect(!setup.contains("\u{1B}[?1049h"))
      #expect(!setup.contains("\u{1B}[6n"))

      var backend = session.makeBackend()
      #expect(try backend.size() == Size(width: 20, height: 10))
      #expect(backend.viewportOrigin == Position(x: 3, y: 2))
      var terminal = try Terminal(backend: backend, viewport: session.configuredViewport)
      let completed = try terminal.draw { frame in
        #expect(frame.area == area)
        frame.render(Paragraph("FIXED"))
      }
      #expect(completed.buffer.area == area)
      let draw = String(decoding: drain(master), as: UTF8.self)
      #expect(draw.contains("\u{1B}[3;4H"))
      #expect(draw.contains("FIXED"))

      var input = session.makeInput()
      let mouse = Array("\u{1B}[<0;5;4M".utf8)
      #expect(mouse.withUnsafeBytes { write(master, $0.baseAddress, $0.count) } == mouse.count)
      #expect(
        try input.readEvent(timeoutMilliseconds: 50)
          == .mouse(MouseEvent(.down(.left), at: Position(x: 4, y: 3))))

      #expect(try session.reanchorAfterResize(Size(width: 12, height: 6)) == .unchanged)
      #expect(session.viewportOrigin == Position(x: 3, y: 2))
      try session.clearScrollbackAndResetViewport()
      let reset = String(decoding: drain(master), as: UTF8.self)
      #expect(reset.contains("\u{1B}[3;4H\u{1B}[5X"))
      #expect(!reset.contains("\u{1B}[3J"))
      #expect(!reset.contains("\u{1B}[2J"))

      try session.restore()
      let restore = String(decoding: drain(master), as: UTF8.self)
      #expect(restore.contains("\u{1B}8"))
      #expect(!restore.contains("\u{1B}[?1049l"))
    }

    @Test func inlineSessionOwnsAndRestoresARealPseudoTerminal() throws {
      var master: Int32 = -1
      var slave: Int32 = -1
      var window = winsize()
      window.ws_col = 80
      window.ws_row = 24
      #expect(openpty(&master, &slave, nil, nil, &window) == 0)
      guard master >= 0, slave >= 0 else { return }
      defer {
        close(master)
        close(slave)
      }

      var original = termios()
      #expect(tcgetattr(slave, &original) == 0)
      _ = fcntl(master, F_SETFL, fcntl(master, F_GETFL) | O_NONBLOCK)

      let report = Array("\u{1B}[5;7R".utf8)
      #expect(report.withUnsafeBytes { write(master, $0.baseAddress, $0.count) } == report.count)

      let output = FileHandle(fileDescriptor: slave, closeOnDealloc: false)
      let session = try TerminalSession(
        viewport: .inline(height: 5),
        inputDescriptor: slave,
        output: output
      )
      #expect(session.viewportOrigin == Position(x: 0, y: 4))

      var raw = termios()
      #expect(tcgetattr(slave, &raw) == 0)
      #expect(raw.c_lflag & tcflag_t(ICANON | ECHO) == 0)

      var backend = session.makeBackend()
      #expect(try backend.size() == Size(width: 80, height: 5))
      #expect(backend.viewportOrigin == Position(x: 0, y: 4))

      var input = session.makeInput()
      var resizedWindow = window
      resizedWindow.ws_col = 100
      resizedWindow.ws_row = 40
      #expect(ioctl(slave, UInt(TIOCSWINSZ), &resizedWindow) == 0)
      let resizedSize = Size(width: 100, height: 40)
      #expect(try input.readEvent(timeoutMilliseconds: 0) == .resize(resizedSize))
      #expect(try session.reanchorAfterResize(resizedSize) == .historyReset)
      #expect(session.viewportOrigin == Position(x: 0, y: 0))
      backend = session.makeBackend()
      #expect(try backend.size() == Size(width: 100, height: 5))
      #expect(backend.viewportOrigin == Position(x: 0, y: 0))

      let burst = Array("/model\r".utf8)
      #expect(burst.withUnsafeBytes { write(master, $0.baseAddress, $0.count) } == burst.count)
      var burstEvents: [TerminalEvent] = []
      for _ in burst.indices {
        if let event = try input.readEvent(timeoutMilliseconds: 50) { burstEvents.append(event) }
      }
      #expect(
        burstEvents == [
          .key(KeyEvent(.character("/"))),
          .key(KeyEvent(.character("m"))),
          .key(KeyEvent(.character("o"))),
          .key(KeyEvent(.character("d"))),
          .key(KeyEvent(.character("e"))),
          .key(KeyEvent(.character("l"))),
          .key(KeyEvent(.enter)),
        ])

      try backend.draw([
        CellUpdate(position: Position(x: 0, y: 0), cell: Cell(symbol: "X"))
      ])

      try session.restore()
      try session.restore()
      var restored = termios()
      #expect(tcgetattr(slave, &restored) == 0)
      #expect(restored.c_iflag == original.c_iflag)
      #expect(restored.c_oflag == original.c_oflag)
      #expect(restored.c_cflag == original.c_cflag)
      // Darwin may mark input for reprocessing when canonical mode is restored.
      // PENDIN is kernel state, not a mode owned by TerminalSession.
      #expect(restored.c_lflag & ~tcflag_t(PENDIN) == original.c_lflag & ~tcflag_t(PENDIN))

      let protocolOutput = String(decoding: drain(master), as: UTF8.self)
      #expect(protocolOutput.contains("\u{1B}[?2004h"))
      #expect(!protocolOutput.contains("\u{1B}[?1002h"))
      #expect(!protocolOutput.contains("\u{1B}[?1006h"))
      #expect(protocolOutput.contains("\u{1B}[?u"))
      #expect(protocolOutput.contains("\u{1B}[>1u"))
      #expect(protocolOutput.contains("\u{1B}[6n"))
      #expect(protocolOutput.contains("\u{1B}[?25l\u{1B}[3J\u{1B}[2J\u{1B}[H"))
      #expect(protocolOutput.contains("\u{1B}[5;1H"))
      #expect(!protocolOutput.contains("\u{1B}[5;7H"))
      #expect(protocolOutput.contains("\u{1B}[<u"))
      #expect(protocolOutput.contains("\u{1B}[?2004l"))
      #expect(protocolOutput.contains("\u{1B}[?1006l"))
    }

    @MainActor
    @Test func inlineViewportCanGrowAndShrinkFromItsStableOrigin() throws {
      var master: Int32 = -1
      var slave: Int32 = -1
      var window = winsize()
      window.ws_col = 80
      window.ws_row = 24
      #expect(openpty(&master, &slave, nil, nil, &window) == 0)
      guard master >= 0, slave >= 0 else { return }
      defer {
        close(master)
        close(slave)
      }
      _ = fcntl(master, F_SETFL, fcntl(master, F_GETFL) | O_NONBLOCK)

      let report = Array("\u{1B}[5;1R".utf8)
      #expect(report.withUnsafeBytes { write(master, $0.baseAddress, $0.count) } == report.count)
      let session = try TerminalSession(
        viewport: .inline(height: 1), inputDescriptor: slave,
        output: FileHandle(fileDescriptor: slave, closeOnDealloc: false))
      #expect(session.viewportOrigin == Position(x: 0, y: 4))
      var backend = session.makeBackend()
      #expect(try backend.size() == Size(width: 80, height: 1))

      #expect(try session.updateInlineViewportHeight(5))
      #expect(session.viewportOrigin == Position(x: 0, y: 4))
      backend = session.makeBackend()
      #expect(try backend.size() == Size(width: 80, height: 5))
      #expect(try session.updateInlineViewportHeight(3))
      backend = session.makeBackend()
      #expect(try backend.size() == Size(width: 80, height: 3))
      #expect(try !session.updateInlineViewportHeight(3))

      try session.restore()
    }

    @Test func inlineViewportGrowthAtBottomScrollsOnlyOverflowAndClampsToScreen() throws {
      var master: Int32 = -1
      var slave: Int32 = -1
      var window = winsize(ws_row: 24, ws_col: 80, ws_xpixel: 0, ws_ypixel: 0)
      #expect(openpty(&master, &slave, nil, nil, &window) == 0)
      guard master >= 0, slave >= 0 else { return }
      defer {
        close(master)
        close(slave)
      }
      _ = fcntl(master, F_SETFL, fcntl(master, F_GETFL) | O_NONBLOCK)

      let report = Array("\u{1B}[23;1R".utf8)
      #expect(report.withUnsafeBytes { write(master, $0.baseAddress, $0.count) } == report.count)
      let session = try TerminalSession(
        viewport: .inline(height: 1), inputDescriptor: slave,
        output: FileHandle(fileDescriptor: slave, closeOnDealloc: false))
      #expect(session.viewportOrigin == Position(x: 0, y: 22))

      #expect(try session.updateInlineViewportHeight(5))
      #expect(session.viewportOrigin == Position(x: 0, y: 19))
      var backend = session.makeBackend()
      #expect(try backend.size() == Size(width: 80, height: 5))
      #expect(try session.updateInlineViewportHeight(100))
      #expect(session.viewportOrigin == Position(x: 0, y: 0))
      backend = session.makeBackend()
      #expect(try backend.size() == Size(width: 80, height: 24))
      #expect(try session.updateInlineViewportHeight(1))
      #expect(session.viewportOrigin == Position(x: 0, y: 0))
      try session.restore()

      let output = String(decoding: drain(master), as: UTF8.self)
      #expect(output.contains("\u{1B}[24;1H\r\n\r\n\r\n"))
      #expect(output.contains("\u{1B}[24;1H\u{1B}[2K"))
    }

    @Test func frameOutputTransactionCommitsViewportChangeAndReplacementDrawTogether() throws {
      var master: Int32 = -1
      var slave: Int32 = -1
      var window = winsize(ws_row: 24, ws_col: 80, ws_xpixel: 0, ws_ypixel: 0)
      #expect(openpty(&master, &slave, nil, nil, &window) == 0)
      guard master >= 0, slave >= 0 else { return }
      defer {
        close(master)
        close(slave)
      }
      _ = fcntl(master, F_SETFL, fcntl(master, F_GETFL) | O_NONBLOCK)

      let report = Array("\u{1B}[5;1R".utf8)
      #expect(report.withUnsafeBytes { write(master, $0.baseAddress, $0.count) } == report.count)
      let session = try TerminalSession(
        viewport: .inline(height: 1), inputDescriptor: slave,
        output: FileHandle(fileDescriptor: slave, closeOnDealloc: false))
      _ = drain(master)

      try session.withFrameOutputTransaction {
        #expect(try session.updateInlineViewportHeight(5))
        #expect(drain(master).isEmpty)

        var terminal = try Terminal(backend: session.makeBackend())
        try terminal.draw { frame in
          frame.render(Paragraph("REPLACEMENT"))
        }
        #expect(drain(master).isEmpty)
      }

      let output = String(decoding: drain(master), as: UTF8.self)
      let destructiveClear = output.range(of: "\u{1B}[5;1H\u{1B}[2K")
      let replacement = output.range(of: "REPLACEMENT")
      #expect(destructiveClear != nil)
      #expect(replacement != nil)
      if let destructiveClear, let replacement {
        #expect(destructiveClear.lowerBound < replacement.lowerBound)
      }
      try session.restore()
    }

    @Test func prefetchedInputIsTransferredToOnlyOneInputStream() throws {
      var master: Int32 = -1
      var slave: Int32 = -1
      var window = winsize(ws_row: 24, ws_col: 80, ws_xpixel: 0, ws_ypixel: 0)
      #expect(openpty(&master, &slave, nil, nil, &window) == 0)
      guard master >= 0, slave >= 0 else { return }
      defer {
        close(master)
        close(slave)
      }
      _ = fcntl(master, F_SETFL, fcntl(master, F_GETFL) | O_NONBLOCK)

      let reportAndInput = Array("\u{1B}[5;1Rx".utf8)
      #expect(
        reportAndInput.withUnsafeBytes { write(master, $0.baseAddress, $0.count) }
          == reportAndInput.count)
      let session = try TerminalSession(
        viewport: .inline(height: 1), inputDescriptor: slave,
        output: FileHandle(fileDescriptor: slave, closeOnDealloc: false))

      var first = session.makeInput()
      #expect(
        try first.readEvent(timeoutMilliseconds: 0)
          == .key(KeyEvent(.character("x"))))
      var second = session.makeInput()
      #expect(try second.readEvent(timeoutMilliseconds: 0) == nil)

      try session.restore()
    }

    @Test func rebasingInputPreservesQueuedEventsAndLocalizesFutureMouseInput() throws {
      var master: Int32 = -1
      var slave: Int32 = -1
      var window = winsize(ws_row: 24, ws_col: 80, ws_xpixel: 0, ws_ypixel: 0)
      #expect(openpty(&master, &slave, nil, nil, &window) == 0)
      guard master >= 0, slave >= 0 else { return }
      defer {
        close(master)
        close(slave)
      }
      _ = fcntl(master, F_SETFL, fcntl(master, F_GETFL) | O_NONBLOCK)

      let report = Array("\u{1B}[5;1R".utf8)
      #expect(report.withUnsafeBytes { write(master, $0.baseAddress, $0.count) } == report.count)
      let session = try TerminalSession(
        viewport: .inline(height: 1), inputDescriptor: slave,
        output: FileHandle(fileDescriptor: slave, closeOnDealloc: false))
      var input = session.makeInput()

      let firstBurst = Array("\u{1B}[<0;1;6M\u{1B}[<0;1;7M".utf8)
      #expect(
        firstBurst.withUnsafeBytes { write(master, $0.baseAddress, $0.count) }
          == firstBurst.count)
      #expect(
        try input.readEvent(timeoutMilliseconds: 50)
          == .mouse(MouseEvent(.down(.left), at: Position(x: 0, y: 1))))

      session.synchronizeViewportOrigin(Position(x: 0, y: 6))
      session.synchronizeInput(&input)
      #expect(
        try input.readEvent(timeoutMilliseconds: 0)
          == .mouse(MouseEvent(.down(.left), at: Position(x: 0, y: 2))))

      let futureMouse = Array("\u{1B}[<0;1;8M".utf8)
      #expect(
        futureMouse.withUnsafeBytes { write(master, $0.baseAddress, $0.count) }
          == futureMouse.count)
      #expect(
        try input.readEvent(timeoutMilliseconds: 50)
          == .mouse(MouseEvent(.down(.left), at: Position(x: 0, y: 1))))

      try session.restore()
    }

    @Test func mouseCaptureIsExplicitlyOptIn() throws {
      var master: Int32 = -1
      var slave: Int32 = -1
      var window = winsize(ws_row: 24, ws_col: 80, ws_xpixel: 0, ws_ypixel: 0)
      #expect(openpty(&master, &slave, nil, nil, &window) == 0)
      guard master >= 0, slave >= 0 else { return }
      defer {
        close(master)
        close(slave)
      }
      _ = fcntl(master, F_SETFL, fcntl(master, F_GETFL) | O_NONBLOCK)
      let report = Array("\u{1B}[1;1R".utf8)
      #expect(report.withUnsafeBytes { write(master, $0.baseAddress, $0.count) } == report.count)

      let session = try TerminalSession(
        viewport: .inline(height: 5), capturesMouse: true, inputDescriptor: slave,
        output: FileHandle(fileDescriptor: slave, closeOnDealloc: false))
      try session.restore()

      let output = String(decoding: drain(master), as: UTF8.self)
      #expect(output.contains("\u{1B}[?1002h"))
      #expect(output.contains("\u{1B}[?1006h"))
    }

    @Test func fullHeightInlineViewportUsesThePhysicalScreenHeightForClearing() throws {
      var master: Int32 = -1
      var slave: Int32 = -1
      var window = winsize(ws_row: 24, ws_col: 80, ws_xpixel: 0, ws_ypixel: 0)
      #expect(openpty(&master, &slave, nil, nil, &window) == 0)
      guard master >= 0, slave >= 0 else { return }
      defer {
        close(master)
        close(slave)
      }
      _ = fcntl(master, F_SETFL, fcntl(master, F_GETFL) | O_NONBLOCK)
      let report = Array("\u{1B}[1;1R".utf8)
      #expect(report.withUnsafeBytes { write(master, $0.baseAddress, $0.count) } == report.count)

      let session = try TerminalSession(
        viewport: .inline(height: .max), inputDescriptor: slave,
        output: FileHandle(fileDescriptor: slave, closeOnDealloc: false))
      var backend = session.makeBackend()
      #expect(try backend.size() == Size(width: 80, height: 24))
      try backend.clear()
      try session.restore()

      let output = String(decoding: drain(master), as: UTF8.self)
      #expect(output.components(separatedBy: "\u{1B}[2K").count - 1 == 24)
      #expect(output.utf8.count < 4_096)
    }

    @MainActor
    @Test func inlineViewportAccumulatesFragmentedCursorReports() async throws {
      var master: Int32 = -1
      var slave: Int32 = -1
      var window = winsize(ws_row: 24, ws_col: 80, ws_xpixel: 0, ws_ypixel: 0)
      #expect(openpty(&master, &slave, nil, nil, &window) == 0)
      guard master >= 0, slave >= 0 else { return }
      defer {
        close(master)
        close(slave)
      }
      _ = fcntl(master, F_SETFL, fcntl(master, F_GETFL) | O_NONBLOCK)

      let prefix = Array("\u{1B}[5;".utf8)
      #expect(prefix.withUnsafeBytes { write(master, $0.baseAddress, $0.count) } == prefix.count)
      let masterDescriptor = master
      let suffixWriter = Task.detached {
        try await Task.sleep(for: .milliseconds(20))
        let suffix = Array("1R".utf8)
        return suffix.withUnsafeBytes {
          write(masterDescriptor, $0.baseAddress, $0.count)
        }
      }
      let session = try TerminalSession(
        viewport: .inline(height: 3), inputDescriptor: slave,
        output: FileHandle(fileDescriptor: slave, closeOnDealloc: false))
      #expect(try await suffixWriter.value == 2)
      #expect(session.viewportOrigin == Position(x: 0, y: 4))
      var input = session.makeInput()
      #expect(try input.readEvent(timeoutMilliseconds: 0) == nil)
      try session.restore()
    }

    @MainActor
    @Test func inlineViewportFallsBackToAbsoluteBottomWhenCursorProbeIsUnsupported() throws {
      var master: Int32 = -1
      var slave: Int32 = -1
      var window = winsize(ws_row: 24, ws_col: 80, ws_xpixel: 0, ws_ypixel: 0)
      #expect(openpty(&master, &slave, nil, nil, &window) == 0)
      guard master >= 0, slave >= 0 else { return }
      defer {
        close(master)
        close(slave)
      }
      _ = fcntl(master, F_SETFL, fcntl(master, F_GETFL) | O_NONBLOCK)

      let session = try TerminalSession(
        viewport: .inline(height: 5), inputDescriptor: slave,
        output: FileHandle(fileDescriptor: slave, closeOnDealloc: false))
      var backend = session.makeBackend()
      try backend.draw([
        CellUpdate(position: Position(x: 79, y: 4), cell: Cell(symbol: "X"))
      ])
      try backend.draw([
        CellUpdate(position: Position(x: 0, y: 0), cell: Cell(symbol: "Y"))
      ])
      try session.restore()

      let output = String(decoding: drain(master), as: UTF8.self)
      #expect(output.contains("\r\u{1B}[6n\r\u{1B}[999B\n\n\n\n"))
      #expect(output.contains("\u{1B}[24;80H"))
      #expect(output.contains("\u{1B}[20;1H"))
      #expect(!output.contains("\u{1B}7"))
      #expect(!output.contains("\u{1B}8"))
    }

    @Test func inlineViewportMatchesRatatuiRustWhenCursorIsAtScreenBottom() throws {
      var master: Int32 = -1
      var slave: Int32 = -1
      var window = winsize(ws_row: 24, ws_col: 80, ws_xpixel: 0, ws_ypixel: 0)
      #expect(openpty(&master, &slave, nil, nil, &window) == 0)
      guard master >= 0, slave >= 0 else { return }
      defer {
        close(master)
        close(slave)
      }
      _ = fcntl(master, F_SETFL, fcntl(master, F_GETFL) | O_NONBLOCK)
      let report = Array("\u{1B}[24;9R".utf8)
      #expect(report.withUnsafeBytes { write(master, $0.baseAddress, $0.count) } == report.count)

      let session = try TerminalSession(
        viewport: .inline(height: 5), inputDescriptor: slave,
        output: FileHandle(fileDescriptor: slave, closeOnDealloc: false))
      #expect(session.viewportOrigin == Position(x: 0, y: 19))
      var backend = session.makeBackend()
      try backend.draw([
        CellUpdate(position: Position(x: 0, y: 0), cell: Cell(symbol: "X"))
      ])
      try session.restore()

      let output = String(decoding: drain(master), as: UTF8.self)
      #expect(output.contains("\u{1B}[6n\n\n\n\n"))
      #expect(output.contains("\u{1B}[20;1H"))
    }

    @Test func suspendedActionRestoresAndResumesThePseudoTerminal() async throws {
      var master: Int32 = -1
      var slave: Int32 = -1
      var window = winsize()
      window.ws_col = 80
      window.ws_row = 24
      #expect(openpty(&master, &slave, nil, nil, &window) == 0)
      guard master >= 0, slave >= 0 else { return }
      defer {
        close(master)
        close(slave)
      }

      var original = termios()
      #expect(tcgetattr(slave, &original) == 0)
      _ = fcntl(master, F_SETFL, fcntl(master, F_GETFL) | O_NONBLOCK)
      var report = Array("\u{1B}[5;7R".utf8)
      #expect(report.withUnsafeBytes { write(master, $0.baseAddress, $0.count) } == report.count)

      let session = try TerminalSession(
        viewport: .inline(height: 5), inputDescriptor: slave,
        output: FileHandle(fileDescriptor: slave, closeOnDealloc: false))

      try await session.withRestoredTerminal {
        var restored = termios()
        #expect(tcgetattr(slave, &restored) == 0)
        #expect(
          restored.c_lflag & tcflag_t(ICANON | ECHO) == original.c_lflag & tcflag_t(ICANON | ECHO))
        report = Array("\u{1B}[9;3R".utf8)
        #expect(report.withUnsafeBytes { write(master, $0.baseAddress, $0.count) } == report.count)
      }

      #expect(session.viewportOrigin == Position(x: 0, y: 8))
      var raw = termios()
      #expect(tcgetattr(slave, &raw) == 0)
      #expect(raw.c_lflag & tcflag_t(ICANON | ECHO) == 0)
      try session.restore()

      let protocolOutput = String(decoding: drain(master), as: UTF8.self)
      #expect(protocolOutput.components(separatedBy: "\u{1B}[?2004h").count - 1 == 2)
      #expect(protocolOutput.components(separatedBy: "\u{1B}[?2004l").count - 1 == 2)
    }

    @Test func consecutiveResumeAndResetProbesAppendCapturedInput() throws {
      var master: Int32 = -1
      var slave: Int32 = -1
      var window = winsize(ws_row: 24, ws_col: 80, ws_xpixel: 0, ws_ypixel: 0)
      #expect(openpty(&master, &slave, nil, nil, &window) == 0)
      guard master >= 0, slave >= 0 else { return }
      defer {
        close(master)
        close(slave)
      }
      _ = fcntl(master, F_SETFL, fcntl(master, F_GETFL) | O_NONBLOCK)

      var report = Array("\u{1B}[5;1R".utf8)
      #expect(report.withUnsafeBytes { write(master, $0.baseAddress, $0.count) } == report.count)
      let session = try TerminalSession(
        viewport: .inline(height: 2), inputDescriptor: slave,
        output: FileHandle(fileDescriptor: slave, closeOnDealloc: false))
      var input = session.makeInput()
      try session.suspend()

      let resumeReportAndInput = Array("\u{1B}[6;1Rx".utf8)
      #expect(
        resumeReportAndInput.withUnsafeBytes { write(master, $0.baseAddress, $0.count) }
          == resumeReportAndInput.count)
      try session.resume()
      report = Array("\u{1B}[1;1R".utf8)
      #expect(report.withUnsafeBytes { write(master, $0.baseAddress, $0.count) } == report.count)
      try session.clearScrollbackAndResetViewport()
      session.synchronizeInput(&input)

      #expect(try input.readEvent(timeoutMilliseconds: 0) == .key(KeyEvent(.character("x"))))
      try session.restore()
    }

    @Test func clearScrollbackReanchorsTheInlineViewport() throws {
      var master: Int32 = -1
      var slave: Int32 = -1
      var window = winsize()
      window.ws_col = 80
      window.ws_row = 24
      #expect(openpty(&master, &slave, nil, nil, &window) == 0)
      guard master >= 0, slave >= 0 else { return }
      defer {
        close(master)
        close(slave)
      }
      _ = fcntl(master, F_SETFL, fcntl(master, F_GETFL) | O_NONBLOCK)
      let report = Array("\u{1B}[4;2R".utf8)
      #expect(report.withUnsafeBytes { write(master, $0.baseAddress, $0.count) } == report.count)
      let session = try TerminalSession(
        viewport: .inline(height: 5), inputDescriptor: slave,
        output: FileHandle(fileDescriptor: slave, closeOnDealloc: false))

      try session.clearScrollbackAndResetViewport()
      #expect(session.viewportOrigin == Position(x: 0, y: 0))
      try session.restore()

      let protocolOutput = String(decoding: drain(master), as: UTF8.self)
      #expect(protocolOutput.contains("\u{1B}[3J\u{1B}[2J\u{1B}[H\n\n\n\n"))
      #expect(protocolOutput.components(separatedBy: "\u{1B}[6n").count - 1 == 1)
      #expect(protocolOutput.components(separatedBy: "\u{1B}[>1u").count - 1 == 1)
      #expect(protocolOutput.components(separatedBy: "\u{1B}[<u").count - 1 == 1)
    }

    @MainActor
    @Test func largeBatchedHistoryFinishesThenAcceptsAndRendersInput() async throws {
      var master: Int32 = -1
      var slave: Int32 = -1
      var window = winsize(ws_row: 24, ws_col: 80, ws_xpixel: 0, ws_ypixel: 0)
      #expect(openpty(&master, &slave, nil, nil, &window) == 0)
      guard master >= 0, slave >= 0 else { return }
      defer {
        close(master)
        close(slave)
      }
      _ = fcntl(master, F_SETFL, fcntl(master, F_GETFL) | O_NONBLOCK)
      let capture = PTYOutputCapture(descriptor: master)
      let report = Array("\u{1B}[24;1R".utf8)
      #expect(report.withUnsafeBytes { write(master, $0.baseAddress, $0.count) } == report.count)

      let session = try TerminalSession(
        viewport: .inline(height: 1), inputDescriptor: slave,
        output: FileHandle(fileDescriptor: slave, closeOnDealloc: false),
        backendConfiguration: ANSIBackendConfiguration(historyInsertionStrategy: .terminalOutput))
      let application = LargeHistoryApplication()
      let task = Task { try await application.run(in: session) }
      try await Task.sleep(for: .milliseconds(100))
      let input = Array("xq".utf8)
      #expect(input.withUnsafeBytes { write(master, $0.baseAddress, $0.count) } == input.count)
      try await task.value
      try session.restore()

      let output = String(decoding: capture.finish(), as: UTF8.self)
      #expect(output.contains("HISTORY-0"))
      #expect(output.contains("HISTORY-599"))
      #expect(output.contains("READY"))
      #expect(output.contains("[24;7H\u{1B}[0mx"))
      #expect(output.components(separatedBy: "\u{1B}[?7l").count - 1 == 1)
      #expect(output.components(separatedBy: "\u{1B}[?7h").count - 1 >= 1)
    }

    @Test func nativeHistoryBatchClampsItsOriginWhenPTYResizesBetweenChunks() throws {
      var master: Int32 = -1
      var slave: Int32 = -1
      var window = winsize(ws_row: 6, ws_col: 10, ws_xpixel: 0, ws_ypixel: 0)
      #expect(openpty(&master, &slave, nil, nil, &window) == 0)
      guard master >= 0, slave >= 0 else { return }
      defer {
        close(master)
        close(slave)
      }

      var backend = ANSIBackend(
        output: FileHandle(fileDescriptor: slave, closeOnDealloc: false),
        viewportHeight: 2,
        viewportOrigin: Position(x: 0, y: 4),
        cursorAddressing: .absoluteOrigin(Position(x: 0, y: 4)),
        configuration: ANSIBackendConfiguration(historyInsertionStrategy: .terminalOutput)
      )
      var first = Buffer(area: Rect(x: 0, y: 0, width: 10, height: 1))
      first.setString("FIRST", at: Position(x: 0, y: 0))
      var last = Buffer(area: Rect(x: 0, y: 0, width: 10, height: 1))
      last.setString("LAST", at: Position(x: 0, y: 0))

      #expect(try backend.insertHistory(first, batchPosition: .first))
      window.ws_row = 4
      #expect(ioctl(master, TIOCSWINSZ, &window) == 0)
      #expect(try backend.insertHistory(last, batchPosition: .last))
      #expect(backend.viewportOrigin == Position(x: 0, y: 2))
    }

    @MainActor
    @Test func pendingHistoryResetReplaysTheCanonicalInlineDocument() async throws {
      var master: Int32 = -1
      var slave: Int32 = -1
      var window = winsize(ws_row: 12, ws_col: 40, ws_xpixel: 0, ws_ypixel: 0)
      #expect(openpty(&master, &slave, nil, nil, &window) == 0)
      guard master >= 0, slave >= 0 else { return }
      defer {
        close(master)
        close(slave)
      }
      _ = fcntl(master, F_SETFL, fcntl(master, F_GETFL) | O_NONBLOCK)
      let capture = PTYOutputCapture(descriptor: master)
      let report = Array("\u{1B}[12;1R".utf8)
      #expect(report.withUnsafeBytes { write(master, $0.baseAddress, $0.count) } == report.count)

      let session = try TerminalSession(
        viewport: .inline(height: 1), inputDescriptor: slave,
        output: FileHandle(fileDescriptor: slave, closeOnDealloc: false),
        backendConfiguration: ANSIBackendConfiguration(historyInsertionStrategy: .terminalOutput))
      let application = PendingHistoryResetApplication()
      let task = Task { try await application.run(in: session) }
      try await Task.sleep(for: .milliseconds(100))
      let input = Array("rq".utf8)
      #expect(input.withUnsafeBytes { write(master, $0.baseAddress, $0.count) } == input.count)
      try await task.value
      try session.restore()

      let output = String(decoding: capture.finish(), as: UTF8.self)
      #expect(output.components(separatedBy: "REPLAY-ME").count - 1 >= 2)
      #expect(output.contains("AFTER-RESET"))
      #expect(!output.contains("STALE-BEFORE-RESET"))
    }

    @Test func observationWakeupInterruptsAWaitingInputPoll() async throws {
      var master: Int32 = -1
      var slave: Int32 = -1
      var window = winsize(ws_row: 8, ws_col: 20, ws_xpixel: 0, ws_ypixel: 0)
      #expect(openpty(&master, &slave, nil, nil, &window) == 0)
      guard master >= 0, slave >= 0 else { return }
      let masterDescriptor = master
      let slaveDescriptor = slave
      defer {
        close(masterDescriptor)
        close(slaveDescriptor)
      }
      let wakeup = TerminalWakeup()
      let reader = Task.detached { () throws -> Duration in
        var input = TerminalInput(
          inputDescriptor: slaveDescriptor, outputDescriptor: slaveDescriptor)
        let clock = ContinuousClock()
        let started = clock.now
        _ = try input.readEvent(timeoutMilliseconds: 500, wakeup: wakeup)
        return started.duration(to: clock.now)
      }

      try await Task.sleep(for: .milliseconds(20))
      wakeup.signal()
      let elapsed = try await reader.value

      #expect(elapsed < .milliseconds(200))
    }

    @MainActor
    @Test func applicationRunTracksObservableReadsInsideWidgetRendering() async throws {
      var master: Int32 = -1
      var slave: Int32 = -1
      var window = winsize(ws_row: 8, ws_col: 20, ws_xpixel: 0, ws_ypixel: 0)
      #expect(openpty(&master, &slave, nil, nil, &window) == 0)
      guard master >= 0, slave >= 0 else { return }
      defer {
        close(master)
        close(slave)
      }
      _ = fcntl(master, F_SETFL, fcntl(master, F_GETFL) | O_NONBLOCK)
      let report = Array("\u{1B}[1;1R".utf8)
      #expect(report.withUnsafeBytes { write(master, $0.baseAddress, $0.count) } == report.count)

      let session = try TerminalSession(
        viewport: .inline(height: 1), inputDescriptor: slave,
        output: FileHandle(fileDescriptor: slave, closeOnDealloc: false))
      let application = RenderObservationApplication()
      let task = Task { try await application.run(in: session) }
      try await Task.sleep(for: .milliseconds(30))
      application.model.value = "B"
      try await Task.sleep(for: .milliseconds(130))
      let quit = Array("q".utf8)
      #expect(quit.withUnsafeBytes { write(master, $0.baseAddress, $0.count) } == quit.count)
      try await task.value
      try session.restore()

      let output = String(decoding: drain(master), as: UTF8.self)
      #expect(output.contains("A"))
      #expect(output.contains("B"))
    }

    @MainActor
    @Test func observationInvalidationDuringAsyncUpdateIsNotLost() async throws {
      var master: Int32 = -1
      var slave: Int32 = -1
      var window = winsize(ws_row: 8, ws_col: 20, ws_xpixel: 0, ws_ypixel: 0)
      #expect(openpty(&master, &slave, nil, nil, &window) == 0)
      guard master >= 0, slave >= 0 else { return }
      defer {
        close(master)
        close(slave)
      }
      _ = fcntl(master, F_SETFL, fcntl(master, F_GETFL) | O_NONBLOCK)
      let report = Array("\u{1B}[1;1R".utf8)
      #expect(report.withUnsafeBytes { write(master, $0.baseAddress, $0.count) } == report.count)

      let session = try TerminalSession(
        viewport: .inline(height: 1), inputDescriptor: slave,
        output: FileHandle(fileDescriptor: slave, closeOnDealloc: false))
      let application = RenderObservationApplication()
      let task = Task { try await application.run(in: session) }
      try await Task.sleep(for: .milliseconds(30))
      let mutate = Array("x".utf8)
      #expect(mutate.withUnsafeBytes { write(master, $0.baseAddress, $0.count) } == mutate.count)
      try await Task.sleep(for: .milliseconds(130))
      let quit = Array("q".utf8)
      #expect(quit.withUnsafeBytes { write(master, $0.baseAddress, $0.count) } == quit.count)
      try await task.value
      try session.restore()

      let output = String(decoding: drain(master), as: UTF8.self)
      #expect(output.contains("A"))
      #expect(output.contains("B"))
      #expect(output.components(separatedBy: "\u{1B}[?2026h").count - 1 == 2)
    }

    @MainActor
    @Test func applicationCoalescesSynchronousObservableMutationsIntoOneFrame() async throws {
      var master: Int32 = -1
      var slave: Int32 = -1
      var window = winsize(ws_row: 8, ws_col: 20, ws_xpixel: 0, ws_ypixel: 0)
      #expect(openpty(&master, &slave, nil, nil, &window) == 0)
      guard master >= 0, slave >= 0 else { return }
      defer {
        close(master)
        close(slave)
      }
      _ = fcntl(master, F_SETFL, fcntl(master, F_GETFL) | O_NONBLOCK)
      let report = Array("\u{1B}[1;1R".utf8)
      #expect(report.withUnsafeBytes { write(master, $0.baseAddress, $0.count) } == report.count)

      let session = try TerminalSession(
        viewport: .inline(height: 1), inputDescriptor: slave,
        output: FileHandle(fileDescriptor: slave, closeOnDealloc: false))
      let application = RenderObservationApplication()
      let task = Task { try await application.run(in: session) }
      try await Task.sleep(for: .milliseconds(30))
      application.model.value = "B"
      application.model.value = "C"
      application.model.value = "D"
      try await Task.sleep(for: .milliseconds(130))
      let quit = Array("q".utf8)
      #expect(quit.withUnsafeBytes { write(master, $0.baseAddress, $0.count) } == quit.count)
      try await task.value
      try session.restore()

      let output = String(decoding: drain(master), as: UTF8.self)
      #expect(output.contains("A"))
      #expect(output.contains("D"))
      #expect(!output.contains("B"))
      #expect(!output.contains("C"))
      #expect(output.components(separatedBy: "\u{1B}[?2026h").count - 1 == 2)
    }

    @MainActor
    @Test func applicationCanDisableAutomaticObservationRedraws() async throws {
      var master: Int32 = -1
      var slave: Int32 = -1
      var window = winsize(ws_row: 8, ws_col: 20, ws_xpixel: 0, ws_ypixel: 0)
      #expect(openpty(&master, &slave, nil, nil, &window) == 0)
      guard master >= 0, slave >= 0 else { return }
      defer {
        close(master)
        close(slave)
      }
      _ = fcntl(master, F_SETFL, fcntl(master, F_GETFL) | O_NONBLOCK)
      let report = Array("\u{1B}[1;1R".utf8)
      #expect(report.withUnsafeBytes { write(master, $0.baseAddress, $0.count) } == report.count)

      let session = try TerminalSession(
        viewport: .inline(height: 1), inputDescriptor: slave,
        output: FileHandle(fileDescriptor: slave, closeOnDealloc: false))
      let application = RenderObservationApplication(automaticallyTracksObservableState: false)
      let task = Task { try await application.run(in: session) }
      try await Task.sleep(for: .milliseconds(30))
      application.model.value = "B"
      try await Task.sleep(for: .milliseconds(100))
      let quit = Array("q".utf8)
      #expect(quit.withUnsafeBytes { write(master, $0.baseAddress, $0.count) } == quit.count)
      try await task.value
      try session.restore()

      let output = String(decoding: drain(master), as: UTF8.self)
      #expect(output.contains("A"))
      #expect(!output.contains("B"))
    }

    @MainActor
    @Test func applicationRunCanOptIntoRedrawsForUnobservedExternalState() async throws {
      var master: Int32 = -1
      var slave: Int32 = -1
      var window = winsize(ws_row: 8, ws_col: 20, ws_xpixel: 0, ws_ypixel: 0)
      #expect(openpty(&master, &slave, nil, nil, &window) == 0)
      guard master >= 0, slave >= 0 else { return }
      defer {
        close(master)
        close(slave)
      }
      _ = fcntl(master, F_SETFL, fcntl(master, F_GETFL) | O_NONBLOCK)
      let report = Array("\u{1B}[1;1R".utf8)
      #expect(report.withUnsafeBytes { write(master, $0.baseAddress, $0.count) } == report.count)

      let session = try TerminalSession(
        viewport: .inline(height: 1), inputDescriptor: slave,
        output: FileHandle(fileDescriptor: slave, closeOnDealloc: false))
      let application = PeriodicRedrawApplication()
      let task = Task { try await application.run(in: session) }
      try await Task.sleep(for: .milliseconds(30))
      application.value = "B"
      application.needsPeriodicRedraw = false
      try await Task.sleep(for: .milliseconds(130))
      let quit = Array("q".utf8)
      #expect(quit.withUnsafeBytes { write(master, $0.baseAddress, $0.count) } == quit.count)
      try await task.value
      try session.restore()

      let output = String(decoding: drain(master), as: UTF8.self)
      #expect(output.contains("A"))
      #expect(output.contains("B"))
    }

    @MainActor
    @Test func applicationRunAppliesUpdatesReturnedBySyntheticFocusEvents() async throws {
      var master: Int32 = -1
      var slave: Int32 = -1
      var window = winsize(ws_row: 8, ws_col: 20, ws_xpixel: 0, ws_ypixel: 0)
      #expect(openpty(&master, &slave, nil, nil, &window) == 0)
      guard master >= 0, slave >= 0 else { return }
      defer {
        close(master)
        close(slave)
      }
      _ = fcntl(master, F_SETFL, fcntl(master, F_GETFL) | O_NONBLOCK)
      let report = Array("\u{1B}[1;1R".utf8)
      #expect(report.withUnsafeBytes { write(master, $0.baseAddress, $0.count) } == report.count)

      let session = try TerminalSession(
        viewport: .inline(height: 1), inputDescriptor: slave,
        output: FileHandle(fileDescriptor: slave, closeOnDealloc: false))
      let application = FocusEffectApplication()
      let task = Task { try await application.run(in: session) }
      try await Task.sleep(for: .milliseconds(100))
      let fallbackQuit = Array("q".utf8)
      #expect(
        fallbackQuit.withUnsafeBytes { write(master, $0.baseAddress, $0.count) }
          == fallbackQuit.count)
      try await task.value
      try session.restore()

      #expect(application.receivedEvents == [.focusChanged("quit")])
    }

    @MainActor
    @Test func applicationResetPreservesQueuedInputFocusAndKeyboardProtocolBalance() async throws {
      var master: Int32 = -1
      var slave: Int32 = -1
      var window = winsize(ws_row: 8, ws_col: 20, ws_xpixel: 0, ws_ypixel: 0)
      #expect(openpty(&master, &slave, nil, nil, &window) == 0)
      guard master >= 0, slave >= 0 else { return }
      defer {
        close(master)
        close(slave)
      }
      _ = fcntl(master, F_SETFL, fcntl(master, F_GETFL) | O_NONBLOCK)
      let report = Array("\u{1B}[1;1R".utf8)
      #expect(report.withUnsafeBytes { write(master, $0.baseAddress, $0.count) } == report.count)

      let session = try TerminalSession(
        viewport: .inline(height: 2), inputDescriptor: slave,
        output: FileHandle(fileDescriptor: slave, closeOnDealloc: false))
      let application = ResetInputApplication()
      let task = Task { try await application.run(in: session) }
      try await Task.sleep(for: .milliseconds(30))
      let burst: [UInt8] = [0x09, 0x67, 0x71]
      #expect(burst.withUnsafeBytes { write(master, $0.baseAddress, $0.count) } == burst.count)
      try await task.value
      try session.restore()

      #expect(
        application.receivedEvents == [
          .focusChanged("first"), .focusChanged("second"),
          .key(KeyEvent(.character("g"))), .key(KeyEvent(.character("q"))),
        ])
      let output = String(decoding: drain(master), as: UTF8.self)
      #expect(output.components(separatedBy: "\u{1B}[>1u").count - 1 == 1)
      #expect(output.components(separatedBy: "\u{1B}[<u").count - 1 == 1)
    }

    private func drain(_ descriptor: Int32) -> [UInt8] {
      var result: [UInt8] = []
      var chunk = [UInt8](repeating: 0, count: 4096)
      while true {
        let count = read(descriptor, &chunk, chunk.count)
        guard count > 0 else { break }
        result.append(contentsOf: chunk.prefix(count))
      }
      return result
    }
  }
#endif
