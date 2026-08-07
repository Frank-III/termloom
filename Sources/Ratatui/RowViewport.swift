/// Pure top-origin row-window geometry for documents, logs, and fixed-height collections.
public struct RowViewport: Hashable, Sendable {
  public var totalRows: Int { didSet { totalRows = max(0, totalRows) } }
  public var viewportRows: Int { didSet { viewportRows = max(0, viewportRows) } }
  public var offset: Int { didSet { offset = max(0, offset) } }

  public init(totalRows: Int, viewportRows: Int, offset: Int = 0) {
    self.totalRows = max(0, totalRows)
    self.viewportRows = max(0, viewportRows)
    self.offset = max(0, offset)
  }

  public var maximumOffset: Int {
    max(0, totalRows - viewportRows)
  }

  public var clampedOffset: Int {
    min(maximumOffset, offset)
  }

  public var visibleRange: Range<Int> {
    guard totalRows > 0, viewportRows > 0 else { return 0..<0 }
    let start = clampedOffset
    return start..<min(totalRows, start + viewportRows)
  }

  public var hasRowsBefore: Bool {
    visibleRange.lowerBound > 0
  }

  public var hasRowsAfter: Bool {
    visibleRange.upperBound < totalRows
  }

  public var progressPercent: Int {
    guard maximumOffset > 0 else { return 100 }
    return Int((Double(clampedOffset) / Double(maximumOffset) * 100).rounded())
  }
}
