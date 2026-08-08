import Observation
import TermLoom

@Observable
@MainActor
public final class DiffScopeApplication: TerminalApplication {
  public let repository: RepositorySnapshot
  public var focus: DiffScopeFocus = .files
  public var selectedFileID: Int?
  public var query = TextFieldState()
  public var isFiltering = false
  public var diffLines: [DiffLine] = []
  public var diffScroll = 0
  public var horizontalScroll = 0
  public var isLoadingDiff = false
  public var errorMessage: String?
  public var showsHelp = false

  @ObservationIgnored private let diffLoader: DiffLoader
  @ObservationIgnored private var diffTask: Task<Void, Never>?
  @ObservationIgnored private var wheelTask: Task<Void, Never>?
  @ObservationIgnored private var pendingWheelDelta = 0
  @ObservationIgnored private var cache: [Int: [DiffLine]] = [:]
  @ObservationIgnored private var cacheOrder: [Int] = []

  public init(repository: RepositorySnapshot, diffLoader: @escaping DiffLoader) {
    self.repository = repository
    self.diffLoader = diffLoader
    selectedFileID = repository.files.first?.id
  }

  public var filteredFiles: [ChangedFile] {
    let needle = query.text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !needle.isEmpty else { return repository.files }
    return repository.files.filter { $0.path.localizedCaseInsensitiveContains(needle) }
  }

  public var selectedFile: ChangedFile? {
    guard let selectedFileID else { return nil }
    return repository.files.first { $0.id == selectedFileID }
  }

  public var body: some Widget {
    DiffScopeScreen(
      repository: repository,
      files: filteredFiles,
      selectedFileID: selectedFileID,
      diffLines: diffLines,
      diffScroll: diffScroll,
      horizontalScroll: horizontalScroll,
      focus: focus,
      query: query,
      isFiltering: isFiltering,
      isLoadingDiff: isLoadingDiff,
      errorMessage: errorMessage,
      showsHelp: showsHelp)
  }

  public func prepare() async {
    loadSelectedDiff()
    await waitForPendingDiff()
  }

  public func waitForPendingDiff() async {
    await diffTask?.value
  }

  public func waitForPendingNavigation() async {
    await wheelTask?.value
    await diffTask?.value
  }

  public func update(_ event: TerminalEvent) async -> ApplicationUpdate {
    if showsHelp {
      if case .key(let key) = event,
        key.kind != .release,
        key.key == .escape || key.key == .character("?") || key.key == .character("q")
      {
        showsHelp = false
      }
      return .ignore
    }

    if isFiltering { return updateFilter(event) }

    if case .action(let action) = event, action.rawValue.hasPrefix("file:"),
      let id = Int(action.rawValue.dropFirst("file:".count))
    {
      selectFile(id: id, debouncesDiff: false)
      return .ignore
    }

    if case .mouse(let mouse) = event {
      switch mouse.kind {
      case .scrollUp:
        enqueueWheelMovement(-3)
        return .ignore
      case .scrollDown:
        enqueueWheelMovement(3)
        return .ignore
      default:
        break
      }
    }

    guard case .key(let key) = event, key.kind != .release else { return .ignore }
    cancelPendingWheel()
    switch key.key {
    case .character("q"):
      diffTask?.cancel()
      return .quit
    case .character("c") where key.modifiers.contains(.control):
      diffTask?.cancel()
      return .quit
    case .character("?"):
      showsHelp = true
    case .tab:
      focus.toggle()
    case .character("1"):
      focus = .files
    case .character("2"):
      focus = .diff
    case .character("/"):
      focus = .files
      isFiltering = true
      query.cursor = query.text.count
      query.selectionAnchor = nil
    case .character("x") where focus == .files:
      let previousSelection = selectedFileID
      query = TextFieldState()
      reconcileSelection()
      if selectedFileID != previousSelection { loadSelectedDiff(afterNavigation: true) }
    case .character("j"), .down:
      moveVertically(1)
    case .character("k"), .up:
      moveVertically(-1)
    case .pageDown:
      moveVertically(15)
    case .pageUp:
      moveVertically(-15)
    case .character("g"):
      moveToBoundary(end: false)
    case .character("G"):
      moveToBoundary(end: true)
    case .character("h") where focus == .diff,
      .left where focus == .diff:
      horizontalScroll = max(0, horizontalScroll - 4)
    case .character("l") where focus == .diff,
      .right where focus == .diff:
      horizontalScroll += 4
    case .character("0") where focus == .diff:
      horizontalScroll = 0
    default:
      return .ignore
    }
    return .ignore
  }

  private func updateFilter(_ event: TerminalEvent) -> ApplicationUpdate {
    if case .key(let key) = event, key.kind != .release {
      if key.key == .escape || key.key == .enter {
        isFiltering = false
        return .ignore
      }
    }
    let previousSelection = selectedFileID
    guard query.handle(event) else { return .ignore }
    reconcileSelection()
    if selectedFileID != previousSelection { loadSelectedDiff(afterNavigation: true) }
    return .ignore
  }

  private func enqueueWheelMovement(_ delta: Int) {
    pendingWheelDelta += delta
    guard wheelTask == nil else { return }
    wheelTask = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(16))
      guard !Task.isCancelled, let self else { return }
      let movement = min(12, max(-12, self.pendingWheelDelta))
      self.pendingWheelDelta = 0
      self.wheelTask = nil
      self.moveVertically(movement)
    }
  }

  private func cancelPendingWheel() {
    wheelTask?.cancel()
    wheelTask = nil
    pendingWheelDelta = 0
  }

  private func moveVertically(_ delta: Int) {
    switch focus {
    case .files:
      let files = filteredFiles
      guard !files.isEmpty else { return }
      let current = selectedFileID.flatMap { id in files.firstIndex { $0.id == id } } ?? 0
      let next = min(max(0, current + delta), files.count - 1)
      selectFile(id: files[next].id)
    case .diff:
      diffScroll = min(maximumDiffScroll, max(0, diffScroll + delta))
    }
  }

  private func moveToBoundary(end: Bool) {
    switch focus {
    case .files:
      guard let file = end ? filteredFiles.last : filteredFiles.first else { return }
      selectFile(id: file.id)
    case .diff:
      diffScroll = end ? maximumDiffScroll : 0
    }
  }

  private var maximumDiffScroll: Int { max(0, diffLines.count - 1) }

  private func reconcileSelection() {
    let files = filteredFiles
    guard !files.isEmpty else {
      diffTask?.cancel()
      selectedFileID = nil
      diffLines = []
      isLoadingDiff = false
      errorMessage = nil
      return
    }
    if let selectedFileID, files.contains(where: { $0.id == selectedFileID }) { return }
    selectedFileID = files[0].id
    diffScroll = 0
    horizontalScroll = 0
  }

  private func selectFile(id: Int, debouncesDiff: Bool = true) {
    guard selectedFileID != id, repository.files.contains(where: { $0.id == id }) else { return }
    selectedFileID = id
    diffScroll = 0
    horizontalScroll = 0
    errorMessage = nil
    loadSelectedDiff(afterNavigation: debouncesDiff)
  }

  private func loadSelectedDiff(afterNavigation: Bool = false) {
    diffTask?.cancel()
    guard let file = selectedFile else {
      diffLines = []
      isLoadingDiff = false
      return
    }
    if let cached = cache[file.id] {
      diffLines = cached
      isLoadingDiff = false
      return
    }
    isLoadingDiff = true
    errorMessage = nil
    let requestedID = file.id
    diffTask = Task { [weak self, diffLoader] in
      do {
        if afterNavigation { try await Task.sleep(for: .milliseconds(140)) }
        guard !Task.isCancelled, let self, self.selectedFileID == requestedID else { return }
        let lines = try await diffLoader(file)
        guard !Task.isCancelled, self.selectedFileID == requestedID else { return }
        self.insertIntoCache(lines, for: requestedID)
        self.diffLines = lines
        self.isLoadingDiff = false
      } catch is CancellationError {
      } catch {
        guard !Task.isCancelled, let self, self.selectedFileID == requestedID else { return }
        self.errorMessage = error.localizedDescription
        self.diffLines = []
        self.isLoadingDiff = false
      }
    }
  }

  private func insertIntoCache(_ lines: [DiffLine], for id: Int) {
    cache[id] = lines
    cacheOrder.removeAll { $0 == id }
    cacheOrder.append(id)
    while cacheOrder.count > 8 {
      let removed = cacheOrder.removeFirst()
      cache[removed] = nil
    }
  }
}
