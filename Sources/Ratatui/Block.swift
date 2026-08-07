public struct BorderEdges: OptionSet, Hashable, Sendable {
  public let rawValue: UInt8

  public init(rawValue: UInt8) {
    self.rawValue = rawValue
  }

  public static let top = Self(rawValue: 1 << 0)
  public static let trailing = Self(rawValue: 1 << 1)
  public static let bottom = Self(rawValue: 1 << 2)
  public static let leading = Self(rawValue: 1 << 3)
  public static let all: Self = [.top, .trailing, .bottom, .leading]
}

/// Internal spacing for a ``Block``.
///
/// Horizontal values use Swift's direction-aware leading/trailing vocabulary. The left/right
/// factories remain available for direct Ratatui fixture translation.
public struct Padding: Hashable, Sendable {
  public var top: UInt16
  public var leading: UInt16
  public var bottom: UInt16
  public var trailing: UInt16

  public init(
    top: UInt16 = 0,
    leading: UInt16 = 0,
    bottom: UInt16 = 0,
    trailing: UInt16 = 0
  ) {
    self.top = top
    self.leading = leading
    self.bottom = bottom
    self.trailing = trailing
  }

  public init(left: UInt16, right: UInt16, top: UInt16, bottom: UInt16) {
    self.init(top: top, leading: left, bottom: bottom, trailing: right)
  }

  public static let zero = Self()

  public static func horizontal(_ value: UInt16) -> Self {
    Self(leading: value, trailing: value)
  }

  public static func vertical(_ value: UInt16) -> Self {
    Self(top: value, bottom: value)
  }

  public static func uniform(_ value: UInt16) -> Self { all(value) }

  public static func all(_ value: UInt16) -> Self {
    Self(top: value, leading: value, bottom: value, trailing: value)
  }

  public static func proportional(_ value: UInt16) -> Self {
    Self(
      top: value,
      leading: UInt16(clamping: Int(value) * 2),
      bottom: value,
      trailing: UInt16(clamping: Int(value) * 2)
    )
  }

  public static func symmetric(horizontal: UInt16, vertical: UInt16) -> Self {
    Self(top: vertical, leading: horizontal, bottom: vertical, trailing: horizontal)
  }

  public static func symmetric(_ x: UInt16, _ y: UInt16) -> Self {
    symmetric(horizontal: x, vertical: y)
  }

  public static func left(_ value: UInt16) -> Self { Self(leading: value) }
  public static func right(_ value: UInt16) -> Self { Self(trailing: value) }
  public static func top(_ value: UInt16) -> Self { Self(top: value) }
  public static func bottom(_ value: UInt16) -> Self { Self(bottom: value) }

  public var insets: Insets {
    Insets(top: top, leading: leading, bottom: bottom, trailing: trailing)
  }
}

public struct BorderSet: Hashable, Sendable {
  public var topLeft: Character
  public var topRight: Character
  public var bottomLeft: Character
  public var bottomRight: Character
  public var verticalLeft: Character
  public var verticalRight: Character
  public var horizontalTop: Character
  public var horizontalBottom: Character

  public var horizontal: Character { horizontalTop }
  public var vertical: Character { verticalLeft }

  public init(
    topLeft: Character,
    topRight: Character,
    bottomLeft: Character,
    bottomRight: Character,
    horizontal: Character,
    vertical: Character
  ) {
    self.init(
      topLeft: topLeft,
      topRight: topRight,
      bottomLeft: bottomLeft,
      bottomRight: bottomRight,
      verticalLeft: vertical,
      verticalRight: vertical,
      horizontalTop: horizontal,
      horizontalBottom: horizontal
    )
  }

  public init(
    topLeft: Character,
    topRight: Character,
    bottomLeft: Character,
    bottomRight: Character,
    verticalLeft: Character,
    verticalRight: Character,
    horizontalTop: Character,
    horizontalBottom: Character
  ) {
    self.topLeft = topLeft
    self.topRight = topRight
    self.bottomLeft = bottomLeft
    self.bottomRight = bottomRight
    self.verticalLeft = verticalLeft
    self.verticalRight = verticalRight
    self.horizontalTop = horizontalTop
    self.horizontalBottom = horizontalBottom
  }

  public static let rounded = Self(
    topLeft: "╭", topRight: "╮", bottomLeft: "╰", bottomRight: "╯",
    horizontal: "─", vertical: "│"
  )
  public static let plain = Self(
    topLeft: "┌", topRight: "┐", bottomLeft: "└", bottomRight: "┘",
    horizontal: "─", vertical: "│"
  )
  public static let single = plain
  public static let double = Self(
    topLeft: "╔", topRight: "╗", bottomLeft: "╚", bottomRight: "╝",
    horizontal: "═", vertical: "║"
  )
  public static let thick = Self(
    topLeft: "┏", topRight: "┓", bottomLeft: "┗", bottomRight: "┛",
    horizontal: "━", vertical: "┃"
  )
  public static let lightDoubleDashed = Self(
    topLeft: "┌", topRight: "┐", bottomLeft: "└", bottomRight: "┘",
    horizontal: "╌", vertical: "╎"
  )
  public static let heavyDoubleDashed = Self(
    topLeft: "┏", topRight: "┓", bottomLeft: "┗", bottomRight: "┛",
    horizontal: "╍", vertical: "╏"
  )
  public static let lightTripleDashed = Self(
    topLeft: "┌", topRight: "┐", bottomLeft: "└", bottomRight: "┘",
    horizontal: "┄", vertical: "┆"
  )
  public static let heavyTripleDashed = Self(
    topLeft: "┏", topRight: "┓", bottomLeft: "┗", bottomRight: "┛",
    horizontal: "┅", vertical: "┇"
  )
  public static let lightQuadrupleDashed = Self(
    topLeft: "┌", topRight: "┐", bottomLeft: "└", bottomRight: "┘",
    horizontal: "┈", vertical: "┊"
  )
  public static let heavyQuadrupleDashed = Self(
    topLeft: "┏", topRight: "┓", bottomLeft: "┗", bottomRight: "┛",
    horizontal: "┉", vertical: "┋"
  )
  public static let quadrantOutside = Self(
    topLeft: "▛", topRight: "▜", bottomLeft: "▙", bottomRight: "▟",
    verticalLeft: "▌", verticalRight: "▐", horizontalTop: "▀", horizontalBottom: "▄"
  )
  public static let quadrantInside = Self(
    topLeft: "▗", topRight: "▖", bottomLeft: "▝", bottomRight: "▘",
    verticalLeft: "▐", verticalRight: "▌", horizontalTop: "▄", horizontalBottom: "▀"
  )
  public static let oneEighthWide = Self(
    topLeft: "▁", topRight: "▁", bottomLeft: "▔", bottomRight: "▔",
    verticalLeft: "▏", verticalRight: "▕", horizontalTop: "▁", horizontalBottom: "▔"
  )
  public static let oneEighthTall = Self(
    topLeft: "▕", topRight: "▏", bottomLeft: "▕", bottomRight: "▏",
    verticalLeft: "▕", verticalRight: "▏", horizontalTop: "▔", horizontalBottom: "▁"
  )
  public static let proportionalWide = Self(
    topLeft: "▄", topRight: "▄", bottomLeft: "▀", bottomRight: "▀",
    verticalLeft: "█", verticalRight: "█", horizontalTop: "▄", horizontalBottom: "▀"
  )
  public static let proportionalTall = Self(
    topLeft: "█", topRight: "█", bottomLeft: "█", bottomRight: "█",
    verticalLeft: "█", verticalRight: "█", horizontalTop: "▀", horizontalBottom: "▄"
  )
  public static let full = Self(
    topLeft: "█", topRight: "█", bottomLeft: "█", bottomRight: "█",
    horizontal: "█", vertical: "█"
  )
  public static let empty = Self(
    topLeft: " ", topRight: " ", bottomLeft: " ", bottomRight: " ",
    horizontal: " ", vertical: " "
  )
}

public enum BlockTitlePosition: Hashable, Sendable {
  case top
  case bottom
}

public struct BlockTitle: Hashable, Sendable, ExpressibleByStringLiteral {
  public var line: Line
  public var position: BlockTitlePosition

  public init(_ line: Line, position: BlockTitlePosition = .top) {
    self.line = line
    self.position = position
  }

  public init(_ content: String, position: BlockTitlePosition = .top) {
    self.init(Line(content), position: position)
  }

  public init(stringLiteral value: String) {
    self.init(value)
  }
}

public struct BlockShadow: Hashable, Sendable {
  public var symbol: Character?
  public var style: Style
  public var offset: Offset

  public init(symbol: Character? = nil, style: Style = .plain, offset: Offset = Offset(x: 1, y: 1))
  {
    self.symbol = symbol
    self.style = style
    self.offset = offset
  }

  public static func overlay(
    style: Style = .plain,
    offset: Offset = Offset(x: 1, y: 1)
  ) -> Self {
    Self(style: style, offset: offset)
  }

  public static func block(
    style: Style = .plain,
    offset: Offset = Offset(x: 1, y: 1)
  ) -> Self {
    Self(symbol: Symbols.Block.full, style: style, offset: offset)
  }

  public static func lightShade(
    style: Style = .plain,
    offset: Offset = Offset(x: 1, y: 1)
  ) -> Self {
    Self(symbol: Symbols.Shade.light, style: style, offset: offset)
  }

  public static func mediumShade(
    style: Style = .plain,
    offset: Offset = Offset(x: 1, y: 1)
  ) -> Self {
    Self(symbol: Symbols.Shade.medium, style: style, offset: offset)
  }

  public static func darkShade(
    style: Style = .plain,
    offset: Offset = Offset(x: 1, y: 1)
  ) -> Self {
    Self(symbol: Symbols.Shade.dark, style: style, offset: offset)
  }
}

public struct Block<Content: Widget>: Widget {
  /// Compatibility title. Advanced blocks can use `titles` for multiple rich titles.
  public var title: String?
  public var titles: [BlockTitle]
  public var borderSet: BorderSet
  public var borderEdges: BorderEdges
  public var style: Style
  public var borderStyle: Style
  public var titleStyle: Style
  public var padding: Padding
  public var shadow: BlockShadow?
  public var borderMerge: BorderMergeStrategy
  public var content: Content

  /// Compatibility spelling retained for the original API.
  public var borders: BorderSet {
    get { borderSet }
    set { borderSet = newValue }
  }

  public init(
    title: String? = nil,
    titles: [BlockTitle] = [],
    borders: BorderSet = .rounded,
    borderEdges: BorderEdges = .all,
    style: Style = .plain,
    borderStyle: Style = .plain,
    titleStyle: Style = .plain,
    padding: Padding = .zero,
    shadow: BlockShadow? = nil,
    borderMerge: BorderMergeStrategy = .replace,
    content: Content
  ) {
    self.title = title
    self.titles = titles
    borderSet = borders
    self.borderEdges = borderEdges
    self.style = style
    self.borderStyle = borderStyle
    self.titleStyle = titleStyle
    self.padding = padding
    self.shadow = shadow
    self.borderMerge = borderMerge
    self.content = content
  }

  public init(
    title: String? = nil,
    titles: [BlockTitle] = [],
    borders: BorderSet = .rounded,
    borderEdges: BorderEdges = .all,
    style: Style = .plain,
    borderStyle: Style = .plain,
    titleStyle: Style = .plain,
    padding: Padding = .zero,
    shadow: BlockShadow? = nil,
    borderMerge: BorderMergeStrategy = .replace,
    @WidgetBuilder content: () -> Content
  ) {
    self.init(
      title: title,
      titles: titles,
      borders: borders,
      borderEdges: borderEdges,
      style: style,
      borderStyle: borderStyle,
      titleStyle: titleStyle,
      padding: padding,
      shadow: shadow,
      borderMerge: borderMerge,
      content: content()
    )
  }

  public func titleTop(_ line: Line) -> Self {
    addingTitle(BlockTitle(line, position: .top))
  }

  public func titleBottom(_ line: Line) -> Self {
    addingTitle(BlockTitle(line, position: .bottom))
  }

  public func addingTitle(_ title: BlockTitle) -> Self {
    var copy = self
    copy.titles.append(title)
    return copy
  }

  public func mergingBorders(_ strategy: BorderMergeStrategy = .exact) -> Self {
    var copy = self
    copy.borderMerge = strategy
    return copy
  }

  public func inner(_ area: Rect) -> Rect {
    let hasTop =
      borderEdges.contains(.top) || title != nil || titles.contains { $0.position == .top }
    let hasBottom = borderEdges.contains(.bottom) || titles.contains { $0.position == .bottom }
    return area.inset(
      by: Insets(
        top: UInt16(clamping: Int(padding.top) + (hasTop ? 1 : 0)),
        leading: UInt16(
          clamping: Int(padding.leading) + (borderEdges.contains(.leading) ? 1 : 0)
        ),
        bottom: UInt16(clamping: Int(padding.bottom) + (hasBottom ? 1 : 0)),
        trailing: UInt16(
          clamping: Int(padding.trailing) + (borderEdges.contains(.trailing) ? 1 : 0)
        )
      )
    )
  }

  public var horizontalSpace: (leading: UInt16, trailing: UInt16) {
    (
      UInt16(clamping: Int(padding.leading) + (borderEdges.contains(.leading) ? 1 : 0)),
      UInt16(clamping: Int(padding.trailing) + (borderEdges.contains(.trailing) ? 1 : 0))
    )
  }

  public var verticalSpace: (top: UInt16, bottom: UInt16) {
    let hasTop =
      borderEdges.contains(.top) || title != nil || titles.contains { $0.position == .top }
    let hasBottom = borderEdges.contains(.bottom) || titles.contains { $0.position == .bottom }
    return (
      UInt16(clamping: Int(padding.top) + (hasTop ? 1 : 0)),
      UInt16(clamping: Int(padding.bottom) + (hasBottom ? 1 : 0))
    )
  }

  public func render(in area: Rect, into frame: inout Frame) {
    guard !area.isEmpty else { return }
    renderShadow(behind: area, into: &frame.buffer)
    if style != .plain {
      frame.buffer.fill(area, with: Cell(symbol: " ", style: style))
    }
    renderBorders(in: area, into: &frame.buffer)
    renderTitles(in: area, into: &frame.buffer)
    frame.render(content, in: inner(area))
  }

  private var resolvedTitles: [BlockTitle] {
    (title.map { [BlockTitle(Line(" \($0) "), position: .top)] } ?? []) + titles
  }

  private func renderShadow(behind area: Rect, into buffer: inout Buffer) {
    guard let shadow else { return }
    let bufferLeft = Int(buffer.area.x)
    let bufferTop = Int(buffer.area.y)
    let bufferRight = bufferLeft + Int(buffer.area.width)
    let bufferBottom = bufferTop + Int(buffer.area.height)
    let shadowLeft = Int(area.x) + shadow.offset.x
    let shadowTop = Int(area.y) + shadow.offset.y

    for y in shadowTop..<(shadowTop + Int(area.height)) {
      guard y >= bufferTop, y < bufferBottom else { continue }
      for x in shadowLeft..<(shadowLeft + Int(area.width)) {
        guard x >= bufferLeft, x < bufferRight else { continue }
        let position = Position(x: UInt16(clamping: x), y: UInt16(clamping: y))
        guard !area.contains(position), var cell = buffer.cell(at: position) else { continue }
        let shadowStyle = cell.style.patching(shadow.style)
        if let symbol = shadow.symbol {
          buffer.setString(String(symbol), at: position, style: shadowStyle)
        } else {
          cell.style = shadowStyle
          buffer.setCell(cell, at: position)
        }
      }
    }
  }

  private func renderBorders(in area: Rect, into buffer: inout Buffer) {
    let right = Int(area.x) + Int(area.width) - 1
    let bottom = Int(area.y) + Int(area.height) - 1
    let drawnStyle = style.patching(borderStyle)

    func draw(_ symbol: Character, at position: Position) {
      buffer.mergeSymbol(symbol, at: position, style: drawnStyle, strategy: borderMerge)
    }

    if borderEdges.contains(.top) {
      let start = Int(area.x) + (borderEdges.contains(.leading) ? 1 : 0)
      let end = right + (borderEdges.contains(.trailing) ? 0 : 1)
      for x in start..<max(start, end) {
        draw(borderSet.horizontalTop, at: Position(x: UInt16(clamping: x), y: area.y))
      }
    }
    if borderEdges.contains(.bottom) {
      let start = Int(area.x) + (borderEdges.contains(.leading) ? 1 : 0)
      let end = right + (borderEdges.contains(.trailing) ? 0 : 1)
      for x in start..<max(start, end) {
        draw(
          borderSet.horizontalBottom,
          at: Position(x: UInt16(clamping: x), y: UInt16(clamping: bottom))
        )
      }
    }
    if borderEdges.contains(.leading) {
      let start = Int(area.y) + (borderEdges.contains(.top) ? 1 : 0)
      let end = bottom + (borderEdges.contains(.bottom) ? 0 : 1)
      for y in start..<max(start, end) {
        draw(borderSet.verticalLeft, at: Position(x: area.x, y: UInt16(clamping: y)))
      }
    }
    if borderEdges.contains(.trailing) {
      let start = Int(area.y) + (borderEdges.contains(.top) ? 1 : 0)
      let end = bottom + (borderEdges.contains(.bottom) ? 0 : 1)
      for y in start..<max(start, end) {
        draw(
          borderSet.verticalRight,
          at: Position(x: UInt16(clamping: right), y: UInt16(clamping: y))
        )
      }
    }

    func corner(_ symbol: Character, x: Int, y: Int) {
      draw(
        symbol,
        at: Position(x: UInt16(clamping: x), y: UInt16(clamping: y))
      )
    }
    if borderEdges.isSuperset(of: [.top, .leading]) {
      corner(borderSet.topLeft, x: Int(area.x), y: Int(area.y))
    }
    if borderEdges.isSuperset(of: [.top, .trailing]) {
      corner(borderSet.topRight, x: right, y: Int(area.y))
    }
    if borderEdges.isSuperset(of: [.bottom, .leading]) {
      corner(borderSet.bottomLeft, x: Int(area.x), y: bottom)
    }
    if borderEdges.isSuperset(of: [.bottom, .trailing]) {
      corner(borderSet.bottomRight, x: right, y: bottom)
    }
  }

  private func renderTitles(in area: Rect, into buffer: inout Buffer) {
    let allTitles = resolvedTitles
    let leftInset = borderEdges.contains(.leading) ? 1 : 0
    let rightInset = borderEdges.contains(.trailing) ? 1 : 0
    let titleArea = Rect(
      x: UInt16(clamping: Int(area.x) + leftInset),
      y: area.y,
      width: UInt16(clamping: Int(area.width) - leftInset - rightInset),
      height: 1
    )
    guard titleArea.width > 0 else { return }

    for position in [BlockTitlePosition.top, .bottom] {
      let y =
        position == .top
        ? Int(area.y)
        : Int(area.y) + Int(area.height) - 1
      for alignment in [Alignment.leading, .center, .trailing] {
        let matching = allTitles.filter {
          $0.position == position && ($0.line.alignment ?? .leading) == alignment
        }
        guard !matching.isEmpty else { continue }
        let styledSpans = matching.enumerated().flatMap { index, title -> [(Span, Style)] in
          let separator: [(Span, Style)] = index == 0 ? [] : [(Span(" "), .plain)]
          return separator + title.line.spans.map { ($0, title.line.style) }
        }
        let width = styledSpans.reduce(0) { $0 + TerminalWidth.of($1.0.content) }
        let offset: Int
        switch alignment {
        case .leading:
          // The original single-title API intentionally leaves one border
          // glyph before its padded title. Rich titles align directly to the
          // title area, matching Ratatui's newer multi-title behavior.
          offset = position == .top && title != nil ? 1 : 0
        case .center: offset = max(0, (Int(titleArea.width) - width) / 2)
        case .trailing: offset = max(0, Int(titleArea.width) - width)
        }
        var cursor = Position(
          x: UInt16(clamping: Int(titleArea.x) + offset),
          y: UInt16(clamping: y)
        )
        let end = Int(titleArea.x) + Int(titleArea.width)
        for (span, lineStyle) in styledSpans where Int(cursor.x) < end {
          cursor = buffer.setString(
            span.content,
            at: cursor,
            style: style.patching(titleStyle).patching(lineStyle).patching(span.style),
            maxWidth: UInt16(clamping: end - Int(cursor.x))
          )
        }
      }
    }
  }
}

extension Block: IntrinsicSizeWidget where Content: IntrinsicSizeWidget {
  public var intrinsicSize: Size {
    let horizontal = horizontalSpace
    let vertical = verticalSpace
    return Size(
      width: UInt16(
        clamping: Int(content.intrinsicSize.width) + Int(horizontal.leading)
          + Int(horizontal.trailing)
      ),
      height: UInt16(
        clamping: Int(content.intrinsicSize.height) + Int(vertical.top) + Int(vertical.bottom)
      )
    )
  }
}
