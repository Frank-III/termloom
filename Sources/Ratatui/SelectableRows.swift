/// Application-owned interaction metadata for a visible selectable row.
public struct RowInteraction: Hashable, Sendable {
  public var control: ControlID
  public var action: ActionID?
  public var isFocusable: Bool

  public init(
    control: ControlID,
    action: ActionID? = nil,
    isFocusable: Bool = false
  ) {
    self.control = control
    self.action = action
    self.isFocusable = isFocusable
  }
}

/// The same-pass geometry supplied to a visible row renderer.
public struct SelectableRow: Hashable, Sendable {
  public var index: Int
  public var area: Rect
  public var isSelected: Bool

  public init(index: Int, area: Rect, isSelected: Bool) {
    self.index = index
    self.area = area
    self.isSelected = isSelected
  }
}

/// A fixed-height, visible-only selectable row projection.
///
/// The application retains row identity, selection, navigation, filtering, and action semantics.
/// This widget only projects visible indices, establishes exact row rectangles, paints an optional
/// selection background, and attaches optional interaction metadata during the same render pass.
public struct SelectableRows: Widget {
  public var itemCount: Int
  public var selectedIndex: Int?
  public var rowHeight: Int
  public var placement: SelectionPlacement
  public var selectedFillStyle: Style?

  private let interaction: (Int) -> RowInteraction?
  private let row: (SelectableRow, inout Frame) -> Void

  public init(
    itemCount: Int,
    selectedIndex: Int? = nil,
    rowHeight: Int = 1,
    placement: SelectionPlacement = .center,
    selectedFillStyle: Style? = nil,
    interaction: @escaping (Int) -> RowInteraction? = { _ in nil },
    row: @escaping (SelectableRow, inout Frame) -> Void
  ) {
    self.itemCount = max(0, itemCount)
    self.selectedIndex = selectedIndex
    self.rowHeight = max(1, rowHeight)
    self.placement = placement
    self.selectedFillStyle = selectedFillStyle
    self.interaction = interaction
    self.row = row
  }

  private var projectedSelectedIndex: Int? {
    guard let selectedIndex, itemCount > 0 else { return nil }
    return min(max(0, selectedIndex), itemCount - 1)
  }

  public func viewport(in area: Rect) -> SelectionViewport {
    SelectionViewport.fixed(
      itemCount: itemCount,
      selectedIndex: projectedSelectedIndex,
      capacity: area.height / rowHeight,
      placement: placement
    )
  }

  public func render(in area: Rect, into frame: inout Frame) {
    guard !area.isEmpty else { return }
    let viewport = viewport(in: area)
    for (visibleIndex, itemIndex) in viewport.range.enumerated() {
      let rowArea = Rect(
        x: area.x,
        y: area.y + visibleIndex * rowHeight,
        width: area.width,
        height: rowHeight
      )
      let isSelected = itemIndex == projectedSelectedIndex
      if isSelected, let selectedFillStyle {
        frame.buffer.fill(rowArea, with: Cell(symbol: " ", style: selectedFillStyle))
      }
      if let interaction = interaction(itemIndex) {
        frame.addInteraction(
          InteractionRegion(
            control: interaction.control,
            area: rowArea,
            action: interaction.action,
            isFocusable: interaction.isFocusable
          )
        )
      }
      row(
        SelectableRow(index: itemIndex, area: rowArea, isSelected: isSelected),
        &frame
      )
    }
  }
}
