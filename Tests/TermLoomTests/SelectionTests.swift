import Testing

@testable import TermLoom

@Suite struct SelectionTests {
  @Test func selectionClampsMovesAndReconcilesEmptyLists() {
    var state = SelectionState(selectedIndex: 2)

    var changed = state.move(by: 1, itemCount: 3)
    #expect(changed == false)
    #expect(state.selectedIndex == 2)
    changed = state.move(by: -2, itemCount: 3)
    #expect(changed)
    #expect(state.selectedIndex == 0)
    changed = state.select(20, itemCount: 3)
    #expect(changed)
    #expect(state.selectedIndex == 2)
    changed = state.reconcile(itemCount: 0)
    #expect(changed)
    #expect(state.selectedIndex == nil)
  }

  @Test func visibleRangeFollowsSelectionAndClampsAtTheEnd() {
    var state = SelectionState(selectedIndex: 0)
    #expect(state.visibleRange(itemCount: 10, viewportCount: 4) == 0..<4)

    _ = state.select(5, itemCount: 10)
    #expect(state.visibleRange(itemCount: 10, viewportCount: 4) == 2..<6)

    _ = state.select(9, itemCount: 10)
    #expect(state.visibleRange(itemCount: 10, viewportCount: 4) == 6..<10)
  }
}
