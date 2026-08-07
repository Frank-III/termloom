public struct Button: Widget, Sendable {
  public var title: String
  public var id: ControlID
  public var action: ActionID
  public var style: Style
  public var focusedStyle: Style
  public var alignment: Alignment

  public init(
    _ title: String,
    id: ControlID,
    action: ActionID,
    style: Style = .plain,
    focusedStyle: Style = Style(modifiers: [.reversed]),
    alignment: Alignment = .center
  ) {
    self.title = title
    self.id = id
    self.action = action
    self.style = style
    self.focusedStyle = focusedStyle
    self.alignment = alignment
  }

  public init<ID: RawRepresentable, Action: RawRepresentable>(
    _ title: String,
    id: ID,
    action: Action,
    style: Style = .plain,
    focusedStyle: Style = Style(modifiers: [.reversed]),
    alignment: Alignment = .center
  ) where ID.RawValue == String, Action.RawValue == String {
    self.init(
      title,
      id: ControlID(id),
      action: ActionID(action),
      style: style,
      focusedStyle: focusedStyle,
      alignment: alignment
    )
  }

  public func render(in area: Rect, into frame: inout Frame) {
    guard !area.isEmpty else { return }
    let activeStyle = frame.environment.focusedControl == id ? style.patching(focusedStyle) : style
    frame.buffer.fill(area, with: Cell(symbol: " ", style: activeStyle))
    frame.render(Text("[ \(title) ]", style: activeStyle, alignment: alignment), in: area)
    frame.addInteraction(InteractionRegion(control: id, area: area, action: action))
  }
}

public struct Focusable<Content: Widget>: Widget {
  public var id: ControlID
  public var action: ActionID?
  public var content: Content

  public init(
    id: ControlID,
    action: ActionID? = nil,
    @WidgetBuilder content: () -> Content
  ) {
    self.id = id
    self.action = action
    self.content = content()
  }

  public func render(in area: Rect, into frame: inout Frame) {
    guard !area.isEmpty else { return }
    frame.addInteraction(InteractionRegion(control: id, area: area, action: action))
    frame.render(content, in: area)
  }
}

public struct Checkbox: Widget, Sendable {
  public var label: String
  public var isOn: Bool
  public var id: ControlID
  public var action: ActionID
  public var style: Style
  public var focusedStyle: Style

  public init(
    _ label: String,
    isOn: Bool,
    id: ControlID,
    action: ActionID,
    style: Style = .plain,
    focusedStyle: Style = Style(modifiers: [.reversed])
  ) {
    self.label = label
    self.isOn = isOn
    self.id = id
    self.action = action
    self.style = style
    self.focusedStyle = focusedStyle
  }

  public func render(in area: Rect, into frame: inout Frame) {
    guard !area.isEmpty else { return }
    let activeStyle = frame.environment.focusedControl == id ? style.patching(focusedStyle) : style
    frame.buffer.fill(area, with: Cell(symbol: " ", style: activeStyle))
    frame.buffer.setString(
      "[\(isOn ? "x" : " ")] \(label)",
      at: Position(x: area.x, y: area.y),
      style: activeStyle,
      maxWidth: area.width
    )
    frame.addInteraction(InteractionRegion(control: id, area: area, action: action))
  }
}

public struct RadioButton: Widget, Sendable {
  public var label: String
  public var isSelected: Bool
  public var id: ControlID
  public var action: ActionID
  public var style: Style
  public var focusedStyle: Style

  public init(
    _ label: String,
    isSelected: Bool,
    id: ControlID,
    action: ActionID,
    style: Style = .plain,
    focusedStyle: Style = Style(modifiers: [.reversed])
  ) {
    self.label = label
    self.isSelected = isSelected
    self.id = id
    self.action = action
    self.style = style
    self.focusedStyle = focusedStyle
  }

  public func render(in area: Rect, into frame: inout Frame) {
    guard !area.isEmpty else { return }
    let activeStyle = frame.environment.focusedControl == id ? style.patching(focusedStyle) : style
    frame.buffer.fill(area, with: Cell(symbol: " ", style: activeStyle))
    frame.buffer.setString(
      "(\(isSelected ? "•" : " ")) \(label)",
      at: Position(x: area.x, y: area.y),
      style: activeStyle,
      maxWidth: area.width
    )
    frame.addInteraction(InteractionRegion(control: id, area: area, action: action))
  }
}

public struct TextFieldElementID: Hashable, Sendable, ExpressibleByStringLiteral {
  public var rawValue: String

  public init(_ rawValue: String) {
    self.rawValue = rawValue
  }

  public init(stringLiteral value: String) {
    rawValue = value
  }
}

public struct TextFieldElement: Hashable, Sendable {
  public var id: TextFieldElementID
  public var range: Range<Int>

  public init(id: TextFieldElementID, range: Range<Int>) {
    self.id = id
    self.range = range
  }
}

public struct TextFieldState: Hashable, Sendable {
  public var text: String {
    didSet {
      elements.removeAll(keepingCapacity: true)
      cursor = min(max(0, cursor), text.count)
      if let selectionAnchor {
        self.selectionAnchor = min(max(0, selectionAnchor), text.count)
      }
    }
  }
  public var cursor: Int
  public var selectionAnchor: Int?
  public var horizontalOffset: Int
  public private(set) var elements: [TextFieldElement]

  public init(
    text: String = "",
    cursor: Int? = nil,
    selectionAnchor: Int? = nil,
    horizontalOffset: Int = 0
  ) {
    self.text = text
    self.cursor = cursor ?? text.count
    self.selectionAnchor = selectionAnchor
    self.horizontalOffset = max(0, horizontalOffset)
    elements = []
    reconcile()
  }

  public var selection: Range<Int>? {
    guard let selectionAnchor, selectionAnchor != cursor else { return nil }
    return min(selectionAnchor, cursor)..<max(selectionAnchor, cursor)
  }

  @discardableResult
  public mutating func handle(_ event: TerminalEvent) -> Bool {
    reconcile()
    switch event {
    case .paste(let value):
      insert(value)
      return true
    case .key(let keyEvent) where keyEvent.kind != .release:
      return handle(keyEvent)
    default:
      return false
    }
  }

  public mutating func selectAll() {
    selectionAnchor = 0
    cursor = text.count
  }

  /// Inserts a protected text element at the current selection or cursor.
  ///
  /// Cursor movement skips the element interior, and any deletion intersecting it removes the entire
  /// element. Callers retain semantic payloads by `id`; the visible text remains ordinary terminal text.
  public mutating func insertElement(_ value: String, id: TextFieldElementID) {
    guard !value.isEmpty else { return }
    _ = deleteSelection()
    insert(value)
    let insertionOffset = cursor - value.count
    elements.append(
      TextFieldElement(id: id, range: insertionOffset..<(insertionOffset + value.count)))
    elements.sort { $0.range.lowerBound < $1.range.lowerBound }
  }

  /// Returns text with protected elements replaced by their semantic payloads.
  public func expandingElements(
    _ replacement: (TextFieldElementID) -> String?
  ) -> String {
    var result = text
    for element in elements.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) {
      guard let value = replacement(element.id) else { continue }
      let lower = result.index(result.startIndex, offsetBy: element.range.lowerBound)
      let upper = result.index(result.startIndex, offsetBy: element.range.upperBound)
      result.replaceSubrange(lower..<upper, with: value)
    }
    return result
  }

  /// Expands a character range so a mutation cannot split protected elements.
  public func rangeIncludingElements(_ range: Range<Int>) -> Range<Int> {
    var lower = min(max(0, range.lowerBound), text.count)
    var upper = min(max(lower, range.upperBound), text.count)
    for element in elements where element.range.overlaps(lower..<upper) {
      lower = min(lower, element.range.lowerBound)
      upper = max(upper, element.range.upperBound)
    }
    return lower..<upper
  }

  @discardableResult
  public mutating func handle(
    _ event: TerminalEvent,
    when focusedControl: ControlID?,
    is id: ControlID
  ) -> Bool {
    guard focusedControl == id else { return false }
    return handle(event)
  }

  private mutating func handle(_ event: KeyEvent) -> Bool {
    let selecting = event.modifiers.contains(.shift)
    let movesByWord = !event.modifiers.intersection([.option, .control]).isEmpty
    switch event.key {
    case .left:
      move(to: movesByWord ? previousWordBoundary() : cursor - 1, selecting: selecting)
    case .right:
      move(to: movesByWord ? nextWordBoundary() : cursor + 1, selecting: selecting)
    case .home:
      move(to: 0, selecting: selecting)
    case .end:
      move(to: text.count, selecting: selecting)
    case .backspace:
      if !deleteSelection() {
        if event.modifiers.contains(.command) {
          delete(0..<cursor)
        } else {
          delete(movesByWord ? previousWordBoundary()..<cursor : cursor - 1..<cursor)
        }
      }
    case .delete:
      if !deleteSelection() {
        if event.modifiers.contains(.command) {
          delete(cursor..<text.count)
        } else {
          delete(cursor..<(movesByWord ? nextWordBoundary() : cursor + 1))
        }
      }
    case .character("w") where event.modifiers.contains(.control):
      if !deleteSelection() { delete(previousWordBoundary()..<cursor) }
    case .character("u") where event.modifiers.contains(.control):
      if !deleteSelection() { delete(0..<cursor) }
    case .character("k") where event.modifiers.contains(.control):
      if !deleteSelection() { delete(cursor..<text.count) }
    case .character("d") where event.modifiers.contains(.control):
      if !deleteSelection() { delete(cursor..<min(text.count, cursor + 1)) }
    case .character("d") where event.modifiers.contains(.option):
      if !deleteSelection() { delete(cursor..<nextWordBoundary()) }
    case .character("b") where event.modifiers.contains(.control):
      move(to: cursor - 1, selecting: selecting)
    case .character("f") where event.modifiers.contains(.control):
      move(to: cursor + 1, selecting: selecting)
    case .character("a") where event.modifiers.contains(.command):
      selectAll()
    case .character("a") where event.modifiers.contains(.control):
      move(to: 0, selecting: selecting)
    case .character("e") where event.modifiers.contains(.control):
      move(to: text.count, selecting: selecting)
    case .character(let character)
    where event.modifiers.intersection([.control, .command, .hyper, .meta]).isEmpty:
      insert(event.text ?? String(character))
    default:
      return false
    }
    return true
  }

  public mutating func moveCursor(to offset: Int, selecting: Bool = false) {
    move(to: offset, selecting: selecting)
  }

  private mutating func move(to offset: Int, selecting: Bool) {
    if selecting {
      selectionAnchor = selectionAnchor ?? cursor
    } else {
      selectionAnchor = nil
    }
    let proposed = min(max(0, offset), text.count)
    guard
      let element = elements.first(where: {
        $0.range.lowerBound < proposed && proposed < $0.range.upperBound
      })
    else {
      cursor = proposed
      return
    }
    cursor = proposed < cursor ? element.range.lowerBound : element.range.upperBound
  }

  public mutating func insert(_ value: String) {
    reconcile()
    if selection == nil,
      let element = elements.first(where: {
        $0.range.lowerBound < cursor && cursor < $0.range.upperBound
      })
    {
      cursor = element.range.upperBound
    }
    _ = deleteSelection()
    let insertionOffset = cursor
    let retainedElements = elements
    let index = text.index(text.startIndex, offsetBy: insertionOffset)
    text.insert(contentsOf: value, at: index)
    elements = retainedElements.map { element in
      guard element.range.lowerBound >= insertionOffset else { return element }
      return TextFieldElement(
        id: element.id,
        range: (element.range.lowerBound + value.count)..<(element.range.upperBound + value.count))
    }
    cursor += value.count
    selectionAnchor = nil
  }

  @discardableResult
  private mutating func deleteSelection() -> Bool {
    guard let selection else { return false }
    delete(selection)
    return true
  }

  @discardableResult
  public mutating func delete(_ range: Range<Int>) -> String {
    let expanded = rangeIncludingElements(range)
    let lower = expanded.lowerBound
    let upper = expanded.upperBound
    guard lower < upper else { return "" }
    let retainedElements = elements
    let stringRange =
      text.index(
        text.startIndex, offsetBy: lower)..<text.index(
        text.startIndex,
        offsetBy: upper
      )
    let removed = String(text[stringRange])
    text.removeSubrange(stringRange)
    elements = retainedElements.compactMap { element in
      if element.range.overlaps(expanded) { return nil }
      guard element.range.lowerBound >= upper else { return element }
      let shiftedLower = element.range.lowerBound - expanded.count
      let shiftedUpper = element.range.upperBound - expanded.count
      return TextFieldElement(id: element.id, range: shiftedLower..<shiftedUpper)
    }
    cursor = lower
    selectionAnchor = nil
    return removed
  }

  private func previousWordBoundary() -> Int {
    let characters = Array(text)
    var index = min(cursor, characters.count)
    while index > 0, characters[index - 1].isWhitespace { index -= 1 }
    while index > 0, !characters[index - 1].isWhitespace { index -= 1 }
    return index
  }

  private func nextWordBoundary() -> Int {
    let characters = Array(text)
    var index = min(cursor, characters.count)
    while index < characters.count, !characters[index].isWhitespace { index += 1 }
    while index < characters.count, characters[index].isWhitespace { index += 1 }
    return index
  }

  fileprivate mutating func reconcile() {
    cursor = min(max(0, cursor), text.count)
    if let selectionAnchor {
      self.selectionAnchor = min(max(0, selectionAnchor), text.count)
    }
    horizontalOffset = max(0, horizontalOffset)
  }

  fileprivate func resolvedHorizontalOffset(viewportWidth: Int) -> Int {
    guard viewportWidth > 0 else { return 0 }
    let characters = Array(text)
    let cursorColumn = TerminalWidth.of(String(characters.prefix(cursor)))
    if cursorColumn < horizontalOffset { return cursorColumn }
    if cursorColumn >= horizontalOffset + viewportWidth {
      let minimumOffset = cursorColumn - viewportWidth + 1
      var boundary = 0
      for character in characters.prefix(cursor) {
        guard boundary < minimumOffset else { break }
        boundary += TerminalWidth.of(character)
      }
      return boundary
    }
    return horizontalOffset
  }
}

public struct TextField: Widget, StatefulWidget {
  public var value: TextFieldState
  public var id: ControlID
  public var placeholder: String
  public var style: Style
  public var focusedStyle: Style
  public var selectionStyle: Style

  public init(
    _ value: TextFieldState = TextFieldState(),
    id: ControlID,
    placeholder: String = "",
    style: Style = .plain,
    focusedStyle: Style = Style(modifiers: [.underlined]),
    selectionStyle: Style = Style(modifiers: [.reversed])
  ) {
    self.value = value
    self.id = id
    self.placeholder = placeholder
    self.style = style
    self.focusedStyle = focusedStyle
    self.selectionStyle = selectionStyle
  }

  public func render(in area: Rect, into frame: inout Frame) {
    var state = value
    render(in: area, into: &frame, state: &state)
  }

  public func render(
    in area: Rect,
    into frame: inout Frame,
    state: inout TextFieldState
  ) {
    guard !area.isEmpty else { return }
    state.reconcile()
    state.horizontalOffset = state.resolvedHorizontalOffset(viewportWidth: Int(area.width))
    let isFocused = frame.environment.focusedControl == id
    let activeStyle = isFocused ? style.patching(focusedStyle) : style
    frame.buffer.fill(area, with: Cell(symbol: " ", style: activeStyle))

    let characters = Array(state.text)
    if state.text.isEmpty {
      frame.buffer.setString(
        placeholder,
        at: Position(x: area.x, y: area.y),
        style: activeStyle.adding(.dim),
        maxWidth: area.width
      )
    } else {
      var sourceColumn = 0
      var targetColumn = 0
      for (index, character) in characters.enumerated() {
        let width = TerminalWidth.of(character)
        defer { sourceColumn += width }
        guard sourceColumn + width > state.horizontalOffset else { continue }
        guard targetColumn + width <= Int(area.width) else { break }
        let selected = state.selection?.contains(index) == true
        frame.buffer.setString(
          String(character),
          at: Position(
            x: UInt16(clamping: Int(area.x) + targetColumn),
            y: area.y
          ),
          style: selected ? activeStyle.patching(selectionStyle) : activeStyle,
          maxWidth: UInt16(clamping: Int(area.width) - targetColumn)
        )
        targetColumn += width
      }
    }

    frame.addInteraction(InteractionRegion(control: id, area: area))
    if isFocused {
      let column = TerminalWidth.of(String(characters.prefix(state.cursor))) - state.horizontalOffset
      frame.placeCursor(
        at: Position(
          x: UInt16(clamping: Int(area.x) + min(max(0, column), Int(area.width) - 1)),
          y: area.y
        ))
    }
  }
}
