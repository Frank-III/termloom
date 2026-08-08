import Foundation

public enum LayoutSpacing: Hashable, Sendable, ExpressibleByIntegerLiteral {
  case space(Int)
  case overlap(Int)

  public init(integerLiteral value: Int) {
    if value < 0 {
      self = .overlap(value == .min ? .max : -value)
    } else {
      self = .space(value)
    }
  }

  fileprivate var signedValue: Int {
    switch self {
    case .space(let value): max(0, value)
    case .overlap(let value): -max(0, value)
    }
  }
}

public struct Layout: Hashable, Sendable {
  public static let defaultCacheCapacity = 500

  public var axis: Axis
  public var constraints: [Constraint]
  public var spacing: LayoutSpacing
  public var flex: Flex
  public var margin: Insets

  public init(
    _ axis: Axis,
    constraints: [Constraint],
    spacing: LayoutSpacing = 0,
    flex: Flex = .start,
    margin: Insets = .all(0)
  ) {
    self.axis = axis
    self.constraints = constraints
    self.spacing = spacing
    self.flex = flex
    self.margin = margin
  }

  public static func horizontal(
    _ constraints: Constraint...,
    spacing: LayoutSpacing = 0,
    flex: Flex = .start,
    margin: Insets = .all(0)
  ) -> Self {
    Self(.horizontal, constraints: constraints, spacing: spacing, flex: flex, margin: margin)
  }

  public static func vertical(
    _ constraints: Constraint...,
    spacing: LayoutSpacing = 0,
    flex: Flex = .start,
    margin: Insets = .all(0)
  ) -> Self {
    Self(.vertical, constraints: constraints, spacing: spacing, flex: flex, margin: margin)
  }

  /// Reconfigures the process-wide bounded layout cache and removes existing entries.
  public static func configureCache(capacity: Int = defaultCacheCapacity) {
    precondition(capacity > 0, "layout cache capacity must be positive")
    cache.withLock { state in
      state.capacity = capacity
      state.clock = 0
      state.entries.removeAll(keepingCapacity: true)
      state.hits = 0
      state.misses = 0
    }
  }

  public static func clearCache() {
    cache.withLock { state in
      state.clock = 0
      state.entries.removeAll(keepingCapacity: true)
      state.hits = 0
      state.misses = 0
    }
  }

  public func split(_ area: Rect) -> [Rect] {
    if !shouldCache { return splitUncached(area) }
    return cachedSplit(area).areas
  }

  private func splitUncached(_ area: Rect) -> [Rect] {
    guard !constraints.isEmpty else { return [] }

    let area = area.inset(by: margin)

    let extent = axis == .horizontal ? area.width : area.height
    let baseSpacers = initialSpacers()
    let totalSpacing = saturatingSum(baseSpacers)
    let available = max(0, saturatingSubtract(extent, totalSpacing))
    if usesCommonSolver {
      return splitCommonConstraints(area, available: available)
    }
    var lengths = constraints.map { constraint -> Int in
      switch constraint {
      case .min(let value), .max(let value), .length(let value):
        min(available, max(0, value))
      case .percentage(let value):
        proportionalRequest(available, numerator: value, denominator: 100)
      case .ratio(let numerator, let denominator):
        proportionalRequest(available, numerator: numerator, denominator: denominator)
      case .flex:
        0
      }
    }

    // Relax lower-priority constraints first. A minimum is the only hard lower
    // bound; every returned segment is still clipped to the available area.
    var overflow = max(0, saturatingSubtract(saturatingSum(lengths), available))
    let shrinkOrder: [[Int]] = [
      indices(matching: { if case .max = $0 { true } else { false } }),
      indices(matching: { if case .flex = $0 { true } else { false } }),
      indices(matching: { if case .ratio = $0 { true } else { false } }),
      indices(matching: { if case .percentage = $0 { true } else { false } }),
      indices(matching: { if case .length = $0 { true } else { false } }),
    ]
    for candidateIndices in shrinkOrder where overflow > 0 {
      for index in candidateIndices.reversed() where overflow > 0 {
        let reduction = min(lengths[index], overflow)
        lengths[index] -= reduction
        overflow -= reduction
      }
    }
    if overflow > 0 {
      // The minimums themselves cannot fit. Clip from the trailing edge while
      // preserving as many leading minimums as possible.
      for index in constraints.indices.reversed() where overflow > 0 {
        let reduction = min(lengths[index], overflow)
        lengths[index] -= reduction
        overflow -= reduction
      }
    }

    var remaining = max(0, saturatingSubtract(available, saturatingSum(lengths)))
    let hasPositiveFill = constraints.contains {
      if case .flex(let weight) = $0 { return weight > 0 }
      return false
    }
    let growers = constraints.enumerated().compactMap { index, constraint -> (Int, Int)? in
      switch constraint {
      case .flex(let weight):
        let weight = hasPositiveFill ? Int(weight) : 1
        return weight > 0 ? (index, weight) : nil
      case .min where flex != .legacy:
        return (index, 1)
      default:
        return nil
      }
    }
    if !growers.isEmpty {
      let shares = distribute(remaining, weights: growers.map(\.1))
      for (grower, share) in zip(growers, shares) {
        lengths[grower.0] = saturatingAdd(lengths[grower.0], share)
      }
      remaining = 0
    } else if flex == .legacy, remaining > 0 {
      lengths[legacyGrowthRecipient()] = saturatingAdd(lengths[legacyGrowthRecipient()], remaining)
      remaining = 0
    }

    var spacers = baseSpacers
    let excess = max(
      0,
      saturatingSubtract(saturatingSubtract(extent, saturatingSum(lengths)), saturatingSum(spacers))
    )
    switch flex {
    case .legacy, .start:
      spacers[spacers.count - 1] = saturatingAdd(spacers[spacers.count - 1], excess)
    case .end:
      spacers[0] = saturatingAdd(spacers[0], excess)
    case .center:
      spacers[0] = saturatingAdd(spacers[0], excess) - excess / 2
      spacers[spacers.count - 1] = saturatingAdd(spacers[spacers.count - 1], excess) / 2
    case .spaceBetween:
      if constraints.count > 1 {
        let shares = distribute(
          excess,
          weights: Array(repeating: 1, count: constraints.count - 1)
        )
        for (index, share) in shares.enumerated() {
          spacers[index + 1] = saturatingAdd(spacers[index + 1], share)
        }
      } else {
        lengths[0] = saturatingAdd(lengths[0], excess)
      }
    case .spaceEvenly:
      let shares = distribute(excess, weights: Array(repeating: 1, count: spacers.count))
      for index in spacers.indices { spacers[index] = saturatingAdd(spacers[index], shares[index]) }
    case .spaceAround:
      let weights =
        constraints.count == 1
        ? [1, 1]
        : [1] + Array(repeating: 2, count: max(0, constraints.count - 1)) + [1]
      let shares = distribute(excess, weights: weights)
      for index in spacers.indices { spacers[index] = saturatingAdd(spacers[index], shares[index]) }
    }

    var cursor = saturatingOffset(
      axis == .horizontal ? area.x : area.y,
      by: spacers[0]
    )
    return lengths.enumerated().map { index, length in
      defer { cursor = saturatingOffset(cursor, by: saturatingAdd(length, spacers[index + 1])) }
      switch axis {
      case .horizontal:
        return Rect(
          x: cursor,
          y: area.y,
          width: length,
          height: area.height
        )
      case .vertical:
        return Rect(
          x: area.x,
          y: cursor,
          width: area.width,
          height: length
        )
      }
    }
  }

  public func splitWithSpacers(_ area: Rect) -> (areas: [Rect], spacers: [Rect]) {
    if !shouldCache {
      let areas = splitUncached(area)
      return (areas, makeSpacers(in: area, areas: areas))
    }
    let cached = cachedSplit(area)
    if let spacers = cached.spacers { return (cached.areas, spacers) }

    let spacers = makeSpacers(in: area, areas: cached.areas)
    Self.cache.withLock { state in
      let key = CacheKey(area: area, layout: self)
      guard var entry = state.entries[key] else { return }
      entry.value.spacers = spacers
      state.clock &+= 1
      entry.lastAccess = state.clock
      state.entries[key] = entry
    }
    return (cached.areas, spacers)
  }

  private func makeSpacers(in area: Rect, areas: [Rect]) -> [Rect] {
    let inner = area.inset(by: margin)
    guard let first = areas.first, let last = areas.last else {
      return [inner]
    }

    func spacer(start: Int, length: Int) -> Rect {
      switch axis {
      case .horizontal:
        Rect(
          x: start,
          y: inner.y,
          width: max(0, length),
          height: inner.height
        )
      case .vertical:
        Rect(
          x: inner.x,
          y: start,
          width: inner.width,
          height: max(0, length)
        )
      }
    }

    let innerStart = axis == .horizontal ? Int(inner.x) : Int(inner.y)
    let innerEnd = innerStart + (axis == .horizontal ? Int(inner.width) : Int(inner.height))
    let firstStart = axis == .horizontal ? Int(first.x) : Int(first.y)
    var spacers = [spacer(start: innerStart, length: firstStart - innerStart)]
    for (previous, next) in zip(areas, areas.dropFirst()) {
      let previousStart = axis == .horizontal ? Int(previous.x) : Int(previous.y)
      let previousLength = axis == .horizontal ? Int(previous.width) : Int(previous.height)
      let previousEnd = previousStart + previousLength
      let nextStart = axis == .horizontal ? Int(next.x) : Int(next.y)
      spacers.append(spacer(start: previousEnd, length: nextStart - previousEnd))
    }
    let lastStart = axis == .horizontal ? Int(last.x) : Int(last.y)
    let lastLength = axis == .horizontal ? Int(last.width) : Int(last.height)
    let lastEnd = lastStart + lastLength
    spacers.append(spacer(start: lastEnd, length: innerEnd - lastEnd))
    return spacers
  }

  public func spacers(in area: Rect) -> [Rect] {
    splitWithSpacers(area).spacers
  }

  /// The overwhelmingly common table/stack path avoids the general solver's
  /// priority and spacer bookkeeping. Keep this allocation-light: layout is
  /// invoked for every rendered frame.
  private func splitCommonConstraints(_ area: Rect, available: Int) -> [Rect] {
    var lengths = Array(repeating: 0, count: constraints.count)
    var remaining = available
    let hasPositiveFill = constraints.contains {
      if case .flex(let weight) = $0 { return weight > 0 }
      return false
    }
    var flexWeight = 0.0
    for (index, constraint) in constraints.enumerated() {
      let requested: Int
      switch constraint {
      case .length(let value):
        requested = min(available, max(0, value))
      case .percentage(let value):
        requested = proportionalRequest(available, numerator: value, denominator: 100)
      case .ratio(let numerator, let denominator):
        requested = proportionalRequest(
          available,
          numerator: numerator,
          denominator: denominator
        )
      case .flex(let weight):
        flexWeight += Double(max(0, hasPositiveFill ? weight : 1))
        continue
      case .min, .max:
        preconditionFailure("minimum and maximum constraints use the general layout path")
      }
      let length = min(remaining, max(0, requested))
      lengths[index] = length
      remaining -= length
    }

    if flexWeight > 0 {
      var consumedWeight = 0.0
      var consumedLength = 0
      for (index, constraint) in constraints.enumerated() {
        guard case .flex(let rawWeight) = constraint else { continue }
        let weight = hasPositiveFill ? rawWeight : 1
        guard weight > 0 else { continue }
        consumedWeight += Double(weight)
        let target = Int((Double(remaining) * consumedWeight / flexWeight).rounded(.down))
        lengths[index] = target - consumedLength
        consumedLength = target
      }
    }

    var result: [Rect] = []
    result.reserveCapacity(lengths.count)
    var cursor = axis == .horizontal ? Int(area.x) : Int(area.y)
    for length in lengths {
      switch axis {
      case .horizontal:
        result.append(
          Rect(
            x: cursor,
            y: area.y,
            width: length,
            height: area.height
          )
        )
      case .vertical:
        result.append(
          Rect(
            x: area.x,
            y: cursor,
            width: area.width,
            height: length
          )
        )
      }
      cursor = saturatingOffset(cursor, by: saturatingAdd(length, spacing.signedValue))
    }
    return result
  }

  private func indices(matching predicate: (Constraint) -> Bool) -> [Int] {
    constraints.indices.filter { predicate(constraints[$0]) }
  }

  private func legacyGrowthRecipient() -> Int {
    let preferred: [(Constraint) -> Bool] = [
      { if case .flex = $0 { true } else { false } },
      { if case .min = $0 { true } else { false } },
      { if case .ratio = $0 { true } else { false } },
      { if case .percentage = $0 { true } else { false } },
      { if case .length = $0 { true } else { false } },
      { if case .max = $0 { true } else { false } },
    ]
    for predicate in preferred {
      if let index = constraints.indices.last(where: { predicate(constraints[$0]) }) {
        return index
      }
    }
    return constraints.indices.last!
  }

  /// Integer weighted apportionment with stable cumulative rounding. The result
  /// always sums to `total`, so a split never leaks a terminal cell.
  private func distribute(_ total: Int, weights: [Int]) -> [Int] {
    let weightTotal = weights.reduce(0.0) { $0 + Double(max(0, $1)) }
    guard total > 0, weightTotal > 0 else {
      return Array(repeating: 0, count: weights.count)
    }
    var consumedWeight = 0.0
    var consumedTotal = 0
    return weights.map { weight in
      consumedWeight += Double(max(0, weight))
      let target = Int((Double(total) * consumedWeight / weightTotal).rounded())
      defer { consumedTotal = target }
      return target - consumedTotal
    }
  }

  private var usesCommonSolver: Bool {
    flex == .start
      && !constraints.contains(where: {
        if case .min = $0 { return true }
        if case .max = $0 { return true }
        return false
      })
  }

  /// Direct arithmetic is cheaper than hashing and locking for the default
  /// start-aligned path, even when it uses minimum/maximum constraints.
  private var shouldCache: Bool { flex != .start }

  private func initialSpacers() -> [Int] {
    var spacers = Array(repeating: 0, count: constraints.count + 1)
    guard constraints.count > 0 else { return spacers }
    let value = spacing.signedValue
    switch flex {
    case .legacy, .start, .end, .center:
      if constraints.count > 1 {
        for index in 1..<constraints.count { spacers[index] = value }
      }
    case .spaceBetween:
      if constraints.count > 1, value > 0 {
        for index in 1..<constraints.count { spacers[index] = value }
      }
    case .spaceEvenly:
      if value > 0 {
        for index in spacers.indices { spacers[index] = value }
      }
    case .spaceAround:
      if value > 0 {
        spacers[0] = value
        spacers[spacers.count - 1] = value
        if constraints.count > 1 {
          for index in 1..<constraints.count { spacers[index] = value * 2 }
        }
      }
    }
    return spacers
  }

  private struct CacheKey: Hashable, Sendable {
    var area: Rect
    var layout: Layout
  }

  private struct CachedSplit: Sendable {
    var areas: [Rect]
    var spacers: [Rect]?
  }

  private struct CacheEntry: Sendable {
    var value: CachedSplit
    var lastAccess: UInt64
  }

  private struct CacheState: Sendable {
    var capacity = Layout.defaultCacheCapacity
    var clock: UInt64 = 0
    var entries: [CacheKey: CacheEntry] = [:]
    var hits: UInt64 = 0
    var misses: UInt64 = 0
  }

  private final class CacheStorage: @unchecked Sendable {
    private let lock = NSLock()
    private var state = CacheState()

    func withLock<Result>(_ body: (inout CacheState) throws -> Result) rethrows -> Result {
      lock.lock()
      defer { lock.unlock() }
      return try body(&state)
    }
  }

  private static let cache = CacheStorage()

  private func cachedSplit(_ area: Rect) -> CachedSplit {
    let key = CacheKey(area: area, layout: self)
    if let cached = Self.cache.withLock({ state -> CachedSplit? in
      guard var entry = state.entries[key] else {
        state.misses &+= 1
        return nil
      }
      state.clock &+= 1
      entry.lastAccess = state.clock
      state.entries[key] = entry
      state.hits &+= 1
      return entry.value
    }) {
      return cached
    }

    let computed = CachedSplit(areas: splitUncached(area), spacers: nil)
    return Self.cache.withLock { state in
      if var existing = state.entries[key] {
        state.clock &+= 1
        existing.lastAccess = state.clock
        state.entries[key] = existing
        state.hits &+= 1
        return existing.value
      }
      if state.entries.count >= state.capacity,
        let leastRecentlyUsed = state.entries.min(by: {
          $0.value.lastAccess < $1.value.lastAccess
        })?.key
      {
        state.entries.removeValue(forKey: leastRecentlyUsed)
      }
      state.clock &+= 1
      state.entries[key] = CacheEntry(value: computed, lastAccess: state.clock)
      return computed
    }
  }

  internal static var cacheStatistics: (entries: Int, hits: UInt64, misses: UInt64) {
    cache.withLock { state in
      (state.entries.count, state.hits, state.misses)
    }
  }
}

extension Rect {
  public func split(
    _ axis: Axis,
    _ constraints: Constraint...,
    spacing: LayoutSpacing = 0,
    flex: Flex = .start,
    margin: Insets = .all(0)
  ) -> [Rect] {
    Layout(axis, constraints: constraints, spacing: spacing, flex: flex, margin: margin).split(self)
  }
}

private func saturatingAdd(_ lhs: Int, _ rhs: Int) -> Int {
  let result = lhs.addingReportingOverflow(rhs)
  guard result.overflow else { return result.partialValue }
  return rhs >= 0 ? .max : .min
}

private func saturatingSubtract(_ lhs: Int, _ rhs: Int) -> Int {
  let result = lhs.subtractingReportingOverflow(rhs)
  guard result.overflow else { return result.partialValue }
  return rhs < 0 ? .max : .min
}

private func saturatingOffset(_ value: Int, by offset: Int) -> Int {
  max(0, saturatingAdd(value, offset))
}

private func saturatingSum(_ values: [Int]) -> Int {
  values.reduce(0, saturatingAdd)
}

private func proportionalRequest(_ available: Int, numerator: Int, denominator: Int) -> Int {
  guard available > 0, numerator > 0, denominator > 0 else { return 0 }
  let value = (Double(available) * Double(numerator) / Double(denominator)).rounded()
  guard value.isFinite, value < Double(available) else { return available }
  return max(0, Int(value))
}
