import FormaGeometry
import Foundation

public enum ShapeKind: String, Codable, CaseIterable, Sendable {
    case rounded, rectangle, ellipse, diamond, text
    case arrowRight, triangle, hexagon, parallelogram, note
    case arrowUp, arrowDown, arrowLeft, terminator, document, cloud, star
    case venn, speech, funnel, octagon, pentagon, doubleArrow
    case cross, heart
    case predefinedProcess, manualInput, delay, display, multiDocument, card, tape, merge, collate, dataStore
    case umlClass, umlInterface, umlActor, umlUseCase, component, database, package
    case server, network, firewall, queue, gateway
    public var title: String {
        switch self {
        case .rounded: "圆角矩形"
        case .rectangle: "矩形"
        case .ellipse: "椭圆"
        case .diamond: "判断"
        case .text: "文本"
        case .arrowRight: "箭头"
        case .triangle: "三角形"
        case .hexagon: "六边形"
        case .parallelogram: "平行四边形"
        case .note: "注释"
        case .arrowUp: "向上箭头"
        case .arrowDown: "向下箭头"
        case .arrowLeft: "向左箭头"
        case .terminator: "端点"
        case .document: "文档"
        case .cloud: "云"
        case .star: "五角星"
        case .venn: "维恩图"
        case .speech: "对话气泡"
        case .funnel: "漏斗"
        case .octagon: "八边形"
        case .pentagon: "五边形"
        case .doubleArrow: "双向箭头"
        case .cross: "十字形"
        case .heart: "心形"
        case .predefinedProcess: "预定义流程"
        case .manualInput: "手动输入"
        case .delay: "延迟"
        case .display: "显示"
        case .multiDocument: "多文档"
        case .card: "卡片"
        case .tape: "磁带"
        case .merge: "合并"
        case .collate: "整理"
        case .dataStore: "数据存储"
        case .umlClass: "UML 类"
        case .umlInterface: "UML 接口"
        case .umlActor: "参与者"
        case .umlUseCase: "用例"
        case .component: "组件"
        case .database: "数据库"
        case .package: "包"
        case .server: "服务器"
        case .network: "网络"
        case .firewall: "防火墙"
        case .queue: "消息队列"
        case .gateway: "网关"
        }
    }
    public var symbol: String {
        switch self {
        case .rounded: "rectangle"
        case .rectangle: "rectangle"
        case .ellipse, .umlUseCase: "oval"
        case .diamond: "diamond"
        case .text: "textformat"
        case .arrowRight: "arrow.right"
        case .triangle: "triangle"
        case .hexagon: "hexagon"
        case .parallelogram: "rectangle"
        case .note: "note.text"
        case .arrowUp: "arrow.up"
        case .arrowDown: "arrow.down"
        case .arrowLeft: "arrow.left"
        case .terminator: "capsule.portrait"
        case .document: "doc"
        case .cloud: "cloud"
        case .star: "star"
        case .venn: "circle.grid.2x1.fill"
        case .speech: "bubble.left"
        case .funnel: "line.3.horizontal.decrease"
        case .octagon: "octagon"
        case .pentagon: "pentagon"
        case .doubleArrow: "arrow.up.arrow.down"
        case .cross: "plus"
        case .heart: "heart"
        case .predefinedProcess: "rectangle.split.3x1"
        case .manualInput: "rectangle"
        case .delay: "capsule.lefthalf.filled"
        case .display: "rectangle"
        case .multiDocument: "doc.on.doc"
        case .card: "creditcard"
        case .tape: "waveform.path"
        case .merge: "triangle"
        case .collate: "hourglass"
        case .dataStore: "cylinder"
        case .umlClass: "rectangle.split.3x1"
        case .umlInterface: "curlybraces"
        case .umlActor: "figure.stand"
        case .component: "shippingbox"
        case .database: "externaldrive"
        case .package: "folder"
        case .server: "server.rack"
        case .network: "network"
        case .firewall: "shield"
        case .queue: "tray.2"
        case .gateway: "arrow.triangle.branch"
        }
    }
    public var minimumWidth: Double { isClass ? 160 : self == .umlActor ? 72 : 24 }
    public var minimumHeight: Double { isClass ? 140 : self == .umlActor ? 144 : 24 }
    public var isClass: Bool { self == .umlClass || self == .umlInterface }
    public var category: String {
        if [.arrowRight, .arrowUp, .arrowDown, .arrowLeft, .doubleArrow].contains(self) { return "箭头" }
        if [
            .diamond, .parallelogram, .terminator, .document, .predefinedProcess, .manualInput, .delay, .display,
            .multiDocument, .card, .tape, .merge, .collate, .dataStore,
        ].contains(self) {
            return "流程图"
        }
        if [
            .rounded, .rectangle, .ellipse, .text, .triangle, .hexagon, .note, .cloud, .star, .venn, .speech,
            .funnel, .octagon, .pentagon, .cross, .heart,
        ].contains(self) {
            return "基础图形"
        }
        return "UML 与企业架构"
    }
}

public enum UMLRelation: String, Codable, CaseIterable, Sendable {
    case directed, association, generalization, realization, dependency, aggregation, composition
    public var title: String {
        switch self {
        case .directed: "有向连接"
        case .association: "关联"
        case .generalization: "泛化 / 继承"
        case .realization: "实现"
        case .dependency: "依赖"
        case .aggregation: "聚合"
        case .composition: "组合"
        }
    }
    public var isDashed: Bool { self == .dependency || self == .realization }
}

/// 连接线线型：未显式设置时由 UMLRelation 推导，保持旧行为。
public enum LineStyle: String, Codable, CaseIterable, Sendable {
    case solid, dashed, dotted, dashDot
    public var title: String {
        switch self {
        case .solid: "实线"
        case .dashed: "虚线"
        case .dotted: "点线"
        case .dashDot: "点划线"
        }
    }
    public var dashPattern: [Double] {
        switch self {
        case .solid: []
        case .dashed: [7, 5]
        case .dotted: [2, 4]
        case .dashDot: [8, 4, 2, 4]
        }
    }
}

/// 连接线箭头端点：未显式设置时由 UMLRelation 决定箭头样式。
public enum ArrowStyle: String, Codable, CaseIterable, Sendable {
    case none, single, double
    public var title: String {
        switch self {
        case .none: "无箭头"
        case .single: "单箭头"
        case .double: "双箭头"
        }
    }
}

/// Each endpoint can override the legacy arrow / UML relation independently.
public enum EndpointMarker: String, Codable, CaseIterable, Sendable {
    case automatic, none, openArrow, filledTriangle, hollowTriangle, filledDiamond, hollowDiamond, circle
    public var title: String {
        switch self {
        case .automatic: "自动（跟随关系）"
        case .none: "无箭头"
        case .openArrow: "开放箭头"
        case .filledTriangle: "实心三角"
        case .hollowTriangle: "空心三角"
        case .filledDiamond: "实心菱形"
        case .hollowDiamond: "空心菱形"
        case .circle: "空心圆"
        }
    }
}

public struct DiagramPanel: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var frame: Rect
    public var color: DiagramColor
    public var isLocked: Bool
    public init(
        id: UUID = UUID(), title: String = "新建 Panel", frame: Rect, color: DiagramColor = .blue, isLocked: Bool = false
    ) {
        self.id = id
        self.title = title
        self.frame = frame
        self.color = color
        self.isLocked = isLocked
    }
}

public struct RecycledElements: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var deletedAt: Date
    public var nodes: [DiagramNode]
    public var edges: [DiagramEdge]
    public var panels: [DiagramPanel]
    public init(title: String, nodes: [DiagramNode], edges: [DiagramEdge], panels: [DiagramPanel]) {
        self.id = UUID()
        self.title = title
        self.deletedAt = Date()
        self.nodes = nodes
        self.edges = edges
        self.panels = panels
    }
}

public enum DiagramColor: String, Codable, CaseIterable, Sendable {
    case blue, violet, mint, peach, rose, neutral
    public var title: String {
        switch self {
        case .blue: "蓝色"
        case .violet: "紫色"
        case .mint: "薄荷"
        case .peach: "杏色"
        case .rose: "玫瑰"
        case .neutral: "中性"
        }
    }
    public var fillHex: UInt32 {
        switch self {
        case .blue: 0xF4F7FC
        case .violet: 0xF7F5FC
        case .mint: 0xF2F9F6
        case .peach: 0xFCF7F0
        case .rose: 0xFCF4F6
        case .neutral: 0xF7F8FA
        }
    }
    public var strokeHex: UInt32 {
        switch self {
        case .blue: 0xA8BBD8
        case .violet: 0xBEB1D8
        case .mint: 0xA0C5B5
        case .peach: 0xD5BE9E
        case .rose: 0xD5ADBB
        case .neutral: 0xC5CBD4
        }
    }
}

public enum DiagramTextAlignment: String, Codable, CaseIterable, Sendable {
    case leading, center, trailing
    public var title: String {
        switch self {
        case .leading: "左对齐"
        case .center: "居中"
        case .trailing: "右对齐"
        }
    }
}

public struct DiagramNode: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var kind: ShapeKind
    public var frame: Rect
    public var color: DiagramColor
    public var fontSize: Double
    public var isHidden: Bool
    public var isLocked: Bool
    public var panelID: UUID?
    public var groupID: UUID?
    public var attributes: [String]?
    public var operations: [String]?
    public var stereotype: String?
    /// Optional fields preserve source compatibility with documents created before style controls existed.
    public var strokeWidth: Double?
    public var opacity: Double?
    public var cornerRadius: Double?
    public var textAlignment: DiagramTextAlignment?
    public var effectiveStrokeWidth: Double { strokeWidth ?? 1.2 }
    public var effectiveOpacity: Double { opacity ?? 1 }
    public var effectiveCornerRadius: Double { cornerRadius ?? 8 }
    public var effectiveTextAlignment: DiagramTextAlignment { textAlignment ?? .center }
    public init(
        id: UUID = UUID(), title: String, kind: ShapeKind = .rounded, frame: Rect,
        color: DiagramColor = .blue, fontSize: Double = 14, isHidden: Bool = false, isLocked: Bool = false,
        panelID: UUID? = nil, attributes: [String]? = nil, operations: [String]? = nil, stereotype: String? = nil,
        strokeWidth: Double? = nil, opacity: Double? = nil, cornerRadius: Double? = nil,
        textAlignment: DiagramTextAlignment? = nil
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.frame = frame
        self.color = color
        self.fontSize = fontSize
        self.isHidden = isHidden
        self.isLocked = isLocked
        self.panelID = panelID
        self.attributes = attributes
        self.operations = operations
        self.stereotype = stereotype
        self.strokeWidth = strokeWidth
        self.opacity = opacity
        self.cornerRadius = cornerRadius
        self.textAlignment = textAlignment
    }
    public func contains(_ point: Point) -> Bool {
        guard frame.contains(point) else { return false }
        let dx = (point.x - frame.center.x) / (frame.width / 2)
        let dy = (point.y - frame.center.y) / (frame.height / 2)
        switch kind {
        case .ellipse, .umlUseCase: return dx * dx + dy * dy <= 1
        case .diamond: return abs(dx) + abs(dy) <= 1
        default: return true
        }
    }
    public func anchor(toward p: Point) -> Point {
        let c = frame.center
        let dx = p.x - c.x
        let dy = p.y - c.y
        guard dx != 0 || dy != 0 else { return Point(x: frame.maxX, y: c.y) }
        let rx = frame.width / 2
        let ry = frame.height / 2
        let t: Double
        switch kind {
        case .ellipse, .umlUseCase: t = 1 / sqrt(dx * dx / (rx * rx) + dy * dy / (ry * ry))
        case .diamond: t = 1 / (abs(dx) / rx + abs(dy) / ry)
        default: t = min(dx == 0 ? .infinity : rx / abs(dx), dy == 0 ? .infinity : ry / abs(dy))
        }
        return Point(x: c.x + dx * t, y: c.y + dy * t)
    }
}

public struct EdgeAnchor: Codable, Equatable, Sendable {
    public enum Side: String, Codable, Sendable { case top, right, bottom, left }
    public var side: Side
    /// 边上的相对位置，0 为左端或上端，1 为右端或下端。
    public var position: Double
    public init(side: Side, position: Double = 0.5) {
        self.side = side
        self.position = position
    }
    public var isValid: Bool { position.isFinite && (0...1).contains(position) }
}

public struct DiagramEdge: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var source: UUID
    public var target: UUID
    public var label: String
    public var relation: UMLRelation?
    public var lineStyle: LineStyle?
    public var arrow: ArrowStyle?
    public var sourceMarker: EndpointMarker?
    public var targetMarker: EndpointMarker?
    public var sourceAnchor: EdgeAnchor?
    public var targetAnchor: EdgeAnchor?
    public var waypoints: [Point]?
    public var effectiveRelation: UMLRelation { relation ?? .directed }
    public var effectiveLineStyle: LineStyle { lineStyle ?? (effectiveRelation.isDashed ? .dashed : .solid) }
    public var effectiveArrow: ArrowStyle { arrow ?? (effectiveRelation == .association ? .none : .single) }
    public var effectiveSourceMarker: EndpointMarker {
        if let sourceMarker, sourceMarker != .automatic { return sourceMarker }
        if let arrow { return arrow == .double ? .filledTriangle : .none }
        switch effectiveRelation {
        case .aggregation: return .hollowDiamond
        case .composition: return .filledDiamond
        default: return .none
        }
    }
    public var effectiveTargetMarker: EndpointMarker {
        if let targetMarker, targetMarker != .automatic { return targetMarker }
        if let arrow { return arrow == .none ? .none : .filledTriangle }
        switch effectiveRelation {
        case .directed: return .filledTriangle
        case .dependency: return .openArrow
        case .generalization, .realization: return .hollowTriangle
        default: return .none
        }
    }
    public init(
        id: UUID = UUID(), source: UUID, target: UUID, label: String = "", relation: UMLRelation? = nil,
        lineStyle: LineStyle? = nil, arrow: ArrowStyle? = nil,
        sourceAnchor: EdgeAnchor? = nil, targetAnchor: EdgeAnchor? = nil,
        sourceMarker: EndpointMarker? = nil, targetMarker: EndpointMarker? = nil, waypoints: [Point]? = nil
    ) {
        self.id = id
        self.source = source
        self.target = target
        self.label = label
        self.relation = relation
        self.lineStyle = lineStyle
        self.arrow = arrow
        self.sourceMarker = sourceMarker
        self.targetMarker = targetMarker
        self.sourceAnchor = sourceAnchor
        self.targetAnchor = targetAnchor
        self.waypoints = waypoints
    }
}

public enum CanvasBackgroundStyle: String, Codable, CaseIterable, Sendable {
    case system, white, warm, cool, sand, mint, lavender, graphite
    public var title: String {
        switch self {
        case .system: "跟随系统"
        case .white: "纯白"
        case .warm: "暖白"
        case .cool: "冷灰"
        case .sand: "沙色"
        case .mint: "薄荷"
        case .lavender: "薰衣草"
        case .graphite: "石墨"
        }
    }
}

public enum CanvasGridStyle: String, Codable, CaseIterable, Sendable {
    case lines, dots
    public var title: String { self == .lines ? "线框" : "点阵" }
}

public struct Diagram: Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var nodes: [DiagramNode]
    public var edges: [DiagramEdge]
    public var panels: [DiagramPanel]
    public var recycleBin: [RecycledElements]
    public var backgroundStyle: CanvasBackgroundStyle
    public var gridSize: Double
    public var gridStyle: CanvasGridStyle
    public var gridOpacity: Double
    public init(
        id: UUID = UUID(), title: String = "未命名图表", nodes: [DiagramNode] = [], edges: [DiagramEdge] = [],
        panels: [DiagramPanel] = [], recycleBin: [RecycledElements] = [],
        backgroundStyle: CanvasBackgroundStyle = .system, gridSize: Double = 8,
        gridStyle: CanvasGridStyle = .lines, gridOpacity: Double = 1
    ) {
        self.id = id
        self.title = title
        self.nodes = nodes
        self.edges = edges
        self.panels = panels
        self.recycleBin = recycleBin
        self.backgroundStyle = backgroundStyle
        self.gridSize = gridSize
        self.gridStyle = gridStyle
        self.gridOpacity = gridOpacity
    }
    enum CodingKeys: String, CodingKey {
        case id, title, nodes, edges, panels, recycleBin, backgroundStyle, gridSize, gridStyle, gridOpacity
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        nodes = try c.decode([DiagramNode].self, forKey: .nodes)
        edges = try c.decode([DiagramEdge].self, forKey: .edges)
        panels = try c.decodeIfPresent([DiagramPanel].self, forKey: .panels) ?? []
        recycleBin = try c.decodeIfPresent([RecycledElements].self, forKey: .recycleBin) ?? []
        backgroundStyle = try c.decodeIfPresent(CanvasBackgroundStyle.self, forKey: .backgroundStyle) ?? .system
        gridSize = try c.decodeIfPresent(Double.self, forKey: .gridSize) ?? 8
        gridStyle = try c.decodeIfPresent(CanvasGridStyle.self, forKey: .gridStyle) ?? .lines
        gridOpacity = try c.decodeIfPresent(Double.self, forKey: .gridOpacity) ?? 1
    }
    public var contentBounds: Rect? {
        (nodes.filter { !$0.isHidden }.map(\.frame) + panels.map(\.frame)
            + edges.flatMap { $0.waypoints ?? [] }.map { Rect(x: $0.x, y: $0.y, width: 0, height: 0) }).reduce(nil) {
                result, frame in
                result.map { $0.union(frame) } ?? frame
            }
    }
    public var elementIDs: Set<UUID> { Set(nodes.map(\.id) + edges.map(\.id) + panels.map(\.id)) }
    public func isLocked(_ node: DiagramNode) -> Bool {
        node.isLocked || panels.contains { $0.id == node.panelID && $0.isLocked }
    }
    public func validated() throws -> Diagram {
        let allNodes = nodes + recycleBin.flatMap(\.nodes)
        let allEdges = edges + recycleBin.flatMap(\.edges)
        let allPanels = panels + recycleBin.flatMap(\.panels)
        guard title.count <= 1_000, gridSize.isFinite, (4...64).contains(gridSize),
            gridOpacity.isFinite, (0.15...1).contains(gridOpacity),
            allNodes.count <= 20_000, allEdges.count <= 40_000, allPanels.count <= 1_000,
            recycleBin.count <= 20_000
        else { throw DiagramError.limitExceeded }
        let allIDs = allNodes.map(\.id) + allEdges.map(\.id) + allPanels.map(\.id)
        guard Set(allIDs).count == allIDs.count, Set(recycleBin.map(\.id)).count == recycleBin.count else {
            throw DiagramError.duplicateID
        }
        func valid(_ f: Rect, minWidth: Double, minHeight: Double) -> Bool {
            Point(x: f.x, y: f.y).isValid && Point(x: f.maxX, y: f.maxY).isValid && f.width.isFinite
                && f.height.isFinite && f.width >= minWidth && f.height >= minHeight
        }
        for n in allNodes {
            guard valid(n.frame, minWidth: n.kind.minimumWidth, minHeight: n.kind.minimumHeight), n.fontSize.isFinite,
                (8...96).contains(n.fontSize), n.title.count <= 100_000,
                n.effectiveStrokeWidth.isFinite, (0...12).contains(n.effectiveStrokeWidth),
                n.effectiveOpacity.isFinite, (0.05...1).contains(n.effectiveOpacity),
                n.effectiveCornerRadius.isFinite, (0...96).contains(n.effectiveCornerRadius),
                (n.attributes ?? []).count <= 200, (n.operations ?? []).count <= 200,
                (n.attributes ?? []).allSatisfy({ $0.count <= 1_000 }),
                (n.operations ?? []).allSatisfy({ $0.count <= 1_000 }), (n.stereotype?.count ?? 0) <= 200
            else { throw DiagramError.invalidGeometry }
        }
        for panel in allPanels {
            guard valid(panel.frame, minWidth: 160, minHeight: 120), panel.title.count <= 1_000 else {
                throw DiagramError.invalidGeometry
            }
        }
        let nodeIDs = Set(nodes.map(\.id))
        let panelIDs = Set(panels.map(\.id))
        let allNodeIDs = Set(allNodes.map(\.id))
        let allPanelIDs = Set(allPanels.map(\.id))
        for n in nodes { if let id = n.panelID, !panelIDs.contains(id) { throw DiagramError.invalidPanel } }
        for n in allNodes { if let id = n.panelID, !allPanelIDs.contains(id) { throw DiagramError.invalidPanel } }
        for e in allEdges {
            guard allNodeIDs.contains(e.source), allNodeIDs.contains(e.target), e.source != e.target,
                (e.waypoints?.count ?? 0) <= 128, (e.waypoints ?? []).allSatisfy({ $0.isValid }),
                e.label.count <= 10_000, e.sourceAnchor?.isValid != false, e.targetAnchor?.isValid != false
            else { throw DiagramError.invalidConnection }
        }
        for e in edges {
            guard nodeIDs.contains(e.source), nodeIDs.contains(e.target) else { throw DiagramError.invalidConnection }
        }
        return self
    }
}

public enum DiagramError: Error, LocalizedError, Sendable {
    case invalidGeometry, duplicateID, invalidConnection, limitExceeded, unsupportedVersion, corruptFile,
        layoutRequiresForest, invalidPanel, restoreDependency, lastPage, pageLimitExceeded
    public var errorDescription: String? {
        switch self {
        case .invalidGeometry: "图形尺寸、坐标或文字参数无效。"
        case .duplicateID: "文件包含重复的图形标识。"
        case .invalidConnection: "连接线引用了无效的图形，或包含尚未支持的自环。"
        case .limitExceeded: "文件超出当前预览版的安全容量限制。"
        case .unsupportedVersion: "此文件由更新版本的 Forma 创建，请更新应用后再打开。"
        case .corruptFile: "文件内容不完整或已损坏，原文件未被修改。"
        case .invalidPanel: "图形引用的 Panel 不存在。"
        case .restoreDependency: "相关节点或 Panel 尚在回收箱中，请先恢复它们，或选择恢复全部。"
        case .lastPage: "文档至少需要保留一个页面。"
        case .pageLimitExceeded: "页面数量超出当前预览版的上限。"
        case .layoutRequiresForest: "当前布局仅支持树结构。请移除循环或多个父节点后重试。"
        }
    }
}

/// 一个 .forma 文件对应一个多页文档；每页复用 Diagram 作为页面模型。
public struct DiagramDocument: Codable, Equatable, Sendable {
    public static let maximumPages = 50
    public var pages: [Diagram]
    public var activePageID: UUID
    public init(
        pages: [Diagram] = [Diagram()], activePageID: UUID? = nil
    ) {
        var pages = pages
        if pages.isEmpty { pages = [Diagram()] }
        self.pages = pages
        self.activePageID = activePageID ?? pages[0].id
    }
    public init(page: Diagram) {
        pages = [page]
        activePageID = page.id
    }
    public var activeIndex: Int? { pages.firstIndex { $0.id == activePageID } }
    public var activePage: Diagram {
        get { pages[activeIndex ?? pages.startIndex] }
        set { pages[activeIndex ?? pages.startIndex] = newValue }
    }
    public func validated() throws -> DiagramDocument {
        var seen = Set<UUID>()
        for page in pages {
            _ = try page.validated()
            guard seen.insert(page.id).inserted else { throw DiagramError.duplicateID }
        }
        guard pages.count <= Self.maximumPages, pages.contains(where: { $0.id == activePageID }) else {
            throw pages.count > Self.maximumPages ? DiagramError.pageLimitExceeded : DiagramError.corruptFile
        }
        return self
    }
}
