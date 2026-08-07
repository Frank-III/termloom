import Foundation
import RatatuiTestSupport
import Testing

@testable import Ratatui

@Suite struct CalendarTests {
  @Test func rendersACompactMonthlyCalendar() {
    let calendar = Monthly(
      CalendarDay(year: 2015, month: 2, day: 11),
      events: CalendarEventStore(),
      weekdayHeaderStyle: .plain,
      monthHeaderStyle: .plain
    )
    var buffer = Buffer(area: Rect(x: 0, y: 0, width: calendar.width, height: calendar.height))

    calendar.render(in: buffer.area, into: &buffer)

    #expect(calendar.width == 21)
    #expect(calendar.height == 6)
    assertTerminal(buffer) {
      """
      │    February 2015    │
      │ Su Mo Tu We Th Fr Sa│
      │  1  2  3  4  5  6  7│
      │  8  9 10 11 12 13 14│
      │ 15 16 17 18 19 20 21│
      │ 22 23 24 25 26 27 28│
      """
    }
  }

  @Test func appliesEventStylesByTimeZoneIndependentDay() {
    let eventDay = CalendarDay(year: 2024, month: 2, day: 29)
    let eventStyle = Style(foreground: .red, modifiers: [.bold])
    let calendar = Monthly(
      eventDay,
      events: CalendarEventStore([eventDay: eventStyle])
    )
    var buffer = Buffer(area: Rect(x: 0, y: 0, width: calendar.width, height: calendar.height))

    calendar.render(in: buffer.area, into: &buffer)

    let eventCell = buffer.cell(at: Position(x: 13, y: 4))
    #expect(eventCell?.symbol == "2")
    #expect(eventCell?.style.foreground == .red)
    #expect(eventCell?.style.modifiers.contains(.bold) == true)
  }

  @Test func localizesHeadersAndHonorsTheCalendarsFirstWeekday() {
    var gregorian = Calendar.ratatuiGregorian
    gregorian.firstWeekday = 2
    let calendar = Monthly(
      CalendarDay(year: 2015, month: 2, day: 11),
      events: CalendarEventStore(),
      weekdayHeaderStyle: .plain,
      monthHeaderStyle: .plain,
      calendar: gregorian,
      labels: .localized(locale: Locale(identifier: "de_DE"), calendar: gregorian)
    )

    assertWidget(calendar, size: Size(width: calendar.width, height: calendar.height)) {
      """
      │    Februar 2015     │
      │ M  D  M  D  F  S  S │
      │                    1│
      │  2  3  4  5  6  7  8│
      │  9 10 11 12 13 14 15│
      │ 16 17 18 19 20 21 22│
      │ 23 24 25 26 27 28   │
      """
    }
    #expect(calendar.height == 7)
  }

  @Test func calendarIntrinsicSizeComposesThroughPaddedBlocks() {
    let events = CalendarEventStore()
    let february2015 = Monthly(CalendarDay(year: 2015, month: 2, day: 1), events: events)
    #expect(february2015.intrinsicSize == Size(width: 21, height: 4))

    let padded = Block(
      borders: .plain,
      padding: Padding(left: 2, right: 3, top: 1, bottom: 2),
      content: february2015
    )
    #expect(padded.intrinsicSize == Size(width: 28, height: 9))

    let april2023 = Monthly(CalendarDay(year: 2023, month: 4, day: 1), events: events)
    let symmetric = Block(
      borders: .plain,
      padding: .symmetric(1, 1),
      content: april2023
    )
    #expect(symmetric.intrinsicSize == Size(width: 25, height: 10))
  }
}
