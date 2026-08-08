import Foundation

/// A time-zone-independent identity for one calendar day.
public struct CalendarDay: Hashable, Sendable {
  public var year: Int
  public var month: Int
  public var day: Int

  public init(year: Int, month: Int, day: Int) {
    self.year = year
    self.month = month
    self.day = day
  }

  public init(_ date: Date, calendar: Calendar = .termloomGregorian) {
    let components = calendar.dateComponents([.year, .month, .day], from: date)
    self.init(
      year: components.year ?? 1,
      month: components.month ?? 1,
      day: components.day ?? 1
    )
  }
}

public protocol DateStyler {
  func style(for day: CalendarDay) -> Style
}

public struct CalendarLabels: Hashable, Sendable {
  public var monthNames: [String]
  /// Weekday names in Foundation's Sunday-first order.
  public var weekdayNames: [String]

  public init(monthNames: [String], weekdayNames: [String]) {
    precondition(monthNames.count == 12, "CalendarLabels requires 12 month names")
    precondition(weekdayNames.count == 7, "CalendarLabels requires 7 weekday names")
    self.monthNames = monthNames
    self.weekdayNames = weekdayNames
  }

  public static let english = Self(
    monthNames: [
      "January", "February", "March", "April", "May", "June",
      "July", "August", "September", "October", "November", "December",
    ],
    weekdayNames: ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]
  )

  public static func localized(
    locale: Locale,
    calendar: Calendar = .termloomGregorian
  ) -> Self {
    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.calendar = calendar
    formatter.timeZone = calendar.timeZone
    return Self(
      monthNames: formatter.monthSymbols,
      weekdayNames: formatter.veryShortStandaloneWeekdaySymbols
    )
  }
}

public struct CalendarEventStore: DateStyler, Hashable, Sendable {
  public var styles: [CalendarDay: Style]

  public init(_ styles: [CalendarDay: Style] = [:]) {
    self.styles = styles
  }

  public subscript(day: CalendarDay) -> Style? {
    get { styles[day] }
    set { styles[day] = newValue }
  }

  public func style(for day: CalendarDay) -> Style {
    styles[day] ?? .plain
  }
}

public struct Monthly<Events: DateStyler>: IntrinsicSizeWidget {
  public var displayDay: CalendarDay
  public var events: Events
  public var surroundingStyle: Style?
  public var weekdayHeaderStyle: Style?
  public var monthHeaderStyle: Style?
  public var defaultStyle: Style
  public var calendar: Calendar
  public var labels: CalendarLabels

  public init(
    _ displayDay: CalendarDay,
    events: Events,
    surroundingStyle: Style? = nil,
    weekdayHeaderStyle: Style? = nil,
    monthHeaderStyle: Style? = nil,
    defaultStyle: Style = .plain,
    calendar: Calendar = .termloomGregorian,
    labels: CalendarLabels = .english
  ) {
    self.displayDay = displayDay
    self.events = events
    self.surroundingStyle = surroundingStyle
    self.weekdayHeaderStyle = weekdayHeaderStyle
    self.monthHeaderStyle = monthHeaderStyle
    self.defaultStyle = defaultStyle
    self.calendar = calendar
    self.labels = labels
  }

  public init(
    _ date: Date,
    events: Events,
    surroundingStyle: Style? = nil,
    weekdayHeaderStyle: Style? = nil,
    monthHeaderStyle: Style? = nil,
    defaultStyle: Style = .plain,
    calendar: Calendar = .termloomGregorian,
    labels: CalendarLabels = .english
  ) {
    self.init(
      CalendarDay(date, calendar: calendar),
      events: events,
      surroundingStyle: surroundingStyle,
      weekdayHeaderStyle: weekdayHeaderStyle,
      monthHeaderStyle: monthHeaderStyle,
      defaultStyle: defaultStyle,
      calendar: calendar,
      labels: labels
    )
  }

  public var width: Int { 21 }

  public var intrinsicSize: Size { Size(width: width, height: height) }

  public var height: Int {
    guard let firstDate, let days = calendar.range(of: .day, in: .month, for: firstDate)?.count
    else {
      return 0
    }
    let offset = weekdayOffset(for: firstDate)
    let weeks = (offset + days + 6) / 7
    return (weeks + (monthHeaderStyle == nil ? 0 : 1) + (weekdayHeaderStyle == nil ? 0 : 1))
  }

  public func render(in area: Rect, into frame: inout Frame) {
    guard !area.isEmpty, let firstDate else { return }
    var y = area.y
    let bottom = area.y + area.height

    if let monthHeaderStyle, y < bottom {
      Text(
        "\(monthName) \(displayDay.year)",
        style: monthHeaderStyle,
        alignment: .center
      ).render(
        in: Rect(x: area.x, y: y, width: area.width, height: 1),
        into: &frame.buffer,
        environment: frame.environment
      )
      y += 1
    }
    if let weekdayHeaderStyle, y < bottom {
      frame.buffer.setString(
        weekdayHeader,
        at: Position(x: area.x, y: y),
        style: weekdayHeaderStyle,
        maxWidth: area.width
      )
      y += 1
    }

    guard
      let daysInMonth = calendar.range(of: .day, in: .month, for: firstDate)?.count
    else { return }
    let offset = weekdayOffset(for: firstDate)
    let weeks = (offset + daysInMonth + 6) / 7
    for week in 0..<weeks where y + week < bottom {
      for weekday in 0..<7 {
        let relativeDay = week * 7 + weekday - offset
        guard let date = calendar.date(byAdding: .day, value: relativeDay, to: firstDate) else {
          continue
        }
        let day = CalendarDay(date, calendar: calendar)
        let isDisplayedMonth = day.year == displayDay.year && day.month == displayDay.month
        guard isDisplayedMonth || surroundingStyle != nil else { continue }
        let base = isDisplayedMonth ? defaultStyle : defaultStyle.patching(surroundingStyle!)
        let style = base.patching(events.style(for: day))
        let number = day.day < 10 ? " \(day.day)" : "\(day.day)"
        frame.buffer.setString(
          number,
          at: Position(
            x: (area.x + weekday * 3 + 1),
            y: (y + week)
          ),
          style: style,
          maxWidth: (max(0, area.width - weekday * 3 - 1))
        )
      }
    }
  }

  private var firstDate: Date? {
    calendar.date(
      from: DateComponents(year: displayDay.year, month: displayDay.month, day: 1)
    )
  }

  private var monthName: String {
    guard labels.monthNames.indices.contains(displayDay.month - 1) else { return "Month" }
    return labels.monthNames[displayDay.month - 1]
  }

  private var weekdayHeader: String {
    let firstIndex = min(6, max(0, calendar.firstWeekday - 1))
    let ordered = (0..<7).map { labels.weekdayNames[(firstIndex + $0) % 7] }
    return " " + ordered.map(Self.twoCellLabel).joined(separator: " ")
  }

  private func weekdayOffset(for date: Date) -> Int {
    let weekday = calendar.component(.weekday, from: date)
    return (weekday - calendar.firstWeekday + 7) % 7
  }

  private static func twoCellLabel(_ label: String) -> String {
    var result = ""
    var width = 0
    for character in label {
      let characterWidth = TerminalWidth.of(character)
      guard width + characterWidth <= 2 else { break }
      result.append(character)
      width += characterWidth
    }
    return result + String(repeating: " ", count: max(0, 2 - width))
  }
}

extension Calendar {
  public static var termloomGregorian: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_US_POSIX")
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    calendar.firstWeekday = 1
    return calendar
  }
}
