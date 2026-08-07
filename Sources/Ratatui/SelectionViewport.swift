/// Places a selected item toward the leading edge, center, or trailing edge of its projection axis.
public enum SelectionPlacement: Hashable, Sendable {
  case leading
  case center
  case trailing
}

/// A pure, value-semantic visible window for selectable content.
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

  /// Projects fixed-height rows without materializing row content.
  public static func fixed(
    itemCount: Int,
    selectedIndex: Int?,
    capacity: Int,
    placement: SelectionPlacement = .center
  ) -> SelectionViewport {
    let itemCount = max(0, itemCount)
    let capacity = max(0, capacity)
    guard itemCount > 0, capacity > 0 else {
      return SelectionViewport(
        range: 0..<0,
        hasItemsBefore: false,
        hasItemsAfter: itemCount > 0
      )
    }

    let visibleCount = min(itemCount, capacity)
    let maximumStart = itemCount - visibleCount
    let start: Int
    if let selectedIndex {
      let selected = min(max(0, selectedIndex), itemCount - 1)
      let proposedStart =
        switch placement {
        case .leading: selected
        case .center: selected - visibleCount / 2
        case .trailing: selected - visibleCount + 1
        }
      start = min(max(0, proposedStart), maximumStart)
    } else {
      start = 0
    }
    let end = start + visibleCount
    return SelectionViewport(
      range: start..<end,
      hasItemsBefore: start > 0,
      hasItemsAfter: end < itemCount
    )
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
