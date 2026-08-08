import SwiftSyntaxMacrosTestSupport
import TermLoomWidgetMacros
import XCTest

final class WidgetComponentExpansionTests: XCTestCase {
  private let macros = ["WidgetComponent": WidgetComponentMacro.self]

  func testMissingBodyDiagnostic() {
    assertMacroExpansion(
      "@WidgetComponent struct Missing {}",
      expandedSource: "struct Missing {}",
      diagnostics: [
        DiagnosticSpec(
          message: "@WidgetComponent requires a 'body' property whose value conforms to Widget",
          line: 1,
          column: 1)
      ],
      macros: macros)
  }

  func testStaticBodyDiagnostic() {
    assertMacroExpansion(
      "@WidgetComponent struct StaticBody { static var body: Never }",
      expandedSource: """
        struct StaticBody { static var body: Never 
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message: "@WidgetComponent requires a 'body' property whose value conforms to Widget",
          line: 1,
          column: 1)
      ],
      macros: macros)
  }

  func testGenericDiagnostic() {
    assertMacroExpansion(
      """
      @WidgetComponent
      struct Generic<Value> {
        var body: Value
      }
      """,
      expandedSource: """
        struct Generic<Value> {
          var body: Value
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message: "@WidgetComponent does not yet support generic declarations",
          line: 1,
          column: 1)
      ],
      macros: macros)
  }
}
