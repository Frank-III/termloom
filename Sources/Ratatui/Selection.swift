/// Reusable keyboard-selection state for menus, pickers, and modal lists.
public struct SelectionState: Hashable, Sendable {
  public private(set) var selectedIndex: Int?
  public private(set) var scrollOffset: Int

  public init(selectedIndex: Int? = 0, scrollOffset: Int = 0) {
    self.selectedIndex = selectedIndex
    self.scrollOffset = max(0, scrollOffset)
  }

  @discardableResult
  public mutating func reconcile(itemCount: Int) -> Bool {
    let previous = self
    guard itemCount > 0 else {
      selectedIndex = nil
      scrollOffset = 0
      return self != previous
    }
    selectedIndex = min(max(0, selectedIndex ?? 0), itemCount - 1)
    scrollOffset = min(scrollOffset, itemCount - 1)
    return self != previous
  }

  @discardableResult
  public mutating func select(_ index: Int, itemCount: Int) -> Bool {
    let previous = selectedIndex
    guard itemCount > 0 else {
      selectedIndex = nil
      scrollOffset = 0
      return previous != nil
    }
    selectedIndex = min(max(0, index), itemCount - 1)
    return selectedIndex != previous
  }

  @discardableResult
  public mutating func move(by distance: Int, itemCount: Int, wraps: Bool = false) -> Bool {
    guard itemCount > 0 else { return reconcile(itemCount: itemCount) }
    let current = min(max(0, selectedIndex ?? 0), itemCount - 1)
    let next =
      if wraps {
        (current + distance % itemCount + itemCount) % itemCount
      } else {
        min(max(0, current + distance), itemCount - 1)
      }
    return select(next, itemCount: itemCount)
  }

  /// Keeps the selected row inside a viewport and returns its source range.
  public mutating func visibleRange(itemCount: Int, viewportCount: Int) -> Range<Int> {
    guard itemCount > 0, viewportCount > 0 else {
      scrollOffset = 0
      return 0..<0
    }
    _ = reconcile(itemCount: itemCount)
    let selected = selectedIndex ?? 0
    if selected < scrollOffset {
      scrollOffset = selected
    } else if selected >= scrollOffset + viewportCount {
      scrollOffset = selected - viewportCount + 1
    }
    let maximumOffset = max(0, itemCount - viewportCount)
    scrollOffset = min(scrollOffset, maximumOffset)
    return scrollOffset..<min(itemCount, scrollOffset + viewportCount)
  }
}
