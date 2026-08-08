import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

private enum WidgetComponentError: Error, CustomStringConvertible {
  case unsupportedDeclaration
  case genericDeclaration
  case missingBody

  var description: String {
    switch self {
    case .unsupportedDeclaration:
      "@WidgetComponent can only be attached to a struct or final class"
    case .genericDeclaration:
      "@WidgetComponent does not yet support generic declarations"
    case .missingBody:
      "@WidgetComponent requires a 'body' property whose value conforms to Widget"
    }
  }
}

public struct WidgetComponentMacro: ExtensionMacro {
  public static func expansion(
    of node: AttributeSyntax,
    attachedTo declaration: some DeclGroupSyntax,
    providingExtensionsOf type: some TypeSyntaxProtocol,
    conformingTo protocols: [TypeSyntax],
    in context: some MacroExpansionContext
  ) throws -> [ExtensionDeclSyntax] {
    let modifiers: DeclModifierListSyntax
    let genericParameters: GenericParameterClauseSyntax?
    let members: MemberBlockItemListSyntax
    if let declaration = declaration.as(StructDeclSyntax.self) {
      modifiers = declaration.modifiers
      genericParameters = declaration.genericParameterClause
      members = declaration.memberBlock.members
    } else if let declaration = declaration.as(ClassDeclSyntax.self),
      declaration.modifiers.contains(where: { $0.name.tokenKind == .keyword(.final) })
    {
      modifiers = declaration.modifiers
      genericParameters = declaration.genericParameterClause
      members = declaration.memberBlock.members
    } else {
      throw WidgetComponentError.unsupportedDeclaration
    }
    guard genericParameters == nil else { throw WidgetComponentError.genericDeclaration }
    let hasBody = members.contains { member in
      guard let variable = member.decl.as(VariableDeclSyntax.self),
        !variable.modifiers.contains(where: {
          $0.name.tokenKind == .keyword(.static) || $0.name.tokenKind == .keyword(.class)
        })
      else { return false }
      return variable.bindings.contains { binding in
        binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == "body"
      }
    }
    guard hasBody else { throw WidgetComponentError.missingBody }
    let access =
      modifiers.contains(where: {
        $0.name.tokenKind == .keyword(.public) || $0.name.tokenKind == .keyword(.open)
      }) ? "public " : ""

    let conformance = protocols.isEmpty ? "" : ": TermLoom.Widget"
    let declaration: DeclSyntax = """
      extension \(type.trimmed)\(raw: conformance) {
        \(raw: access)func render(
          in area: TermLoom.Rect,
          into frame: inout TermLoom.Frame
        ) {
          frame.render(body, in: area)
        }
      }
      """
    guard let result = declaration.as(ExtensionDeclSyntax.self) else { return [] }
    return [result]
  }
}

@main
struct TermLoomWidgetPlugin: CompilerPlugin {
  let providingMacros: [Macro.Type] = [WidgetComponentMacro.self]
}
