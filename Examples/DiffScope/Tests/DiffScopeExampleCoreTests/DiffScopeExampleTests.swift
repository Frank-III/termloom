import Foundation
import Ratatui
import Testing

@testable import DiffScopeExampleCore

private actor DiffLoadCounter {
  private(set) var ids: [Int] = []

  func record(_ id: Int) {
    ids.append(id)
  }
}

@MainActor
@Suite struct DiffScopeExampleTests {
  @Test func bunFixtureRepresentsTheExtremePullRequestWithoutBundlingItsPatch() async {
    let (repository, loader) = DemoRepository.bunRewrite()

    #expect(repository.files.count == 2_188)
    #expect(repository.additions == 1_009_257)
    #expect(repository.deletions == 4_024)
    #expect(repository.commits == 100)
    #expect(repository.files.first?.path == "src/js_parser/p.rs")
    #expect(try! await loader(repository.files[0]).count > 20)
  }

  @Test func initialScreenRendersLargeFileListAndSelectedDiff() async {
    let (repository, loader) = DemoRepository.bunRewrite()
    let application = DiffScopeApplication(repository: repository, diffLoader: loader)
    await application.prepare()

    let output = render(application.body, width: 120, height: 34)

    #expect(output.contains("DIFFSCOPE"))
    #expect(output.contains("Bun #30412"))
    #expect(output.contains("2,188 files"))
    #expect(output.contains("src/js_parser/p.rs"))
    #expect(output.contains("diff --git"))
    #expect(output.contains("FILES"))
  }

  @Test func fileRowsEmitOnlyVisibleSamePassInteractionsAndHelpMasksThem() {
    let files = (0..<100).map {
      ChangedFile(
        id: $0,
        path: "Sources/File\($0).swift",
        kind: .modified,
        additions: $0,
        deletions: 0
      )
    }
    let repository = RepositorySnapshot(
      title: "Fixture",
      subtitle: "many files",
      branch: "main",
      files: files,
      additions: 4_950,
      deletions: 0
    )
    var screen = DiffScopeScreen(
      repository: repository,
      files: files,
      selectedFileID: 50,
      diffLines: [],
      diffScroll: 0,
      horizontalScroll: 0,
      focus: .files,
      query: TextFieldState(),
      isFiltering: false,
      isLoadingDiff: false,
      errorMessage: nil,
      showsHelp: false
    )
    var frame = Frame(buffer: Buffer(area: Rect(x: 0, y: 0, width: 80, height: 20)))

    screen.render(in: frame.area, into: &frame)

    let fileRegions = frame.interactions.regions.filter {
      $0.action?.rawValue.hasPrefix("file:") == true
    }
    #expect(!fileRegions.isEmpty)
    #expect(fileRegions.count < files.count)
    #expect(fileRegions.last?.action == ActionID("file:50"))
    #expect(fileRegions.allSatisfy { $0.area.height == 1 && !$0.isFocusable })
    #expect(Set(fileRegions.map(\.area)).count == fileRegions.count)

    screen.showsHelp = true
    frame = Frame(buffer: Buffer(area: frame.area))
    screen.render(in: frame.area, into: &frame)
    #expect(
      !frame.interactions.regions.contains {
        $0.action?.rawValue.hasPrefix("file:") == true
      }
    )
  }

  @Test func keyboardNavigationFilteringAndDiffScrollingRemainApplicationPolicy() async {
    let repository = RepositorySnapshot(
      title: "Fixture",
      subtitle: "three files",
      branch: "main",
      files: [
        ChangedFile(id: 1, path: "Sources/App.swift", kind: .modified, additions: 4, deletions: 1),
        ChangedFile(id: 2, path: "Sources/Model.swift", kind: .added, additions: 20, deletions: 0),
        ChangedFile(id: 3, path: "Tests/AppTests.swift", kind: .added, additions: 10, deletions: 0),
      ],
      additions: 34,
      deletions: 1)
    let application = DiffScopeApplication(
      repository: repository,
      diffLoader: { file in
        [DiffLine("diff --git a/\(file.path) b/\(file.path)")]
          + (0..<50).map { DiffLine("+line \($0)") }
      })
    await application.prepare()

    _ = await application.update(.key(KeyEvent(.down)))
    await application.waitForPendingDiff()
    #expect(application.selectedFileID == 2)

    _ = await application.update(.key(KeyEvent(.character("/"))))
    _ = await application.update(.key(KeyEvent(.character("T"))))
    _ = await application.update(.key(KeyEvent(.character("e"))))
    _ = await application.update(.key(KeyEvent(.character("s"))))
    _ = await application.update(.key(KeyEvent(.character("t"))))
    #expect(application.filteredFiles.map(\.id) == [3])
    #expect(application.selectedFileID == 3)

    _ = await application.update(.key(KeyEvent(.enter)))
    _ = await application.update(.key(KeyEvent(.tab)))
    _ = await application.update(.key(KeyEvent(.pageDown)))
    #expect(application.focus == .diff)
    #expect(application.diffScroll == 15)
  }

  @Test func rapidMouseWheelNavigationDebouncesExpensivePatchLoads() async {
    let counter = DiffLoadCounter()
    let files = (0..<12).map {
      ChangedFile(
        id: $0,
        path: "Sources/File\($0).swift",
        kind: .modified,
        additions: 1,
        deletions: 1)
    }
    let repository = RepositorySnapshot(
      title: "Fixture",
      subtitle: "rapid navigation",
      branch: "main",
      files: files,
      additions: 12,
      deletions: 12)
    let application = DiffScopeApplication(
      repository: repository,
      diffLoader: { file in
        await counter.record(file.id)
        return [DiffLine("+file \(file.id)")]
      })
    await application.prepare()

    for _ in 0..<4 {
      _ = await application.update(
        .mouse(MouseEvent(.scrollDown, at: Position(x: 2, y: 4))))
    }
    for _ in 0..<2 {
      _ = await application.update(
        .mouse(MouseEvent(.scrollUp, at: Position(x: 2, y: 4))))
    }
    await application.waitForPendingNavigation()

    #expect(application.selectedFileID == 6)
    #expect(await counter.ids == [0, 6])
  }

  @Test func largeDiffRendersTheVisibleWindowAtDeepOffsets() async {
    let file = ChangedFile(
      id: 1,
      path: "Sources/Huge.swift",
      kind: .modified,
      additions: 20_000,
      deletions: 0)
    let repository = RepositorySnapshot(
      title: "Fixture",
      subtitle: "large patch",
      branch: "main",
      files: [file],
      additions: 20_000,
      deletions: 0)
    let application = DiffScopeApplication(
      repository: repository,
      diffLoader: { _ in (0..<20_000).map { DiffLine("+visible line \($0)") } })
    await application.prepare()
    application.focus = .diff
    application.diffScroll = 19_980

    let output = render(application.body, width: 110, height: 28)

    #expect(output.contains("visible line 19980"))
    #expect(!output.contains("visible line 0"))
  }

  @Test func compactLayoutShowsTheFocusedPane() async {
    let (repository, loader) = DemoRepository.bunRewrite()
    let application = DiffScopeApplication(repository: repository, diffLoader: loader)
    await application.prepare()

    let files = render(application.body, width: 70, height: 24)
    #expect(files.contains("Files"))
    #expect(!files.contains("diff --git"))

    _ = await application.update(.key(KeyEvent(.tab)))
    let diff = render(application.body, width: 70, height: 24)
    #expect(diff.contains("diff --git"))
  }

  @Test func liveGitAdapterFindsTheRepositoryRootAndLoadsASelectedPatch() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("diffscope-tests-\(UUID().uuidString)", isDirectory: true)
    let sources = root.appendingPathComponent("Sources", isDirectory: true)
    try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    try "let value = 1\n".write(
      to: sources.appendingPathComponent("App.swift"), atomically: true, encoding: .utf8)
    try run("git", ["init", "-q"], at: root)
    try run("git", ["config", "user.email", "demo@example.com"], at: root)
    try run("git", ["config", "user.name", "Demo"], at: root)
    try run("git", ["add", "."], at: root)
    try run("git", ["commit", "-qm", "initial"], at: root)
    let baseRevision = try capture("git", ["rev-parse", "HEAD"], at: root)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    try "let value = 2\nlet added = true\n".write(
      to: sources.appendingPathComponent("App.swift"), atomically: true, encoding: .utf8)

    let configuration = try await DiffScopeConfiguration.resolve(
      arguments: ["--repo", sources.path])
    let snapshot = configuration.repository
    let file = try #require(snapshot.files.first { $0.path == "Sources/App.swift" })
    let patch = try await configuration.diffLoader(file)

    #expect(snapshot.title == root.lastPathComponent)
    #expect(file.kind == .modified)
    #expect(patch.contains { $0.text == "+let value = 2" })

    try run("git", ["add", "."], at: root)
    try run("git", ["commit", "-qm", "change"], at: root)
    let rangeConfiguration = try await DiffScopeConfiguration.resolve(
      arguments: ["--repo", sources.path, "--base", baseRevision])
    let rangeFile = try #require(
      rangeConfiguration.repository.files.first { $0.path == "Sources/App.swift" })
    let rangePatch = try await rangeConfiguration.diffLoader(rangeFile)

    #expect(!rangeConfiguration.repository.aggregateStatsAvailable)
    #expect(rangePatch.contains { $0.text == "+let value = 2" })
  }

  private func render<W: Widget>(_ screen: W, width: Int, height: Int) -> String {
    let area = Rect(x: 0, y: 0, width: width, height: height)
    var buffer = Buffer(area: area)
    screen.render(in: area, into: &buffer, environment: RenderEnvironment())
    return (0..<height).map { y in
      (0..<width).map { x in buffer[Position(x: x, y: y)].symbol }.joined()
    }.joined(separator: "\n")
  }

  private func run(_ executable: String, _ arguments: [String], at directory: URL) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [executable] + arguments
    process.currentDirectoryURL = directory
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    #expect(process.terminationStatus == 0)
  }

  private func capture(_ executable: String, _ arguments: [String], at directory: URL) throws
    -> String
  {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [executable] + arguments
    process.currentDirectoryURL = directory
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    #expect(process.terminationStatus == 0)
    return String(decoding: data, as: UTF8.self)
  }
}
