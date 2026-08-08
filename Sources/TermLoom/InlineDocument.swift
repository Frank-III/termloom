/// A source-backed sequence of stable rows rendered above a retained inline viewport.
///
/// Applications decide when content is semantically stable and provide the current canonical blocks.
/// `InlineDocumentRuntime` owns append tracking, width-dependent replay, rewrite detection, and terminal
/// history reset requests.
public struct InlineDocument<ID: Hashable & Sendable>: Hashable, Sendable {
  public var id: ID
  /// An optional application-owned content revision. When unchanged at the same width, the runtime can
  /// skip reconciling every stable block. Applications must advance it whenever `blocks` may change.
  public var revision: UInt64?
  public var blocks: [InlineDocumentBlock<ID>]

  public init(
    id: ID, revision: UInt64? = nil, blocks: [InlineDocumentBlock<ID>] = []
  ) {
    self.id = id
    self.revision = revision
    self.blocks = blocks
  }
}

/// One ordered source-backed block in an ``InlineDocument``.
///
/// An incomplete block may grow by appending rendered lines. Blocks after the first incomplete block are
/// retained as canonical source but are not emitted until their predecessor completes. A completed block
/// is immutable; changing it causes a source-backed reset and replay.
public struct InlineDocumentBlock<ID: Hashable & Sendable>: Hashable, Sendable {
  public var id: ID
  public var text: Text
  public var wrap: WrapMode
  public var isComplete: Bool

  public init(
    id: ID, text: Text, wrap: WrapMode = .word, isComplete: Bool = true
  ) {
    self.id = id
    self.text = text
    self.wrap = wrap
    self.isComplete = isComplete
  }
}

/// Reconciles canonical inline-document snapshots into terminal history insertions.
///
/// This type is public so custom runtimes can use the same behavior as ``TerminalApplication/run``.
public struct InlineDocumentRuntime<ID: Hashable & Sendable>: Sendable {
  private struct EmittedBlock: Sendable {
    var id: ID
    var lines: [Line]
    var wrap: WrapMode
    var isComplete: Bool
  }

  private var documentID: ID?
  private var revision: UInt64?
  private var width: Int?
  private var emitted: [EmittedBlock] = []

  public init() {}

  public var hasEmittedRows: Bool {
    emitted.contains { !$0.lines.isEmpty }
  }

  public mutating func reset() {
    documentID = nil
    revision = nil
    width = nil
    emitted.removeAll(keepingCapacity: true)
  }

  public mutating func reconcile(
    _ document: InlineDocument<ID>, width newWidth: Int
  ) -> [TerminalHistoryInsertion] {
    if documentID == document.id, width == newWidth, let newRevision = document.revision,
      revision == newRevision
    {
      return []
    }
    let active = activeBlocks(in: document.blocks)
    let needsReplay = requiresReplay(document: document, active: active, width: newWidth)
    var insertions: [TerminalHistoryInsertion] = []

    if needsReplay {
      if hasEmittedRows { insertions.append(.reset) }
      emitted.removeAll(keepingCapacity: true)
    }

    documentID = document.id
    revision = document.revision
    width = newWidth

    for (index, block) in active.enumerated() {
      let previousLineCount = index < emitted.count ? emitted[index].lines.count : 0
      let suffix = Array(block.text.lines.dropFirst(previousLineCount))
      if !suffix.isEmpty {
        insertions.append(TerminalHistoryInsertion(text: Text(suffix), wrap: block.wrap))
      }
      let state = EmittedBlock(
        id: block.id, lines: block.text.lines, wrap: block.wrap,
        isComplete: block.isComplete)
      if index < emitted.count {
        emitted[index] = state
      } else {
        emitted.append(state)
      }
    }
    if emitted.count > active.count {
      emitted.removeSubrange(active.count...)
    }
    return insertions
  }

  private func activeBlocks(
    in blocks: [InlineDocumentBlock<ID>]
  ) -> [InlineDocumentBlock<ID>] {
    guard let boundary = blocks.firstIndex(where: { !$0.isComplete }) else { return blocks }
    return Array(blocks.prefix(through: boundary))
  }

  private func requiresReplay(
    document: InlineDocument<ID>, active: [InlineDocumentBlock<ID>], width newWidth: Int
  ) -> Bool {
    guard documentID != nil else { return false }
    guard documentID == document.id, width == newWidth, emitted.count <= active.count else {
      return true
    }

    for (index, old) in emitted.enumerated() {
      let new = active[index]
      guard old.id == new.id, old.wrap == new.wrap else { return true }
      if old.isComplete {
        guard new.isComplete, old.lines == new.text.lines else { return true }
      } else {
        guard new.text.lines.starts(with: old.lines) else { return true }
      }
    }
    return false
  }
}
