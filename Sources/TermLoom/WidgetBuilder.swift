public struct AnyWidget: Widget {
  private let renderBody: (Rect, inout Frame) -> Void

  public init<W: Widget>(_ widget: W) {
    renderBody = widget.render
  }

  public func render(in area: Rect, into frame: inout Frame) {
    renderBody(area, &frame)
  }
}

public struct WidgetList: Widget {
  public var widgets: [AnyWidget]

  public init(_ widgets: [AnyWidget] = []) {
    self.widgets = widgets
  }

  public func render(in area: Rect, into frame: inout Frame) {
    for widget in widgets {
      frame.render(widget, in: area)
    }
  }
}

@resultBuilder
public enum WidgetBuilder {
  public static func buildExpression<W: Widget>(_ expression: W) -> WidgetList {
    WidgetList([AnyWidget(expression)])
  }

  public static func buildBlock(_ components: WidgetList...) -> WidgetList {
    WidgetList(components.flatMap(\.widgets))
  }

  public static func buildOptional(_ component: WidgetList?) -> WidgetList {
    component ?? WidgetList()
  }

  public static func buildEither(first component: WidgetList) -> WidgetList {
    component
  }

  public static func buildEither(second component: WidgetList) -> WidgetList {
    component
  }

  public static func buildArray(_ components: [WidgetList]) -> WidgetList {
    WidgetList(components.flatMap(\.widgets))
  }

  public static func buildLimitedAvailability(_ component: WidgetList) -> WidgetList {
    component
  }
}
