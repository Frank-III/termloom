import Foundation
import TermLoom

public enum TextMateThemeError: Error, LocalizedError, Sendable {
  case invalidPropertyList
  case missingName

  public var errorDescription: String? {
    switch self {
    case .invalidPropertyList: "The .tmTheme file is not a valid TextMate property list."
    case .missingName: "The .tmTheme file has no theme name."
    }
  }
}

extension SyntaxTheme {
  public static func textMateTheme(at url: URL) throws -> Self {
    let data = try Data(contentsOf: url)
    guard
      let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        as? [String: Any]
    else { throw TextMateThemeError.invalidPropertyList }
    let name = (plist["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let name, !name.isEmpty else { throw TextMateThemeError.missingName }
    let globals = (plist["settings"] as? [[String: Any]])?.first?["settings"] as? [String: Any]
    let foreground = globals?["foreground"] as? String
    let background = globals?["background"] as? String
    var theme = Self(
      name: name,
      plain: .init(foreground: foreground.flatMap(terminalColor)),
      background: background.flatMap(terminalColor),
      sourceURL: url)
    for item in (plist["settings"] as? [[String: Any]]) ?? [] {
      guard let sourceScopes = item["scope"] as? String,
        let settings = item["settings"] as? [String: Any]
      else { continue }
      let style = SyntaxTokenStyle(
        foreground: (settings["foreground"] as? String).flatMap(terminalColor),
        background: (settings["background"] as? String).flatMap(terminalColor),
        modifiers: modifiers(from: settings["fontStyle"] as? String))
      for sourceScope in sourceScopes.split(separator: ",").map({
        $0.trimmingCharacters(in: .whitespaces)
      }) {
        for target in highlightScopes(forTextMateScope: sourceScope) {
          theme.scopes[target] = style
        }
      }
    }
    return theme
  }

  private static func modifiers(from fontStyle: String?) -> Modifier {
    guard let fontStyle else { return [] }
    var result: Modifier = []
    if fontStyle.contains("bold") { result.insert(.bold) }
    if fontStyle.contains("italic") { result.insert(.italic) }
    if fontStyle.contains("underline") { result.insert(.underlined) }
    return result
  }

  private static func terminalColor(_ source: String) -> Color? {
    if source.count == 9, source.hasPrefix("#") {
      return Color(String(source.prefix(7)))
    }
    if source.count == 4, source.hasPrefix("#") {
      let digits = source.dropFirst()
      return Color("#" + digits.map { "\($0)\($0)" }.joined())
    }
    return Color(source)
  }

  private static func highlightScopes(forTextMateScope scope: String) -> [String] {
    if scope.contains("comment") { return ["comment", "quote"] }
    if scope.contains("string") { return ["string", "regexp", "meta.string"] }
    if scope.contains("constant.numeric") { return ["number"] }
    if scope.contains("constant") { return ["literal", "symbol", "number"] }
    if scope.contains("keyword") || scope.contains("storage") {
      return ["keyword", "meta.keyword", "operator"]
    }
    if scope.contains("entity.name.type") || scope.contains("support.type") {
      return ["type", "title.class", "built_in"]
    }
    if scope.contains("entity.name.function") || scope.contains("support.function") {
      return ["title", "title.function"]
    }
    if scope.contains("variable") { return ["variable", "attr", "attribute"] }
    if scope.contains("invalid") { return ["deletion"] }
    if scope.contains("markup.inserted") { return ["addition"] }
    if scope.contains("markup.deleted") { return ["deletion"] }
    if scope.contains("markup.bold") { return ["strong"] }
    if scope.contains("markup.italic") { return ["emphasis"] }
    return []
  }
}
