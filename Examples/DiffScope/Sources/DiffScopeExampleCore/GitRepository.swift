import Foundation

public struct DiffScopeConfiguration: Sendable {
  public var repository: RepositorySnapshot
  public var diffLoader: DiffLoader

  public static func resolve(arguments: [String]) async throws -> Self {
    let baseRevision = value(after: "--base", in: arguments)
    if let path = value(after: "--repo", in: arguments) {
      return try await liveRepository(at: path, baseRevision: baseRevision)
    }
    if let path = arguments.first, !path.hasPrefix("-") {
      return try await liveRepository(at: path, baseRevision: baseRevision)
    }
    let (repository, loader) = DemoRepository.bunRewrite()
    return Self(repository: repository, diffLoader: loader)
  }

  private static func value(after option: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: option), arguments.indices.contains(index + 1) else {
      return nil
    }
    return arguments[index + 1]
  }

  private static func liveRepository(at path: String, baseRevision: String?) async throws -> Self {
    let discoveryClient = GitRepositoryClient(path: path, baseRevision: baseRevision)
    let snapshot = try await Task.detached { try discoveryClient.snapshot() }.value
    let repositoryClient = GitRepositoryClient(
      path: snapshot.subtitle, baseRevision: baseRevision)
    return Self(
      repository: snapshot,
      diffLoader: { file in
        try await Task.detached { try repositoryClient.diff(for: file) }.value
      })
  }
}

public struct GitRepositoryClient: Sendable {
  public let root: URL
  public let baseRevision: String?

  public init(path: String, baseRevision: String? = nil) {
    root = URL(fileURLWithPath: path).standardizedFileURL
    self.baseRevision = baseRevision
  }

  public func snapshot() throws -> RepositorySnapshot {
    let topLevel = try git(["rev-parse", "--show-toplevel"]).trimmingCharacters(
      in: .whitespacesAndNewlines)
    let repositoryRoot = URL(fileURLWithPath: topLevel)
    let currentBranch =
      (try? runGit(
        at: repositoryRoot,
        arguments: ["symbolic-ref", "--quiet", "--short", "HEAD"]
      ).trimmingCharacters(in: .whitespacesAndNewlines)) ?? "detached HEAD"
    let branch = baseRevision.map { "\(currentBranch) vs \($0.prefix(8))" } ?? currentBranch
    let files: [ChangedFile]
    let aggregateStatsAvailable: Bool
    if let baseRevision {
      files = try revisionFiles(at: repositoryRoot, range: "\(baseRevision)..HEAD")
      aggregateStatsAvailable = false
    } else {
      files = try workingTreeFiles(at: repositoryRoot)
      aggregateStatsAvailable = true
    }
    return RepositorySnapshot(
      title: repositoryRoot.lastPathComponent,
      subtitle: repositoryRoot.path,
      branch: branch,
      files: files,
      additions: files.reduce(0) { $0 + $1.additions },
      deletions: files.reduce(0) { $0 + $1.deletions },
      aggregateStatsAvailable: aggregateStatsAvailable)
  }

  private func workingTreeFiles(at repositoryRoot: URL) throws -> [ChangedFile] {
    let status = try statusMap(at: repositoryRoot)
    let numstat = try runGit(
      at: repositoryRoot, arguments: ["diff", "--numstat", "HEAD", "--"])
    var files: [ChangedFile] = []
    var represented: Set<String> = []
    for line in numstat.split(separator: "\n", omittingEmptySubsequences: true) {
      let fields = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
      guard fields.count == 3 else { continue }
      let path = normalizeRenamePath(String(fields[2]))
      represented.insert(path)
      files.append(
        ChangedFile(
          id: files.count,
          path: path,
          kind: status[path] ?? .modified,
          additions: Int(fields[0]) ?? 0,
          deletions: Int(fields[1]) ?? 0))
    }
    for (path, kind) in status where !represented.contains(path) {
      files.append(
        ChangedFile(
          id: files.count,
          path: path,
          kind: kind,
          additions: 0,
          deletions: 0))
    }
    return identifiedAndSorted(files)
  }

  private func revisionFiles(at repositoryRoot: URL, range: String) throws -> [ChangedFile] {
    let output = try runGit(
      at: repositoryRoot,
      arguments: ["diff", "--name-status", "--find-renames", range, "--"])
    let files = output.split(separator: "\n", omittingEmptySubsequences: true).compactMap {
      line -> ChangedFile? in
      let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
      guard fields.count >= 2, let path = fields.last else { return nil }
      let code = String(fields[0])
      let kind: FileChangeKind =
        if code.hasPrefix("A") { .added } else if code.hasPrefix("D") {
          .deleted
        } else if code.hasPrefix("R") { .renamed } else { .modified }
      return ChangedFile(
        id: 0,
        path: String(path),
        kind: kind,
        additions: 0,
        deletions: 0)
    }
    return identifiedAndSorted(files)
  }

  private func identifiedAndSorted(_ source: [ChangedFile]) -> [ChangedFile] {
    var files = source.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    for index in files.indices { files[index].id = index }
    return files
  }

  public func diff(for file: ChangedFile) throws -> [DiffLine] {
    if file.kind == .untracked {
      let url = root.appendingPathComponent(file.path)
      let source = try String(contentsOf: url, encoding: .utf8)
      var lines = [
        DiffLine("diff --git a/\(file.path) b/\(file.path)"),
        DiffLine("new file mode 100644"),
        DiffLine("--- /dev/null"),
        DiffLine("+++ b/\(file.path)"),
        DiffLine(
          "@@ -0,0 +1,\(source.split(separator: "\n", omittingEmptySubsequences: false).count) @@"),
      ]
      lines += source.split(separator: "\n", omittingEmptySubsequences: false).prefix(5_000)
        .map { DiffLine("+\($0)") }
      return lines
    }
    let comparison = baseRevision.map { "\($0)..HEAD" } ?? "HEAD"
    let patch = try git([
      "diff", "--no-ext-diff", "--unified=3", comparison, "--", file.path,
    ])
    if patch.isEmpty {
      return [DiffLine("No textual patch is available for \(file.path).", kind: .context)]
    }
    return patch.split(separator: "\n", omittingEmptySubsequences: false).map {
      DiffLine(String($0))
    }
  }

  private func statusMap(at root: URL) throws -> [String: FileChangeKind] {
    let output = try runGit(
      at: root,
      arguments: ["status", "--porcelain=v1", "--untracked-files=all"])
    var result: [String: FileChangeKind] = [:]
    for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
      guard line.count >= 3 else { continue }
      let code = String(line.prefix(2))
      let rawPath = String(line.dropFirst(3))
      let path = normalizeRenamePath(rawPath)
      let kind: FileChangeKind =
        if code == "??" { .untracked } else if code.contains("R") {
          .renamed
        } else if code.contains("A") { .added } else if code.contains("D") { .deleted } else {
          .modified
        }
      result[path] = kind
    }
    return result
  }

  private func normalizeRenamePath(_ path: String) -> String {
    path.components(separatedBy: " -> ").last ?? path
  }

  private func git(_ arguments: [String]) throws -> String {
    try runGit(at: root, arguments: arguments)
  }

  private func runGit(at root: URL, arguments: [String]) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["git", "-C", root.path] + arguments

    let temporary = FileManager.default.temporaryDirectory
      .appendingPathComponent("termloom-diffscope-\(UUID().uuidString)")
    let errorURL = temporary.appendingPathExtension("stderr")
    FileManager.default.createFile(atPath: temporary.path, contents: nil)
    FileManager.default.createFile(atPath: errorURL.path, contents: nil)
    let outputHandle = try FileHandle(forWritingTo: temporary)
    let errorHandle = try FileHandle(forWritingTo: errorURL)
    defer {
      try? outputHandle.close()
      try? errorHandle.close()
      try? FileManager.default.removeItem(at: temporary)
      try? FileManager.default.removeItem(at: errorURL)
    }
    process.standardOutput = outputHandle
    process.standardError = errorHandle
    try process.run()
    process.waitUntilExit()
    try outputHandle.synchronize()
    try errorHandle.synchronize()
    let output = try String(contentsOf: temporary, encoding: .utf8)
    guard process.terminationStatus == 0 else {
      let message = try String(contentsOf: errorURL, encoding: .utf8)
      throw GitRepositoryError.commandFailed(
        message.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    return output
  }
}

public enum GitRepositoryError: LocalizedError {
  case commandFailed(String)

  public var errorDescription: String? {
    switch self {
    case .commandFailed(let message): message.isEmpty ? "Git command failed" : message
    }
  }
}
