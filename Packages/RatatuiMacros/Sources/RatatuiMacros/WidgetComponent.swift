import Ratatui

/// Synthesizes `Widget` conformance by forwarding rendering, interaction, and cursor metadata to `body`.
///
/// Use this for lightweight custom components whose entire presentation is expressed by another widget:
///
/// ```swift
/// @WidgetComponent
/// struct EmptyState {
///   var message: String
///
///   var body: some Widget {
///     Text(message, alignment: .center).dim()
///   }
/// }
/// ```
///
/// The macro deliberately does not synthesize state, event handling, layout policy, or an application runtime.
@attached(
  extension,
  conformances: Widget,
  names: named(render), named(collectInteractions), named(cursorPosition), named(cursorStyle)
)
public macro WidgetComponent() =
  #externalMacro(module: "RatatuiWidgetMacros", type: "WidgetComponentMacro")
