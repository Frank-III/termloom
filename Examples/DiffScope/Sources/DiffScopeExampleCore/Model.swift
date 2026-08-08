import Foundation
import TermLoom

public enum FileChangeKind: String, Hashable, Sendable {
  case added = "A"
  case modified = "M"
  case deleted = "D"
  case renamed = "R"
  case untracked = "?"

  var label: String {
    switch self {
    case .added: "added"
    case .modified: "modified"
    case .deleted: "deleted"
    case .renamed: "renamed"
    case .untracked: "untracked"
    }
  }
}

public struct ChangedFile: Identifiable, Hashable, Sendable {
  public var id: Int
  public var path: String
  public var kind: FileChangeKind
  public var additions: Int
  public var deletions: Int

  public init(
    id: Int,
    path: String,
    kind: FileChangeKind,
    additions: Int,
    deletions: Int
  ) {
    self.id = id
    self.path = path
    self.kind = kind
    self.additions = additions
    self.deletions = deletions
  }
}

public enum DiffLineKind: Hashable, Sendable {
  case header
  case hunk
  case addition
  case deletion
  case context
}

public struct DiffLine: Hashable, Sendable {
  public var text: String
  public var kind: DiffLineKind

  public init(_ text: String, kind: DiffLineKind? = nil) {
    self.text = text
    self.kind = kind ?? Self.classify(text)
  }

  private static func classify(_ line: String) -> DiffLineKind {
    if line.hasPrefix("@@") { return .hunk }
    if line.hasPrefix("diff --git") || line.hasPrefix("index ") || line.hasPrefix("---")
      || line.hasPrefix("+++")
    {
      return .header
    }
    if line.hasPrefix("+") { return .addition }
    if line.hasPrefix("-") { return .deletion }
    return .context
  }
}

public struct RepositorySnapshot: Hashable, Sendable {
  public var title: String
  public var subtitle: String
  public var branch: String
  public var files: [ChangedFile]
  public var additions: Int
  public var deletions: Int
  public var commits: Int?
  public var isDemonstration: Bool
  public var aggregateStatsAvailable: Bool

  public init(
    title: String,
    subtitle: String,
    branch: String,
    files: [ChangedFile],
    additions: Int,
    deletions: Int,
    commits: Int? = nil,
    isDemonstration: Bool = false,
    aggregateStatsAvailable: Bool = true
  ) {
    self.title = title
    self.subtitle = subtitle
    self.branch = branch
    self.files = files
    self.additions = additions
    self.deletions = deletions
    self.commits = commits
    self.isDemonstration = isDemonstration
    self.aggregateStatsAvailable = aggregateStatsAvailable
  }
}

public typealias DiffLoader = @Sendable (ChangedFile) async throws -> [DiffLine]

public enum DiffScopeFocus: Hashable, Sendable {
  case files
  case diff

  mutating func toggle() {
    self = self == .files ? .diff : .files
  }
}

enum DiffScopeTheme {
  static let foreground = Color.rgb(0xC0, 0xCA, 0xF5)
  static let pale = Color.rgb(0x9A, 0xA5, 0xCE)
  static let dim = Color.rgb(0x56, 0x5F, 0x89)
  static let border = Color.rgb(0x3B, 0x42, 0x61)
  static let selection = Color.rgb(0x28, 0x34, 0x57)
  static let dark = Color.rgb(0x16, 0x16, 0x1E)
  static let panel = Color.rgb(0x1A, 0x1B, 0x26)
  static let accent = Color.rgb(0x7A, 0xA2, 0xF7)
  static let purple = Color.rgb(0xBB, 0x9A, 0xF7)
  static let green = Color.rgb(0x9E, 0xCE, 0x6A)
  static let red = Color.rgb(0xF7, 0x76, 0x8E)
  static let yellow = Color.rgb(0xE0, 0xAF, 0x68)
  static let orange = Color.rgb(0xFF, 0x9E, 0x64)
  static let cyan = Color.rgb(0x7D, 0xCF, 0xFF)

  static func change(_ kind: FileChangeKind) -> Color {
    switch kind {
    case .added, .untracked: green
    case .modified: yellow
    case .deleted: red
    case .renamed: cyan
    }
  }
}
