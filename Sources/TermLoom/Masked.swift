/// Text whose rendered and diagnostic representations replace every grapheme
/// with a caller-selected mask character.
///
/// Unlike an ordinary string wrapper, `description` and `debugDescription`
/// never reveal the underlying value. Applications should retain the source
/// string separately when they need to edit or submit it.
public struct Masked: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible,
  Widget
{
  private var source: String
  public var mask: Character

  public init(_ source: String, mask: Character = "•") {
    self.source = source
    self.mask = mask
  }

  public var maskedValue: String {
    String(repeating: String(mask), count: source.count)
  }

  public var description: String { maskedValue }
  public var debugDescription: String { maskedValue }

  public func render(in area: Rect, into frame: inout Frame) {
    Text(maskedValue).render(in: area, into: &frame.buffer, environment: frame.environment)
  }
}

extension Text {
  public init(
    _ masked: Masked,
    style: Style = .plain,
    alignment: Alignment = .leading
  ) {
    self.init(masked.maskedValue, style: style, alignment: alignment)
  }
}

extension Span {
  public init(_ masked: Masked, style: Style = .plain) {
    self.init(masked.maskedValue, style: style)
  }
}

extension Line {
  public init(_ masked: Masked, alignment: Alignment = .leading) {
    self.init(masked.maskedValue, alignment: alignment)
  }
}
