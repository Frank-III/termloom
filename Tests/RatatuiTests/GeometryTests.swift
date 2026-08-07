import CustomDump
import Testing

@testable import Ratatui

@Suite struct GeometryTests {
  @Test func rectArithmeticUsesNonnegativeNativeIntegersAndSaturatesOverflow() {
    #expect(
      Rect(x: Int.max - 1, y: Int.max - 1, width: 10, height: 10).size
        == Size(width: 1, height: 1))
    #expect(Rect(x: -4, y: -3, width: -2, height: -1) == .zero)
    #expect(Position(x: -1, y: -2) == Position(x: 0, y: 0))
    #expect(Size(width: -1, height: -2) == .zero)

    var mutated = Rect(x: 1, y: 2, width: 3, height: 4)
    mutated.x = -1
    mutated.y = -2
    mutated.width = -3
    mutated.height = -4
    #expect(mutated == .zero)

    mutated = Rect(x: 1, y: 2, width: 3, height: 4)
    mutated.x = .max
    mutated.y = .max
    #expect(mutated == Rect(x: .max, y: .max, width: 0, height: 0))
    mutated.width = .max
    mutated.height = .max
    #expect(mutated.width == 0)
    #expect(mutated.height == 0)

    let rect = Rect(x: 80, y: 80, width: 30, height: 30)
    #expect(
      rect.clamped(to: Rect(x: 0, y: 0, width: 100, height: 100))
        == Rect(x: 70, y: 70, width: 30, height: 30))
    #expect(
      rect.offset(by: Offset(x: -100, y: 100_000))
        == Rect(x: 0, y: 100_080, width: 30, height: 30))
    #expect(
      Rect(x: Int.max - 40, y: 0, width: 30, height: 1)
        .offset(by: Offset(x: 100, y: 0))
        == Rect(x: Int.max - 30, y: 0, width: 30, height: 1))
  }

  @Test func rectSetOperationsAndInsetsRemainValueSemantic() {
    let first = Rect(x: 2, y: 3, width: 8, height: 6)
    let second = Rect(x: 7, y: 1, width: 5, height: 5)

    #expect(first.intersects(second))
    #expect(first.intersection(second) == Rect(x: 7, y: 3, width: 3, height: 3))
    #expect(first.union(second) == Rect(x: 2, y: 1, width: 10, height: 8))
    #expect(
      first.inset(by: Insets(top: 1, leading: 2, bottom: 1, trailing: 2))
        == Rect(x: 4, y: 4, width: 4, height: 4)
    )
    #expect(
      first.outset(by: Insets(top: 1, leading: 2, bottom: 1, trailing: 2))
        == Rect(x: 0, y: 2, width: 12, height: 8)
    )
  }

  @Test func rowsColumnsAndPositionsAreLazyStableSequences() {
    let rect = Rect(x: 2, y: 3, width: 2, height: 2)
    expectNoDifference(
      Array(rect.rows()),
      [
        Rect(x: 2, y: 3, width: 2, height: 1),
        Rect(x: 2, y: 4, width: 2, height: 1),
      ]
    )
    expectNoDifference(
      Array(rect.columns()),
      [
        Rect(x: 2, y: 3, width: 1, height: 2),
        Rect(x: 3, y: 3, width: 1, height: 2),
      ]
    )
    expectNoDifference(
      Array(rect.positions()),
      [
        Position(x: 2, y: 3),
        Position(x: 3, y: 3),
        Position(x: 2, y: 4),
        Position(x: 3, y: 4),
      ]
    )
  }
}
