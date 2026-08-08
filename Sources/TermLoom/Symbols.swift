/// Canonical terminal glyphs shared by widgets and custom renderers.
///
/// These are values rather than renderer policy: applications can use a
/// different symbol set without changing buffer or backend behavior.
public enum Symbols {
  public enum Bar {
    public static let full: Character = "█"
    public static let sevenEighths: Character = "▇"
    public static let threeQuarters: Character = "▆"
    public static let fiveEighths: Character = "▅"
    public static let half: Character = "▄"
    public static let threeEighths: Character = "▃"
    public static let quarter: Character = "▂"
    public static let oneEighth: Character = "▁"

    public struct Set: Hashable, Sendable {
      public var levels: [Character]

      public init(
        empty: Character,
        oneEighth: Character,
        quarter: Character,
        threeEighths: Character,
        half: Character,
        fiveEighths: Character,
        threeQuarters: Character,
        sevenEighths: Character,
        full: Character
      ) {
        levels = [
          empty, oneEighth, quarter, threeEighths, half, fiveEighths, threeQuarters,
          sevenEighths, full,
        ]
      }

      public subscript(level: Int) -> Character {
        levels[min(8, max(0, level))]
      }

      public static let nineLevels = Self(
        empty: " ", oneEighth: "▁", quarter: "▂", threeEighths: "▃", half: "▄",
        fiveEighths: "▅", threeQuarters: "▆", sevenEighths: "▇", full: "█"
      )
      public static let threeLevels = Self(
        empty: " ", oneEighth: " ", quarter: "▄", threeEighths: "▄", half: "▄",
        fiveEighths: "▄", threeQuarters: "▄", sevenEighths: "█", full: "█"
      )
    }
  }

  public enum Block {
    public static let full: Character = "█"
    public static let sevenEighths: Character = "▉"
    public static let threeQuarters: Character = "▊"
    public static let fiveEighths: Character = "▋"
    public static let half: Character = "▌"
    public static let threeEighths: Character = "▍"
    public static let quarter: Character = "▎"
    public static let oneEighth: Character = "▏"
    public static let upperHalf: Character = "▀"
    public static let lowerHalf: Character = "▄"
    public static let leftHalf: Character = "▌"
    public static let rightHalf: Character = "▐"
  }

  public enum Shade {
    public static let light: Character = "░"
    public static let medium: Character = "▒"
    public static let dark: Character = "▓"
  }

  public enum Braille {
    public static let blank: Character = "⠀"
    public static let full: Character = "⣿"

    public static func character(bits: UInt8) -> Character {
      Character(UnicodeScalar(0x2800 + UInt32(bits))!)
    }
  }

  /// Dense pseudo-pixel lookup tables indexed by a row-major bit pattern.
  ///
  /// A 2x2 quadrant uses bits `0...3`, a 2x3 sextant uses bits `0...5`, and a
  /// 2x4 octant uses bits `0...7`. Keeping these tables canonical lets custom
  /// renderers share the same mapping as `Canvas` without knowing Unicode
  /// code-point allocation details.
  public enum Pixel {
    public static let quadrants = Array(" ▘▝▀▖▌▞▛▗▚▐▜▄▙▟█")
    public static let sextants = Array(
      " 🬀🬁🬂🬃🬄🬅🬆🬇🬈🬉🬊🬋🬌🬍🬎🬏🬐🬑🬒🬓▌🬔🬕🬖🬗🬘🬙🬚🬛🬜🬝🬞🬟🬠🬡🬢🬣🬤🬥🬦🬧▐🬨🬩🬪🬫🬬🬭🬮🬯🬰🬱🬲🬳🬴🬵🬶🬷🬸🬹🬺🬻█"
    )
    public static let octants = Array(
      " 𜺨𜺫🮂𜴀▘𜴁𜴂𜴃𜴄▝𜴅𜴆𜴇𜴈▀𜴉𜴊𜴋𜴌🯦𜴍𜴎𜴏𜴐𜴑𜴒𜴓𜴔𜴕𜴖𜴗𜴘𜴙𜴚𜴛𜴜𜴝𜴞𜴟🯧𜴠𜴡𜴢𜴣𜴤𜴥𜴦𜴧𜴨𜴩𜴪𜴫𜴬𜴭𜴮𜴯𜴰𜴱𜴲𜴳𜴴𜴵🮅𜺣𜴶𜴷𜴸𜴹𜴺𜴻𜴼𜴽𜴾𜴿𜵀𜵁𜵂𜵃𜵄▖𜵅𜵆𜵇𜵈▌𜵉𜵊𜵋𜵌▞𜵍𜵎𜵏𜵐▛𜵑𜵒𜵓𜵔𜵕𜵖𜵗𜵘𜵙𜵚𜵛𜵜𜵝𜵞𜵟𜵠𜵡𜵢𜵣𜵤𜵥𜵦𜵧𜵨𜵩𜵪𜵫𜵬𜵭𜵮𜵯𜵰𜺠𜵱𜵲𜵳𜵴𜵵𜵶𜵷𜵸𜵹𜵺𜵻𜵼𜵽𜵾𜵿𜶀𜶁𜶂𜶃𜶄𜶅𜶆𜶇𜶈𜶉𜶊𜶋𜶌𜶍𜶎𜶏▗𜶐𜶑𜶒𜶓▚𜶔𜶕𜶖𜶗▐𜶘𜶙𜶚𜶛▜𜶜𜶝𜶞𜶟𜶠𜶡𜶢𜶣𜶤𜶥𜶦𜶧𜶨𜶩𜶪𜶫▂𜶬𜶭𜶮𜶯𜶰𜶱𜶲𜶳𜶴𜶵𜶶𜶷𜶸𜶹𜶺𜶻𜶼𜶽𜶾𜶿𜷀𜷁𜷂𜷃𜷄𜷅𜷆𜷇𜷈𜷉𜷊𜷋𜷌𜷍𜷎𜷏𜷐𜷑𜷒𜷓𜷔𜷕𜷖𜷗𜷘𜷙𜷚▄𜷛𜷜𜷝𜷞▙𜷟𜷠𜷡𜷢▟𜷣▆𜷤𜷥█"
    )
  }

  public enum Scrollbar {
    public static let verticalTrack: Character = "│"
    public static let horizontalTrack: Character = "─"
    public static let thumb: Character = "█"
    public static let begin: Character = "▲"
    public static let end: Character = "▼"
  }
}
