public enum RatatuiLogoSize: Hashable, Sendable {
  case tiny
  case small
}

public struct RatatuiLogo: Widget, Hashable, Sendable {
  public var size: RatatuiLogoSize

  public init(size: RatatuiLogoSize = .tiny) {
    self.size = size
  }

  public static let tiny = Self(size: .tiny)
  public static let small = Self(size: .small)

  public func render(in area: Rect, into frame: inout Frame) {
    let lines =
      switch size {
      case .tiny:
        ["▛▚▗▀▖▜▘▞▚▝▛▐ ▌▌", "▛▚▐▀▌▐ ▛▜ ▌▝▄▘▌"]
      case .small:
        ["█▀▀▄ ▄▀▀▄▝▜▛▘▄▀▀▄▝▜▛▘█  █ █", "█▀▀▄ █▀▀█ ▐▌ █▀▀█ ▐▌ ▀▄▄▀ █"]
      }
    Paragraph(wrap: .none) {
      for line in lines { Line(line) }
    }.render(in: area, into: &frame.buffer, environment: frame.environment)
  }
}

public enum MascotEyeColor: Hashable, Sendable {
  case standard
  case red
}

public struct RatatuiMascot: Widget, Hashable, Sendable {
  public var eyeColor: MascotEyeColor

  public init(eyeColor: MascotEyeColor = .standard) {
    self.eyeColor = eyeColor
  }

  public func render(in area: Rect, into frame: inout Frame) {
    guard !area.isEmpty else { return }
    let left = max(Int(area.x), Int(frame.buffer.area.x))
    let top = max(Int(area.y), Int(frame.buffer.area.y))
    let right = min(Int(area.x) + Int(area.width), Int(frame.buffer.area.x) + Int(frame.buffer.area.width))
    let bottom = min(Int(area.y) + Int(area.height), Int(frame.buffer.area.y) + Int(frame.buffer.area.height))
    guard right > left, bottom > top else { return }

    for row in stride(from: 0, to: Self.source.count - 1, by: 2) {
      let outputY = Int(area.y) + row / 2
      guard outputY >= top, outputY < bottom else { continue }
      for (column, pair) in zip(Self.source[row], Self.source[row + 1]).enumerated() {
        let outputX = Int(area.x) + column
        guard outputX >= left, outputX < right else { continue }
        let position = Position(x: UInt16(clamping: outputX), y: UInt16(clamping: outputY))
        var cell = frame.buffer[position]
        let topPixel = pair.0
        let bottomPixel = pair.1
        let colors = colors(forTop: topPixel, bottom: bottomPixel)
        if let foreground = colors.foreground { cell.style.foreground = foreground }
        if let background = colors.background { cell.style.background = background }
        if let symbol = symbol(forTop: topPixel, bottom: bottomPixel) {
          cell.symbol = String(symbol)
          cell.width = 1
        }
        frame.buffer[position] = cell
      }
    }
  }

  private func color(for pixel: Character) -> Color? {
    switch pixel {
    case "█": .indexed(252)
    case "h": .indexed(231)
    case "e": eyeColor == .red ? .indexed(196) : .indexed(236)
    case "░": .indexed(232)
    case "▒": .indexed(237)
    case "▓": .indexed(248)
    default: nil
    }
  }

  private func colors(
    forTop top: Character,
    bottom: Character
  ) -> (foreground: Color?, background: Color?) {
    switch (top, bottom) {
    case (" ", " "):
      (nil, nil)
    case (let pixel, " "), (" ", let pixel):
      (color(for: pixel), nil)
    case ("░", "▒"):
      (color(for: "▒"), color(for: "░"))
    case ("░", let pixel), (let pixel, "░"):
      (color(for: pixel), color(for: "░"))
    case (let top, let bottom):
      (color(for: top), color(for: bottom))
    }
  }

  private func symbol(forTop top: Character, bottom: Character) -> Character? {
    switch (top, bottom) {
    case (" ", " "): nil
    case ("░", "░"): " "
    case (_, " "), (_, "░"): Symbols.Block.upperHalf
    case (" ", _), ("░", _): Symbols.Block.lowerHalf
    case (let top, let bottom) where top == bottom: Symbols.Block.full
    default: Symbols.Block.upperHalf
    }
  }

  private static let source = [
    "               hhh",
    "             hhhhhh",
    "            hhhhhhh",
    "           hhhhhhhh",
    "          hhhhhhhhh",
    "         hhhhhhhhhh",
    "        hhhhhhhhhhhh",
    "        hhhhhhhhhhhhh",
    "        hhhhhhhhhhhhh     ██████",
    "         hhhhhhhhhhh    ████████",
    "              hhhhh ███████████",
    "               hhh ██ee████████",
    "                h █████████████",
    "            ████ █████████████",
    "           █████████████████",
    "           ████████████████",
    "           ████████████████",
    "            ███ ██████████",
    "          ▒▒    █████████",
    "         ▒░░▒   █████████",
    "        ▒░░░░▒ ██████████",
    "       ▒░░▓░░░▒ █████████",
    "      ▒░░▓▓░░░░▒ ████████",
    "     ▒░░░░░░░░░░▒ ██████████",
    "    ▒░░░░░░░░░░░░▒ ██████████",
    "   ▒░░░░░░░▓▓░░░░░▒ █████████",
    "  ▒░░░░░░░░░▓▓░░░░░▒ ████  ███",
    " ▒░░░░░░░░░░░░░░░░░░▒ ██   ███",
    "▒░░░░░░░░░░░░░░░░░░░░▒ █   ███",
    "▒░░░░░░░░░░░░░░░░░░░░░▒   ███",
    " ▒░░░░░░░░░░░░░░░░░░░░░▒ ███",
    "  ▒░░░░░░░░░░░░░░░░░░░░░▒ █",
  ]
}
