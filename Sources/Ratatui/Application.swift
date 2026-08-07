import Foundation
import Observation

public enum ApplicationUpdate: Hashable, Sendable {
  case redraw
  case ignore
  /// Clear only the application's retained viewport and redraw it.
  case clearViewport
  /// Explicitly purge native terminal scrollback and rebuild source-backed inline history.
  case resetTerminalHistory
  case suspend
  case quit
}

/// Source-backed rows an inline application has committed to terminal scrollback.
///
/// Applications retain their own semantic history and regenerate these rows when terminal width
/// changes. The runtime inserts them immediately above the live viewport using Ratatui's inline
/// scrolling algorithm instead of letting an oversized frame silently clip its oldest rows.
public struct TerminalHistoryInsertion: Hashable, Sendable {
  public var text: Text
  public var wrap: WrapMode
  public var resetsScrollback: Bool

  public init(
    text: Text = Text([]), wrap: WrapMode = .word, resetsScrollback: Bool = false
  ) {
    self.text = text
    self.wrap = wrap
    self.resetsScrollback = resetsScrollback
  }

  public static let reset = Self(resetsScrollback: true)
}

private final class InvalidationFlag: @unchecked Sendable {
  private let lock = NSLock()
  private let wakeup = TerminalWakeup()
  private var invalidated = false

  var wakeupSource: TerminalWakeup { wakeup }

  func invalidate() {
    lock.withLock {
      guard !invalidated else { return }
      invalidated = true
      wakeup.signal()
    }
  }

  func take() -> Bool {
    lock.withLock {
      wakeup.drain()
      defer { invalidated = false }
      return invalidated
    }
  }
}

/// Tracks Observation reads performed by an arbitrary rendering or presentation closure.
///
/// The callback fires once after any tracked value changes. Call `track(refresh:_:)` again while
/// producing the next presentation to arm tracking for its current dependencies. This is the same
/// primitive used by `TerminalApplication.run()` and is also suitable for offscreen renderers whose
/// completed buffers are sent to another process.
public final class ObservationInvalidationTracker: @unchecked Sendable {
  private let lock = NSLock()
  private let onChange: @Sendable () -> Void
  private var isArmed = false
  private var generation = 0

  public init(onChange: @escaping @Sendable () -> Void) {
    self.onChange = onChange
  }

  public func track<Value>(refresh: Bool = true, _ apply: () -> Value) -> Value {
    let token = lock.withLock { () -> Int? in
      guard refresh || !isArmed else { return nil }
      generation += 1
      isArmed = true
      return generation
    }
    guard let token else { return apply() }
    return withObservationTracking(apply) { [weak self] in
      self?.observedChange(generation: token)
    }
  }

  private func observedChange(generation changedGeneration: Int) {
    lock.withLock {
      if generation == changedGeneration { isArmed = false }
    }
    onChange()
  }
}

struct PreparedHistoryInsertion {
  var insertion: TerminalHistoryInsertion
  var height: UInt16
  var batchPosition: HistoryInsertionBatchPosition
}

func prepareHistoryInsertions(
  _ insertions: [TerminalHistoryInsertion], width: UInt16,
  targetChunkHeight: Int = 512
) -> [PreparedHistoryInsertion] {
  guard width > 0 else { return [] }
  var chunks: [(insertion: TerminalHistoryInsertion, height: UInt16)] = []
  var pendingLines: [Line] = []
  var pendingWrap: WrapMode?
  var pendingHeight = 0

  func measuredHeight(_ lines: [Line], wrap: WrapMode) -> Int {
    Paragraph(Text(lines), wrap: wrap, trimLeadingWhitespace: false).lineCount(width: width)
  }

  func flushPending() {
    guard let wrap = pendingWrap, !pendingLines.isEmpty else { return }
    chunks.append(
      (
        TerminalHistoryInsertion(text: Text(pendingLines), wrap: wrap),
        UInt16(clamping: pendingHeight)
      ))
    pendingLines.removeAll(keepingCapacity: true)
    pendingWrap = nil
    pendingHeight = 0
  }

  func appendLines(_ lines: [Line], wrap: WrapMode, height: Int) {
    if let activeWrap = pendingWrap,
      activeWrap != wrap || pendingHeight + height > targetChunkHeight
    {
      flushPending()
    }
    if height <= targetChunkHeight {
      pendingWrap = wrap
      pendingLines.append(contentsOf: lines)
      pendingHeight += height
      return
    }

    flushPending()
    for line in lines {
      let lineHeight = measuredHeight([line], wrap: wrap)
      if pendingWrap != nil, pendingHeight + lineHeight > targetChunkHeight {
        flushPending()
      }
      pendingWrap = wrap
      pendingLines.append(line)
      pendingHeight += lineHeight
    }
  }

  for insertion in insertions {
    if insertion.resetsScrollback {
      flushPending()
      chunks.append((insertion, 0))
      continue
    }
    guard !insertion.text.lines.isEmpty else { continue }
    let height = measuredHeight(insertion.text.lines, wrap: insertion.wrap)
    appendLines(insertion.text.lines, wrap: insertion.wrap, height: height)
  }
  flushPending()

  var prepared = chunks.map {
    PreparedHistoryInsertion(insertion: $0.insertion, height: $0.height, batchPosition: .single)
  }
  var index = 0
  while index < prepared.count {
    if prepared[index].insertion.resetsScrollback {
      index += 1
      continue
    }
    var end = index + 1
    while end < prepared.count, !prepared[end].insertion.resetsScrollback { end += 1 }
    if end - index > 1 {
      for position in index..<end {
        prepared[position].batchPosition =
          position == index ? .first : position == end - 1 ? .last : .middle
      }
    }
    index = end
  }
  return prepared
}

// A reset invalidates every queued row before it. When multiple resets are coalesced into one
// application turn, only the suffix after the last marker can still be canonical.
func normalizePendingHistoryResets(
  _ insertions: [TerminalHistoryInsertion]
) -> (requiresReset: Bool, insertions: [TerminalHistoryInsertion]) {
  guard let lastReset = insertions.lastIndex(where: \.resetsScrollback) else {
    return (false, insertions)
  }
  return (true, Array(insertions[insertions.index(after: lastReset)...]))
}

/// Opt-in refresh policy for applications whose model can change without terminal input.
///
/// The application loop polls at the terminal input interval and redraws while this value is true. Use it
/// for streaming, timers, progress, and external event sources; idle applications remain event-driven.
@MainActor
public protocol PeriodicallyRedrawingTerminalApplication: AnyObject {
  var needsPeriodicRedraw: Bool { get }
}

/// Optional capability for inline applications whose retained region follows content height.
@MainActor
public protocol InlineViewportSizing: AnyObject {
  func desiredInlineViewportHeight(size: Size) -> UInt16
}

@MainActor
public protocol TerminalApplication: AnyObject {
  associatedtype Body: Widget
  associatedtype InlineDocumentID: Hashable & Sendable = Never

  var body: Body { get }
  /// Automatically redraw when Swift Observation values read by `body` or widget rendering change.
  /// Applications with a complete explicit redraw scheduler can return `false` to avoid duplicate frames.
  var automaticallyTracksObservableState: Bool { get }
  func update(_ event: TerminalEvent) async -> ApplicationUpdate
  /// Returns the canonical source-backed document rendered above the retained viewport.
  /// Return `nil` while an overlay temporarily defers native-history updates.
  func inlineDocument(size: Size) -> InlineDocument<InlineDocumentID>?
  func takePendingHistoryInsertions(size: Size) -> [TerminalHistoryInsertion]
  func terminalHistoryDidReset()
  func performSuspendedAction() async
}

private final class AsyncInputPump: @unchecked Sendable {
  private let lock = NSLock()
  private var input: TerminalInput

  init(_ input: TerminalInput) {
    self.input = input
  }

  func next(wakeup: TerminalWakeup? = nil) async throws -> TerminalEvent? {
    try await Task.detached { [self] in
      try lock.withLock {
        try input.readEvent(wakeup: wakeup)
      }
    }.value
  }

  @MainActor
  func synchronize(with session: TerminalSession) {
    lock.withLock {
      session.synchronizeInput(&input)
    }
  }
}

extension TerminalApplication {
  public var automaticallyTracksObservableState: Bool { true }
  public func inlineDocument(size: Size) -> InlineDocument<InlineDocumentID>? { nil }
  public func takePendingHistoryInsertions(size: Size) -> [TerminalHistoryInsertion] { [] }
  public func terminalHistoryDidReset() {}
  public func performSuspendedAction() async {}

  /// Runs the application in a scoped raw-mode terminal session.
  ///
  /// The body is rendered initially and then only after an event requests a redraw. Terminal
  /// resizes always redraw, even when the application ignores the event.
  @MainActor
  public func run(
    viewport: Viewport = .inline(height: 10), capturesMouse: Bool = false
  ) async throws {
    try await withTerminalSession(viewport: viewport, capturesMouse: capturesMouse) { session in
      try await run(in: session)
    }
  }

  /// Runs with a caller-owned terminal session.
  ///
  /// This is an internal integration seam: the caller remains responsible for restoring the session.
  @MainActor
  func run(in session: TerminalSession) async throws {
    var terminal = try Terminal(
      backend: session.makeBackend(), viewport: session.configuredViewport)
    let input = AsyncInputPump(session.makeInput())
    var needsRedraw = true
    var isRunning = true
    var interactionRouter = InteractionRouter()
    var interactions = InteractionMap()
    var inlineDocumentRuntime = InlineDocumentRuntime<InlineDocumentID>()
    let invalidation = InvalidationFlag()
    let tracksObservableState = automaticallyTracksObservableState
    let presentationObservation = ObservationInvalidationTracker {
      invalidation.invalidate()
    }
    let renderObservation = ObservationInvalidationTracker {
      invalidation.invalidate()
    }
    var refreshObservationTracking = true
    var periodicRedrawWasActive = false

    while isRunning, !Task.isCancelled {
      if needsRedraw {
        let refreshTracking = refreshObservationTracking
        refreshObservationTracking = false
        let terminalSize = try terminal.withBackend { (try $0.windowSize()).cells }
        let terminalWidth = terminalSize.width
        let pendingDrain = normalizePendingHistoryResets(
          takePendingHistoryInsertions(size: terminalSize))
        let pendingHistory = pendingDrain.insertions
        if pendingDrain.requiresReset {
          try session.clearScrollbackAndResetViewport()
          inlineDocumentRuntime.reset()
          terminalHistoryDidReset()
          terminal = try Terminal(
            backend: session.makeBackend(), viewport: session.configuredViewport)
          input.synchronize(with: session)
        }
        // Pending-history drains happen before presentation tracking so queue mutation cannot schedule a
        // redundant frame. Any prior invalidation is incorporated by the complete presentation below.
        _ = invalidation.take()
        let makePresentation = {
          (
            (self as? any InlineViewportSizing)?.desiredInlineViewportHeight(size: terminalSize),
            self.inlineDocument(size: terminalSize), self.body
          )
        }
        let presentation =
          tracksObservableState
          ? presentationObservation.track(refresh: refreshTracking, makePresentation)
          : makePresentation()
        var historyInsertions: [TerminalHistoryInsertion] = []
        if session.supportsInlineHistory, let document = presentation.1 {
          historyInsertions += inlineDocumentRuntime.reconcile(
            document, width: terminalWidth)
        }
        historyInsertions += pendingHistory
        let preparedHistory = prepareHistoryInsertions(historyInsertions, width: terminalWidth)
        let renderedBody = presentation.2

        let updateViewportHistoryAndDraw = { () throws -> CompletedFrame in
          if let height = presentation.0, try session.updateInlineViewportHeight(height) {
            terminal = try Terminal(
              backend: session.makeBackend(), viewport: session.configuredViewport)
            input.synchronize(with: session)
          }
          for prepared in preparedHistory {
            let insertion = prepared.insertion
            if insertion.resetsScrollback {
              try session.clearScrollbackAndResetViewport()
              terminal = try Terminal(
                backend: session.makeBackend(), viewport: session.configuredViewport)
              input.synchronize(with: session)
            }
            guard prepared.height > 0 else { continue }
            let paragraph = Paragraph(
              insertion.text, wrap: insertion.wrap, trimLeadingWhitespace: false)
            try terminal.insertBefore(
              height: prepared.height, batchPosition: prepared.batchPosition
            ) { buffer in
              paragraph.render(
                in: buffer.area, into: &buffer, environment: RenderEnvironment())
            }
            session.synchronizeViewportOrigin(terminal.backend.viewportOrigin)
            input.synchronize(with: session)
          }

          let renderFrame = { () -> Result<CompletedFrame, any Error> in
            Result {
              try terminal.draw(
                environment: RenderEnvironment(
                  focusedControl: interactionRouter.focus.focusedControl
                )
              ) { frame in
                frame.render(renderedBody)
              }
            }
          }
          let completedResult =
            tracksObservableState
            ? renderObservation.track(refresh: refreshTracking, renderFrame)
            : renderFrame()
          return try completedResult.get()
        }
        let completed = try session.withFrameOutputTransaction(updateViewportHistoryAndDraw)
        interactions = completed.interactions
        needsRedraw = false
        periodicRedrawWasActive =
          (self as? any PeriodicallyRedrawingTerminalApplication)?.needsPeriodicRedraw ?? false
        if let routed = interactionRouter.reconcile(with: interactions) {
          for event in routed.events {
            let applicationUpdate = await update(event)
            switch applicationUpdate {
            case .redraw:
              needsRedraw = true
            case .ignore:
              break
            case .clearViewport:
              try terminal.clear()
              needsRedraw = true
            case .resetTerminalHistory:
              try session.clearScrollbackAndResetViewport()
              inlineDocumentRuntime.reset()
              terminalHistoryDidReset()
              terminal = try Terminal(
                backend: session.makeBackend(), viewport: session.configuredViewport)
              input.synchronize(with: session)
              needsRedraw = true
            case .suspend:
              try await session.withRestoredTerminal {
                await performSuspendedAction()
              }
              try session.clearScrollbackAndResetViewport()
              inlineDocumentRuntime.reset()
              terminalHistoryDidReset()
              terminal = try Terminal(
                backend: session.makeBackend(), viewport: session.configuredViewport)
              input.synchronize(with: session)
              needsRedraw = true
            case .quit:
              isRunning = false
            }
          }
          if isRunning {
            needsRedraw = true
            refreshObservationTracking = true
          }
          continue
        }
      }

      let nextEvent = try await input.next(wakeup: invalidation.wakeupSource)
      let observationInvalidated = invalidation.take()
      if observationInvalidated { refreshObservationTracking = true }
      guard let event = nextEvent else {
        let periodicRedraw =
          (self as? any PeriodicallyRedrawingTerminalApplication)?.needsPeriodicRedraw ?? false
        let trailingPeriodicRedraw = periodicRedrawWasActive && !periodicRedraw
        needsRedraw =
          needsRedraw || observationInvalidated || periodicRedraw || trailingPeriodicRedraw
        periodicRedrawWasActive = periodicRedraw
        await Task.yield()
        continue
      }
      needsRedraw = needsRedraw || observationInvalidated
      if case .resize(let size) = event {
        let disposition = try session.reanchorAfterResize(size)
        if disposition != .unchanged {
          if disposition == .historyReset {
            inlineDocumentRuntime.reset()
            terminalHistoryDidReset()
          }
          terminal = try Terminal(
            backend: session.makeBackend(), viewport: session.configuredViewport)
          input.synchronize(with: session)
          needsRedraw = true

        }
      }
      let routed = interactionRouter.route(event, through: interactions)
      needsRedraw = needsRedraw || routed.focusChanged
      for routedEvent in routed.events {
        if case .endOfInput = routedEvent {
          isRunning = false
          continue
        }
        let applicationUpdate = await update(routedEvent)
        switch applicationUpdate {
        case .redraw:
          needsRedraw = true
        case .ignore:
          if case .resize = routedEvent {
            needsRedraw = true
          }
        case .clearViewport:
          try terminal.clear()
          needsRedraw = true
        case .resetTerminalHistory:
          try session.clearScrollbackAndResetViewport()
          inlineDocumentRuntime.reset()
          terminalHistoryDidReset()
          terminal = try Terminal(
            backend: session.makeBackend(), viewport: session.configuredViewport)
          input.synchronize(with: session)
          needsRedraw = true
        case .suspend:
          try await session.withRestoredTerminal {
            await performSuspendedAction()
          }
          // A child process can reflow or replace the normal buffer while raw mode is suspended.
          // Reestablish one canonical inline surface, then let source-backed applications replay.
          try session.clearScrollbackAndResetViewport()
          inlineDocumentRuntime.reset()
          terminalHistoryDidReset()
          terminal = try Terminal(
            backend: session.makeBackend(), viewport: session.configuredViewport)
          input.synchronize(with: session)
          needsRedraw = true
        case .quit:
          isRunning = false
        }
      }
      let trailingInvalidation = invalidation.take()
      needsRedraw = needsRedraw || trailingInvalidation
      if needsRedraw { refreshObservationTracking = true }
    }
  }
}
