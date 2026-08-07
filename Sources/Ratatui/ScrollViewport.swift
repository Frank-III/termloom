/// Pure row-window geometry for large pre-rendered documents and logs.
///
/// `offsetFromEnd == 0` follows the newest rows. Increasing it moves toward the document start without
/// requiring callers to slice, copy, or render off-screen rows.
public struct ScrollViewport: Hashable, Sendable {
  public var totalRows: Int
  public var viewportRows: Int
  public var offsetFromEnd: Int

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

  public var visibleRange: Range<Int> {
    guard totalRows > 0, viewportRows > 0 else { return 0..<0 }
    let start = maximumOffset - clampedOffsetFromEnd
    return start..<min(totalRows, start + viewportRows)
  }

  public var progressPercent: Int {
    guard maximumOffset > 0 else { return 100 }
    let topOffset = maximumOffset - clampedOffsetFromEnd
    return Int((Double(topOffset) / Double(maximumOffset) * 100).rounded())
  }
}
