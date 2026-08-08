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
/// factories remain available for direct TermLoom fixture translation.
public struct Padding: Hashable, Sendable {
  public var top: Int { didSet { top = max(0, top) } }
  public var leading: Int { didSet { leading = max(0, leading) } }
  public var bottom: Int { didSet { bottom = max(0, bottom) } }
  public var trailing: Int { didSet { trailing = max(0, trailing) } }

  public init(
    top: Int = 0,
    leading: Int = 0,
    bottom: Int = 0,
    trailing: Int = 0
  ) {
    self.top = max(0, top)
    self.leading = max(0, leading)
    self.bottom = max(0, bottom)
    self.trailing = max(0, trailing)
  }

  public init(left: Int, right: Int, top: Int, bottom: Int) {
    self.init(top: top, leading: left, bottom: bottom, trailing: right)
  }

  public static let zero = Self()

  public static func horizontal(_ value: Int) -> Self {
    Self(leading: value, trailing: value)
  }

  public static func vertical(_ value: Int) -> Self {
    Self(top: value, bottom: value)
  }

  public static func uniform(_ value: Int) -> Self { all(value) }

  public static func all(_ value: Int) -> Self {
    Self(top: value, leading: value, bottom: value, trailing: value)
  }

  public static func proportional(_ value: Int) -> Self {
    let value = max(0, value)
    let horizontal = value > Int.max / 2 ? Int.max : value * 2
    return Self(top: value, leading: horizontal, bottom: value, trailing: horizontal)
  }

  public static func symmetric(horizontal: Int, vertical: Int) -> Self {
    Self(top: vertical, leading: horizontal, bottom: vertical, trailing: horizontal)
  }

  public static func symmetric(_ x: Int, _ y: Int) -> Self {
    symmetric(horizontal: x, vertical: y)
  }

  public static func left(_ value: Int) -> Self { Self(leading: value) }
  public static func right(_ value: Int) -> Self { Self(trailing: value) }
  public static func top(_ value: Int) -> Self { Self(top: value) }
  public static func bottom(_ value: Int) -> Self { Self(bottom: value) }

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
        top: paddedSpace(padding.top, decorated: hasTop),
        leading: paddedSpace(padding.leading, decorated: borderEdges.contains(.leading)),
        bottom: paddedSpace(padding.bottom, decorated: hasBottom),
        trailing: paddedSpace(padding.trailing, decorated: borderEdges.contains(.trailing))
      )
    )
  }

  public var horizontalSpace: (leading: Int, trailing: Int) {
    (
      paddedSpace(padding.leading, decorated: borderEdges.contains(.leading)),
      paddedSpace(padding.trailing, decorated: borderEdges.contains(.trailing))
    )
  }

  public var verticalSpace: (top: Int, bottom: Int) {
    let hasTop =
      borderEdges.contains(.top) || title != nil || titles.contains { $0.position == .top }
    let hasBottom = borderEdges.contains(.bottom) || titles.contains { $0.position == .bottom }
    return (
      paddedSpace(padding.top, decorated: hasTop),
      paddedSpace(padding.bottom, decorated: hasBottom)
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
    let bufferLeft = buffer.area.x
    let bufferTop = buffer.area.y
    let bufferRight = bufferLeft + buffer.area.width
    let bufferBottom = bufferTop + buffer.area.height
    let shadowLeft = area.x + shadow.offset.x
    let shadowTop = area.y + shadow.offset.y

    for y in shadowTop..<(shadowTop + area.height) {
      guard y >= bufferTop, y < bufferBottom else { continue }
      for x in shadowLeft..<(shadowLeft + area.width) {
        guard x >= bufferLeft, x < bufferRight else { continue }
        let position = Position(x: x, y: y)
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
    let right = area.x + area.width - 1
    let bottom = area.y + area.height - 1
    let drawnStyle = style.patching(borderStyle)

    func draw(_ symbol: Character, at position: Position) {
      buffer.mergeSymbol(symbol, at: position, style: drawnStyle, strategy: borderMerge)
    }

    if borderEdges.contains(.top) {
      let start = area.x + (borderEdges.contains(.leading) ? 1 : 0)
      let end = right + (borderEdges.contains(.trailing) ? 0 : 1)
      for x in start..<max(start, end) {
        draw(borderSet.horizontalTop, at: Position(x: x, y: area.y))
      }
    }
    if borderEdges.contains(.bottom) {
      let start = area.x + (borderEdges.contains(.leading) ? 1 : 0)
      let end = right + (borderEdges.contains(.trailing) ? 0 : 1)
      for x in start..<max(start, end) {
        draw(
          borderSet.horizontalBottom,
          at: Position(x: x, y: bottom)
        )
      }
    }
    if borderEdges.contains(.leading) {
      let start = area.y + (borderEdges.contains(.top) ? 1 : 0)
      let end = bottom + (borderEdges.contains(.bottom) ? 0 : 1)
      for y in start..<max(start, end) {
        draw(borderSet.verticalLeft, at: Position(x: area.x, y: y))
      }
    }
    if borderEdges.contains(.trailing) {
      let start = area.y + (borderEdges.contains(.top) ? 1 : 0)
      let end = bottom + (borderEdges.contains(.bottom) ? 0 : 1)
      for y in start..<max(start, end) {
        draw(
          borderSet.verticalRight,
          at: Position(x: right, y: y)
        )
      }
    }

    func corner(_ symbol: Character, x: Int, y: Int) {
      draw(
        symbol,
        at: Position(x: x, y: y)
      )
    }
    if borderEdges.isSuperset(of: [.top, .leading]) {
      corner(borderSet.topLeft, x: area.x, y: area.y)
    }
    if borderEdges.isSuperset(of: [.top, .trailing]) {
      corner(borderSet.topRight, x: right, y: area.y)
    }
    if borderEdges.isSuperset(of: [.bottom, .leading]) {
      corner(borderSet.bottomLeft, x: area.x, y: bottom)
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
      x: (area.x + leftInset),
      y: area.y,
      width: (area.width - leftInset - rightInset),
      height: 1
    )
    guard titleArea.width > 0 else { return }

    for position in [BlockTitlePosition.top, .bottom] {
      let y =
        position == .top
        ? area.y
        : area.y + area.height - 1
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
          // title area, matching TermLoom's newer multi-title behavior.
          offset = position == .top && title != nil ? 1 : 0
        case .center: offset = max(0, (titleArea.width - width) / 2)
        case .trailing: offset = max(0, titleArea.width - width)
        }
        var cursor = Position(
          x: (titleArea.x + offset),
          y: y
        )
        let end = titleArea.x + titleArea.width
        for (span, lineStyle) in styledSpans where cursor.x < end {
          cursor = buffer.setString(
            span.content,
            at: cursor,
            style: style.patching(titleStyle).patching(lineStyle).patching(span.style),
            maxWidth: (end - cursor.x)
          )
        }
      }
    }
  }
}

extension Block where Content == EmptyWidget {
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
    borderMerge: BorderMergeStrategy = .replace
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
      content: EmptyWidget()
    )
  }
}

extension Block: IntrinsicSizeWidget where Content: IntrinsicSizeWidget {
  public var intrinsicSize: Size {
    let horizontal = horizontalSpace
    let vertical = verticalSpace
    return Size(
      width: (content.intrinsicSize.width + horizontal.leading
        + horizontal.trailing),
      height: (content.intrinsicSize.height + vertical.top + vertical.bottom)
    )
  }
}

private func paddedSpace(_ padding: Int, decorated: Bool) -> Int {
  let padding = max(0, padding)
  guard decorated else { return padding }
  return padding == Int.max ? Int.max : padding + 1
}
