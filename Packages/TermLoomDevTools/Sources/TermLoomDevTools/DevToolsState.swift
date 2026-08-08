import TermLoom

public enum DevToolsLogLevel: String, Hashable, Sendable {
  case trace
  case info
  case warning
  case error
}

public struct DevToolsLogEntry: Hashable, Sendable {
  public var sequence: UInt64
  public var level: DevToolsLogLevel
  public var message: String

  public init(sequence: UInt64, level: DevToolsLogLevel, message: String) {
    self.sequence = sequence
    self.level = level
    self.message = message
  }
}

public struct FrameStatistics: Hashable, Sendable {
  public private(set) var count: UInt64 = 0
  public private(set) var lastMilliseconds: Double = 0
  public private(set) var averageMilliseconds: Double = 0
  public private(set) var maximumMilliseconds: Double = 0
  public private(set) var lastChangedCells: Int?
  public private(set) var lastOutputBytes: Int?

  public init() {}

  public var estimatedFramesPerSecond: Double {
    averageMilliseconds > 0 ? 1_000 / averageMilliseconds : 0
  }

  public mutating func record(
    milliseconds: Double,
    changedCells: Int? = nil,
    outputBytes: Int? = nil
  ) {
    let milliseconds = max(0, milliseconds)
    count &+= 1
    lastMilliseconds = milliseconds
    averageMilliseconds += (milliseconds - averageMilliseconds) / Double(count)
    maximumMilliseconds = max(maximumMilliseconds, milliseconds)
    lastChangedCells = changedCells
    lastOutputBytes = outputBytes
  }
}

public struct DevToolsState: Hashable, Sendable {
  public var isPresented: Bool
  public var terminalSize: Size?
  public var frames: FrameStatistics
  public var logCapacity: Int {
    didSet {
      logCapacity = max(0, logCapacity)
      trimLogs()
    }
  }
  public private(set) var logs: [DevToolsLogEntry]
  private var nextSequence: UInt64

  public init(isPresented: Bool = false, logCapacity: Int = 200) {
    self.isPresented = isPresented
    terminalSize = nil
    frames = FrameStatistics()
    self.logCapacity = max(0, logCapacity)
    logs = []
    nextSequence = 1
  }

  public mutating func toggle() {
    isPresented.toggle()
  }

  public mutating func record(
    frameMilliseconds: Double,
    changedCells: Int? = nil,
    outputBytes: Int? = nil
  ) {
    frames.record(
      milliseconds: frameMilliseconds,
      changedCells: changedCells,
      outputBytes: outputBytes)
  }

  @discardableResult
  public mutating func measureFrame<Result>(
    changedCells: Int? = nil,
    outputBytes: Int? = nil,
    _ operation: () throws -> Result
  ) rethrows -> Result {
    let clock = ContinuousClock()
    let started = clock.now
    do {
      let result = try operation()
      record(
        frameMilliseconds: Self.milliseconds(started.duration(to: clock.now)),
        changedCells: changedCells,
        outputBytes: outputBytes)
      return result
    } catch {
      record(
        frameMilliseconds: Self.milliseconds(started.duration(to: clock.now)),
        changedCells: changedCells,
        outputBytes: outputBytes)
      throw error
    }
  }

  public mutating func log(_ message: String, level: DevToolsLogLevel = .info) {
    guard logCapacity > 0 else { return }
    logs.append(DevToolsLogEntry(sequence: nextSequence, level: level, message: message))
    nextSequence &+= 1
    trimLogs()
  }

  public mutating func record(event: TerminalEvent) {
    log(String(describing: event), level: .trace)
  }

  public mutating func clearLogs() {
    logs.removeAll(keepingCapacity: true)
  }

  private mutating func trimLogs() {
    if logs.count > logCapacity {
      logs.removeFirst(logs.count - logCapacity)
    }
  }

  private static func milliseconds(_ duration: Duration) -> Double {
    let components = duration.components
    return Double(components.seconds) * 1_000
      + Double(components.attoseconds) / 1_000_000_000_000_000
  }
}
