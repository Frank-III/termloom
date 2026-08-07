import Testing

@testable import Ratatui

@Suite struct TabViewportTests {
  @Test func smallDomainAlwaysKeepsClampedSelectionRepresented() {
    for count in 0...8 {
      let widths = (0..<count).map { ($0 % 3) + 1 }
      for selected in -2...(count + 2) {
        for capacity in 0...16 {
          for placement in [SelectionPlacement.leading, .center, .trailing] {
            let viewport = TabViewport.fitting(
              widths: widths,
              selectedIndex: selected,
              capacity: capacity,
              spacing: 1,
              leadingOverflowWidth: 2,
              trailingOverflowWidth: 2,
              placement: placement
            )
            #expect(0 <= viewport.range.lowerBound)
            #expect(viewport.range.upperBound <= count)
            if count > 0, capacity > 0 {
              let clamped = min(max(0, selected), count - 1)
              #expect(viewport.range.contains(clamped))
              #expect(viewport.hasTabsBefore == (viewport.range.lowerBound > 0))
              #expect(viewport.hasTabsAfter == (viewport.range.upperBound < count))
            } else {
              #expect(viewport.range.isEmpty)
            }
          }
        }
      }
    }
  }

  @Test func projectionKeepsSelectionVisibleAndExposesOverflow() {
    let viewport = TabViewport.fitting(
      widths: [5, 5, 5, 5],
      selectedIndex: 2,
      capacity: 14,
      spacing: 1,
      leadingOverflowWidth: 2,
      trailingOverflowWidth: 2,
      placement: .trailing
    )

    #expect(viewport.range == 2..<4)
    #expect(viewport.hasTabsBefore)
    #expect(!viewport.hasTabsAfter)

    let leading = TabViewport.fitting(
      widths: [5, 5, 5, 5],
      selectedIndex: 1,
      capacity: 14,
      spacing: 1,
      leadingOverflowWidth: 2,
      trailingOverflowWidth: 2,
      placement: .leading
    )
    #expect(leading.range.contains(1))
    #expect(leading.hasTabsAfter)

    let indicatorReleasedAtBoundary = TabViewport.fitting(
      widths: [1, 1, 1],
      selectedIndex: 0,
      capacity: 5,
      spacing: 1,
      trailingOverflowWidth: 100,
      placement: .leading
    )
    #expect(indicatorReleasedAtBoundary.range == 0..<3)
    #expect(!indicatorReleasedAtBoundary.hasTabsAfter)
  }

  @Test func tabLayoutUsesTerminalWidthsAndSamePassInteractionAreas() {
    let family = "👨‍👩‍👧‍👦"
    let tabs = Tabs(
      ["one", "界", family, "last"],
      selectedIndex: 2,
      divider: " ",
      selectionPlacement: .center,
      interactions: (0..<4).map {
        InteractionDescriptor(control: ControlID("tab-\($0)"), action: ActionID("select:\($0)"))
      }
    )
    let area = Rect(x: 3, y: 2, width: 15, height: 1)
    let layout = tabs.layout(in: area)
    var frame = Frame(buffer: Buffer(area: Rect(x: 0, y: 0, width: 24, height: 5)))

    tabs.render(in: area, into: &frame)

    #expect(layout.viewport.range.contains(2))
    #expect(layout.tabs.contains { $0.index == 2 })
    #expect(layout.tabs.allSatisfy { area.contains(Position(x: $0.area.x, y: $0.area.y)) })
    #expect(frame.interactions.regions.map(\.area) == layout.tabs.map(\.area))
    #expect(
      frame.interactions.regions.map(\.control.rawValue) == layout.tabs.map { "tab-\($0.index)" })
    let selected = layout.tabs.first { $0.index == 2 }
    #expect(selected?.area.width == TerminalWidth.of(family) + 2)
  }

  @Test func largeTabProjectionKeepsTheSelectedRangeBounded() {
    let count = 100_000
    let viewport = TabViewport.fitting(
      widths: Array(repeating: 12, count: count),
      selectedIndex: count / 2,
      capacity: 80,
      spacing: 1,
      leadingOverflowWidth: 1,
      trailingOverflowWidth: 1,
      placement: .center
    )

    #expect(viewport.range.contains(count / 2))
    #expect(viewport.range.count <= 6)
    #expect(viewport.hasTabsBefore)
    #expect(viewport.hasTabsAfter)
  }

  @Test func oversizedSelectedTabRetainsAVisiblePlacementInNarrowAreas() {
    let tabs = Tabs(
      ["before", "selected tab is wide", "after"],
      selectedIndex: 1,
      divider: " ",
      interactions: [
        nil,
        InteractionDescriptor(control: "selected", action: "activate"),
        nil,
      ]
    )
    let area = Rect(x: 0, y: 0, width: 4, height: 1)
    let layout = tabs.layout(in: area)
    var frame = Frame(buffer: Buffer(area: area))

    tabs.render(in: area, into: &frame)

    #expect(layout.viewport.range == 1..<2)
    #expect(layout.viewport.hasTabsBefore)
    #expect(layout.viewport.hasTabsAfter)
    #expect(layout.tabs.first?.index == 1)
    #expect(layout.tabs.first?.area.width == 1)
    #expect(frame.interactions.regions.first?.area == layout.tabs.first?.area)
    #expect(frame.buffer.lines().first?.contains("‹") == true)
    #expect(frame.buffer.lines().first?.contains("›") == true)
  }

  @Test func emptyAndInvalidInputsNormalizeWithoutInteractions() {
    let viewport = TabViewport.fitting(
      widths: [-1, 4],
      selectedIndex: 99,
      capacity: -1,
      spacing: .max,
      leadingOverflowWidth: .max,
      trailingOverflowWidth: .max
    )
    #expect(viewport.range.isEmpty)

    let tabs = Tabs(
      ["one"], selectedIndex: -10, interactions: [InteractionDescriptor(control: "one")])
    var frame = Frame(buffer: Buffer(area: .zero))
    tabs.render(in: .zero, into: &frame)
    #expect(frame.interactions.regions.isEmpty)
  }
}
