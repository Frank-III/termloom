import Foundation
import Testing

@testable import Ratatui

@Suite struct SelectionViewportTests {
  @Test func variableHeightSelectionAlwaysRemainsVisible() {
    let heights = [2, 4, 1, 3, 2]

    let nearTop = SelectionViewport.fitting(
      itemHeights: heights, selectedIndex: 1, capacity: 7)
    #expect(nearTop.range == 0..<3)
    #expect(!nearTop.hasItemsBefore)
    #expect(nearTop.hasItemsAfter)

    let nearBottom = SelectionViewport.fitting(
      itemHeights: heights, selectedIndex: 4, capacity: 6)
    #expect(nearBottom.range == 2..<5)
    #expect(nearBottom.hasItemsBefore)
    #expect(!nearBottom.hasItemsAfter)
    #expect(nearBottom.range.contains(4))
  }

  @Test func smallDomainExhaustivelyKeepsClampedSelectionRepresented() {
    for count in 0...5 {
      let combinations = Int(pow(5.0, Double(count)))
      for encoded in 0..<combinations {
        var value = encoded
        let heights = (0..<count).map { _ in
          defer { value /= 5 }
          return value % 5
        }
        for selected in -1...(count + 1) {
          for capacity in 0...8 {
            let viewport = SelectionViewport.fitting(
              itemHeights: heights, selectedIndex: selected, capacity: capacity)
            #expect(viewport.range.lowerBound >= 0)
            #expect(viewport.range.upperBound <= count)
            #expect(viewport.hasItemsBefore == (viewport.range.lowerBound > 0))
            #expect(viewport.hasItemsAfter == (viewport.range.upperBound < count))
            if count > 0, capacity > 0 {
              let clamped = min(max(0, selected), count - 1)
              #expect(viewport.range.contains(clamped))
              let used = viewport.range.reduce(0) { $0 + max(1, heights[$1]) }
              #expect(used <= capacity || max(1, heights[clamped]) > capacity)
            } else {
              #expect(viewport.range.isEmpty)
            }
          }
        }
      }
    }
  }

  @Test func oversizedSelectionStillGetsItsOwnWindow() {
    let viewport = SelectionViewport.fitting(
      itemHeights: [1, 12, 1], selectedIndex: 1, capacity: 5)

    #expect(viewport.range == 1..<2)
    #expect(viewport.hasItemsBefore)
    #expect(viewport.hasItemsAfter)
  }
}
