#if canImport(Darwin)
  import Darwin
  import Foundation
  import Observation
  import Testing

  @testable import TermLoom

  private enum IdleLoopTestError: Error {
    case pseudoTerminalUnavailable
  }

  /// A pseudo-terminal whose output side is drained continuously, so the application never blocks
  /// writing frames.
  private final class IdleLoopPTY: @unchecked Sendable {
    let master: Int32
    let slave: Int32
    private let source: DispatchSourceRead
    private let lock = NSLock()
    private let cancelled = DispatchSemaphore(value: 0)
    private var bytes: [UInt8] = []

    init(columns: UInt16 = 20, rows: UInt16 = 8) throws {
      var master: Int32 = -1
      var slave: Int32 = -1
      var window = winsize(ws_row: rows, ws_col: columns, ws_xpixel: 0, ws_ypixel: 0)
      guard openpty(&master, &slave, nil, nil, &window) == 0, master >= 0, slave >= 0 else {
        throw IdleLoopTestError.pseudoTerminalUnavailable
      }
      self.master = master
      self.slave = slave
      _ = fcntl(master, F_SETFL, fcntl(master, F_GETFL) | O_NONBLOCK)
      source = DispatchSource.makeReadSource(fileDescriptor: master, queue: .global())
      source.setEventHandler { [weak self] in self?.readAvailable() }
      source.setCancelHandler { [cancelled] in cancelled.signal() }
      source.resume()
    }

    var output: String {
      lock.withLock { String(decoding: bytes, as: UTF8.self) }
    }

    var byteCount: Int { lock.withLock { bytes.count } }

    /// Output written after the first `offset` bytes.
    func output(after offset: Int) -> String {
      lock.withLock { String(decoding: bytes[min(offset, bytes.count)...], as: UTF8.self) }
    }

    func send(_ text: String) {
      let input = Array(text.utf8)
      _ = input.withUnsafeBytes { write(master, $0.baseAddress, $0.count) }
    }

    func resize(columns: UInt16, rows: UInt16) {
      var window = winsize(ws_row: rows, ws_col: columns, ws_xpixel: 0, ws_ypixel: 0)
      _ = ioctl(slave, UInt(TIOCSWINSZ), &window)
    }

    func finish() {
      source.cancel()
      cancelled.wait()
      Darwin.close(master)
      Darwin.close(slave)
    }

    private func readAvailable() {
      var buffer = [UInt8](repeating: 0, count: 16_384)
      while true {
        let count = read(master, &buffer, buffer.count)
        guard count > 0 else { return }
        lock.withLock { bytes.append(contentsOf: buffer.prefix(count)) }
      }
    }
  }

  private final class ReadinessFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var isReady = false

    var ready: Bool { lock.withLock { isReady } }

    func markReady() {
      lock.withLock { isReady = true }
    }
  }

  @MainActor private final class StaticIdleApplication: TerminalApplication {
    var renders = 0
    var events: [TerminalEvent] = []
    var suspendedActions = 0

    var body: Paragraph {
      renders += 1
      return Paragraph("IDLE \(events.count)")
    }

    func update(_ event: TerminalEvent) async -> ApplicationUpdate {
      events.append(event)
      guard case .key(let key) = event else { return .ignore }
      switch key.key {
      case .character("q"): return .quit
      case .character("s"): return .suspend
      case .character("x"): return .redraw
      default: return .ignore
      }
    }

    func performSuspendedAction() async {
      suspendedActions += 1
    }
  }

  // Greek letters cannot be mistaken for CSI final bytes in the written frame.
  @MainActor @Observable private final class IdleObservableModel {
    var value = "α"
  }

  @MainActor private final class ObservedIdleApplication: TerminalApplication {
    let model = IdleObservableModel()
    var renders = 0

    var body: Paragraph {
      renders += 1
      return Paragraph("VALUE \(model.value)")
    }

    func update(_ event: TerminalEvent) async -> ApplicationUpdate {
      if case .key(let key) = event, key.key == .character("q") { return .quit }
      return .ignore
    }
  }

  /// A periodic application whose flag is a plain stored property the loop cannot observe.
  @MainActor
  private final class PollingPeriodicApplication: TerminalApplication,
    PeriodicallyRedrawingTerminalApplication
  {
    var needsPeriodicRedraw = true
    var renders = 0

    var body: Paragraph {
      renders += 1
      return Paragraph("FRAME \(renders)")
    }

    func update(_ event: TerminalEvent) async -> ApplicationUpdate {
      if case .key(let key) = event, key.key == .character("q") { return .quit }
      return .ignore
    }
  }

  /// A periodic application with an explicit redraw scheduler, like Postcat's explicit mode: the
  /// flag is derived from observable state, but frames are not tracked automatically.
  @MainActor @Observable
  private final class ObservablePeriodicApplication: TerminalApplication,
    PeriodicallyRedrawingTerminalApplication
  {
    var loading = false
    @ObservationIgnored var renders = 0

    var needsPeriodicRedraw: Bool { loading }
    var automaticallyTracksObservableState: Bool { false }

    var body: Paragraph {
      renders += 1
      return Paragraph("FRAME \(renders)")
    }

    func update(_ event: TerminalEvent) async -> ApplicationUpdate {
      if case .key(let key) = event, key.key == .character("q") { return .quit }
      return .ignore
    }
  }

  @MainActor
  @Suite(.serialized) struct IdleLoopTests {
    @Test func idleApplicationBlocksWithoutWakingOrRendering() async throws {
      let pty = try IdleLoopPTY()
      defer { pty.finish() }
      let session = try makeSession(pty)
      let application = StaticIdleApplication()
      let statistics = ApplicationLoopStatistics()
      let task = Task {
        try await application.run(
          in: session,
          configuration: ApplicationLoopConfiguration(
            receivesResizeSignals: true, statistics: statistics))
      }
      try await eventually { statistics.snapshot.indefiniteWaits >= 1 }
      try await Task.sleep(for: .milliseconds(20))
      let before = statistics.snapshot
      let rendersBefore = application.renders

      try await Task.sleep(for: .milliseconds(300))

      let after = statistics.snapshot
      #expect(rendersBefore == 1)
      #expect(application.renders == rendersBefore)
      #expect(after.wakeups == before.wakeups)
      #expect(after.timedWaits == 0)
      pty.send("q")
      try await task.value
      try session.restore()
    }

    @Test func withoutResizeSignalsTheLoopKeepsPollingAtTheInputInterval() async throws {
      let pty = try IdleLoopPTY()
      defer { pty.finish() }
      let session = try makeSession(pty)
      // The pseudo-terminal is not this process's controlling terminal, so no SIGWINCH arrives.
      #expect(!session.receivesResizeSignals)
      let application = StaticIdleApplication()
      let statistics = ApplicationLoopStatistics()
      let task = Task {
        try await application.run(
          in: session, configuration: ApplicationLoopConfiguration(statistics: statistics))
      }
      try await eventually { statistics.snapshot.timedWaits >= 1 }
      let before = statistics.snapshot
      let rendersBefore = application.renders

      try await Task.sleep(for: .milliseconds(300))

      let after = statistics.snapshot
      #expect(after.wakeups - before.wakeups >= 2)
      #expect(after.indefiniteWaits == 0)
      #expect(application.renders == rendersBefore)

      // Polling still notices a resize without any signal.
      pty.resize(columns: 30, rows: 10)
      try await eventually { application.events.contains(.resize(Size(width: 30, height: 10))) }
      pty.send("q")
      try await task.value
      try session.restore()
    }

    @Test func resizeSignalWakesTheLoopAndRedrawsExactlyOnce() async throws {
      let pty = try IdleLoopPTY()
      defer { pty.finish() }
      let session = try makeSession(pty)
      let application = StaticIdleApplication()
      let statistics = ApplicationLoopStatistics()
      let task = Task {
        try await application.run(
          in: session,
          configuration: ApplicationLoopConfiguration(
            receivesResizeSignals: true, statistics: statistics))
      }
      try await eventually { statistics.snapshot.indefiniteWaits >= 1 }
      try await Task.sleep(for: .milliseconds(20))
      let before = statistics.snapshot
      let rendersBefore = application.renders

      // The loop waits without a timeout, so only the signal can make it notice the new size.
      pty.resize(columns: 30, rows: 10)
      kill(getpid(), SIGWINCH)
      let resized = TerminalEvent.resize(Size(width: 30, height: 10))
      try await eventually { application.events.contains(resized) }
      try await Task.sleep(for: .milliseconds(100))

      let after = statistics.snapshot
      #expect(application.events == [resized])
      #expect(application.renders == rendersBefore + 1)
      #expect(after.wakeups == before.wakeups + 1)
      #expect(after.timedWaits == 0)

      // A signal without a size change wakes the loop but renders nothing.
      kill(getpid(), SIGWINCH)
      try await eventually { statistics.snapshot.wakeups == after.wakeups + 1 }
      try await Task.sleep(for: .milliseconds(50))
      #expect(application.events == [resized])
      #expect(application.renders == rendersBefore + 1)
      pty.send("q")
      try await task.value
      try session.restore()
    }

    @Test func observationChangesFromOtherTasksWakeTheIdleLoopPromptly() async throws {
      let pty = try IdleLoopPTY()
      defer { pty.finish() }
      let session = try makeSession(pty)
      let application = ObservedIdleApplication()
      let statistics = ApplicationLoopStatistics()
      let task = Task {
        try await application.run(
          in: session,
          configuration: ApplicationLoopConfiguration(
            receivesResizeSignals: true, statistics: statistics))
      }
      try await eventually { statistics.snapshot.indefiniteWaits >= 1 }
      try await Task.sleep(for: .milliseconds(20))
      let before = statistics.snapshot
      let rendersBefore = application.renders

      // A background task posts its result to the main-actor model. Frames write only changed
      // cells, so look for the new value inside a complete frame written after the change.
      let model = application.model
      let outputBeforeB = pty.byteCount
      Task.detached {
        try? await Task.sleep(for: .milliseconds(10))
        await MainActor.run { model.value = "β" }
      }
      try await eventually(timeout: .seconds(1)) {
        let written = pty.output(after: outputBeforeB)
        return written.contains("β") && written.contains("\u{1B}[?2026l")
      }
      try await Task.sleep(for: .milliseconds(50))
      #expect(application.renders == rendersBefore + 1)
      #expect(statistics.snapshot.wakeups == before.wakeups + 1)

      // A main-actor task mutating the model while the loop is blocked.
      let outputBeforeC = pty.byteCount
      Task { @MainActor in model.value = "γ" }
      try await eventually(timeout: .seconds(1)) {
        let written = pty.output(after: outputBeforeC)
        return written.contains("γ") && written.contains("\u{1B}[?2026l")
      }
      try await Task.sleep(for: .milliseconds(50))
      #expect(application.renders == rendersBefore + 2)
      #expect(statistics.snapshot.wakeups == before.wakeups + 2)
      #expect(statistics.snapshot.timedWaits == 0)
      pty.send("q")
      try await task.value
      try session.restore()
    }

    @Test func unobservablePeriodicRedrawsTickAtTheInputInterval() async throws {
      let pty = try IdleLoopPTY()
      defer { pty.finish() }
      let session = try makeSession(pty)
      let application = PollingPeriodicApplication()
      let statistics = ApplicationLoopStatistics()
      let task = Task {
        try await application.run(
          in: session,
          configuration: ApplicationLoopConfiguration(
            receivesResizeSignals: true, statistics: statistics))
      }
      try await eventually { application.renders >= 2 }
      let rendersBefore = application.renders

      try await Task.sleep(for: .milliseconds(500))

      // One frame per 50 ms input interval.
      let ticks = application.renders - rendersBefore
      #expect(ticks >= 4)
      #expect(ticks <= 11)
      #expect(statistics.snapshot.indefiniteWaits == 0)

      // The flag cannot be observed, so it is still re-checked at the input interval: the change
      // produces the trailing frame and later flips would still be noticed.
      application.needsPeriodicRedraw = false
      try await Task.sleep(for: .milliseconds(150))
      let settledRenders = application.renders
      let settled = statistics.snapshot
      try await Task.sleep(for: .milliseconds(200))
      #expect(application.renders == settledRenders)
      #expect(statistics.snapshot.timedWaits > settled.timedWaits)
      #expect(statistics.snapshot.indefiniteWaits == 0)

      application.needsPeriodicRedraw = true
      try await eventually { application.renders >= settledRenders + 2 }
      pty.send("q")
      try await task.value
      try session.restore()
    }

    @Test func observablePeriodicFlagWakesTheLoopAndSleepsAfterTheTrailingFrame() async throws {
      let pty = try IdleLoopPTY()
      defer { pty.finish() }
      let session = try makeSession(pty)
      let application = ObservablePeriodicApplication()
      let statistics = ApplicationLoopStatistics()
      let task = Task {
        try await application.run(
          in: session,
          configuration: ApplicationLoopConfiguration(
            receivesResizeSignals: true, statistics: statistics))
      }
      try await eventually { statistics.snapshot.indefiniteWaits >= 1 }
      try await Task.sleep(for: .milliseconds(20))
      let idle = statistics.snapshot
      let idleRenders = application.renders
      try await Task.sleep(for: .milliseconds(200))
      #expect(statistics.snapshot.wakeups == idle.wakeups)
      #expect(application.renders == idleRenders)

      // Starting work while the loop is blocked wakes it; frames then follow the input interval.
      application.loading = true
      try await eventually { application.renders >= idleRenders + 3 }
      #expect(statistics.snapshot.timedWaits > 0)
      let activeStart = application.renders
      try await Task.sleep(for: .milliseconds(500))
      let ticks = application.renders - activeStart
      #expect(ticks >= 4)
      #expect(ticks <= 11)

      // Finishing work renders exactly one trailing frame, then the loop blocks again.
      application.loading = false
      let rendersAtStop = application.renders
      let waitsAtStop = statistics.snapshot.indefiniteWaits
      try await eventually { statistics.snapshot.indefiniteWaits > waitsAtStop }
      try await Task.sleep(for: .milliseconds(20))
      let stopped = statistics.snapshot
      let stoppedRenders = application.renders
      #expect(stoppedRenders == rendersAtStop + 1)
      try await Task.sleep(for: .milliseconds(200))
      #expect(statistics.snapshot.wakeups == stopped.wakeups)
      #expect(application.renders == stoppedRenders)
      pty.send("q")
      try await task.value
      try session.restore()
    }

    @Test func loneEscapeStillResolvesWhileTheLoopWaitsIndefinitely() async throws {
      let pty = try IdleLoopPTY()
      defer { pty.finish() }
      let session = try makeSession(pty)
      let application = StaticIdleApplication()
      let statistics = ApplicationLoopStatistics()
      let task = Task {
        try await application.run(
          in: session,
          configuration: ApplicationLoopConfiguration(
            receivesResizeSignals: true, statistics: statistics))
      }
      try await eventually { statistics.snapshot.indefiniteWaits >= 1 }
      pty.send("\u{1B}")
      try await eventually(timeout: .seconds(1)) {
        application.events.contains(.key(KeyEvent(.escape)))
      }
      pty.send("q")
      try await task.value
      try session.restore()
      #expect(
        application.events == [.key(KeyEvent(.escape)), .key(KeyEvent(.character("q")))])
    }

    @Test func suspendResumeAndQuitStillWorkWithIndefiniteWaits() async throws {
      let pty = try IdleLoopPTY()
      defer { pty.finish() }
      let session = try makeSession(pty)
      let application = StaticIdleApplication()
      let statistics = ApplicationLoopStatistics()
      let task = Task {
        try await application.run(
          in: session,
          configuration: ApplicationLoopConfiguration(
            receivesResizeSignals: true, statistics: statistics))
      }
      try await eventually { statistics.snapshot.indefiniteWaits >= 1 }
      let waitsBeforeSuspend = statistics.snapshot.indefiniteWaits
      pty.send("s")
      try await eventually { application.suspendedActions == 1 }
      try await eventually { statistics.snapshot.indefiniteWaits > waitsBeforeSuspend }
      try await Task.sleep(for: .milliseconds(20))
      let resumed = statistics.snapshot
      let resumedRenders = application.renders
      #expect(resumedRenders == 2)
      try await Task.sleep(for: .milliseconds(200))
      #expect(statistics.snapshot.wakeups == resumed.wakeups)
      #expect(application.renders == resumedRenders)

      pty.send("x")
      try await eventually { application.renders == resumedRenders + 1 }
      pty.send("q")
      try await task.value
      try session.restore()
      #expect(
        application.events == [
          .key(KeyEvent(.character("s"))), .key(KeyEvent(.character("x"))),
          .key(KeyEvent(.character("q"))),
        ])
      #expect(statistics.snapshot.timedWaits == 0)
    }

    @Test func cancellingAnIdleLoopWakesItImmediately() async throws {
      let pty = try IdleLoopPTY()
      defer { pty.finish() }
      let session = try makeSession(pty)
      let application = StaticIdleApplication()
      let statistics = ApplicationLoopStatistics()
      let task = Task {
        try await application.run(
          in: session,
          configuration: ApplicationLoopConfiguration(
            receivesResizeSignals: true, statistics: statistics))
      }
      try await eventually { statistics.snapshot.indefiniteWaits >= 1 }
      // Should cancellation fail to wake the wait, quit after a while instead of hanging.
      let watchdog = Task {
        try await Task.sleep(for: .seconds(2))
        pty.send("q")
      }
      let clock = ContinuousClock()
      let started = clock.now
      task.cancel()
      try await task.value
      let elapsed = started.duration(to: clock.now)
      watchdog.cancel()
      try session.restore()
      #expect(elapsed < .seconds(1))
      #expect(application.events.isEmpty)
    }

    @Test func indefiniteReadReportsAResizeAsSoonAsItIsWoken() async throws {
      let pty = try IdleLoopPTY()
      defer { pty.finish() }
      let wakeup = TerminalWakeup()
      let ready = ReadinessFlag()
      let slave = pty.slave
      let reader = Task.detached { () throws -> TerminalEvent? in
        var input = TerminalInput(inputDescriptor: slave, outputDescriptor: slave)
        ready.markReady()
        return try input.readEvent(waitMilliseconds: nil, wakeup: wakeup)
      }
      try await eventually { ready.ready }
      try await Task.sleep(for: .milliseconds(20))
      pty.resize(columns: 30, rows: 10)
      wakeup.signal()
      #expect(try await reader.value == .resize(Size(width: 30, height: 10)))
    }

    @Test func indefiniteReadStillResolvesALoneEscapeAfterTheInputInterval() throws {
      let pty = try IdleLoopPTY()
      defer { pty.finish() }
      let session = try TerminalSession(
        viewport: .fixed(Rect(x: 0, y: 0, width: 20, height: 8)),
        inputDescriptor: pty.slave,
        output: FileHandle(fileDescriptor: pty.slave, closeOnDealloc: false))
      var input = session.makeInput()
      pty.send("\u{1B}")
      #expect(try input.readEvent(waitMilliseconds: nil, wakeup: nil) == nil)
      let clock = ContinuousClock()
      let started = clock.now
      #expect(try input.readEvent(waitMilliseconds: nil, wakeup: nil) == .key(KeyEvent(.escape)))
      #expect(started.duration(to: clock.now) >= .milliseconds(40))
      try session.restore()
    }

    private func makeSession(_ pty: IdleLoopPTY) throws -> TerminalSession {
      try TerminalSession(
        viewport: .fullscreen, inputDescriptor: pty.slave,
        output: FileHandle(fileDescriptor: pty.slave, closeOnDealloc: false),
        backendConfiguration: .full)
    }

    /// Waits until `condition` holds, recording an issue if it does not within `timeout`.
    private func eventually(
      timeout: Duration = .seconds(2), sourceLocation: SourceLocation = #_sourceLocation,
      _ condition: () -> Bool
    ) async throws {
      let clock = ContinuousClock()
      let deadline = clock.now + timeout
      while !condition() {
        if clock.now >= deadline {
          Issue.record("condition not met within \(timeout)", sourceLocation: sourceLocation)
          return
        }
        try await Task.sleep(for: .milliseconds(1))
      }
    }
  }
#endif
