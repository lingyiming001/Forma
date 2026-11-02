import FormaDomain
import FormaGeometry
import FormaLocalization
import Foundation
import Observation

public enum CanvasTool: String, CaseIterable, Sendable {
    case select, rounded, rectangle, ellipse, diamond, text, connector, hand, panel
    case arrowRight, triangle, hexagon, parallelogram, note
    case arrowUp, arrowDown, arrowLeft, terminator, document, cloud, star
    case venn, speech, funnel, octagon, pentagon, doubleArrow
    case cross, heart
    case predefinedProcess, manualInput, delay, display, multiDocument, card, tape, merge, collate, dataStore
    case umlClass, umlInterface, umlActor, umlUseCase, component, database, package
    case server, network, firewall, queue, gateway
    public var title: String {
        switch self {
        case .select: "选择"
        case .connector: "连接线"
        case .hand: "抓手"
        case .panel: "Panel 分区"
        default: shape?.title ?? rawValue
        }
    }
    public var symbol: String {
        switch self {
        case .select: "cursorarrow"
        case .connector: "arrow.up.right"
        case .hand: "hand.draw"
        case .panel: "rectangle.dashed"
        default: shape?.symbol ?? "square"
        }
    }
    public var shape: ShapeKind? { ShapeKind(rawValue: rawValue) }
}
public struct TemplateDescriptor: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let symbol: String
    public let category: String
    public init(id: String, title: String, subtitle: String, symbol: String, category: String = "基础") {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.category = category
    }
}

@MainActor @Observable public final class DocumentSession {
    public private(set) var pages: [Diagram]
    public private(set) var revision: UInt64 = 0
    public var activePageID: UUID
    public var selection: Set<UUID> = [] {
        didSet {
            let expanded = expandedSelection(selection)
            if expanded != selection { selection = expanded }
        }
    }
    public func expandedSelection(_ ids: Set<UUID>) -> Set<UUID> {
        let groups = Set(diagram.nodes.filter { ids.contains($0.id) }.compactMap(\.groupID))
        return ids.union(diagram.nodes.filter { $0.groupID.map { groups.contains($0) } ?? false }.map(\.id))
    }
    public var canGroupSelection: Bool {
        selectedNodes.count > 1 && selectedPanels.isEmpty && selectedNodes.allSatisfy { !diagram.isLocked($0) }
    }
    public var canUngroupSelection: Bool {
        selectedNodes.contains { $0.groupID != nil } && selectedNodes.allSatisfy { !diagram.isLocked($0) }
    }
    public func groupSelection() {
        guard canGroupSelection else { return }
        let ids = selection
        let group = UUID()
        perform("组合") { model in
            for i in model.nodes.indices where ids.contains(model.nodes[i].id) { model.nodes[i].groupID = group }
        }
    }
    public func ungroupSelection() {
        guard canUngroupSelection else { return }
        let ids = selection
        perform("取消组合") { model in
            for i in model.nodes.indices where ids.contains(model.nodes[i].id) { model.nodes[i].groupID = nil }
        }
    }
    public var tool: CanvasTool = .select
    public var camera = Camera()
    public var viewportSize = Point(x: 720, y: 640)
    public var showGrid = true
    public var snapToGrid = true
    public var showSidebar = true
    public var showInspector = true
    public var showDocumentTrash = false
    public var statusMessage: String?
    public var fitRequest = 0
    public var templates: [TemplateDescriptor] = []
    public var errorMessage: String?
    public var isProcessing = false
    @ObservationIgnored public var undoManager: UndoManager?
    @ObservationIgnored public var onChange: (() -> Void)?
    @ObservationIgnored public var onUndo: (() -> Void)?
    @ObservationIgnored public var onRedo: (() -> Void)?
    @ObservationIgnored public var exportAction: ((Bool) -> Void)?
    @ObservationIgnored public var templateAction: ((String) -> Void)?
    @ObservationIgnored public var settingsAction: (() -> Void)?
    @ObservationIgnored public var workspaceAction: (() -> Void)?
    @ObservationIgnored public var saveToWorkspaceAction: (() -> Void)?
    public init(diagram: Diagram = Diagram()) {
        pages = [diagram]
        activePageID = diagram.id
    }
    /// 当前活动页；全部编辑操作均作于当前页，页面增删改通过专用方法。
    public var diagram: Diagram {
        get { pages.first { $0.id == activePageID } ?? pages[0] }
        set {
            if let i = pages.firstIndex(where: { $0.id == activePageID }) {
                pages[i] = newValue
            } else if !pages.isEmpty {
                pages[0] = newValue
            }
        }
    }
    public var pageIndex: Int { (pages.firstIndex { $0.id == activePageID } ?? 0) + 1 }
    public var selectedNodes: [DiagramNode] { diagram.nodes.filter { selection.contains($0.id) } }
    public var selectedPanels: [DiagramPanel] { diagram.panels.filter { selection.contains($0.id) } }
    public var selectedEdge: DiagramEdge? { diagram.edges.first { selection.contains($0.id) } }
    public var screenCenter: Point { Point(x: viewportSize.x / 2, y: viewportSize.y / 2) }
    public func load(_ content: Diagram) { load(DiagramDocument(page: content)) }
    public func load(_ document: DiagramDocument) {
        var pages = document.pages
        if pages.isEmpty { pages = [Diagram()] }
        self.pages = pages
        activePageID = document.activePageID
        if !pages.contains(where: { $0.id == activePageID }) { activePageID = pages[0].id }
        selection = []
        revision &+= 1
        undoManager?.removeAllActions()
        fitRequest += 1
    }
    /// 快照覆盖全部页面与活动页，页面操作（新建/删除/改名）同样可撤销。
    private struct Snapshot {
        var pages: [Diagram]
        var activePageID: UUID
        var selection: Set<UUID>
    }
    @discardableResult public func perform(_ name: String, _ edit: (inout Diagram) throws -> Void) -> Bool {
        errorMessage = nil
        do {
            // pages 由 load/构造保证非空；活动页丢失时回退首页。
            let index = pages.firstIndex(where: { $0.id == activePageID }) ?? 0
            var updated = pages[index]
            try edit(&updated)
            updated = try updated.validated()
            guard updated != pages[index] else { return false }
            let previous = Snapshot(pages: pages, activePageID: activePageID, selection: selection)
            pages[index] = updated
            revision &+= 1
            selection.formIntersection(updated.elementIDs)
            onChange?()
            registerRestore(previous, name: name)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
    private func registerRestore(_ snapshot: Snapshot, name: String) {
        let explicitGroup =
            undoManager?.groupsByEvent == false && undoManager?.isUndoing == false && undoManager?.isRedoing == false
        if explicitGroup { undoManager?.beginUndoGrouping() }
        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated { target.restore(snapshot, name: name) }
        }
        undoManager?.setActionName(tr(name))
        if explicitGroup { undoManager?.endUndoGrouping() }
    }
    private func restore(_ snapshot: Snapshot, name: String) {
        let previous = Snapshot(pages: pages, activePageID: activePageID, selection: selection)
        let redoing = undoManager?.isRedoing == true
        pages = snapshot.pages
        activePageID = snapshot.activePageID
        revision &+= 1
        selection = snapshot.selection.intersection(currentElementIDs)
        if redoing { onRedo?() } else { onUndo?() }
        registerRestore(previous, name: name)
    }
    private var currentElementIDs: Set<UUID> { Set(pages.flatMap { $0.elementIDs }) }
    /// 页面级操作：快照／变更／验证后统一登记撤销，失败时保持原状。
    @discardableResult private func mutatePages(
        _ name: String,
        _ change: (inout [Diagram], inout UUID) ->
            Void
    ) -> Bool {
        errorMessage = nil
        do {
            var next = pages
            var nextActive = activePageID
            change(&next, &nextActive)
            var document = DiagramDocument(pages: next, activePageID: nextActive)
            document = try document.validated()
            let previous = Snapshot(pages: pages, activePageID: activePageID, selection: selection)
            pages = document.pages
            activePageID = document.activePageID
            revision &+= 1
            selection.formIntersection(diagram.elementIDs)
            onChange?()
            registerRestore(previous, name: name)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
    public func selectPage(_ id: UUID) {
        guard pages.contains(where: { $0.id == id }), id != activePageID else { return }
        activePageID = id
        selection = []
        revision &+= 1
        fitRequest += 1
    }
    @discardableResult public func addPage() -> Bool {
        guard pages.count < DiagramDocument.maximumPages else {
            errorMessage = DiagramError.pageLimitExceeded.localizedDescription
            return false
        }
        let page = Diagram(title: String(format: tr("页面 %d"), pages.count + 1))
        return mutatePages("添加页面") { list, active in
            if let index = list.firstIndex(where: { $0.id == active }) {
                list.insert(page, at: index + 1)
            } else {
                list.append(page)
            }
            active = page.id
        }
    }
    public func renamePage(_ id: UUID, title: String) {
        mutatePages("重命名页面") { list, _ in
            if let i = list.firstIndex(where: { $0.id == id }) { list[i].title = title }
        }
    }
    public func duplicatePage(_ id: UUID) {
        mutatePages("重复页面") { list, active in
            guard let i = list.firstIndex(where: { $0.id == id }) else { return }
            var copy = list[i]
            let remap = Dictionary(uniqueKeysWithValues: copy.elementIDs.map { ($0, UUID()) })
            copy.id = remap[list[i].id] ?? UUID()
            copy.title = list[i].title + tr(" 副本")
            let groups = Dictionary(uniqueKeysWithValues: Set(copy.nodes.compactMap(\.groupID)).map { ($0, UUID()) })
            copy.nodes = copy.nodes.map { n in
                var node = n
                node.id = remap[n.id] ?? node.id
                node.groupID = n.groupID.flatMap { groups[$0] }
                node.panelID = n.panelID.flatMap { remap[$0] }
                return node
            }
            copy.edges = copy.edges.map { e in
                var edge = e
                edge.id = remap[e.id] ?? e.id
                edge.source = remap[e.source] ?? e.source
                edge.target = remap[e.target] ?? e.target
                return edge
            }
            copy.panels = copy.panels.map { p in
                var panel = p
                panel.id = remap[p.id] ?? panel.id
                return panel
            }
            copy.recycleBin = copy.recycleBin.map { entry in
                var recycled = entry
                recycled.id = UUID()
                recycled.nodes = entry.nodes.map { n in
                    var node = n
                    node.id = remap[n.id] ?? node.id
                    node.groupID = n.groupID.flatMap { groups[$0] }
                    node.panelID = n.panelID.flatMap { remap[$0] }
                    return node
                }
                recycled.edges = entry.edges.map { e in
                    var edge = e
                    edge.id = remap[e.id] ?? e.id
                    edge.source = remap[e.source] ?? e.source
                    edge.target = remap[e.target] ?? e.target
                    return edge
                }
                recycled.panels = entry.panels.map { p in
                    var panel = p
                    panel.id = remap[p.id] ?? panel.id
                    return panel
                }
                return recycled
            }
            list.insert(copy, at: i + 1)
            active = copy.id
        }
    }
    public func movePage(_ id: UUID, left: Bool) {
        mutatePages(left ? "页面左移" : "页面右移") { list, _ in
            guard let i = list.firstIndex(where: { $0.id == id }) else { return }
            let j = left ? i - 1 : i + 1
            guard list.indices.contains(j) else { return }
            list.swapAt(i, j)
        }
    }
    public func deletePage(_ id: UUID) {
        guard pages.count > 1 else {
            errorMessage = DiagramError.lastPage.localizedDescription
            return
        }
        mutatePages("删除页面") { list, active in
            guard list.count > 1, let i = list.firstIndex(where: { $0.id == id }) else { return }
            list.remove(at: i)
            if active == id { active = list[max(0, i - 1)].id }
        }
    }
    public func add(_ kind: ShapeKind, at point: Point) {
        let arrowUpDown = kind == .arrowUp || kind == .arrowDown || kind == .doubleArrow
        let arrowHorizontal = kind == .arrowRight || kind == .arrowLeft
        let width =
            kind.isClass
            ? 240.0
            : kind == .umlActor
                ? 100
                : kind == .diamond
                    ? 140
                    : kind == .triangle
                        ? 120
                        : arrowUpDown
                            ? 120
                            : arrowHorizontal
                                ? 200
                                : kind == .star || kind == .octagon
                                    ? 140
                                    : kind == .pentagon || kind == .funnel
                                        ? 150 : kind == .venn ? 200 : kind == .speech ? 180 : 168
        let height =
            kind.isClass
            ? 190.0
            : kind == .umlActor
                ? 150
                : kind == .diamond
                    ? 100
                    : kind == .triangle
                        ? 120
                        : arrowUpDown
                            ? 180
                            : arrowHorizontal
                                ? 96
                                : kind == .star || kind == .octagon
                                    ? 140
                                    : kind == .pentagon || kind == .funnel
                                        ? 140 : kind == .venn ? 120 : kind == .speech ? 128 : 72
        let spacing = diagram.gridSize
        let p =
            snapToGrid
            ? Point(x: (point.x / spacing).rounded() * spacing, y: (point.y / spacing).rounded() * spacing)
            : point
        let node = DiagramNode(
            title: kind.isClass ? "NewClass" : kind == .text ? tr("双击编辑文字") : tr(kind.title), kind: kind,
            frame: Rect(x: p.x - width / 2, y: p.y - height / 2, width: width, height: height),
            panelID: diagram.panels.last(where: { !$0.isLocked && $0.frame.contains(p) })?.id,
            attributes: kind.isClass ? ["- id: UUID"] : nil, operations: kind.isClass ? ["+ execute(): void"] : nil)
        if perform("添加" + kind.title, { $0.nodes.append(node) }) {
            selection = [node.id]
            tool = .select
        }
    }
    public func addPanel(at point: Point) {
        let panel = DiagramPanel(
            title: "Panel \(diagram.panels.count+1)",
            frame: Rect(x: point.x - 280, y: point.y - 180, width: 560, height: 360))
        if perform("添加 Panel", { $0.panels.append(panel) }) {
            selection = [panel.id]
            tool = .select
        }
    }
    public func connect(from: UUID, to: UUID) {
        guard from != to, !diagram.edges.contains(where: { $0.source == from && $0.target == to }) else { return }
        let edge = DiagramEdge(source: from, target: to)
        if perform("添加连接线", { $0.edges.append(edge) }) { selection = [edge.id] }
    }
    public func deleteSelection() {
        let panels = diagram.panels.filter { selection.contains($0.id) && !$0.isLocked }
        let panelIDs = Set(panels.map(\.id))
        let nodes = diagram.nodes.filter {
            (selection.contains($0.id) && !diagram.isLocked($0)) || ($0.panelID.map { panelIDs.contains($0) } ?? false)
        }
        let nodeIDs = Set(nodes.map(\.id))
        let edges = diagram.edges.filter {
            selection.contains($0.id) || nodeIDs.contains($0.source) || nodeIDs.contains($0.target)
        }
        guard !panels.isEmpty || !nodes.isEmpty || !edges.isEmpty else { return }
        let edgeIDs = Set(edges.map(\.id))
        let entry = RecycledElements(
            title: panels.first?.title ?? nodes.first?.title ?? "连接线", nodes: nodes, edges: edges, panels: panels)
        perform("移入回收箱") {
            $0.panels.removeAll { panelIDs.contains($0.id) }
            $0.nodes.removeAll { nodeIDs.contains($0.id) }
            $0.edges.removeAll { edgeIDs.contains($0.id) }
            $0.recycleBin.append(entry)
        }
    }
    public func restoreRecycled(_ id: UUID? = nil) {
        let entries = diagram.recycleBin.filter { id == nil || $0.id == id }
        let ids = Set(entries.map(\.id))
        guard !entries.isEmpty else { return }
        perform("恢复回收内容") { model in
            model.nodes += entries.flatMap(\.nodes)
            model.edges += entries.flatMap(\.edges)
            model.panels += entries.flatMap(\.panels)
            model.recycleBin.removeAll { ids.contains($0.id) }
            do { _ = try model.validated() } catch { throw DiagramError.restoreDependency }
        }
    }
    public func selectionPayload() -> Diagram {
        let panels = selectedPanels
        let panelIDs = Set(panels.map(\.id))
        let nodes = diagram.nodes.filter {
            selection.contains($0.id) || ($0.panelID.map { panelIDs.contains($0) } ?? false)
        }.map { n in
            var copy = n
            if let id = copy.panelID, !panelIDs.contains(id) { copy.panelID = nil }
            return copy
        }
        let ids = Set(nodes.map(\.id))
        return Diagram(
            nodes: nodes, edges: diagram.edges.filter { ids.contains($0.source) && ids.contains($0.target) },
            panels: panels)
    }
    public func paste(_ source: Diagram, at point: Point) {
        do { _ = try source.validated() } catch {
            errorMessage = error.localizedDescription
            return
        }
        let ids = Dictionary(
            uniqueKeysWithValues: (source.nodes.map(\.id) + source.panels.map(\.id)).map { ($0, UUID()) })
        let center = source.contentBounds?.center ?? point
        let dx = point.x - center.x
        let dy = point.y - center.y
        let groups = Dictionary(uniqueKeysWithValues: Set(source.nodes.compactMap(\.groupID)).map { ($0, UUID()) })
        let nodes = source.nodes.map { n in
            var c = n
            c.id = ids[n.id]!
            c.groupID = n.groupID.flatMap { groups[$0] }
            c.panelID = n.panelID.flatMap { ids[$0] }
            c.frame.x += dx
            c.frame.y += dy
            return c
        }
        let panels = source.panels.map { p in
            var c = p
            c.id = ids[p.id]!
            c.frame.x += dx
            c.frame.y += dy
            return c
        }
        let edges = source.edges.compactMap { e -> DiagramEdge? in
            guard let a = ids[e.source], let b = ids[e.target] else { return nil }
            var edge = e
            edge.id = UUID()
            edge.source = a
            edge.target = b
            edge.waypoints = e.waypoints?.map { $0.offset(x: dx, y: dy) }
            return edge
        }
        if perform(
            "粘贴图形",
            {
                $0.nodes += nodes
                $0.edges += edges
                $0.panels += panels
            })
        {
            selection = Set(panels.isEmpty ? nodes.map(\.id) : panels.map(\.id))
        }
    }
    public func duplicateSelection() {
        let source = selectionPayload()
        guard let center = source.contentBounds?.center else { return }
        paste(source, at: center.offset(x: 24, y: 24))
    }
    public func updateNode(_ id: UUID, name: String, _ update: (inout DiagramNode) -> Void) {
        perform(name) { model in
            guard let index = model.nodes.firstIndex(where: { $0.id == id }) else { return }
            update(&model.nodes[index])
        }
    }
    public func updatePanel(_ id: UUID, name: String, _ update: (inout DiagramPanel) -> Void) {
        perform(name) { model in
            guard let i = model.panels.firstIndex(where: { $0.id == id }) else { return }
            let before = model.panels[i].frame
            update(&model.panels[i])
            let after = model.panels[i].frame
            for n in model.nodes.indices where model.nodes[n].panelID == id {
                model.nodes[n].frame.x += after.x - before.x
                model.nodes[n].frame.y += after.y - before.y
            }
        }
    }
    public func updateSelectedColor(_ color: DiagramColor) {
        let ids = selection
        perform("更改颜色") { model in
            for i in model.nodes.indices where ids.contains(model.nodes[i].id) && !model.isLocked(model.nodes[i]) {
                model.nodes[i].color = color
            }
            for i in model.panels.indices where ids.contains(model.panels[i].id) && !model.panels[i].isLocked {
                model.panels[i].color = color
            }
        }
    }
    public func moveSelection(dx: Double, dy: Double) {
        let ids = selection
        let panelIDs = Set(selectedPanels.filter { !$0.isLocked }.map(\.id))
        perform("移动图形") { model in
            let moving = Set(
                model.nodes.filter {
                    (ids.contains($0.id) && !model.isLocked($0)) || ($0.panelID.map { panelIDs.contains($0) } ?? false)
                }.map(\.id))
            for i in model.edges.indices
            where moving.contains(model.edges[i].source) && moving.contains(model.edges[i].target) {
                model.edges[i].waypoints = model.edges[i].waypoints?.map { $0.offset(x: dx, y: dy) }
            }
            for i in model.nodes.indices
            where (ids.contains(model.nodes[i].id) && !model.isLocked(model.nodes[i]))
                || (model.nodes[i].panelID.map { panelIDs.contains($0) } ?? false)
            {
                model.nodes[i].frame.x += dx
                model.nodes[i].frame.y += dy
            }
            for i in model.panels.indices where panelIDs.contains(model.panels[i].id) {
                model.panels[i].frame.x += dx
                model.panels[i].frame.y += dy
            }
        }
    }
    public func assignSelection(to panelID: UUID?) {
        let ids = selection
        perform("移动到 Panel") { model in
            let panel = model.panels.first { $0.id == panelID }
            guard panel?.isLocked != true else { return }
            for i in model.nodes.indices where ids.contains(model.nodes[i].id) && !model.isLocked(model.nodes[i]) {
                model.nodes[i].panelID = panelID
                if let panel, !panel.frame.contains(model.nodes[i].frame.center) {
                    model.nodes[i].frame.x = panel.frame.x + 24
                    model.nodes[i].frame.y = panel.frame.y + 56
                }
            }
        }
    }
    public func align(_ horizontal: Bool) {
        let nodes = selectedNodes.filter { !diagram.isLocked($0) }
        guard nodes.count > 1 else { return }
        let value = nodes.map { horizontal ? $0.frame.center.y : $0.frame.center.x }.reduce(0, +) / Double(nodes.count)
        let ids = Set(nodes.map(\.id))
        perform(horizontal ? "水平对齐" : "垂直对齐") { model in
            for i in model.nodes.indices where ids.contains(model.nodes[i].id) {
                if horizontal {
                    model.nodes[i].frame.y = value - model.nodes[i].frame.height / 2
                } else {
                    model.nodes[i].frame.x = value - model.nodes[i].frame.width / 2
                }
            }
        }
    }
}
