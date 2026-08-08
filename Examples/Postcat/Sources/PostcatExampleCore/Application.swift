import Foundation
import Observation
import TermLoom
import TermLoomOverlays
import TermLoomTextArea

#if DevTools
  import TermLoomDevTools
#endif

public enum PostcatRenderingMode: Hashable, Sendable {
  case explicit
  case observation
}

@Observable
@MainActor
public final class PostcatApplication: TerminalApplication, PeriodicallyRedrawingTerminalApplication
{
  public var method: HTTPMethod = .get
  public var url = TextFieldState(text: "https://httpbin.org/anything")
  public var requestBody = TextAreaState(text: "{\n  \"hello\": \"swift\"\n}")
  public var focus: AppFocus = .url
  public var editing = false
  public var response: APIResponse?
  public var responseTab: ResponseTab = .body
  public var renderedResponse: [Line] = []
  public var responseScroll = 0
  public var wrapsResponse = false
  public var loading = false
  public var error: String?
  public var statusMessage: String?
  public var showsHelp = false
  public var spinnerFrame = 0
  #if DevTools
    public var devTools = DevToolsState()
  #endif

  public let renderingMode: PostcatRenderingMode
  @ObservationIgnored private let sender: RequestSender
  @ObservationIgnored private var requestTask: Task<Void, Never>?
  @ObservationIgnored private var spinnerTask: Task<Void, Never>?
  @ObservationIgnored private var requestGeneration = 0

  public init(
    renderingMode: PostcatRenderingMode = .explicit,
    sender: @escaping RequestSender = liveRequestSender()
  ) {
    self.renderingMode = renderingMode
    self.sender = sender
  }

  public var automaticallyTracksObservableState: Bool { renderingMode == .observation }
  public var needsPeriodicRedraw: Bool { renderingMode == .explicit && loading }
  private var mutationUpdate: ApplicationUpdate {
    renderingMode == .observation ? .ignore : .redraw
  }
  private var maximumResponseScroll: Int { max(0, renderedResponse.count - 1) }

  public var body: some Widget {
    let screen = PostcatScreen(
      method: method,
      url: url,
      requestBody: requestBody,
      focus: focus,
      editing: editing,
      response: response,
      responseTab: responseTab,
      responseLines: renderedResponse,
      responseScroll: responseScroll,
      wrapsResponse: wrapsResponse,
      loading: loading,
      error: error,
      statusMessage: statusMessage,
      showsHelp: showsHelp,
      spinnerFrame: renderingMode == .observation
        ? spinnerFrame : Int(Date.timeIntervalSinceReferenceDate * 10)
    )
    #if DevTools
      return Overlay(
        isPresented: devTools.isPresented,
        base: screen,
        layer: DevToolsOverlay(devTools))
    #else
      return screen
    #endif
  }

  public func update(_ event: TerminalEvent) async -> ApplicationUpdate {
    #if DevTools
      devTools.record(event: event)
      if case .resize(let size) = event { devTools.terminalSize = size }
      if case .key(let key) = event, key.kind != .release, key.key == .function(12) {
        devTools.toggle()
        return mutationUpdate
      }
      if devTools.isPresented { return .ignore }
    #endif
    if showsHelp {
      if case .key(let key) = event,
        key.key == .escape || key.key == .character("?") || key.key == .character("q")
      {
        showsHelp = false
        return mutationUpdate
      }
      return .ignore
    }

    if editing {
      return updateEditor(event)
    }

    if case .action(let action) = event {
      switch action.rawValue {
      case "postcat.response.body":
        focus = .response
        responseTab = .body
        rebuildResponseLines()
        return mutationUpdate
      case "postcat.response.headers":
        focus = .response
        responseTab = .headers
        rebuildResponseLines()
        return mutationUpdate
      default:
        return .ignore
      }
    }

    guard case .key(let key) = event, key.kind != .release else { return .ignore }
    switch key.key {
    case .character("q"):
      requestTask?.cancel()
      return .quit
    case .character("c") where key.modifiers.contains(.control):
      requestTask?.cancel()
      return .quit
    case .character("?"):
      showsHelp = true
    case .tab:
      focus.advance(key.modifiers.contains(.shift) ? -1 : 1)
    case .character("1"):
      focus = .url
    case .character("2"):
      focus = .request
    case .character("3"):
      focus = .response
    case .character("i"):
      guard focus != .response else { return .ignore }
      editing = true
    case .character("m"):
      method.cycle()
    case .character("M"):
      method.cycle(-1)
    case .character("s"), .enter:
      startRequest()
    case .escape where loading:
      cancelRequest()
    case .character("[") where focus == .response,
      .left where focus == .response:
      responseTab = .body
      rebuildResponseLines()
    case .character("]") where focus == .response,
      .right where focus == .response:
      responseTab = .headers
      rebuildResponseLines()
    case .character("j") where focus == .response,
      .down where focus == .response:
      responseScroll = min(maximumResponseScroll, responseScroll + 1)
    case .character("k") where focus == .response,
      .up where focus == .response:
      responseScroll = max(0, responseScroll - 1)
    case .pageDown where focus == .response:
      responseScroll = min(maximumResponseScroll, responseScroll + 12)
    case .pageUp where focus == .response:
      responseScroll = max(0, responseScroll - 12)
    case .character("g") where focus == .response:
      responseScroll = 0
    case .character("G") where focus == .response:
      responseScroll = maximumResponseScroll
    case .character("w") where focus == .response:
      wrapsResponse.toggle()
      responseScroll = 0
    default:
      return .ignore
    }
    return mutationUpdate
  }

  public func waitForCurrentRequest() async {
    await requestTask?.value
  }

  private func updateEditor(_ event: TerminalEvent) -> ApplicationUpdate {
    if case .key(let key) = event, key.key == .escape {
      editing = false
      return mutationUpdate
    }
    if focus == .url, case .key(let key) = event, key.key == .enter {
      editing = false
      startRequest()
      return mutationUpdate
    }
    let changed: Bool =
      switch focus {
      case .url: url.handle(event)
      case .request: requestBody.handle(event)
      case .response: false
      }
    return changed ? mutationUpdate : .ignore
  }

  private func startRequest() {
    guard !loading else { return }
    let request = APIRequest(
      method: method,
      url: url.text.trimmingCharacters(in: .whitespacesAndNewlines),
      body: requestBody.text)
    loading = true
    error = nil
    statusMessage = nil
    responseScroll = 0
    requestGeneration += 1
    let generation = requestGeneration
    if renderingMode == .observation {
      spinnerFrame = 0
      spinnerTask?.cancel()
      spinnerTask = Task { [weak self] in
        while let self, self.loading, !Task.isCancelled {
          try? await Task.sleep(for: .milliseconds(100))
          guard self.loading, !Task.isCancelled else { return }
          self.spinnerFrame += 1
        }
      }
    }
    requestTask = Task.detached { [weak self, sender] in
      do {
        let response = try await sender(request)
        guard !Task.isCancelled else { return }
        await self?.finishRequest(.success(response), generation: generation)
      } catch is CancellationError {
        await self?.finishCancellation(generation: generation)
      } catch {
        guard !Task.isCancelled else { return }
        await self?.finishRequest(.failure(error), generation: generation)
      }
    }
  }

  private func finishRequest(_ result: Result<APIResponse, Error>, generation: Int) {
    guard generation == requestGeneration else { return }
    switch result {
    case .success(let response):
      self.response = response
      rebuildResponseLines()
      statusMessage = "received \(response.status)"
      #if DevTools
        devTools.log("received HTTP \(response.status) in \(response.durationMilliseconds) ms")
      #endif
    case .failure(let error):
      self.error = error.localizedDescription
      #if DevTools
        devTools.log(error.localizedDescription, level: .error)
      #endif
    }
    loading = false
    requestTask = nil
    stopSpinner()
  }

  private func finishCancellation(generation: Int) {
    guard generation == requestGeneration else { return }
    loading = false
    statusMessage = "request cancelled"
    requestTask = nil
    stopSpinner()
  }

  private func cancelRequest() {
    requestGeneration += 1
    requestTask?.cancel()
    requestTask = nil
    loading = false
    statusMessage = "request cancelled"
    stopSpinner()
  }

  private func stopSpinner() {
    spinnerTask?.cancel()
    spinnerTask = nil
  }

  private func rebuildResponseLines() {
    renderedResponse = response.map { responseLines(for: $0, tab: responseTab) } ?? []
    responseScroll = 0
  }
}
