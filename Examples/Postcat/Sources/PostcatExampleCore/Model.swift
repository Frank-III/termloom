import Foundation
import Ratatui
import RatatuiSyntaxHighlighting

extension Line {
  init(_ spans: [Span], alignment: Alignment? = nil) {
    self.init("")
    self.spans = spans
    self.alignment = alignment
  }
}

public enum HTTPMethod: String, CaseIterable, Hashable, Sendable {
  case get = "GET"
  case post = "POST"
  case put = "PUT"
  case patch = "PATCH"
  case delete = "DELETE"

  mutating func cycle(_ delta: Int = 1) {
    let methods = Self.allCases
    let index = methods.firstIndex(of: self) ?? 0
    self = methods[(index + delta + methods.count) % methods.count]
  }
}

public struct APIRequest: Hashable, Sendable {
  public var method: HTTPMethod
  public var url: String
  public var body: String

  public init(method: HTTPMethod, url: String, body: String = "") {
    self.method = method
    self.url = url
    self.body = body
  }
}

public struct APIResponse: Hashable, Sendable {
  public var status: Int
  public var reason: String
  public var headers: [(String, String)]
  public var body: String
  public var durationMilliseconds: Int
  public var size: Int

  public init(
    status: Int,
    reason: String = "",
    headers: [(String, String)] = [],
    body: String,
    durationMilliseconds: Int = 0,
    size: Int? = nil
  ) {
    self.status = status
    self.reason = reason
    self.headers = headers
    self.body = body
    self.durationMilliseconds = durationMilliseconds
    self.size = size ?? body.utf8.count
  }

  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.status == rhs.status && lhs.reason == rhs.reason
      && lhs.headers.elementsEqual(
        rhs.headers, by: ==)
      && lhs.body == rhs.body
      && lhs.durationMilliseconds == rhs.durationMilliseconds && lhs.size == rhs.size
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(status)
    hasher.combine(reason)
    for header in headers {
      hasher.combine(header.0)
      hasher.combine(header.1)
    }
    hasher.combine(body)
    hasher.combine(durationMilliseconds)
    hasher.combine(size)
  }
}

public typealias RequestSender = @Sendable (APIRequest) async throws -> APIResponse

public enum ResponseTab: Hashable, Sendable {
  case body
  case headers
}

public enum AppFocus: Int, CaseIterable, Hashable, Sendable {
  case url
  case request
  case response

  mutating func advance(_ delta: Int = 1) {
    let values = Self.allCases
    self = values[(rawValue + delta + values.count) % values.count]
  }
}

enum ExampleTheme {
  static let foreground = Color.rgb(0xC0, 0xCA, 0xF5)
  static let pale = Color.rgb(0x9A, 0xA5, 0xCE)
  static let dim = Color.rgb(0x56, 0x5F, 0x89)
  static let border = Color.rgb(0x3B, 0x42, 0x61)
  static let selection = Color.rgb(0x28, 0x34, 0x57)
  static let dark = Color.rgb(0x16, 0x16, 0x1E)
  static let accent = Color.rgb(0x7A, 0xA2, 0xF7)
  static let purple = Color.rgb(0xBB, 0x9A, 0xF7)
  static let green = Color.rgb(0x9E, 0xCE, 0x6A)
  static let red = Color.rgb(0xF7, 0x76, 0x8E)
  static let yellow = Color.rgb(0xE0, 0xAF, 0x68)
  static let orange = Color.rgb(0xFF, 0x9E, 0x64)
  static let cyan = Color.rgb(0x7D, 0xCF, 0xFF)

  static func method(_ method: HTTPMethod) -> Color {
    switch method {
    case .get: green
    case .post: accent
    case .put: yellow
    case .patch: purple
    case .delete: red
    }
  }

  static func status(_ code: Int) -> Color {
    switch code {
    case 200..<300: green
    case 300..<400: yellow
    case 400..<500: orange
    default: red
    }
  }

  static let syntax = SyntaxTheme(
    name: "Postcat",
    plain: SyntaxTokenStyle(foreground: foreground),
    scopes: [
      "string": SyntaxTokenStyle(foreground: green),
      "number": SyntaxTokenStyle(foreground: orange),
      "literal": SyntaxTokenStyle(foreground: purple),
      "keyword": SyntaxTokenStyle(foreground: accent),
      "property": SyntaxTokenStyle(foreground: cyan),
      "punctuation": SyntaxTokenStyle(foreground: dim),
    ]
  )
}

func responseLines(for response: APIResponse, tab: ResponseTab) -> [Line] {
  switch tab {
  case .headers:
    return response.headers.map { name, value in
      Line([
        Span(name, style: Style(foreground: ExampleTheme.cyan)),
        Span(": ", style: Style(foreground: ExampleTheme.dim)),
        Span(value, style: Style(foreground: ExampleTheme.foreground)),
      ])
    }
  case .body:
    let source: String
    if let object = try? JSONSerialization.jsonObject(with: Data(response.body.utf8)),
      let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted]),
      let formatted = String(data: data, encoding: .utf8)
    {
      source = formatted
    } else {
      source = response.body
    }
    return TerminalSyntaxHighlighter().highlightLines(
      source,
      language: source == response.body ? nil : "json",
      theme: ExampleTheme.syntax
    ).map { spans in
      var line = Line("")
      line.spans = spans
      return line
    }
  }
}

func humanSize(_ bytes: Int) -> String {
  if bytes < 1_024 { return "\(bytes) B" }
  if bytes < 1_048_576 { return String(format: "%.1f KiB", Double(bytes) / 1_024) }
  return String(format: "%.1f MiB", Double(bytes) / 1_048_576)
}
