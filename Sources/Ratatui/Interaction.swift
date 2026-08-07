public struct ControlID: Hashable, Sendable, ExpressibleByStringLiteral {
  public var rawValue: String

  public init(_ rawValue: String) {
    self.rawValue = rawValue
  }

  public init<Value: RawRepresentable>(_ value: Value) where Value.RawValue == String {
    rawValue = value.rawValue
  }

  public init(stringLiteral value: String) {
    rawValue = value
  }
}

public struct ActionID: Hashable, Sendable, ExpressibleByStringLiteral {
  public var rawValue: String

  public init(_ rawValue: String) {
    self.rawValue = rawValue
  }

  public init<Value: RawRepresentable>(_ value: Value) where Value.RawValue == String {
    rawValue = value.rawValue
  }

  public init(stringLiteral value: String) {
    rawValue = value
  }

  public func decode<Value: RawRepresentable>(as type: Value.Type = Value.self) -> Value?
  where Value.RawValue == String {
    Value(rawValue: rawValue)
  }
}

public struct RenderEnvironment: Hashable, Sendable {
  public var focusedControl: ControlID?

  public init(focusedControl: ControlID? = nil) {
    self.focusedControl = focusedControl
  }
}

/// Product-neutral, geometry-free metadata for an interaction generated during rendering.
public struct InteractionDescriptor: Hashable, Sendable {
  public var control: ControlID
  public var action: ActionID?
  public var isFocusable: Bool

  public init(
    control: ControlID,
    action: ActionID? = nil,
    isFocusable: Bool = false
  ) {
    self.control = control
    self.action = action
    self.isFocusable = isFocusable
  }
}

public struct InteractionRegion: Hashable, Sendable {
  public var control: ControlID
  public var area: Rect
  public var action: ActionID?
  public var isFocusable: Bool

  public init(
    control: ControlID,
    area: Rect,
    action: ActionID? = nil,
    isFocusable: Bool = true
  ) {
    self.control = control
    self.area = area
    self.action = action
    self.isFocusable = isFocusable
  }
}

public struct InteractionMap: Hashable, Sendable {
  public var regions: [InteractionRegion]

  public init(regions: [InteractionRegion] = []) {
    self.regions = regions
  }

  public func region(at position: Position) -> InteractionRegion? {
    regions.last { $0.area.contains(position) }
  }

  public func region(for control: ControlID) -> InteractionRegion? {
    regions.first { $0.control == control }
  }

  public var focusableControls: [ControlID] {
    var seen: Set<ControlID> = []
    return regions.compactMap { region in
      guard region.isFocusable, seen.insert(region.control).inserted else { return nil }
      return region.control
    }
  }
}

public struct FocusManager: Hashable, Sendable {
  public private(set) var focusedControl: ControlID?

  public init(focusedControl: ControlID? = nil) {
    self.focusedControl = focusedControl
  }

  @discardableResult
  public mutating func reconcile(with interactions: InteractionMap) -> Bool {
    let controls = interactions.focusableControls
    let previous = focusedControl
    if let focusedControl, controls.contains(focusedControl) {
      return false
    }
    focusedControl = controls.first
    return focusedControl != previous
  }

  @discardableResult
  public mutating func focus(_ control: ControlID?, in interactions: InteractionMap) -> Bool {
    let previous = focusedControl
    if let control {
      focusedControl = interactions.focusableControls.contains(control) ? control : previous
    } else {
      focusedControl = nil
    }
    return focusedControl != previous
  }

  @discardableResult
  public mutating func advance(
    reverse: Bool = false,
    in interactions: InteractionMap
  ) -> Bool {
    let controls = interactions.focusableControls
    guard !controls.isEmpty else {
      let changed = focusedControl != nil
      focusedControl = nil
      return changed
    }
    let current = focusedControl.flatMap { controls.firstIndex(of: $0) }
    let next: Int
    if reverse {
      next = current.map { ($0 - 1 + controls.count) % controls.count } ?? controls.count - 1
    } else {
      next = current.map { ($0 + 1) % controls.count } ?? 0
    }
    let changed = focusedControl != controls[next]
    focusedControl = controls[next]
    return changed
  }
}

public struct RoutedInteraction: Hashable, Sendable {
  public var events: [TerminalEvent]
  public var focusChanged: Bool

  public init(events: [TerminalEvent], focusChanged: Bool = false) {
    self.events = events
    self.focusChanged = focusChanged
  }
}

public struct InteractionRouter: Hashable, Sendable {
  public private(set) var focus: FocusManager

  public init(focusedControl: ControlID? = nil) {
    focus = FocusManager(focusedControl: focusedControl)
  }

  public mutating func reconcile(with interactions: InteractionMap) -> RoutedInteraction? {
    guard focus.reconcile(with: interactions) else { return nil }
    return RoutedInteraction(
      events: [.focusChanged(focus.focusedControl)],
      focusChanged: true
    )
  }

  public mutating func route(
    _ event: TerminalEvent,
    through interactions: InteractionMap
  ) -> RoutedInteraction {
    switch event {
    case .key(let keyEvent) where keyEvent.kind == .release:
      return RoutedInteraction(events: [event])

    case .key(let keyEvent) where keyEvent.key == .tab:
      guard !interactions.focusableControls.isEmpty else {
        return RoutedInteraction(events: [event])
      }
      let changed = focus.advance(
        reverse: keyEvent.modifiers.contains(.shift),
        in: interactions
      )
      return RoutedInteraction(
        events: changed ? [.focusChanged(focus.focusedControl)] : [],
        focusChanged: changed
      )

    case .key(let keyEvent)
    where keyEvent.key == .enter || keyEvent.key == .character(" "):
      if let focused = focus.focusedControl,
        let action = interactions.region(for: focused)?.action
      {
        return RoutedInteraction(events: [.action(action)])
      }
      return RoutedInteraction(events: [event])

    case .mouse(let mouseEvent):
      guard case .down(.left) = mouseEvent.kind,
        let region = interactions.region(at: mouseEvent.position)
      else { return RoutedInteraction(events: [event]) }
      let changed = focus.focus(region.control, in: interactions)
      var events: [TerminalEvent] = []
      if changed { events.append(.focusChanged(focus.focusedControl)) }
      if let action = region.action { events.append(.action(action)) } else { events.append(event) }
      return RoutedInteraction(events: events, focusChanged: changed)

    case .key, .paste, .resize, .terminalFocus, .keyboardEnhancementFlags, .deviceAttributes,
      .cursorPositionReport, .terminalModeReport, .action, .focusChanged, .endOfInput:
      return RoutedInteraction(events: [event])
    }
  }
}
