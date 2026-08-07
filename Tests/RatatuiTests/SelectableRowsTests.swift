import Testing

@testable import Ratatui

@Suite struct SelectableRowsTests {
  @Test func fixedProjectionPlacesSelectionAndClampsBoundaries() {
    #expect(
      SelectionViewport.fixed(
        itemCount: 10, selectedIndex: 5, capacity: 4, placement: .leading
      ).range == 5..<9
    )
    #expect(
      SelectionViewport.fixed(
        itemCount: 10, selectedIndex: 5, capacity: 4, placement: .center
      ).range == 3..<7
    )
    #expect(
      SelectionViewport.fixed(
        itemCount: 10, selectedIndex: 5, capacity: 4, placement: .trailing
      ).range == 2..<6
    )
    let clampedEnd = SelectionViewport.fixed(
      itemCount: 10, selectedIndex: 100, capacity: 4, placement: .leading
    )
    #expect(clampedEnd.range == 6..<10)
    #expect(clampedEnd.hasItemsBefore)
    #expect(!clampedEnd.hasItemsAfter)
    #expect(
      SelectionViewport.fixed(
        itemCount: -1, selectedIndex: -1, capacity: -1
      ).range.isEmpty
    )
  }

  @Test func selectableRowsEvaluateOnlyVisibleRowsAndUseExactSamePassGeometry() {
    var rendered: [SelectableRow] = []
    var requestedInteractions: [Int] = []
    let rows = SelectableRows(
      itemCount: 100,
      selectedIndex: 50,
      rowHeight: 2,
      placement: .center,
      selectedFillStyle: Style(background: .blue),
      interaction: { index in
        requestedInteractions.append(index)
        return RowInteraction(
          control: ControlID("row-\(index)"),
          action: ActionID("select:\(index)")
        )
      },
      row: { visibleRow, frame in
        rendered.append(visibleRow)
        frame.buffer.setString(
          "row \(visibleRow.index)",
          at: Position(x: visibleRow.area.x, y: visibleRow.area.y)
        )
      }
    )
    var frame = Frame(buffer: Buffer(area: Rect(x: 4, y: 3, width: 12, height: 5)))

    rows.render(in: frame.area, into: &frame)

    #expect(rendered.map(\.index) == [49, 50])
    #expect(requestedInteractions == [49, 50])
    #expect(
      rendered.map(\.area) == [
        Rect(x: 4, y: 3, width: 12, height: 2),
        Rect(x: 4, y: 5, width: 12, height: 2),
      ]
    )
    #expect(rendered.map(\.isSelected) == [false, true])
    #expect(frame.interactions.regions.map(\.area) == rendered.map(\.area))
    #expect(frame.interactions.regions.map(\.isFocusable) == [false, false])
    #expect(frame.buffer.cell(at: Position(x: 15, y: 5))?.style.background == .blue)
  }

  @Test func clampedSelectionDoesNotMutateApplicationInputAndEmptyInputsDoNothing() {
    var rendered: [SelectableRow] = []
    let rows = SelectableRows(
      itemCount: 3,
      selectedIndex: -100,
      row: { row, _ in rendered.append(row) }
    )
    var frame = Frame(buffer: Buffer(area: Rect(x: 0, y: 0, width: 4, height: 3)))

    rows.render(in: frame.area, into: &frame)

    #expect(rows.selectedIndex == -100)
    #expect(rendered.first?.index == 0)
    #expect(rendered.first?.isSelected == true)

    rendered.removeAll()
    SelectableRows(itemCount: 10, row: { row, _ in rendered.append(row) })
      .render(in: .zero, into: &frame)
    #expect(rendered.isEmpty)
  }
}
