import Ratatui

public enum PopupDimension: Hashable, Sendable {
  case cells(UInt16)
  case percentage(UInt16)
  case fill

  func resolve(available: UInt16) -> UInt16 {
    switch self {
    case .cells(let cells): min(cells, available)
    case .percentage(let percent):
      UInt16(clamping: Int(available) * min(100, Int(percent)) / 100)
    case .fill: available
    }
  }
}

public struct PopupSize: Hashable, Sendable {
  public var width: PopupDimension
  public var height: PopupDimension

  public init(width: PopupDimension, height: PopupDimension) {
    self.width = width
    self.height = height
  }

  public static func cells(width: UInt16, height: UInt16) -> Self {
    Self(width: .cells(width), height: .cells(height))
  }

  public static func percentage(width: UInt16, height: UInt16) -> Self {
    Self(width: .percentage(width), height: .percentage(height))
  }
}

public enum PopupPlacement: Hashable, Sendable {
  case center
  case top
  case bottom
  case leading
  case trailing
  case topLeading
  case topTrailing
  case bottomLeading
  case bottomTrailing
}

public struct PopupLayout: Hashable, Sendable {
  public var size: PopupSize
  public var placement: PopupPlacement
  public var margins: Insets

  public init(
    size: PopupSize,
    placement: PopupPlacement = .center,
    margins: Insets = .all(1)
  ) {
    self.size = size
    self.placement = placement
    self.margins = margins
  }

  public func resolve(in area: Rect) -> Rect {
    let available = area.inset(by: margins)
    guard !available.isEmpty else { return available }
    let width = max(1, size.width.resolve(available: available.width))
    let height = max(1, size.height.resolve(available: available.height))
    let centeredX = Int(available.x) + (Int(available.width) - Int(width)) / 2
    let centeredY = Int(available.y) + (Int(available.height) - Int(height)) / 2
    let trailingX = Int(available.right) - Int(width)
    let bottomY = Int(available.bottom) - Int(height)
    let point: (x: Int, y: Int) =
      switch placement {
      case .center: (centeredX, centeredY)
      case .top: (centeredX, Int(available.y))
      case .bottom: (centeredX, bottomY)
      case .leading: (Int(available.x), centeredY)
      case .trailing: (trailingX, centeredY)
      case .topLeading: (Int(available.x), Int(available.y))
      case .topTrailing: (trailingX, Int(available.y))
      case .bottomLeading: (Int(available.x), bottomY)
      case .bottomTrailing: (trailingX, bottomY)
      }
    return Rect(
      x: UInt16(clamping: point.x),
      y: UInt16(clamping: point.y),
      width: width,
      height: height)
  }
}

public struct Popup<Content: Widget>: Widget {
  public var layout: PopupLayout
  public var title: String?
  public var style: Style
  public var borderStyle: Style
  public var titleStyle: Style
  public var padding: Padding
  public var scrimStyle: Style?
  public var content: Content

  public init(
    layout: PopupLayout,
    title: String? = nil,
    style: Style = .plain,
    borderStyle: Style = .plain,
    titleStyle: Style = .plain,
    padding: Padding = .zero,
    scrimStyle: Style? = nil,
    content: Content
  ) {
    self.layout = layout
    self.title = title
    self.style = style
    self.borderStyle = borderStyle
    self.titleStyle = titleStyle
    self.padding = padding
    self.scrimStyle = scrimStyle
    self.content = content
  }

  public init(
    layout: PopupLayout,
    title: String? = nil,
    style: Style = .plain,
    borderStyle: Style = .plain,
    titleStyle: Style = .plain,
    padding: Padding = .zero,
    scrimStyle: Style? = nil,
    @WidgetBuilder content: () -> Content
  ) {
    self.init(
      layout: layout,
      title: title,
      style: style,
      borderStyle: borderStyle,
      titleStyle: titleStyle,
      padding: padding,
      scrimStyle: scrimStyle,
      content: content())
  }

  public func render(in area: Rect, into frame: inout Frame) {
    if let scrimStyle {
      frame.buffer.fill(area, with: Cell(symbol: " ", style: scrimStyle))
    }
    let popupArea = layout.resolve(in: area)
    guard !popupArea.isEmpty else { return }
    frame.buffer.fill(popupArea, with: Cell(symbol: " ", style: style))
    frame.render(block, in: popupArea)
  }

  private var block: Block<Content> {
    Block(
      title: title,
      style: style,
      borderStyle: borderStyle,
      titleStyle: titleStyle,
      padding: padding,
      content: content)
  }
}
