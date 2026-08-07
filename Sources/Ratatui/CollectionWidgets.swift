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

public struct TabPlacement: Hashable, Sendable {
  public var index: Int
  public var area: Rect

  public init(index: Int, area: Rect) {
    self.index = index
    self.area = area
  }
}

public struct TabLayout: Hashable, Sendable {
  public var viewport: TabViewport
  public var tabs: [TabPlacement]
  public var leadingOverflowArea: Rect?
  public var trailingOverflowArea: Rect?

  public init(
    viewport: TabViewport,
    tabs: [TabPlacement],
    leadingOverflowArea: Rect? = nil,
    trailingOverflowArea: Rect? = nil
  ) {
    self.viewport = viewport
    self.tabs = tabs
    self.leadingOverflowArea = leadingOverflowArea
    self.trailingOverflowArea = trailingOverflowArea
  }
}

public struct Tabs: Widget, Hashable, Sendable {
  public var titles: [Line]
  public var selectedIndex: Int
  public var divider: String
  public var style: Style
  public var selectedStyle: Style
  public var alignment: Alignment
  public var selectionPlacement: SelectionPlacement
  public var leadingOverflowIndicator: String?
  public var trailingOverflowIndicator: String?
  public var interactions: [InteractionDescriptor?]

  public init(
    _ titles: [String],
    selectedIndex: Int = 0,
    divider: String = " │ ",
    style: Style = .plain,
    selectedStyle: Style = Style(modifiers: [.bold, .reversed]),
    alignment: Alignment = .leading,
    selectionPlacement: SelectionPlacement = .trailing,
    leadingOverflowIndicator: String? = "‹ ",
    trailingOverflowIndicator: String? = " ›",
    interactions: [InteractionDescriptor?] = []
  ) {
    self.init(
      titles.map(Line.init),
      selectedIndex: selectedIndex,
      divider: divider,
      style: style,
      selectedStyle: selectedStyle,
      alignment: alignment,
      selectionPlacement: selectionPlacement,
      leadingOverflowIndicator: leadingOverflowIndicator,
      trailingOverflowIndicator: trailingOverflowIndicator,
      interactions: interactions
    )
  }

  public init(
    _ titles: [Line],
    selectedIndex: Int = 0,
    divider: String = " │ ",
    style: Style = .plain,
    selectedStyle: Style = Style(modifiers: [.bold, .reversed]),
    alignment: Alignment = .leading,
    selectionPlacement: SelectionPlacement = .trailing,
    leadingOverflowIndicator: String? = "‹ ",
    trailingOverflowIndicator: String? = " ›",
    interactions: [InteractionDescriptor?] = []
  ) {
    self.titles = titles
    self.selectedIndex = selectedIndex
    self.divider = divider
    self.style = style
    self.selectedStyle = selectedStyle
    self.alignment = alignment
    self.selectionPlacement = selectionPlacement
    self.leadingOverflowIndicator = leadingOverflowIndicator
    self.trailingOverflowIndicator = trailingOverflowIndicator
    self.interactions = interactions
  }

  private var projectedSelectedIndex: Int? {
    guard !titles.isEmpty else { return nil }
    return min(max(0, selectedIndex), titles.count - 1)
  }

  public func layout(in area: Rect) -> TabLayout {
    let emptyViewport = TabViewport(
      range: 0..<0,
      hasTabsBefore: false,
      hasTabsAfter: !titles.isEmpty
    )
    guard !area.isEmpty, !titles.isEmpty else {
      return TabLayout(viewport: emptyViewport, tabs: [])
    }

    let tabWidths = titles.map { saturatingTabsAdd($0.width, 2) }
    let dividerWidth = TerminalWidth.of(divider)
    let leadingIndicatorWidth = leadingOverflowIndicator.map { TerminalWidth.of($0) } ?? 0
    let trailingIndicatorWidth = trailingOverflowIndicator.map { TerminalWidth.of($0) } ?? 0
    let viewport = TabViewport.fitting(
      widths: tabWidths,
      selectedIndex: projectedSelectedIndex,
      capacity: area.width,
      spacing: dividerWidth,
      leadingOverflowWidth: leadingIndicatorWidth,
      trailingOverflowWidth: trailingIndicatorWidth,
      placement: selectionPlacement
    )
    guard !viewport.range.isEmpty else {
      return TabLayout(viewport: viewport, tabs: [])
    }

    let visibleTabWidth = viewport.range.reduce(0) {
      saturatingTabsAdd($0, tabWidths[$1])
    }
    let visibleDividerWidth = saturatingTabsMultiply(
      max(0, viewport.range.count - 1),
      dividerWidth
    )
    let desiredLeading = viewport.hasTabsBefore ? leadingIndicatorWidth : 0
    let desiredTrailing = viewport.hasTabsAfter ? trailingIndicatorWidth : 0
    let desiredWidth = saturatingTabsAdd(
      saturatingTabsAdd(visibleTabWidth, visibleDividerWidth),
      saturatingTabsAdd(desiredLeading, desiredTrailing)
    )

    let leadingWidth: Int
    let trailingWidth: Int
    if desiredWidth <= area.width {
      leadingWidth = desiredLeading
      trailingWidth = desiredTrailing
    } else {
      let markerBudget = max(0, area.width - 1)
      if desiredLeading > 0, desiredTrailing > 0 {
        leadingWidth = min(desiredLeading, (markerBudget + 1) / 2)
        trailingWidth = min(desiredTrailing, markerBudget - leadingWidth)
      } else if desiredLeading > 0 {
        leadingWidth = min(desiredLeading, markerBudget)
        trailingWidth = 0
      } else {
        leadingWidth = 0
        trailingWidth = min(desiredTrailing, markerBudget)
      }
    }

    let tabsBudget = max(0, area.width - leadingWidth - trailingWidth)
    let renderedTabsWidth = min(
      tabsBudget,
      saturatingTabsAdd(visibleTabWidth, visibleDividerWidth)
    )
    let contentWidth = leadingWidth + renderedTabsWidth + trailingWidth
    let horizontalOffset: Int
    switch alignment {
    case .leading: horizontalOffset = 0
    case .center: horizontalOffset = max(0, (area.width - contentWidth) / 2)
    case .trailing: horizontalOffset = max(0, area.width - contentWidth)
    }

    let rowHeight = min(1, area.height)
    let contentX = area.x + horizontalOffset
    let leadingArea =
      leadingWidth > 0
      ? Rect(x: contentX, y: area.y, width: leadingWidth, height: rowHeight)
      : nil
    let tabsStart = contentX + leadingWidth
    let tabsEnd = tabsStart + renderedTabsWidth
    var x = tabsStart
    var placements: [TabPlacement] = []
    placements.reserveCapacity(viewport.range.count)
    for index in viewport.range {
      if index != viewport.range.lowerBound {
        x = min(tabsEnd, saturatingTabsAdd(x, dividerWidth))
      }
      guard x < tabsEnd else { break }
      let width = min(tabWidths[index], tabsEnd - x)
      guard width > 0 else { continue }
      placements.append(
        TabPlacement(
          index: index,
          area: Rect(x: x, y: area.y, width: width, height: rowHeight)
        )
      )
      x += width
    }
    let trailingArea =
      trailingWidth > 0
      ? Rect(
        x: contentX + contentWidth - trailingWidth,
        y: area.y,
        width: trailingWidth,
        height: rowHeight
      )
      : nil

    return TabLayout(
      viewport: viewport,
      tabs: placements,
      leadingOverflowArea: leadingArea,
      trailingOverflowArea: trailingArea
    )
  }

  public func render(in area: Rect, into frame: inout Frame) {
    let layout = layout(in: area)
    if let overflowArea = layout.leadingOverflowArea, let leadingOverflowIndicator {
      frame.buffer.setString(
        TerminalWidth.prefix(leadingOverflowIndicator, fitting: overflowArea.width),
        at: Position(x: overflowArea.x, y: overflowArea.y),
        style: style,
        maxWidth: overflowArea.width
      )
    }
    if let overflowArea = layout.trailingOverflowArea, let trailingOverflowIndicator {
      frame.buffer.setString(
        TerminalWidth.suffix(trailingOverflowIndicator, fitting: overflowArea.width),
        at: Position(x: overflowArea.x, y: overflowArea.y),
        style: style,
        maxWidth: overflowArea.width
      )
    }

    for (offset, placement) in layout.tabs.enumerated() {
      if offset > 0 {
        let previous = layout.tabs[offset - 1].area
        let dividerArea = Rect(
          x: previous.right,
          y: placement.area.y,
          width: max(0, placement.area.x - previous.right),
          height: placement.area.height
        )
        frame.buffer.setString(
          divider,
          at: Position(x: dividerArea.x, y: dividerArea.y),
          style: style,
          maxWidth: dividerArea.width
        )
      }

      let isSelected = placement.index == projectedSelectedIndex
      let activeStyle = isSelected ? style.patching(selectedStyle) : style
      frame.buffer.fill(placement.area, with: Cell(symbol: " ", style: activeStyle))
      if placement.area.width > 2 {
        var renderedTitle = titles[placement.index]
        renderedTitle.style = activeStyle.patching(renderedTitle.style)
        Paragraph(wrap: .none) { renderedTitle }.render(
          in: Rect(
            x: placement.area.x + 1,
            y: placement.area.y,
            width: placement.area.width - 2,
            height: placement.area.height
          ),
          into: &frame.buffer,
          environment: frame.environment
        )
      }
      if interactions.indices.contains(placement.index),
        let interaction = interactions[placement.index]
      {
        frame.addInteraction(
          InteractionRegion(
            control: interaction.control,
            area: placement.area,
            action: interaction.action,
            isFocusable: interaction.isFocusable
          )
        )
      }
    }
  }
}

private func saturatingTabsAdd(_ lhs: Int, _ rhs: Int) -> Int {
  let result = lhs.addingReportingOverflow(rhs)
  return result.overflow ? .max : result.partialValue
}

private func saturatingTabsMultiply(_ lhs: Int, _ rhs: Int) -> Int {
  let result = lhs.multipliedReportingOverflow(by: rhs)
  return result.overflow ? .max : result.partialValue
}

public struct Clear: Widget, Hashable, Sendable {
  public init() {}

  public func render(in area: Rect, into frame: inout Frame) {
    frame.buffer.fill(area, with: .empty)
  }
}
