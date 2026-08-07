#if Overlays
  import Ratatui
  import RatatuiOverlays

  public struct DevToolsOverlay: Widget, Hashable, Sendable {
    public var state: DevToolsState
    public var layout: PopupLayout

    public init(
      _ state: DevToolsState,
      layout: PopupLayout = PopupLayout(
        size: .percentage(width: 72, height: 62),
        placement: .bottomTrailing)
    ) {
      self.state = state
      self.layout = layout
    }

    public func render(in area: Rect, into frame: inout Frame) {
      frame.render(popup, in: area)
    }

    private var popup: Popup<DevToolsPanel> {
      Popup(
        layout: layout,
        style: Style(foreground: .white, background: .black),
        borderStyle: Style(foreground: .cyan),
        padding: .zero,
        content: DevToolsPanel(state))
    }
  }
#endif
