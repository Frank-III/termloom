public struct Frame {
  public var buffer: Buffer
  public private(set) var interactions: InteractionMap
  public var environment: RenderEnvironment
  public private(set) var cursorPosition: Position?
  public private(set) var cursorStyle: CursorStyle

  public init(buffer: Buffer, environment: RenderEnvironment = RenderEnvironment()) {
    self.buffer = buffer
    interactions = InteractionMap()
    self.environment = environment
    cursorPosition = nil
    cursorStyle = .defaultUserShape
  }

  public var area: Rect {
    buffer.area
  }

  public mutating func render<W: Widget>(
    _ widget: W,
    in area: Rect? = nil,
    collectsInteractions: Bool = true
  ) {
    let interactionCount = interactions.regions.count
    widget.render(in: area ?? self.area, into: &self)
    if !collectsInteractions {
      interactions.regions.removeSubrange(interactionCount...)
    }
  }

  public mutating func render<W: Widget>(
    _ widget: W,
    in area: Rect? = nil,
    environment: RenderEnvironment,
    collectsInteractions: Bool = true
  ) {
    let previousEnvironment = self.environment
    self.environment = environment
    defer { self.environment = previousEnvironment }
    render(widget, in: area, collectsInteractions: collectsInteractions)
  }

  public mutating func render<W: StatefulWidget>(
    _ widget: W,
    in area: Rect? = nil,
    state: inout W.State,
    collectsInteractions: Bool = true
  ) {
    let interactionCount = interactions.regions.count
    widget.render(in: area ?? self.area, into: &self, state: &state)
    if !collectsInteractions {
      interactions.regions.removeSubrange(interactionCount...)
    }
  }

  public mutating func render<W: StatefulWidget>(
    _ widget: W,
    in area: Rect? = nil,
    environment: RenderEnvironment,
    state: inout W.State,
    collectsInteractions: Bool = true
  ) {
    let previousEnvironment = self.environment
    self.environment = environment
    defer { self.environment = previousEnvironment }
    render(widget, in: area, state: &state, collectsInteractions: collectsInteractions)
  }

  public mutating func addInteraction(_ region: InteractionRegion) {
    interactions.regions.append(region)
  }

  public mutating func addInteractions(_ map: InteractionMap) {
    interactions.regions.append(contentsOf: map.regions)
  }

  public mutating func placeCursor(at position: Position?) {
    cursorPosition = position.flatMap { area.contains($0) ? $0 : nil }
    if cursorPosition == nil { cursorStyle = .defaultUserShape }
  }

  public mutating func placeCursor(at position: Position?, style: CursorStyle) {
    placeCursor(at: position)
    if cursorPosition != nil { cursorStyle = style }
  }
}

public struct CompletedFrame: Hashable, Sendable {
  public var buffer: Buffer
  public var count: UInt64
  public var updates: Int
  public var interactions: InteractionMap

  public init(
    buffer: Buffer,
    count: UInt64,
    updates: Int,
    interactions: InteractionMap = InteractionMap()
  ) {
    self.buffer = buffer
    self.count = count
    self.updates = updates
    self.interactions = interactions
  }
}

public enum TerminalViewportError: Error, Equatable {
  case requiresFixedViewport
}

public struct Terminal<BackendType: Backend> {
  public private(set) var backend: BackendType
  public private(set) var viewport: Viewport
  private var current: Buffer
  private var previous: Buffer
  private var frameCount: UInt64 = 0
  // Cursor state of a frame rendered into `current` by `renderWithoutPresenting` but not written.
  private var pendingPresentation: PendingPresentation?

  private struct PendingPresentation {
    var cursorStyle: CursorStyle
    var cursorPosition: Position?
  }

  public init(backend: BackendType) throws {
    try self.init(backend: backend, viewport: .fullscreen)
  }

  public init(backend: BackendType, viewport: Viewport) throws {
    var backend = backend
    let area =
      switch viewport {
      case .fixed(let area): area
      case .inline, .fullscreen: Rect(size: try backend.size())
      }
    self.backend = backend
    self.viewport = viewport
    current = Buffer(area: area)
    previous = Buffer(area: area)
  }

  @discardableResult
  public mutating func draw(
    environment: RenderEnvironment = RenderEnvironment(),
    _ render: (inout Frame) throws -> Void
  ) throws -> CompletedFrame {
    try autoresize()
    let frame = try renderBackBuffer(environment: environment, render)
    let updates = try present(cursorStyle: frame.cursorStyle, cursorPosition: frame.cursorPosition)
    return CompletedFrame(
      buffer: previous,
      count: frameCount,
      updates: updates,
      interactions: frame.interactions
    )
  }

  /// Whether `renderWithoutPresenting` renders exactly what `draw` would: `draw` would not have to
  /// replace the diff buffers for a new terminal size first.
  mutating func canRenderWithoutPresenting() throws -> Bool {
    if case .fixed = viewport { return true }
    return try backend.size() == current.area.size
  }

  /// Renders a frame into the back buffer exactly as `draw` would, but defers writing it.
  ///
  /// The deferred frame is written by `presentPendingFrame()`, or discarded when a later `draw`
  /// supersedes it before anything else is written to the terminal. Either way the terminal ends up
  /// showing the same cells as if every frame had been written.
  mutating func renderWithoutPresenting(
    environment: RenderEnvironment, _ render: (inout Frame) throws -> Void
  ) throws -> InteractionMap {
    let frame = try renderBackBuffer(environment: environment, render)
    pendingPresentation = PendingPresentation(
      cursorStyle: frame.cursorStyle, cursorPosition: frame.cursorPosition)
    return frame.interactions
  }

  var hasPendingFrame: Bool { pendingPresentation != nil }

  /// Writes the frame deferred by `renderWithoutPresenting`, if any.
  mutating func presentPendingFrame() throws {
    guard let pending = pendingPresentation else { return }
    pendingPresentation = nil
    _ = try present(cursorStyle: pending.cursorStyle, cursorPosition: pending.cursorPosition)
  }

  private mutating func renderBackBuffer(
    environment: RenderEnvironment, _ render: (inout Frame) throws -> Void
  ) throws -> Frame {
    pendingPresentation = nil
    current.reset()
    // Move the back buffer into the frame instead of sharing it, so the first widget write does not
    // copy every cell before the buffer is moved back.
    let area = current.area
    var frame = Frame(buffer: Buffer(area: .zero), environment: environment)
    swap(&frame.buffer, &current)
    do {
      try render(&frame)
    } catch {
      swap(&current, &frame.buffer)
      if current.area != area { current = Buffer(area: area) }
      throw error
    }
    swap(&current, &frame.buffer)
    return frame
  }

  private mutating func present(cursorStyle: CursorStyle, cursorPosition: Position?) throws -> Int {
    let updates = current.diff(from: previous)
    try backend.draw(updates)
    try backend.setCursorStyle(cursorStyle)
    try backend.setCursor(cursorPosition)
    try backend.flush()
    frameCount &+= 1
    swap(&current, &previous)
    return updates.count
  }

  /// Diff state captured before an application frame transaction.
  ///
  /// Unlike a plain copy of the terminal, the rollback does not retain the back buffer, so the next
  /// `draw` can reset and render into it without a copy-on-write of every cell. The back buffer's
  /// contents are always reset before rendering; only its area is part of the terminal state.
  struct FrameRollback {
    let terminal: Terminal
    let currentArea: Rect
  }

  func frameRollback() -> FrameRollback {
    var terminal = self
    terminal.current = Buffer(area: .zero)
    return FrameRollback(terminal: terminal, currentArea: current.area)
  }

  /// Restores the viewport, backend, front buffer, and frame count captured by `frameRollback()`.
  ///
  /// A deferred frame is discarded: the restored front buffer describes what is actually on screen.
  mutating func rollBack(to rollback: FrameRollback) {
    var restored = rollback.terminal
    if current.area == rollback.currentArea {
      swap(&restored.current, &current)
    } else {
      restored.current = Buffer(area: rollback.currentArea)
    }
    restored.pendingPresentation = nil
    self = restored
  }

  public mutating func clear() throws {
    if case .fixed(let area) = viewport {
      try clearFixedArea(area)
    } else {
      try backend.clear()
    }
    pendingPresentation = nil
    current.reset()
    previous.reset()
  }

  /// Changes a fixed viewport without coupling it to the backend's physical window size.
  ///
  /// Fixed viewports never autoresize. The old region is cleared before both diff buffers adopt the
  /// new terminal-coordinate rectangle, so the next draw fully paints the replacement region.
  public mutating func resize(to area: Rect) throws {
    guard case .fixed(let previousArea) = viewport else {
      throw TerminalViewportError.requiresFixedViewport
    }
    try clearFixedArea(previousArea)
    viewport = .fixed(area)
    pendingPresentation = nil
    current = Buffer(area: area)
    previous = Buffer(area: area)
  }

  /// Inserts rendered rows immediately above an inline viewport while keeping
  /// the retained viewport content intact.
  public mutating func insertBefore(
    height: Int,
    batchPosition: HistoryInsertionBatchPosition = .single,
    _ render: (inout Buffer) throws -> Void
  ) throws where BackendType: InlineHistoryBackend {
    guard height > 0, backend.capabilities.contains(.inlineViewport) else { return }

    let screen = try backend.windowSize().cells
    var origin = backend.viewportOrigin
    let viewportHeight = current.area.height
    guard screen.width > 0, screen.height > 0, viewportHeight > 0 else { return }

    var inserted = Buffer(
      area: Rect(x: 0, y: 0, width: current.area.width, height: height)
    )
    try render(&inserted)
    if try backend.insertHistory(
      inserted,
      batchPosition: batchPosition,
      restoring: previous
    ) {
      return
    }
    var consumed = 0

    let viewportBottom = min(screen.height, origin.y + viewportHeight)
    let spaceBelow = max(0, screen.height - viewportBottom)
    let pushDown = min(height, spaceBelow)
    if pushDown > 0 {
      try backend.scrollRegionDown(
        origin.y..<(viewportBottom + pushDown),
        by: pushDown
      )
      try drawRows(
        from: inserted,
        startingAt: consumed,
        count: pushDown,
        screenY: origin.y
      )
      consumed += pushDown
      origin.y = (origin.y + pushDown)
      try backend.setViewportOrigin(origin)
    }

    while consumed < height, origin.y > 0 {
      let count = min(height - consumed, origin.y)
      try backend.scrollRegionUpIntoScrollback(
        0..<origin.y, by: count)
      try drawRows(
        from: inserted,
        startingAt: consumed,
        count: count,
        screenY: origin.y - count
      )
      consumed += count
    }

    while consumed < Int(height) {
      try drawRows(from: inserted, startingAt: consumed, count: 1, screenY: 0)
      try backend.scrollRegionUpIntoScrollback(0..<1, by: 1)
      consumed += 1
    }
    if origin.y == 0 {
      try drawRows(from: previous, startingAt: 0, count: Int(viewportHeight), screenY: 0)
    }
  }

  public mutating func withBackend<Result>(
    _ operation: (inout BackendType) throws -> Result
  ) rethrows -> Result {
    try operation(&backend)
  }

  private mutating func autoresize() throws {
    if case .fixed = viewport { return }
    let size = try backend.size()
    guard size != current.area.size else { return }
    // Ratatui Rust clears the affected viewport before replacing both diff buffers. Without this,
    // shrinking leaves cells from the old wider frame visible because they no longer participate in
    // the next diff.
    try backend.clear()
    let area = Rect(size: size)
    pendingPresentation = nil
    current = Buffer(area: area)
    previous = Buffer(area: area)
  }

  private mutating func clearFixedArea(_ area: Rect) throws {
    guard !area.isEmpty else { return }
    var updates: [CellUpdate] = []
    updates.reserveCapacity(area.area)
    for position in area.positions() {
      updates.append(CellUpdate(position: position, cell: .empty))
    }
    try backend.draw(updates)
  }

  private mutating func drawRows(
    from buffer: Buffer,
    startingAt startRow: Int,
    count: Int,
    screenY: Int
  ) throws {
    guard count > 0 else { return }
    let savedOrigin = backend.viewportOrigin
    try backend.setViewportOrigin(
      Position(x: savedOrigin.x, y: screenY)
    )
    defer { try? backend.setViewportOrigin(savedOrigin) }
    var updates: [CellUpdate] = []
    updates.reserveCapacity(buffer.area.width * count)
    for row in 0..<count {
      for column in 0..<buffer.area.width {
        let source = Position(
          x: column,
          y: (startRow + row)
        )
        guard let cell = buffer.cell(at: source) else { continue }
        updates.append(
          CellUpdate(
            position: Position(x: column, y: row),
            cell: cell
          )
        )
      }
    }
    try backend.draw(updates)
  }
}
