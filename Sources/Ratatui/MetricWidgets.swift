import Foundation

public struct Gauge: Widget, Hashable, Sendable {
  public var ratio: Double
  public var label: String?
  public var filledStyle: Style
  public var emptyStyle: Style
  public var symbols: (filled: Character, empty: Character)

  public init(
    ratio: Double,
    label: String? = nil,
    filledStyle: Style = Style(foreground: .green),
    emptyStyle: Style = Style(foreground: .darkGray),
    symbols: (filled: Character, empty: Character) = ("█", "░")
  ) {
    self.ratio = min(1, max(0, ratio))
    self.label = label
    self.filledStyle = filledStyle
    self.emptyStyle = emptyStyle
    self.symbols = symbols
  }

  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.ratio == rhs.ratio && lhs.label == rhs.label && lhs.filledStyle == rhs.filledStyle
      && lhs.emptyStyle == rhs.emptyStyle && lhs.symbols == rhs.symbols
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(ratio)
    hasher.combine(label)
    hasher.combine(filledStyle)
    hasher.combine(emptyStyle)
    hasher.combine(symbols.filled)
    hasher.combine(symbols.empty)
  }

  public func render(in area: Rect, into frame: inout Frame) {
    guard !area.isEmpty else { return }
    let filled = Int((Double(area.width) * ratio).rounded(.down))
    for x in 0..<Int(area.width) {
      frame.buffer.setString(
        String(x < filled ? symbols.filled : symbols.empty),
        at: Position(x: UInt16(clamping: Int(area.x) + x), y: area.y),
        style: x < filled ? filledStyle : emptyStyle
      )
    }
    let displayLabel = label ?? "\(Int((ratio * 100).rounded()))%"
    Text(displayLabel, style: Style(modifiers: [.bold]), alignment: .center)
      .render(in: area, into: &frame.buffer, environment: frame.environment)
  }
}

public struct LineGauge: Widget, Hashable, Sendable {
  public var ratio: Double
  public var label: String?
  public var style: Style
  public var filledStyle: Style
  public var unfilledStyle: Style
  public var filledSymbol: Character
  public var unfilledSymbol: Character

  public init(
    ratio: Double,
    label: String? = nil,
    style: Style = .plain,
    filledStyle: Style = Style(foreground: .green),
    unfilledStyle: Style = Style(foreground: .darkGray),
    filledSymbol: Character = "━",
    unfilledSymbol: Character = "─"
  ) {
    self.ratio = min(1, max(0, ratio))
    self.label = label
    self.style = style
    self.filledStyle = filledStyle
    self.unfilledStyle = unfilledStyle
    self.filledSymbol = filledSymbol
    self.unfilledSymbol = unfilledSymbol
  }

  public func render(in area: Rect, into frame: inout Frame) {
    guard !area.isEmpty else { return }
    let displayLabel = label ?? String(format: "%3.0f%%", ratio * 100)
    let labelEnd = frame.buffer.setString(
      displayLabel,
      at: Position(x: area.x, y: area.y),
      style: style,
      maxWidth: area.width
    )
    let start = min(Int(area.x) + Int(area.width), Int(labelEnd.x) + 1)
    let end = Int(area.x) + Int(area.width)
    let filledEnd = start + Int((Double(max(0, end - start)) * ratio).rounded(.down))
    for x in start..<end {
      frame.buffer.setString(
        String(x < filledEnd ? filledSymbol : unfilledSymbol),
        at: Position(x: UInt16(clamping: x), y: area.y),
        style: x < filledEnd ? filledStyle : unfilledStyle
      )
    }
  }
}

public enum RenderDirection: Hashable, Sendable {
  case leftToRight
  case rightToLeft
}

public struct SparklineBar: Hashable, Sendable {
  public var value: Double?
  public var style: Style?

  public init(_ value: Double?, style: Style? = nil) {
    self.value = value
    self.style = style
  }

  public func style(_ style: Style?) -> Self {
    var copy = self
    copy.style = style
    return copy
  }
}

public struct Sparkline: Widget, Hashable, Sendable {
  public var values: [Double?]
  public var valueStyles: [Style?]
  public var bounds: ClosedRange<Double>?
  public var style: Style
  public var direction: RenderDirection
  public var absentValueStyle: Style
  public var absentValueSymbol: Character
  public var symbolSet: Symbols.Bar.Set

  public init(
    _ values: [Double],
    bounds: ClosedRange<Double>? = nil,
    style: Style = .plain,
    direction: RenderDirection = .leftToRight,
    absentValueStyle: Style = .plain,
    absentValueSymbol: Character = "░",
    symbolSet: Symbols.Bar.Set = .nineLevels
  ) {
    self.values = values.map(Optional.some)
    valueStyles = Array(repeating: nil, count: values.count)
    self.bounds = bounds
    self.style = style
    self.direction = direction
    self.absentValueStyle = absentValueStyle
    self.absentValueSymbol = absentValueSymbol
    self.symbolSet = symbolSet
  }

  public init(
    _ values: [Double?],
    bounds: ClosedRange<Double>? = nil,
    style: Style = .plain,
    direction: RenderDirection = .leftToRight,
    absentValueStyle: Style = .plain,
    absentValueSymbol: Character = "░",
    symbolSet: Symbols.Bar.Set = .nineLevels
  ) {
    self.values = values
    valueStyles = Array(repeating: nil, count: values.count)
    self.bounds = bounds
    self.style = style
    self.direction = direction
    self.absentValueStyle = absentValueStyle
    self.absentValueSymbol = absentValueSymbol
    self.symbolSet = symbolSet
  }

  public init(
    _ bars: [SparklineBar],
    bounds: ClosedRange<Double>? = nil,
    style: Style = .plain,
    direction: RenderDirection = .leftToRight,
    absentValueStyle: Style = .plain,
    absentValueSymbol: Character = "░",
    symbolSet: Symbols.Bar.Set = .nineLevels
  ) {
    values = bars.map(\.value)
    valueStyles = bars.map(\.style)
    self.bounds = bounds
    self.style = style
    self.direction = direction
    self.absentValueStyle = absentValueStyle
    self.absentValueSymbol = absentValueSymbol
    self.symbolSet = symbolSet
  }

  public func render(in area: Rect, into frame: inout Frame) {
    guard !area.isEmpty, !values.isEmpty else { return }
    let visible = Array(values.prefix(Int(area.width)))
    let present = visible.compactMap { $0 }
    let range = bounds ?? (present.min() ?? 0)...(present.max() ?? 1)
    let extent = max(Double.ulpOfOne, range.upperBound - range.lowerBound)
    for (index, value) in visible.enumerated() {
      let x =
        direction == .leftToRight
        ? Int(area.x) + index
        : Int(area.x) + Int(area.width) - index - 1
      guard let value else {
        for row in 0..<Int(area.height) {
          frame.buffer.setString(
            String(absentValueSymbol),
            at: Position(x: UInt16(clamping: x), y: UInt16(clamping: Int(area.y) + row)),
            style: style.patching(absentValueStyle)
          )
        }
        continue
      }
      let valueStyle = style.patching(valueStyles[index] ?? .plain)
      let normalized = min(1, max(0, (value - range.lowerBound) / extent))
      if area.height == 1 {
        let symbolIndex = min(8, max(0, Int(normalized * 8)))
        frame.buffer.setString(
          String(symbolSet[symbolIndex]),
          at: Position(x: UInt16(clamping: x), y: area.y),
          style: valueStyle
        )
      } else {
        var ticks = Int(normalized * Double(Int(area.height) * 8))
        for row in (0..<Int(area.height)).reversed() {
          let rowTicks = min(8, ticks)
          let symbol = String(symbolSet[rowTicks])
          frame.buffer.setString(
            symbol,
            at: Position(x: UInt16(clamping: x), y: UInt16(clamping: Int(area.y) + row)),
            style: valueStyle
          )
          ticks = max(0, ticks - 8)
        }
      }
    }
  }
}

public struct Bar: Hashable, Sendable {
  public var label: String
  public var value: Double
  public var style: Style
  public var valueLabel: String?

  public init(
    _ label: String,
    value: Double,
    style: Style = .plain,
    valueLabel: String? = nil
  ) {
    self.label = label
    self.value = value
    self.style = style
    self.valueLabel = valueLabel
  }
}

public struct BarGroup: Hashable, Sendable {
  public var label: String?
  public var bars: [Bar]

  public init(_ label: String? = nil, bars: [Bar]) {
    self.label = label
    self.bars = bars
  }
}

public enum BarChartDirection: Hashable, Sendable {
  case vertical
  case horizontal
}

public struct BarChart: Widget, Hashable, Sendable {
  public var groups: [BarGroup]
  public var maximum: Double?
  public var barWidth: UInt16
  public var spacing: UInt16
  public var groupSpacing: UInt16
  public var direction: BarChartDirection
  public var showsValues: Bool

  public var bars: [Bar] {
    get { groups.flatMap(\.bars) }
    set { groups = [BarGroup(bars: newValue)] }
  }

  public init(
    _ bars: [Bar],
    maximum: Double? = nil,
    barWidth: UInt16 = 3,
    spacing: UInt16 = 1,
    direction: BarChartDirection = .vertical,
    showsValues: Bool = false
  ) {
    groups = [BarGroup(bars: bars)]
    self.maximum = maximum
    self.barWidth = max(1, barWidth)
    self.spacing = spacing
    groupSpacing = spacing
    self.direction = direction
    self.showsValues = showsValues
  }

  public init(
    groups: [BarGroup],
    maximum: Double? = nil,
    barWidth: UInt16 = 3,
    spacing: UInt16 = 1,
    groupSpacing: UInt16 = 2,
    direction: BarChartDirection = .vertical,
    showsValues: Bool = false
  ) {
    self.groups = groups
    self.maximum = maximum
    self.barWidth = max(1, barWidth)
    self.spacing = spacing
    self.groupSpacing = groupSpacing
    self.direction = direction
    self.showsValues = showsValues
  }

  public func render(in area: Rect, into frame: inout Frame) {
    guard !area.isEmpty, !bars.isEmpty else { return }
    let maxValue = max(Double.ulpOfOne, maximum ?? bars.map(\.value).max() ?? 1)
    switch direction {
    case .vertical:
      renderVertical(
        in: area,
        into: &frame.buffer,
        environment: frame.environment,
        maximum: maxValue
      )
    case .horizontal:
      renderHorizontal(
        in: area,
        into: &frame.buffer,
        environment: frame.environment,
        maximum: maxValue
      )
    }
  }

  private func renderVertical(
    in area: Rect,
    into buffer: inout Buffer,
    environment: RenderEnvironment,
    maximum: Double
  ) {
    let hasGroupLabels = groups.contains { $0.label != nil }
    let labelRows = hasGroupLabels ? 2 : 1
    let plotHeight = max(0, Int(area.height) - labelRows)
    guard plotHeight > 0 else { return }
    let partialSymbols = Array("▁▂▃▄▅▆▇")
    var x = Int(area.x)
    let end = Int(area.x) + Int(area.width)
    for (groupIndex, group) in groups.enumerated() where x < end {
      let groupStart = x
      for bar in group.bars where x < end {
        let ticks = min(
          plotHeight * 8,
          Int((max(0, bar.value) / maximum * Double(plotHeight * 8)).rounded())
        )
        for column in 0..<Int(barWidth) where x + column < end {
          for row in 0..<plotHeight {
            let remaining = ticks - row * 8
            guard remaining > 0 else { break }
            let symbol = remaining >= 8 ? "█" : String(partialSymbols[remaining - 1])
            buffer.setString(
              symbol,
              at: Position(
                x: UInt16(clamping: x + column),
                y: UInt16(clamping: Int(area.y) + plotHeight - 1 - row)
              ),
              style: bar.style
            )
          }
        }
        if showsValues {
          let value = bar.valueLabel ?? String(format: "%g", bar.value)
          Text(value, style: bar.style, alignment: .center).render(
            in: Rect(
              x: UInt16(clamping: x),
              y: UInt16(clamping: max(Int(area.y), Int(area.y) + plotHeight - (ticks + 7) / 8)),
              width: min(barWidth, UInt16(clamping: end - x)),
              height: 1
            ),
            into: &buffer,
            environment: environment
          )
        }
        Text(bar.label, style: bar.style, alignment: .center).render(
          in: Rect(
            x: UInt16(clamping: x),
            y: UInt16(clamping: Int(area.y) + plotHeight),
            width: min(barWidth, UInt16(clamping: end - x)),
            height: 1
          ),
          into: &buffer,
          environment: environment
        )
        x += Int(barWidth) + Int(spacing)
      }
      if !group.bars.isEmpty { x -= Int(spacing) }
      if let label = group.label {
        Text(label, alignment: .center).render(
          in: Rect(
            x: UInt16(clamping: groupStart),
            y: UInt16(clamping: Int(area.y) + plotHeight + 1),
            width: UInt16(clamping: max(0, min(end, x) - groupStart)),
            height: 1
          ),
          into: &buffer,
          environment: environment
        )
      }
      if groupIndex < groups.count - 1 { x += Int(groupSpacing) }
    }
  }

  private func renderHorizontal(
    in area: Rect,
    into buffer: inout Buffer,
    environment: RenderEnvironment,
    maximum: Double
  ) {
    let visibleBars = Array(bars.prefix(Int(area.height)))
    let labelWidth = min(
      max(0, Int(area.width) / 3),
      visibleBars.map { TerminalWidth.of($0.label) }.max() ?? 0
    )
    let plotStart = Int(area.x) + (labelWidth > 0 ? labelWidth + 1 : 0)
    let plotWidth = max(0, Int(area.x) + Int(area.width) - plotStart)
    let partialSymbols = Array("▏▎▍▌▋▊▉")
    for (row, bar) in visibleBars.enumerated() {
      let y = UInt16(clamping: Int(area.y) + row)
      Text(bar.label, style: bar.style, alignment: .trailing).render(
        in: Rect(x: area.x, y: y, width: UInt16(clamping: labelWidth), height: 1),
        into: &buffer,
        environment: environment
      )
      let ticks = min(
        plotWidth * 8,
        Int((max(0, bar.value) / maximum * Double(plotWidth * 8)).rounded())
      )
      let full = ticks / 8
      if full > 0 {
        buffer.setString(
          String(repeating: "█", count: full),
          at: Position(x: UInt16(clamping: plotStart), y: y),
          style: bar.style,
          maxWidth: UInt16(clamping: plotWidth)
        )
      }
      let remainder = ticks % 8
      if remainder > 0, full < plotWidth {
        buffer.setString(
          String(partialSymbols[remainder - 1]),
          at: Position(x: UInt16(clamping: plotStart + full), y: y),
          style: bar.style
        )
      }
      if showsValues {
        let value = bar.valueLabel ?? String(format: "%g", bar.value)
        buffer.setString(
          value,
          at: Position(x: UInt16(clamping: plotStart), y: y),
          style: bar.style,
          maxWidth: UInt16(clamping: plotWidth)
        )
      }
    }
  }
}

public enum ScrollbarOrientation: Hashable, Sendable {
  case vertical
  case horizontal
  case verticalLeft
  case verticalRight
  case horizontalTop
  case horizontalBottom
}

public struct ScrollbarState: Hashable, Sendable {
  public var contentLength: Int
  public var viewportLength: Int
  public var position: Int

  public init(contentLength: Int, viewportLength: Int, position: Int = 0) {
    self.contentLength = max(0, contentLength)
    self.viewportLength = max(0, viewportLength)
    self.position = max(0, position)
  }

  public mutating func scroll(to position: Int) {
    self.position = min(max(0, position), max(0, contentLength - viewportLength))
  }

  public mutating func scroll(by offset: Int) { scroll(to: position + offset) }
  public mutating func scrollToBeginning() { scroll(to: 0) }
  public mutating func scrollToEnd() { scroll(to: contentLength) }
}

public struct Scrollbar: Widget, StatefulWidget, Hashable, Sendable {
  public var contentLength: Int
  public var viewportLength: Int
  public var position: Int
  public var orientation: ScrollbarOrientation
  public var style: Style
  public var thumbStyle: Style
  public var trackSymbol: Character
  public var thumbSymbol: Character
  public var beginSymbol: Character?
  public var endSymbol: Character?

  public init(
    contentLength: Int,
    viewportLength: Int,
    position: Int,
    orientation: ScrollbarOrientation = .vertical,
    style: Style = .plain,
    thumbStyle: Style = Style(modifiers: [.reversed]),
    trackSymbol: Character? = nil,
    thumbSymbol: Character = "█",
    beginSymbol: Character? = nil,
    endSymbol: Character? = nil
  ) {
    self.contentLength = max(0, contentLength)
    self.viewportLength = max(0, viewportLength)
    self.position = max(0, position)
    self.orientation = orientation
    self.style = style
    self.thumbStyle = thumbStyle
    self.trackSymbol = trackSymbol ?? (orientation.isVertical ? "│" : "─")
    self.thumbSymbol = thumbSymbol
    self.beginSymbol = beginSymbol
    self.endSymbol = endSymbol
  }

  public func render(in area: Rect, into frame: inout Frame) {
    var state = ScrollbarState(
      contentLength: contentLength,
      viewportLength: viewportLength,
      position: position
    )
    render(in: area, into: &frame, state: &state)
  }

  public func render(
    in area: Rect,
    into frame: inout Frame,
    state: inout ScrollbarState
  ) {
    state.scroll(to: state.position)
    let length = orientation.isVertical ? Int(area.height) : Int(area.width)
    guard length > 0 else { return }
    let leading = beginSymbol == nil ? 0 : 1
    let trailing = endSymbol == nil ? 0 : 1
    let trackLength = max(0, length - leading - trailing)
    guard trackLength > 0 else { return }
    let thumbLength =
      state.contentLength <= state.viewportLength
      ? trackLength
      : max(1, trackLength * state.viewportLength / max(1, state.contentLength))
    let maximumPosition = max(1, state.contentLength - state.viewportLength)
    let thumbStart =
      leading + (trackLength - thumbLength) * min(state.position, maximumPosition) / maximumPosition
    for offset in 0..<length {
      let isThumb = offset >= thumbStart && offset < thumbStart + thumbLength
      let symbol: Character
      if offset == 0, let beginSymbol {
        symbol = beginSymbol
      } else if offset == length - 1, let endSymbol {
        symbol = endSymbol
      } else {
        symbol = isThumb ? thumbSymbol : trackSymbol
      }
      let point: Position
      switch orientation {
      case .vertical, .verticalLeft:
        point = Position(x: area.x, y: UInt16(clamping: Int(area.y) + offset))
      case .verticalRight:
        point = Position(
          x: UInt16(clamping: Int(area.x) + Int(area.width) - 1),
          y: UInt16(clamping: Int(area.y) + offset)
        )
      case .horizontal, .horizontalTop:
        point = Position(x: UInt16(clamping: Int(area.x) + offset), y: area.y)
      case .horizontalBottom:
        point = Position(
          x: UInt16(clamping: Int(area.x) + offset),
          y: UInt16(clamping: Int(area.y) + Int(area.height) - 1)
        )
      }
      frame.buffer.setString(
        String(symbol),
        at: point,
        style: isThumb ? style.patching(thumbStyle) : style
      )
    }
  }
}

extension ScrollbarOrientation {
  fileprivate var isVertical: Bool {
    switch self {
    case .vertical, .verticalLeft, .verticalRight: true
    case .horizontal, .horizontalTop, .horizontalBottom: false
    }
  }
}
