import Ratatui

/// Renders a layer over base content without introducing retained view state.
public struct Overlay<Base: Widget, Layer: Widget>: Widget {
  public var isPresented: Bool
  public var isModal: Bool
  public var hidesBaseCursor: Bool
  public var base: Base
  public var layer: Layer

  public init(
    isPresented: Bool = true,
    isModal: Bool = true,
    hidesBaseCursor: Bool = true,
    base: Base,
    layer: Layer
  ) {
    self.isPresented = isPresented
    self.isModal = isModal
    self.hidesBaseCursor = hidesBaseCursor
    self.base = base
    self.layer = layer
  }

  public func render(in area: Rect, into frame: inout Frame) {
    frame.render(base, in: area, collectsInteractions: !isPresented || !isModal)
    guard isPresented else { return }

    let baseCursor = frame.cursorPosition
    let baseCursorStyle = frame.cursorStyle
    frame.placeCursor(at: nil)
    frame.render(layer, in: area)
    if frame.cursorPosition == nil, !hidesBaseCursor {
      frame.placeCursor(at: baseCursor, style: baseCursorStyle)
    }
  }
}
