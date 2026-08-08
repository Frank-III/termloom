import InlineSnapshotTesting
import TermLoom

@discardableResult
public func assertWidget<W: Widget>(
  _ widget: W,
  size: Size,
  renderArea: Rect? = nil,
  environment: RenderEnvironment = RenderEnvironment(),
  matches snapshot: (() -> String)? = nil,
  fileID: StaticString = #fileID,
  file: StaticString = #filePath,
  function: StaticString = #function,
  line: UInt = #line,
  column: UInt = #column
) -> Buffer {
  var buffer = Buffer(area: Rect(size: size))
  widget.render(
    in: renderArea ?? buffer.area,
    into: &buffer,
    environment: environment
  )
  assertInlineSnapshot(
    of: terminalSnapshot(buffer),
    as: .lines,
    matches: snapshot,
    fileID: fileID,
    file: file,
    function: function,
    line: line,
    column: column
  )
  return buffer
}

@discardableResult
public func assertWidget<W: StatefulWidget>(
  _ widget: W,
  size: Size,
  state: inout W.State,
  renderArea: Rect? = nil,
  environment: RenderEnvironment = RenderEnvironment(),
  matches snapshot: (() -> String)? = nil,
  fileID: StaticString = #fileID,
  file: StaticString = #filePath,
  function: StaticString = #function,
  line: UInt = #line,
  column: UInt = #column
) -> Buffer {
  var buffer = Buffer(area: Rect(size: size))
  widget.render(
    in: renderArea ?? buffer.area,
    into: &buffer,
    environment: environment,
    state: &state
  )
  assertInlineSnapshot(
    of: terminalSnapshot(buffer),
    as: .lines,
    matches: snapshot,
    fileID: fileID,
    file: file,
    function: function,
    line: line,
    column: column
  )
  return buffer
}

public func assertTerminal(
  _ buffer: @autoclosure () -> Buffer,
  matches snapshot: (() -> String)? = nil,
  fileID: StaticString = #fileID,
  file: StaticString = #filePath,
  function: StaticString = #function,
  line: UInt = #line,
  column: UInt = #column
) {
  assertInlineSnapshot(
    of: terminalSnapshot(buffer()),
    as: .lines,
    matches: snapshot,
    fileID: fileID,
    file: file,
    function: function,
    line: line,
    column: column
  )
}

public func assertTerminalCodes(
  _ output: @autoclosure () -> String,
  matches snapshot: (() -> String)? = nil,
  fileID: StaticString = #fileID,
  file: StaticString = #filePath,
  function: StaticString = #function,
  line: UInt = #line,
  column: UInt = #column
) {
  assertInlineSnapshot(
    of: visibleTerminalCodes(output()),
    as: .lines,
    matches: snapshot,
    fileID: fileID,
    file: file,
    function: function,
    line: line,
    column: column
  )
}

public func visibleTerminalCodes(_ output: String) -> String {
  output
    .replacingOccurrences(of: "\u{1B}", with: "<ESC>")
    .replacingOccurrences(of: "\r", with: "<CR>")
}

private func terminalSnapshot(_ buffer: Buffer) -> String {
  buffer.lines().map { "│\($0)│" }.joined(separator: "\n")
}
