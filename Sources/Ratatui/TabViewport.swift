/// A pure contiguous projection for variable-width horizontal tabs.
public struct TabViewport: Hashable, Sendable {
  public var range: Range<Int>
  public var hasTabsBefore: Bool
  public var hasTabsAfter: Bool

  public init(range: Range<Int>, hasTabsBefore: Bool, hasTabsAfter: Bool) {
    self.range = range
    self.hasTabsBefore = hasTabsBefore
    self.hasTabsAfter = hasTabsAfter
  }

  public static func fitting(
    widths: [Int],
    selectedIndex: Int?,
    capacity: Int,
    spacing: Int = 0,
    leadingOverflowWidth: Int = 0,
    trailingOverflowWidth: Int = 0,
    placement: SelectionPlacement = .trailing
  ) -> TabViewport {
    let widths = widths.map { max(0, $0) }
    let capacity = max(0, capacity)
    guard !widths.isEmpty, capacity > 0 else {
      return TabViewport(
        range: 0..<0,
        hasTabsBefore: false,
        hasTabsAfter: !widths.isEmpty
      )
    }

    let selected = min(max(0, selectedIndex ?? 0), widths.count - 1)
    let spacing = max(0, spacing)
    let leadingOverflowWidth = max(0, leadingOverflowWidth)
    let trailingOverflowWidth = max(0, trailingOverflowWidth)
    var start = selected
    var end = selected + 1
    var tabWidth = widths[selected]

    func projectedWidth(start: Int, end: Int, tabWidth: Int) -> Int {
      var result = tabWidth
      result = saturatingTabAdd(
        result, saturatingTabMultiply(max(0, end - start - 1), spacing))
      if start > 0 { result = saturatingTabAdd(result, leadingOverflowWidth) }
      if end < widths.count { result = saturatingTabAdd(result, trailingOverflowWidth) }
      return result
    }

    func canInclude(start candidateStart: Int, end candidateEnd: Int, width: Int) -> Bool {
      projectedWidth(start: candidateStart, end: candidateEnd, tabWidth: width) <= capacity
    }

    func prepend() -> Bool {
      guard start > 0 else { return false }
      let candidateStart = start - 1
      let candidateWidth = saturatingTabAdd(tabWidth, widths[candidateStart])
      guard canInclude(start: candidateStart, end: end, width: candidateWidth) else { return false }
      start = candidateStart
      tabWidth = candidateWidth
      return true
    }

    func append() -> Bool {
      guard end < widths.count else { return false }
      let candidateWidth = saturatingTabAdd(tabWidth, widths[end])
      guard canInclude(start: start, end: end + 1, width: candidateWidth) else { return false }
      tabWidth = candidateWidth
      end += 1
      return true
    }

    // Reaching an edge removes that side's overflow indicator. In very narrow layouts the complete
    // remainder can therefore fit even when adding only the next tab cannot.
    func prependToBoundary() -> Bool {
      guard start > 0 else { return false }
      let candidateWidth = widths[..<start].reduce(tabWidth, saturatingTabAdd)
      guard canInclude(start: 0, end: end, width: candidateWidth) else { return false }
      start = 0
      tabWidth = candidateWidth
      return true
    }

    func appendToBoundary() -> Bool {
      guard end < widths.count else { return false }
      let candidateWidth = widths[end...].reduce(tabWidth, saturatingTabAdd)
      guard canInclude(start: start, end: widths.count, width: candidateWidth) else { return false }
      end = widths.count
      tabWidth = candidateWidth
      return true
    }

    func prependAvailable() -> Bool { prepend() || prependToBoundary() }
    func appendAvailable() -> Bool { append() || appendToBoundary() }

    switch placement {
    case .leading:
      while appendAvailable() {}
      while prependAvailable() {}
    case .trailing:
      while prependAvailable() {}
      while appendAvailable() {}
    case .center:
      var prefersLeading = true
      while true {
        let expanded =
          prefersLeading
          ? prependAvailable() || appendAvailable()
          : appendAvailable() || prependAvailable()
        guard expanded else { break }
        prefersLeading.toggle()
      }
    }

    return TabViewport(
      range: start..<end,
      hasTabsBefore: start > 0,
      hasTabsAfter: end < widths.count
    )
  }
}

private func saturatingTabAdd(_ lhs: Int, _ rhs: Int) -> Int {
  let result = lhs.addingReportingOverflow(rhs)
  return result.overflow ? .max : result.partialValue
}

private func saturatingTabMultiply(_ lhs: Int, _ rhs: Int) -> Int {
  let result = lhs.multipliedReportingOverflow(by: rhs)
  return result.overflow ? .max : result.partialValue
}
