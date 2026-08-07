import Testing

@testable import Ratatui

@Suite struct RowViewportTests {
  @Test func topOriginOffsetsClampAndExposeBoundaries() {
    let top = RowViewport(totalRows: 100, viewportRows: 20, offset: 0)
    #expect(top.visibleRange == 0..<20)
    #expect(!top.hasRowsBefore)
    #expect(top.hasRowsAfter)
    #expect(top.progressPercent == 0)

    let middle = RowViewport(totalRows: 100, viewportRows: 20, offset: 37)
    #expect(middle.visibleRange == 37..<57)
    #expect(middle.hasRowsBefore)
    #expect(middle.hasRowsAfter)

    let bottom = RowViewport(totalRows: 100, viewportRows: 20, offset: .max)
    #expect(bottom.clampedOffset == 80)
    #expect(bottom.visibleRange == 80..<100)
    #expect(bottom.hasRowsBefore)
    #expect(!bottom.hasRowsAfter)
    #expect(bottom.progressPercent == 100)
  }

  @Test func invalidAndOversizedInputsNormalizeSafely() {
    #expect(RowViewport(totalRows: -1, viewportRows: -1, offset: -1).visibleRange.isEmpty)
    #expect(RowViewport(totalRows: 3, viewportRows: 20, offset: 9).visibleRange == 0..<3)
    #expect(RowViewport(totalRows: 3, viewportRows: 0, offset: 2).visibleRange.isEmpty)

    var mutated = RowViewport(totalRows: 3, viewportRows: 2, offset: 1)
    mutated.totalRows = -1
    mutated.viewportRows = -1
    mutated.offset = -1
    #expect(mutated == RowViewport(totalRows: 0, viewportRows: 0, offset: 0))
  }

  @Test func smallDomainAlwaysReturnsAValidWindow() {
    for total in -2...20 {
      for height in -2...20 {
        for offset in [-1, 0, 1, 5, 20, Int.max] {
          let viewport = RowViewport(totalRows: total, viewportRows: height, offset: offset)
          #expect(viewport.visibleRange.lowerBound >= 0)
          #expect(viewport.visibleRange.upperBound <= max(0, total))
          #expect(viewport.visibleRange.count <= max(0, height))
          #expect(viewport.clampedOffset <= viewport.maximumOffset)
          #expect(viewport.hasRowsBefore == (viewport.visibleRange.lowerBound > 0))
          #expect(viewport.hasRowsAfter == (viewport.visibleRange.upperBound < max(0, total)))
        }
      }
    }
  }

  @Test func endOriginViewportRetainsItsEstablishedProjection() {
    let scroll = ScrollViewport(totalRows: 100, viewportRows: 20, offsetFromEnd: 7)
    #expect(scroll.rowViewport == RowViewport(totalRows: 100, viewportRows: 20, offset: 73))
    #expect(scroll.visibleRange == 73..<93)
  }
}
