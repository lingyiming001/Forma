import AppKit
import CoreGraphics
import FormaApplication
import FormaCanvasEngine
import FormaCatalogInfrastructure
import FormaDocumentIO
import FormaDomain
import FormaGeometry
import FormaInterchange
import Foundation
import Testing

struct GeometryTests {
    @Test func cameraKeepsPointerAnchor() {
        var camera = Camera(offset: Point(x: 123, y: -88), scale: 0.7)
        let screen = Point(x: 310, y: 212)
        let before = camera.world(screen)
        camera.zoom(to: 3.1, at: screen)
        #expect(abs(camera.world(screen).x - before.x) < 0.00001)
        #expect(abs(camera.world(screen).y - before.y) < 0.00001)
        #expect(camera.screen(camera.world(screen)).distance(to: screen) < 0.00001)
    }
    @Test func preciseShapeHitTest() {
        let rect = Rect(x: 0, y: 0, width: 100, height: 100)
        for kind in [ShapeKind.ellipse, .diamond] {
            let node = DiagramNode(title: "节点", kind: kind, frame: rect)
            #expect(node.contains(Point(x: 50, y: 50)))
            #expect(!node.contains(Point(x: 1, y: 1)))
        }
    }
    @Test func connectionFollowsMovedNode() {
        let a = DiagramNode(title: "A", frame: Rect(x: 0, y: 0, width: 100, height: 60))
        var b = DiagramNode(title: "B", frame: Rect(x: 300, y: 0, width: 100, height: 60))
        let edge = DiagramEdge(source: a.id, target: b.id)
        let initial = ConnectionGeometry.points(for: edge, nodes: [a.id: a, b.id: b])
        b.frame.x += 80
        let moved = ConnectionGeometry.points(for: edge, nodes: [a.id: a, b.id: b])
        #expect(moved.last!.x == initial.last!.x + 80)
        #expect(ConnectionGeometry.distance(Point(x: 4, y: 3), to: Point(), Point(x: 10, y: 0)) == 3)
    }
    @Test func draggedEndpointSnapsAndFollowsTarget() throws {
        let a = DiagramNode(title: "A", frame: Rect(x: 0, y: 0, width: 100, height: 60))
        var b = DiagramNode(title: "B", frame: Rect(x: 250, y: 200, width: 160, height: 80))
        let anchor = ConnectionGeometry.nearestAnchor(
            on: b, to: Point(x: 330 + 4, y: 201), snapDistance: 12)
        #expect(anchor == EdgeAnchor(side: .top, position: 0.5))
        let edge = DiagramEdge(source: a.id, target: b.id, targetAnchor: anchor)
        let original = ConnectionGeometry.points(for: edge, nodes: [a.id: a, b.id: b])
        #expect(original.last == Point(x: 330, y: 200))
        #expect(original[original.count - 2] == Point(x: 330, y: 180))
        b.frame.x += 40
        b.frame.y += 30
        let moved = ConnectionGeometry.points(for: edge, nodes: [a.id: a, b.id: b])
        #expect(moved.last == Point(x: 370, y: 230))
        let model = try Diagram(nodes: [a, b], edges: [edge]).validated()
        let decoded = try DocumentCodec.decode(DocumentCodec.encode(model))
        #expect(decoded.pages[0].edges[0].targetAnchor == anchor)
    }
}

struct DocumentTests {
    @Test(arguments: DiagramTemplate.allCases) func templatesAreValid(_ template: DiagramTemplate) throws {
        _ = try template.makeDiagram().validated()
    }
    @Test func roundTripPreservesUnicodeAndConnections() throws {
        var source = DiagramTemplate.architecture.makeDiagram()
        source.nodes[0].title = "支付系统 👩‍💻\n订单与账户"
        let decoded = try DocumentCodec.decode(DocumentCodec.encode(source))
        #expect(decoded.pages[0] == source)
    }
    @Test func unknownVersionRejectedWithoutChangingData() throws {
        let model = DiagramTemplate.mindmap.makeDiagram()
        let wrapper = try DocumentCodec.encode(model)
        let manifest = try JSONEncoder().encode(
            DocumentManifest(documentID: model.id, formatVersion: 99, minimumReaderVersion: 99))
        wrapper.removeFileWrapper(wrapper.fileWrappers!["manifest.json"]!)
        let replacement = FileWrapper(regularFileWithContents: manifest)
        replacement.preferredFilename = "manifest.json"
        wrapper.addFileWrapper(replacement)
        #expect(throws: DiagramError.self) { try DocumentCodec.decode(wrapper) }
    }
    @Test func packageReadRejectsSymbolicLink() throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let folder = root.appendingPathComponent(".agents/test/file-safety-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let document = folder.appendingPathComponent("sample.forma")
        try DocumentCodec.encode(DiagramTemplate.architecture.makeDiagram()).write(
            to: document, options: .atomic, originalContentsURL: nil)
        #expect(try DocumentCodec.read(at: document).pages[0].nodes.count == 8)
        let manifest = document.appendingPathComponent("manifest.json")
        let outside = folder.appendingPathComponent("outside.json")
        try FileManager.default.moveItem(at: manifest, to: outside)
        try FileManager.default.createSymbolicLink(at: manifest, withDestinationURL: outside)
        #expect(throws: DiagramError.self) { try DocumentCodec.read(at: document) }
        try FileManager.default.removeItem(at: folder)
    }
    @Test func invalidReferencesAndDuplicateIDsRejected() {
        var model = DiagramTemplate.mindmap.makeDiagram()
        model.edges[0].target = UUID()
        #expect(throws: DiagramError.self) { try model.validated() }
        model = DiagramTemplate.mindmap.makeDiagram()
        model.nodes.append(model.nodes[0])
        #expect(throws: DiagramError.self) { try model.validated() }
    }
    @Test func nonFiniteGeometryRejected() {
        var model = DiagramTemplate.mindmap.makeDiagram()
        model.nodes[0].frame.x = .nan
        #expect(throws: DiagramError.self) { try model.validated() }
    }
    @Test func forestLayoutAndCycleRejection() throws {
        let model = DiagramTemplate.mindmap.makeDiagram()
        let frames = try TreeLayout.apply(to: model)
        #expect(frames.count == model.nodes.count)
        var cycle = model
        cycle.edges.append(DiagramEdge(source: model.nodes[1].id, target: model.nodes[0].id))
        #expect(throws: DiagramError.self) { try TreeLayout.apply(to: cycle) }
    }
    @Test func largeForestLayoutCompletesAtSupportedLimit() throws {
        var nodes: [DiagramNode] = []
        var edges: [DiagramEdge] = []
        nodes.reserveCapacity(2_000)
        edges.reserveCapacity(1_999)
        for index in 0..<2_000 {
            let node = DiagramNode(
                title: "N\(index)", frame: Rect(x: 0, y: 0, width: 120, height: 56))
            if let previous = nodes.last { edges.append(DiagramEdge(source: previous.id, target: node.id)) }
            nodes.append(node)
        }
        let frames = try TreeLayout.apply(to: Diagram(nodes: nodes, edges: edges))
        #expect(frames.count == 2_000)
        #expect(frames[nodes.last!.id]?.x ?? 0 > frames[nodes.first!.id]?.x ?? 0)
    }
}

struct ExportConcurrencyTests {
    @Test func exportRunsFromBackgroundExecutor() async throws {
        let model = DiagramTemplate.architecture.makeDiagram()
        let signatures = try await Task.detached {
            let pdf = try DiagramExporter.pdf(model)
            let png = try DiagramExporter.png(model, scale: 1)
            return (String(data: pdf.prefix(4), encoding: .ascii), Data(png.prefix(4)))
        }.value
        #expect(signatures.0 == "%PDF")
        #expect(signatures.1 == Data([137, 80, 78, 71]))
    }
}

@MainActor struct EditingTests {
    private func session() -> DocumentSession {
        let session = DocumentSession(diagram: DiagramTemplate.mindmap.makeDiagram())
        let undo = UndoManager()
        undo.groupsByEvent = false
        session.undoManager = undo
        return session
    }
    @Test func deleteAndUndoRestoreAssociatedEdgesAtomically() {
        let s = session()
        let before = s.diagram
        let root = before.nodes[0]
        s.selection = [root.id]
        s.deleteSelection()
        #expect(s.diagram.edges.isEmpty)
        #expect(s.diagram.nodes.count == before.nodes.count - 1)
        s.undoManager?.undo()
        #expect(s.diagram == before)
        s.undoManager?.redo()
        #expect(s.diagram.edges.isEmpty)
    }
    @Test func duplicateRemapsInternalConnections() {
        let s = session()
        let before = s.diagram
        s.selection = Set(before.nodes.map(\.id))
        s.duplicateSelection()
        #expect(s.diagram.nodes.count == before.nodes.count * 2)
        #expect(s.diagram.edges.count == before.edges.count * 2)
        let originalIDs = Set(before.nodes.map(\.id))
        let copies = s.diagram.nodes.filter { !originalIDs.contains($0.id) }
        let copyIDs = Set(copies.map(\.id))
        #expect(
            s.diagram.edges.suffix(before.edges.count).allSatisfy {
                copyIDs.contains($0.source) && copyIDs.contains($0.target)
            })
        s.undoManager?.undo()
        #expect(s.diagram == before)
    }
    @Test func invalidEditDoesNotMutateOrRegisterHistory() {
        let s = session()
        let before = s.diagram
        s.perform("无效编辑") { $0.nodes[0].frame.width = -1 }
        #expect(s.diagram == before)
        #expect(!s.undoManager!.canUndo)
        #expect(s.errorMessage != nil)
    }
    @Test func newEditInvalidatesRedoAndRevisionNeverRewinds() {
        let s = session()
        s.selection = [s.diagram.nodes[0].id]
        s.moveSelection(dx: 8, dy: 0)
        let revision = s.revision
        s.undoManager?.undo()
        #expect(s.revision > revision)
        #expect(s.undoManager!.canRedo)
        s.moveSelection(dx: 16, dy: 0)
        #expect(!s.undoManager!.canRedo)
    }
    @Test func lockedNodesCannotBeMovedOrDeleted() {
        let s = session()
        let id = s.diagram.nodes[0].id
        s.updateNode(id, name: "锁定") { $0.isLocked = true }
        let before = s.diagram
        s.selection = [id]
        s.moveSelection(dx: 80, dy: 80)
        s.deleteSelection()
        #expect(s.diagram == before)
    }
    @Test func exportsHaveValidStructureAndPNGDimensions() throws {
        let model = DiagramTemplate.architecture.makeDiagram()
        let pdf = try DiagramExporter.pdf(model)
        let png = try DiagramExporter.png(model)
        #expect(String(data: pdf.prefix(4), encoding: .ascii) == "%PDF")
        let provider = try #require(CGDataProvider(data: pdf as CFData))
        let document = try #require(CGPDFDocument(provider))
        #expect(document.numberOfPages == 1)
        let image = try #require(NSBitmapImageRep(data: png))
        #expect(image.pixelsWide > 1000)
        #expect(image.pixelsHigh > 300)
        #expect(png.prefix(4) == Data([137, 80, 78, 71]))
    }
}

struct ShapeAndLineTests {
    @Test(arguments: ShapeKind.allCases) func allShapesRoundTripAndValidate(_ kind: ShapeKind) throws {
        #expect(["基础图形", "流程图", "箭头", "UML 与企业架构"].contains(kind.category))
        let node = DiagramNode(
            title: "形状", kind: kind,
            frame: Rect(x: 0, y: 0, width: max(160, kind.minimumWidth), height: max(80, kind.minimumHeight)))
        let model = try Diagram(nodes: [node]).validated()
        let decoded = try DocumentCodec.decode(DocumentCodec.encode(model))
        #expect(decoded.pages[0].nodes == [node])
    }
    @Test func edgeLineDefaultsDeriveFromRelation() {
        // 未显式设置时，线型/箭头由 UMLRelation 推导，保持旧行为。
        #expect(DiagramEdge(source: UUID(), target: UUID()).effectiveLineStyle == .solid)
        #expect(DiagramEdge(source: UUID(), target: UUID()).effectiveArrow == .single)
        #expect(
            DiagramEdge(source: UUID(), target: UUID(), relation: .dependency).effectiveLineStyle == .dashed)
        #expect(
            DiagramEdge(source: UUID(), target: UUID(), relation: .association).effectiveArrow == .none)
    }
    @Test func explicitLineStyleAndArrowRoundTrip() throws {
        let a = DiagramNode(title: "A", frame: Rect(x: 0, y: 0, width: 120, height: 60))
        let b = DiagramNode(title: "B", frame: Rect(x: 300, y: 0, width: 120, height: 60))
        let edge = DiagramEdge(
            source: a.id, target: b.id, lineStyle: .dotted, arrow: .double)
        let model = try Diagram(nodes: [a, b], edges: [edge]).validated()
        let decoded = try DocumentCodec.decode(DocumentCodec.encode(model))
        let restored = try #require(decoded.pages[0].edges.first)
        #expect(restored.lineStyle == .dotted)
        #expect(restored.arrow == .double)
        #expect(restored.effectiveLineStyle.dashPattern == [2, 4])
    }
    @Test func legacyEdgeWithoutLineFieldsDecodes() throws {
        // 旧文件（边无 lineStyle/arrow/relation 键）应解码为 nil 并保持关系推导的默认外观。
        let a = UUID(), b = UUID()
        func node(_ id: UUID, _ title: String, _ x: Double) -> String {
            "{\"id\":\"\(id.uuidString)\",\"title\":\"\(title)\",\"kind\":\"rounded\","
                + "\"frame\":{\"x\":\(x),\"y\":0,\"width\":120,\"height\":60},"
                + "\"color\":\"blue\",\"fontSize\":14,\"isHidden\":false,\"isLocked\":false}"
        }
        let json =
            "{\"id\":\"\(UUID().uuidString)\",\"title\":\"旧\","
            + "\"nodes\":[\(node(a, "A", 0)),\(node(b, "B", 300))],"
            + "\"edges\":[{\"id\":\"\(UUID().uuidString)\",\"source\":\"\(a.uuidString)\","
            + "\"target\":\"\(b.uuidString)\",\"label\":\"\"}],\"panels\":[],\"recycleBin\":[]}"
        let diagram = try JSONDecoder().decode(Diagram.self, from: Data(json.utf8))
        let edge = try #require(diagram.edges.first)
        #expect(edge.lineStyle == nil && edge.arrow == nil)
        #expect(edge.sourceAnchor == nil && edge.targetAnchor == nil)
        #expect(edge.effectiveLineStyle == .solid && edge.effectiveArrow == .single)
    }
}
