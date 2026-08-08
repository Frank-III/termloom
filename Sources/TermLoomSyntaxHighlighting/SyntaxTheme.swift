import Foundation
import TermLoom

public struct SyntaxTokenStyle: Hashable, Sendable {
  public var foreground: Color?
  public var background: Color?
  public var modifiers: Modifier

  public init(
    foreground: Color? = nil, background: Color? = nil, modifiers: Modifier = []
  ) {
    self.foreground = foreground
    self.background = background
    self.modifiers = modifiers
  }

  public var style: Style {
    Style(foreground: foreground, background: background, modifiers: modifiers)
  }

  func merged(over base: Self) -> Self {
    Self(
      foreground: foreground ?? base.foreground,
      background: background ?? base.background,
      modifiers: base.modifiers.union(modifiers))
  }
}

public struct SyntaxTheme: Identifiable, Hashable, Sendable {
  public var id: String { name }
  public var name: String
  public var plain: SyntaxTokenStyle
  public var background: Color?
  public var scopes: [String: SyntaxTokenStyle]
  public var sourceURL: URL?

  public init(
    name: String,
    plain: SyntaxTokenStyle = .init(),
    background: Color? = nil,
    scopes: [String: SyntaxTokenStyle] = [:],
    sourceURL: URL? = nil
  ) {
    self.name = name
    self.plain = plain
    self.background = background
    self.scopes = scopes
    self.sourceURL = sourceURL
  }

  public func style(for scope: String) -> SyntaxTokenStyle {
    if scope.hasPrefix("language:") { return plain }
    if let exact = scopes[scope] { return exact.merged(over: plain) }
    var candidate = scope
    while let dot = candidate.lastIndex(of: ".") {
      candidate = String(candidate[..<dot])
      if let style = scopes[candidate] { return style.merged(over: plain) }
    }
    let normalized = scope.replacingOccurrences(of: "_", with: "")
    return (scopes[normalized] ?? .init()).merged(over: plain)
  }
}

extension SyntaxTheme {
  private static func palette(
    _ name: String, foreground: UInt32, background: UInt32, comment: UInt32,
    keyword: UInt32, string: UInt32, number: UInt32, type: UInt32, function: UInt32,
    accent: UInt32? = nil
  ) -> Self {
    let accent = accent ?? function
    return Self(
      name: name,
      plain: .init(foreground: .init(rgb: foreground)),
      background: .init(rgb: background),
      scopes: [
        "comment": .init(foreground: .init(rgb: comment), modifiers: [.italic]),
        "quote": .init(foreground: .init(rgb: comment), modifiers: [.italic]),
        "keyword": .init(foreground: .init(rgb: keyword)),
        "doctag": .init(foreground: .init(rgb: keyword)),
        "meta.keyword": .init(foreground: .init(rgb: keyword)),
        "selector-tag": .init(foreground: .init(rgb: keyword)),
        "string": .init(foreground: .init(rgb: string)),
        "regexp": .init(foreground: .init(rgb: string)),
        "meta.string": .init(foreground: .init(rgb: string)),
        "number": .init(foreground: .init(rgb: number)),
        "literal": .init(foreground: .init(rgb: number)),
        "type": .init(foreground: .init(rgb: type)),
        "built_in": .init(foreground: .init(rgb: type)),
        "title": .init(foreground: .init(rgb: function)),
        "title.function": .init(foreground: .init(rgb: function)),
        "title.class": .init(foreground: .init(rgb: type)),
        "attr": .init(foreground: .init(rgb: accent)),
        "attribute": .init(foreground: .init(rgb: accent)),
        "variable": .init(foreground: .init(rgb: accent)),
        "operator": .init(foreground: .init(rgb: accent)),
        "symbol": .init(foreground: .init(rgb: accent)),
        "meta": .init(foreground: .init(rgb: accent)),
        "section": .init(foreground: .init(rgb: function), modifiers: [.bold]),
        "addition": .init(foreground: .init(rgb: string)),
        "deletion": .init(foreground: .init(rgb: keyword)),
        "emphasis": .init(modifiers: [.italic]),
        "strong": .init(modifiers: [.bold]),
      ])
  }

  public static let builtins: [Self] = [
    palette(
      "1337", foreground: 0xF7F7F7, background: 0x191919, comment: 0x666666, keyword: 0xFF0055,
      string: 0x55FF55, number: 0xFFAA00, type: 0x00FFFF, function: 0x55AAFF),
    palette(
      "ansi", foreground: 0xD0D0D0, background: 0x000000, comment: 0x808080, keyword: 0xFF5F5F,
      string: 0x5FFF5F, number: 0xFFFF5F, type: 0x5FFFFF, function: 0x5F87FF),
    palette(
      "base16", foreground: 0xD8D8D8, background: 0x181818, comment: 0x585858, keyword: 0xBA8BAF,
      string: 0xA1B56C, number: 0xDC9656, type: 0xF7CA88, function: 0x7CAFC2),
    palette(
      "base16-256", foreground: 0xD8D8D8, background: 0x181818, comment: 0x585858,
      keyword: 0xAF87AF, string: 0x87AF5F, number: 0xD7875F, type: 0xFFD787, function: 0x5FAFD7),
    palette(
      "base16-eighties-dark", foreground: 0xD3D0C8, background: 0x2D2D2D, comment: 0x747369,
      keyword: 0xCC99CC, string: 0x99CC99, number: 0xF99157, type: 0xFFCC66, function: 0x6699CC),
    palette(
      "base16-mocha-dark", foreground: 0xD0C8C6, background: 0x3B3228, comment: 0x7E705A,
      keyword: 0xA89BB9, string: 0xBEB55B, number: 0xD28B71, type: 0xF4BC87, function: 0x7BBDA4),
    palette(
      "base16-ocean-dark", foreground: 0xC0C5CE, background: 0x2B303B, comment: 0x65737E,
      keyword: 0xB48EAD, string: 0xA3BE8C, number: 0xD08770, type: 0xEBCB8B, function: 0x8FA1B3),
    palette(
      "base16-ocean-light", foreground: 0x4F5B66, background: 0xEFF1F5, comment: 0xA7ADBA,
      keyword: 0xB48EAD, string: 0xA3BE8C, number: 0xD08770, type: 0xD08770, function: 0x6699CC),
    palette(
      "catppuccin-frappe", foreground: 0xC6D0F5, background: 0x303446, comment: 0x949CBB,
      keyword: 0xCA9EE6, string: 0xA6D189, number: 0xEF9F76, type: 0xE5C890, function: 0x8CAAEE,
      accent: 0x81C8BE),
    palette(
      "catppuccin-latte", foreground: 0x4C4F69, background: 0xEFF1F5, comment: 0x7C7F93,
      keyword: 0x8839EF, string: 0x40A02B, number: 0xFE640B, type: 0xDF8E1D, function: 0x1E66F5,
      accent: 0x179299),
    palette(
      "catppuccin-macchiato", foreground: 0xCAD3F5, background: 0x24273A, comment: 0x939AB7,
      keyword: 0xC6A0F6, string: 0xA6DA95, number: 0xF5A97F, type: 0xEED49F, function: 0x8AADF4,
      accent: 0x8BD5CA),
    palette(
      "catppuccin-mocha", foreground: 0xCDD6F4, background: 0x1E1E2E, comment: 0x9399B2,
      keyword: 0xCBA6F7, string: 0xA6E3A1, number: 0xFAB387, type: 0xF9E2AF, function: 0x89B4FA,
      accent: 0x94E2D5),
    palette(
      "coldark-cold", foreground: 0x111B27, background: 0xE3EAF2, comment: 0x3C526D,
      keyword: 0x74531F, string: 0x116B00, number: 0x755F00, type: 0x005A8E, function: 0x005A8E),
    palette(
      "coldark-dark", foreground: 0xE3EAF2, background: 0x111B27, comment: 0x8DA1B9,
      keyword: 0xE9AE7E, string: 0xB4D273, number: 0xF78C6C, type: 0x6CB8E6, function: 0x82AAFF),
    palette(
      "dark-neon", foreground: 0xFFFFFF, background: 0x000000, comment: 0x7F7F7F, keyword: 0xFF00FF,
      string: 0x00FF00, number: 0xFF8800, type: 0x00FFFF, function: 0x00AAFF),
    palette(
      "dracula", foreground: 0xF8F8F2, background: 0x282A36, comment: 0x6272A4, keyword: 0xFF79C6,
      string: 0xF1FA8C, number: 0xBD93F9, type: 0x8BE9FD, function: 0x50FA7B),
    palette(
      "github", foreground: 0x24292E, background: 0xFFFFFF, comment: 0x6A737D, keyword: 0xD73A49,
      string: 0x032F62, number: 0x005CC5, type: 0x6F42C1, function: 0x6F42C1),
    palette(
      "gruvbox-dark", foreground: 0xEBDBB2, background: 0x282828, comment: 0x928374,
      keyword: 0xFB4934, string: 0xB8BB26, number: 0xD3869B, type: 0xFABD2F, function: 0x83A598),
    palette(
      "gruvbox-light", foreground: 0x3C3836, background: 0xFBF1C7, comment: 0x928374,
      keyword: 0x9D0006, string: 0x79740E, number: 0x8F3F71, type: 0xB57614, function: 0x076678),
    palette(
      "inspired-github", foreground: 0x323232, background: 0xFFFFFF, comment: 0x969896,
      keyword: 0xA71D5D, string: 0x183691, number: 0x0086B3, type: 0x795DA3, function: 0x795DA3),
    palette(
      "monokai-extended", foreground: 0xF8F8F2, background: 0x272822, comment: 0x75715E,
      keyword: 0xF92672, string: 0xE6DB74, number: 0xAE81FF, type: 0x66D9EF, function: 0xA6E22E),
    palette(
      "monokai-extended-bright", foreground: 0xF8F8F2, background: 0x272822, comment: 0x88846F,
      keyword: 0xFF007F, string: 0xF3E430, number: 0xC48DFF, type: 0x75DFFF, function: 0xB7F34B),
    palette(
      "monokai-extended-light", foreground: 0x49483E, background: 0xFAFAFA, comment: 0x88846F,
      keyword: 0xF92672, string: 0x998A00, number: 0x7C4DFF, type: 0x0088A8, function: 0x669900),
    palette(
      "monokai-extended-origin", foreground: 0xF8F8F2, background: 0x272822, comment: 0x75715E,
      keyword: 0xF92672, string: 0xE6DB74, number: 0xAE81FF, type: 0x66D9EF, function: 0xA6E22E),
    palette(
      "nord", foreground: 0xD8DEE9, background: 0x2E3440, comment: 0x616E88, keyword: 0x81A1C1,
      string: 0xA3BE8C, number: 0xB48EAD, type: 0x8FBCBB, function: 0x88C0D0),
    palette(
      "one-half-dark", foreground: 0xDCDFE4, background: 0x282C34, comment: 0x5C6370,
      keyword: 0xC678DD, string: 0x98C379, number: 0xD19A66, type: 0xE5C07B, function: 0x61AFEF),
    palette(
      "one-half-light", foreground: 0x383A42, background: 0xFAFAFA, comment: 0xA0A1A7,
      keyword: 0xA626A4, string: 0x50A14F, number: 0x986801, type: 0xC18401, function: 0x4078F2),
    palette(
      "solarized-dark", foreground: 0x839496, background: 0x002B36, comment: 0x586E75,
      keyword: 0x859900, string: 0x2AA198, number: 0xD33682, type: 0xB58900, function: 0x268BD2),
    palette(
      "solarized-light", foreground: 0x657B83, background: 0xFDF6E3, comment: 0x93A1A1,
      keyword: 0x859900, string: 0x2AA198, number: 0xD33682, type: 0xB58900, function: 0x268BD2),
    palette(
      "sublime-snazzy", foreground: 0xEFF0EB, background: 0x282A36, comment: 0x686868,
      keyword: 0xFF5C57, string: 0x5AF78E, number: 0xF3F99D, type: 0x9AEDFE, function: 0x57C7FF),
    palette(
      "two-dark", foreground: 0xABB2BF, background: 0x282C34, comment: 0x5C6370, keyword: 0xC678DD,
      string: 0x98C379, number: 0xD19A66, type: 0xE5C07B, function: 0x61AFEF),
    palette(
      "zenburn", foreground: 0xDCDCCC, background: 0x3F3F3F, comment: 0x7F9F7F, keyword: 0xF0DFAF,
      string: 0xCC9393, number: 0x8CD0D3, type: 0x93E0E3, function: 0xEFEF8F),
  ]

  public static let defaultName = "base16-ocean-dark"

  public static func named(_ name: String) -> Self? {
    builtins.first { $0.name == name }
  }
}
