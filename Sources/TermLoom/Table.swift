/// Rich content and per-row presentation for one logical table cell.
public struct TableCell: Hashable, Sendable {
  public var lines: [Line]
  public var style: Style
  public var columnSpan: Int

  public init(_ content: String, style: Style = .plain, columnSpan: Int = 1) {
    lines = content.split(separator: "\n", omittingEmptySubsequences: false).map {
      Line(String($0))
    }
    self.style = style
    self.columnSpan = max(0, columnSpan)
  }

  public init(_ line: Line, style: Style = .plain, columnSpan: Int = 1) {
    lines = [line]
    self.style = style
    self.columnSpan = max(0, columnSpan)
  }

  public init(_ lines: [Line], style: Style = .plain, columnSpan: Int = 1) {
    self.lines = lines
    self.style = style
    self.columnSpan = max(0, columnSpan)
  }

  public init(
    style: Style = .plain,
    columnSpan: Int = 1,
    @LineBuilder lines: () -> [Line]
  ) {
    self.lines = lines()
    self.style = style
    self.columnSpan = max(0, columnSpan)
  }
}

@resultBuilder
public enum TableCellBuilder {
  public static func buildExpression(_ expression: TableCell) -> [TableCell] { [expression] }
  public static func buildExpression(_ expression: String) -> [TableCell] {
    [TableCell(expression)]
  }
  public static func buildExpression(_ expression: Line) -> [TableCell] { [TableCell(expression)] }
  public static func buildBlock(_ components: [TableCell]...) -> [TableCell] {
    components.flatMap { $0 }
  }
  public static func buildOptional(_ component: [TableCell]?) -> [TableCell] { component ?? [] }
  public static func buildEither(first component: [TableCell]) -> [TableCell] { component }
  public static func buildEither(second component: [TableCell]) -> [TableCell] { component }
  public static func buildArray(_ components: [[TableCell]]) -> [TableCell] {
    components.flatMap { $0 }
  }
}

extension Table where Row == TableRow {
  /// Creates a table from row-owned cells, matching TermLoom's sequential cell model.
  ///
  /// Omit `widths` to divide the usable area equally using the maximum cell count from
  /// the header, rows, and footer. A zero-span cell is skipped without consuming a column.
  public init(
    _ rows: [TableRow],
    widths: [Constraint] = [],
    header: TableRow? = nil,
    footer: TableRow? = nil,
    selectedRow: Int? = nil,
    style: Style = .plain,
    headerStyle: Style = .plain,
    footerStyle: Style = .plain,
    selectedStyle: Style = .plain,
    selectedColumnStyle: Style = .plain,
    selectedCellStyle: Style = .plain,
    highlightSymbol: Line = Line(""),
    highlightSymbols: [Line] = [],
    highlightSpacing: HighlightSpacing = .whenSelected,
    columnSpacing: Int = 1,
    flex: Flex = .start,
    rowSpacing: Int = 0
  ) {
    self.rows = rows
    columns = []
    self.style = style
    self.headerStyle = headerStyle
    self.footerStyle = footerStyle
    headerConfiguration = header?.configuration ?? .hidden
    footerConfiguration = footer?.configuration ?? .hidden
    self.selectedStyle = selectedStyle
    self.selectedColumnStyle = selectedColumnStyle
    self.selectedCellStyle = selectedCellStyle
    self.selectedRow = selectedRow
    self.highlightSymbols = highlightSymbols.isEmpty ? [highlightSymbol] : highlightSymbols
    self.highlightSpacing = highlightSpacing
    self.columnSpacing = max(0, columnSpacing)
    self.flex = flex
    self.rowSpacing = max(0, rowSpacing)
    rowStyle = nil
    rowHeight = nil
    rowConfiguration = { row in
      let configuration = row.configuration
      return TableRowConfiguration(
        style: configuration.style,
        height: configuration.height,
        topMargin: configuration.topMargin,
        bottomMargin: configuration.bottomMargin + Int(rowSpacing)
      )
    }
    rowCells = \.cells
    rawWidths = widths
    rawHeader = header
    rawFooter = footer
  }
}

/// A row-owned sequence of cells for tables whose shape varies from row to row.
///
/// Use this representation when cell order and spans are data. The typed `TableColumn`
/// initializer remains the faster and more ergonomic path for record-shaped data.
public struct TableRow: Hashable, Sendable {
  public var cells: [TableCell]
  public var configuration: TableRowConfiguration

  public init(
    _ cells: [TableCell],
    style: Style = .plain,
    height: Int = 1,
    topMargin: Int = 0,
    bottomMargin: Int = 0
  ) {
    self.cells = cells
    configuration = TableRowConfiguration(
      style: style,
      height: height,
      topMargin: topMargin,
      bottomMargin: bottomMargin
    )
  }

  public init(
    style: Style = .plain,
    height: Int = 1,
    topMargin: Int = 0,
    bottomMargin: Int = 0,
    @TableCellBuilder cells: () -> [TableCell]
  ) {
    self.init(
      cells(),
      style: style,
      height: height,
      topMargin: topMargin,
      bottomMargin: bottomMargin
    )
  }
}

/// Per-row geometry and style, corresponding to TermLoom's row-owned presentation.
public struct TableRowConfiguration: Hashable, Sendable {
  public var style: Style
  public var height: Int
  public var topMargin: Int
  public var bottomMargin: Int

  public init(
    style: Style = .plain,
    height: Int = 1,
    topMargin: Int = 0,
    bottomMargin: Int = 0
  ) {
    self.style = style
    self.height = max(0, height)
    self.topMargin = max(0, topMargin)
    self.bottomMargin = max(0, bottomMargin)
  }

  fileprivate var normalized: Self {
    Self(style: style, height: height, topMargin: topMargin, bottomMargin: bottomMargin)
  }

  fileprivate var totalHeight: Int {
    let (heightAndTop, topOverflow) = height.addingReportingOverflow(topMargin)
    guard !topOverflow else { return .max }
    let (total, bottomOverflow) = heightAndTop.addingReportingOverflow(bottomMargin)
    return bottomOverflow ? .max : total
  }

  public static let hidden = Self(height: 0)
}

public struct TableColumn<Row> {
  public var title: Line {
    didSet {
      headerLines = [title]
      plainTitle = nil
    }
  }
  public var footer: Line? {
    didSet {
      footerLines = footer.map { [$0] }
      plainFooter = nil
    }
  }
  public var constraint: Constraint {
    didSet { usesAutomaticWidth = false }
  }
  /// Overrides the alignment carried by each rich line when non-`nil`.
  public var alignment: Alignment?
  public var style: Style
  public var headerCellStyle: Style
  public var footerCellStyle: Style
  fileprivate var plainTitle: String?
  fileprivate var plainFooter: String?
  fileprivate var headerLines: [Line]
  fileprivate var footerLines: [Line]?
  fileprivate var usesAutomaticWidth: Bool
  private let plainValue: ((Row) -> String)?
  private let plainSpan: ((Row) -> Int)?
  private let richValue: ((Row) -> TableCell)?

  public init<Value>(
    _ title: String,
    value keyPath: KeyPath<Row, Value>,
    footer: String? = nil,
    width: Constraint? = nil,
    alignment: Alignment = .leading,
    style: Style = .plain,
    headerCellStyle: Style = .plain,
    footerCellStyle: Style = .plain,
    format: @escaping (Value) -> String = { String(describing: $0) },
    columnSpan: @escaping (Row) -> Int = { _ in 1 }
  ) {
    self.title = Line(title)
    self.footer = footer.map(Line.init)
    constraint = width ?? .fill
    self.alignment = alignment
    self.style = style
    self.headerCellStyle = headerCellStyle
    self.footerCellStyle = footerCellStyle
    plainTitle = title
    plainFooter = footer
    headerLines = [Line(title)]
    footerLines = footer.map { [Line($0)] }
    usesAutomaticWidth = width == nil
    plainValue = { format($0[keyPath: keyPath]) }
    plainSpan = columnSpan
    richValue = nil
  }

  public init(
    _ title: String,
    footer: String? = nil,
    width: Constraint? = nil,
    alignment: Alignment = .leading,
    style: Style = .plain,
    headerCellStyle: Style = .plain,
    footerCellStyle: Style = .plain,
    value: @escaping (Row) -> String,
    columnSpan: @escaping (Row) -> Int = { _ in 1 }
  ) {
    self.title = Line(title)
    self.footer = footer.map(Line.init)
    constraint = width ?? .fill
    self.alignment = alignment
    self.style = style
    self.headerCellStyle = headerCellStyle
    self.footerCellStyle = footerCellStyle
    plainTitle = title
    plainFooter = footer
    headerLines = [Line(title)]
    footerLines = footer.map { [Line($0)] }
    usesAutomaticWidth = width == nil
    plainValue = value
    plainSpan = columnSpan
    richValue = nil
  }

  /// Creates a column whose header, footer, and row values can contain styled spans and independent
  /// line alignment. Pass `alignment` to override the alignment carried by every line.
  public init(
    _ title: Line,
    footer: Line? = nil,
    width: Constraint? = nil,
    alignment: Alignment? = nil,
    style: Style = .plain,
    headerCellStyle: Style = .plain,
    footerCellStyle: Style = .plain,
    lines: @escaping (Row) -> [Line],
    columnSpan: @escaping (Row) -> Int = { _ in 1 }
  ) {
    self.title = title
    self.footer = footer
    constraint = width ?? .fill
    self.alignment = alignment
    self.style = style
    self.headerCellStyle = headerCellStyle
    self.footerCellStyle = footerCellStyle
    plainTitle = nil
    plainFooter = nil
    headerLines = [title]
    footerLines = footer.map { [$0] }
    usesAutomaticWidth = width == nil
    plainValue = nil
    plainSpan = nil
    richValue = { row in
      let cellLines = lines(row)
      return TableCell(cellLines, columnSpan: columnSpan(row))
    }
  }

  /// Creates a column with fully dynamic cell content, style, and column span.
  public init(
    _ title: Line,
    footer: Line? = nil,
    width: Constraint? = nil,
    alignment: Alignment? = nil,
    style: Style = .plain,
    headerCellStyle: Style = .plain,
    footerCellStyle: Style = .plain,
    cell: @escaping (Row) -> TableCell
  ) {
    self.title = title
    self.footer = footer
    constraint = width ?? .fill
    self.alignment = alignment
    self.style = style
    self.headerCellStyle = headerCellStyle
    self.footerCellStyle = footerCellStyle
    plainTitle = nil
    plainFooter = nil
    headerLines = [title]
    footerLines = footer.map { [$0] }
    usesAutomaticWidth = width == nil
    plainValue = nil
    plainSpan = nil
    richValue = cell
  }

  /// Creates a column with multi-line rich header and footer cells.
  public init(
    header: [Line],
    footer: [Line]? = nil,
    width: Constraint? = nil,
    alignment: Alignment? = nil,
    style: Style = .plain,
    headerCellStyle: Style = .plain,
    footerCellStyle: Style = .plain,
    cell: @escaping (Row) -> TableCell
  ) {
    title = header.first ?? Line("")
    self.footer = footer?.first
    constraint = width ?? .fill
    self.alignment = alignment
    self.style = style
    self.headerCellStyle = headerCellStyle
    self.footerCellStyle = footerCellStyle
    plainTitle = nil
    plainFooter = nil
    headerLines = header
    footerLines = footer
    usesAutomaticWidth = width == nil
    plainValue = nil
    plainSpan = nil
    richValue = cell
  }

  fileprivate func plainCell(for row: Row) -> (content: String, columnSpan: Int)? {
    guard let plainValue, let plainSpan else { return nil }
    return (plainValue(row), max(1, plainSpan(row)))
  }

  fileprivate func richCell(for row: Row) -> TableCell? {
    richValue?(row)
  }

  fileprivate func aligned(_ line: Line) -> Line {
    alignment.map { line.alignment($0) } ?? line
  }

}

@resultBuilder
public enum TableColumnBuilder<Row> {
  public static func buildExpression(_ expression: TableColumn<Row>) -> [TableColumn<Row>] {
    [expression]
  }

  public static func buildBlock(_ components: [TableColumn<Row>]...) -> [TableColumn<Row>] {
    components.flatMap { $0 }
  }

  public static func buildOptional(_ component: [TableColumn<Row>]?) -> [TableColumn<Row>] {
    component ?? []
  }

  public static func buildEither(first component: [TableColumn<Row>]) -> [TableColumn<Row>] {
    component
  }

  public static func buildEither(second component: [TableColumn<Row>]) -> [TableColumn<Row>] {
    component
  }

  public static func buildArray(_ components: [[TableColumn<Row>]]) -> [TableColumn<Row>] {
    components.flatMap { $0 }
  }
}

public struct Table<Row>: Widget, StatefulWidget {
  public var rows: [Row]
  public var columns: [TableColumn<Row>]
  /// The base style applied to the entire table area before row and cell styles.
  public var style: Style
  public var headerStyle: Style
  public var footerStyle: Style
  public var headerConfiguration: TableRowConfiguration
  public var footerConfiguration: TableRowConfiguration
  public var selectedStyle: Style
  public var selectedColumnStyle: Style
  public var selectedCellStyle: Style
  public var selectedRow: Int?
  /// Rich selection text rendered down the selected row and measured by its widest line.
  public var highlightSymbols: [Line]
  /// The first selection line, retained as the convenient single-line API.
  public var highlightSymbol: Line {
    get { highlightSymbols.first ?? Line("") }
    set { highlightSymbols = [newValue] }
  }
  public var highlightSpacing: HighlightSpacing
  public var columnSpacing: Int { didSet { columnSpacing = max(0, columnSpacing) } }
  public var flex: Flex
  public var rowSpacing: Int { didSet { rowSpacing = max(0, rowSpacing) } }
  private let rowStyle: ((Row) -> Style)?
  private let rowHeight: ((Row) -> Int)?
  private let rowConfiguration: ((Row) -> TableRowConfiguration)?
  private let rowCells: ((Row) -> [TableCell])?
  private let rawWidths: [Constraint]?
  private let rawHeader: TableRow?
  private let rawFooter: TableRow?

  public init(
    _ rows: [Row],
    selectedRow: Int? = nil,
    style: Style = .plain,
    headerStyle: Style = Style(modifiers: [.bold]),
    footerStyle: Style = Style(modifiers: [.bold]),
    headerConfiguration: TableRowConfiguration = TableRowConfiguration(),
    footerConfiguration: TableRowConfiguration = TableRowConfiguration(),
    selectedStyle: Style = Style(modifiers: [.reversed]),
    selectedColumnStyle: Style = .plain,
    selectedCellStyle: Style = Style(modifiers: [.bold]),
    highlightSymbol: Line = Line(""),
    highlightSymbols: [Line] = [],
    highlightSpacing: HighlightSpacing = .whenSelected,
    columnSpacing: Int = 1,
    flex: Flex = .start,
    rowSpacing: Int = 0,
    rowStyle: ((Row) -> Style)? = nil,
    rowHeight: ((Row) -> Int)? = nil,
    rowConfiguration: ((Row) -> TableRowConfiguration)? = nil,
    @TableColumnBuilder<Row> columns: () -> [TableColumn<Row>]
  ) {
    self.rows = rows
    self.columns = columns()
    self.style = style
    self.headerStyle = headerStyle
    self.footerStyle = footerStyle
    self.headerConfiguration = headerConfiguration
    self.footerConfiguration = footerConfiguration
    self.selectedStyle = selectedStyle
    self.selectedColumnStyle = selectedColumnStyle
    self.selectedCellStyle = selectedCellStyle
    self.selectedRow = selectedRow
    self.highlightSymbols = highlightSymbols.isEmpty ? [highlightSymbol] : highlightSymbols
    self.highlightSpacing = highlightSpacing
    self.columnSpacing = max(0, columnSpacing)
    self.flex = flex
    self.rowSpacing = max(0, rowSpacing)
    self.rowStyle = rowStyle
    self.rowHeight = rowHeight
    self.rowConfiguration = rowConfiguration
    rowCells = nil
    rawWidths = nil
    rawHeader = nil
    rawFooter = nil
  }

  public func render(in area: Rect, into frame: inout Frame) {
    var state = TableState(selectedRow: selectedRow)
    render(in: area, into: &frame, state: &state)
  }

  public func render(
    in area: Rect,
    into frame: inout Frame,
    state: inout TableState
  ) {
    Self.patch(style, in: area, into: &frame.buffer)
    guard !area.isEmpty else { return }
    let resolvedRowCells = rowCells.map { cells in rows.map(cells) }
    let logicalColumnCount: Int
    if let resolvedRowCells {
      logicalColumnCount = max(
        resolvedRowCells.lazy.map(\.count).max() ?? 0,
        max(rawHeader?.cells.count ?? 0, rawFooter?.cells.count ?? 0)
      )
    } else {
      logicalColumnCount = columns.count
    }
    let layoutColumnCount =
      rawWidths?.isEmpty == false ? rawWidths?.count ?? 0 : logicalColumnCount
    let highlightWidth = highlightSymbols.lazy.map(\.width).max() ?? 0
    let reservesSelectionColumn =
      highlightSpacing.reservesColumn(hasSelection: state.selectedRow != nil)
      && highlightWidth > 0
    let selectionWidth =
      reservesSelectionColumn ? min(area.width, highlightWidth) : 0
    let columnsArea = Rect(
      x: (area.x + selectionWidth),
      y: area.y,
      width: (area.width - selectionWidth),
      height: area.height
    )
    let columnAreas: [Rect]
    if let rawWidths, !rawWidths.isEmpty {
      columnAreas = Self.resolveColumnAreas(
        in: columnsArea,
        constraints: rawWidths,
        spacing: columnSpacing,
        flex: flex
      )
    } else if rawWidths != nil || columns.allSatisfy(\.usesAutomaticWidth) {
      let defaultWidth = logicalColumnCount > 0 ? area.width / logicalColumnCount : 0
      let defaultLengths = Array(repeating: defaultWidth, count: layoutColumnCount)
      if flex == .start {
        columnAreas = Self.fixedColumnAreas(
          in: columnsArea,
          requestedLengths: defaultLengths,
          spacing: columnSpacing
        )
      } else {
        columnAreas = Layout(
          .horizontal,
          constraints: defaultLengths.map { .length(($0)) },
          spacing: .space(columnSpacing),
          flex: flex
        ).split(columnsArea)
      }
    } else {
      columnAreas = Self.resolveColumnAreas(
        in: columnsArea,
        constraints: columns.map(\.constraint),
        spacing: columnSpacing,
        flex: flex
      )
    }

    let hasFooter = rawFooter != nil || columns.contains { $0.footerLines != nil }
    let headerConfiguration = self.headerConfiguration.normalized
    let footerConfiguration =
      hasFooter ? self.footerConfiguration.normalized : TableRowConfiguration(height: 0)
    let bands: (header: Rect, rows: Rect, footer: Rect)
    let defaultFooterConfiguration =
      hasFooter ? TableRowConfiguration() : TableRowConfiguration(height: 0)
    if area.height == 1, headerConfiguration.totalHeight > 0,
      footerConfiguration.totalHeight > 0
    {
      let emptyBand = Rect(x: area.x, y: area.y, width: area.width, height: 0)
      bands = (emptyBand, emptyBand, emptyBand)
    } else if headerConfiguration == TableRowConfiguration(),
      footerConfiguration == defaultFooterConfiguration,
      area.height >= 1 + (hasFooter ? 1 : 0)
    {
      let headerHeight = min(area.height, 1)
      let footerHeight: Int = hasFooter ? min(area.height, 1) : 0
      bands = (
        Rect(x: area.x, y: area.y, width: area.width, height: headerHeight),
        Rect(
          x: area.x,
          y: (area.y + headerHeight),
          width: area.width,
          height: (max(0, area.height - headerHeight - footerHeight))
        ),
        Rect(
          x: area.x,
          y: (area.bottom - footerHeight),
          width: area.width,
          height: footerHeight
        )
      )
    } else {
      let verticalAreas = Layout.vertical(
        .length(headerConfiguration.topMargin),
        .length(headerConfiguration.height),
        .length(headerConfiguration.bottomMargin),
        .min(0),
        .length(footerConfiguration.topMargin),
        .length(footerConfiguration.height),
        .length(footerConfiguration.bottomMargin)
      ).split(area)
      bands = (verticalAreas[1], verticalAreas[3], verticalAreas[5])
    }
    let headerBand = bands.header
    let rowBand = bands.rows
    let footerBand = bands.footer
    let resolvedHeaderStyle =
      style
      .patching(headerStyle)
      .patching(headerConfiguration.style)
    let resolvedFooterStyle =
      style
      .patching(footerStyle)
      .patching(footerConfiguration.style)

    if let rawHeader {
      Self.patch(resolvedHeaderStyle, in: headerBand, into: &frame.buffer)
      for (cell, columnArea) in zip(rawHeader.cells, columnAreas) {
        Self.render(
          cell,
          baseStyle: resolvedHeaderStyle,
          in: Rect(
            x: columnArea.x,
            y: headerBand.y,
            width: columnArea.width,
            height: headerBand.height
          ),
          into: &frame.buffer,
          environment: frame.environment
        )
      }
    } else {
      for (column, columnArea) in zip(columns, columnAreas) {
        let headerArea = Rect(
          x: columnArea.x,
          y: headerBand.y,
          width: columnArea.width,
          height: headerBand.height
        )
        let headerCellStyle = resolvedHeaderStyle.patching(column.headerCellStyle)
        Self.patch(headerCellStyle, in: headerArea, into: &frame.buffer)
        if let title = column.plainTitle {
          Self.renderPlainLine(
            title,
            style: headerCellStyle,
            alignment: column.alignment ?? .leading,
            in: headerArea,
            into: &frame.buffer
          )
        } else {
          Self.render(
            column.headerLines.map { column.aligned($0).patchStyle(headerCellStyle) },
            in: headerArea,
            into: &frame.buffer,
            environment: frame.environment
          )
        }
      }
    }

    let viewportHeight = rowBand.height
    if logicalColumnCount == 0 {
      state.selectedColumn = nil
    } else if let selectedColumn = state.selectedColumn {
      state.selectedColumn = min(max(0, selectedColumn), logicalColumnCount - 1)
    }
    let rowConfigurations: [TableRowConfiguration]?
    if rowConfiguration != nil || rowStyle != nil || rowHeight != nil || rowSpacing > 0 {
      rowConfigurations = rows.map { row in
        if let rowConfiguration {
          return rowConfiguration(row).normalized
        }
        return TableRowConfiguration(
          style: rowStyle?(row) ?? .plain,
          height: rowHeight.map { max(0, $0(row)) } ?? 1,
          bottomMargin: Int(rowSpacing)
        )
      }
    } else {
      rowConfigurations = nil
    }
    let visible: Range<Int>
    if let rowConfigurations {
      visible = state.visibleRows(
        rowHeights: rowConfigurations.map(\.totalHeight),
        rowContentHeights: rowConfigurations.map(\.height),
        viewportHeight: viewportHeight
      )
    } else {
      let visibleCount = viewportHeight
      state.reconcile(
        rowCount: rows.count,
        columnCount: logicalColumnCount,
        viewportLength: visibleCount
      )
      visible = state.offset..<min(rows.count, state.offset + visibleCount)
    }
    var consumedHeight = 0
    var selectedRowArea: Rect?
    for rowIndex in visible {
      let row = rows[rowIndex]
      let configuration = rowConfigurations?[rowIndex] ?? TableRowConfiguration()
      let rowY = (rowBand.y + consumedHeight + configuration.topMargin)
      let contentHeight = configuration.height
      consumedHeight += configuration.totalHeight
      let baseStyle = style.patching(configuration.style)
      let rowArea = Rect(
        x: area.x,
        y: rowY,
        width: area.width,
        height: contentHeight
      )
      Self.patch(baseStyle, in: rowArea, into: &frame.buffer)
      if rowIndex == state.selectedRow {
        selectedRowArea = rowArea
        if selectionWidth > 0 {
          Self.render(
            highlightSymbols.map { $0.patchStyle(baseStyle) },
            in: Rect(
              x: area.x,
              y: rowY,
              width: selectionWidth,
              height: contentHeight
            ),
            into: &frame.buffer,
            environment: frame.environment
          )
        }
      }
      if let cells = resolvedRowCells?[rowIndex] {
        Self.renderSequentialCells(
          cells,
          columnAreas: columnAreas,
          rowY: rowY,
          contentHeight: contentHeight,
          baseStyle: baseStyle,
          into: &frame.buffer,
          environment: frame.environment
        )
      } else {
        var columnIndex = 0
        while columnIndex < min(columns.count, columnAreas.count) {
          let column = columns[columnIndex]
          let plainCell = column.plainCell(for: row)
          let richCell = plainCell == nil ? column.richCell(for: row) : nil
          let span = min(
            plainCell?.columnSpan ?? max(1, richCell?.columnSpan ?? 1),
            columns.count - columnIndex
          )
          let finalColumnIndex = min(columnAreas.count - 1, columnIndex + span - 1)
          let firstArea = columnAreas[columnIndex]
          let finalArea = columnAreas[finalColumnIndex]
          let columnArea = Rect(
            x: firstArea.x,
            y: firstArea.y,
            width: (finalArea.right - firstArea.x),
            height: firstArea.height
          )
          let cellArea = Rect(
            x: columnArea.x,
            y: rowY,
            width: columnArea.width,
            height: contentHeight
          )
          let configuredCellStyle = column.style.patching(richCell?.style ?? .plain)
          Self.patch(configuredCellStyle, in: cellArea, into: &frame.buffer)
          let cellStyle = baseStyle.patching(configuredCellStyle)
          if let plainCell {
            Self.renderPlain(
              plainCell.content,
              style: cellStyle,
              alignment: column.alignment ?? .leading,
              contentHeight: contentHeight,
              in: cellArea,
              into: &frame.buffer
            )
          } else if let richCell {
            for (lineIndex, line) in richCell.lines.prefix(contentHeight).enumerated() {
              Self.render(
                column.aligned(line).patchStyle(cellStyle),
                in: Rect(
                  x: columnArea.x,
                  y: (rowY + lineIndex),
                  width: columnArea.width,
                  height: 1
                ),
                into: &frame.buffer,
                environment: frame.environment
              )
            }
          }
          columnIndex += span
        }
      }
    }

    let rowsArea = Rect(
      x: columnsArea.x,
      y: rowBand.y,
      width: columnsArea.width,
      height: rowBand.height
    )
    let selectedColumnArea = state.selectedColumn.flatMap { selectedColumn in
      columnAreas.indices.contains(selectedColumn)
        ? Rect(
          x: columnAreas[selectedColumn].x,
          y: rowsArea.y,
          width: columnAreas[selectedColumn].width,
          height: rowsArea.height
        )
        : nil
    }
    if let selectedRowArea {
      Self.patch(selectedStyle, in: selectedRowArea, into: &frame.buffer)
    }
    if let selectedColumnArea {
      Self.patch(selectedColumnStyle, in: selectedColumnArea, into: &frame.buffer)
    }
    if let selectedRowArea, let selectedColumnArea {
      Self.patch(
        selectedCellStyle,
        in: selectedRowArea.intersection(selectedColumnArea),
        into: &frame.buffer
      )
    }

    if hasFooter {
      if let rawFooter {
        Self.patch(resolvedFooterStyle, in: footerBand, into: &frame.buffer)
        for (cell, columnArea) in zip(rawFooter.cells, columnAreas) {
          Self.render(
            cell,
            baseStyle: resolvedFooterStyle,
            in: Rect(
              x: columnArea.x,
              y: footerBand.y,
              width: columnArea.width,
              height: footerBand.height
            ),
            into: &frame.buffer,
            environment: frame.environment
          )
        }
      } else {
        for (column, columnArea) in zip(columns, columnAreas) {
          let footerArea = Rect(
            x: columnArea.x,
            y: footerBand.y,
            width: columnArea.width,
            height: footerBand.height
          )
          let footerCellStyle = resolvedFooterStyle.patching(column.footerCellStyle)
          Self.patch(footerCellStyle, in: footerArea, into: &frame.buffer)
          if let footer = column.plainFooter {
            Self.renderPlainLine(
              footer,
              style: footerCellStyle,
              alignment: column.alignment ?? .leading,
              in: footerArea,
              into: &frame.buffer
            )
          } else {
            Self.render(
              (column.footerLines ?? []).map {
                column.aligned($0).patchStyle(footerCellStyle)
              },
              in: footerArea,
              into: &frame.buffer,
              environment: frame.environment
            )
          }
        }
      }
    }
  }

  /// Returns a copy with rich, potentially multi-line selection text.
  public func withHighlightSymbols(@LineBuilder _ symbols: () -> [Line]) -> Self {
    var copy = self
    let lines = symbols()
    copy.highlightSymbols = lines
    return copy
  }

  private static func renderSequentialCells(
    _ cells: [TableCell],
    columnAreas: [Rect],
    rowY: Int,
    contentHeight: Int,
    baseStyle: Style,
    into buffer: inout Buffer,
    environment: RenderEnvironment
  ) {
    var columnIndex = 0
    for cell in cells {
      guard columnIndex < columnAreas.count else { break }
      let span = min(cell.columnSpan, columnAreas.count - columnIndex)
      guard span > 0 else { continue }
      let firstArea = columnAreas[columnIndex]
      let finalArea = columnAreas[columnIndex + span - 1]
      render(
        cell,
        baseStyle: baseStyle,
        in: Rect(
          x: firstArea.x,
          y: rowY,
          width: (finalArea.right - firstArea.x),
          height: contentHeight
        ),
        into: &buffer,
        environment: environment
      )
      columnIndex += span
    }
  }

  private static func render(
    _ cell: TableCell,
    baseStyle: Style,
    in area: Rect,
    into buffer: inout Buffer,
    environment: RenderEnvironment
  ) {
    patch(cell.style, in: area, into: &buffer)
    let cellStyle = baseStyle.patching(cell.style)
    for (lineIndex, line) in cell.lines.prefix(area.height).enumerated() {
      render(
        line.patchStyle(cellStyle),
        in: Rect(
          x: area.x,
          y: (area.y + lineIndex),
          width: area.width,
          height: 1
        ),
        into: &buffer,
        environment: environment
      )
    }
  }

  private static func render(
    _ lines: [Line],
    in area: Rect,
    into buffer: inout Buffer,
    environment: RenderEnvironment
  ) {
    for (lineIndex, line) in lines.prefix(area.height).enumerated() {
      render(
        line,
        in: Rect(
          x: area.x,
          y: (area.y + lineIndex),
          width: area.width,
          height: 1
        ),
        into: &buffer,
        environment: environment
      )
    }
  }

  private static func render(
    _ line: Line,
    in area: Rect,
    into buffer: inout Buffer,
    environment: RenderEnvironment
  ) {
    Paragraph { line }.render(in: area, into: &buffer, environment: environment)
  }

  private static func renderPlain(
    _ content: String,
    style: Style,
    alignment: Alignment,
    contentHeight: Int,
    in area: Rect,
    into buffer: inout Buffer
  ) {
    guard contentHeight > 1, content.contains("\n") else {
      renderPlainLine(content, style: style, alignment: alignment, in: area, into: &buffer)
      return
    }
    for (lineIndex, line) in content.split(separator: "\n", omittingEmptySubsequences: false)
      .prefix(contentHeight).enumerated()
    {
      renderPlainLine(
        String(line),
        style: style,
        alignment: alignment,
        in: Rect(
          x: area.x,
          y: (area.y + lineIndex),
          width: area.width,
          height: 1
        ),
        into: &buffer
      )
    }
  }

  /// Keeps the common key-path table path allocation-free while preserving
  /// the exact alignment and wide-glyph clipping semantics of `Line`.
  private static func renderPlainLine(
    _ content: String,
    style: Style,
    alignment: Alignment,
    in area: Rect,
    into buffer: inout Buffer
  ) {
    let area = area.intersection(buffer.area)
    guard !area.isEmpty else { return }
    if style != .plain { buffer.setStyle(style, in: area) }

    let contentWidth = TerminalWidth.of(content)
    guard contentWidth > 0 else { return }
    let areaWidth = area.width
    let leadingSkip: Int
    let indent: Int
    if contentWidth <= areaWidth {
      leadingSkip = 0
      indent =
        switch alignment {
        case .leading: 0
        case .center: (areaWidth - contentWidth) / 2
        case .trailing: areaWidth - contentWidth
        }
    } else {
      indent = 0
      leadingSkip =
        switch alignment {
        case .leading: 0
        case .center: (contentWidth - areaWidth) / 2
        case .trailing: contentWidth - areaWidth
        }
    }

    var skipped = 0
    var position = Position(x: (area.x + indent), y: area.y)
    let end = area.x + area.width
    if leadingSkip == 0 {
      buffer.setString(
        content,
        at: position,
        style: style,
        maxWidth: (end - position.x)
      )
      return
    }
    for character in content {
      let characterWidth = TerminalWidth.of(character)
      if skipped < leadingSkip {
        let endOfCharacter = skipped + characterWidth
        if endOfCharacter > leadingSkip {
          position.x = (position.x + endOfCharacter - leadingSkip)
        }
        skipped = endOfCharacter
        continue
      }
      guard characterWidth > 0 else { continue }
      guard position.x + characterWidth <= end else { return }
      position = buffer.setString(
        String(character),
        at: position,
        style: style,
        maxWidth: (end - position.x)
      )
    }
  }

  private static func patch(_ style: Style, in area: Rect, into buffer: inout Buffer) {
    guard style != .plain else { return }
    buffer.setStyle(style, in: area)
  }

  private static func fixedLengths(_ constraints: [Constraint]) -> [Int]? {
    let lengths = constraints.compactMap { constraint -> Int? in
      guard case .length(let value) = constraint else { return nil }
      return Int(value)
    }
    return lengths.count == constraints.count ? lengths : nil
  }

  /// Table columns use TermLoom's solver boundaries, which intentionally differ
  /// from a general stack layout when equal-priority constraints compete.
  static func resolveColumnAreas(
    in area: Rect,
    constraints: [Constraint],
    spacing: Int,
    flex: Flex
  ) -> [Rect] {
    guard !constraints.isEmpty else { return [] }
    let homogeneousMinimums = constraints.allSatisfy {
      if case .min = $0 { true } else { false }
    }
    guard flex == .start || (flex == .spaceBetween && homogeneousMinimums) else {
      return Layout(
        .horizontal,
        constraints: constraints,
        spacing: .space(spacing),
        flex: flex
      ).split(area)
    }

    if let lengths = fixedLengths(constraints) {
      return fixedColumnAreas(in: area, requestedLengths: lengths, spacing: spacing)
    }
    if constraints.allSatisfy({ if case .max = $0 { true } else { false } }) {
      let lengths = constraints.map { constraint in
        guard case .max(let value) = constraint else { return 0 }
        return Int(value)
      }
      return fixedColumnAreas(in: area, requestedLengths: lengths, spacing: spacing)
    }
    if homogeneousMinimums {
      let minimums: [Double] = constraints.map { constraint in
        guard case .min(let value) = constraint else { return 0.0 }
        return Double(value)
      }
      return fractionalColumnAreas(
        in: area,
        requestedLengths: waterFilledMinimums(
          minimums, total: availableWidth(in: area, spacing: spacing, count: constraints.count)),
        spacing: spacing,
        fillWhenOverconstrained: true
      )
    }
    if constraints.allSatisfy({ if case .percentage = $0 { true } else { false } }) {
      let extent = Double(area.width)
      let lengths: [Double] = constraints.map { constraint in
        guard case .percentage(let value) = constraint else { return 0.0 }
        return extent * Double(value) / 100
      }
      return fractionalColumnAreas(
        in: area,
        requestedLengths: lengths,
        spacing: spacing,
        fillWhenOverconstrained: true
      )
    }
    if constraints.allSatisfy({ if case .ratio = $0 { true } else { false } }) {
      let extent = Double(area.width)
      let lengths: [Double] = constraints.map { constraint in
        guard case .ratio(let numerator, let denominator) = constraint, denominator != 0 else {
          return 0.0
        }
        return extent * Double(numerator) / Double(denominator)
      }
      return fractionalColumnAreas(
        in: area,
        requestedLengths: lengths,
        spacing: spacing,
        fillWhenOverconstrained: true
      )
    }
    return Layout(
      .horizontal,
      constraints: constraints,
      spacing: .space(spacing),
      flex: flex
    ).split(area)
  }

  private static func availableWidth(in area: Rect, spacing: Int, count: Int) -> Int {
    max(0, area.width - min(area.width, max(0, count - 1) * spacing))
  }

  private static func waterFilledMinimums(_ minimums: [Double], total: Int) -> [Double] {
    guard !minimums.isEmpty else { return [] }
    let available = Double(total)
    let minimumTotal = minimums.reduce(0, +)
    guard minimumTotal <= available else { return minimums }
    var low = 0.0
    var high = max(available, minimums.max() ?? 0)
    for _ in 0..<64 {
      let level = (low + high) / 2
      if minimums.reduce(0, { $0 + max($1, level) }) > available {
        high = level
      } else {
        low = level
      }
    }
    return minimums.map { max($0, low) }
  }

  private static func fractionalColumnAreas(
    in area: Rect,
    requestedLengths: [Double],
    spacing: Int,
    fillWhenOverconstrained: Bool
  ) -> [Rect] {
    let available = availableWidth(in: area, spacing: spacing, count: requestedLengths.count)
    let requestedTotal = requestedLengths.reduce(0, +)
    let scale =
      fillWhenOverconstrained && requestedTotal > Double(available) && requestedTotal > 0
      ? Double(available) / requestedTotal
      : 1
    var previousBoundary = 0
    var cumulative = 0.0
    let lengths = requestedLengths.map { requested in
      cumulative += max(0, requested) * scale
      let boundary = min(available, Int(cumulative.rounded()))
      defer { previousBoundary = boundary }
      return max(0, boundary - previousBoundary)
    }
    var cursor = area.x
    return lengths.map { width in
      defer { cursor = min(area.right, cursor + width + spacing) }
      return Rect(
        x: cursor,
        y: area.y,
        width: width,
        height: area.height
      )
    }
  }

  /// Resolves equal-priority fixed widths using TermLoom's rounded solver boundaries.
  private static func fixedColumnAreas(
    in area: Rect,
    requestedLengths: [Int],
    spacing: Int
  ) -> [Rect] {
    guard !requestedLengths.isEmpty else { return [] }
    let gapCount = max(0, requestedLengths.count - 1)
    let totalSpacing = min(area.width, gapCount * spacing)
    let available = max(0, area.width - totalSpacing)
    let requestedTotal = requestedLengths.reduce(0, +)
    let lengths: [Int]
    if requestedTotal > available, requestedTotal > 0 {
      var cumulativeRequested = 0
      var previousBoundary = 0
      lengths = requestedLengths.map { requested in
        cumulativeRequested += requested
        let boundary = Int(
          (Double(available) * Double(cumulativeRequested) / Double(requestedTotal)).rounded()
        )
        defer { previousBoundary = boundary }
        return max(0, boundary - previousBoundary)
      }
    } else {
      lengths = requestedLengths
    }
    var cursor = area.x
    return lengths.map { width in
      defer { cursor = min(area.right, cursor + width + spacing) }
      return Rect(
        x: cursor,
        y: area.y,
        width: width,
        height: area.height
      )
    }
  }
}
