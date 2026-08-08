public struct StackItem {
  public var widget: AnyWidget
  public var constraint: Constraint

  public init<W: Widget>(_ widget: W, constraint: Constraint = .fill) {
    self.widget = AnyWidget(widget)
    self.constraint = constraint
  }
}

extension Widget {
  public func frame(_ constraint: Constraint) -> StackItem {
    StackItem(self, constraint: constraint)
  }
}

@resultBuilder
public enum StackBuilder {
  public static func buildExpression<W: Widget>(_ expression: W) -> [StackItem] {
    [StackItem(expression)]
  }

  public static func buildExpression(_ expression: StackItem) -> [StackItem] {
    [expression]
  }

  public static func buildBlock(_ components: [StackItem]...) -> [StackItem] {
    components.flatMap { $0 }
  }

  public static func buildOptional(_ component: [StackItem]?) -> [StackItem] {
    component ?? []
  }

  public static func buildEither(first component: [StackItem]) -> [StackItem] {
    component
  }

  public static func buildEither(second component: [StackItem]) -> [StackItem] {
    component
  }

  public static func buildArray(_ components: [[StackItem]]) -> [StackItem] {
    components.flatMap { $0 }
  }
}

public struct Stack: Widget {
  public var axis: Axis
  public var spacing: Int { didSet { spacing = max(0, spacing) } }
  public var items: [StackItem]

  public init(
    _ axis: Axis,
    spacing: Int = 0,
    @StackBuilder content: () -> [StackItem]
  ) {
    self.axis = axis
    self.spacing = max(0, spacing)
    items = content()
  }

  private func itemAreas(in area: Rect) -> [Rect] {
    Layout(
      axis,
      constraints: items.map(\.constraint),
      spacing: .space(spacing)
    ).split(area)
  }

  public func render(in area: Rect, into frame: inout Frame) {
    let areas = itemAreas(in: area)
    for (item, itemArea) in zip(items, areas) {
      frame.render(item.widget, in: itemArea)
    }
  }
}

public struct VStack: Widget {
  private var stack: Stack

  public init(spacing: Int = 0, @StackBuilder content: () -> [StackItem]) {
    stack = Stack(.vertical, spacing: spacing, content: content)
  }

  public func render(in area: Rect, into frame: inout Frame) {
    frame.render(stack, in: area)
  }
}

public struct HStack: Widget {
  private var stack: Stack

  public init(spacing: Int = 0, @StackBuilder content: () -> [StackItem]) {
    stack = Stack(.horizontal, spacing: spacing, content: content)
  }

  public func render(in area: Rect, into frame: inout Frame) {
    frame.render(stack, in: area)
  }
}
