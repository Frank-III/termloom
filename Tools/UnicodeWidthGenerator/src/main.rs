use unicode_width::UnicodeWidthChar;

#[derive(Clone, Copy, PartialEq, Eq)]
enum Kind {
    Zero,
    Wide,
    Ambiguous,
    Default,
}

fn kind(character: char) -> Kind {
    match (character.width(), character.width_cjk()) {
        (Some(0), _) => Kind::Zero,
        (Some(2), _) => Kind::Wide,
        (Some(1), Some(2)) => Kind::Ambiguous,
        _ => Kind::Default,
    }
}

fn ranges(target: Kind) -> Vec<(u32, u32)> {
    let mut result = Vec::new();
    let mut start = None;
    let mut previous = 0;
    for value in 0..=0x10_FFFF {
        let matches = char::from_u32(value).is_some_and(|character| kind(character) == target);
        match (start, matches) {
            (None, true) => start = Some(value),
            (Some(range_start), false) => {
                result.push((range_start, previous));
                start = None;
            }
            _ => {}
        }
        previous = value;
    }
    if let Some(range_start) = start {
        result.push((range_start, previous));
    }
    result
}

fn emit(name: &str, ranges: &[(u32, u32)]) {
    println!("  static let {name}: [ClosedRange<UInt32>] = [");
    for &(lower, upper) in ranges {
        if lower == upper {
            println!("    0x{lower:X}...0x{upper:X},");
        } else {
            println!("    0x{lower:X}...0x{upper:X},");
        }
    }
    println!("  ]\n");
}

fn main() {
    println!("// Generated from unicode-width 0.2.2 (Unicode 17.0.0). Do not edit.");
    println!("enum GeneratedUnicodeWidth {{");
    emit("zero", &ranges(Kind::Zero));
    emit("wide", &ranges(Kind::Wide));
    emit("ambiguous", &ranges(Kind::Ambiguous));
    println!("  static func contains(_ value: UInt32, in ranges: [ClosedRange<UInt32>]) -> Bool {{");
    println!("    var lower = 0");
    println!("    var upper = ranges.count");
    println!("    while lower < upper {{");
    println!("      let middle = lower + (upper - lower) / 2");
    println!("      let range = ranges[middle]");
    println!("      if value < range.lowerBound {{ upper = middle }}");
    println!("      else if value > range.upperBound {{ lower = middle + 1 }}");
    println!("      else {{ return true }}");
    println!("    }}");
    println!("    return false");
    println!("  }}");
    println!("}}");
}
