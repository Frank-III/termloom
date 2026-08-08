import TermLoom

struct ProcessRow {
  var name: String
  var cpu: Int
  var status: String
}

let rows = [
  ProcessRow(name: "renderer", cpu: 12, status: "running"),
  ProcessRow(name: "events", cpu: 3, status: "waiting"),
  ProcessRow(name: "database", cpu: 1, status: "idle"),
]

var terminal = try Terminal(
  backend: ANSIBackend(fallbackSize: Size(width: 68, height: 14))
)

try terminal.draw { frame in
  frame.render(
    Block(title: "TermLoom, shaped for Swift", padding: .all(1)) {
      VStack(spacing: 1) {
        Text("Typed at the edges. Flat in the renderer.")
          .foregroundStyle(.cyan)
          .bold()
          .frame(.length(1))

        Table(rows, selectedRow: 0) {
          TableColumn("Process", value: \.name, width: .flex(2))
          TableColumn("CPU", value: \.cpu, width: .length(8), alignment: .trailing) {
            "\($0)%"
          }
          TableColumn("State", value: \.status)
        }
      }
    }
  )
}
