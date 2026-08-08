extension TerminalWidth {
  /// Returns the longest leading substring that fits in `columns` terminal columns.
  public static func prefix(
    _ value: String,
    fitting columns: Int,
    policy: TerminalWidthPolicy = .standard
  ) -> String {
    let columns = max(0, columns)
    guard columns > 0 else { return "" }

    return prefixProbe(value, fitting: columns, policy: policy).content
  }

  /// Returns the longest trailing substring that fits in `columns` terminal columns.
  public static func suffix(
    _ value: String,
    fitting columns: Int,
    policy: TerminalWidthPolicy = .standard
  ) -> String {
    let columns = max(0, columns)
    guard columns > 0 else { return "" }

    var characters: [Character] = []
    var used = 0
    for character in value.reversed() {
      let width = of(character, policy: policy)
      guard width <= columns - used else { break }
      characters.append(character)
      used += width
    }
    return String(characters.reversed())
  }

  /// Truncates trailing content to `columns`, optionally reserving room for an ellipsis.
  public static func truncated(
    _ value: String,
    to columns: Int,
    ellipsis: String? = "…",
    policy: TerminalWidthPolicy = .standard
  ) -> String {
    let columns = max(0, columns)
    guard columns > 0 else { return "" }
    let probe = prefixProbe(value, fitting: columns, policy: policy)
    guard probe.isTruncated else { return value }
    guard let ellipsis else { return probe.content }

    let fittedEllipsis = prefix(ellipsis, fitting: columns, policy: policy)
    let ellipsisWidth = of(fittedEllipsis, policy: policy)
    return prefix(value, fitting: columns - ellipsisWidth, policy: policy) + fittedEllipsis
  }

  /// Pads a value with spaces until it occupies at least `columns` terminal columns.
  /// Values wider than the target are returned unchanged.
  public static func padded(
    _ value: String,
    to columns: Int,
    alignment: Alignment = .leading,
    policy: TerminalWidthPolicy = .standard
  ) -> String {
    let missing = max(0, max(0, columns) - of(value, policy: policy))
    guard missing > 0 else { return value }
    let padding = paddingWidths(missing, alignment: alignment)
    return String(repeating: " ", count: padding.leading) + value
      + String(repeating: " ", count: padding.trailing)
  }

  /// Truncates and pads a value to exactly `columns` terminal columns.
  public static func fitted(
    _ value: String,
    to columns: Int,
    alignment: Alignment = .leading,
    ellipsis: String? = "…",
    policy: TerminalWidthPolicy = .standard
  ) -> String {
    padded(
      truncated(value, to: columns, ellipsis: ellipsis, policy: policy),
      to: columns,
      alignment: alignment,
      policy: policy
    )
  }

  private static func prefixProbe(
    _ value: String,
    fitting columns: Int,
    policy: TerminalWidthPolicy
  ) -> (content: String, isTruncated: Bool) {
    var boundary = value.startIndex
    var used = 0
    while boundary < value.endIndex {
      let character = value[boundary]
      let width = of(character, policy: policy)
      guard width <= columns - used else {
        return (String(value[..<boundary]), true)
      }
      used += width
      boundary = value.index(after: boundary)
    }
    return (value, false)
  }
}

extension Span {
  public func truncated(
    to columns: Int,
    ellipsis: String? = "…",
    policy: TerminalWidthPolicy = .standard
  ) -> Span {
    Span(
      TerminalWidth.truncated(content, to: columns, ellipsis: ellipsis, policy: policy),
      style: style
    )
  }

  public func fitted(
    to columns: Int,
    alignment: Alignment = .leading,
    ellipsis: String? = "…",
    policy: TerminalWidthPolicy = .standard
  ) -> Span {
    Span(
      TerminalWidth.fitted(
        content,
        to: columns,
        alignment: alignment,
        ellipsis: ellipsis,
        policy: policy
      ),
      style: style
    )
  }
}

extension Line {
  /// Truncates trailing spans without flattening their styles.
  public func truncated(
    to columns: Int,
    ellipsis: Span? = Span("…"),
    policy: TerminalWidthPolicy = .standard
  ) -> Line {
    let columns = max(0, columns)
    guard columns > 0 else { return Line([], style: style, alignment: alignment) }
    guard lineExceedsWidth(spans, columns: columns, policy: policy) else { return self }

    let fittedEllipsis = ellipsis.map {
      Span(
        TerminalWidth.prefix($0.content, fitting: columns, policy: policy),
        style: $0.style
      )
    }
    let ellipsisWidth = fittedEllipsis.map { TerminalWidth.of($0.content, policy: policy) } ?? 0
    var remaining = columns - ellipsisWidth
    var fittedSpans: [Span] = []

    for span in spans where remaining > 0 {
      let content = TerminalWidth.prefix(span.content, fitting: remaining, policy: policy)
      if content.isEmpty {
        if span.content.isEmpty { continue }
        break
      }
      fittedSpans.append(Span(content, style: span.style))
      remaining -= TerminalWidth.of(content, policy: policy)
      if content != span.content { break }
    }
    if let fittedEllipsis, !fittedEllipsis.content.isEmpty {
      fittedSpans.append(fittedEllipsis)
    }
    return Line(fittedSpans, style: style, alignment: alignment)
  }

  /// Truncates and pads a styled line to exactly `columns` terminal columns.
  public func fitted(
    to columns: Int,
    alignment fittedAlignment: Alignment = .leading,
    ellipsis: Span? = Span("…"),
    paddingStyle: Style = .plain,
    policy: TerminalWidthPolicy = .standard
  ) -> Line {
    var result = truncated(to: columns, ellipsis: ellipsis, policy: policy)
    let resultWidth = result.spans.reduce(0) {
      $0 + TerminalWidth.of($1.content, policy: policy)
    }
    let missing = max(0, max(0, columns) - resultWidth)
    let padding = paddingWidths(missing, alignment: fittedAlignment)
    if padding.leading > 0 {
      result.spans.insert(
        Span(String(repeating: " ", count: padding.leading), style: paddingStyle),
        at: 0
      )
    }
    if padding.trailing > 0 {
      result.spans.append(
        Span(String(repeating: " ", count: padding.trailing), style: paddingStyle)
      )
    }
    return result
  }
}

private func lineExceedsWidth(
  _ spans: [Span],
  columns: Int,
  policy: TerminalWidthPolicy
) -> Bool {
  var used = 0
  for span in spans {
    for character in span.content {
      let width = TerminalWidth.of(character, policy: policy)
      if width > columns - used { return true }
      used += width
    }
  }
  return false
}

private func paddingWidths(_ missing: Int, alignment: Alignment) -> (leading: Int, trailing: Int) {
  switch alignment {
  case .leading: (0, missing)
  case .center:
    (missing / 2, missing - missing / 2)
  case .trailing: (missing, 0)
  }
}
