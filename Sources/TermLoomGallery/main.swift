import TermLoom

struct GalleryRow {
  var name: String
  var state: String
}

final class Gallery: TerminalApplication {
  var page = 0
  var progress = 0.62
  var selected = 1
  var query = TextFieldState()
  var focusedControl: ControlID?
  var isEnabled = true
  var mode = 0

  private let samples = [2.0, 5, 3, 8, 6, 9, 4, 7, 8, 10, 7, 11]

  var body: some Widget {
    Block(title: "TermLoom Swift Gallery", padding: .all(1)) {
      VStack(spacing: 1) {
        Tabs(["Metrics", "Collections", "Canvas", "Controls"], selectedIndex: page)
          .frame(.length(1))

        if page == 0 {
          VStack(spacing: 1) {
            Gauge(ratio: progress, label: "Build \(Int(progress * 100))%")
              .frame(.length(1))
            Sparkline(samples, style: Style(foreground: .cyan))
              .frame(.length(1))
            BarChart(
              groups: [
                BarGroup(
                  "Host",
                  bars: [
                    Bar("CPU", value: 7, style: Style(foreground: .green)),
                    Bar("MEM", value: 5, style: Style(foreground: .blue)),
                  ]
                ),
                BarGroup(
                  "I/O",
                  bars: [
                    Bar("NET", value: 9, style: Style(foreground: .magenta))
                  ]
                ),
              ],
              barWidth: 3,
              groupSpacing: 2
            )
            Scrollbar(
              contentLength: 100,
              viewportLength: 20,
              position: Int(progress * 80),
              orientation: .horizontalBottom,
              beginSymbol: "←",
              endSymbol: "→"
            ).frame(.length(1))
          }
        } else if page == 1 {
          HStack(spacing: 2) {
            Block(title: "Modules") {
              List(
                ["renderer", "input", "scheduler", "backend"],
                selectedRow: selected
              ) { $0 }
            }.mergingBorders()
            Block(title: "Status") {
              Table(
                [
                  GalleryRow(name: "renderer", state: "running"),
                  GalleryRow(name: "input", state: "waiting"),
                  GalleryRow(name: "scheduler", state: "idle"),
                ],
                selectedRow: selected
              ) {
                TableColumn("Name", value: \.name, width: .flex(2))
                TableColumn("State", value: \.state)
              }
            }.mergingBorders()
          }
        } else if page == 2 {
          Chart([
            Dataset(
              "load",
              points: samples.enumerated().map { (Double($0.offset), $0.element) },
              style: Style(foreground: .cyan),
              marker: .sextant,
              graphType: .line
            )
          ])
        } else {
          VStack(spacing: 1) {
            Text("Tab between controls; editing state stays in the model.").dim()
              .frame(.length(1))
            TextField(query, id: "query", placeholder: "Filter processes")
              .frame(.length(1))
            Checkbox("Live updates", isOn: isEnabled, id: "enabled", action: "toggle-enabled")
              .frame(.length(1))
            HStack(spacing: 1) {
              RadioButton("Fast", isSelected: mode == 0, id: "fast", action: "mode-fast")
              RadioButton("Exact", isSelected: mode == 1, id: "exact", action: "mode-exact")
            }.frame(.length(1))
          }
        }

        HStack(spacing: 1) {
          Button("Previous", id: "previous", action: "previous")
          Button("Next", id: "next", action: "next")
          Button("Quit", id: "quit", action: "quit")
        }.frame(.length(1))
      }
    }
  }

  func update(_ event: TerminalEvent) async -> ApplicationUpdate {
    if case .focusChanged(let control) = event {
      focusedControl = control
      return .ignore
    }
    if query.handle(event, when: focusedControl, is: "query") {
      return .redraw
    }
    switch event {
    case .key(let key) where key.key == .left:
      page = (page + 3) % 4
      return .redraw
    case .action("previous"):
      page = (page + 3) % 4
      return .redraw
    case .key(let key) where key.key == .right:
      page = (page + 1) % 4
      return .redraw
    case .action("next"):
      page = (page + 1) % 4
      return .redraw
    case .key(let key) where key.key == .up:
      selected = max(0, selected - 1)
      progress = min(1, progress + 0.05)
      return .redraw
    case .key(let key) where key.key == .down:
      selected = min(3, selected + 1)
      progress = max(0, progress - 0.05)
      return .redraw
    case .action("toggle-enabled"):
      isEnabled.toggle()
      return .redraw
    case .action("mode-fast"):
      mode = 0
      return .redraw
    case .action("mode-exact"):
      mode = 1
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

let gallery = Gallery()
try await gallery.run(viewport: .inline(height: 20))
