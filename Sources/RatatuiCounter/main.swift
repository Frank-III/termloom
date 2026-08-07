import Ratatui

final class Counter: TerminalApplication {
  var count = 0

  var body: some Widget {
    Block(title: "Swift Ratatui", padding: .all(1)) {
      VStack(spacing: 1) {
        Text("Count: \(count)", alignment: .center)
          .foregroundStyle(.cyan)
          .bold()
          .frame(.length(1))
        Text("↑/k increment  ↓/j decrement", alignment: .center)
          .frame(.length(1))
        HStack(spacing: 1) {
          Button("−", id: "decrement", action: "decrement")
          Button("+", id: "increment", action: "increment")
          Button("Quit", id: "quit", action: "quit")
        }.frame(.length(1))
      }
    }
  }

  func update(_ event: TerminalEvent) async -> ApplicationUpdate {
    switch event {
    case .key(KeyEvent(.up)), .key(KeyEvent(.character("k"))), .action("increment"):
      count += 1
      return .redraw
    case .key(KeyEvent(.down)), .key(KeyEvent(.character("j"))), .action("decrement"):
      count -= 1
      return .redraw
    case .key(KeyEvent(.character("q"))),
      .key(KeyEvent(.character("c"), modifiers: [.control])),
      .action("quit"):
      return .quit
    default:
      return .ignore
    }
  }
}

let counter = Counter()
try await counter.run(viewport: .inline(height: 10))
