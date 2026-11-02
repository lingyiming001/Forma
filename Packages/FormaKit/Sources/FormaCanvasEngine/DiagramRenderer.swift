@preconcurrency import AppKit
import FormaDomain
import FormaGeometry

extension Rect {
    public var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}
extension Point { public var cgPoint: CGPoint { CGPoint(x: x, y: y) } }
extension NSColor {
    public convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: alpha)
    }
}

public enum ConnectionGeometry {
    public static func point(on node: DiagramNode, anchor: EdgeAnchor) -> Point {
        let f = node.frame
        let value = min(1, max(0, anchor.position))
        let toward: Point =
            switch anchor.side {
            case .top: Point(x: f.x + f.width * value, y: f.y)
            case .right: Point(x: f.maxX, y: f.y + f.height * value)
            case .bottom: Point(x: f.x + f.width * value, y: f.maxY)
            case .left: Point(x: f.x, y: f.y + f.height * value)
            }
        return node.anchor(toward: toward)
    }
    public static func nearestAnchor(on node: DiagramNode, to point: Point, snapDistance: Double) -> EdgeAnchor {
        let f = node.frame
        let candidates: [(EdgeAnchor.Side, Double, Double)] = [
            (.top, (point.x - f.x) / f.width, abs(point.y - f.y)),
            (.right, (point.y - f.y) / f.height, abs(point.x - f.maxX)),
            (.bottom, (point.x - f.x) / f.width, abs(point.y - f.maxY)),
            (.left, (point.y - f.y) / f.height, abs(point.x - f.x)),
        ]
        let side = candidates.min { $0.2 < $1.2 }!
        var position = min(1, max(0, side.1))
        let length = side.0 == .top || side.0 == .bottom ? f.width : f.height
        if abs(position - 0.5) * length <= snapDistance { position = 0.5 }
        return EdgeAnchor(side: side.0, position: position)
    }
    private static func outset(_ point: Point, side: EdgeAnchor.Side, by distance: Double) -> Point {
        switch side {
        case .top: point.offset(x: 0, y: -distance)
        case .right: point.offset(x: distance, y: 0)
        case .bottom: point.offset(x: 0, y: distance)
        case .left: point.offset(x: -distance, y: 0)
        }
    }
    public static func points(for edge: DiagramEdge, nodes: [UUID: DiagramNode]) -> [Point] {
        guard let a = nodes[edge.source], let b = nodes[edge.target] else { return [] }
        if let waypoints = edge.waypoints, !waypoints.isEmpty {
            let start = edge.sourceAnchor.map { point(on: a, anchor: $0) } ?? a.anchor(toward: waypoints[0])
            let end =
                edge.targetAnchor.map { point(on: b, anchor: $0) } ?? b.anchor(toward: waypoints[waypoints.count - 1])
            return [start] + waypoints + [end]
        }
        let horizontal = abs(b.frame.center.x - a.frame.center.x) >= abs(b.frame.center.y - a.frame.center.y)
        if edge.sourceAnchor != nil || edge.targetAnchor != nil {
            let sourceSide: EdgeAnchor.Side =
                horizontal
                ? (b.frame.center.x >= a.frame.center.x ? .right : .left)
                : (b.frame.center.y >= a.frame.center.y ? .bottom : .top)
            let targetSide: EdgeAnchor.Side =
                horizontal
                ? (b.frame.center.x >= a.frame.center.x ? .left : .right)
                : (b.frame.center.y >= a.frame.center.y ? .top : .bottom)
            let from = edge.sourceAnchor ?? EdgeAnchor(side: sourceSide)
            let to = edge.targetAnchor ?? EdgeAnchor(side: targetSide)
            let p = point(on: a, anchor: from)
            let q = point(on: b, anchor: to)
            let first = outset(p, side: from.side, by: 20)
            let last = outset(q, side: to.side, by: 20)
            let sourceHorizontal = from.side == .left || from.side == .right
            let targetHorizontal = to.side == .left || to.side == .right
            if sourceHorizontal && targetHorizontal {
                let mid = (first.x + last.x) / 2
                return [p, first, Point(x: mid, y: first.y), Point(x: mid, y: last.y), last, q]
            }
            if !sourceHorizontal && !targetHorizontal {
                let mid = (first.y + last.y) / 2
                return [p, first, Point(x: first.x, y: mid), Point(x: last.x, y: mid), last, q]
            }
            let corner = sourceHorizontal ? Point(x: first.x, y: last.y) : Point(x: last.x, y: first.y)
            return [p, first, corner, last, q]
        }
        if horizontal {
            let forward = b.frame.center.x >= a.frame.center.x
            let p = Point(x: forward ? a.frame.maxX : a.frame.x, y: a.frame.center.y)
            let q = Point(x: forward ? b.frame.x : b.frame.maxX, y: b.frame.center.y)
            let mid = (p.x + q.x) / 2
            return [p, Point(x: mid, y: p.y), Point(x: mid, y: q.y), q]
        } else {
            let forward = b.frame.center.y >= a.frame.center.y
            let p = Point(x: a.frame.center.x, y: forward ? a.frame.maxY : a.frame.y)
            let q = Point(x: b.frame.center.x, y: forward ? b.frame.y : b.frame.maxY)
            let mid = (p.y + q.y) / 2
            return [p, Point(x: p.x, y: mid), Point(x: q.x, y: mid), q]
        }
    }
    /// Remove redundant automatic bends before presenting editable handles.
    public static func editableRoute(for edge: DiagramEdge, nodes: [UUID: DiagramNode]) -> [Point] {
        let route = points(for: edge, nodes: nodes)
        guard edge.waypoints?.isEmpty != false else { return route }
        var result: [Point] = []
        for point in route {
            if result.last == point { continue }
            while result.count > 1 {
                let a = result[result.count - 2]
                let b = result[result.count - 1]
                let cross = (b.x - a.x) * (point.y - b.y) - (b.y - a.y) * (point.x - b.x)
                let dot = (b.x - a.x) * (point.x - b.x) + (b.y - a.y) * (point.y - b.y)
                guard abs(cross) < 0.001 && dot >= 0 else { break }
                result.removeLast()
            }
            result.append(point)
        }
        return result
    }
    public static func distance(_ p: Point, to a: Point, _ b: Point) -> Double {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let length = dx * dx + dy * dy
        if length == 0 { return p.distance(to: a) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / length))
        return p.distance(to: Point(x: a.x + t * dx, y: a.y + t * dy))
    }
    public static func midpoint(of points: [Point]) -> Point {
        guard let first = points.first else { return Point() }
        let lengths = zip(points, points.dropFirst()).map { $0.0.distance(to: $0.1) }
        var remaining = lengths.reduce(0, +) / 2
        for (i, length) in lengths.enumerated() where length > 0 {
            if remaining <= length {
                let fraction = remaining / length
                return Point(
                    x: points[i].x + (points[i + 1].x - points[i].x) * fraction,
                    y: points[i].y + (points[i + 1].y - points[i].y) * fraction)
            }
            remaining -= length
        }
        return points.last ?? first
    }
}

public enum DiagramRenderer {
    public static let accent = NSColor(hex: 0x5364EF)
    public static func path(for node: DiagramNode) -> CGPath {
        let rect = node.frame.cgRect
        switch node.kind {
        case .ellipse, .umlUseCase: return CGPath(ellipseIn: rect, transform: nil)
        case .diamond:
            let p = CGMutablePath()
            p.move(to: CGPoint(x: rect.midX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            p.closeSubpath()
            return p
        case .database, .dataStore:
            let p = CGMutablePath()
            p.move(to: CGPoint(x: rect.minX, y: rect.minY + 9))
            p.addCurve(
                to: CGPoint(x: rect.maxX, y: rect.minY + 9), control1: CGPoint(x: rect.minX, y: rect.minY - 3),
                control2: CGPoint(x: rect.maxX, y: rect.minY - 3))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - 9))
            p.addCurve(
                to: CGPoint(x: rect.minX, y: rect.maxY - 9), control1: CGPoint(x: rect.maxX, y: rect.maxY + 3),
                control2: CGPoint(x: rect.minX, y: rect.maxY + 3))
            p.closeSubpath()
            return p
        case .package:
            let p = CGMutablePath()
            let tab = min(rect.width * 0.4, 72)
            let h = min(rect.height * 0.25, 18)
            p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.minX + tab, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.minX + tab, y: rect.minY + h))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + h))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.closeSubpath()
            return p
        case .rounded:
            let radius = min(node.effectiveCornerRadius, min(rect.width, rect.height) / 2)
            return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        case .arrowRight:
            let p = CGMutablePath()
            let headX = rect.minX + rect.width * 0.62
            let notch = rect.height * 0.26
            p.move(to: CGPoint(x: rect.minX, y: rect.minY + notch))
            p.addLine(to: CGPoint(x: headX, y: rect.minY + notch))
            p.addLine(to: CGPoint(x: headX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            p.addLine(to: CGPoint(x: headX, y: rect.maxY))
            p.addLine(to: CGPoint(x: headX, y: rect.maxY - notch))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - notch))
            p.closeSubpath()
            return p
        case .triangle:
            let p = CGMutablePath()
            p.move(to: CGPoint(x: rect.midX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.closeSubpath()
            return p
        case .hexagon:
            let p = CGMutablePath()
            let ix = rect.width * 0.25
            p.move(to: CGPoint(x: rect.minX + ix, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX - ix, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.maxX - ix, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX + ix, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            p.closeSubpath()
            return p
        case .parallelogram:
            let p = CGMutablePath()
            let sk = rect.width * 0.22
            p.move(to: CGPoint(x: rect.minX + sk, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX - sk, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.closeSubpath()
            return p
        case .note:
            let p = CGMutablePath()
            let fold = min(rect.width, rect.height) * 0.28
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX - fold, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + fold))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.closeSubpath()
            return p
        case .arrowUp:
            let p = CGMutablePath()
            let cx = rect.midX
            let headY = rect.minY + rect.height * 0.42
            let shaft = rect.width * 0.26
            p.move(to: CGPoint(x: cx - shaft, y: rect.maxY))
            p.addLine(to: CGPoint(x: cx - shaft, y: headY))
            p.addLine(to: CGPoint(x: rect.minX, y: headY))
            p.addLine(to: CGPoint(x: cx, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: headY))
            p.addLine(to: CGPoint(x: cx + shaft, y: headY))
            p.addLine(to: CGPoint(x: cx + shaft, y: rect.maxY))
            p.closeSubpath()
            return p
        case .arrowDown:
            let p = CGMutablePath()
            let cx = rect.midX
            let headY = rect.maxY - rect.height * 0.42
            let shaft = rect.width * 0.26
            p.move(to: CGPoint(x: cx - shaft, y: rect.minY))
            p.addLine(to: CGPoint(x: cx - shaft, y: headY))
            p.addLine(to: CGPoint(x: rect.minX, y: headY))
            p.addLine(to: CGPoint(x: cx, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.maxX, y: headY))
            p.addLine(to: CGPoint(x: cx + shaft, y: headY))
            p.addLine(to: CGPoint(x: cx + shaft, y: rect.minY))
            p.closeSubpath()
            return p
        case .arrowLeft:
            let p = CGMutablePath()
            let headX = rect.maxX - rect.width * 0.62
            let notch = rect.height * 0.26
            p.move(to: CGPoint(x: rect.maxX, y: rect.minY + notch))
            p.addLine(to: CGPoint(x: headX, y: rect.minY + notch))
            p.addLine(to: CGPoint(x: headX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            p.addLine(to: CGPoint(x: headX, y: rect.maxY))
            p.addLine(to: CGPoint(x: headX, y: rect.maxY - notch))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - notch))
            p.closeSubpath()
            return p
        case .terminator:
            let r = min(rect.width, rect.height) / 2
            return CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
        case .document:
            let p = CGMutablePath()
            let amp = rect.height * 0.18
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - amp))
            p.addCurve(
                to: CGPoint(x: rect.minX, y: rect.maxY - amp),
                control1: CGPoint(x: rect.maxX - rect.width * 0.25, y: rect.maxY + amp),
                control2: CGPoint(x: rect.minX + rect.width * 0.25, y: rect.maxY - amp * 2.2))
            p.closeSubpath()
            return p
        case .cloud:
            let p = CGMutablePath()
            let w = rect.width
            let h = rect.height
            p.move(to: CGPoint(x: rect.minX, y: rect.maxY - h * 0.35))
            p.addLine(to: CGPoint(x: rect.maxX - w * 0.02, y: rect.maxY - h * 0.35))
            p.addCurve(
                to: CGPoint(x: rect.maxX - w * 0.28, y: rect.maxY - h * 0.55),
                control1: CGPoint(x: rect.maxX + w * 0.05, y: rect.maxY - h * 0.55),
                control2: CGPoint(x: rect.maxX - w * 0.02, y: rect.maxY - h * 0.78))
            p.addCurve(
                to: CGPoint(x: rect.midX + w * 0.05, y: rect.maxY - h * 0.62),
                control1: CGPoint(x: rect.maxX - w * 0.35, y: rect.maxY - h * 0.98),
                control2: CGPoint(x: rect.midX + w * 0.3, y: rect.maxY - h * 0.98))
            p.addCurve(
                to: CGPoint(x: rect.minX + w * 0.2, y: rect.maxY - h * 0.5),
                control1: CGPoint(x: rect.midX - w * 0.25, y: rect.maxY - h * 0.98),
                control2: CGPoint(x: rect.minX, y: rect.maxY - h * 0.8))
            p.addCurve(
                to: CGPoint(x: rect.minX, y: rect.maxY - h * 0.35),
                control1: CGPoint(x: rect.minX - w * 0.12, y: rect.maxY - h * 0.5),
                control2: CGPoint(x: rect.minX - w * 0.08, y: rect.maxY - h * 0.32))
            p.closeSubpath()
            return p
        case .star:
            let p = CGMutablePath()
            let cx = rect.midX
            let cy = rect.midY
            let outer = min(rect.width, rect.height) / 2
            let inner = outer * 0.42
            for i in 0..<10 {
                let r = (i % 2 == 0) ? outer : inner
                let angle = -Double.pi / 2 + Double(i) * Double.pi / 5
                let pt = CGPoint(x: cx + r * cos(angle), y: cy + r * sin(angle))
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            p.closeSubpath()
            return p
        case .venn:
            let p = CGMutablePath()
            let d = rect.height
            p.addEllipse(in: CGRect(x: rect.minX, y: rect.minY, width: d, height: d))
            p.addEllipse(in: CGRect(x: rect.maxX - d, y: rect.minY, width: d, height: d))
            return p
        case .speech:
            let p = CGMutablePath()
            let bodyBottom = rect.minY + rect.height * 0.76
            p.addRoundedRect(
                in: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: bodyBottom - rect.minY),
                cornerWidth: 14, cornerHeight: 14)
            p.move(to: CGPoint(x: rect.minX + 20, y: bodyBottom - 2))
            p.addLine(to: CGPoint(x: rect.minX + 12, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX + 52, y: bodyBottom - 2))
            p.closeSubpath()
            return p
        case .funnel:
            let p = CGMutablePath()
            let stem = rect.width * 0.16
            let shoulder = rect.minY + rect.height * 0.55
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.midX + stem, y: shoulder))
            p.addLine(to: CGPoint(x: rect.midX + stem, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.midX - stem, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.midX - stem, y: shoulder))
            p.closeSubpath()
            return p
        case .octagon:
            let p = CGMutablePath()
            let kx = rect.width * 0.29
            let ky = rect.height * 0.29
            p.move(to: CGPoint(x: rect.minX + kx, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX - kx, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + ky))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - ky))
            p.addLine(to: CGPoint(x: rect.maxX - kx, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX + kx, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - ky))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + ky))
            p.closeSubpath()
            return p
        case .pentagon:
            let p = CGMutablePath()
            p.move(to: CGPoint(x: rect.midX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.42))
            p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.81, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.19, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.42))
            p.closeSubpath()
            return p
        case .doubleArrow:
            let p = CGMutablePath()
            let cx = rect.midX
            let shaft = rect.width * 0.22
            let head = rect.height * 0.28
            p.move(to: CGPoint(x: cx, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + head))
            p.addLine(to: CGPoint(x: cx + shaft, y: rect.minY + head))
            p.addLine(to: CGPoint(x: cx + shaft, y: rect.maxY - head))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - head))
            p.addLine(to: CGPoint(x: cx, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - head))
            p.addLine(to: CGPoint(x: cx - shaft, y: rect.maxY - head))
            p.addLine(to: CGPoint(x: cx - shaft, y: rect.minY + head))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + head))
            p.closeSubpath()
            return p
        case .cross:
            let p = CGMutablePath()
            let x = rect.width * 0.32
            let y = rect.height * 0.32
            p.move(to: CGPoint(x: rect.minX + x, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX - x, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX - x, y: rect.minY + y))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + y))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - y))
            p.addLine(to: CGPoint(x: rect.maxX - x, y: rect.maxY - y))
            p.addLine(to: CGPoint(x: rect.maxX - x, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX + x, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX + x, y: rect.maxY - y))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - y))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + y))
            p.addLine(to: CGPoint(x: rect.minX + x, y: rect.minY + y))
            p.closeSubpath()
            return p
        case .heart:
            let p = CGMutablePath()
            p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
            p.addCurve(
                to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.3),
                control1: CGPoint(x: rect.midX - rect.width * 0.18, y: rect.maxY - rect.height * 0.18),
                control2: CGPoint(x: rect.minX, y: rect.midY))
            p.addCurve(
                to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.22),
                control1: CGPoint(x: rect.minX, y: rect.minY - rect.height * 0.05),
                control2: CGPoint(x: rect.midX - rect.width * 0.18, y: rect.minY))
            p.addCurve(
                to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.3),
                control1: CGPoint(x: rect.midX + rect.width * 0.18, y: rect.minY),
                control2: CGPoint(x: rect.maxX, y: rect.minY - rect.height * 0.05))
            p.addCurve(
                to: CGPoint(x: rect.midX, y: rect.maxY),
                control1: CGPoint(x: rect.maxX, y: rect.midY),
                control2: CGPoint(x: rect.midX + rect.width * 0.18, y: rect.maxY - rect.height * 0.18))
            p.closeSubpath()
            return p
        case .manualInput:
            let p = CGMutablePath()
            p.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.22))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.closeSubpath()
            return p
        case .delay:
            let p = CGMutablePath()
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
            p.addCurve(
                to: CGPoint(x: rect.midX, y: rect.maxY), control1: CGPoint(x: rect.maxX, y: rect.minY),
                control2: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.closeSubpath()
            return p
        case .display:
            let p = CGMutablePath()
            p.move(to: CGPoint(x: rect.minX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.2, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.2, y: rect.minY))
            p.addCurve(
                to: CGPoint(x: rect.maxX - rect.width * 0.2, y: rect.maxY),
                control1: CGPoint(x: rect.maxX + rect.width * 0.08, y: rect.minY),
                control2: CGPoint(x: rect.maxX + rect.width * 0.08, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.2, y: rect.maxY))
            p.closeSubpath()
            return p
        case .multiDocument:
            return path(
                for: DiagramNode(
                    title: node.title, kind: .document, frame: node.frame, color: node.color,
                    fontSize: node.fontSize))
        case .card:
            let p = CGMutablePath()
            let cut = min(rect.width, rect.height) * 0.2
            p.move(to: CGPoint(x: rect.minX + cut, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cut))
            p.closeSubpath()
            return p
        case .tape:
            let p = CGMutablePath()
            let wave = rect.height * 0.15
            p.move(to: CGPoint(x: rect.minX, y: rect.minY + wave))
            p.addCurve(
                to: CGPoint(x: rect.maxX, y: rect.minY + wave),
                control1: CGPoint(x: rect.minX + rect.width * 0.33, y: rect.minY - wave),
                control2: CGPoint(x: rect.minX + rect.width * 0.66, y: rect.minY + wave * 3))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - wave))
            p.addCurve(
                to: CGPoint(x: rect.minX, y: rect.maxY - wave),
                control1: CGPoint(x: rect.minX + rect.width * 0.66, y: rect.maxY + wave),
                control2: CGPoint(x: rect.minX + rect.width * 0.33, y: rect.maxY - wave * 3))
            p.closeSubpath()
            return p
        case .merge:
            let p = CGMutablePath()
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            p.closeSubpath()
            return p
        case .collate:
            let p = CGMutablePath()
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.closeSubpath()
            return p
        case .server, .network, .firewall, .queue, .gateway:
            return CGPath(roundedRect: rect, cornerWidth: 6, cornerHeight: 6, transform: nil)
        default: return CGPath(rect: rect, transform: nil)
        }
    }
    public static func draw(
        _ model: Diagram, in context: CGContext, visible: Rect? = nil, selection: Set<UUID> = [], scale: Double = 1,
        darkCanvas: Bool = false
    ) {
        let nodes = Dictionary(uniqueKeysWithValues: model.nodes.map { ($0.id, $0) })
        context.saveGState()
        for panel in model.panels {
            if let visible, !visible.intersects(panel.frame.expanded(by: 8)) { continue }
            let r = panel.frame.cgRect
            context.setFillColor(NSColor(hex: panel.color.fillHex, alpha: darkCanvas ? 0.07 : 0.55).cgColor)
            context.addPath(CGPath(roundedRect: r, cornerWidth: 10, cornerHeight: 10, transform: nil))
            context.fillPath()
            context.setStrokeColor(NSColor(hex: panel.color.strokeHex, alpha: 0.7).cgColor)
            context.setLineWidth(1 / scale)
            context.addPath(CGPath(roundedRect: r, cornerWidth: 10, cornerHeight: 10, transform: nil))
            context.strokePath()
            let color = darkCanvas ? NSColor(hex: 0xDAE2F5) : NSColor(hex: 0x586984)
            drawString(
                panel.title, in: CGRect(x: r.minX + 16, y: r.minY + 12, width: r.width - 32, height: 22),
                attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: color],
                context: context)
            context.setStrokeColor(NSColor(hex: panel.color.strokeHex, alpha: 0.3).cgColor)
            context.move(to: CGPoint(x: r.minX, y: r.minY + 40))
            context.addLine(to: CGPoint(x: r.maxX, y: r.minY + 40))
            context.strokePath()
            if selection.contains(panel.id) {
                drawSelection(panel.frame, locked: panel.isLocked, in: context, scale: scale)
            }
        }
        for node in model.nodes where !node.isHidden {
            if let visible, !visible.intersects(node.frame.expanded(by: 12)) { continue }
            context.saveGState()
            context.setAlpha(node.effectiveOpacity)
            if node.kind != .text && node.kind != .umlActor {
                context.saveGState()
                context.setShadow(
                    offset: CGSize(width: 0, height: 2), blur: 5,
                    color: NSColor.black.withAlphaComponent(0.055).cgColor)
                context.addPath(path(for: node))
                context.setFillColor(NSColor(hex: node.color.fillHex).cgColor)
                context.fillPath()
                context.restoreGState()
                context.addPath(path(for: node))
                context.setStrokeColor(NSColor(hex: node.color.strokeHex).cgColor)
                context.setLineWidth(node.effectiveStrokeWidth)
                context.strokePath()
            }
            if node.kind == .database || node.kind == .dataStore {
                let r = node.frame.cgRect
                context.setStrokeColor(NSColor(hex: node.color.strokeHex).cgColor)
                context.setLineWidth(1.2)
                context.strokeEllipse(in: CGRect(x: r.minX, y: r.minY, width: r.width, height: 18))
            }
            if node.kind == .predefinedProcess {
                let r = node.frame.cgRect
                context.setStrokeColor(NSColor(hex: node.color.strokeHex).cgColor)
                context.setLineWidth(1.2)
                for x in [r.minX + 14, r.maxX - 14] {
                    context.move(to: CGPoint(x: x, y: r.minY))
                    context.addLine(to: CGPoint(x: x, y: r.maxY))
                    context.strokePath()
                }
            }
            if node.kind == .multiDocument {
                let r = node.frame.cgRect
                context.setStrokeColor(NSColor(hex: node.color.strokeHex).cgColor)
                context.setLineWidth(1.0)
                for offset in [CGPoint(x: -8, y: -8), CGPoint(x: -4, y: -4)] {
                    context.stroke(r.offsetBy(dx: offset.x, dy: offset.y))
                }
            }
            if node.kind == .component {
                context.setStrokeColor(NSColor(hex: node.color.strokeHex).cgColor)
                for y in [node.frame.y + 12, node.frame.y + 26] {
                    context.stroke(CGRect(x: node.frame.maxX - 24, y: y, width: 16, height: 10))
                }
            }
            if node.kind == .umlActor {
                let r = node.frame.cgRect
                let cx = r.midX
                let top = r.minY + 8
                context.setStrokeColor((darkCanvas ? NSColor(hex: 0xDCE4F5) : NSColor(hex: 0x586984)).cgColor)
                context.setLineWidth(1.8)
                context.strokeEllipse(in: CGRect(x: cx - 12, y: top, width: 24, height: 24))
                for (a, b) in [
                    (CGPoint(x: cx, y: top + 24), CGPoint(x: cx, y: top + 66)),
                    (CGPoint(x: cx - 24, y: top + 42), CGPoint(x: cx + 24, y: top + 42)),
                    (CGPoint(x: cx, y: top + 66), CGPoint(x: cx - 22, y: top + 96)),
                    (CGPoint(x: cx, y: top + 66), CGPoint(x: cx + 22, y: top + 96)),
                ] {
                    context.move(to: a)
                    context.addLine(to: b)
                    context.strokePath()
                }
                let paragraph = NSMutableParagraphStyle()
                paragraph.alignment = node.effectiveTextAlignment.nsTextAlignment
                drawString(
                    node.title, in: CGRect(x: r.minX, y: top + 105, width: r.width, height: 28),
                    attributes: [
                        .font: NSFont.systemFont(ofSize: node.fontSize),
                        .foregroundColor: darkCanvas ? NSColor.white : NSColor(hex: 0x27344F),
                        .paragraphStyle: paragraph,
                    ], context: context)
            } else if node.kind.isClass {
                if scale >= 0.25 || selection.contains(node.id) { drawClass(node, context: context) }
            } else if scale >= 0.25 || selection.contains(node.id) {
                let paragraph = NSMutableParagraphStyle()
                paragraph.alignment = .center
                paragraph.lineBreakMode = .byWordWrapping
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: node.fontSize, weight: node.kind == .text ? .semibold : .medium),
                    .foregroundColor: NSColor(hex: darkCanvas && node.kind == .text ? 0xE2E8F5 : 0x27344F),
                    .paragraphStyle: paragraph,
                ]
                let text = node.title as NSString
                let padding = node.kind == .diamond ? 24.0 : 12.0
                let available = node.frame.cgRect.insetBy(dx: padding, dy: 8)
                let measured = text.boundingRect(
                    with: NSSize(width: max(1, available.width), height: 10_000),
                    options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs)
                let rect = CGRect(
                    x: available.minX, y: max(available.minY, node.frame.cgRect.midY - measured.height / 2),
                    width: available.width, height: min(available.height, measured.height + 2))
                context.saveGState()
                context.clip(to: node.frame.cgRect.insetBy(dx: 4, dy: 4))
                drawString(node.title, in: rect, attributes: attrs, context: context)
                context.restoreGState()
            }
            context.restoreGState()
            if selection.contains(node.id), node.groupID == nil {
                drawSelection(node.frame, locked: model.isLocked(node), in: context, scale: scale)
            }
        }
        // Connections stay visible across enclosing service shapes as well as free-standing nodes.
        for edge in model.edges {
            guard let source = nodes[edge.source], let target = nodes[edge.target], !source.isHidden, !target.isHidden
            else { continue }
            let pts = ConnectionGeometry.points(for: edge, nodes: nodes)
            guard pts.count > 1 else { continue }
            if let visible {
                let minX = pts.map(\.x).min() ?? 0
                let maxX = pts.map(\.x).max() ?? 0
                let minY = pts.map(\.y).min() ?? 0
                let maxY = pts.map(\.y).max() ?? 0
                let bounds = Rect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).expanded(by: 16)
                if !visible.intersects(bounds) { continue }
            }
            let selected = selection.contains(edge.id)
            context.setStrokeColor((selected ? accent : NSColor(hex: 0xA3ADBF)).cgColor)
            context.setLineWidth(selected ? 2.2 / scale : 1.5)
            context.setLineDash(phase: 0, lengths: edge.effectiveLineStyle.dashPattern.map { CGFloat($0) })
            context.setLineJoin(.round)
            context.setLineCap(.round)
            context.beginPath()
            context.move(to: pts[0].cgPoint)
            for p in pts.dropFirst() { context.addLine(to: p.cgPoint) }
            context.strokePath()
            context.setLineDash(phase: 0, lengths: [])
            if let end = pts.last, let start = pts.first {
                drawMarker(
                    edge.effectiveSourceMarker, at: start,
                    from: pts.dropFirst().first(where: { $0 != start }) ?? end,
                    selected: selected, context: context)
                drawMarker(
                    edge.effectiveTargetMarker, at: end,
                    from: pts.dropLast().last(where: { $0 != end }) ?? start,
                    selected: selected, context: context)
            }
            if !edge.label.isEmpty {
                let mid = ConnectionGeometry.midpoint(of: pts)
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor(hex: 0x65718A),
                ]
                let size = (edge.label as NSString).size(withAttributes: attrs)
                let rect = CGRect(
                    x: mid.x - size.width / 2 - 7, y: mid.y - size.height / 2 - 4, width: size.width + 14,
                    height: size.height + 8)
                context.setFillColor(NSColor.white.cgColor)
                context.addPath(CGPath(roundedRect: rect, cornerWidth: 6, cornerHeight: 6, transform: nil))
                context.fillPath()
                drawString(edge.label, in: rect.insetBy(dx: 7, dy: 4), attributes: attrs, context: context)
            }
        }
        let selectedGroups = Dictionary(
            grouping: model.nodes.filter {
                selection.contains($0.id) && !$0.isHidden && $0.groupID != nil
            }, by: { $0.groupID! })
        for nodes in selectedGroups.values {
            guard let first = nodes.first else { continue }
            let frame = nodes.dropFirst().reduce(first.frame.cgRect) { $0.union($1.frame.cgRect) }
            context.setStrokeColor(accent.cgColor)
            context.setLineWidth(1.5 / scale)
            context.setLineDash(phase: 0, lengths: [5 / scale, 3 / scale])
            context.stroke(frame.insetBy(dx: -6 / scale, dy: -6 / scale))
            context.setLineDash(phase: 0, lengths: [])
        }
        context.restoreGState()
    }
    private static func drawSelection(_ frame: Rect, locked: Bool, in context: CGContext, scale: Double) {
        context.setStrokeColor(accent.cgColor)
        context.setLineWidth(1.5 / scale)
        context.stroke(frame.cgRect.insetBy(dx: -3 / scale, dy: -3 / scale))
        guard !locked else { return }
        let size = 7 / scale
        for p in [
            CGPoint(x: frame.x, y: frame.y), CGPoint(x: frame.maxX, y: frame.y), CGPoint(x: frame.x, y: frame.maxY),
            CGPoint(x: frame.maxX, y: frame.maxY),
        ] {
            let rect = CGRect(x: p.x - size / 2, y: p.y - size / 2, width: size, height: size)
            context.setFillColor(NSColor.white.cgColor)
            context.fill(rect)
            context.stroke(rect)
        }
    }
    private static func drawClass(_ node: DiagramNode, context: CGContext) {
        let r = node.frame.cgRect
        let header = node.kind == .umlInterface || node.stereotype != nil ? 56.0 : 40.0
        let separator = r.minY + header + (r.height - header) * 0.5
        context.saveGState()
        context.clip(to: r.insetBy(dx: 2, dy: 2))
        context.setStrokeColor(NSColor(hex: node.color.strokeHex).cgColor)
        context.setLineWidth(1)
        for y in [r.minY + header, separator] {
            context.move(to: CGPoint(x: r.minX, y: y))
            context.addLine(to: CGPoint(x: r.maxX, y: y))
            context.strokePath()
        }
        let center = NSMutableParagraphStyle()
        center.alignment = .center
        let textColor = NSColor(hex: 0x27344F)
        if let stereotype = node.stereotype ?? (node.kind == .umlInterface ? "interface" : nil) {
            drawString(
                "«\(stereotype)»", in: CGRect(x: r.minX + 8, y: r.minY + 8, width: r.width - 16, height: 17),
                attributes: [
                    .font: NSFont.systemFont(ofSize: 11), .foregroundColor: textColor, .paragraphStyle: center,
                ], context: context)
        }
        drawString(
            node.title, in: CGRect(x: r.minX + 8, y: r.minY + header - 28, width: r.width - 16, height: 24),
            attributes: [
                .font: NSFont.systemFont(ofSize: node.fontSize, weight: .semibold), .foregroundColor: textColor,
                .paragraphStyle: center,
            ], context: context)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: max(10, node.fontSize - 2), weight: .regular),
            .foregroundColor: textColor,
        ]
        drawString(
            (node.attributes ?? []).joined(separator: "\n"),
            in: CGRect(
                x: r.minX + 12, y: r.minY + header + 10, width: r.width - 24, height: separator - r.minY - header - 16),
            attributes: attrs, context: context)
        drawString(
            (node.operations ?? []).joined(separator: "\n"),
            in: CGRect(x: r.minX + 12, y: separator + 10, width: r.width - 24, height: r.maxY - separator - 16),
            attributes: attrs, context: context)
        context.restoreGState()
    }
    private static func drawMarker(
        _ marker: EndpointMarker, at tip: Point, from previous: Point, selected: Bool, context: CGContext
    ) {
        guard marker != .none && marker != .automatic else { return }
        let angle = atan2(tip.y - previous.y, tip.x - previous.x)
        let color = selected ? accent : NSColor(hex: 0xA3ADBF)
        context.saveGState()
        context.setStrokeColor(color.cgColor)
        context.setFillColor(color.cgColor)
        context.setLineWidth(1.5)
        context.setLineDash(phase: 0, lengths: [])
        func point(_ back: Double, _ side: Double) -> CGPoint {
            CGPoint(
                x: tip.x - back * cos(angle) - side * sin(angle),
                y: tip.y - back * sin(angle) + side * cos(angle))
        }
        context.beginPath()
        switch marker {
        case .openArrow:
            context.move(to: point(10, -5))
            context.addLine(to: tip.cgPoint)
            context.addLine(to: point(10, 5))
            context.strokePath()
        case .filledTriangle, .hollowTriangle:
            let size = marker == .hollowTriangle ? 14.0 : 10.0
            context.move(to: tip.cgPoint)
            context.addLine(to: point(size, size * 0.45))
            context.addLine(to: point(size, -size * 0.45))
            context.closePath()
            context.setFillColor((marker == .hollowTriangle ? NSColor.white : color).cgColor)
            context.drawPath(using: .fillStroke)
        case .filledDiamond, .hollowDiamond:
            context.move(to: tip.cgPoint)
            context.addLine(to: point(9, 5))
            context.addLine(to: point(18, 0))
            context.addLine(to: point(9, -5))
            context.closePath()
            context.setFillColor((marker == .hollowDiamond ? NSColor.white : color).cgColor)
            context.drawPath(using: .fillStroke)
        case .circle:
            let center = point(5, 0)
            context.setFillColor(NSColor.white.cgColor)
            context.addEllipse(in: CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10))
            context.drawPath(using: .fillStroke)
        case .none, .automatic: break
        }
        context.restoreGState()
    }
    private static func drawString(
        _ text: String, in rect: CGRect, attributes: [NSAttributedString.Key: Any], context: CGContext
    ) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        (text as NSString).draw(in: rect, withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
    }
}

extension DiagramTextAlignment {
    fileprivate var nsTextAlignment: NSTextAlignment {
        switch self {
        case .leading: .left
        case .center: .center
        case .trailing: .right
        }
    }
}
