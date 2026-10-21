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
  /// Frames rendered by the application body (loop suite only).
  var framesPerIteration: Double?
  /// Frames written to the terminal, counted as synchronized-output blocks (loop suite only).
  var writtenFramesPerIteration: Double?
  /// Process CPU time per wall-clock second (idle loop measurements only).
  var cpuMicrosecondsPerSecond: Double?
  /// Voluntary context switches per second: each ended blocking wait is one (idle loop only).
  var voluntaryContextSwitchesPerSecond: Double?
  var involuntaryContextSwitchesPerSecond: Double?
  /// Frames rendered by the body per second (idle loop measurements only).
  var framesPerSecond: Double?
  /// Synchronized-output blocks written per second (idle loop measurements only).
  var writtenFramesPerSecond: Double?
  /// The slowest iteration (resize latency only).
  var maximumLatencyMilliseconds: Double?
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

// MARK: - Text drawing

// The `text` suite measures string -> cell drawing: grapheme segmentation, width measurement,
// clipping, alignment and wrapping. Every operation draws a whole 120x40 screen (or one list or
// paragraph viewport of that size), so ns/iteration is the cost of one frame's text.

private let textScreen = Rect(x: 0, y: 0, width: 120, height: 40)

/// Deterministic ASCII prose, `length` bytes, starting at a row-dependent offset.
private func asciiText(row: Int, length: Int) -> String {
  let words = [
    "alpha", "beta", "gamma", "delta", "epsilon", "zeta", "eta", "theta", "iota", "kappa", "lambda",
    "mu", "worker-\(row)", "status=ok", "42ms", "[INFO]",
  ]
  var result = ""
  var index = row
  while result.utf8.count < length {
    result += words[index % words.count] + " "
    index += 7
  }
  return String(result.prefix(length))
}

/// Deterministic mixed text, about `columns` terminal columns long: wide CJK and Hangul, a
/// combining accent, a ZWJ family, an emoji presentation selector, a flag, a skin-tone modifier,
/// precomposed Latin, Greek and ASCII.
private func mixedText(row: Int, columns: Int) -> String {
  let pieces = [
    "\u{754C}\u{9762}", "e\u{301}", "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}",
    "ok ", "\u{2714}\u{FE0F}", "\u{1F1EF}\u{1F1F5}",
    "\u{65E5}\u{672C}\u{8A9E}\u{30C6}\u{30AD}\u{30B9}\u{30C8} ", "caf\u{E9} ",
    "\u{D55C}\u{AD6D}\u{C5B4} ", "\u{1F44D}\u{1F3FD}", "abc ", "\u{3A9}\u{2248} ",
  ]
  var result = ""
  var index = row
  var usedColumns = 0
  while usedColumns < columns {
    let piece = pieces[index % pieces.count]
    result += piece
    usedColumns += TerminalWidth.of(piece)
    index += 5
  }
  return result
}

private func textBenchmarks(iterations: Int) throws -> [BenchmarkSample] {
  var samples: [BenchmarkSample] = []
  let environment = RenderEnvironment()
  let frameIterations = max(1, iterations / 5)

  func bufferSample(
    _ name: String,
    iterations: Int,
    draw: (inout Buffer, Int) -> Void
  ) -> BenchmarkSample {
    var buffer = Buffer(area: textScreen)
    var sample = measure(name, iterations: iterations) { iteration in
      draw(&buffer, iteration)
      return 0
    }
    withExtendedLifetime(buffer) {}
    sample.cellUpdatesPerIteration = nil
    return sample
  }

  // Two alternating contents so each frame really rewrites every cell.
  let asciiLines = (0..<2).map { variant in
    (0..<textScreen.height).map { asciiText(row: $0 + variant, length: textScreen.width) }
  }
  let mixedLines = (0..<2).map { variant in
    (0..<textScreen.height).map { mixedText(row: $0 + variant, columns: textScreen.width) }
  }
  let longASCIILines = (0..<textScreen.height).map { asciiText(row: $0, length: 400) }

  let kinds = [("ascii", asciiLines), ("mixed", mixedLines)]
  for (kind, lines) in kinds {
    let name = "text/setString/\(kind)-120x40"
    samples.append(
      bufferSample(name, iterations: frameIterations) { buffer, iteration in
        for (row, line) in lines[iteration % 2].enumerated() {
          buffer.setString(line, at: Position(x: 0, y: row))
        }
      })
  }

  let clippedName = "text/setString/ascii-clipped-400-to-120x40"
  samples.append(
    bufferSample(clippedName, iterations: frameIterations) { buffer, _ in
      for (row, line) in longASCIILines.enumerated() {
        buffer.setString(line, at: Position(x: 0, y: row), maxWidth: textScreen.width)
      }
    })

  for (kind, lines) in kinds {
    let texts = lines.map { variant in
      Text(variant.map { Line([Span($0, style: Style(foreground: .cyan))]) })
    }
    let name = "text/text-widget/\(kind)-120x40"
    samples.append(
      bufferSample(name, iterations: frameIterations) { buffer, iteration in
        texts[iteration % 2].render(in: textScreen, into: &buffer, environment: environment)
      })
  }

  let centeredOverflow = Text(longASCIILines.map { Line($0, alignment: .center) })
  let centeredName = "text/text-widget/ascii-centered-400-in-120x40"
  samples.append(
    bufferSample(centeredName, iterations: frameIterations) { buffer, _ in
      centeredOverflow.render(in: textScreen, into: &buffer, environment: environment)
    })

  let listRows = Array(0..<200)
  let asciiLabels = listRows.map { asciiText(row: $0, length: 160) }
  let mixedLabels = listRows.map { mixedText(row: $0, columns: 160) }
  for (kind, labels) in [("ascii", asciiLabels), ("mixed", mixedLabels)] {
    let name = "text/list/\(kind)-200-rows-160-cols-in-120x40"
    samples.append(
      bufferSample(name, iterations: frameIterations) { buffer, iteration in
        buffer.reset()
        List(listRows, selectedRow: 100 + iteration % 2, label: { labels[$0] })
          .render(in: textScreen, into: &buffer, environment: environment)
      })
  }

  let asciiDocument = (0..<60).map { asciiText(row: $0, length: 300) }.joined(separator: "\n")
  let mixedDocument = (0..<60).map { mixedText(row: $0, columns: 300) }.joined(separator: "\n")
  for (kind, document) in [("ascii", asciiDocument), ("mixed", mixedDocument)] {
    for wrap in [WrapMode.word, .character] {
      let paragraph = Paragraph(document, wrap: wrap)
      let name = "text/paragraph-\(wrap == .word ? "word" : "character")-wrap/\(kind)-120x40"
      samples.append(
        bufferSample(name, iterations: frameIterations) { buffer, _ in
          buffer.reset()
          paragraph.render(in: textScreen, into: &buffer, environment: environment)
        })
    }
  }

  let tableRows = (0..<200).map { Row(name: asciiText(row: $0, length: 90), value: $0 * 7) }
  let table = Table(tableRows, selectedRow: 100) {
    TableColumn("Name", value: \.name, width: .flex(2), alignment: .center)
    TableColumn("Value", value: \.value, alignment: .trailing)
  }
  let tableName = "text/table/ascii-centered-overflow-120x40"
  samples.append(
    bufferSample(tableName, iterations: frameIterations) { buffer, _ in
      buffer.reset()
      table.render(in: textScreen, into: &buffer, environment: environment)
    })

  // End to end: full-screen text through Terminal.draw (render + diff) with alternating content.
  for (kind, lines) in kinds {
    let texts = lines.map { variant in Text(variant.map { Line($0) }) }
    var terminal = try Terminal(
      backend: TestBackend(width: textScreen.width, height: textScreen.height))
    let name = "text/frame/\(kind)-full-screen-120x40"
    samples.append(
      try measure(name, iterations: frameIterations) { iteration in
        try terminal.draw { frame in frame.render(texts[iteration % 2]) }.updates
      })
  }

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

// Style-heavy output scenarios. Each frame alternates between two phases so every cell changes
// (text, and for the styled patterns also its style) and the diff covers the whole screen.
private enum OutputPattern: CaseIterable {
  /// Only the text changes; every cell keeps one bold green-on-black style.
  case constantStyle
  /// Truecolor foreground and background change on every cell.
  case trueColorEveryCell
  /// 256-color palette foreground and background change on every cell.
  case indexedEveryCell
  /// Runs of four cells share a style: named, palette and truecolor colors, some bold.
  case styleEvery4Cells
  /// Modifiers (bold, dim, italic, underline, reverse, hidden, strike) toggle on every cell.
  case attributeToggles
  /// A dashboard: bold header, dim border, zebra rows, a highlighted row, colored value columns.
  case dashboardMixed

  var name: String {
    switch self {
    case .constantStyle: "text-churn-constant-style"
    case .trueColorEveryCell: "truecolor-every-cell"
    case .indexedEveryCell: "indexed-every-cell"
    case .styleEvery4Cells: "style-every-4-cells"
    case .attributeToggles: "attribute-toggles"
    case .dashboardMixed: "dashboard-mixed"
    }
  }

  func cell(column: Int, row: Int, phase: Int) -> Cell {
    let letter = Character(Unicode.Scalar(UInt8(97 + (column + row + phase) % 26)))
    return Cell(symbol: String(letter), style: style(column: column, row: row, phase: phase))
  }

  func style(column: Int, row: Int, phase: Int) -> Style {
    switch self {
    case .constantStyle:
      return Style(foreground: .lightGreen, background: .black, modifiers: [.bold])
    case .trueColorEveryCell:
      return Style(
        foreground: .rgb(UInt8((column * 2 + phase) % 256), UInt8(row * 6 % 256), 128),
        background: .rgb(20, UInt8(phase * 40), UInt8((column + row) % 256)))
    case .indexedEveryCell:
      return Style(
        foreground: .indexed(UInt8((column + row * 7 + phase) % 256)),
        background: .indexed(UInt8((column * 3 + row) % 256)))
    case .styleEvery4Cells:
      switch (column / 4 + row + phase) % 3 {
      case 0: return Style(foreground: .red, background: .indexed(236))
      case 1: return Style(foreground: .green, background: .indexed(237), modifiers: [.bold])
      default: return Style(foreground: .rgb(200, 120, 40), background: .indexed(238))
      }
    case .attributeToggles:
      let bits = UInt16((column + row + phase) % 128)
      return Style(foreground: .cyan, modifiers: Modifier(rawValue: bits))
    case .dashboardMixed:
      return dashboardStyle(column: column, row: row, selectedRow: 3 + phase * 4)
    }
  }

  private func dashboardStyle(column: Int, row: Int, selectedRow: Int) -> Style {
    if row == 0 { return Style(foreground: .white, background: .blue, modifiers: [.bold]) }
    if column == 0 || column == 119 { return Style(foreground: .darkGray, modifiers: [.dim]) }
    var style = Style(foreground: .gray)
    if column >= 80 {
      style.foreground = .indexed(214)
    } else if column >= 40 {
      style.foreground = .rgb(120, 200, 120)
    }
    if row == selectedRow {
      style.background = .rgb(60, 60, 90)
      style = style.adding(.italic)
    } else if row.isMultiple(of: 2) {
      style.background = .indexed(236)
    }
    if column >= 80, column < 90 { style = style.adding(.bold) }
    return style
  }

  func updates(width: Int, height: Int, phase: Int) -> [CellUpdate] {
    var updates: [CellUpdate] = []
    updates.reserveCapacity(width * height)
    for row in 0..<height {
      for column in 0..<width {
        updates.append(
          CellUpdate(
            position: Position(x: column, y: row),
            cell: cell(column: column, row: row, phase: phase)))
      }
    }
    return updates
  }
}

private struct OutputPatternGrid: Widget {
  var pattern: OutputPattern
  var phase: Int

  func render(in area: Rect, into frame: inout Frame) {
    for row in 0..<area.height {
      for column in 0..<area.width {
        frame.buffer.setCell(
          pattern.cell(column: column, row: row, phase: phase),
          at: Position(x: area.x + column, y: area.y + row))
      }
    }
  }
}

/// Measures `ANSIBackend.draw` alone: the full-screen updates are built once per phase, so the
/// sample covers only escape-sequence building and the write to `/dev/null`. Output bytes are
/// counted separately by drawing both phases once into a temporary file.
private func ansiEmitBenchmark(
  name: String,
  iterations: Int,
  configuration: ANSIBackendConfiguration,
  pattern: OutputPattern
) throws -> BenchmarkSample {
  let size = Size(width: 120, height: 40)
  let phases = [0, 1].map { pattern.updates(width: size.width, height: size.height, phase: $0) }

  let url = FileManager.default.temporaryDirectory
    .appendingPathComponent("termloom-benchmark-\(UUID().uuidString).ansi")
  _ = FileManager.default.createFile(atPath: url.path, contents: nil)
  defer { try? FileManager.default.removeItem(at: url) }
  let counted = try FileHandle(forWritingTo: url)
  defer { try? counted.close() }
  var countingBackend = ANSIBackend(
    output: counted, fallbackSize: size, configuration: configuration)
  for updates in phases { try countingBackend.draw(updates) }
  try counted.synchronize()
  let byteCount = try counted.offset()

  guard let discard = FileHandle(forWritingAtPath: "/dev/null") else {
    throw CocoaError(.fileNoSuchFile)
  }
  defer { try? discard.close() }
  var backend = ANSIBackend(output: discard, fallbackSize: size, configuration: configuration)
  var sample = try measure(name, iterations: iterations) { iteration in
    let updates = phases[iteration % 2]
    try backend.draw(updates)
    return updates.count
  }
  sample.outputBytesPerIteration = Double(byteCount) / Double(phases.count)
  return sample
}

private func outputBenchmarks(iterations: Int) throws -> [BenchmarkSample] {
  let outputIterations = min(iterations, 1_000)
  let emitIterations = min(iterations, 500)
  var samples = try fixedOutputBenchmarks(iterations: outputIterations)
  samples += try cursorOutputBenchmarks(iterations: outputIterations)
  // Whole frames through `Terminal.draw` (render, diff, emit) with style-heavy content.
  for pattern in OutputPattern.allCases {
    samples.append(
      try ansiOutputBenchmark(
        name: "ansi/\(pattern.name)", iterations: outputIterations
      ) { iteration, frame in
        frame.render(OutputPatternGrid(pattern: pattern, phase: iteration % 2))
      })
  }
  // The ANSI emitter alone, for every pattern and for color-profile quantization.
  for pattern in OutputPattern.allCases {
    samples.append(
      try ansiEmitBenchmark(
        name: "ansi/emit/\(pattern.name)", iterations: emitIterations,
        configuration: .full, pattern: pattern))
  }
  samples.append(
    try ansiEmitBenchmark(
      name: "ansi/emit/truecolor-on-256-profile", iterations: emitIterations,
      configuration: ANSIBackendConfiguration(colorProfile: .indexed256),
      pattern: .trueColorEveryCell))
  samples.append(
    try ansiEmitBenchmark(
      name: "ansi/emit/truecolor-on-16-profile", iterations: emitIterations,
      configuration: ANSIBackendConfiguration(
        colorProfile: .ansi16, supportsUnderlineColor: false, supportsSynchronizedOutput: false),
      pattern: .trueColorEveryCell))
  return samples
}

private func fixedOutputBenchmarks(iterations outputIterations: Int) throws -> [BenchmarkSample] {
  [
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

/// A text-input line: `length` letters on one row of a blank screen.
private struct CaretLine: Widget {
  var row: Int
  var length: Int

  func render(in area: Rect, into frame: inout Frame) {
    guard area.height > row else { return }
    let text = String((0..<length).map { Character(Unicode.Scalar(UInt8(97 + $0 % 26))) })
    frame.buffer.setString(text, at: Position(x: area.x, y: area.y + row))
  }
}

// Frames whose cost is dominated by the cursor: nothing changes at all, only the caret moves, or
// one cell changes while the caret stays put. `outputBytesPerIteration` is the number of bytes
// written to the terminal per frame. Each sample's first frame paints the whole screen once.
private func cursorOutputBenchmarks(iterations: Int) throws -> [BenchmarkSample] {
  let caret = Position(x: 10, y: 20)
  return [
    // Idle frames: nothing changed, the cursor is hidden.
    try ansiOutputBenchmark(
      name: "ansi/cursor/idle-hidden", iterations: iterations
    ) { _, frame in
      frame.render(Fill(" "))
    },
    // Idle frames: nothing changed, a visible bar caret stays at one position.
    try ansiOutputBenchmark(
      name: "ansi/cursor/idle-visible", iterations: iterations
    ) { _, frame in
      frame.render(Fill(" "))
      frame.placeCursor(at: caret, style: .steadyBar)
    },
    // A text-input caret moves along a line every frame; no cell changes.
    try ansiOutputBenchmark(
      name: "ansi/cursor/caret-moving", iterations: iterations
    ) { iteration, frame in
      frame.render(Fill(" "))
      frame.placeCursor(at: Position(x: iteration % 80, y: 20), style: .steadyBar)
    },
    // The caret visits every cell of the screen (the ANSI version of `frame/cursor-only`).
    try ansiOutputBenchmark(
      name: "ansi/cursor/grid-moving", iterations: iterations
    ) { iteration, frame in
      frame.render(Fill(" "))
      frame.placeCursor(
        at: Position(x: iteration % 120, y: (iteration / 120) % 40), style: .steadyBar)
    },
    // One cell changes every frame while a visible caret stays put.
    try ansiOutputBenchmark(
      name: "ansi/cursor/one-cell-fixed-caret", iterations: iterations
    ) { iteration, frame in
      frame.render(SingleCell(symbol: iteration.isMultiple(of: 2) ? "A" : "B"))
      frame.placeCursor(at: caret, style: .steadyBar)
    },
    // Typing: each frame adds one letter and the caret follows it (the line restarts every 80).
    try ansiOutputBenchmark(
      name: "ansi/cursor/typing", iterations: iterations
    ) { iteration, frame in
      let length = iteration % 80
      frame.render(CaretLine(row: 20, length: length))
      frame.placeCursor(at: Position(x: length, y: 20), style: .steadyBar)
    },
  ]
}

// MARK: - Application run loop

// The `loop` suite drives the public `TerminalApplication.run(viewport:capturesMouse:)` path
// through a pseudo-terminal. Standard input and output are temporarily redirected to the PTY
// slave while a driver thread writes input to the master side and a drain thread counts the
// bytes and synchronized-output frames the application emits.

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
  private var frameCount = 0
  private var frameMarkerMatch = 0
  private var lastReadUptime = DispatchTime.now().uptimeNanoseconds
  private var isStopping = false

  init(descriptor: Int32) {
    self.descriptor = descriptor
  }

  var bytes: Int { lock.withLock { byteCount } }
  /// Frames written by the application: each begins a synchronized update (`CSI ? 2026 h`).
  var frames: Int { lock.withLock { frameCount } }

  private static let frameMarker = Array("\u{1B}[?2026h".utf8)

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

  /// Counts frame markers, including markers split across reads. Only the first marker byte is ESC,
  /// so a mismatch can restart matching at that byte alone.
  private func countFrameMarkers(in bytes: ArraySlice<UInt8>) {
    let marker = Self.frameMarker
    for byte in bytes {
      if byte == marker[frameMarkerMatch] {
        frameMarkerMatch += 1
        if frameMarkerMatch == marker.count {
          frameCount += 1
          frameMarkerMatch = 0
        }
      } else {
        frameMarkerMatch = byte == marker[0] ? 1 : 0
      }
    }
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
            countFrameMarkers(in: buffer[..<count])
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
  var steadyWrittenFrames = 0
  var burstSeconds = 0.0
  var burstFrames = 0
  var burstBytes = 0
  var burstWrittenFrames = 0
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
    let steadyWrittenFramesBefore = output.frames
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
    result.steadyWrittenFrames = output.frames - steadyWrittenFramesBefore

    // b) Burst: everything arrives in one write; wait until a frame reflects the final event.
    for _ in 0..<workload.bursts {
      let before = probe.snapshot
      let bytesBefore = output.bytes
      let writtenFramesBefore = output.frames
      let start = DispatchTime.now().uptimeNanoseconds
      try send(workload.burstPayload)
      let target = before.updates + workload.burstEvents
      try probe.waitForFrame("the burst to become idle") { $0.updatesAtLastFrame >= target }
      result.burstSeconds += Self.seconds(since: start)
      output.waitForQuiet()
      result.burstFrames += probe.snapshot.frames - before.frames
      result.burstBytes += output.bytes - bytesBefore
      result.burstWrittenFrames += output.frames - writtenFramesBefore
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
        framesPerIteration: Double(measured.steadyFrames) / Double(steadyCount),
        writtenFramesPerIteration: Double(measured.steadyWrittenFrames) / Double(steadyCount)),
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
        framesPerIteration: Double(measured.burstFrames) / Double(workload.bursts),
        writtenFramesPerIteration: Double(measured.burstWrittenFrames) / Double(workload.bursts)),
    ]
  #else
    return []
  #endif
}

// MARK: - Idle application loop

// The idle measurements run in a child process that makes a fresh pseudo-terminal its controlling
// terminal, exactly like an application started from a shell: resizing the terminal then sends
// SIGWINCH to the application. Wakeups are measured as process CPU time and voluntary context
// switches (each blocking wait that ends is one) while nothing is animating; frames are counted by
// the body (`frames`) and as synchronized updates on the terminal (`written frames`).

private let idleLoopChildArgument = "--idle-loop-child"
private let idleWindowSeconds = 2.0
private let resizeIterations = 20

private struct ResourceUsage {
  var cpuSeconds = 0.0
  var voluntaryContextSwitches = 0
  var involuntaryContextSwitches = 0

  static func now() -> ResourceUsage {
    #if canImport(Darwin)
      var usage = rusage()
      guard getrusage(RUSAGE_SELF, &usage) == 0 else { return ResourceUsage() }
      let user = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1e6
      let system = Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1e6
      return ResourceUsage(
        cpuSeconds: user + system,
        voluntaryContextSwitches: Int(usage.ru_nvcsw),
        involuntaryContextSwitches: Int(usage.ru_nivcsw))
    #else
      return ResourceUsage()
    #endif
  }
}

/// What happened during one measured wall-clock window.
private struct LoopWindow: Sendable {
  var seconds = 0.0
  var cpuSeconds = 0.0
  var voluntaryContextSwitches = 0
  var involuntaryContextSwitches = 0
  var frames = 0
  var writtenFrames = 0
  var bytes = 0
}

/// Drains the PTY master without ever waking on a timer, counting synchronized-update begin and
/// end markers. Each end marker is the moment a complete frame reached the terminal.
private final class FrameEndMonitor: @unchecked Sendable {
  private let descriptor: Int32
  private var stopDescriptors: [Int32] = [-1, -1]
  private let lock = NSLock()
  private let frameEnded = DispatchSemaphore(value: 0)
  private let finished = DispatchSemaphore(value: 0)
  private var byteCount = 0
  private var beginCount = 0
  private var endCount = 0
  private var lastEndUptime: UInt64 = 0
  private var lastReadUptime = DispatchTime.now().uptimeNanoseconds
  private var prefixMatch = 0

  // `CSI ? 2026 h` begins and `CSI ? 2026 l` ends a synchronized update.
  private static let markerPrefix = Array("\u{1B}[?2026".utf8)

  init(descriptor: Int32) {
    self.descriptor = descriptor
    _ = pipe(&stopDescriptors)
  }

  var bytes: Int { lock.withLock { byteCount } }
  var frameBegins: Int { lock.withLock { beginCount } }
  var frameEnds: Int { lock.withLock { endCount } }

  func start() {
    Thread { [self] in drain() }.start()
  }

  /// Waits for the frame end after `count` ends, returning when it arrived (uptime nanoseconds).
  func waitForFrameEnd(after count: Int, timeoutSeconds: Double = 5) -> UInt64? {
    let deadline = DispatchTime.now() + timeoutSeconds
    while true {
      let state = lock.withLock { (endCount, lastEndUptime) }
      if state.0 > count { return state.1 }
      if frameEnded.wait(timeout: deadline) == .timedOut {
        let late = lock.withLock { (endCount, lastEndUptime) }
        return late.0 > count ? late.1 : nil
      }
    }
  }

  /// Waits until no output has arrived for `milliseconds` (polls; never used inside a window).
  func waitForQuiet(milliseconds: UInt64 = 100, timeoutSeconds: Double = 5) {
    let quiet = milliseconds * 1_000_000
    let deadline = DispatchTime.now() + timeoutSeconds
    while DispatchTime.now() < deadline {
      let last = lock.withLock { lastReadUptime }
      let now = DispatchTime.now().uptimeNanoseconds
      if now >= last, now - last >= quiet { return }
      usleep(2_000)
    }
  }

  func stop() {
    var byte: UInt8 = 1
    _ = write(stopDescriptors[1], &byte, 1)
    _ = finished.wait(timeout: .now() + 2)
    close(stopDescriptors[0])
    close(stopDescriptors[1])
  }

  private func countMarkers(in bytes: ArraySlice<UInt8>, at uptime: UInt64) {
    let prefix = Self.markerPrefix
    for byte in bytes {
      if prefixMatch == prefix.count {
        prefixMatch = 0
        if byte == UInt8(ascii: "h") {
          beginCount += 1
          continue
        }
        if byte == UInt8(ascii: "l") {
          endCount += 1
          lastEndUptime = uptime
          frameEnded.signal()
          continue
        }
      }
      if byte == prefix[prefixMatch] {
        prefixMatch += 1
      } else {
        prefixMatch = byte == prefix[0] ? 1 : 0
      }
    }
  }

  private func drain() {
    var buffer = [UInt8](repeating: 0, count: 16_384)
    while true {
      var descriptors = [
        pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0),
        pollfd(fd: stopDescriptors[0], events: Int16(POLLIN), revents: 0),
      ]
      let ready = poll(&descriptors, 2, -1)
      if ready < 0 {
        if errno == EINTR { continue }
        break
      }
      if descriptors[1].revents != 0 { break }
      guard descriptors[0].revents != 0 else { continue }
      let count = read(descriptor, &buffer, buffer.count)
      if count > 0 {
        let now = DispatchTime.now().uptimeNanoseconds
        lock.withLock {
          byteCount += count
          lastReadUptime = now
          countMarkers(in: buffer[..<count], at: now)
        }
        continue
      }
      if count == 0 || (errno != EAGAIN && errno != EINTR) { break }
    }
    finished.signal()
  }
}

@MainActor private final class IdleBenchmarkApplication: TerminalApplication {
  let probe: LoopProbe

  init(probe: LoopProbe) {
    self.probe = probe
  }

  var body: LoopDashboard {
    LoopDashboard(selectedRow: 0, status: "idle", probe: probe)
  }

  func update(_ event: TerminalEvent) async -> ApplicationUpdate {
    probe.recordUpdate()
    if case .key(let key) = event, key.key == .character("q") { return .quit }
    return .ignore
  }
}

@MainActor @Observable private final class TickerModel {
  var tick = 0
}

/// Animates through Observation: a main-actor task advances the model at a fixed rate.
@MainActor private final class TickerBenchmarkApplication: TerminalApplication {
  let probe: LoopProbe
  let model = TickerModel()

  init(probe: LoopProbe) {
    self.probe = probe
  }

  var body: LoopDashboard {
    LoopDashboard(
      selectedRow: model.tick % rows.count, status: "tick \(model.tick)", probe: probe)
  }

  func update(_ event: TerminalEvent) async -> ApplicationUpdate {
    probe.recordUpdate()
    if case .key(let key) = event, key.key == .character("q") { return .quit }
    return .ignore
  }
}

/// Animates through `PeriodicallyRedrawingTerminalApplication` with a plain stored flag.
@MainActor
private final class PeriodicBenchmarkApplication: TerminalApplication,
  PeriodicallyRedrawingTerminalApplication
{
  let probe: LoopProbe
  var needsPeriodicRedraw: Bool
  var frame = 0

  init(probe: LoopProbe, needsPeriodicRedraw: Bool) {
    self.probe = probe
    self.needsPeriodicRedraw = needsPeriodicRedraw
  }

  var body: LoopDashboard {
    frame += 1
    return LoopDashboard(
      selectedRow: frame % rows.count, status: "frame \(frame)", probe: probe)
  }

  func update(_ event: TerminalEvent) async -> ApplicationUpdate {
    probe.recordUpdate()
    if case .key(let key) = event, key.key == .character("q") { return .quit }
    return .ignore
  }
}

/// Like Postcat's explicit mode: an observable model whose flag drives periodic redraws, with
/// automatic Observation redraws disabled.
@MainActor @Observable
private final class ObservablePeriodicBenchmarkApplication: TerminalApplication,
  PeriodicallyRedrawingTerminalApplication
{
  let probe: LoopProbe
  var loading = false
  @ObservationIgnored var frame = 0

  init(probe: LoopProbe) {
    self.probe = probe
  }

  var needsPeriodicRedraw: Bool { loading }
  var automaticallyTracksObservableState: Bool { false }

  var body: LoopDashboard {
    frame += 1
    return LoopDashboard(
      selectedRow: frame % rows.count, status: "frame \(frame)", probe: probe)
  }

  func update(_ event: TerminalEvent) async -> ApplicationUpdate {
    probe.recordUpdate()
    if case .key(let key) = event, key.key == .character("q") { return .quit }
    return .ignore
  }
}

#if canImport(Darwin)
  /// Runs `measure` on a driver thread while `application` runs on the main actor, then quits.
  private final class IdleScenarioDriver: @unchecked Sendable {
    let master: Int32
    let slave: Int32
    let probe = LoopProbe()
    let monitor: FrameEndMonitor
    let controllingTerminal: Bool
    private let finished = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var failure: String?

    init(master: Int32, slave: Int32, monitor: FrameEndMonitor, controllingTerminal: Bool) {
      self.master = master
      self.slave = slave
      self.monitor = monitor
      self.controllingTerminal = controllingTerminal
    }

    @MainActor
    func run<Application: TerminalApplication>(
      _ application: Application, measure: @escaping @Sendable (IdleScenarioDriver) throws -> Void
    ) async throws {
      Thread { [self] in
        do {
          try measure(self)
        } catch {
          lock.withLock { failure = String(describing: error) }
        }
        send(Array("q".utf8))
        finished.signal()
      }.start()
      try await application.run(viewport: .fullscreen, capturesMouse: false)
      let finished = self.finished
      let result = await Task.detached { blockingWait(finished, seconds: 30) }.value
      guard result == .success else {
        throw LoopBenchmarkError.driverDidNotFinish
      }
      if let failure = lock.withLock({ failure }) { throw LoopBenchmarkError.timedOut(failure) }
      monitor.waitForQuiet(milliseconds: 50)
    }

    /// Waits for the first frame and for output to settle.
    func waitUntilIdle() throws {
      try probe.waitForFrame("the initial frame") { $0.frames >= 1 }
      monitor.waitForQuiet()
    }

    /// Measures one window with a single blocking sleep on this thread.
    func window(seconds: Double = idleWindowSeconds) -> LoopWindow {
      let usageBefore = ResourceUsage.now()
      let framesBefore = probe.snapshot.frames
      let writtenBefore = monitor.frameBegins
      let bytesBefore = monitor.bytes
      let start = DispatchTime.now().uptimeNanoseconds
      Thread.sleep(forTimeInterval: seconds)
      let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9
      let usageAfter = ResourceUsage.now()
      return LoopWindow(
        seconds: elapsed,
        cpuSeconds: usageAfter.cpuSeconds - usageBefore.cpuSeconds,
        voluntaryContextSwitches: usageAfter.voluntaryContextSwitches
          - usageBefore.voluntaryContextSwitches,
        involuntaryContextSwitches: usageAfter.involuntaryContextSwitches
          - usageBefore.involuntaryContextSwitches,
        frames: probe.snapshot.frames - framesBefore,
        writtenFrames: monitor.frameBegins - writtenBefore,
        bytes: monitor.bytes - bytesBefore)
    }

    /// Resizes the terminal and returns the time until the redrawn frame was written.
    func resize(
      columns: UInt16, rows: UInt16
    ) throws -> (seconds: Double, frames: Int, written: Int) {
      let framesBefore = probe.snapshot.frames
      let endsBefore = monitor.frameEnds
      let writtenBefore = monitor.frameBegins
      var window = winsize(ws_row: rows, ws_col: columns, ws_xpixel: 0, ws_ypixel: 0)
      let start = DispatchTime.now().uptimeNanoseconds
      guard ioctl(slave, UInt(TIOCSWINSZ), &window) == 0 else {
        throw LoopBenchmarkError.timedOut("TIOCSWINSZ")
      }
      // With a controlling terminal the kernel sends SIGWINCH to the foreground process group.
      if !controllingTerminal { kill(getpid(), SIGWINCH) }
      guard let ended = monitor.waitForFrameEnd(after: endsBefore) else {
        throw LoopBenchmarkError.timedOut("the redrawn frame after a resize")
      }
      try probe.waitForFrame("the resize frame") { $0.frames > framesBefore }
      monitor.waitForQuiet(milliseconds: 30)
      return (
        Double(ended > start ? ended - start : 0) / 1e9, probe.snapshot.frames - framesBefore,
        monitor.frameBegins - writtenBefore
      )
    }

    func send(_ bytes: [UInt8]) {
      var offset = 0
      while offset < bytes.count {
        let count = bytes[offset...].withUnsafeBytes { buffer in
          write(master, buffer.baseAddress, buffer.count)
        }
        if count < 0 {
          if errno == EINTR || errno == EAGAIN { continue }
          return
        }
        offset += count
      }
    }
  }

  private final class IdleScenarioResults: @unchecked Sendable {
    private let lock = NSLock()
    private var windows: [String: LoopWindow] = [:]
    private var latencies: [Double] = []
    private var resizeFrames = 0
    private var resizeWritten = 0

    func record(_ name: String, _ window: LoopWindow) {
      lock.withLock { windows[name] = window }
    }

    func recordResize(seconds: Double, frames: Int, written: Int) {
      lock.withLock {
        latencies.append(seconds)
        resizeFrames += frames
        resizeWritten += written
      }
    }

    var snapshot: (windows: [String: LoopWindow], latencies: [Double], frames: Int, written: Int) {
      lock.withLock { (windows, latencies, resizeFrames, resizeWritten) }
    }
  }

  private func windowSample(_ name: String, _ window: LoopWindow) -> BenchmarkSample {
    let seconds = max(window.seconds, .leastNonzeroMagnitude)
    return BenchmarkSample(
      name: name,
      iterations: 1,
      seconds: window.seconds,
      // Process CPU nanoseconds per wall-clock second of the window.
      nanosecondsPerIteration: window.cpuSeconds * 1e9 / seconds,
      iterationsPerSecond: 1 / seconds,
      cellUpdatesPerIteration: nil,
      outputBytesPerIteration: Double(window.bytes),
      retainedBytesDelta: nil,
      peakResidentBytes: peakResidentBytes(),
      framesPerIteration: Double(window.frames),
      writtenFramesPerIteration: Double(window.writtenFrames),
      cpuMicrosecondsPerSecond: window.cpuSeconds * 1e6 / seconds,
      voluntaryContextSwitchesPerSecond: Double(window.voluntaryContextSwitches) / seconds,
      involuntaryContextSwitchesPerSecond: Double(window.involuntaryContextSwitches) / seconds,
      framesPerSecond: Double(window.frames) / seconds,
      writtenFramesPerSecond: Double(window.writtenFrames) / seconds)
  }

  /// Runs in the child process: owns a controlling pseudo-terminal and runs every idle scenario.
  @MainActor
  private func idleLoopChildBenchmarks() async throws -> [BenchmarkSample] {
    // Closing the master side hangs up the controlling terminal; the results are printed after.
    signal(SIGHUP, SIG_IGN)
    let becameSessionLeader = setsid() >= 0
    var master: Int32 = -1
    var slave: Int32 = -1
    var window = winsize(ws_row: 40, ws_col: 120, ws_xpixel: 0, ws_ypixel: 0)
    guard openpty(&master, &slave, nil, nil, &window) == 0 else {
      throw LoopBenchmarkError.pseudoTerminalUnavailable
    }
    var controllingTerminal = false
    if becameSessionLeader, ioctl(slave, UInt(TIOCSCTTY), 0) == 0 {
      controllingTerminal = tcgetpgrp(slave) == getpgrp()
    }
    if !controllingTerminal {
      FileHandle.standardError.write(
        Data(
          "warning: no controlling terminal; resizes are signalled with kill(SIGWINCH)\n".utf8))
    }
    setenv("TERM", "xterm-256color", 1)
    fflush(nil)
    let savedInput = dup(STDIN_FILENO)
    let savedOutput = dup(STDOUT_FILENO)
    func restoreStandardStreams() {
      fflush(nil)
      if savedInput >= 0 {
        dup2(savedInput, STDIN_FILENO)
        close(savedInput)
      }
      if savedOutput >= 0 {
        dup2(savedOutput, STDOUT_FILENO)
        close(savedOutput)
      }
    }
    guard savedInput >= 0, savedOutput >= 0,
      dup2(slave, STDIN_FILENO) >= 0, dup2(slave, STDOUT_FILENO) >= 0
    else {
      restoreStandardStreams()
      throw LoopBenchmarkError.redirectionFailed
    }

    let monitor = FrameEndMonitor(descriptor: master)
    monitor.start()
    let results = IdleScenarioResults()
    func makeDriver() -> IdleScenarioDriver {
      IdleScenarioDriver(
        master: master, slave: slave, monitor: monitor, controllingTerminal: controllingTerminal)
    }

    do {
      // 1. Nothing animating, then resizes of the same idle application.
      let idle = makeDriver()
      try await idle.run(IdleBenchmarkApplication(probe: idle.probe)) { driver in
        try driver.waitUntilIdle()
        results.record("idle", driver.window())
        for index in 0..<resizeIterations {
          let size: (UInt16, UInt16) = index.isMultiple(of: 2) ? (100, 30) : (120, 40)
          let resized = try driver.resize(columns: size.0, rows: size.1)
          results.recordResize(
            seconds: resized.seconds, frames: resized.frames, written: resized.written)
        }
      }

      // 2. Observation-driven animation at about 30 ticks per second.
      let ticker = makeDriver()
      let tickerApplication = TickerBenchmarkApplication(probe: ticker.probe)
      let model = tickerApplication.model
      let tickTask = Task { @MainActor in
        while !Task.isCancelled {
          try? await Task.sleep(for: .milliseconds(33))
          model.tick += 1
        }
      }
      try await ticker.run(tickerApplication) { driver in
        try driver.probe.waitForFrame("the initial frame") { $0.frames >= 1 }
        Thread.sleep(forTimeInterval: 0.2)
        results.record("ticker", driver.window())
      }
      tickTask.cancel()

      // 3. Periodic redraws through a plain stored flag (polled at the input interval).
      let periodic = makeDriver()
      try await periodic.run(
        PeriodicBenchmarkApplication(probe: periodic.probe, needsPeriodicRedraw: true)
      ) { driver in
        try driver.probe.waitForFrame("the initial frame") { $0.frames >= 1 }
        Thread.sleep(forTimeInterval: 0.2)
        results.record("periodic", driver.window())
      }

      // 4. A plain periodic flag that is off: the flag cannot be observed, so it is still polled.
      let periodicOff = makeDriver()
      try await periodicOff.run(
        PeriodicBenchmarkApplication(probe: periodicOff.probe, needsPeriodicRedraw: false)
      ) { driver in
        try driver.waitUntilIdle()
        results.record("periodic-off", driver.window())
      }

      // 5. An observable periodic flag: idle while off, animating while on.
      let observable = makeDriver()
      let observableApplication = ObservablePeriodicBenchmarkApplication(probe: observable.probe)
      try await observable.run(observableApplication) { driver in
        try driver.waitUntilIdle()
        results.record("observable-periodic-off", driver.window())
        Task { @MainActor in observableApplication.loading = true }
        Thread.sleep(forTimeInterval: 0.2)
        results.record("observable-periodic-on", driver.window())
        Task { @MainActor in observableApplication.loading = false }
        driver.monitor.waitForQuiet()
      }
    } catch {
      monitor.stop()
      restoreStandardStreams()
      close(master)
      close(slave)
      throw error
    }
    monitor.stop()
    restoreStandardStreams()

    let measured = results.snapshot
    var samples: [BenchmarkSample] = []
    let windowNames = [
      ("idle", "loop/idle-2s"),
      ("periodic-off", "loop/idle-2s-unobservable-periodic-flag-off"),
      ("observable-periodic-off", "loop/idle-2s-observable-periodic-flag-off"),
      ("ticker", "loop/animating-observation-30hz-2s"),
      ("periodic", "loop/animating-periodic-flag-2s"),
      ("observable-periodic-on", "loop/animating-observable-periodic-flag-2s"),
    ]
    for (key, name) in windowNames {
      if let window = measured.windows[key] { samples.append(windowSample(name, window)) }
    }
    let latencies = measured.latencies
    if !latencies.isEmpty {
      let total = latencies.reduce(0, +)
      let count = Double(latencies.count)
      samples.append(
        BenchmarkSample(
          name: controllingTerminal ? "loop/resize-latency" : "loop/resize-latency-kill-sigwinch",
          iterations: latencies.count,
          seconds: total,
          nanosecondsPerIteration: total * 1e9 / count,
          iterationsPerSecond: count / max(total, .leastNonzeroMagnitude),
          cellUpdatesPerIteration: nil,
          outputBytesPerIteration: nil,
          retainedBytesDelta: nil,
          peakResidentBytes: peakResidentBytes(),
          framesPerIteration: Double(measured.frames) / count,
          writtenFramesPerIteration: Double(measured.written) / count,
          maximumLatencyMilliseconds: (latencies.max() ?? 0) * 1e3))
    }
    close(master)
    close(slave)
    return samples
  }

  /// Runs the idle scenarios in a child process and collects its JSON samples.
  private func idleLoopBenchmarks() throws -> [BenchmarkSample] {
    var output: [Int32] = [-1, -1]
    guard pipe(&output) == 0 else { throw LoopBenchmarkError.redirectionFailed }
    var actions: posix_spawn_file_actions_t?
    posix_spawn_file_actions_init(&actions)
    defer { posix_spawn_file_actions_destroy(&actions) }
    posix_spawn_file_actions_adddup2(&actions, output[1], STDOUT_FILENO)
    posix_spawn_file_actions_addclose(&actions, output[0])
    posix_spawn_file_actions_addclose(&actions, output[1])

    let executable = Bundle.main.executablePath ?? CommandLine.arguments[0]
    let arguments = [executable, idleLoopChildArgument]
    let environment = ProcessInfo.processInfo.environment.map { "\($0.key)=\($0.value)" }
    let argv: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) } + [nil]
    let envp: [UnsafeMutablePointer<CChar>?] = environment.map { strdup($0) } + [nil]
    defer {
      for pointer in argv { free(pointer) }
      for pointer in envp { free(pointer) }
    }
    var child: pid_t = 0
    let spawned = posix_spawn(&child, executable, &actions, nil, argv, envp)
    close(output[1])
    guard spawned == 0 else {
      close(output[0])
      throw LoopBenchmarkError.timedOut("spawning the idle benchmark child (\(spawned))")
    }
    let data = FileHandle(fileDescriptor: output[0], closeOnDealloc: true)
      .readDataToEndOfFile()
    var status: Int32 = 0
    _ = waitpid(child, &status, 0)
    guard let samples = try? JSONDecoder().decode([BenchmarkSample].self, from: data) else {
      throw LoopBenchmarkError.timedOut("the idle benchmark child (status \(status))")
    }
    return samples
  }
#endif

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
    if let written = sample.writtenFramesPerIteration {
      metrics.append(String(format: "%.2f written frames/iteration", written))
    }
    if let cpu = sample.cpuMicrosecondsPerSecond {
      metrics.append(String(format: "%.0f CPU µs/s", cpu))
    }
    if let switches = sample.voluntaryContextSwitchesPerSecond {
      metrics.append(String(format: "%.1f voluntary context switches/s", switches))
    }
    if let switches = sample.involuntaryContextSwitchesPerSecond {
      metrics.append(String(format: "%.1f involuntary context switches/s", switches))
    }
    if let frames = sample.framesPerSecond {
      metrics.append(String(format: "%.1f frames/s", frames))
    }
    if let written = sample.writtenFramesPerSecond {
      metrics.append(String(format: "%.1f written frames/s", written))
    }
    if let latency = sample.maximumLatencyMilliseconds {
      metrics.append(String(format: "%.2f ms max latency", latency))
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

#if canImport(Darwin)
  if CommandLine.arguments.dropFirst().first == idleLoopChildArgument {
    do {
      try printSamples(try await idleLoopChildBenchmarks(), asJSON: true)
      exit(0)
    } catch {
      FileHandle.standardError.write(Data("idle benchmark child failed: \(error)\n".utf8))
      exit(1)
    }
  }
#endif

let options = BenchmarkOptions(arguments: Array(CommandLine.arguments.dropFirst()))
let validSuites = ["frames", "primitives", "collections", "output", "text", "loop", "idle", "all"]
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
if options.suite == "text" || options.suite == "all" {
  samples += try textBenchmarks(iterations: options.iterations)
}
if options.suite == "loop" || options.suite == "all" {
  samples += try await loopBenchmarks(iterations: options.iterations)
}
#if canImport(Darwin)
  if options.suite == "loop" || options.suite == "idle" || options.suite == "all" {
    samples += try idleLoopBenchmarks()
  }
#endif
try printSamples(samples, asJSON: options.emitsJSON)

/// Blocks the calling thread on `semaphore`; call it only from a detached task.
private func blockingWait(
  _ semaphore: DispatchSemaphore, seconds: Double
) -> DispatchTimeoutResult {
  semaphore.wait(timeout: .now() + seconds)
}
