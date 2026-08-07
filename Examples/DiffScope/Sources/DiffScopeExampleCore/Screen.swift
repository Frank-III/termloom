import Ratatui
import RatatuiOverlays

public struct DiffScopeScreen: Widget, Sendable {
  public var repository: RepositorySnapshot
  public var files: [ChangedFile]
  public var selectedFileID: Int?
  public var diffLines: [DiffLine]
  public var diffScroll: Int
  public var horizontalScroll: Int
  public var focus: DiffScopeFocus
  public var query: TextFieldState
  public var isFiltering: Bool
  public var isLoadingDiff: Bool
  public var errorMessage: String?
  public var showsHelp: Bool

  public func render(in area: Rect, into frame: inout Frame) {
    guard !area.isEmpty else { return }
    frame.buffer.fill(area, with: Cell(symbol: " ", style: Style(background: DiffScopeTheme.dark)))
    let regions = layout(in: area)
    renderHeader(in: regions.header, into: &frame)
    if let filesArea = regions.files {
      renderFiles(in: filesArea, into: &frame)
    }
    if let diffArea = regions.diff {
      renderDiff(in: diffArea, into: &frame)
    }
    renderFooter(in: regions.footer, into: &frame)
    if showsHelp {
      renderHelp(in: area, into: &frame)
      frame.placeCursor(at: nil)
    }
  }

  private struct Regions {
    var header: Rect
    var files: Rect?
    var diff: Rect?
    var footer: Rect
    var isCompact: Bool
  }

  private func layout(in area: Rect) -> Regions {
    let rows = Layout(
      .vertical,
      constraints: [.length(area.height > 8 ? 2 : 1), .flex(1), .length(1)]
    ).split(area)
    let compact = area.width < 88
    if compact {
      return Regions(
        header: rows[0],
        files: focus == .files ? rows[1] : nil,
        diff: focus == .diff ? rows[1] : nil,
        footer: rows[2],
        isCompact: true)
    }
    let columns = Layout(.horizontal, constraints: [.percentage(36), .flex(1)]).split(rows[1])
    return Regions(
      header: rows[0], files: columns[0], diff: columns[1], footer: rows[2], isCompact: false)
  }

  private func paneBlock(_ title: String, focused: Bool) -> Block<EmptyWidget> {
    Block(
      title: title,
      style: Style(background: DiffScopeTheme.panel),
      borderStyle: Style(foreground: focused ? DiffScopeTheme.accent : DiffScopeTheme.border),
      titleStyle: Style(
        foreground: focused ? DiffScopeTheme.accent : DiffScopeTheme.pale,
        modifiers: focused ? [.bold] : []))
  }

  private func renderHeader(
    in area: Rect,
    into frame: inout Frame
  ) {
    guard !area.isEmpty else { return }
    Line([
      Span(
        " DIFFSCOPE ",
        style: Style(
          foreground: DiffScopeTheme.dark,
          background: DiffScopeTheme.accent,
          modifiers: [.bold])),
      Span(
        "  \(repository.title)",
        style: Style(foreground: DiffScopeTheme.foreground, modifiers: [.bold])),
      Span(" · \(repository.subtitle)", style: Style(foreground: DiffScopeTheme.dim)),
    ]).render(
      in: Rect(x: area.x, y: area.y, width: area.width, height: 1), into: &frame)
    if area.height > 1 {
      Line(
        [
          Span("   \(repository.branch)", style: Style(foreground: DiffScopeTheme.purple)),
          Span(
            "   \(repository.files.count.formatted()) files",
            style: Style(foreground: DiffScopeTheme.pale)),
          repository.aggregateStatsAvailable
            ? Span(
              "   +\(repository.additions.formatted())",
              style: Style(foreground: DiffScopeTheme.green)) : nil,
          repository.aggregateStatsAvailable
            ? Span(
              "  -\(repository.deletions.formatted())",
              style: Style(foreground: DiffScopeTheme.red)) : nil,
          repository.commits.map {
            Span("   \($0) commits", style: Style(foreground: DiffScopeTheme.dim))
          },
          repository.isDemonstration
            ? Span("   synthetic patches", style: Style(foreground: DiffScopeTheme.orange)) : nil,
        ].compactMap { $0 }
      ).render(
        in: Rect(x: area.x, y: area.y + 1, width: area.width, height: 1),
        into: &frame)
    }
  }

  private func filesContentArea(in area: Rect) -> Rect {
    let inner = paneBlock("", focused: false).inner(area)
    return Rect(
      x: inner.x,
      y: inner.y + min(1, inner.height),
      width: inner.width,
      height: inner.height > 1 ? inner.height - 1 : 0)
  }

  private func renderFiles(
    in area: Rect,
    into frame: inout Frame
  ) {
    let block = paneBlock(
      " Files \(files.count)/\(repository.files.count) ", focused: focus == .files)
    block.render(in: area, into: &frame)
    let inner = block.inner(area)
    guard !inner.isEmpty else { return }
    let filterStyle = isFiltering ? DiffScopeTheme.accent : DiffScopeTheme.dim
    Line([
      Span(
        " Filter ", style: Style(foreground: filterStyle, modifiers: isFiltering ? [.bold] : [])),
      Span(
        query.text.isEmpty ? "press /" : query.text,
        style: Style(
          foreground: query.text.isEmpty ? DiffScopeTheme.dim : DiffScopeTheme.foreground)),
    ]).render(
      in: Rect(x: inner.x, y: inner.y, width: inner.width, height: 1),
      into: &frame)
    if isFiltering, !showsHelp, inner.width > 9 {
      let prefix = String(query.text.prefix(query.cursor))
      frame.placeCursor(
        at: Position(
          x: (inner.x + 8
            + min(TerminalWidth.of(prefix), inner.width - 9)),
          y: inner.y),
        style: .steadyBar)
    }

    let content = filesContentArea(in: area)
    guard !content.isEmpty else { return }
    guard !files.isEmpty else {
      Text("No files match \"\(query.text)\"", alignment: .center)
        .foregroundStyle(DiffScopeTheme.dim)
        .render(in: content, into: &frame)
      return
    }
    let viewport = fileViewport(capacity: content.height)
    for (row, index) in viewport.range.enumerated() {
      let file = files[index]
      let y = (content.y + row)
      let isSelected = file.id == selectedFileID
      if !showsHelp {
        frame.addInteraction(
          InteractionRegion(
            control: ControlID("diffscope-file-\(file.id)"),
            area: Rect(x: content.x, y: y, width: content.width, height: 1),
            action: ActionID("file:\(file.id)"),
            isFocusable: false))
      }
      if isSelected {
        frame.buffer.fill(
          Rect(x: content.x, y: y, width: content.width, height: 1),
          with: Cell(symbol: " ", style: Style(background: DiffScopeTheme.selection)))
      }
      let marker = isSelected ? "›" : " "
      let status = file.kind.rawValue
      let stats = "+\(file.additions) -\(file.deletions)"
      let prefixWidth = 5
      let statsWidth =
        repository.aggregateStatsAvailable
        ? min(15, max(0, content.width - prefixWidth)) : 0
      let pathWidth = max(0, content.width - prefixWidth - statsWidth)
      Line([
        Span(
          "\(marker) ",
          style: Style(foreground: DiffScopeTheme.accent, modifiers: isSelected ? [.bold] : [])),
        Span(
          "\(status) ",
          style: Style(foreground: DiffScopeTheme.change(file.kind), modifiers: [.bold])),
        Span(
          file.path,
          style: Style(foreground: isSelected ? DiffScopeTheme.foreground : DiffScopeTheme.pale)),
      ]).render(
        in: Rect(x: content.x, y: y, width: (prefixWidth + pathWidth), height: 1),
        into: &frame)
      if statsWidth > 0 {
        Line(stats, style: Style(foreground: DiffScopeTheme.dim), alignment: .trailing)
          .render(
            in: Rect(
              x: (content.right - statsWidth),
              y: y,
              width: statsWidth,
              height: 1),
            into: &frame)
      }
    }
    Scrollbar(
      contentLength: files.count,
      viewportLength: content.height,
      position: viewport.range.lowerBound,
      orientation: .verticalRight,
      style: Style(foreground: DiffScopeTheme.border),
      thumbStyle: Style(foreground: DiffScopeTheme.accent)
    ).render(in: content, into: &frame)
  }

  private func fileViewport(capacity: Int) -> SelectionViewport {
    let selected = selectedFileID.flatMap { id in files.firstIndex { $0.id == id } } ?? 0
    return SelectionViewport.fitting(
      itemHeights: Array(repeating: 1, count: files.count),
      selectedIndex: selected,
      capacity: capacity)
  }

  private func renderDiff(
    in area: Rect,
    into frame: inout Frame
  ) {
    let title = selectedFile.map { " Diff · \($0.path) " } ?? " Diff "
    let block = paneBlock(title, focused: focus == .diff)
    block.render(in: area, into: &frame)
    let inner = block.inner(area)
    guard !inner.isEmpty else { return }
    if let file = selectedFile {
      Line(
        [
          Span(
            " \(file.kind.label)",
            style: Style(foreground: DiffScopeTheme.change(file.kind), modifiers: [.bold])),
          repository.aggregateStatsAvailable
            ? Span("   +\(file.additions)", style: Style(foreground: DiffScopeTheme.green)) : nil,
          repository.aggregateStatsAvailable
            ? Span("  -\(file.deletions)", style: Style(foreground: DiffScopeTheme.red)) : nil,
          horizontalScroll > 0
            ? Span(
              "   column \(horizontalScroll + 1)", style: Style(foreground: DiffScopeTheme.dim))
            : nil,
        ].compactMap { $0 }
      ).render(
        in: Rect(x: inner.x, y: inner.y, width: inner.width, height: 1),
        into: &frame)
    }
    let content = Rect(
      x: inner.x,
      y: inner.y + min(1, inner.height),
      width: inner.width,
      height: inner.height > 1 ? inner.height - 1 : 0)
    guard !content.isEmpty else { return }
    if isLoadingDiff {
      Text("Loading patch…", alignment: .center)
        .foregroundStyle(DiffScopeTheme.accent)
        .render(in: content, into: &frame)
    } else if let errorMessage {
      Text("Could not load patch\n\n\(errorMessage)", alignment: .center)
        .foregroundStyle(DiffScopeTheme.red)
        .render(in: content, into: &frame)
    } else if selectedFile == nil {
      Text("Select a changed file", alignment: .center)
        .foregroundStyle(DiffScopeTheme.dim)
        .render(in: content, into: &frame)
    } else {
      let start = min(max(0, diffScroll), diffLines.count)
      let end = min(diffLines.count, start + content.height)
      let visibleLines = diffLines[start..<end].map(styledDiffLine)
      let paragraph = Paragraph(
        Text(visibleLines),
        wrap: .none,
        horizontalScroll: horizontalScroll,
        trimLeadingWhitespace: false)
      paragraph.render(in: content, into: &frame)
      Scrollbar(
        contentLength: diffLines.count,
        viewportLength: content.height,
        position: diffScroll,
        orientation: .verticalRight,
        style: Style(foreground: DiffScopeTheme.border),
        thumbStyle: Style(foreground: DiffScopeTheme.accent)
      ).render(in: content, into: &frame)
    }
  }

  private var selectedFile: ChangedFile? {
    guard let selectedFileID else { return nil }
    return repository.files.first { $0.id == selectedFileID }
  }

  private func styledDiffLine(_ diffLine: DiffLine) -> Line {
    let style: Style =
      switch diffLine.kind {
      case .header: Style(foreground: DiffScopeTheme.dim)
      case .hunk: Style(foreground: DiffScopeTheme.cyan, background: Color.rgb(0x1D, 0x33, 0x44))
      case .addition:
        Style(foreground: DiffScopeTheme.green, background: Color.rgb(0x1B, 0x32, 0x27))
      case .deletion: Style(foreground: DiffScopeTheme.red, background: Color.rgb(0x3B, 0x24, 0x2C))
      case .context: Style(foreground: DiffScopeTheme.pale)
      }
    return Line(diffLine.text, style: style)
  }

  private func renderFooter(
    in area: Rect,
    into frame: inout Frame
  ) {
    let mode = isFiltering ? " FILTER " : focus == .files ? " FILES " : " DIFF "
    let hints =
      if isFiltering { "type to filter · enter apply · esc close" } else if area.width < 90 {
        "tab pane · / filter · j/k move · ? help · q quit"
      } else { "tab panes · / filter · j/k move · g/G ends · h/l columns · ? help · q quit" }
    Line([
      Span(" "),
      Span(
        mode,
        style: Style(
          foreground: DiffScopeTheme.dark,
          background: isFiltering ? DiffScopeTheme.green : DiffScopeTheme.accent,
          modifiers: [.bold])),
      Span("  \(hints)", style: Style(foreground: DiffScopeTheme.dim)),
    ]).render(in: area, into: &frame)
  }

  private func renderHelp(
    in area: Rect,
    into frame: inout Frame
  ) {
    Popup(
      layout: PopupLayout(size: .cells(width: 66, height: 19)),
      title: " DiffScope keys ",
      style: Style(foreground: DiffScopeTheme.foreground, background: DiffScopeTheme.dark),
      borderStyle: Style(foreground: DiffScopeTheme.accent),
      titleStyle: Style(foreground: DiffScopeTheme.accent, modifiers: [.bold]),
      padding: .all(1),
      scrimStyle: Style(foreground: DiffScopeTheme.dim, background: DiffScopeTheme.dark),
      content: Text(
        "Navigation\n  tab, 1 / 2          switch files · diff\n  j / k, arrows        move or scroll\n  page up / page down  move by a page\n  g / G                first · last\n\nFiles\n  /                    filter paths\n  x                    clear filter\n  mouse click          select visible file\n\nDiff\n  h / l                horizontal scroll\n  0                    first column\n\nGlobal\n  ?                    this help\n  q                    quit"
      ).foregroundStyle(DiffScopeTheme.foreground)
    ).render(in: area, into: &frame)
  }

}
