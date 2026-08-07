import CustomDump
import Testing

@testable import Ratatui

@Suite struct GeometryTests {
  @Test func rectArithmeticClampsToTerminalCoordinates() {
    #expect(
      Rect(x: UInt16.max - 1, y: UInt16.max - 1, width: 10, height: 10).size
        == Size(width: 1, height: 1))

    let rect = Rect(x: 80, y: 80, width: 30, height: 30)
    #expect(
      rect.clamped(to: Rect(x: 0, y: 0, width: 100, height: 100))
        == Rect(x: 70, y: 70, width: 30, height: 30))
    #expect(
      rect.offset(by: Offset(x: -100, y: 100_000))
        == Rect(x: 0, y: UInt16.max - 30, width: 30, height: 30))
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
