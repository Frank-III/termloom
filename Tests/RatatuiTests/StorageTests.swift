import Testing

@testable import Ratatui

@Suite struct StorageTests {
  @Test func hotValuesStayWithinMeasuredBudgets() {
    #expect(MemoryLayout<Position>.stride == 16)
    #expect(MemoryLayout<Style>.stride <= 16)
    #expect(MemoryLayout<Cell>.stride <= 32)
    #expect(MemoryLayout<CellUpdate>.stride <= 48)
  }

  @Test func ordinaryTerminalBuffersRemainModest() {
    let doubleBufferedBytes = 120 * 40 * MemoryLayout<Cell>.stride * 2
    #expect(doubleBufferedBytes <= 320 * 1024)
  }

  @Test func stylePatchingCanExplicitlyRemoveAndRestoreModifiers() {
    let base = Style(modifiers: [.bold, .italic], removedModifiers: [.dim])
    let patched = base.patching(
      Style(underlineColor: .cyan, modifiers: [.dim], removedModifiers: [.bold])
    )

    #expect(patched.modifiers == [.dim, .italic])
    #expect(patched.removedModifiers == [.bold])
    #expect(patched.underlineColor == .cyan)
    #expect(patched.adding(.bold).removedModifiers.contains(.bold) == false)
    #expect(patched.removing(.italic).modifiers.contains(.italic) == false)
  }

  @Test func colorsParseAliasesHexAndIndexedFormsWithoutGrowingStyle() {
    #expect(Color("bright-red") == .lightRed)
    #expect(Color("dark grey") == .darkGray)
    #expect(Color("silver") == .gray)
    #expect(Color("#12aBcD") == .rgb(0x12, 0xAB, 0xCD))
    #expect(Color("255") == .indexed(255))
    #expect(Color("256") == nil)
    #expect(Color("#1234") == nil)
    #expect(Color(rgb: 0x12ABCD) == .rgb(0x12, 0xAB, 0xCD))

    let colors: [Color] = [
      .reset, .black, .red, .green, .yellow, .blue, .magenta, .cyan, .gray, .darkGray,
      .lightRed, .lightGreen, .lightYellow, .lightBlue, .lightMagenta, .lightCyan, .white,
      .indexed(42), .rgb(1, 2, 3),
    ]
    for color in colors {
      #expect(Color(color.description) == color)
      #expect(Style(foreground: color).foreground == color)
    }
    #expect(MemoryLayout<Style>.stride == 16)
  }
}
