public enum ListDirection: Hashable, Sendable {
  case topToBottom
  case bottomToTop
}

public enum HighlightSpacing: Hashable, Sendable {
  case always
  case whenSelected
  case never

  func reservesColumn(hasSelection: Bool) -> Bool {
    switch self {
    case .always: true
    case .whenSelected: hasSelection
    case .never: false
    }
  }
}

public struct List<Row>: Widget, StatefulWidget {
  public var rows: [Row]
  public var selectedRow: Int?
  public var selectedStyle: Style
  public var marker: String
  public var direction: ListDirection
  public var repeatMarker: Bool
  public var highlightSpacing: HighlightSpacing
  public var scrollPadding: Int
  private let content: (Row) -> [Line]

  public init<Value>(
    _ rows: [Row],
    label keyPath: KeyPath<Row, Value>,
    selectedRow: Int? = nil,
    marker: String = "› ",
    selectedStyle: Style = Style(modifiers: [.reversed]),
    direction: ListDirection = .topToBottom,
    repeatMarker: Bool = false,
    highlightSpacing: HighlightSpacing = .always,
    scrollPadding: Int = 0,
    format: @escaping (Value) -> String = { String(describing: $0) }
  ) {
    self.rows = rows
    self.selectedRow = selectedRow
    self.marker = marker
    self.selectedStyle = selectedStyle
    self.direction = direction
    self.repeatMarker = repeatMarker
    self.highlightSpacing = highlightSpacing
    self.scrollPadding = max(0, scrollPadding)
    content = { Self.lines(from: format($0[keyPath: keyPath])) }
  }

  public init(
    _ rows: [Row],
    selectedRow: Int? = nil,
    marker: String = "› ",
    selectedStyle: Style = Style(modifiers: [.reversed]),
    direction: ListDirection = .topToBottom,
    repeatMarker: Bool = false,
    highlightSpacing: HighlightSpacing = .always,
    scrollPadding: Int = 0,
    label: @escaping (Row) -> String
  ) {
    self.rows = rows
    self.selectedRow = selectedRow
    self.marker = marker
    self.selectedStyle = selectedStyle
    self.direction = direction
    self.repeatMarker = repeatMarker
    self.highlightSpacing = highlightSpacing
    self.scrollPadding = max(0, scrollPadding)
    content = { Self.lines(from: label($0)) }
  }

  public init(
    _ rows: [Row],
    selectedRow: Int? = nil,
    marker: String = "› ",
    selectedStyle: Style = Style(modifiers: [.reversed]),
    direction: ListDirection = .topToBottom,
    repeatMarker: Bool = false,
    highlightSpacing: HighlightSpacing = .always,
    scrollPadding: Int = 0,
    lines: @escaping (Row) -> [Line]
  ) {
    self.rows = rows
    self.selectedRow = selectedRow
    self.marker = marker
    self.selectedStyle = selectedStyle
    self.direction = direction
    self.repeatMarker = repeatMarker
    self.highlightSpacing = highlightSpacing
    self.scrollPadding = max(0, scrollPadding)
    content = lines
  }

  public func render(in area: Rect, into frame: inout Frame) {
    var state = ListState(selected: selectedRow)
    render(in: area, into: &frame, state: &state)
  }

  public func render(
    in area: Rect,
    into frame: inout Frame,
    state: inout ListState
  ) {
    guard !area.isEmpty else { return }
    guard !rows.isEmpty else {
      state.select(nil)
      return
    }
    let rowLines = rows.map(content)
    let heights = rowLines.map { max(1, $0.count) }
    let bounds = visibleBounds(
      state: &state,
      heights: heights,
      viewportHeight: area.height
    )
    let markerWidth =
      highlightSpacing.reservesColumn(hasSelection: state.selected != nil)
      ? TerminalWidth.of(marker) : 0
    var consumedHeight = 0
    for rowIndex in bounds {
      let lines = rowLines[rowIndex]
      let rowHeight = heights[rowIndex]
      let y: Int
      switch direction {
      case .topToBottom:
        y = area.y + consumedHeight
      case .bottomToTop:
        y = area.y + area.height - consumedHeight - rowHeight
      }
      consumedHeight += rowHeight
      let isSelected = rowIndex == state.selected
      let style = isSelected ? selectedStyle : .plain
      if isSelected {
        frame.buffer.fill(
          Rect(
            x: area.x,
            y: y,
            width: area.width,
            height: rowHeight
          ),
          with: Cell(symbol: " ", style: style)
        )
      }
      for lineIndex in 0..<rowHeight {
        let lineY = (y + lineIndex)
        if markerWidth > 0 {
          let showsMarker = isSelected && (lineIndex == 0 || repeatMarker)
          frame.buffer.setString(
            showsMarker ? marker : String(repeating: " ", count: markerWidth),
            at: Position(x: area.x, y: lineY),
            style: style,
            maxWidth: markerWidth
          )
        }
        guard lineIndex < lines.count else { continue }
        var line = lines[lineIndex]
        if isSelected {
          line.spans = line.spans.map { span in
            var span = span
            span.style = selectedStyle.patching(span.style)
            return span
          }
        }
        Paragraph(wrap: .none) { line }.render(
          in: Rect(
            x: (area.x + markerWidth),
            y: lineY,
            width: (max(0, area.width - markerWidth)),
            height: 1
          ),
          into: &frame.buffer,
          environment: frame.environment
        )
      }
    }
  }

  private func visibleBounds(
    state: inout ListState,
    heights: [Int],
    viewportHeight: Int
  ) -> Range<Int> {
    guard viewportHeight > 0, !heights.isEmpty else {
      state.offset = 0
      return 0..<0
    }
    if let selected = state.selected {
      state.selected = min(max(0, selected), heights.count - 1)
    }
    var first = min(max(0, state.offset), heights.count - 1)
    var last = first
    var usedHeight = 0
    while last < heights.count, usedHeight + heights[last] <= viewportHeight {
      usedHeight += heights[last]
      last += 1
    }
    let target =
      paddedTarget(
        selected: state.selected,
        heights: heights,
        viewportHeight: viewportHeight,
        firstVisible: first,
        lastVisible: last
      ) ?? first
    while target >= last, last < heights.count {
      usedHeight += heights[last]
      last += 1
      while usedHeight > viewportHeight, first < last {
        usedHeight -= heights[first]
        first += 1
      }
    }
    while target < first {
      first -= 1
      usedHeight += heights[first]
      while usedHeight > viewportHeight, last > first {
        last -= 1
        usedHeight -= heights[last]
      }
    }
    state.offset = first
    return first..<last
  }

  private func paddedTarget(
    selected: Int?,
    heights: [Int],
    viewportHeight: Int,
    firstVisible: Int,
    lastVisible: Int
  ) -> Int? {
    guard let selected else { return nil }
    let lastIndex = heights.count - 1
    let clampedSelected = min(max(0, selected), lastIndex)
    var padding = scrollPadding
    while padding > 0 {
      let lower = max(0, clampedSelected - padding)
      let upper = min(lastIndex, clampedSelected + padding)
      let surroundingHeight = heights[lower...upper].reduce(0, +)
      if surroundingHeight <= viewportHeight { break }
      padding -= 1
    }
    if min(lastIndex, clampedSelected + padding) >= lastVisible {
      return min(lastIndex, clampedSelected + padding)
    }
    if max(0, clampedSelected - padding) < firstVisible {
      return max(0, clampedSelected - padding)
    }
    return clampedSelected
  }

  private static func lines(from value: String) -> [Line] {
    value.split(separator: "\n", omittingEmptySubsequences: false).map { Line(String($0)) }
  }
}

public struct Tabs: Widget, Hashable, Sendable {
  public var titles: [Line]
  public var selectedIndex: Int
  public var divider: String
  public var style: Style
  public var selectedStyle: Style
  public var alignment: Alignment

  public init(
    _ titles: [String],
    selectedIndex: Int = 0,
    divider: String = " │ ",
    style: Style = .plain,
    selectedStyle: Style = Style(modifiers: [.bold, .reversed]),
    alignment: Alignment = .leading
  ) {
    self.titles = titles.map(Line.init)
    self.selectedIndex = selectedIndex
    self.divider = divider
    self.style = style
    self.selectedStyle = selectedStyle
    self.alignment = alignment
  }

  public init(
    _ titles: [Line],
    selectedIndex: Int = 0,
    divider: String = " │ ",
    style: Style = .plain,
    selectedStyle: Style = Style(modifiers: [.bold, .reversed]),
    alignment: Alignment = .leading
  ) {
    self.titles = titles
    self.selectedIndex = selectedIndex
    self.divider = divider
    self.style = style
    self.selectedStyle = selectedStyle
    self.alignment = alignment
  }

  public func render(in area: Rect, into frame: inout Frame) {
    guard !area.isEmpty else { return }
    let contentWidth =
      titles.reduce(0) { $0 + $1.width + 2 }
      + max(0, titles.count - 1) * TerminalWidth.of(divider)
    let horizontalOffset: Int
    switch alignment {
    case .leading: horizontalOffset = 0
    case .center: horizontalOffset = max(0, (area.width - contentWidth) / 2)
    case .trailing: horizontalOffset = max(0, area.width - contentWidth)
    }
    var position = Position(
      x: (area.x + horizontalOffset),
      y: area.y
    )
    let end = area.x + area.width
    for (index, title) in titles.enumerated() {
      guard position.x < end else { break }
      if index > 0 {
        position = frame.buffer.setString(
          divider,
          at: position,
          style: style,
          maxWidth: (end - position.x)
        )
      }
      let activeStyle = index == selectedIndex ? style.patching(selectedStyle) : style
      position = frame.buffer.setString(" ", at: position, style: activeStyle, maxWidth: 1)
      var renderedTitle = title
      renderedTitle.spans = renderedTitle.spans.map { span in
        var span = span
        span.style = activeStyle.patching(span.style)
        return span
      }
      let titleWidth = min(renderedTitle.width, max(0, end - position.x))
      Paragraph(wrap: .none) { renderedTitle }.render(
        in: Rect(
          x: position.x,
          y: position.y,
          width: titleWidth,
          height: 1
        ),
        into: &frame.buffer,
        environment: frame.environment
      )
      position.x = (position.x + titleWidth)
      position = frame.buffer.setString(" ", at: position, style: activeStyle, maxWidth: 1)
    }
  }
}

public struct Clear: Widget, Hashable, Sendable {
  public init() {}

  public func render(in area: Rect, into frame: inout Frame) {
    frame.buffer.fill(area, with: .empty)
  }
}
