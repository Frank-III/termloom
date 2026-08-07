import CustomDump
import Testing

@testable import Ratatui

@Suite struct LayoutTests {
  @Test func repeatedSplitsUseTheBoundedCacheAndReuseSpacerGeometry() {
    Layout.configureCache(capacity: 500)
    defer { Layout.configureCache() }

    let area = Rect(x: 2, y: 3, width: 97, height: 11)
    let layout = Layout.horizontal(
      .length(7),
      .percentage(30),
      .min(4),
      spacing: 2,
      flex: .spaceAround,
      margin: Insets(top: 0, leading: 1, bottom: 0, trailing: 1)
    )
    let first = layout.splitWithSpacers(area)
    let afterFirst = Layout.cacheStatistics
    var second = first
    for _ in 0..<16 { second = layout.splitWithSpacers(area) }
    let afterSecond = Layout.cacheStatistics

    expectNoDifference(second.areas, first.areas)
    expectNoDifference(second.spacers, first.spacers)
    #expect((1...500).contains(afterFirst.entries))
    #expect((1...500).contains(afterSecond.entries))
    #expect(afterSecond.hits > afterFirst.hits)

    _ = Layout.vertical(.length(1), .flex(1)).split(area)
    _ = Layout.horizontal(.ratio(numerator: 1, denominator: 2), .flex(1)).split(area)
    #expect((1...500).contains(Layout.cacheStatistics.entries))
  }

  @Test func cachedSplitsAreSafeAcrossConcurrentTasks() async {
    let area = Rect(x: 0, y: 0, width: 120, height: 40)
    let layout = Layout.horizontal(
      .length(12),
      .percentage(25),
      .ratio(numerator: 1, denominator: 3),
      .min(8),
      spacing: 1,
      flex: .center
    )
    let expected = layout.splitWithSpacers(area)

    let matches = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
      for _ in 0..<64 {
        group.addTask {
          let result = layout.splitWithSpacers(area)
          return result.areas == expected.areas && result.spacers == expected.spacers
        }
      }
      var matches: [Bool] = []
      for await match in group { matches.append(match) }
      return matches
    }
    #expect(matches.allSatisfy { $0 })
  }

  @Test func fixedAndFlexibleConstraintsShareRemainingSpace() {
    let areas = Layout.horizontal(
      .length(10),
      .flex(2),
      .flex(1),
      spacing: 1
    ).split(Rect(x: 0, y: 0, width: 42, height: 3))

    expectNoDifference(
      areas,
      [
        Rect(x: 0, y: 0, width: 10, height: 3),
        Rect(x: 11, y: 0, width: 20, height: 3),
        Rect(x: 32, y: 0, width: 10, height: 3),
      ]
    )
  }

  @Test func fixedConstraintsDoNotSilentlyStretchTheLastChild() {
    let areas = Layout.vertical(.length(1), .length(1), spacing: 1)
      .split(Rect(x: 0, y: 0, width: 10, height: 8))

    expectNoDifference(
      areas,
      [
        Rect(x: 0, y: 0, width: 10, height: 1),
        Rect(x: 0, y: 2, width: 10, height: 1),
      ]
    )
  }

  @Test func flexModesPlaceUnusedSpace() {
    let area = Rect(x: 0, y: 0, width: 12, height: 1)
    let constraints: [Constraint] = [.length(2), .length(2)]

    #expect(
      Layout(.horizontal, constraints: constraints, flex: .start).split(area).map(\.x) == [0, 2])
    #expect(
      Layout(.horizontal, constraints: constraints, flex: .end).split(area).map(\.x) == [8, 10])
    #expect(
      Layout(.horizontal, constraints: constraints, flex: .center).split(area).map(\.x) == [4, 6])
    #expect(
      Layout(.horizontal, constraints: constraints, flex: .spaceBetween).split(area).map(\.x)
        == [0, 10]
    )
    #expect(
      Layout(.horizontal, constraints: constraints, flex: .spaceEvenly).split(area).map(\.x)
        == [3, 7]
    )
    #expect(
      Layout(.horizontal, constraints: constraints, flex: .spaceAround).split(area).map(\.x)
        == [2, 8]
    )
  }

  @Test func flexPositionsEveryConstraintFamilyLikeUpstream() {
    typealias Case = (constraints: [Constraint], flex: Flex, expected: [(UInt16, UInt16)])
    let cases: [Case] = [
      ([.length(50)], .legacy, [(0, 100)]),
      ([.length(50)], .start, [(0, 50)]),
      ([.length(50)], .end, [(50, 50)]),
      ([.length(50)], .center, [(25, 50)]),
      ([.length(50)], .spaceBetween, [(0, 100)]),
      ([.length(50)], .spaceEvenly, [(25, 50)]),
      ([.length(50)], .spaceAround, [(25, 50)]),
      ([.min(50)], .start, [(0, 100)]),
      ([.min(50)], .center, [(0, 100)]),
      ([.max(50)], .start, [(0, 50)]),
      ([.max(50)], .end, [(50, 50)]),
      ([.max(20)], .spaceBetween, [(0, 100)]),
      ([.length(25), .length(25)], .legacy, [(0, 25), (25, 75)]),
      ([.length(25), .length(25)], .start, [(0, 25), (25, 25)]),
      ([.length(25), .length(25)], .center, [(25, 25), (50, 25)]),
      ([.length(25), .length(25)], .end, [(50, 25), (75, 25)]),
      ([.length(25), .length(25)], .spaceBetween, [(0, 25), (75, 25)]),
      ([.length(25), .length(25)], .spaceEvenly, [(17, 25), (58, 25)]),
      ([.length(25), .length(25)], .spaceAround, [(13, 25), (63, 25)]),
      ([.percentage(25), .percentage(25)], .spaceEvenly, [(17, 25), (58, 25)]),
      ([.min(25), .min(25)], .spaceAround, [(0, 50), (50, 50)]),
      ([.max(25), .max(25)], .spaceAround, [(13, 25), (63, 25)]),
      (
        [.length(25), .length(25), .length(25)], .spaceBetween,
        [(0, 25), (38, 25), (75, 25)]
      ),
    ]
    let area = Rect(x: 0, y: 0, width: 100, height: 1)
    for testCase in cases {
      let result = Layout(
        .horizontal,
        constraints: testCase.constraints,
        flex: testCase.flex
      ).split(area).map { ($0.x, $0.width) }
      #expect(result.elementsEqual(testCase.expected, by: ==))
    }
  }

  @Test func minAndMaxMatchRatatuiGrowthSemantics() {
    let area = Rect(x: 0, y: 0, width: 80, height: 1)

    #expect(
      Layout.horizontal(.min(20), .max(20)).split(area).map(\.width)
        == [60, 20]
    )
    #expect(
      Layout.horizontal(.max(20), .max(20)).split(area).map(\.width)
        == [20, 20]
    )
    #expect(
      Layout(.horizontal, constraints: [.max(20)], flex: .legacy).split(area).map(\.width)
        == [80]
    )
  }

  @Test func relativeConstraintsRoundToTerminalCells() {
    let areas = Layout.horizontal(
      .percentage(25),
      .ratio(numerator: 1, denominator: 3)
    ).split(Rect(x: 0, y: 0, width: 10, height: 1))

    #expect(areas.map(\.width) == [3, 3])
  }

  @Test func marginsOverlapAndSpacerGeometryMatchUpstreamSemantics() {
    let result = Layout.horizontal(
      .length(10),
      .length(10),
      spacing: -1,
      flex: .start,
      margin: Insets(top: 1, leading: 2, bottom: 1, trailing: 2)
    ).splitWithSpacers(Rect(x: 0, y: 0, width: 104, height: 3))

    expectNoDifference(
      result.areas,
      [
        Rect(x: 2, y: 1, width: 10, height: 1),
        Rect(x: 11, y: 1, width: 10, height: 1),
      ]
    )
    expectNoDifference(
      result.spacers,
      [
        Rect(x: 2, y: 1, width: 0, height: 1),
        Rect(x: 12, y: 1, width: 0, height: 1),
        Rect(x: 21, y: 1, width: 81, height: 1),
      ]
    )
  }

  @Test func positiveSpacingProducesInspectableSpacerRects() {
    let layout = Layout.horizontal(
      .length(10),
      .length(10),
      spacing: 5,
      flex: .center
    )
    expectNoDifference(
      layout.splitWithSpacers(Rect(x: 0, y: 0, width: 100, height: 2)).spacers,
      [
        Rect(x: 0, y: 0, width: 38, height: 2),
        Rect(x: 48, y: 0, width: 5, height: 2),
        Rect(x: 63, y: 0, width: 37, height: 2),
      ]
    )
  }

  @Test func legacyPrioritiesMatchUpstreamPathologicalConstraints() {
    let area = Rect(x: 0, y: 0, width: 100, height: 1)
    func widths(_ constraints: [Constraint]) -> [UInt16] {
      Layout(.horizontal, constraints: constraints, flex: .legacy).split(area).map(\.width)
    }

    expectNoDifference(widths([.length(25), .min(100)]), [0, 100])
    expectNoDifference(widths([.length(25), .min(0)]), [25, 75])
    expectNoDifference(widths([.length(25), .max(0)]), [100, 0])
    expectNoDifference(widths([.length(25), .max(100)]), [25, 75])
    expectNoDifference(widths([.length(25), .percentage(25)]), [25, 75])
    expectNoDifference(widths([.percentage(25), .length(25)]), [75, 25])
    expectNoDifference(widths([.length(25), .ratio(numerator: 1, denominator: 4)]), [25, 75])
    expectNoDifference(widths([.ratio(numerator: 1, denominator: 4), .length(25)]), [75, 25])
    expectNoDifference(widths([.min(25), .length(25), .max(25)]), [50, 25, 25])
    expectNoDifference(widths([.max(25), .length(25), .min(25)]), [25, 25, 50])
    expectNoDifference(widths([.length(100), .length(1), .min(20)]), [80, 0, 20])
    expectNoDifference(widths([.min(20), .length(1), .length(100)]), [20, 1, 79])
  }

  @Test func fillWeightsMatchTheUpstreamConstraintCorpus() {
    typealias Case = (constraints: [Constraint], expected: [(UInt16, UInt16)])
    let cases: [Case] = [
      ([.flex(1), .flex(2), .flex(1), .flex(1)], [(0, 20), (20, 40), (60, 20), (80, 20)]),
      ([.flex(1), .flex(2), .flex(3), .flex(4)], [(0, 10), (10, 20), (30, 30), (60, 40)]),
      ([.flex(4), .flex(3), .flex(2), .flex(1)], [(0, 40), (40, 30), (70, 20), (90, 10)]),
      (
        [.flex(1), .flex(3), .length(50), .flex(2), .flex(4)],
        [(0, 5), (5, 15), (20, 50), (70, 10), (80, 20)]
      ),
      ([.flex(0), .flex(1), .flex(0)], [(0, 0), (0, 100), (100, 0)]),
      ([.flex(0), .length(1), .flex(0)], [(0, 50), (50, 1), (51, 49)]),
      ([.flex(0), .flex(2), .flex(0), .flex(1)], [(0, 0), (0, 67), (67, 0), (67, 33)]),
      ([.flex(0), .percentage(20)], [(0, 80), (80, 20)]),
      ([.flex(0), .flex(0), .percentage(20)], [(0, 40), (40, 40), (80, 20)]),
      ([.flex(0), .ratio(numerator: 1, denominator: 5)], [(0, 80), (80, 20)]),
      ([.flex(0), .flex(.max)], [(0, 0), (0, 100)]),
      ([.flex(.max), .flex(0), .percentage(20)], [(0, 80), (80, 0), (80, 20)]),
      (
        [.flex(1), .flex(1), .flex(1), .min(30), .length(50)],
        [(0, 7), (7, 6), (13, 7), (20, 30), (50, 50)]
      ),
      (
        [.flex(1), .flex(1), .flex(1), .length(50), .length(50)],
        [(0, 0), (0, 0), (0, 0), (0, 50), (50, 50)]
      ),
      (
        [.flex(1), .flex(1), .flex(1), .ratio(numerator: 1, denominator: 1)],
        [(0, 0), (0, 0), (0, 0), (0, 100)]
      ),
    ]
    let area = Rect(x: 0, y: 0, width: 100, height: 1)
    for testCase in cases {
      let result = Layout(.horizontal, constraints: testCase.constraints, flex: .legacy)
        .split(area).map { ($0.x, $0.width) }
      #expect(result.elementsEqual(testCase.expected, by: ==))
    }
  }

  @Test func flexSpacingAndOverlapMatchTheUpstreamMatrix() {
    typealias Case = (
      constraints: [Constraint], flex: Flex, spacing: LayoutSpacing,
      expected: [(UInt16, UInt16)]
    )
    let fixed: [Constraint] = [.length(20), .length(20), .length(20)]
    let cases: [Case] = [
      (fixed, .start, 2, [(0, 20), (22, 20), (44, 20)]),
      (fixed, .center, 2, [(18, 20), (40, 20), (62, 20)]),
      (fixed, .end, 2, [(36, 20), (58, 20), (80, 20)]),
      (fixed, .legacy, 2, [(0, 20), (22, 20), (44, 56)]),
      (fixed, .spaceBetween, 2, [(0, 20), (40, 20), (80, 20)]),
      (fixed, .spaceEvenly, 2, [(10, 20), (40, 20), (70, 20)]),
      (fixed, .spaceAround, 2, [(7, 20), (40, 20), (73, 20)]),
      (fixed, .center, -1, [(21, 20), (40, 20), (59, 20)]),
      (fixed, .end, -1, [(42, 20), (61, 20), (80, 20)]),
      (fixed, .legacy, -1, [(0, 20), (19, 20), (38, 62)]),
      (
        [.flex(1), .flex(1)], .spaceEvenly, 10,
        [(10, 35), (55, 35)]
      ),
      (
        [.flex(1), .flex(1)], .spaceAround, 10,
        [(10, 30), (60, 30)]
      ),
      (
        [.flex(1), .length(10), .flex(1)], .spaceEvenly, 10,
        [(10, 25), (45, 10), (65, 25)]
      ),
      (
        [.flex(1), .length(10), .flex(1)], .spaceAround, 10,
        [(10, 15), (45, 10), (75, 15)]
      ),
      (
        [.flex(1), .flex(1)], .spaceAround, -10,
        [(0, 50), (50, 50)]
      ),
      (
        [.flex(1), .length(10), .flex(1)], .spaceEvenly, -10,
        [(0, 45), (45, 10), (55, 45)]
      ),
    ]
    let area = Rect(x: 0, y: 0, width: 100, height: 1)
    for testCase in cases {
      let result = Layout(
        .horizontal,
        constraints: testCase.constraints,
        spacing: testCase.spacing,
        flex: testCase.flex
      ).split(area).map { ($0.x, $0.width) }
      #expect(result.elementsEqual(testCase.expected, by: ==))
    }
  }

  @Test func tinyAreasMatchUpstreamSolverEdgeCases() {
    let vertical = Rect(x: 0, y: 0, width: 1, height: 1)
    expectNoDifference(
      Layout(
        .vertical,
        constraints: [.percentage(50), .percentage(50), .min(0)],
        flex: .legacy
      ).split(vertical),
      [
        Rect(x: 0, y: 0, width: 1, height: 1),
        Rect(x: 0, y: 1, width: 1, height: 0),
        Rect(x: 0, y: 1, width: 1, height: 0),
      ]
    )
    expectNoDifference(
      Layout(
        .vertical,
        constraints: [.max(1), .percentage(99), .min(0)],
        flex: .legacy
      ).split(vertical),
      [
        Rect(x: 0, y: 0, width: 1, height: 0),
        Rect(x: 0, y: 0, width: 1, height: 1),
        Rect(x: 0, y: 1, width: 1, height: 0),
      ]
    )
    expectNoDifference(
      Layout(
        .horizontal,
        constraints: [.min(1), .length(0), .min(1)],
        flex: .legacy
      ).split(vertical),
      [
        Rect(x: 0, y: 0, width: 1, height: 1),
        Rect(x: 1, y: 0, width: 0, height: 1),
        Rect(x: 1, y: 0, width: 0, height: 1),
      ]
    )
  }
}
