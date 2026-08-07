/// A pure, value-semantic visible window for variable-height selectable content.
///
/// Applications own selection identity and navigation. This type only determines which contiguous
/// items fit while guaranteeing that the selected item remains represented in the viewport.
public struct SelectionViewport: Hashable, Sendable {
  public var range: Range<Int>
  public var hasItemsBefore: Bool
  public var hasItemsAfter: Bool

  public init(range: Range<Int>, hasItemsBefore: Bool, hasItemsAfter: Bool) {
    self.range = range
    self.hasItemsBefore = hasItemsBefore
    self.hasItemsAfter = hasItemsAfter
  }

  public static func fitting(
    itemHeights: [Int], selectedIndex: Int, capacity: Int
  ) -> SelectionViewport {
    guard !itemHeights.isEmpty, capacity > 0 else {
      return SelectionViewport(
        range: 0..<0, hasItemsBefore: false, hasItemsAfter: !itemHeights.isEmpty)
    }

    let selected = min(max(0, selectedIndex), itemHeights.count - 1)
    var start = selected
    var end = selected + 1
    var used = min(max(1, itemHeights[selected]), capacity)

    while start > 0 {
      let height = max(1, itemHeights[start - 1])
      guard used + height <= capacity else { break }
      start -= 1
      used += height
    }
    while end < itemHeights.count {
      let height = max(1, itemHeights[end])
      guard used + height <= capacity else { break }
      end += 1
      used += height
    }

    return SelectionViewport(
      range: start..<end,
      hasItemsBefore: start > 0,
      hasItemsAfter: end < itemHeights.count
    )
  }
}
