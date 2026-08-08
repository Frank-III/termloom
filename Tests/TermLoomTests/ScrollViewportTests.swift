import TermLoom
import Testing

@Suite struct ScrollViewportTests {
  @Test func followsEndAndClampsEveryBoundary() {
    #expect(ScrollViewport(totalRows: 100, viewportRows: 20).visibleRange == 80..<100)
    #expect(
      ScrollViewport(totalRows: 100, viewportRows: 20, offsetFromEnd: 7).visibleRange == 73..<93)
    #expect(
      ScrollViewport(totalRows: 100, viewportRows: 20, offsetFromEnd: .max).visibleRange == 0..<20)
    #expect(ScrollViewport(totalRows: 3, viewportRows: 20).visibleRange == 0..<3)
    #expect(ScrollViewport(totalRows: 3, viewportRows: 0).visibleRange.isEmpty)
    #expect(ScrollViewport(totalRows: -1, viewportRows: -1).visibleRange.isEmpty)
  }

  @Test func smallDomainNeverEscapesRowsOrViewport() {
    for total in 0...20 {
      for height in 0...20 {
        for offset in 0...25 {
          let viewport = ScrollViewport(
            totalRows: total, viewportRows: height, offsetFromEnd: offset)
          #expect(viewport.visibleRange.lowerBound >= 0)
          #expect(viewport.visibleRange.upperBound <= total)
          #expect(viewport.visibleRange.count <= height)
          #expect((0...100).contains(viewport.progressPercent))
        }
      }
    }
  }
}
