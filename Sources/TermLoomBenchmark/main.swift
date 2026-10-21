import Foundation
import Observation
import TermLoom

#if canImport(Darwin)
  import Darwin
#endif

struct Row: Hashable, Sendable {
  var name: String
  var value: Int
}

@Observable final class BenchmarkModel {
  var selectedRow = 0
}

struct BenchmarkSample: Codable {
  var name: String
  var iterations: Int
  var seconds: Double
  var nanosecondsPerIteration: Double
  var iterationsPerSecond: Double
  var cellUpdatesPerIteration: Double?
  var outputBytesPerIteration: Double?
  var retainedBytesDelta: Int64?
  var peakResidentBytes: Int64?
  var framesPerIteration: Double?
}

struct BenchmarkOptions {
  var iterations = 5_000
  var suite = "frames"
  var emitsJSON = false

  init(arguments: [String]) {
    var index = 0
    while index < arguments.count {
      switch arguments[index] {
      case "--iterations":
        if arguments.indices.contains(index + 1), let value = Int(arguments[index + 1]) {
          iterations = max(1, value)
          index += 1
        }
      case "--suite":
        if arguments.indices.contains(index + 1) {
          suite = arguments[index + 1]
          index += 1
        }
      case "--json":
        emitsJSON = true
      default:
        if let value = Int(arguments[index]) { iterations = max(1, value) }
      }
      index += 1
    }
  }
}

private struct SingleCell: Widget {
  var symbol: String

  func render(in area: Rect, into frame: inout Frame) {
    guard !area.isEmpty else { return }
    frame.buffer.setString(symbol, at: Position(x: area.x, y: area.y))
  }
}

private struct InteractionGrid: Widget {
  var count: Int

  func render(in area: Rect, into frame: inout Frame) {
    guard area.width > 0, area.height > 0 else { return }
    frame.buffer.setString("interaction grid", at: Position(x: area.x, y: area.y))
    for index in 0..<count {
      frame.addInteraction(
        InteractionRegion(
          control: ControlID("item-\(index)"),
          area: Rect(
            x: area.x &+ Int(index % area.width),
            y: area.y &+ Int((index / area.width) % area.height),
            width: 1,
            height: 1),
          action: ActionID("activate-\(index)"),
          isFocusable: true))
    }
  }
}

private let rows = (0..<30).map { Row(name: "worker-\($0)", value: $0 * 7) }
private let clock = ContinuousClock()

private func dashboard(selectedRow: Int) -> some Widget {
  Block(title: "Workers") {
    Table(rows, selectedRow: selectedRow) {
      TableColumn("Name", value: \.name, width: .flex(2))
      TableColumn("Value", value: \.value, alignment: .trailing)
    }
  }
}

private func seconds(_ duration: Duration) -> Double {
  let components = duration.components
  return Double(components.seconds) + Double(components.attoseconds) / 1e18
}

private func retainedBytes() -> Int64? {
  #if canImport(Darwin)
    var statistics = malloc_statistics_t()
    malloc_zone_statistics(malloc_default_zone(), &statistics)
    return Int64(statistics.size_in_use)
  #else
    return nil
  #endif
}

private func peakResidentBytes() -> Int64? {
  #if canImport(Darwin)
    var usage = rusage()
    guard getrusage(RUSAGE_SELF, &usage) == 0 else { return nil }
    return Int64(usage.ru_maxrss)
  #else
    return nil
  #endif
}

private func measure(
  _ name: String,
  iterations: Int,
  operation: (Int) throws -> Int
) rethrows -> BenchmarkSample {
  let retainedBefore = retainedBytes()
  var cellUpdates = 0
  let elapsed = try clock.measure {
    for iteration in 0..<iterations {
      cellUpdates += try operation(iteration)
    }
  }
  let retainedAfter = retainedBytes()
  let elapsedSeconds = seconds(elapsed)
  return BenchmarkSample(
    name: name,
    iterations: iterations,
    seconds: elapsedSeconds,
    nanosecondsPerIteration: elapsedSeconds * 1e9 / Double(iterations),
    iterationsPerSecond: Double(iterations) / elapsedSeconds,
    cellUpdatesPerIteration: Double(cellUpdates) / Double(iterations),
    outputBytesPerIteration: nil,
    retainedBytesDelta: retainedBefore.flatMap { before in
      retainedAfter.map { $0 - before }
    },
    peakResidentBytes: peakResidentBytes())
}

private func frameBenchmarks(iterations: Int) throws -> [BenchmarkSample] {
  var samples: [BenchmarkSample] = []

  var dashboardTerminal = try Terminal(backend: TestBackend(width: 120, height: 40))
  samples.append(
    try measure("frame/dashboard-diff", iterations: iterations) { iteration in
      try dashboardTerminal.draw { frame in
        frame.render(dashboard(selectedRow: iteration % rows.count))
      }.updates
    })

  let model = BenchmarkModel()
  var observedTerminal = try Terminal(backend: TestBackend(width: 120, height: 40))
  samples.append(
    try measure("frame/dashboard-observation", iterations: iterations) { iteration in
      model.selectedRow = iteration % rows.count
      let widget = withObservationTracking {
        dashboard(selectedRow: model.selectedRow)
      } onChange: {
      }
      let result: Result<CompletedFrame, any Error> = withObservationTracking {
        Result {
          try observedTerminal.draw { frame in frame.render(widget) }
        }
      } onChange: {
      }
      return try result.get().updates
    })

  var staticTerminal = try Terminal(backend: TestBackend(width: 120, height: 40))
  _ = try staticTerminal.draw { $0.render(Fill(" ")) }
  samples.append(
    try measure("frame/static", iterations: iterations) { _ in
      try staticTerminal.draw { $0.render(Fill(" ")) }.updates
    })

  var singleCellTerminal = try Terminal(backend: TestBackend(width: 120, height: 40))
  samples.append(
    try measure("frame/one-cell", iterations: iterations) { iteration in
      try singleCellTerminal.draw {
        $0.render(SingleCell(symbol: iteration.isMultiple(of: 2) ? "A" : "B"))
      }.updates
    })

  var fullFrameTerminal = try Terminal(backend: TestBackend(width: 120, height: 40))
  samples.append(
    try measure("frame/full-churn", iterations: iterations) { iteration in
      try fullFrameTerminal.draw {
        $0.render(
          Fill(
            iteration.isMultiple(of: 2) ? "A" : "B",
            style: Style(background: iteration.isMultiple(of: 2) ? .blue : .magenta)))
      }.updates
    })

  var cursorTerminal = try Terminal(backend: TestBackend(width: 120, height: 40))
  _ = try cursorTerminal.draw { $0.render(Fill(" ")) }
  samples.append(
    try measure("frame/cursor-only", iterations: iterations) { iteration in
      try cursorTerminal.draw { frame in
        frame.render(Fill(" "))
        frame.placeCursor(
          at: Position(x: Int(iteration % 120), y: Int((iteration / 120) % 40)),
          style: .steadyBar)
      }.updates
    })

  var emptyInteractionTerminal = try Terminal(backend: TestBackend(width: 120, height: 40))
  samples.append(
    try measure("frame/0-interactions", iterations: iterations) { _ in
      try emptyInteractionTerminal.draw { $0.render(InteractionGrid(count: 0)) }.updates
    })

  var interactionTerminal = try Terminal(backend: TestBackend(width: 120, height: 40))
  samples.append(
    try measure("frame/100-interactions", iterations: iterations) { _ in
      try interactionTerminal.draw { $0.render(InteractionGrid(count: 100)) }.updates
    })

  return samples
}

private func primitiveBenchmarks(iterations: Int) throws -> [BenchmarkSample] {
  var samples: [BenchmarkSample] = []

  for dimension in [16, 64, 255] {
    let scaledIterations = max(1, iterations / max(1, dimension / 16))
    var retainedCellCount = 0
    var sample = measure(
      "buffer/empty/\(dimension)x\(dimension)", iterations: scaledIterations
    ) { _ in
      let buffer = Buffer(
        area: Rect(
          x: 0, y: 0, width: dimension, height: dimension))
      retainedCellCount ^= buffer.count
      return 0
    }
    sample.cellUpdatesPerIteration = nil
    withExtendedLifetime(retainedCellCount) {}
    samples.append(sample)
  }

  let constraints = Array(repeating: Constraint.flex(1), count: 10)
  var layoutChecksum = 0
  var layoutSample = measure("layout/10-fill", iterations: iterations) { _ in
    let areas = Layout(.vertical, constraints: constraints).split(
      Rect(x: 0, y: 0, width: 120, height: 40))
    layoutChecksum ^= areas.count
    return 0
  }
  layoutSample.cellUpdatesPerIteration = nil
  withExtendedLifetime(layoutChecksum) {}
  samples.append(layoutSample)

  for lineCount in [64, 2_048] {
    let text = Text(
      (0..<lineCount).map {
        Line("line \($0) alpha beta gamma delta epsilon zeta eta theta")
      })
    let paragraph = Paragraph(text, wrap: .word, trimLeadingWhitespace: false)
    var buffer = Buffer(area: Rect(x: 0, y: 0, width: 100, height: 50))
    let scaledIterations = max(1, iterations / max(1, lineCount / 64))
    var sample = measure(
      "paragraph/wrap/\(lineCount)-lines", iterations: scaledIterations
    ) { _ in
      buffer.reset()
      paragraph.render(
        in: buffer.area, into: &buffer, environment: RenderEnvironment())
      return 0
    }
    sample.cellUpdatesPerIteration = nil
    samples.append(sample)
  }

  let scrolledText = Text(
    (0..<2_048).map {
      Line("line \($0) alpha beta gamma delta epsilon zeta eta theta")
    })
  let scrolledParagraph = Paragraph(
    scrolledText,
    wrap: .word,
    scroll: 1_024,
    trimLeadingWhitespace: false
  )
  var scrolledBuffer = Buffer(area: Rect(x: 0, y: 0, width: 100, height: 50))
  var scrolledSample = measure(
    "paragraph/wrap/2048-lines/scrolled-1024", iterations: max(1, iterations / 32)
  ) { _ in
    scrolledBuffer.reset()
    scrolledParagraph.render(
      in: scrolledBuffer.area,
      into: &scrolledBuffer,
      environment: RenderEnvironment()
    )
    return 0
  }
  scrolledSample.cellUpdatesPerIteration = nil
  samples.append(scrolledSample)

  for rowCount in [64, 2_048] {
    let tableRows = (0..<rowCount).map { Row(name: "worker-\($0)", value: $0 * 7) }
    let table = Table(tableRows, selectedRow: rowCount / 2) {
      TableColumn("Name", value: \.name, width: .flex(2))
      TableColumn("Value", value: \.value, alignment: .trailing)
    }
    var buffer = Buffer(area: Rect(x: 0, y: 0, width: 120, height: 50))
    let scaledIterations = max(1, iterations / max(1, rowCount / 64))
    var sample = measure(
      "table/render/\(rowCount)x2", iterations: scaledIterations
    ) { _ in
      buffer.reset()
      table.render(in: buffer.area, into: &buffer, environment: RenderEnvironment())
      return 0
    }
    sample.cellUpdatesPerIteration = nil
    samples.append(sample)
  }

  return samples
}

private func collectionBenchmarks(iterations: Int) -> [BenchmarkSample] {
  var samples: [BenchmarkSample] = []
  let longUnicode = String(repeating: "界é👨‍👩‍👧‍👦", count: 100_000)
  let styledLine = Line([
    Span(longUnicode, style: Style(foreground: .cyan)),
    Span(longUnicode, style: Style(modifiers: [.bold])),
  ])

  var checksum = 0
  var stringSample = measure(
    "fitting/string-unicode-100k", iterations: max(1, iterations / 10)
  ) { _ in
    checksum ^= TerminalWidth.truncated(longUnicode, to: 80).utf8.count
    return 0
  }
  stringSample.cellUpdatesPerIteration = nil
  samples.append(stringSample)

  var fullWidthSample = measure(
    "fitting/full-width-reference-100k", iterations: max(1, iterations / 100)
  ) { _ in
    checksum ^= TerminalWidth.of(longUnicode)
    return 0
  }
  fullWidthSample.cellUpdatesPerIteration = nil
  samples.append(fullWidthSample)

  var lineSample = measure(
    "fitting/line-unicode-200k", iterations: max(1, iterations / 10)
  ) { _ in
    checksum ^= styledLine.truncated(to: 80).spans.count
    return 0
  }
  lineSample.cellUpdatesPerIteration = nil
  samples.append(lineSample)

  let selectableRows = SelectableRows(
    itemCount: 1_000_000,
    selectedIndex: 500_000,
    interaction: { index in InteractionDescriptor(control: ControlID("row-\(index)")) },
    row: { row, frame in
      frame.buffer.setString(
        "row \(row.index)", at: Position(x: row.area.x, y: row.area.y))
    }
  )
  let rowArea = Rect(x: 0, y: 0, width: 100, height: 40)
  var rowsSample = measure("viewport/selectable-million", iterations: iterations) { _ in
    var rowFrame = Frame(buffer: Buffer(area: rowArea))
    rowFrame.render(selectableRows)
    checksum ^= rowFrame.interactions.regions.count
    return 0
  }
  rowsSample.cellUpdatesPerIteration = nil
  samples.append(rowsSample)

  for count in [1_000, 100_000] {
    let widths = Array(repeating: 12, count: count)
    let scaledIterations = max(1, iterations / max(1, count / 1_000))
    var tabSample = measure(
      "viewport/tabs-\(count)", iterations: scaledIterations
    ) { _ in
      let viewport = TabViewport.fitting(
        widths: widths,
        selectedIndex: count / 2,
        capacity: 120,
        spacing: 1,
        leadingOverflowWidth: 1,
        trailingOverflowWidth: 1,
        placement: .center
      )
      checksum ^= viewport.range.count
      return 0
    }
    tabSample.cellUpdatesPerIteration = nil
    samples.append(tabSample)
  }

  withExtendedLifetime(checksum) {}
  return samples
}

private func ansiOutputBenchmark(
  name: String,
  iterations: Int,
  render: (Int, inout Frame) -> Void
) throws -> BenchmarkSample {
  let url = FileManager.default.temporaryDirectory
    .appendingPathComponent("termloom-benchmark-\(UUID().uuidString).ansi")
  _ = FileManager.default.createFile(atPath: url.path, contents: nil)
  defer { try? FileManager.default.removeItem(at: url) }
  let output = try FileHandle(forWritingTo: url)
  defer { try? output.close() }
  var terminal = try Terminal(
    backend: ANSIBackend(
      output: output,
      fallbackSize: Size(width: 120, height: 40),
      configuration: .full))
  var sample = try measure(name, iterations: iterations) { iteration in
    try terminal.draw { frame in render(iteration, &frame) }.updates
  }
  try output.synchronize()
  let byteCount = try output.offset()
  sample.outputBytesPerIteration = Double(byteCount) / Double(iterations)
  return sample
}

private func outputBenchmarks(iterations: Int) throws -> [BenchmarkSample] {
  let outputIterations = min(iterations, 1_000)
  return [
    try ansiOutputBenchmark(
      name: "ansi/static", iterations: outputIterations
    ) { _, frame in
      frame.render(Fill(" "))
    },
    try ansiOutputBenchmark(
      name: "ansi/one-cell", iterations: outputIterations
    ) { iteration, frame in
      frame.render(SingleCell(symbol: iteration.isMultiple(of: 2) ? "A" : "B"))
    },
    try ansiOutputBenchmark(
      name: "ansi/full-churn", iterations: outputIterations
    ) { iteration, frame in
      frame.render(
        Fill(
          iteration.isMultiple(of: 2) ? "A" : "B",
          style: Style(background: iteration.isMultiple(of: 2) ? .blue : .magenta)))
    },
  ]
}

// MARK: - Application run loop

// The `loop` suite drives the public `TerminalApplication.run(viewport:capturesMouse:)` path
// through a pseudo-terminal. Standard input and output are temporarily redirected to the PTY
// slave while a driver thread writes input to the master side and a drain thread counts the
// bytes the application emits.

private enum LoopBenchmarkError: Error, CustomStringConvertible {
  case pseudoTerminalUnavailable
  case redirectionFailed
  case writeFailed
  case timedOut(String)
  case driverDidNotFinish

  var description: String {
    switch self {
    case .pseudoTerminalUnavailable: "openpty failed"
    case .redirectionFailed: "could not redirect standard input and output to the pseudo-terminal"
    case .writeFailed: "could not write input to the pseudo-terminal"
    case .timedOut(let stage): "timed out waiting for \(stage)"
    case .driverDidNotFinish: "the loop benchmark driver did not finish"
    }
  }
}

/// Frame and update counters shared by the main-actor application and the driver thread.
private final class LoopProbe: @unchecked Sendable {
  struct Snapshot {
    var frames = 0
    var updates = 0
    var updatesAtLastFrame = 0
  }

  private let lock = NSLock()
  private let rendered = DispatchSemaphore(value: 0)
  private var state = Snapshot()

  var snapshot: Snapshot { lock.withLock { state } }

  func recordUpdate() {
    lock.withLock { state.updates += 1 }
  }

  func recordFrame() {
    lock.withLock {
      state.frames += 1
      state.updatesAtLastFrame = state.updates
    }
    rendered.signal()
  }

  func waitForFrame(
    _ stage: String, timeoutSeconds: Double = 10, until condition: (Snapshot) -> Bool
  ) throws {
    let deadline = DispatchTime.now() + timeoutSeconds
    while !condition(snapshot) {
      if rendered.wait(timeout: deadline) == .timedOut, !condition(snapshot) {
        throw LoopBenchmarkError.timedOut(stage)
      }
    }
  }
}

/// Continuously drains the PTY master so terminal output can never block the application.
private final class PseudoTerminalOutputDrain: @unchecked Sendable {
  private let descriptor: Int32
  private let lock = NSLock()
  private let finished = DispatchSemaphore(value: 0)
  private var byteCount = 0
  private var lastReadUptime = DispatchTime.now().uptimeNanoseconds
  private var isStopping = false

  init(descriptor: Int32) {
    self.descriptor = descriptor
  }

  var bytes: Int { lock.withLock { byteCount } }

  func start() {
    Thread { [self] in drain() }.start()
  }

  /// Waits until no output has arrived for `milliseconds`, so trailing frame output is attributed
  /// to the workload that produced it.
  func waitForQuiet(milliseconds: UInt64 = 25, timeoutSeconds: Double = 5) {
    let quiet = milliseconds * 1_000_000
    let deadline = DispatchTime.now() + timeoutSeconds
    while DispatchTime.now() < deadline {
      let last = lock.withLock { lastReadUptime }
      let now = DispatchTime.now().uptimeNanoseconds
      if now >= last, now - last >= quiet { return }
      usleep(2_000)
    }
  }

  func stop(timeoutSeconds: Double = 2) {
    lock.withLock { isStopping = true }
    _ = finished.wait(timeout: .now() + timeoutSeconds)
  }

  private func drain() {
    var buffer = [UInt8](repeating: 0, count: 16_384)
    while true {
      var descriptors = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
      let ready = poll(&descriptors, 1, 10)
      if ready > 0 {
        let count = read(descriptor, &buffer, buffer.count)
        if count > 0 {
          let now = DispatchTime.now().uptimeNanoseconds
          lock.withLock {
            byteCount += count
            lastReadUptime = now
          }
          continue
        }
        if count == 0 || (errno != EAGAIN && errno != EINTR) { break }
      } else if ready < 0, errno != EINTR {
        break
      }
      if lock.withLock({ isStopping }) { break }
    }
    finished.signal()
  }
}

private struct LoopWorkload: Sendable {
  var steadyFrames: Int
  var bursts: Int
  var burstPayload: [UInt8]
  var burstEvents: Int

  init(iterations: Int) {
    steadyFrames = min(iterations, 1_000)
    bursts = max(1, min(iterations / 100, 20))
    // One 1,000-byte bracketed paste followed by 200 alternating SGR mouse-motion and key events,
    // delivered with a single write.
    var payload = Array("\u{1B}[200~".utf8)
    payload += (0..<1_000).map { UInt8(ascii: "a") + UInt8($0 % 26) }
    payload += Array("\u{1B}[201~".utf8)
    var events = 1
    for index in 0..<200 {
      if index.isMultiple(of: 2) {
        payload += Array("\u{1B}[<35;\(index % 120 + 1);\(index % 40 + 1)M".utf8)
      } else {
        payload.append(UInt8(ascii: "j"))
      }
      events += 1
    }
    burstPayload = payload
    burstEvents = events
  }
}

private struct LoopResult: Sendable {
  var steadySeconds = 0.0
  var steadyStateChanges = 0
  var steadyFrames = 0
  var steadyBytes = 0
  var burstSeconds = 0.0
  var burstFrames = 0
  var burstBytes = 0
  var failure: String?
}

/// Writes input to the PTY master from a dedicated thread and measures the application's response.
private final class LoopDriver: @unchecked Sendable {
  private let master: Int32
  private let probe: LoopProbe
  private let output: PseudoTerminalOutputDrain
  private let workload: LoopWorkload
  private let finished = DispatchSemaphore(value: 0)
  private let lock = NSLock()
  private var result = LoopResult()

  init(
    master: Int32, probe: LoopProbe, output: PseudoTerminalOutputDrain, workload: LoopWorkload
  ) {
    self.master = master
    self.probe = probe
    self.output = output
    self.workload = workload
  }

  func start() {
    Thread { [self] in drive() }.start()
  }

  func waitForResult(timeoutSeconds: Double = 30) -> LoopResult? {
    guard finished.wait(timeout: .now() + timeoutSeconds) == .success else { return nil }
    return lock.withLock { result }
  }

  private func drive() {
    var measured = LoopResult()
    do {
      try measure(into: &measured)
    } catch {
      measured.failure = String(describing: error)
    }
    // Always ask the application to quit, including after a failed measurement.
    try? send(Array("q".utf8))
    lock.withLock { result = measured }
    finished.signal()
  }

  private func measure(into result: inout LoopResult) throws {
    try probe.waitForFrame("the initial frame") { $0.frames >= 1 }
    output.waitForQuiet()

    // a) Steady redraw: one state change per frame, sent only after the previous frame rendered.
    let steadyBefore = probe.snapshot
    let steadyBytesBefore = output.bytes
    let steadyStart = DispatchTime.now().uptimeNanoseconds
    for _ in 0..<workload.steadyFrames {
      let frames = probe.snapshot.frames
      try send(Array("j".utf8))
      try probe.waitForFrame("a steady-state frame") { $0.frames > frames }
    }
    result.steadySeconds = Self.seconds(since: steadyStart)
    result.steadyStateChanges = workload.steadyFrames
    output.waitForQuiet()
    result.steadyFrames = probe.snapshot.frames - steadyBefore.frames
    result.steadyBytes = output.bytes - steadyBytesBefore

    // b) Burst: everything arrives in one write; wait until a frame reflects the final event.
    for _ in 0..<workload.bursts {
      let before = probe.snapshot
      let bytesBefore = output.bytes
      let start = DispatchTime.now().uptimeNanoseconds
      try send(workload.burstPayload)
      let target = before.updates + workload.burstEvents
      try probe.waitForFrame("the burst to become idle") { $0.updatesAtLastFrame >= target }
      result.burstSeconds += Self.seconds(since: start)
      output.waitForQuiet()
      result.burstFrames += probe.snapshot.frames - before.frames
      result.burstBytes += output.bytes - bytesBefore
    }
  }

  private func send(_ bytes: [UInt8]) throws {
    var offset = 0
    while offset < bytes.count {
      let count = bytes[offset...].withUnsafeBytes { buffer in
        write(master, buffer.baseAddress, buffer.count)
      }
      if count < 0 {
        if errno == EINTR || errno == EAGAIN { continue }
        throw LoopBenchmarkError.writeFailed
      }
      offset += count
    }
  }

  private static func seconds(since start: UInt64) -> Double {
    Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9
  }
}

private struct LoopDashboard: Widget {
  var selectedRow: Int
  var status: String
  var probe: LoopProbe

  func render(in area: Rect, into frame: inout Frame) {
    let sections = Layout(.vertical, constraints: [.flex(1), .length(1)]).split(area)
    frame.render(dashboard(selectedRow: selectedRow), in: sections[0])
    frame.render(Paragraph(status), in: sections[1])
    probe.recordFrame()
  }
}

@MainActor private final class LoopBenchmarkApplication: TerminalApplication {
  let probe: LoopProbe
  var selectedRow = 0
  var pointer = Position(x: 0, y: 0)
  var pastedCharacters = 0
  var events = 0

  init(probe: LoopProbe) {
    self.probe = probe
  }

  var body: LoopDashboard {
    let status = "events \(events) pointer \(pointer.x),\(pointer.y) pasted \(pastedCharacters)"
    return LoopDashboard(selectedRow: selectedRow, status: status, probe: probe)
  }

  func update(_ event: TerminalEvent) async -> ApplicationUpdate {
    probe.recordUpdate()
    events += 1
    switch event {
    case .key(let key) where key.key == .character("q"):
      return .quit
    case .key:
      selectedRow = (selectedRow + 1) % rows.count
      return .redraw
    case .mouse(let mouse):
      pointer = mouse.position
      return .redraw
    case .paste(let text):
      pastedCharacters += text.count
      return .redraw
    default:
      return .ignore
    }
  }
}

@MainActor
private func loopBenchmarks(iterations: Int) async throws -> [BenchmarkSample] {
  #if canImport(Darwin)
    let workload = LoopWorkload(iterations: iterations)
    var master: Int32 = -1
    var slave: Int32 = -1
    var window = winsize(ws_row: 40, ws_col: 120, ws_xpixel: 0, ws_ypixel: 0)
    guard openpty(&master, &slave, nil, nil, &window) == 0 else {
      throw LoopBenchmarkError.pseudoTerminalUnavailable
    }
    // Keep the detected backend configuration stable across hosts.
    setenv("TERM", "xterm-256color", 1)
    fflush(nil)
    let savedInput = dup(STDIN_FILENO)
    let savedOutput = dup(STDOUT_FILENO)
    func restoreStandardStreams() {
      if savedInput >= 0 {
        dup2(savedInput, STDIN_FILENO)
        close(savedInput)
      }
      if savedOutput >= 0 {
        dup2(savedOutput, STDOUT_FILENO)
        close(savedOutput)
      }
      close(slave)
    }
    guard savedInput >= 0, savedOutput >= 0,
      dup2(slave, STDIN_FILENO) >= 0, dup2(slave, STDOUT_FILENO) >= 0
    else {
      restoreStandardStreams()
      close(master)
      throw LoopBenchmarkError.redirectionFailed
    }

    let output = PseudoTerminalOutputDrain(descriptor: master)
    output.start()
    let probe = LoopProbe()
    let driver = LoopDriver(master: master, probe: probe, output: output, workload: workload)
    driver.start()
    let application = LoopBenchmarkApplication(probe: probe)
    var runError: (any Error)?
    do {
      try await application.run(viewport: .fullscreen, capturesMouse: true)
    } catch {
      runError = error
    }
    let measured = driver.waitForResult()
    restoreStandardStreams()
    output.stop()
    close(master)

    if let runError { throw runError }
    guard let measured else { throw LoopBenchmarkError.driverDidNotFinish }
    if let failure = measured.failure { throw LoopBenchmarkError.timedOut(failure) }

    let peakResident = peakResidentBytes()
    let steadyCount = max(1, measured.steadyStateChanges)
    let steadySeconds = max(measured.steadySeconds, .leastNonzeroMagnitude)
    let burstSeconds = max(measured.burstSeconds, .leastNonzeroMagnitude)
    return [
      BenchmarkSample(
        name: "loop/steady-redraw",
        iterations: steadyCount,
        seconds: measured.steadySeconds,
        nanosecondsPerIteration: measured.steadySeconds * 1e9 / Double(steadyCount),
        iterationsPerSecond: Double(steadyCount) / steadySeconds,
        cellUpdatesPerIteration: nil,
        outputBytesPerIteration: Double(measured.steadyBytes) / Double(steadyCount),
        retainedBytesDelta: nil,
        peakResidentBytes: peakResident,
        framesPerIteration: Double(measured.steadyFrames) / Double(steadyCount)),
      BenchmarkSample(
        name: "loop/burst-paste-1000b-200-events",
        iterations: workload.bursts,
        seconds: measured.burstSeconds,
        nanosecondsPerIteration: measured.burstSeconds * 1e9 / Double(workload.bursts),
        iterationsPerSecond: Double(workload.bursts) / burstSeconds,
        cellUpdatesPerIteration: nil,
        outputBytesPerIteration: Double(measured.burstBytes) / Double(workload.bursts),
        retainedBytesDelta: nil,
        peakResidentBytes: peakResident,
        framesPerIteration: Double(measured.burstFrames) / Double(workload.bursts)),
    ]
  #else
    return []
  #endif
}

private func printSamples(_ samples: [BenchmarkSample], asJSON: Bool) throws {
  if asJSON {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    print(String(decoding: try encoder.encode(samples), as: UTF8.self))
    return
  }
  for sample in samples {
    var metrics = [
      String(format: "%.0f ns/iteration", sample.nanosecondsPerIteration),
      String(format: "%.0f iterations/s", sample.iterationsPerSecond),
    ]
    if let updates = sample.cellUpdatesPerIteration {
      metrics.append(String(format: "%.2f cell updates/iteration", updates))
    }
    if let bytes = sample.outputBytesPerIteration {
      metrics.append(String(format: "%.2f output bytes/iteration", bytes))
    }
    if let frames = sample.framesPerIteration {
      metrics.append(String(format: "%.2f frames/iteration", frames))
    }
    if let retained = sample.retainedBytesDelta {
      metrics.append("\(retained) retained bytes")
    }
    if let resident = sample.peakResidentBytes {
      metrics.append("\(resident) peak RSS bytes")
    }
    print("\(sample.name): \(sample.iterations) iterations; \(metrics.joined(separator: "; "))")
  }
}

let options = BenchmarkOptions(arguments: Array(CommandLine.arguments.dropFirst()))
let validSuites = ["frames", "primitives", "collections", "output", "loop", "all"]
guard validSuites.contains(options.suite) else {
  FileHandle.standardError.write(
    Data("unknown suite '\(options.suite)'; expected \(validSuites.joined(separator: ", "))\n".utf8)
  )
  exit(2)
}

var samples: [BenchmarkSample] = []
if options.suite == "frames" || options.suite == "all" {
  samples += try frameBenchmarks(iterations: options.iterations)
}
if options.suite == "primitives" || options.suite == "all" {
  samples += try primitiveBenchmarks(iterations: options.iterations)
}
if options.suite == "collections" || options.suite == "all" {
  samples += collectionBenchmarks(iterations: options.iterations)
}
if options.suite == "output" || options.suite == "all" {
  samples += try outputBenchmarks(iterations: options.iterations)
}
if options.suite == "loop" || options.suite == "all" {
  samples += try await loopBenchmarks(iterations: options.iterations)
}
try printSamples(samples, asJSON: options.emitsJSON)
