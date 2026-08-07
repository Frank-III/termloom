import Foundation

public struct CanvasPoint: Hashable, Sendable {
  public var x: Double
  public var y: Double
  public var style: Style

  public init(x: Double, y: Double, style: Style = .plain) {
    self.x = x
    self.y = y
    self.style = style
  }
}

public struct CanvasLine: Hashable, Sendable {
  public var start: CanvasPoint
  public var end: CanvasPoint

  public init(from start: CanvasPoint, to end: CanvasPoint) {
    self.start = start
    self.end = end
  }
}

public struct CanvasFilledLine: Hashable, Sendable {
  public var start: CanvasPoint
  public var end: CanvasPoint
  public var fillToY: Double

  public init(from start: CanvasPoint, to end: CanvasPoint, fillToY: Double) {
    self.start = start
    self.end = end
    self.fillToY = fillToY
  }
}

public struct CanvasRectangle: Hashable, Sendable {
  public var x: Double
  public var y: Double
  public var width: Double
  public var height: Double
  public var style: Style

  public init(x: Double, y: Double, width: Double, height: Double, style: Style = .plain) {
    self.x = x
    self.y = y
    self.width = width
    self.height = height
    self.style = style
  }
}

public struct CanvasCircle: Hashable, Sendable {
  public var center: (x: Double, y: Double)
  public var radius: Double
  public var style: Style

  public init(center: (Double, Double), radius: Double, style: Style = .plain) {
    self.center = center
    self.radius = radius
    self.style = style
  }

  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.center == rhs.center && lhs.radius == rhs.radius && lhs.style == rhs.style
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(center.x)
    hasher.combine(center.y)
    hasher.combine(radius)
    hasher.combine(style)
  }
}

public enum CanvasMapResolution: Hashable, Sendable {
  /// Approximately one thousand geographic points.
  case low
  /// Approximately five thousand geographic points.
  case high

  public var pointCount: Int {
    data.count
  }

  fileprivate var data: [(Double, Double)] {
    switch self {
    case .low: CanvasWorldData.low
    case .high: CanvasWorldData.high
    }
  }
}

/// A world map in EPSG:4326 longitude/latitude coordinates.
public struct CanvasMap: Hashable, Sendable {
  public var resolution: CanvasMapResolution
  public var style: Style

  public init(resolution: CanvasMapResolution = .low, style: Style = .plain) {
    self.resolution = resolution
    self.style = style
  }
}

/// Rich text pinned to a coordinate and rendered above every canvas layer.
public struct CanvasLabel: Hashable, Sendable {
  public var x: Double
  public var y: Double
  public var content: Line

  public init(x: Double, y: Double, content: Line) {
    self.x = x
    self.y = y
    self.content = content
  }

  public init(_ content: String, x: Double, y: Double, style: Style = .plain) {
    self.init(x: x, y: y, content: Line { Span(content, style: style) })
  }
}

public enum CanvasMarker: Hashable, Sendable {
  case dot
  case block
  case bar
  case braille
  case halfBlock
  case quadrant
  case sextant
  case octant
  case custom(Character)
}

/// One independently rasterized canvas plane.
///
/// Layers render in declaration order. Empty cells remain transparent, while
/// painted cells replace the symbol and patch their style over the layer below.
/// A `nil` marker inherits the marker of the containing `Canvas`.
public struct CanvasLayer: Hashable, Sendable {
  public var points: [CanvasPoint]
  public var lines: [CanvasLine]
  public var filledLines: [CanvasFilledLine]
  public var rectangles: [CanvasRectangle]
  public var circles: [CanvasCircle]
  public var maps: [CanvasMap]
  public var marker: CanvasMarker?

  public init(
    points: [CanvasPoint] = [],
    lines: [CanvasLine] = [],
    filledLines: [CanvasFilledLine] = [],
    rectangles: [CanvasRectangle] = [],
    circles: [CanvasCircle] = [],
    maps: [CanvasMap] = [],
    marker: CanvasMarker? = nil
  ) {
    self.points = points
    self.lines = lines
    self.filledLines = filledLines
    self.rectangles = rectangles
    self.circles = circles
    self.maps = maps
    self.marker = marker
  }
}

@resultBuilder
public enum CanvasLayerBuilder {
  public static func buildExpression(_ expression: CanvasLayer) -> [CanvasLayer] {
    [expression]
  }

  public static func buildBlock(_ components: [CanvasLayer]...) -> [CanvasLayer] {
    components.flatMap { $0 }
  }

  public static func buildOptional(_ component: [CanvasLayer]?) -> [CanvasLayer] {
    component ?? []
  }

  public static func buildEither(first component: [CanvasLayer]) -> [CanvasLayer] {
    component
  }

  public static func buildEither(second component: [CanvasLayer]) -> [CanvasLayer] {
    component
  }

  public static func buildArray(_ components: [[CanvasLayer]]) -> [CanvasLayer] {
    components.flatMap { $0 }
  }
}

public struct Canvas: Widget, Hashable, Sendable {
  public var xBounds: ClosedRange<Double>
  public var yBounds: ClosedRange<Double>
  public var points: [CanvasPoint]
  public var lines: [CanvasLine]
  public var filledLines: [CanvasFilledLine]
  public var rectangles: [CanvasRectangle]
  public var circles: [CanvasCircle]
  public var maps: [CanvasMap]
  public var labels: [CanvasLabel]
  public var backgroundColor: Color?
  public var marker: CanvasMarker
  public var layers: [CanvasLayer]

  public init(
    x: ClosedRange<Double>,
    y: ClosedRange<Double>,
    points: [CanvasPoint] = [],
    lines: [CanvasLine] = [],
    filledLines: [CanvasFilledLine] = [],
    rectangles: [CanvasRectangle] = [],
    circles: [CanvasCircle] = [],
    maps: [CanvasMap] = [],
    labels: [CanvasLabel] = [],
    backgroundColor: Color? = nil,
    marker: CanvasMarker = .braille,
    layers: [CanvasLayer] = []
  ) {
    xBounds = x
    yBounds = y
    self.points = points
    self.lines = lines
    self.filledLines = filledLines
    self.rectangles = rectangles
    self.circles = circles
    self.maps = maps
    self.labels = labels
    self.backgroundColor = backgroundColor
    self.marker = marker
    self.layers = layers
  }

  public init(
    x: ClosedRange<Double>,
    y: ClosedRange<Double>,
    points: [CanvasPoint] = [],
    lines: [CanvasLine] = [],
    filledLines: [CanvasFilledLine] = [],
    rectangles: [CanvasRectangle] = [],
    circles: [CanvasCircle] = [],
    maps: [CanvasMap] = [],
    labels: [CanvasLabel] = [],
    backgroundColor: Color? = nil,
    marker: CanvasMarker = .braille,
    @CanvasLayerBuilder layers: () -> [CanvasLayer]
  ) {
    self.init(
      x: x,
      y: y,
      points: points,
      lines: lines,
      filledLines: filledLines,
      rectangles: rectangles,
      circles: circles,
      maps: maps,
      labels: labels,
      backgroundColor: backgroundColor,
      marker: marker,
      layers: layers()
    )
  }

  public func render(in area: Rect, into frame: inout Frame) {
    guard !area.isEmpty else { return }
    if let backgroundColor {
      let left = max(Int(area.x), Int(frame.buffer.area.x))
      let top = max(Int(area.y), Int(frame.buffer.area.y))
      let right = min(
        Int(area.x) + Int(area.width),
        Int(frame.buffer.area.x) + Int(frame.buffer.area.width)
      )
      let bottom = min(
        Int(area.y) + Int(area.height),
        Int(frame.buffer.area.y) + Int(frame.buffer.area.height)
      )
      if right > left, bottom > top {
        for y in top..<bottom {
          for x in left..<right {
            let position = Position(x: UInt16(clamping: x), y: UInt16(clamping: y))
            var cell = frame.buffer[position]
            cell.style.background = backgroundColor
            frame.buffer[position] = cell
          }
        }
      }
    }
    let base = CanvasLayer(
      points: points,
      lines: lines,
      filledLines: filledLines,
      rectangles: rectangles,
      circles: circles,
      maps: maps
    )
    render(base, marker: marker, in: area, into: &frame.buffer)
    for layer in layers {
      render(layer, marker: layer.marker ?? marker, in: area, into: &frame.buffer)
    }
    renderLabels(in: area, into: &frame.buffer, environment: frame.environment)
  }

  private func renderLabels(
    in area: Rect,
    into buffer: inout Buffer,
    environment: RenderEnvironment
  ) {
    let xExtent = xBounds.upperBound - xBounds.lowerBound
    let yExtent = yBounds.upperBound - yBounds.lowerBound
    guard xExtent > 0, yExtent > 0 else { return }

    for label in labels where xBounds.contains(label.x) && yBounds.contains(label.y) {
      let x = Int(
        (label.x - xBounds.lowerBound) / xExtent * Double(max(0, Int(area.width) - 1))
      )
      let y = Int(
        (yBounds.upperBound - label.y) / yExtent * Double(max(0, Int(area.height) - 1))
      )
      let position = Position(
        x: UInt16(clamping: Int(area.x) + x),
        y: UInt16(clamping: Int(area.y) + y)
      )
      let labelArea = Rect(
        x: position.x,
        y: position.y,
        width: UInt16(clamping: Int(area.x) + Int(area.width) - Int(position.x)),
        height: 1
      )
      Paragraph(wrap: .none) { label.content }
        .render(in: labelArea, into: &buffer, environment: environment)
    }
  }

  private func render(
    _ layer: CanvasLayer,
    marker: CanvasMarker,
    in area: Rect,
    into buffer: inout Buffer
  ) {
    guard
      !layer.points.isEmpty || !layer.lines.isEmpty || !layer.filledLines.isEmpty
        || !layer.rectangles.isEmpty || !layer.circles.isEmpty || !layer.maps.isEmpty
    else { return }
    let resolution: (x: Int, y: Int) =
      switch marker {
      case .braille: (2, 4)
      case .halfBlock: (1, 2)
      case .quadrant: (2, 2)
      case .sextant: (2, 3)
      case .octant: (2, 4)
      case .dot, .block, .bar, .custom: (1, 1)
      }
    let dotWidth = Int(area.width) * resolution.x
    let dotHeight = Int(area.height) * resolution.y
    guard dotWidth > 0, dotHeight > 0 else { return }
    var dots = Array(repeating: UInt8(0), count: area.area)
    var styles = Array(repeating: Style.plain, count: area.area)
    var halfBlockStyles: [Style?] =
      marker == .halfBlock ? Array(repeating: nil, count: area.area * 2) : []

    func raster(x pointX: Double, y pointY: Double) -> (x: Int, y: Int)? {
      let xExtent = xBounds.upperBound - xBounds.lowerBound
      let yExtent = yBounds.upperBound - yBounds.lowerBound
      guard xExtent > 0, yExtent > 0, xBounds.contains(pointX), yBounds.contains(pointY) else {
        return nil
      }
      let x = Int(
        ((pointX - xBounds.lowerBound) / xExtent * Double(dotWidth - 1)).rounded()
      )
      let y =
        dotHeight - 1
        - Int(((pointY - yBounds.lowerBound) / yExtent * Double(dotHeight - 1)).rounded())
      return (x, y)
    }

    func raster(_ point: CanvasPoint) -> (x: Int, y: Int)? {
      raster(x: point.x, y: point.y)
    }

    func clipped(
      from first: CanvasPoint,
      to second: CanvasPoint
    ) -> (start: CanvasPoint, end: CanvasPoint)? {
      let left: UInt8 = 1 << 0
      let right: UInt8 = 1 << 1
      let bottom: UInt8 = 1 << 2
      let top: UInt8 = 1 << 3

      func outcode(x: Double, y: Double) -> UInt8 {
        var result: UInt8 = 0
        if x < xBounds.lowerBound { result |= left }
        if x > xBounds.upperBound { result |= right }
        if y < yBounds.lowerBound { result |= bottom }
        if y > yBounds.upperBound { result |= top }
        return result
      }

      var start = first
      var end = second
      while true {
        let startCode = outcode(x: start.x, y: start.y)
        let endCode = outcode(x: end.x, y: end.y)
        if startCode == 0, endCode == 0 { return (start, end) }
        if startCode & endCode != 0 { return nil }

        let code = startCode != 0 ? startCode : endCode
        let x: Double
        let y: Double
        if code & top != 0 {
          y = yBounds.upperBound
          x = start.x + (end.x - start.x) * (y - start.y) / (end.y - start.y)
        } else if code & bottom != 0 {
          y = yBounds.lowerBound
          x = start.x + (end.x - start.x) * (y - start.y) / (end.y - start.y)
        } else if code & right != 0 {
          x = xBounds.upperBound
          y = start.y + (end.y - start.y) * (x - start.x) / (end.x - start.x)
        } else {
          x = xBounds.lowerBound
          y = start.y + (end.y - start.y) * (x - start.x) / (end.x - start.x)
        }
        if code == startCode {
          start.x = x
          start.y = y
        } else {
          end.x = x
          end.y = y
        }
      }
    }

    func mark(_ x: Int, _ y: Int, style: Style) {
      guard x >= 0, y >= 0, x < dotWidth, y < dotHeight else { return }
      let cellX = x / resolution.x
      let cellY = y / resolution.y
      let index = cellY * Int(area.width) + cellX
      let bit: UInt8 =
        switch marker {
        case .braille:
          [[0, 1, 2, 6], [3, 4, 5, 7]][x % 2][y % 4]
        case .halfBlock:
          UInt8(y % 2)
        case .quadrant:
          UInt8((y % 2) * 2 + x % 2)
        case .sextant:
          UInt8((y % 3) * 2 + x % 2)
        case .octant:
          UInt8((y % 4) * 2 + x % 2)
        case .dot, .block, .bar, .custom:
          0
        }
      dots[index] |= 1 << bit
      styles[index] = styles[index].patching(style)
      if marker == .halfBlock {
        let pixelIndex = index * 2 + y % 2
        halfBlockStyles[pixelIndex] = (halfBlockStyles[pixelIndex] ?? .plain).patching(style)
      }
    }

    func forEachLinePoint(
      from start: (x: Int, y: Int),
      to end: (x: Int, y: Int),
      _ body: (Int, Int) -> Void
    ) {
      let dx = abs(end.x - start.x)
      let dy = abs(end.y - start.y)
      if dx == 0 {
        for y in min(start.y, end.y)...max(start.y, end.y) { body(start.x, y) }
        return
      }
      if dy == 0 {
        for x in min(start.x, end.x)...max(start.x, end.x) { body(x, start.y) }
        return
      }

      func low(from first: (x: Int, y: Int), to second: (x: Int, y: Int)) {
        let deltaX = second.x - first.x
        let deltaY = abs(second.y - first.y)
        var decision = 2 * deltaY - deltaX
        var y = first.y
        for x in first.x...second.x {
          body(x, y)
          if decision > 0 {
            y += first.y > second.y ? -1 : 1
            decision -= 2 * deltaX
          }
          decision += 2 * deltaY
        }
      }

      func high(from first: (x: Int, y: Int), to second: (x: Int, y: Int)) {
        let deltaX = abs(second.x - first.x)
        let deltaY = second.y - first.y
        var decision = 2 * deltaX - deltaY
        var x = first.x
        for y in first.y...second.y {
          body(x, y)
          if decision > 0 {
            x += first.x > second.x ? -1 : 1
            decision -= 2 * deltaY
          }
          decision += 2 * deltaX
        }
      }

      if dy < dx {
        start.x > end.x ? low(from: end, to: start) : low(from: start, to: end)
      } else {
        start.y > end.y ? high(from: end, to: start) : high(from: start, to: end)
      }
    }

    let rectangleLines = layer.rectangles.flatMap { rectangle in
      let topLeft = CanvasPoint(x: rectangle.x, y: rectangle.y, style: rectangle.style)
      let topRight = CanvasPoint(
        x: rectangle.x + rectangle.width,
        y: rectangle.y,
        style: rectangle.style
      )
      let bottomLeft = CanvasPoint(
        x: rectangle.x,
        y: rectangle.y + rectangle.height,
        style: rectangle.style
      )
      let bottomRight = CanvasPoint(
        x: rectangle.x + rectangle.width,
        y: rectangle.y + rectangle.height,
        style: rectangle.style
      )
      return [
        CanvasLine(from: topLeft, to: topRight),
        CanvasLine(from: topRight, to: bottomRight),
        CanvasLine(from: bottomRight, to: bottomLeft),
        CanvasLine(from: bottomLeft, to: topLeft),
      ]
    }
    for line in layer.lines + rectangleLines {
      guard let line = clipped(from: line.start, to: line.end),
        let start = raster(line.start), let end = raster(line.end)
      else { continue }
      forEachLinePoint(from: start, to: end) { x, y in
        mark(x, y, style: line.start.style)
      }
    }
    for filledLine in layer.filledLines {
      guard let line = clipped(from: filledLine.start, to: filledLine.end),
        let start = raster(line.start), let end = raster(line.end),
        let fill = raster(
          x: line.start.x,
          y: min(max(filledLine.fillToY, yBounds.lowerBound), yBounds.upperBound)
        )
      else { continue }
      forEachLinePoint(from: start, to: end) { x, y in
        for fillY in min(y, fill.y)...max(y, fill.y) {
          mark(x, fillY, style: line.start.style)
        }
      }
    }
    for point in layer.points {
      guard let coordinate = raster(point) else { continue }
      mark(coordinate.x, coordinate.y, style: point.style)
    }
    for circle in layer.circles where circle.radius >= 0 {
      for degrees in 0..<360 {
        let angle = Double(degrees) * .pi / 180
        let point = CanvasPoint(
          x: circle.center.x + cos(angle) * circle.radius,
          y: circle.center.y + sin(angle) * circle.radius,
          style: circle.style
        )
        guard let coordinate = raster(point) else { continue }
        mark(coordinate.x, coordinate.y, style: point.style)
      }
    }
    for map in layer.maps {
      for (x, y) in map.resolution.data {
        guard let coordinate = raster(x: x, y: y) else { continue }
        mark(coordinate.x, coordinate.y, style: map.style)
      }
    }

    for index in dots.indices where dots[index] != 0 {
      let position = Position(
        x: UInt16(clamping: Int(area.x) + index % Int(area.width)),
        y: UInt16(clamping: Int(area.y) + index / Int(area.width))
      )
      let underlyingStyle = buffer.cell(at: position)?.style ?? .plain
      var style = underlyingStyle.patching(styles[index])
      let renderedSymbol: Character
      if marker == .halfBlock {
        let upper = halfBlockStyles[index * 2]
        let lower = halfBlockStyles[index * 2 + 1]
        switch (upper, lower) {
        case (.some(let upper), .none):
          renderedSymbol = Symbols.Block.upperHalf
          style = underlyingStyle.patching(upper)
        case (.none, .some(let lower)):
          renderedSymbol = Symbols.Block.lowerHalf
          style = underlyingStyle.patching(lower)
        case (.some(let upper), .some(let lower)):
          let upperStyle = underlyingStyle.patching(upper)
          let lowerStyle = underlyingStyle.patching(lower)
          if upperStyle.foreground == lowerStyle.foreground {
            renderedSymbol = Symbols.Block.full
            style = upperStyle
          } else {
            renderedSymbol = Symbols.Block.upperHalf
            style = upperStyle
            style.background = lowerStyle.foreground ?? .reset
          }
        case (.none, .none):
          continue
        }
      } else {
        renderedSymbol = symbol(for: dots[index], marker: marker)
      }
      if marker == .block, style.background == nil, let foreground = styles[index].foreground {
        style.background = foreground
      }
      buffer.setString(
        String(renderedSymbol),
        at: position,
        style: style
      )
    }
  }

  private func symbol(for bits: UInt8, marker: CanvasMarker) -> Character {
    switch marker {
    case .dot: "•"
    case .block: Symbols.Block.full
    case .bar: Symbols.Block.lowerHalf
    case .braille: Symbols.Braille.character(bits: bits)
    case .halfBlock:
      switch bits & 0b11 {
      case 0b01: Symbols.Block.upperHalf
      case 0b10: Symbols.Block.lowerHalf
      default: Symbols.Block.full
      }
    case .quadrant:
      Symbols.Pixel.quadrants[Int(bits & 0x0F)]
    case .sextant:
      Symbols.Pixel.sextants[Int(bits & 0x3F)]
    case .octant:
      Symbols.Pixel.octants[Int(bits)]
    case .custom(let character): character
    }
  }
}

public enum GraphType: Hashable, Sendable {
  case scatter
  case line
  case bar
  case area
}

public struct ChartAxis: Hashable, Sendable {
  public var title: Line?
  public var bounds: ClosedRange<Double>?
  public var labels: [Line]
  public var style: Style
  public var labelsAlignment: Alignment

  public init(
    title: String? = nil,
    bounds: ClosedRange<Double>? = nil,
    labels: [String] = [],
    style: Style = .plain,
    labelsAlignment: Alignment = .leading
  ) {
    self.title = title.map(Line.init)
    self.bounds = bounds
    self.labels = labels.map(Line.init)
    self.style = style
    self.labelsAlignment = labelsAlignment
  }

  public init(
    title: Line?,
    bounds: ClosedRange<Double>? = nil,
    labels: [Line],
    style: Style = .plain,
    labelsAlignment: Alignment = .leading
  ) {
    self.title = title
    self.bounds = bounds
    self.labels = labels
    self.style = style
    self.labelsAlignment = labelsAlignment
  }
}

public enum ChartLegendPosition: Hashable, Sendable {
  case top
  case topLeading
  case topTrailing
  case leading
  case trailing
  case bottom
  case bottomLeading
  case bottomTrailing
}

public struct ChartLegendConstraints: Hashable, Sendable {
  public var width: Constraint
  public var height: Constraint

  public init(
    width: Constraint = .ratio(numerator: 1, denominator: 4),
    height: Constraint = .ratio(numerator: 1, denominator: 4)
  ) {
    self.width = width
    self.height = height
  }

  public static let always = Self(width: .min(0), height: .min(0))
}

public struct Dataset: Hashable, Sendable {
  public var name: Line?
  public var points: [(x: Double, y: Double)]
  public var style: Style
  public var marker: CanvasMarker
  public var graphType: GraphType
  public var fillToY: Double

  public init(
    _ name: String? = nil,
    points: [(Double, Double)],
    style: Style = .plain,
    marker: CanvasMarker = .dot,
    graphType: GraphType = .scatter,
    fillToY: Double = 0
  ) {
    self.name = name.map(Line.init)
    self.points = points
    self.style = style
    self.marker = marker
    self.graphType = graphType
    self.fillToY = fillToY
  }

  public init(
    name: Line?,
    points: [(Double, Double)],
    style: Style = .plain,
    marker: CanvasMarker = .dot,
    graphType: GraphType = .scatter,
    fillToY: Double = 0
  ) {
    self.name = name
    self.points = points.map { (x: $0.0, y: $0.1) }
    self.style = style
    self.marker = marker
    self.graphType = graphType
    self.fillToY = fillToY
  }

  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.name == rhs.name && lhs.style == rhs.style && lhs.marker == rhs.marker
      && lhs.graphType == rhs.graphType && lhs.fillToY == rhs.fillToY
      && lhs.points.elementsEqual(rhs.points) { $0.x == $1.x && $0.y == $1.y }
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(name)
    hasher.combine(style)
    hasher.combine(marker)
    hasher.combine(graphType)
    hasher.combine(fillToY)
    for point in points {
      hasher.combine(point.x)
      hasher.combine(point.y)
    }
  }
}

public struct Chart: Widget, Hashable, Sendable {
  public var datasets: [Dataset]
  public var style: Style
  public var xBounds: ClosedRange<Double>?
  public var yBounds: ClosedRange<Double>?
  public var xAxis: ChartAxis?
  public var yAxis: ChartAxis?
  public var legendPosition: ChartLegendPosition?
  public var legendConstraints: ChartLegendConstraints

  public init(
    _ datasets: [Dataset],
    style: Style = .plain,
    x: ClosedRange<Double>? = nil,
    y: ClosedRange<Double>? = nil,
    xAxis: ChartAxis? = nil,
    yAxis: ChartAxis? = nil,
    legendPosition: ChartLegendPosition? = .topTrailing,
    legendConstraints: ChartLegendConstraints = ChartLegendConstraints()
  ) {
    self.datasets = datasets
    self.style = style
    xBounds = x
    yBounds = y
    self.xAxis = xAxis
    self.yAxis = yAxis
    self.legendPosition = legendPosition
    self.legendConstraints = legendConstraints
  }

  public func render(in area: Rect, into frame: inout Frame) {
    if style != .plain {
      frame.buffer.setStyle(style, in: area)
    }
    guard let layout = chartLayout(in: area) else { return }
    let allPoints = datasets.flatMap(\.points)
    let xRange = xAxis?.bounds ?? xBounds ?? range(allPoints.map(\.x))
    let yRange = yAxis?.bounds ?? yBounds ?? range(allPoints.map(\.y))

    renderAxes(layout, in: area, into: &frame.buffer, environment: frame.environment)
    for dataset in datasets {
      let points = dataset.points.map {
        CanvasPoint(x: $0.x, y: $0.y, style: dataset.style)
      }
      let lines: [CanvasLine]
      let filledLines: [CanvasFilledLine]
      switch dataset.graphType {
      case .scatter:
        lines = []
        filledLines = []
      case .line:
        lines = zip(points, points.dropFirst()).map(CanvasLine.init(from:to:))
        filledLines = []
      case .bar:
        lines = points.map {
          CanvasLine(
            from: CanvasPoint(x: $0.x, y: yRange.lowerBound, style: dataset.style),
            to: $0
          )
        }
        filledLines = []
      case .area:
        lines = []
        filledLines = zip(points, points.dropFirst()).map {
          CanvasFilledLine(from: $0, to: $1, fillToY: dataset.fillToY)
        }
      }
      Canvas(
        x: xRange,
        y: yRange,
        points: dataset.graphType == .scatter ? points : [],
        lines: lines,
        filledLines: filledLines,
        marker: dataset.marker
      ).render(in: layout.graphArea, into: &frame.buffer, environment: frame.environment)
    }
    renderTitles(layout, into: &frame.buffer, environment: frame.environment)
    renderLegend(layout.legendArea, into: &frame.buffer, environment: frame.environment)
  }

  public func foregroundStyle(_ color: Color) -> Self {
    var copy = self
    copy.style.foreground = color
    return copy
  }

  public func backgroundStyle(_ color: Color) -> Self {
    var copy = self
    copy.style.background = color
    return copy
  }

  public func bold(_ active: Bool = true) -> Self {
    var copy = self
    copy.style = active ? copy.style.adding(.bold) : copy.style.removing(.bold)
    return copy
  }

  private struct ChartLayout {
    var graphArea: Rect
    var xLabelRow: Int?
    var yLabelColumn: Int?
    var xAxisRow: Int?
    var yAxisColumn: Int?
    var xTitlePosition: Position?
    var yTitlePosition: Position?
    var legendArea: Rect?
  }

  private func chartLayout(in area: Rect) -> ChartLayout? {
    guard !area.isEmpty else { return nil }
    let top = Int(area.y)
    let right = Int(area.x) + Int(area.width)
    var x = Int(area.x)
    var y = top + Int(area.height) - 1
    let hasXLabels = xAxis?.labels.isEmpty == false
    let hasYLabels = yAxis?.labels.isEmpty == false

    let xLabelRow: Int? =
      if hasXLabels, y > top {
        consume(&y)
      } else {
        nil
      }
    let yLabelColumn = hasYLabels ? x : nil
    x += maximumLeftLabelWidth(in: area, hasYAxis: hasYLabels)

    let xAxisRow: Int? =
      if hasXLabels, y > top {
        consume(&y)
      } else {
        nil
      }
    let yAxisColumn: Int? =
      if hasYLabels, x + 1 < right {
        consume(&x, increasing: true)
      } else {
        nil
      }

    let graphArea = Rect(
      x: UInt16(clamping: x),
      y: area.y,
      width: UInt16(clamping: right - x),
      height: UInt16(clamping: y - top + 1)
    )
    guard !graphArea.isEmpty else { return nil }

    let xTitlePosition = titlePosition(
      xAxis?.title,
      fitting: graphArea,
      at: Position(x: UInt16(clamping: right), y: UInt16(clamping: y)),
      trailing: true
    )
    let yTitlePosition = titlePosition(
      yAxis?.title,
      fitting: graphArea,
      at: Position(x: graphArea.x, y: area.y),
      trailing: false
    )
    let legendArea = legendArea(
      in: graphArea,
      xTitleWidth: xTitlePosition == nil ? 0 : (xAxis?.title?.width ?? 0),
      yTitleWidth: yTitlePosition == nil ? 0 : (yAxis?.title?.width ?? 0)
    )
    return ChartLayout(
      graphArea: graphArea,
      xLabelRow: xLabelRow,
      yLabelColumn: yLabelColumn,
      xAxisRow: xAxisRow,
      yAxisColumn: yAxisColumn,
      xTitlePosition: xTitlePosition,
      yTitlePosition: yTitlePosition,
      legendArea: legendArea
    )
  }

  private func consume(_ value: inout Int, increasing: Bool = false) -> Int {
    let result = value
    value += increasing ? 1 : -1
    return result
  }

  private func maximumLeftLabelWidth(in area: Rect, hasYAxis: Bool) -> Int {
    var width = yAxis?.labels.map(\.width).max() ?? 0
    if let first = xAxis?.labels.first {
      let leftWidth =
        switch xAxis?.labelsAlignment ?? .leading {
        case .leading: max(0, first.width - (hasYAxis ? 1 : 0))
        case .center: first.width / 2
        case .trailing: 0
        }
      width = max(width, leftWidth)
    }
    return min(width, Int(area.width) / 3)
  }

  private func titlePosition(
    _ title: Line?,
    fitting graphArea: Rect,
    at anchor: Position,
    trailing: Bool
  ) -> Position? {
    guard let title, title.width < Int(graphArea.width), graphArea.height > 2 else { return nil }
    return Position(
      x: trailing ? UInt16(clamping: Int(anchor.x) - title.width) : anchor.x,
      y: anchor.y
    )
  }

  private func renderAxes(
    _ layout: ChartLayout,
    in area: Rect,
    into buffer: inout Buffer,
    environment: RenderEnvironment
  ) {
    let graphArea = layout.graphArea
    let graphRight = Int(graphArea.x) + Int(graphArea.width)
    let graphBottom = Int(graphArea.y) + Int(graphArea.height)
    if let yAxis, let axisX = layout.yAxisColumn {
      for y in Int(graphArea.y)..<graphBottom {
        buffer.setString(
          "│",
          at: Position(x: UInt16(clamping: axisX), y: UInt16(clamping: y)),
          style: yAxis.style
        )
      }
      if let labelX = layout.yLabelColumn, yAxis.labels.count >= 2 {
        for (index, label) in yAxis.labels.enumerated() {
          let y =
            graphBottom - 1
            - (max(0, Int(graphArea.height) - 1) * index / (yAxis.labels.count - 1))
          render(
            label.patchStyle(yAxis.style).alignment(yAxis.labelsAlignment),
            in: Rect(
              x: UInt16(clamping: labelX),
              y: UInt16(clamping: y),
              width: UInt16(clamping: max(0, Int(graphArea.x) - Int(area.x) - 1)),
              height: 1
            ),
            into: &buffer,
            environment: environment
          )
        }
      }
    }
    if let xAxis, let axisY = layout.xAxisRow {
      for x in Int(graphArea.x)..<graphRight {
        buffer.setString(
          "─",
          at: Position(x: UInt16(clamping: x), y: UInt16(clamping: axisY)),
          style: xAxis.style
        )
      }
      if let axisX = layout.yAxisColumn {
        buffer.setString(
          "└",
          at: Position(x: UInt16(clamping: axisX), y: UInt16(clamping: axisY)),
          style: xAxis.style.patching(yAxis?.style ?? .plain)
        )
      }
      if let labelY = layout.xLabelRow, xAxis.labels.count >= 2 {
        renderXLabels(
          xAxis,
          row: labelY,
          chartArea: area,
          graphArea: graphArea,
          into: &buffer,
          environment: environment
        )
      }
    }
  }

  private func renderXLabels(
    _ axis: ChartAxis,
    row: Int,
    chartArea: Rect,
    graphArea: Rect,
    into buffer: inout Buffer,
    environment: RenderEnvironment
  ) {
    let count = axis.labels.count
    let tickWidth = Int(graphArea.width) / count
    let first = axis.labels[0].patchStyle(axis.style)
    let firstBounds: (Int, Int) =
      switch axis.labelsAlignment {
      case .leading: (Int(chartArea.x), Int(graphArea.x))
      case .center: (Int(chartArea.x), Int(graphArea.x) + min(tickWidth, first.width))
      case .trailing: (max(Int(chartArea.x), Int(graphArea.x) - 1), Int(graphArea.x) + tickWidth)
      }
    render(
      first.alignment(opposite(axis.labelsAlignment)),
      in: Rect(
        x: UInt16(clamping: firstBounds.0),
        y: UInt16(clamping: row),
        width: UInt16(clamping: firstBounds.1 - firstBounds.0),
        height: 1
      ),
      into: &buffer,
      environment: environment
    )
    for (index, label) in axis.labels.dropFirst().dropLast().enumerated() {
      render(
        label.patchStyle(axis.style).alignment(.center),
        in: Rect(
          x: UInt16(clamping: Int(graphArea.x) + (index + 1) * tickWidth + 1),
          y: UInt16(clamping: row),
          width: UInt16(clamping: max(0, tickWidth - 1)),
          height: 1
        ),
        into: &buffer,
        environment: environment
      )
    }
    render(
      axis.labels[count - 1].patchStyle(axis.style).alignment(.trailing),
      in: Rect(
        x: UInt16(clamping: graphRight(graphArea) - tickWidth),
        y: UInt16(clamping: row),
        width: UInt16(clamping: tickWidth),
        height: 1
      ),
      into: &buffer,
      environment: environment
    )
  }

  private func opposite(_ alignment: Alignment) -> Alignment {
    switch alignment {
    case .leading: .trailing
    case .center: .center
    case .trailing: .leading
    }
  }

  private func graphRight(_ area: Rect) -> Int { Int(area.x) + Int(area.width) }

  private func renderTitles(
    _ layout: ChartLayout,
    into buffer: inout Buffer,
    environment: RenderEnvironment
  ) {
    if let position = layout.xTitlePosition, let title = xAxis?.title {
      render(
        title,
        in: Rect(
          x: position.x,
          y: position.y,
          width: UInt16(clamping: min(title.width, graphRight(layout.graphArea) - Int(position.x))),
          height: 1
        ),
        into: &buffer,
        environment: environment
      )
    }
    if let position = layout.yTitlePosition, let title = yAxis?.title {
      render(
        title,
        in: Rect(
          x: position.x,
          y: position.y,
          width: UInt16(clamping: min(title.width, graphRight(layout.graphArea) - Int(position.x))),
          height: 1
        ),
        into: &buffer,
        environment: environment
      )
    }
  }

  private func render(
    _ line: Line,
    in area: Rect,
    into buffer: inout Buffer,
    environment: RenderEnvironment
  ) {
    Paragraph(wrap: .none) { line }.render(in: area, into: &buffer, environment: environment)
  }

  private func legendArea(
    in graphArea: Rect,
    xTitleWidth: Int,
    yTitleWidth: Int
  ) -> Rect? {
    guard let legendPosition else { return nil }
    let named = datasets.compactMap(\.name)
    guard !named.isEmpty else { return nil }
    let innerWidth = named.map(\.width).max() ?? 0
    let width = innerWidth + 2
    let height = named.count + 2
    let maximumWidth = legendLimit(legendConstraints.width, extent: Int(graphArea.width))
    let maximumHeight = legendLimit(legendConstraints.height, extent: Int(graphArea.height))
    guard innerWidth > 0, width <= maximumWidth, height <= maximumHeight else { return nil }
    var verticalMargin = Int(graphArea.height) - height
    if xTitleWidth > 0 { verticalMargin -= 1 }
    if yTitleWidth > 0 { verticalMargin -= 1 }
    guard verticalMargin >= 0 else { return nil }

    let horizontalCenter = Int(graphArea.x) + (Int(graphArea.width) - width) / 2
    let x: Int
    switch legendPosition {
    case .topLeading, .leading, .bottomLeading: x = Int(graphArea.x)
    case .top, .bottom: x = horizontalCenter
    case .topTrailing, .trailing, .bottomTrailing:
      x = Int(graphArea.x) + Int(graphArea.width) - width
    }
    let y: Int
    switch legendPosition {
    case .topLeading:
      y = Int(graphArea.y) + (yTitleWidth > 0 ? 1 : 0)
    case .topTrailing:
      y = Int(graphArea.y) + (width + yTitleWidth > Int(graphArea.width) ? 1 : 0)
    case .top:
      y = Int(graphArea.y) + (Int(graphArea.x) + yTitleWidth > horizontalCenter ? 1 : 0)
    case .leading, .trailing:
      var offset = (Int(graphArea.height) - height) / 2
      if yTitleWidth > 0 { offset += 1 }
      if xTitleWidth > 0 { offset = max(0, offset - 1) }
      y = Int(graphArea.y) + offset
    case .bottomLeading:
      y =
        Int(graphArea.y) + Int(graphArea.height) - height
        - (xTitleWidth + width > Int(graphArea.width) ? 1 : 0)
    case .bottomTrailing:
      y = Int(graphArea.y) + Int(graphArea.height) - height - (xTitleWidth > 0 ? 1 : 0)
    case .bottom:
      y =
        Int(graphArea.y) + Int(graphArea.height) - height
        - (horizontalCenter + width > graphRight(graphArea) - xTitleWidth ? 1 : 0)
    }
    return Rect(
      x: UInt16(clamping: x),
      y: UInt16(clamping: y),
      width: UInt16(clamping: width),
      height: UInt16(clamping: height)
    )
  }

  private func renderLegend(
    _ legendArea: Rect?,
    into buffer: inout Buffer,
    environment: RenderEnvironment
  ) {
    guard let legendArea else { return }
    Block(borders: .plain) { Text("") }.render(in: legendArea, into: &buffer)
    let named = datasets.compactMap { dataset in dataset.name.map { ($0, dataset.style) } }
    for (row, entry) in named.enumerated() {
      render(
        entry.0.patchStyle(entry.1),
        in: Rect(
          x: legendArea.x + 1,
          y: UInt16(clamping: Int(legendArea.y) + row + 1),
          width: legendArea.width - 2,
          height: 1
        ),
        into: &buffer,
        environment: environment
      )
    }
  }

  private func legendLimit(_ constraint: Constraint, extent: Int) -> Int {
    switch constraint {
    case .min: extent
    case .max(let value), .length(let value): min(extent, Int(value))
    case .percentage(let value): min(extent, extent * Int(value) / 100)
    case .ratio(let numerator, let denominator):
      denominator == 0 ? 0 : min(extent, extent * Int(numerator) / Int(denominator))
    case .flex: extent
    }
  }

  private func range(_ values: [Double]) -> ClosedRange<Double> {
    let lower = values.min() ?? 0
    let upper = values.max() ?? 1
    return lower == upper ? lower...(upper + 1) : lower...upper
  }
}
