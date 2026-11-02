import Foundation

public struct Point: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double = 0, y: Double = 0) {
        self.x = x
        self.y = y
    }
    public func offset(x dx: Double, y dy: Double) -> Point { Point(x: x + dx, y: y + dy) }
    public func distance(to p: Point) -> Double { hypot(x - p.x, y - p.y) }
    public var isValid: Bool { x.isFinite && y.isFinite && abs(x) <= 1_000_000 && abs(y) <= 1_000_000 }
}

public struct Rect: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
    public var center: Point { Point(x: x + width / 2, y: y + height / 2) }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public func contains(_ p: Point) -> Bool { p.x >= x && p.x <= maxX && p.y >= y && p.y <= maxY }
    public func intersects(_ r: Rect) -> Bool { maxX >= r.x && r.maxX >= x && maxY >= r.y && r.maxY >= y }
    public func union(_ r: Rect) -> Rect {
        let left = min(x, r.x)
        let top = min(y, r.y)
        return Rect(x: left, y: top, width: max(maxX, r.maxX) - left, height: max(maxY, r.maxY) - top)
    }
    public func expanded(by v: Double) -> Rect {
        Rect(x: x - v, y: y - v, width: width + 2 * v, height: height + 2 * v)
    }
}

public struct Camera: Equatable, Sendable {
    public var offset: Point
    public var scale: Double
    public init(offset: Point = Point(x: 80, y: 80), scale: Double = 1) {
        self.offset = offset
        self.scale = scale
    }
    public func world(_ screen: Point) -> Point {
        Point(x: (screen.x - offset.x) / scale, y: (screen.y - offset.y) / scale)
    }
    public func screen(_ world: Point) -> Point { Point(x: world.x * scale + offset.x, y: world.y * scale + offset.y) }
    public mutating func zoom(to newScale: Double, at anchor: Point) {
        let worldAnchor = world(anchor)
        scale = min(8, max(0.05, newScale))
        offset = Point(x: anchor.x - worldAnchor.x * scale, y: anchor.y - worldAnchor.y * scale)
    }
}
