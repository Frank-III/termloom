public enum TerminalWidthPolicy: Hashable, Sendable {
  case standard
  case cjk
}

public enum TerminalWidth {
  public static let unicodeVersion = (major: 17, minor: 0, patch: 0)

  public static func of(
    _ character: Character,
    policy: TerminalWidthPolicy = .standard
  ) -> Int {
    if character.isASCII, let value = character.asciiValue {
      return value < 0x20 || value == 0x7F ? 0 : 1
    }
    let scalars = character.unicodeScalars
    if scalars.count == 1, let scalar = scalars.first {
      return scalarWidth(scalar, policy: policy)
    }
    return width(of: Array(scalars), policy: policy)
  }

  public static func of(
    _ string: String,
    policy: TerminalWidthPolicy = .standard
  ) -> Int {
    if string.utf8.allSatisfy({ $0 < 0x80 }) {
      return string.utf8.reduce(into: 0) { width, byte in
        if byte >= 0x20, byte != 0x7F { width += 1 }
      }
    }
    return width(of: Array(string.unicodeScalars), policy: policy)
  }

  private static func width(
    of scalars: [UnicodeScalar],
    policy: TerminalWidthPolicy
  ) -> Int {
    guard !scalars.isEmpty else { return 0 }
    var result = scalars.reduce(into: 0) {
      $0 += scalarWidth($1, policy: policy)
    }

    // Presentation selectors modify the immediately preceding base, rather
    // than having an unconditional width of their own.
    for index in scalars.indices where index > scalars.startIndex {
      let scalar = scalars[index]
      let base = scalars[index - 1]
      if scalar.value == 0xFE0F, base.properties.isEmoji {
        result += max(0, 2 - scalarWidth(base, policy: policy))
      } else if scalar.value == 0xFE0E,
        policy == .standard,
        base.properties.isEmojiPresentation,
        !(0x1F200...0x1F2FF).contains(base.value)
      {
        result -= max(0, scalarWidth(base, policy: policy) - 1)
      }
    }
    if policy == .standard {
      for index in scalars.indices
      where index > scalars.startIndex && scalars[index].value == 0xFE01
        && [0x2018, 0x2019, 0x201C, 0x201D].contains(scalars[index - 1].value)
      {
        result += 1
      }
    } else {
      for index in scalars.indices
      where index > scalars.startIndex && (0xFE00...0xFE02).contains(scalars[index].value)
        && [0x2018, 0x2019, 0x201C, 0x201D].contains(scalars[index - 1].value)
      {
        result -= 1
      }
      for index in scalars.indices
      where scalars[index].value == 0x3C || scalars[index].value == 0x3D
        || scalars[index].value == 0x3E
      {
        var cursor = index + 1
        while cursor < scalars.count, isSolidusTransparent(scalars[cursor]) { cursor += 1 }
        if cursor < scalars.count, scalars[cursor].value == 0x0338 { result += 1 }
      }
    }

    // Emoji modifiers and each well-formed ZWJ edge form a two-cell ligature.
    for index in scalars.indices where index > scalars.startIndex {
      if (0x1F3FB...0x1F3FF).contains(scalars[index].value),
        scalars[index - 1].properties.isEmojiModifierBase
      {
        let sequenceWidth =
          scalarWidth(scalars[index - 1], policy: policy)
          + scalarWidth(scalars[index], policy: policy)
        result -= max(0, sequenceWidth - 2)
      }
    }
    for index in scalars.indices where scalars[index].value == 0x200D {
      guard index > scalars.startIndex, index + 1 < scalars.endIndex else { continue }
      guard scalars[index - 1].value != 0x200D, scalars[index + 1].value != 0x200D else {
        continue
      }
      if emojiComponent(before: index, in: scalars)
        && emojiComponent(after: index, in: scalars)
      {
        result -= 2
      }
    }

    result += scriptLigatureAdjustment(scalars)
    return max(0, result)
  }

  private static func scalarWidth(
    _ scalar: UnicodeScalar,
    policy: TerminalWidthPolicy
  ) -> Int {
    let value = scalar.value
    if value < 0x20 || (0x7F...0x9F).contains(value) { return 0 }
    if (0x1F1E6...0x1F1FF).contains(value) { return 1 }
    switch value {
    case 0x115F, 0x17A4: return 2
    case 0x17D8: return 3
    case 0x2D7F, 0xFF9E, 0xFF9F: return 1
    default:
      if isZeroWidth(value) { return 0 }
      return isWide(value, policy: policy) ? 2 : 1
    }
  }

  private static func emojiComponent(
    before index: Int,
    in scalars: [UnicodeScalar]
  ) -> Bool {
    var start = index - 1
    while start > 0, scalars[start - 1].value != 0x200D { start -= 1 }
    return isEmojiComponent(scalars[start..<index])
  }

  private static func emojiComponent(
    after index: Int,
    in scalars: [UnicodeScalar]
  ) -> Bool {
    var end = index + 1
    while end < scalars.count, scalars[end].value != 0x200D { end += 1 }
    return isEmojiComponent(scalars[(index + 1)..<end])
  }

  private static func isEmojiComponent(_ component: ArraySlice<UnicodeScalar>) -> Bool {
    let values = component.map(\.value)
    guard !values.isEmpty else { return false }
    if values.contains(where: { (0xE0030...0xE007F).contains($0) }) {
      return isValidEmojiTagSequence(values)
    }
    if values.contains(0x20E3) {
      guard values.count == 3, values[1] == 0xFE0F, values[2] == 0x20E3 else {
        return false
      }
      return values[0] == 0x23 || values[0] == 0x2A || (0x30...0x39).contains(values[0])
    }
    let regionalIndicators = values.filter { (0x1F1E6...0x1F1FF).contains($0) }
    if !regionalIndicators.isEmpty {
      return regionalIndicators.count >= 2 && regionalIndicators.count == values.count
    }
    for index in values.indices where values[index] == 0xFE0F {
      guard index > values.startIndex,
        UnicodeScalar(values[index - 1])?.properties.isEmoji == true
      else { return false }
    }
    return component.contains { $0.properties.isEmojiPresentation }
      || component.contains { scalar in
        scalar.properties.isEmoji
          && component.contains(where: { $0.value == 0xFE0F })
      }
  }

  private static func isValidEmojiTagSequence(_ values: [UInt32]) -> Bool {
    guard values.first == 0x1F3F4, values.last == 0xE007F, values.count >= 5 else {
      return false
    }
    let tags = values.dropFirst().dropLast()
    if tags.allSatisfy({ (0xE0061...0xE007A).contains($0) }) {
      return (3...6).contains(tags.count)
    }
    return tags.count == 3 && tags.allSatisfy { (0xE0030...0xE0039).contains($0) }
  }

  private static func scriptLigatureAdjustment(_ scalars: [UnicodeScalar]) -> Int {
    let values = scalars.map(\.value)
    var adjustment = 0
    var index = 0
    while index < values.count {
      if isArabicLam(values[index]) {
        var end = index + 1
        while end < values.count, isTransparentZeroWidth(values[end]) { end += 1 }
        if end < values.count, isArabicAlef(values[end]) {
          adjustment -= 1
          index = end + 1
          continue
        }
      }
      if values[index] == 0x05D0 {
        var end = index + 1
        var sawJoiner = false
        while end < values.count, isLigatureTransparent(values[end]) {
          sawJoiner = sawJoiner || values[end] == 0x200D
          end += 1
        }
        if sawJoiner, end < values.count, values[end] == 0x05DC {
          adjustment -= 1
          index = end + 1
          continue
        }
      }
      if isTifinaghConsonant(values[index]), index + 2 < values.count,
        values[index + 1] == 0x200D || values[index + 1] == 0x2D7F,
        isTifinaghConsonant(values[index + 2])
      {
        adjustment -= values[index + 1] == 0x2D7F ? 2 : 1
        index += 3
        continue
      }
      if values[index] == 0x10C32, index + 2 < values.count,
        values[index + 1] == 0x200D, values[index + 2] == 0x10C03
      {
        adjustment -= 1
        index += 3
        continue
      }
      if values[index] == 0x1A15, index + 3 < values.count,
        values[index + 1] == 0x1A17, values[index + 2] == 0x200D,
        values[index + 3] == 0x1A10
      {
        adjustment -= 1
        index += 4
        continue
      }
      if values[index] == 0x17D2 {
        var end = index + 1
        while end < values.count, values[end] == 0x200D { end += 1 }
        if end < values.count, isKhmerCoengEligible(values[end]) {
          adjustment -= 1
          index = end + 1
          continue
        }
      }
      if (0xA4F8...0xA4FB).contains(values[index]), index + 1 < values.count,
        (0xA4FC...0xA4FD).contains(values[index + 1])
      {
        adjustment -= 1
        index += 2
        continue
      }
      if values[index] == 0x16D63, index + 1 < values.count,
        values[index + 1] == 0x16D67 || values[index + 1] == 0x16D68
      {
        adjustment -= 1
        index += 2
        continue
      }
      index += 1
    }
    return adjustment
  }

  private static func isArabicLam(_ value: UInt32) -> Bool {
    value == 0x0644 || (0x06B5...0x06B8).contains(value) || value == 0x076A
      || value == 0x08A6 || value == 0x08C7
  }

  private static func isArabicAlef(_ value: UInt32) -> Bool {
    (0x0622...0x0625).contains(value) || value == 0x0627
      || (0x0671...0x0673).contains(value) || value == 0x0675
      || (0x0773...0x0774).contains(value)
  }

  private static func isTransparentZeroWidth(_ value: UInt32) -> Bool {
    value != 0x200D && isZeroWidth(value)
  }

  private static func isLigatureTransparent(_ value: UInt32) -> Bool {
    value == 0x034F || (0x17B4...0x17B5).contains(value)
      || (0x180B...0x180D).contains(value) || value == 0x180F || value == 0x200D
      || (0xFE00...0xFE0F).contains(value) || (0xE0100...0xE01EF).contains(value)
  }

  private static func isSolidusTransparent(_ scalar: UnicodeScalar) -> Bool {
    isLigatureTransparent(scalar.value)
      || (0x0300...0x036F).contains(scalar.value) && scalar.value != 0x0338
  }

  private static func isTifinaghConsonant(_ value: UInt32) -> Bool {
    (0x2D31...0x2D65).contains(value) || value == 0x2D6F
  }

  private static func isKhmerCoengEligible(_ value: UInt32) -> Bool {
    (0x1780...0x1782).contains(value) || (0x1784...0x1787).contains(value)
      || (0x1789...0x178C).contains(value) || (0x178E...0x1793).contains(value)
      || (0x1795...0x1798).contains(value) || (0x179B...0x179D).contains(value)
      || value == 0x17A0 || value == 0x17A2 || value == 0x17A7
      || (0x17AB...0x17AC).contains(value) || value == 0x17AF
  }

  private static func isZeroWidth(_ value: UInt32) -> Bool {
    guard let scalar = UnicodeScalar(value) else { return true }
    switch scalar.properties.generalCategory {
    case .control:
      return true
    default:
      break
    }
    return GeneratedUnicodeWidth.contains(value, in: GeneratedUnicodeWidth.zero)
  }

  private static func isWide(_ value: UInt32, policy: TerminalWidthPolicy) -> Bool {
    GeneratedUnicodeWidth.contains(value, in: GeneratedUnicodeWidth.wide)
      || (policy == .cjk
        && GeneratedUnicodeWidth.contains(value, in: GeneratedUnicodeWidth.ambiguous))
  }
}
