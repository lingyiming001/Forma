import AppKit
import FormaApplication
import FormaCanvasEngine
import FormaDomain
import FormaGeometry
import FormaLocalization
import SwiftUI

private let shapePasteboardType = NSPasteboard.PasteboardType("com.forma.shape-kind")

public struct CanvasHostView: NSViewRepresentable {
    let session: DocumentSession
    public init(session: DocumentSession) { self.session = session }
    public func makeNSView(context: Context) -> DiagramCanvasView { DiagramCanvasView(session: session) }
    public func updateNSView(_ view: DiagramCanvasView, context: Context) {
        _ = session.revision
        _ = session.selection
        _ = session.camera
        _ = session.showGrid
        _ = session.tool
        _ = session.fitRequest
        view.refresh()
    }
}

@MainActor public final class DiagramCanvasView: NSView, NSTextViewDelegate, NSUserInterfaceValidations {
    let session: DocumentSession
    private var preview: [UUID: Rect] = [:]
    private var panelPreview: [UUID: Rect] = [:]
    private var edgePreview: DiagramEdge?
    private var danglingEndpoint: Point?
    private var gesture: Gesture?
    private var marquee: Rect?
    private var connectionStart: UUID?
    private var pointer = Point()
    private var isSpaceDown = false
    private var lastFitRequest = -1
    private var hasFitted = false
    private var fitScheduled = false
    private var tracking: NSTrackingArea?
    private var editor: CanvasTextView?
    private var editingID: UUID?
    private var editingCamera: Camera?
    private var committing = false
    private enum Gesture {
        case pan(Point, Point)
        case move(Point, [UUID: Rect], [UUID: Rect], UInt64)
        case resizePanel(Point, DiagramPanel, Int, UInt64)
        case resize(Point, DiagramNode, Int, UInt64)
        case box(Point, Set<UUID>)
        case endpoint(UUID, Bool, UInt64)
        case waypoint(UUID, Int, [Point], UInt64)
    }
    public init(session: DocumentSession) {
        self.session = session
        super.init(frame: .zero)
        wantsLayer = true
        clipsToBounds = true
        layer?.masksToBounds = true
        registerForDraggedTypes([shapePasteboardType])
        setAccessibilityLabel(tr("图表画布"))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) 未使用") }
    public override var wantsDefaultClipping: Bool { true }
    public override var isFlipped: Bool { true }
    public override var acceptsFirstResponder: Bool { true }
    public func refresh() {
        setAccessibilityLabel(tr("图表画布"))

        if lastFitRequest != session.fitRequest {
            fitContent()
            lastFitRequest = session.fitRequest
        }
        if session.tool != .connector { connectionStart = nil }
        if let id = editingID {
            if !session.diagram.nodes.contains(where: { $0.id == id }) {
                finishText(cancel: true)
            } else if session.selection != [id] || session.tool != .select || editingCamera != session.camera {
                DispatchQueue.main.async { [weak self] in self?.finishText(cancel: false) }
            }
        }
        needsDisplay = true
    }
    public override func layout() {
        super.layout()
        session.viewportSize = Point(x: bounds.width, y: bounds.height)
        if !hasFitted && !fitScheduled && bounds.width > 10 {
            fitScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.fitContent()
                self.hasFitted = true
                self.needsDisplay = true
            }
        }
    }
    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: .zero, options: [.activeInKeyWindow, .mouseMoved, .inVisibleRect, .cursorUpdate], owner: self)
        addTrackingArea(area)
        tracking = area
    }
    public override func cursorUpdate(with event: NSEvent) {
        if isSpaceDown || session.tool == .hand {
            NSCursor.openHand.set()
        } else if session.tool == .select {
            NSCursor.arrow.set()
        } else {
            NSCursor.crosshair.set()
        }
    }
    public override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        draggedShape(from: sender) == nil ? [] : .copy
    }
    public override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        draggedShape(from: sender) == nil ? [] : .copy
    }
    public override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let kind = draggedShape(from: sender) else { return false }
        let location = convert(sender.draggingLocation, from: nil)
        session.add(kind, at: session.camera.world(Point(x: location.x, y: location.y)))
        return true
    }
    private func draggedShape(from sender: any NSDraggingInfo) -> ShapeKind? {
        sender.draggingPasteboard.string(forType: shapePasteboardType).flatMap(ShapeKind.init(rawValue:))
    }
    private func local(_ event: NSEvent) -> Point {
        let p = convert(event.locationInWindow, from: nil)
        return Point(x: p.x, y: p.y)
    }
    private func renderedModel() -> Diagram {
        var model = session.diagram
        if preview.count < 16 {
            for (id, frame) in preview {
                if let i = model.nodes.firstIndex(where: { $0.id == id }) { model.nodes[i].frame = frame }
            }
        } else {
            for i in model.nodes.indices { if let frame = preview[model.nodes[i].id] { model.nodes[i].frame = frame } }
        }
        if panelPreview.count < 16 {
            for (id, frame) in panelPreview {
                if let i = model.panels.firstIndex(where: { $0.id == id }) { model.panels[i].frame = frame }
            }
        } else {
            for i in model.panels.indices {
                if let frame = panelPreview[model.panels[i].id] { model.panels[i].frame = frame }
            }
        }
        if let edgePreview, let i = model.edges.firstIndex(where: { $0.id == edgePreview.id }) {
            model.edges[i] = edgePreview
        }
        return model
    }
    public override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.clip(to: bounds)
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let background: NSColor =
            switch session.diagram.backgroundStyle {
            case .system: NSColor(hex: dark ? 0x20232C : 0xFAFBFD)
            case .white: NSColor(hex: 0xFFFFFF)
            case .warm: NSColor(hex: 0xFBF8F2)
            case .cool: NSColor(hex: 0xF3F6FA)
            case .sand: NSColor(hex: 0xF6F0E4)
            case .mint: NSColor(hex: 0xEEF7F2)
            case .lavender: NSColor(hex: 0xF4F1FA)
            case .graphite: NSColor(hex: 0x20232C)
            }
        ctx.setFillColor(background.cgColor)
        ctx.fill(bounds)
        let camera = session.camera
        if session.showGrid {
            // 网格改为次/主分层线阵：次线细淡、主线清晰，对齐世界原点，随缩放自适应密度。
            var step = session.diagram.gridSize * camera.scale
            while step < 14 { step *= 2 }
            while step > 48 { step /= 2 }
            let darkCanvas =
                session.diagram.backgroundStyle == .graphite
                || (session.diagram.backgroundStyle == .system && dark)
            let opacity = session.diagram.gridOpacity
            let minor = NSColor(hex: darkCanvas ? 0x596175 : 0xC8D1DF).withAlphaComponent(0.55 * opacity)
            let major = NSColor(hex: darkCanvas ? 0x7B849B : 0x9BA9BE).withAlphaComponent(0.82 * opacity)
            let originX = camera.offset.x.truncatingRemainder(dividingBy: step)
            let originY = camera.offset.y.truncatingRemainder(dividingBy: step)
            var column = Int(floor((originX - camera.offset.x) / step))
            var x = originX
            if x < 0 {
                x += step
                column += 1
            }
            var row = Int(floor((originY - camera.offset.y) / step))
            var y = originY
            if y < 0 {
                y += step
                row += 1
            }
            if session.diagram.gridStyle == .lines {
                while x <= bounds.width {
                    let isMajor = column % 5 == 0
                    ctx.setStrokeColor((isMajor ? major : minor).cgColor)
                    ctx.setLineWidth(isMajor ? 1.0 : 0.5)
                    ctx.move(to: CGPoint(x: x, y: 0))
                    ctx.addLine(to: CGPoint(x: x, y: bounds.height))
                    ctx.strokePath()
                    x += step
                    column += 1
                }
                while y <= bounds.height {
                    let isMajor = row % 5 == 0
                    ctx.setStrokeColor((isMajor ? major : minor).cgColor)
                    ctx.setLineWidth(isMajor ? 1.0 : 0.5)
                    ctx.move(to: CGPoint(x: 0, y: y))
                    ctx.addLine(to: CGPoint(x: bounds.width, y: y))
                    ctx.strokePath()
                    y += step
                    row += 1
                }
            } else {
                while y <= bounds.height {
                    var dotX = x
                    var dotColumn = column
                    while dotX <= bounds.width {
                        let isMajor = row % 5 == 0 && dotColumn % 5 == 0
                        let radius = isMajor ? 1.35 : 0.8
                        ctx.setFillColor((isMajor ? major : minor).cgColor)
                        ctx.fillEllipse(
                            in: CGRect(x: dotX - radius, y: y - radius, width: radius * 2, height: radius * 2))
                        dotX += step
                        dotColumn += 1
                    }
                    y += step
                    row += 1
                }
            }
        }
        ctx.saveGState()
        ctx.translateBy(x: camera.offset.x, y: camera.offset.y)
        ctx.scaleBy(x: camera.scale, y: camera.scale)
        let origin = camera.world(Point())
        let end = camera.world(Point(x: bounds.width, y: bounds.height))
        DiagramRenderer.draw(
            renderedModel(), in: ctx,
            visible: Rect(x: origin.x, y: origin.y, width: end.x - origin.x, height: end.y - origin.y),
            selection: session.selection, scale: camera.scale,
            darkCanvas: session.diagram.backgroundStyle == .graphite
                || (session.diagram.backgroundStyle == .system && dark))
        if let edge = renderedModel().edges.first(where: { session.selection.contains($0.id) }) {
            let nodes = Dictionary(uniqueKeysWithValues: renderedModel().nodes.map { ($0.id, $0) })
            let points = ConnectionGeometry.points(for: edge, nodes: nodes)
            if let start = points.first, let end = points.last, points.count > 1 {
                if let danglingEndpoint, case .endpoint(_, let source, _) = gesture {
                    ctx.setStrokeColor(DiagramRenderer.accent.withAlphaComponent(0.7).cgColor)
                    ctx.setLineWidth(1.5 / camera.scale)
                    ctx.setLineDash(phase: 0, lengths: [5 / camera.scale, 4 / camera.scale])
                    ctx.move(to: (source ? end : start).cgPoint)
                    ctx.addLine(to: danglingEndpoint.cgPoint)
                    ctx.strokePath()
                    ctx.setLineDash(phase: 0, lengths: [])
                }
                let route = ConnectionGeometry.editableRoute(for: edge, nodes: nodes)
                for point in route.dropFirst().dropLast() {
                    let size = 7 / camera.scale
                    ctx.setFillColor(DiagramRenderer.accent.cgColor)
                    ctx.fill(CGRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size))
                }
                for (a, b) in zip(route, route.dropFirst()) where a.distance(to: b) > 28 / camera.scale {
                    let point = Point(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                    let size = 6 / camera.scale
                    let rect = CGRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size)
                    ctx.setFillColor(NSColor.white.cgColor)
                    ctx.fill(rect)
                    ctx.setStrokeColor(DiagramRenderer.accent.cgColor)
                    ctx.setLineWidth(1 / camera.scale)
                    ctx.stroke(rect)
                }
                for point in [start, end] {
                    let radius = 5 / camera.scale
                    ctx.setFillColor(NSColor.white.cgColor)
                    ctx.fillEllipse(
                        in: CGRect(
                            x: point.x - radius, y: point.y - radius,
                            width: radius * 2, height: radius * 2))
                    ctx.setStrokeColor(DiagramRenderer.accent.cgColor)
                    ctx.setLineWidth(1.5 / camera.scale)
                    ctx.strokeEllipse(
                        in: CGRect(
                            x: point.x - radius, y: point.y - radius,
                            width: radius * 2, height: radius * 2))
                }
            }
        }
        if let id = connectionStart, let node = session.diagram.nodes.first(where: { $0.id == id }) {
            ctx.setStrokeColor(DiagramRenderer.accent.cgColor)
            ctx.setLineWidth(1.5 / camera.scale)
            ctx.setLineDash(phase: 0, lengths: [5 / camera.scale, 4 / camera.scale])
            ctx.move(to: node.anchor(toward: pointer).cgPoint)
            ctx.addLine(to: pointer.cgPoint)
            ctx.strokePath()
            ctx.setLineDash(phase: 0, lengths: [])
        }
        if let r = marquee {
            ctx.setFillColor(DiagramRenderer.accent.withAlphaComponent(0.07).cgColor)
            ctx.fill(r.cgRect)
            ctx.setStrokeColor(DiagramRenderer.accent.withAlphaComponent(0.65).cgColor)
            ctx.setLineWidth(1 / camera.scale)
            ctx.stroke(r.cgRect)
        }
        ctx.restoreGState()
    }
    /// Prefer the innermost shape when service boundaries surround actionable nodes.
    /// Unrelated overlapping shapes retain their normal front-to-back order.
    private func hitNode(_ p: Point, tolerance: Double = 0) -> DiagramNode? {
        let candidates = renderedModel().nodes.reversed().filter {
            !$0.isHidden && !session.diagram.isLocked($0)
                && (tolerance > 0 ? $0.frame.expanded(by: tolerance).contains(p) : $0.contains(p))
        }
        return candidates.first { candidate in
            !candidates.contains { other in
                other.id != candidate.id
                    && other.frame.width * other.frame.height < candidate.frame.width * candidate.frame.height
                    && candidate.frame.contains(Point(x: other.frame.x, y: other.frame.y))
                    && candidate.frame.contains(Point(x: other.frame.maxX, y: other.frame.maxY))
            }
        }
    }
    private func hitEdge(_ p: Point) -> UUID? {
        let nodes = Dictionary(uniqueKeysWithValues: session.diagram.nodes.map { ($0.id, $0) })
        return session.diagram.edges.reversed().first { edge in
            guard nodes[edge.source]?.isHidden == false, nodes[edge.target]?.isHidden == false else { return false }
            let points = ConnectionGeometry.points(for: edge, nodes: nodes)
            return zip(points, points.dropFirst()).contains {
                ConnectionGeometry.distance(p, to: $0.0, $0.1) < 6 / session.camera.scale
            }
        }?.id
    }
    private func hitEndpoint(_ p: Point) -> (UUID, Bool)? {
        let nodes = Dictionary(uniqueKeysWithValues: session.diagram.nodes.map { ($0.id, $0) })
        let edges =
            session.diagram.edges.filter { session.selection.contains($0.id) }
            + Array(session.diagram.edges.filter { !session.selection.contains($0.id) }.reversed())
        for edge in edges {
            guard let source = nodes[edge.source], let target = nodes[edge.target],
                !source.isHidden, !target.isHidden,
                !session.diagram.isLocked(source), !session.diagram.isLocked(target)
            else { continue }
            let points = ConnectionGeometry.points(for: edge, nodes: nodes)
            guard let first = points.first, let last = points.last else { continue }
            if p.distance(to: last) < 10 / session.camera.scale { return (edge.id, false) }
            if p.distance(to: first) < 10 / session.camera.scale { return (edge.id, true) }
        }
        return nil
    }
    private func attachment(at p: Point) -> (UUID, EdgeAnchor)? {
        let tolerance = 12 / session.camera.scale
        guard let node = hitNode(p, tolerance: tolerance) else { return nil }
        return (node.id, ConnectionGeometry.nearestAnchor(on: node, to: p, snapDistance: tolerance))
    }
    public override func mouseMoved(with event: NSEvent) {
        pointer = session.camera.world(local(event))
        if connectionStart != nil { needsDisplay = true }
    }
    public override func mouseDown(with event: NSEvent) {
        finishText(cancel: false)
        window?.makeFirstResponder(self)
        let screen = local(event)
        let p = session.camera.world(screen)
        pointer = p
        if isSpaceDown || session.tool == .hand {
            gesture = .pan(screen, session.camera.offset)
            NSCursor.closedHand.set()
            return
        }
        if session.tool == .panel {
            session.addPanel(at: p)
            return
        }
        if let kind = session.tool.shape {
            session.add(kind, at: p)
            return
        }
        if session.tool == .connector {
            if let node = hitNode(p) {
                if let start = connectionStart {
                    session.connect(from: start, to: node.id)
                    connectionStart = nil
                    session.tool = .select
                } else {
                    connectionStart = node.id
                    session.selection = [node.id]
                }
            } else {
                connectionStart = nil
            }
            needsDisplay = true
            return
        }
        if let edge = session.selectedEdge {
            let nodes = Dictionary(uniqueKeysWithValues: session.diagram.nodes.map { ($0.id, $0) })
            let route = ConnectionGeometry.editableRoute(for: edge, nodes: nodes)
            var controls = Array(route.dropFirst().dropLast())
            if let index = controls.firstIndex(where: { $0.distance(to: p) < 9 / session.camera.scale }) {
                if event.clickCount == 2 {
                    controls.remove(at: index)
                    session.perform("移除连线控制点") { model in
                        if let i = model.edges.firstIndex(where: { $0.id == edge.id }) {
                            model.edges[i].waypoints = controls.isEmpty ? nil : controls
                        }
                    }
                } else {
                    gesture = .waypoint(edge.id, index, controls, session.revision)
                }
                return
            }
            if controls.count < 128 {
                for (index, pair) in zip(route, route.dropFirst()).enumerated() {
                    let middle = Point(x: (pair.0.x + pair.1.x) / 2, y: (pair.0.y + pair.1.y) / 2)
                    if pair.0.distance(to: pair.1) > 28 / session.camera.scale,
                        middle.distance(to: p) < 9 / session.camera.scale
                    {
                        controls.insert(middle, at: index)
                        gesture = .waypoint(edge.id, index, controls, session.revision)
                        return
                    }
                }
            }
        }
        if let (id, source) = hitEndpoint(p) {
            session.selection = [id]
            gesture = .endpoint(id, source, session.revision)
            return
        }
        for panel in session.selectedPanels where !panel.isLocked {
            let f = panel.frame
            let corners = [
                Point(x: f.x, y: f.y), Point(x: f.maxX, y: f.y), Point(x: f.x, y: f.maxY), Point(x: f.maxX, y: f.maxY),
            ]
            if let corner = corners.firstIndex(where: { $0.distance(to: p) < 8 / session.camera.scale }) {
                gesture = .resizePanel(p, panel, corner, session.revision)
                return
            }
        }
        for node in session.selectedNodes where !session.diagram.isLocked(node) && !node.isHidden && node.groupID == nil
        {
            let f = node.frame
            let corners = [
                Point(x: f.x, y: f.y), Point(x: f.maxX, y: f.y), Point(x: f.x, y: f.maxY), Point(x: f.maxX, y: f.maxY),
            ]
            if let corner = corners.firstIndex(where: { $0.distance(to: p) < 8 / session.camera.scale }) {
                gesture = .resize(p, node, corner, session.revision)
                return
            }
        }
        if let edge = hitEdge(p) {
            session.selection = [edge]
        } else if let node = hitNode(p) {
            if event.clickCount == 2 {
                session.selection = [node.id]
                beginText(node)
                return
            }
            if event.modifierFlags.contains(.shift) {
                if session.selection.contains(node.id) {
                    session.selection.subtract(session.expandedSelection([node.id]))
                } else {
                    session.selection.insert(node.id)
                }
            } else if !session.selection.contains(node.id) {
                session.selection = [node.id]
            }
            beginMove(at: p)
        } else if let panel = session.diagram.panels.reversed().first(where: {
            !$0.isLocked && $0.frame.contains(p) && p.y < ($0.frame.y + 40)
        }) {
            if event.modifierFlags.contains(.shift) {
                if session.selection.contains(panel.id) {
                    session.selection.remove(panel.id)
                } else {
                    session.selection.insert(panel.id)
                }
            } else if !session.selection.contains(panel.id) {
                session.selection = [panel.id]
            }
            beginMove(at: p)
        } else {
            let previous = event.modifierFlags.contains(.shift) ? session.selection : []
            session.selection = previous
            gesture = .box(p, previous)
        }
    }
    private func beginMove(at p: Point) {
        let panels = session.selectedPanels.filter { !$0.isLocked }
        let ids = Set(panels.map(\.id))
        let nodes = session.diagram.nodes.filter {
            (session.selection.contains($0.id) && !session.diagram.isLocked($0))
                || ($0.panelID.map { ids.contains($0) } ?? false)
        }
        gesture = .move(
            p, Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0.frame) }),
            Dictionary(uniqueKeysWithValues: panels.map { ($0.id, $0.frame) }), session.revision)
    }
    public override func mouseDragged(with event: NSEvent) {
        let screen = local(event)
        let p = session.camera.world(screen)
        pointer = p
        guard let gesture else { return }
        switch gesture {
        case .waypoint(let id, let index, var controls, let revision):
            guard revision == session.revision, var edge = session.diagram.edges.first(where: { $0.id == id }) else {
                cancelGesture()
                return
            }
            let grid = session.diagram.gridSize
            controls[index] =
                session.snapToGrid
                ? Point(x: (p.x / grid).rounded() * grid, y: (p.y / grid).rounded() * grid) : p
            edge.waypoints = controls
            edgePreview = edge
        case .endpoint(let id, let source, let revision):
            guard revision == session.revision,
                let edge = session.diagram.edges.first(where: { $0.id == id })
            else {
                cancelGesture()
                return
            }
            if let (nodeID, anchor) = attachment(at: p), nodeID != (source ? edge.target : edge.source) {
                var updated = edge
                if source {
                    updated.source = nodeID
                    updated.sourceAnchor = anchor
                } else {
                    updated.target = nodeID
                    updated.targetAnchor = anchor
                }
                edgePreview = updated
                danglingEndpoint = nil
            } else {
                edgePreview = nil
                danglingEndpoint = p
            }
        case .pan(let start, let offset):
            session.camera.offset = offset.offset(x: screen.x - start.x, y: screen.y - start.y)
        case .move(let start, let frames, let panelFrames, let revision):
            guard revision == session.revision else {
                cancelGesture()
                return
            }
            var dx = p.x - start.x
            var dy = p.y - start.y
            if event.modifierFlags.contains(.shift) { if abs(dx) > abs(dy) { dy = 0 } else { dx = 0 } }
            if session.snapToGrid && !event.modifierFlags.contains(.option) {
                let gridSize = session.diagram.gridSize
                dx = (dx / gridSize).rounded() * gridSize
                dy = (dy / gridSize).rounded() * gridSize
            }
            if hypot(dx, dy) * session.camera.scale >= 3 {
                preview = frames.mapValues { Rect(x: $0.x + dx, y: $0.y + dy, width: $0.width, height: $0.height) }
                panelPreview = panelFrames.mapValues {
                    Rect(x: $0.x + dx, y: $0.y + dy, width: $0.width, height: $0.height)
                }
            } else {
                preview = [:]
                panelPreview = [:]
            }
        case .resize(let start, let node, let corner, let revision):
            guard revision == session.revision else {
                cancelGesture()
                return
            }
            let dx = p.x - start.x
            let dy = p.y - start.y
            var f = node.frame
            if corner == 0 || corner == 2 {
                f.width = max(node.kind.minimumWidth, node.frame.width - dx)
                f.x = node.frame.maxX - f.width
            } else {
                f.width = max(node.kind.minimumWidth, node.frame.width + dx)
            }
            if corner < 2 {
                f.height = max(node.kind.minimumHeight, node.frame.height - dy)
                f.y = node.frame.maxY - f.height
            } else {
                f.height = max(node.kind.minimumHeight, node.frame.height + dy)
            }
            if event.modifierFlags.contains(.shift) {
                f.height = max(node.kind.minimumHeight, f.width * node.frame.height / node.frame.width)
                if corner < 2 { f.y = node.frame.maxY - f.height }
            }
            preview = [node.id: f]
        case .resizePanel(let start, let panel, let corner, let revision):
            guard revision == session.revision else {
                cancelGesture()
                return
            }
            let dx = p.x - start.x
            let dy = p.y - start.y
            var f = panel.frame
            if corner == 0 || corner == 2 {
                f.width = max(160, panel.frame.width - dx)
                f.x = panel.frame.maxX - f.width
            } else {
                f.width = max(160, panel.frame.width + dx)
            }
            if corner < 2 {
                f.height = max(120, panel.frame.height - dy)
                f.y = panel.frame.maxY - f.height
            } else {
                f.height = max(120, panel.frame.height + dy)
            }
            panelPreview = [panel.id: f]
        case .box(let start, let previous):
            let r = Rect(
                x: min(start.x, p.x), y: min(start.y, p.y), width: abs(start.x - p.x), height: abs(start.y - p.y))
            marquee = r
            session.selection = previous.union(
                session.diagram.nodes.filter {
                    !$0.isHidden && !session.diagram.isLocked($0) && r.contains(Point(x: $0.frame.x, y: $0.frame.y))
                        && r.contains(Point(x: $0.frame.maxX, y: $0.frame.maxY))
                }.map(\.id))
        }
        needsDisplay = true
    }
    public override func mouseUp(with event: NSEvent) {
        if case .waypoint(let id, _, _, let revision) = gesture {
            if revision == session.revision, let updated = edgePreview {
                session.perform("调整连线路径") { model in
                    if let i = model.edges.firstIndex(where: { $0.id == id }) {
                        model.edges[i].waypoints = updated.waypoints
                    }
                }
            }
            cancelGesture()
            return
        }
        if case .endpoint(let id, let source, let revision) = gesture {
            let p = session.camera.world(local(event))
            if revision == session.revision,
                let original = session.diagram.edges.first(where: { $0.id == id }),
                let (nodeID, anchor) = attachment(at: p),
                nodeID != (source ? original.target : original.source)
            {
                session.perform("调整连接端点") { model in
                    guard let i = model.edges.firstIndex(where: { $0.id == id }) else { return }
                    if source {
                        model.edges[i].source = nodeID
                        model.edges[i].sourceAnchor = anchor
                    } else {
                        model.edges[i].target = nodeID
                        model.edges[i].targetAnchor = anchor
                    }
                }
            }
            cancelGesture()
            return
        }
        if !preview.isEmpty || !panelPreview.isEmpty {
            let frames = preview
            let panels = panelPreview
            let reparent: Bool
            if case .move = gesture { reparent = panels.isEmpty } else { reparent = false }
            session.perform("调整图形与 Panel") { model in
                for i in model.panels.indices { if let f = panels[model.panels[i].id] { model.panels[i].frame = f } }
                for i in model.edges.indices {
                    let edge = model.edges[i]
                    if let a = frames[edge.source], let b = frames[edge.target],
                        let oldA = model.nodes.first(where: { $0.id == edge.source })?.frame,
                        let oldB = model.nodes.first(where: { $0.id == edge.target })?.frame,
                        abs((a.x - oldA.x) - (b.x - oldB.x)) < 0.001,
                        abs((a.y - oldA.y) - (b.y - oldB.y)) < 0.001
                    {
                        model.edges[i].waypoints = edge.waypoints?.map { $0.offset(x: a.x - oldA.x, y: a.y - oldA.y) }
                    }
                }
                for i in model.nodes.indices {
                    if let f = frames[model.nodes[i].id] {
                        model.nodes[i].frame = f
                        if reparent {
                            model.nodes[i].panelID =
                                model.panels.last(where: { !$0.isLocked && $0.frame.contains(f.center) })?.id
                        }
                    }
                }
            }
        }
        cancelGesture()
    }
    private func cancelGesture() {
        preview = [:]
        panelPreview = [:]
        edgePreview = nil
        danglingEndpoint = nil
        gesture = nil
        marquee = nil
        needsDisplay = true
        NSCursor.arrow.set()
    }
    public override func scrollWheel(with event: NSEvent) {
        finishText(cancel: false)
        cancelGesture()
        if event.modifierFlags.contains(.command) {
            session.camera.zoom(to: session.camera.scale * exp(event.scrollingDeltaY * 0.01), at: local(event))
        } else {
            let multiplier = event.hasPreciseScrollingDeltas ? 1.0 : 12.0
            session.camera.offset.x += event.scrollingDeltaX * multiplier
            session.camera.offset.y += event.scrollingDeltaY * multiplier
        }
        needsDisplay = true
    }
    public override func magnify(with event: NSEvent) {
        finishText(cancel: false)
        cancelGesture()
        session.camera.zoom(to: session.camera.scale * (1 + event.magnification), at: local(event))
        needsDisplay = true
    }
    public func fitContent() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        guard let rect = session.diagram.contentBounds else {
            session.camera = Camera(offset: Point(x: bounds.width / 2, y: bounds.height / 2))
            return
        }
        let scale = min(
            1.1, max(0.05, min((bounds.width - 120) / max(1, rect.width), (bounds.height - 140) / max(1, rect.height))))
        session.camera = Camera(
            offset: Point(x: bounds.width / 2 - rect.center.x * scale, y: bounds.height / 2 - rect.center.y * scale),
            scale: scale)
    }
    public override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            connectionStart = nil
            cancelGesture()
            session.tool = .select
            return
        }
        if event.keyCode == 49 {
            isSpaceDown = true
            NSCursor.openHand.set()
            return
        }
        if event.modifierFlags.contains(.command) {
            if event.charactersIgnoringModifiers?.lowercased() == "g" {
                if event.modifierFlags.contains(.shift) { session.ungroupSelection() } else { session.groupSelection() }
                return
            }
            super.keyDown(with: event)
            return
        }
        let step = event.modifierFlags.contains(.shift) ? 10.0 : 1.0
        switch event.keyCode {
        case 51, 117: session.deleteSelection()
        case 123: session.moveSelection(dx: -step, dy: 0)
        case 124: session.moveSelection(dx: step, dy: 0)
        case 125: session.moveSelection(dx: 0, dy: step)
        case 126: session.moveSelection(dx: 0, dy: -step)
        case 36: if let node = session.selectedNodes.first, !session.diagram.isLocked(node) { beginText(node) }
        default:
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "v": session.tool = .select
            case "r": session.tool = .rounded
            case "o": session.tool = .ellipse
            case "d": session.tool = .diamond
            case "t": session.tool = .text
            case "l": session.tool = .connector
            case "h": session.tool = .hand
            case "p": session.tool = .panel
            default: super.keyDown(with: event)
            }
        }
    }
    public override func keyUp(with event: NSEvent) {
        if event.keyCode == 49 {
            isSpaceDown = false
            NSCursor.arrow.set()
        } else {
            super.keyUp(with: event)
        }
    }
    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: nil)
        if let window {
            NotificationCenter.default.addObserver(
                self, selector: #selector(windowLostFocus(_:)), name: NSWindow.didResignKeyNotification, object: window)
        }
    }
    @objc private func windowLostFocus(_ notification: Notification) {
        isSpaceDown = false
        cancelGesture()
        finishText(cancel: false)
    }
    deinit { NotificationCenter.default.removeObserver(self) }
    public override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            finishText(cancel: false)
            isSpaceDown = false
            cancelGesture()
        }
        super.viewWillMove(toWindow: newWindow)
    }
    private func beginText(_ node: DiagramNode) {
        let p = session.camera.screen(Point(x: node.frame.x, y: node.frame.y))
        let scale = session.camera.scale
        let text = CanvasTextView(
            frame: NSRect(
                x: p.x + 4, y: p.y + 4, width: max(60, node.frame.width * scale - 8),
                height: max(node.kind.minimumHeight, node.frame.height * scale - 8)))
        text.string = node.title
        text.font = NSFont.systemFont(ofSize: max(8, node.fontSize * scale), weight: .medium)
        text.alignment = .center
        text.isRichText = false
        text.allowsUndo = true
        text.backgroundColor = .white
        text.textColor = NSColor(hex: 0x27344F)
        text.isVerticallyResizable = false
        text.isHorizontallyResizable = false
        text.textContainerInset = NSSize(width: 4, height: 8)
        text.autoresizingMask = []
        text.delegate = self
        text.onResign = { [weak self] in self?.finishText(cancel: false) }
        editor = text
        editingID = node.id
        editingCamera = session.camera
        addSubview(text)
        window?.makeFirstResponder(text)
        text.selectAll(nil)
    }
    private func finishText(cancel: Bool) {
        guard !committing, let text = editor, let id = editingID else { return }
        committing = true
        let value = text.string
        editor = nil
        editingID = nil
        text.onResign = nil
        text.removeFromSuperview()
        if !cancel { session.updateNode(id, name: "编辑文字") { $0.title = value } }
        committing = false
        needsDisplay = true
    }
    public func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            finishText(cancel: true)
            window?.makeFirstResponder(self)
            return true
        }
        if commandSelector == #selector(NSResponder.insertNewline(_:)),
            NSApp.currentEvent?.modifierFlags.contains(.command) == true
        {
            finishText(cancel: false)
            window?.makeFirstResponder(self)
            return true
        }
        return false
    }
    @objc public override func selectAll(_ sender: Any?) {
        session.selection = Set(session.diagram.nodes.filter { !$0.isLocked && !$0.isHidden }.map(\.id))
    }
    @objc public func copy(_ sender: Any?) {
        let payload = session.selectionPayload()
        guard !payload.nodes.isEmpty || !payload.panels.isEmpty, let data = try? JSONEncoder().encode(payload) else {
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(data, forType: NSPasteboard.PasteboardType("com.forma.diagram-selection"))
        NSPasteboard.general.setString(payload.nodes.map(\.title).joined(separator: "\n"), forType: .string)
    }
    @objc public func cut(_ sender: Any?) {
        copy(sender)
        session.deleteSelection()
    }
    @objc public func paste(_ sender: Any?) {
        guard let data = NSPasteboard.general.data(forType: NSPasteboard.PasteboardType("com.forma.diagram-selection"))
        else {
            if let text = NSPasteboard.general.string(forType: .string), !text.isEmpty {
                guard text.count <= 100_000 else {
                    session.errorMessage = "粘贴的文字过长。"
                    return
                }
                let point = session.camera.world(Point(x: bounds.midX, y: bounds.midY))
                let node = DiagramNode(
                    title: text, kind: .text, frame: Rect(x: point.x - 120, y: point.y - 40, width: 240, height: 80))
                if session.perform("粘贴文字", { $0.nodes.append(node) }) { session.selection = [node.id] }
            }
            return
        }
        guard data.count <= 20_000_000 else {
            session.errorMessage = "剪贴板图形超出当前容量限制。"
            return
        }
        do {
            let source = try JSONDecoder().decode(Diagram.self, from: data).validated()
            session.paste(source, at: session.camera.world(Point(x: bounds.midX, y: bounds.midY)))
        } catch { session.errorMessage = error.localizedDescription }
    }
    @objc public func delete(_ sender: Any?) { session.deleteSelection() }
    @objc public func duplicate(_ sender: Any?) { session.duplicateSelection() }
    public func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(copy(_:)), #selector(cut(_:)), #selector(duplicate(_:)):
            return !session.selectedNodes.isEmpty || !session.selectedPanels.isEmpty
        case #selector(delete(_:)): return !session.selection.isEmpty
        case #selector(paste(_:)):
            return NSPasteboard.general.data(forType: NSPasteboard.PasteboardType("com.forma.diagram-selection")) != nil
                || NSPasteboard.general.string(forType: .string) != nil
        default: return true
        }
    }
    @objc private func groupNodes(_ sender: Any?) { session.groupSelection() }
    @objc private func ungroupNodes(_ sender: Any?) { session.ungroupSelection() }
    public override func menu(for event: NSEvent) -> NSMenu? {
        let p = session.camera.world(local(event))
        if let node = hitNode(p), !session.selection.contains(node.id) { session.selection = [node.id] }
        let menu = NSMenu()
        if session.canGroupSelection {
            menu.addItem(withTitle: tr("组合"), action: #selector(groupNodes(_:)), keyEquivalent: "")
        }
        if session.canUngroupSelection {
            menu.addItem(withTitle: tr("取消组合"), action: #selector(ungroupNodes(_:)), keyEquivalent: "")
        }
        menu.addItem(withTitle: tr("复制"), action: #selector(copy(_:)), keyEquivalent: "")
        menu.addItem(withTitle: tr("粘贴"), action: #selector(paste(_:)), keyEquivalent: "")
        menu.addItem(withTitle: tr("就地复制"), action: #selector(duplicate(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: tr("移入回收箱"), action: #selector(delete(_:)), keyEquivalent: "")
        return menu
    }
}

@MainActor private final class CanvasTextView: NSTextView {
    private let textUndoManager = UndoManager()
    var onResign: (() -> Void)?
    override var undoManager: UndoManager? { textUndoManager }
    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result { onResign?() }
        return result
    }
}
