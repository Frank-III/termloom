/// Pure row-window geometry for large pre-rendered documents and logs.
///
/// `offsetFromEnd == 0` follows the newest rows. Increasing it moves toward the document start without
/// requiring callers to slice, copy, or render off-screen rows.
public struct ScrollViewport: Hashable, Sendable {
  public var totalRows: Int { didSet { totalRows = max(0, totalRows) } }
  public var viewportRows: Int { didSet { viewportRows = max(0, viewportRows) } }
  public var offsetFromEnd: Int { didSet { offsetFromEnd = max(0, offsetFromEnd) } }

  public init(totalRows: Int, viewportRows: Int, offsetFromEnd: Int = 0) {
    self.totalRows = max(0, totalRows)
    self.viewportRows = max(0, viewportRows)
    self.offsetFromEnd = max(0, offsetFromEnd)
  }

  public var maximumOffset: Int {
    max(0, totalRows - viewportRows)
  }

  public var clampedOffsetFromEnd: Int {
    min(maximumOffset, offsetFromEnd)
  }

  public var rowViewport: RowViewport {
    RowViewport(
      totalRows: totalRows,
      viewportRows: viewportRows,
      offset: maximumOffset - clampedOffsetFromEnd
    )
  }

  public var visibleRange: Range<Int> {
    rowViewport.visibleRange
  }

  public var progressPercent: Int {
    rowViewport.progressPercent
  }
}
