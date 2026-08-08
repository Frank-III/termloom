public struct Cell: Hashable, Sendable {
  public var symbol: String
  private var styledMetadata: Style

  public var style: Style {
    get { styledMetadata.clearingCellWidthMetadata() }
    set {
      let width = styledMetadata.cellWidthMetadata
      styledMetadata = newValue.withCellWidthMetadata(width)
    }
  }

  public var width: UInt8 {
    get { styledMetadata.cellWidthMetadata }
    set { styledMetadata = styledMetadata.withCellWidthMetadata(newValue) }
  }

  public var isContinuation: Bool {
    get { width == 0 }
    set {
      if newValue {
        width = 0
      } else if width == 0 {
        width = 1
      }
    }
  }

  public init(
    symbol: String = " ",
    style: Style = .plain,
    width: UInt8 = 1,
    isContinuation: Bool = false
  ) {
    self.symbol = symbol
    styledMetadata = style.withCellWidthMetadata(isContinuation ? 0 : max(1, width))
  }

  public static let empty = Self()
}

public struct CellUpdate: Hashable, Sendable {
  public var position: Position
  public var cell: Cell

  public init(position: Position, cell: Cell) {
    self.position = position
    self.cell = cell
  }
}
