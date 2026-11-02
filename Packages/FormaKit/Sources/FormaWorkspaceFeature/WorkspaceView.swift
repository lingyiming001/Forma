import AppKit
import FormaApplication
import FormaCanvasEngine
import FormaDesignSystem
import FormaDomain
import FormaGeometry
import FormaLocalization
import SwiftUI

public struct WorkspaceView: View {
    @Bindable var session: DocumentSession
    /// 所有编辑视图共享侧栏页签，确保内嵌编辑器和独立窗口保持一致。
    @AppStorage("Forma.editorSidebarTab") private var sidebarTab = 0
    @State private var requestedInitialSidebarTab: Int?
    @State private var showHelp = false
    @State private var shapeSearch = ""
    @State private var renamingPage: PageRenameRequest?
    private let showsOwnSidebar: Bool
    @State private var expandedShapeCategories: Set<String> = ["常用图形", "基础图形", "UML 与企业架构"]
    @AppStorage("Forma.favoriteShapeKinds") private var favoriteShapeKinds = "rounded,text,rectangle,ellipse,diamond"
    public init(session: DocumentSession, initialSidebarTab: Int = 0, showsOwnSidebar: Bool = true) {
        self.session = session
        self.showsOwnSidebar = showsOwnSidebar
        _requestedInitialSidebarTab = State(initialValue: initialSidebarTab == 0 ? nil : initialSidebarTab)
    }
    public var body: some View {
        HStack(spacing: 0) {
            if showsOwnSidebar && session.showSidebar {
                sidebar.frame(width: 224).clipped()
                Divider()
            }
            VStack(spacing: 0) {
                ZStack(alignment: .top) {
                    CanvasHostView(session: session).clipped()
                    HStack {
                        Spacer()
                        Text(session.diagram.panels.isEmpty ? tr("自由画布") : "\(session.diagram.panels.count) Panels")
                            .font(.system(size: 10)).foregroundStyle(.secondary).padding(10)
                    }.padding(16).allowsHitTesting(false)
                    if session.diagram.nodes.isEmpty && session.diagram.panels.isEmpty {
                        VStack(spacing: 14) {
                            Image(systemName: "square.on.square.dashed").font(.system(size: 36, weight: .ultraLight))
                                .foregroundStyle(FormaTheme.gradient)
                            Text(tr("让想法，清晰成形。")).font(.system(size: 22, weight: .semibold))
                            Text(tr("选择图形或 Panel，再单击画布放置。也可以从模板开始。")).font(.system(size: 12)).foregroundStyle(
                                .secondary)
                            Button(tr("添加第一个图形")) {
                                session.add(.rounded, at: session.camera.world(session.screenCenter))
                            }.buttonStyle(.borderedProminent)
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }.clipped()
                    .overlay(alignment: .topLeading) {
                        if let edge = session.selectedEdge {
                            connectionStyleBar(edge).padding(12)
                        }
                    }
                Divider()
                pageTabBar
                Divider()
                HStack(spacing: 10) {
                    Circle().fill(FormaTheme.accent).frame(width: 5, height: 5)
                    Text(
                        tr(
                            session.statusMessage
                                ?? (session.tool == .connector ? "依次点击两个图形建立连接 · Esc 取消" : "空格拖动画布 · 双击编辑文字"))
                    ).font(
                        .system(size: 10)
                    ).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 4)
                    Button {
                        session.showGrid.toggle()
                    } label: {
                        Image(systemName: "circle.grid.3x3.fill").foregroundStyle(
                            session.showGrid ? FormaTheme.accent : .secondary)
                    }.buttonStyle(.plain).help(tr("显示或隐藏网格"))
                    Divider().frame(height: 12)
                    Button {
                        zoom(0.8)
                    } label: {
                        Image(systemName: "minus")
                    }.buttonStyle(.plain).help(tr("缩小"))
                    ZoomControl(session: session)
                    Button {
                        zoom(1.25)
                    } label: {
                        Image(systemName: "plus")
                    }.buttonStyle(.plain).help(tr("放大"))
                }.padding(.horizontal, 16).frame(height: 32).background(FormaTheme.panel)
            }.frame(minWidth: 440).clipped()
            if session.showInspector {
                Divider()
                inspector.frame(width: 264).clipped()
            }
        }.environment(\.locale, Locale(identifier: Localization.shared.language.identifier)).background(
            FormaTheme.panel
        ).tint(FormaTheme.accent)
            .overlay {
                if session.isProcessing {
                    VStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text(tr("正在处理大型图表…")).font(.system(size: 11, weight: .medium))
                    }.padding(.horizontal, 20).padding(.vertical, 14)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
                }
            }
            .alert(
                tr("无法完成操作"),
                isPresented: Binding(
                    get: { session.errorMessage != nil && !session.showDocumentTrash },
                    set: { if !$0 { session.errorMessage = nil } })
            ) {
                Button(tr("好")) { session.errorMessage = nil }
            } message: {
                Text(tr(session.errorMessage ?? ""))
            }
            .sheet(isPresented: $session.showDocumentTrash) { documentTrash }
            .sheet(isPresented: $showHelp) { helpSheet }
            .onAppear {
                guard let requestedInitialSidebarTab else { return }
                sidebarTab = min(max(requestedInitialSidebarTab, 0), 2)
                self.requestedInitialSidebarTab = nil
            }
    }
    private func zoom(_ value: Double) {
        session.camera.zoom(to: session.camera.scale * value, at: session.screenCenter)
    }
    /// 页面标签栏：切换、新建、重命名、重复、排序与删除当前文档的页面。
    private var pageTabBar: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(session.pages.enumerated()), id: \.element.id) { index, page in
                        let active = page.id == session.activePageID
                        Button {
                            session.selectPage(page.id)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: active ? "square.on.square" : "square").font(.system(size: 10))
                                Text(page.title).font(.system(size: 11, weight: active ? .semibold : .regular))
                                    .lineLimit(1)
                                Text("\(index + 1)").font(.system(size: 9)).foregroundStyle(.tertiary)
                            }.padding(.horizontal, 10).padding(.vertical, 6)
                                .background(
                                    active ? FormaTheme.accent.opacity(0.12) : .clear,
                                    in: RoundedRectangle(cornerRadius: 7))
                        }.buttonStyle(.plain).foregroundStyle(active ? FormaTheme.accent : .secondary)
                            .contextMenu {
                                Button(tr("重命名")) { renamingPage = PageRenameRequest(id: page.id) }
                                Button(tr("重复页面")) { session.duplicatePage(page.id) }
                                Divider()
                                Button(tr("左移页面")) { session.movePage(page.id, left: true) }.disabled(index == 0)
                                Button(tr("右移页面")) { session.movePage(page.id, left: false) }
                                    .disabled(index == session.pages.count - 1)
                                Divider()
                                Button(tr("删除页面"), role: .destructive) { session.deletePage(page.id) }
                                    .disabled(session.pages.count <= 1)
                            }
                    }
                }
            }
            Button {
                session.addPage()
            } label: {
                Image(systemName: "plus.square").font(.system(size: 12))
            }.buttonStyle(.plain).help(tr("添加页面"))
            Spacer(minLength: 0)
        }.padding(.horizontal, 12).frame(height: 34).background(FormaTheme.panel)
            .sheet(item: $renamingPage) { request in
                if let page = session.pages.first(where: { $0.id == request.id }) {
                    NamingSheet(title: "重命名页面", initial: page.title) { value in
                        renamingPage = nil
                        let title = value.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !title.isEmpty, title.count <= 200 { session.renamePage(request.id, title: title) }
                    }
                }
            }
    }
    private var sidebar: some View {
        VStack(spacing: 0) {
            sidebarContent
            Divider()
            HStack {
                Spacer()
                Button {
                    showHelp = true
                } label: {
                    Image(systemName: "questionmark.circle")
                }.buttonStyle(.plain).help(tr("快捷键与使用帮助"))
                Button {
                    session.settingsAction?()
                } label: {
                    Image(systemName: "gearshape")
                }.buttonStyle(.plain).help(tr("设置"))
            }.font(.system(size: 11)).foregroundStyle(.secondary).padding(16)
        }
    }
    public var sidebarContent: some View {
        VStack(spacing: 0) {
            Picker(tr("侧栏"), selection: $sidebarTab) {
                Text(tr("图层")).tag(0)
                Text(tr("图形")).tag(1)
                Text(tr("模板")).tag(2)
            }.pickerStyle(.segmented).labelsHidden().padding(.horizontal, 14).padding(.vertical, 14)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(
                            sidebarTab == 0
                                ? String(format: tr("页面 %d"), session.pageIndex)
                                : tr(sidebarTab == 1 ? "图形库" : "从这里开始")
                        ).font(
                            .system(size: 11, weight: .semibold))
                        Spacer()
                        if sidebarTab == 0 {
                            Button {
                                session.addPanel(at: session.camera.world(session.screenCenter))
                            } label: {
                                Image(systemName: "plus.rectangle.dashed")
                            }.buttonStyle(.plain).help(tr("添加 Panel"))
                        }
                    }.padding(.top, 8)
                    if sidebarTab == 0 { layers } else if sidebarTab == 1 { shapes } else { templates }
                }.padding(14)
            }
        }
    }
    private var layers: some View {
        let grouped = Dictionary(grouping: session.diagram.nodes, by: \.panelID)
        let visiblePanels = Array(session.diagram.panels.prefix(200))
        let topLevelNodes = Array((grouped[nil] ?? []).reversed().prefix(500))
        return LazyVStack(alignment: .leading, spacing: 4) {
            ForEach(visiblePanels) { panel in
                VStack(alignment: .leading, spacing: 2) {
                    Button {
                        session.selection = [panel.id]
                        session.tool = .select
                    } label: {
                        HStack {
                            Image(systemName: "rectangle.dashed")
                            Text(panel.title).lineLimit(1)
                            Spacer()
                            if panel.isLocked { Image(systemName: "lock.fill") }
                        }.font(.system(size: 11, weight: .semibold)).padding(9)
                            .background(
                                session.selection.contains(panel.id)
                                    ? FormaTheme.accent.opacity(0.12) : Color.primary.opacity(0.03),
                                in: RoundedRectangle(cornerRadius: 6))
                    }.buttonStyle(.plain)
                    let panelNodes = Array((grouped[panel.id] ?? []).reversed().prefix(250))
                    ForEach(panelNodes) { node in
                        nodeRow(node).padding(.leading, 12)
                    }
                    let hiddenCount = (grouped[panel.id]?.count ?? 0) - panelNodes.count
                    if hiddenCount > 0 { omittedLayerCount(hiddenCount).padding(.leading, 20) }
                }.padding(.bottom, 8)
            }
            if session.diagram.panels.count > visiblePanels.count {
                omittedLayerCount(session.diagram.panels.count - visiblePanels.count)
            }
            ForEach(topLevelNodes) { node in nodeRow(node) }
            let hiddenTopLevelCount = (grouped[nil]?.count ?? 0) - topLevelNodes.count
            if hiddenTopLevelCount > 0 { omittedLayerCount(hiddenTopLevelCount) }
            if session.diagram.nodes.isEmpty && session.diagram.panels.isEmpty {
                Text(tr("添加的图形会显示在这里")).font(.system(size: 11)).foregroundStyle(.tertiary).padding(.vertical, 24)
            }
            if !session.diagram.edges.isEmpty {
                Text(tr("连接线") + " · \(session.diagram.edges.count)").font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary).padding(.top, 16)
                ForEach(session.diagram.edges.prefix(500)) { edge in
                    Button {
                        session.selection = [edge.id]
                    } label: {
                        Label(
                            edge.label.isEmpty ? tr(edge.effectiveRelation.title) : edge.label,
                            systemImage: "arrow.up.right"
                        ).font(.system(size: 11)).foregroundStyle(
                            session.selection.contains(edge.id) ? FormaTheme.accent : .secondary
                        ).frame(maxWidth: .infinity, alignment: .leading).padding(8)
                    }.buttonStyle(.plain)
                }
                if session.diagram.edges.count > 500 { omittedLayerCount(session.diagram.edges.count - 500) }
            }
        }
    }
    private func omittedLayerCount(_ count: Int) -> some View {
        Text(String(format: tr("另有 %d 项未在侧栏展开"), count)).font(.system(size: 10)).foregroundStyle(.tertiary)
            .padding(.horizontal, 9).padding(.vertical, 5)
    }
    private func nodeRow(_ node: DiagramNode) -> some View {
        HStack(spacing: 8) {
            Image(systemName: node.kind.symbol).font(.system(size: 12)).foregroundStyle(
                session.selection.contains(node.id) ? FormaTheme.accent : .secondary
            ).frame(width: 18)
            Text(node.title.replacingOccurrences(of: "\n", with: " ")).font(.system(size: 11)).lineLimit(1)
            Spacer(minLength: 0)
            if session.diagram.isLocked(node) {
                Image(systemName: "lock.fill").font(.system(size: 9)).foregroundStyle(.secondary)
            }
            Button {
                session.updateNode(node.id, name: node.isHidden ? "显示图形" : "隐藏图形") { $0.isHidden.toggle() }
            } label: {
                Image(systemName: node.isHidden ? "eye.slash" : "eye").font(.system(size: 10)).foregroundStyle(
                    .tertiary)
            }.buttonStyle(.plain).help(tr(node.isHidden ? "显示图形" : "隐藏图形"))
        }.padding(.horizontal, 9).padding(.vertical, 9).background(
            session.selection.contains(node.id) ? FormaTheme.accent.opacity(0.1) : .clear,
            in: RoundedRectangle(cornerRadius: 6)
        ).opacity(node.isHidden ? 0.5 : 1).contentShape(Rectangle())
            .onTapGesture {
                session.selection = [node.id]
                session.tool = .select
            }
            .accessibilityElement(children: .contain).accessibilityLabel(node.title).accessibilityAction(
                named: tr("选择图形")
            ) { session.selection = [node.id] }
    }
    private var shapes: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(tr("搜索图形"), text: $shapeSearch).textFieldStyle(.plain).font(.system(size: 12))
                if !shapeSearch.isEmpty {
                    Button {
                        shapeSearch = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }.buttonStyle(.plain)
                }
            }.padding(.horizontal, 11).frame(height: 34)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.primary.opacity(0.08)))
            Button {
                session.tool = .panel
            } label: {
                Label(tr("Panel 分区"), systemImage: "rectangle.dashed").font(.system(size: 12)).frame(
                    maxWidth: .infinity
                )
                .padding(12).background(FormaTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
            }.buttonStyle(.plain)
            if shapeSearch.isEmpty, !favoriteKinds.isEmpty {
                shapeSection(title: "常用图形", kinds: favoriteKinds, symbol: "star.fill")
            }
            ForEach(["基础图形", "流程图", "箭头", "UML 与企业架构"], id: \.self) { category in
                let kinds = filteredKinds(in: category)
                if !kinds.isEmpty {
                    shapeSection(
                        title: category, kinds: kinds,
                        symbol: categorySymbol(category))
                }
            }
            if !shapeSearch.isEmpty && filteredKinds.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 22, weight: .light))
                    Text(tr("没有匹配的图形")).font(.system(size: 11))
                }.foregroundStyle(.tertiary).frame(maxWidth: .infinity).padding(.vertical, 24)
            }
            Text(tr("单击选择工具，或拖到画布直接放置。")).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
    private func categorySymbol(_ category: String) -> String {
        switch category {
        case "流程图": "point.3.connected.trianglepath.dotted"
        case "箭头": "arrow.right"
        case "UML 与企业架构": "building.columns"
        default: "square.grid.2x2"
        }
    }
    private var favoriteKinds: [ShapeKind] {
        let values = Set(favoriteShapeKinds.split(separator: ",").compactMap { ShapeKind(rawValue: String($0)) })
        return ShapeKind.allCases.filter { values.contains($0) }
    }
    private var filteredKinds: [ShapeKind] {
        ShapeKind.allCases.filter(shapeMatches)
    }
    private func filteredKinds(in category: String) -> [ShapeKind] {
        ShapeKind.allCases.filter { $0.category == category && shapeMatches($0) }
    }
    private func shapeMatches(_ kind: ShapeKind) -> Bool {
        let query = shapeSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty || tr(kind.title).localizedStandardContains(query)
            || tr(kind.category).localizedStandardContains(query)
    }
    private func shapeSection(title: String, kinds: [ShapeKind], symbol: String) -> some View {
        let expanded = expandedShapeCategories.contains(title) || !shapeSearch.isEmpty
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                if expandedShapeCategories.contains(title) {
                    expandedShapeCategories.remove(title)
                } else {
                    expandedShapeCategories.insert(title)
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.system(size: 9, weight: .bold))
                    Image(systemName: symbol).font(.system(size: 11))
                    Text(tr(title)).font(.system(size: 11, weight: .semibold))
                    Spacer()
                    Text("\(kinds.count)").font(.system(size: 9).monospacedDigit()).foregroundStyle(.tertiary)
                }.foregroundStyle(.secondary).contentShape(Rectangle())
            }.buttonStyle(.plain)
            if expanded {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(kinds, id: \.self) { shapeButton($0) }
                }
            }
        }
    }
    private func shapeButton(_ kind: ShapeKind) -> some View {
        Button {
            session.tool = CanvasTool(rawValue: kind.rawValue) ?? .select
        } label: {
            VStack(spacing: 8) {
                Image(systemName: kind.symbol).font(.system(size: 24, weight: .ultraLight))
                    .foregroundStyle(session.tool.shape == kind ? FormaTheme.accent : .primary)
                Text(tr(kind.title)).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }.frame(maxWidth: .infinity).frame(height: 68).background(
                FormaTheme.accent.opacity(session.tool.shape == kind ? 0.14 : 0.035),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.05)))
        }.buttonStyle(.plain).help(tr(kind.title)).contextMenu {
            Button {
                toggleFavorite(kind)
            } label: {
                Label(
                    tr(favoriteKinds.contains(kind) ? "从常用图形移除" : "添加到常用图形"),
                    systemImage: favoriteKinds.contains(kind) ? "star.slash" : "star")
            }
        }.onDrag {
            NSItemProvider(item: kind.rawValue as NSString, typeIdentifier: "com.forma.shape-kind")
        }
    }
    private func toggleFavorite(_ kind: ShapeKind) {
        var values = Set(favoriteKinds)
        if values.contains(kind) { values.remove(kind) } else { values.insert(kind) }
        favoriteShapeKinds = ShapeKind.allCases.filter { values.contains($0) }.map(\.rawValue).joined(separator: ",")
    }
    private var templates: some View {
        VStack(spacing: 12) {
            ForEach(session.templates) { template in
                Button {
                    session.templateAction?(template.id)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: template.symbol).font(.system(size: 24, weight: .light)).foregroundStyle(
                            FormaTheme.gradient
                        ).frame(width: 32)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(tr(template.title)).font(.system(size: 12, weight: .semibold)).foregroundStyle(
                                .primary)
                            Text(tr(template.category)).font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }.padding(13).background(
                        Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10)
                    ).overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.06)))
                }.buttonStyle(.plain).help(tr(template.subtitle))
            }
        }
    }
    private var inspector: some View {
        VStack(spacing: 0) {
            HStack {
                Text(tr("检查器")).font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(session.selection.isEmpty ? tr("画布") : "\(session.selection.count) " + tr("项所选")).font(
                    .system(size: 10)
                ).foregroundStyle(.secondary)
            }.padding(18)
            Divider()
            ScrollView {
                if session.selectedPanels.count == 1, session.selectedNodes.isEmpty,
                    let panel = session.selectedPanels.first
                {
                    PanelInspector(panel: panel, session: session).id(panel.id)
                } else if session.selectedNodes.count == 1, let node = session.selectedNodes.first {
                    NodeInspector(node: node, session: session).id(node.id)
                } else if session.selectedNodes.count > 1 {
                    InspectorSection("批量编辑") {
                        HStack {
                            Button(tr("组合")) { session.groupSelection() }.disabled(!session.canGroupSelection)
                            Button(tr("取消组合")) { session.ungroupSelection() }.disabled(!session.canUngroupSelection)
                        }
                        Text(tr("组合后可整体移动、复制和删除")).font(.system(size: 10)).foregroundStyle(.secondary)
                        PalettePicker(session: session)
                        HStack {
                            Button(tr("水平对齐")) { session.align(true) }
                            Button(tr("垂直对齐")) { session.align(false) }
                        }.font(.system(size: 11))
                        panelAssignment
                    }
                } else if let edge = session.selectedEdge {
                    edgeInspector(edge)
                } else {
                    documentInspector
                }
            }
            Spacer(minLength: 0)
            Divider()
            HStack {
                Label(tr("本地文档"), systemImage: "internaldrive").foregroundStyle(.secondary)
                Spacer()
                Menu {
                    Button(tr("存入工作空间副本")) { session.saveToWorkspaceAction?() }
                    Button(tr("导出 PDF…")) { session.exportAction?(false) }
                    Button(tr("导出 PNG…")) { session.exportAction?(true) }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }.menuStyle(.borderlessButton).frame(width: 22)
            }.font(.system(size: 10)).padding(16)
        }
    }
    private var panelAssignment: some View {
        Menu(tr("移动到 Panel")) {
            Button(tr("自由画布")) { session.assignSelection(to: nil) }
            ForEach(session.diagram.panels.filter { !$0.isLocked }) { panel in
                Button(panel.title) { session.assignSelection(to: panel.id) }
            }
        }
    }
    private func endpointPicker(_ edge: DiagramEdge, source: Bool) -> some View {
        Picker(
            tr(source ? "起点箭头" : "终点箭头"),
            selection: Binding(
                get: { (source ? edge.sourceMarker : edge.targetMarker) ?? .automatic },
                set: { value in
                    session.perform(source ? "更改起点箭头" : "更改终点箭头") { model in
                        guard let i = model.edges.firstIndex(where: { $0.id == edge.id }) else { return }
                        if source {
                            model.edges[i].sourceMarker = value == .automatic ? nil : value
                        } else {
                            model.edges[i].targetMarker = value == .automatic ? nil : value
                        }
                    }
                })
        ) {
            ForEach(EndpointMarker.allCases, id: \.self) { marker in Text(tr(marker.title)).tag(marker) }
        }.font(.system(size: 11))
    }
    private func connectionStyleBar(_ edge: DiagramEdge) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "line.diagonal").foregroundStyle(FormaTheme.accent)
            Menu(tr("线型") + " · " + tr(edge.effectiveLineStyle.title)) {
                ForEach(LineStyle.allCases, id: \.self) { style in
                    Button(tr(style.title)) {
                        session.perform("更改线型") { model in
                            if let i = model.edges.firstIndex(where: { $0.id == edge.id }) {
                                model.edges[i].lineStyle = style
                            }
                        }
                    }
                }
            }.fixedSize()
            Menu(tr("路径")) {
                Button(tr("恢复自动路径")) {
                    session.perform("调整连线路径") { model in
                        if let i = model.edges.firstIndex(where: { $0.id == edge.id }) {
                            model.edges[i].waypoints = nil
                        }
                    }
                }.disabled(edge.waypoints?.isEmpty != false)
            }.fixedSize()
            Divider().frame(height: 16)
            Menu(tr("起点箭头")) { endpointPicker(edge, source: true).pickerStyle(.inline) }.fixedSize()
            Menu(tr("终点箭头")) { endpointPicker(edge, source: false).pickerStyle(.inline) }.fixedSize()
        }.font(.system(size: 11)).padding(10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08)))
            .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
    }
    private func edgeInspector(_ edge: DiagramEdge) -> some View {
        InspectorSection("连接线") {
            CommitField(label: "标签", value: edge.label) { value in
                session.perform("编辑连接标签") { model in
                    if let i = model.edges.firstIndex(where: { $0.id == edge.id }) { model.edges[i].label = value }
                }
            }
            Picker(
                tr("关系类型"),
                selection: Binding(
                    get: { edge.effectiveRelation },
                    set: { value in
                        session.perform("更改关系类型") { model in
                            if let i = model.edges.firstIndex(where: { $0.id == edge.id }) {
                                model.edges[i].relation = value
                            }
                        }
                    })
            ) { ForEach(UMLRelation.allCases, id: \.self) { relation in Text(tr(relation.title)).tag(relation) } }.font(
                .system(size: 11))
            Picker(
                tr("线型"),
                selection: Binding(
                    get: { edge.effectiveLineStyle },
                    set: { value in
                        session.perform("更改线型") { model in
                            if let i = model.edges.firstIndex(where: { $0.id == edge.id }) {
                                model.edges[i].lineStyle = value
                            }
                        }
                    })
            ) { ForEach(LineStyle.allCases, id: \.self) { style in Text(tr(style.title)).tag(style) } }.font(
                .system(size: 11))
            endpointPicker(edge, source: true)
            endpointPicker(edge, source: false)
            LabeledContent(tr("起点"), value: session.diagram.nodes.first { $0.id == edge.source }?.title ?? "—")
            LabeledContent(tr("终点"), value: session.diagram.nodes.first { $0.id == edge.target }?.title ?? "—")
            Button(tr("交换起点与终点")) {
                session.perform("交换连接方向") { model in
                    guard let index = model.edges.firstIndex(where: { $0.id == edge.id }) else { return }
                    let source = model.edges[index].source
                    model.edges[index].source = model.edges[index].target
                    model.edges[index].target = source
                    let anchor = model.edges[index].sourceAnchor
                    model.edges[index].sourceAnchor = model.edges[index].targetAnchor
                    model.edges[index].targetAnchor = anchor
                }
            }
            Button(tr("恢复自动路径")) {
                session.perform("调整连线路径") { model in
                    if let i = model.edges.firstIndex(where: { $0.id == edge.id }) { model.edges[i].waypoints = nil }
                }
            }.disabled(edge.waypoints?.isEmpty != false)
            Text(tr("拖动线段中间的空心方点添加控制点；拖动实心方点调整，双击移除。"))
                .font(.system(size: 11)).foregroundStyle(.secondary)
            Button(tr("恢复自动样式")) {
                session.perform("恢复连接样式") { model in
                    guard let index = model.edges.firstIndex(where: { $0.id == edge.id }) else { return }
                    model.edges[index].lineStyle = nil
                    model.edges[index].arrow = nil
                    model.edges[index].sourceMarker = nil
                    model.edges[index].targetMarker = nil
                }
            }
            Text(tr("拖动连线两端的圆点，可吸附到图形的其他边或位置。")).font(.system(size: 11)).foregroundStyle(.secondary)
            Button(tr("移入回收箱"), role: .destructive) { session.deleteSelection() }
        }
    }
    private var documentInspector: some View {
        VStack(spacing: 10) {
            CanvasInspectorCard("文档", systemName: "doc.text") {
                CommitField(label: "名称", value: session.diagram.title) { value in
                    session.renamePage(session.diagram.id, title: value)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                    InspectorMetric("页面", value: session.pages.count, systemName: "rectangle.on.rectangle")
                    InspectorMetric("图形", value: session.diagram.nodes.count, systemName: "square.on.circle")
                    InspectorMetric("Panel", value: session.diagram.panels.count, systemName: "rectangle.split.2x1")
                    InspectorMetric("连接线", value: session.diagram.edges.count, systemName: "arrow.triangle.branch")
                    InspectorMetric(
                        "隐藏", value: session.diagram.nodes.filter(\.isHidden).count, systemName: "eye.slash")
                    InspectorMetric(
                        "锁定",
                        value: session.diagram.nodes.filter(\.isLocked).count
                            + session.diagram.panels.filter(\.isLocked).count,
                        systemName: "lock")
                }
                HStack(spacing: 7) {
                    Image(systemName: "trash").foregroundStyle(.tertiary).frame(width: 15)
                    Text(tr("页面回收箱")).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(session.diagram.recycleBin.count)").monospacedDigit().foregroundStyle(.tertiary)
                }.padding(.horizontal, 9).frame(height: 28)
                    .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 7))
            }.font(.system(size: 11))
            CanvasInspectorCard("画布外观", systemName: "paintpalette") {
                CanvasBackgroundPicker(session: session)
            }.font(.system(size: 11))
            CanvasInspectorCard("网格", systemName: "circle.grid.3x3") {
                Toggle(tr("显示网格"), isOn: $session.showGrid)
                Toggle(tr("吸附到网格"), isOn: $session.snapToGrid)
                Picker(
                    tr("网格样式"),
                    selection: Binding(
                        get: { session.diagram.gridStyle },
                        set: { value in session.perform("更改网格样式") { $0.gridStyle = value } })
                ) {
                    ForEach(CanvasGridStyle.allCases, id: \.self) { style in Text(tr(style.title)).tag(style) }
                }.pickerStyle(.segmented)
                Stepper(
                    value: Binding(
                        get: { session.diagram.gridSize },
                        set: { value in session.perform("更改网格间距") { $0.gridSize = value } }),
                    in: 4...64,
                    step: 4
                ) {
                    LabeledContent(tr("网格间距"), value: "\(Int(session.diagram.gridSize)) pt")
                }
                .disabled(!session.showGrid && !session.snapToGrid)
                VStack(alignment: .leading, spacing: 5) {
                    LabeledContent(tr("网格透明度"), value: "\(Int(session.diagram.gridOpacity * 100))%")
                    Slider(
                        value: Binding(
                            get: { session.diagram.gridOpacity },
                            set: { value in session.perform("更改网格透明度") { $0.gridOpacity = value } }),
                        in: 0.15...1
                    )
                }.disabled(!session.showGrid)
            }.font(.system(size: 11)).toggleStyle(.checkbox)
            CanvasInspectorCard("视图", systemName: "viewfinder") {
                LabeledContent(tr("缩放"), value: "\(Int((session.camera.scale * 100).rounded()))%")
                LabeledContent(
                    tr("视口中心"),
                    value:
                        "\(Int(session.camera.world(session.screenCenter).x)), \(Int(session.camera.world(session.screenCenter).y))"
                )
                InspectorActionButton("适合全部内容", systemName: "arrow.up.left.and.arrow.down.right") {
                    session.fitRequest += 1
                }
                InspectorActionButton("实际大小", systemName: "1.magnifyingglass") {
                    session.camera.zoom(to: 1, at: session.screenCenter)
                }
                InspectorActionButton("添加 Panel", systemName: "plus.rectangle.on.rectangle") {
                    session.addPanel(at: session.camera.world(session.screenCenter))
                }
                InspectorActionButton("树形自动布局", systemName: "point.3.connected.trianglepath.dotted") {
                    applyLayout()
                }.disabled(session.isProcessing)
            }.font(.system(size: 11))
            CanvasInspectorCard("工作空间", systemName: "square.grid.2x2") {
                InspectorActionButton("返回工作空间", systemName: "chevron.backward") { session.workspaceAction?() }
                InspectorActionButton("存入工作空间副本", systemName: "square.and.arrow.down") {
                    session.saveToWorkspaceAction?()
                }
                InspectorActionButton("页面回收箱", systemName: "trash") { session.showDocumentTrash = true }
            }.font(.system(size: 11))
        }.padding(10)
    }
    private func applyLayout() {
        guard session.diagram.nodes.count <= 2_000 else {
            session.errorMessage = "当前预览版支持对 2,000 个以内的图形进行自动布局。"
            return
        }
        guard !session.isProcessing else { return }
        let snapshot = session.diagram
        let revision = session.revision
        session.isProcessing = true
        Task {
            defer { session.isProcessing = false }
            do {
                let frames = try await Task.detached(priority: .userInitiated) {
                    try TreeLayout.apply(to: snapshot)
                }.value
                guard session.revision == revision else {
                    session.statusMessage = tr("图表已发生变化，已取消本次布局。")
                    return
                }
                session.perform("自动布局") { model in
                    for i in model.nodes.indices {
                        if let frame = frames[model.nodes[i].id] { model.nodes[i].frame = frame }
                    }
                    let grouped = Dictionary(grouping: model.nodes, by: \.panelID)
                    for i in model.panels.indices where !model.panels[i].isLocked {
                        let children = grouped[model.panels[i].id] ?? []
                        if let x = children.map({ $0.frame.maxX }).max(),
                            let y = children.map({ $0.frame.maxY }).max()
                        {
                            model.panels[i].frame.width = max(
                                model.panels[i].frame.width, x - model.panels[i].frame.x + 32)
                            model.panels[i].frame.height = max(
                                model.panels[i].frame.height, y - model.panels[i].frame.y + 32)
                        }
                    }
                }
                session.fitRequest += 1
            } catch { session.errorMessage = error.localizedDescription }
        }
    }
    private var documentTrash: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(tr("页面回收箱")).font(.system(size: 22, weight: .semibold))
                Spacer()
                Button(tr("完成")) { session.showDocumentTrash = false }
            }
            Text(tr("删除的图形、Panel 和连接线保留在当前页面中，可恢复，也支持撤销。")).font(.system(size: 12)).foregroundStyle(.secondary)
            if let error = session.errorMessage { Text(tr(error)).font(.system(size: 12)).foregroundStyle(.red) }
            if session.diagram.recycleBin.isEmpty {
                Text(tr("回收箱是空的")).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(session.diagram.recycleBin.reversed()) { entry in
                            HStack {
                                Image(systemName: entry.panels.isEmpty ? "square.on.square" : "rectangle.dashed")
                                    .foregroundStyle(FormaTheme.accent)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.title).font(.system(size: 13, weight: .medium))
                                    Text("\(entry.nodes.count) " + tr("图形") + " · \(entry.edges.count) " + tr("连接线"))
                                        .font(.system(size: 11)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button(tr("恢复")) { session.restoreRecycled(entry.id) }
                            }.padding(12).background(FormaTheme.panel, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                HStack {
                    Spacer()
                    Button(tr("恢复全部")) { session.restoreRecycled() }
                }
            }
        }.padding(28).frame(width: 600, height: 430)
    }
    private var helpSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(tr("快捷键与使用帮助")).font(.system(size: 22, weight: .semibold))
            ForEach(
                [
                    ("V / R / O / D", "选择 / 圆角矩形 / 椭圆 / 判断"), ("P / L / H", "Panel / 连接线 / 抓手"),
                    ("⌘Z / ⇧⌘Z", "撤销 / 重做"), ("⌘D / ⌘0", "就地复制 / 适合全部"), ("⌘,", "设置"), ("⇧⌘O", "工作空间"),
                ], id: \.0
            ) { key, title in
                HStack {
                    Text(key).monospaced().frame(width: 150, alignment: .leading)
                    Text(tr(title))
                }.font(.system(size: 12))
            }
            Text(tr("双击图形编辑文字。拖动 Panel 标题移动整个分区。P 添加新分区。")).font(.system(size: 12)).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button(tr("完成")) { showHelp = false }.keyboardShortcut(.defaultAction)
            }
        }.padding(32).frame(width: 570)
    }
}

private struct CanvasInspectorCard<Content: View>: View {
    let title: String
    let systemName: String
    @ViewBuilder let content: () -> Content
    init(_ title: String, systemName: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.systemName = systemName
        self.content = content
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: systemName).foregroundStyle(FormaTheme.accent)
                Text(tr(title)).foregroundStyle(.secondary)
            }.font(.system(size: 11, weight: .semibold))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(Color.primary.opacity(0.018), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.04)))
    }
}

private struct InspectorMetric: View {
    let title: String
    let value: Int
    let systemName: String
    init(_ title: String, value: Int, systemName: String) {
        self.title = title
        self.value = value
        self.systemName = systemName
    }
    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: systemName).font(.system(size: 9, weight: .medium)).foregroundStyle(.tertiary)
                Text("\(value)").font(.system(size: 14, weight: .semibold).monospacedDigit())
            }
            Text(tr(title)).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity).frame(height: 51)
        .background(Color.primary.opacity(0.026), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct InspectorActionButton: View {
    let title: String
    let systemName: String
    let action: () -> Void
    init(_ title: String, systemName: String, action: @escaping () -> Void) {
        self.title = title
        self.systemName = systemName
        self.action = action
    }
    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: systemName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(FormaTheme.accent)
                    .frame(width: 17)
                Text(tr(title)).foregroundStyle(.primary)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .semibold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10).frame(height: 32)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(.plain)
    }
}

private struct CanvasBackgroundPicker: View {
    let session: DocumentSession
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 7), count: 4)
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            LabeledContent(tr("画布背景"), value: tr(session.diagram.backgroundStyle.title))
            LazyVGrid(columns: columns, spacing: 7) {
                ForEach(CanvasBackgroundStyle.allCases, id: \.self) { style in
                    Button {
                        session.perform("更改画布背景") { $0.backgroundStyle = style }
                    } label: {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(style.swatch)
                            .frame(height: 30)
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.12)))
                            .overlay {
                                if session.diagram.backgroundStyle == style {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(style == .graphite ? .white : FormaTheme.accent)
                                }
                            }
                    }.buttonStyle(.plain).help(tr(style.title))
                }
            }
        }
    }
}

extension CanvasBackgroundStyle {
    fileprivate var swatch: Color {
        switch self {
        case .system: Color(nsColor: .windowBackgroundColor)
        case .white: Color.white
        case .warm: Color(red: 0.984, green: 0.973, blue: 0.949)
        case .cool: Color(red: 0.953, green: 0.965, blue: 0.980)
        case .sand: Color(red: 0.965, green: 0.941, blue: 0.894)
        case .mint: Color(red: 0.933, green: 0.969, blue: 0.949)
        case .lavender: Color(red: 0.957, green: 0.945, blue: 0.980)
        case .graphite: Color(red: 0.125, green: 0.137, blue: 0.173)
        }
    }
}

private struct PalettePicker: View {
    let session: DocumentSession
    var selected: DiagramColor?
    var body: some View {
        HStack(spacing: 10) {
            ForEach(DiagramColor.allCases, id: \.self) { color in
                Button {
                    session.updateSelectedColor(color)
                } label: {
                    Circle().fill(Color(nsColor: NSColor(hex: color.strokeHex))).frame(width: 23, height: 23).overlay {
                        if color == selected { Circle().stroke(.primary.opacity(0.5), lineWidth: 1).padding(-3) }
                    }
                }.buttonStyle(.plain).help(tr(color.title))
            }
        }
    }
}
private struct PanelInspector: View {
    let panel: DiagramPanel
    let session: DocumentSession
    var body: some View {
        VStack(spacing: 0) {
            InspectorSection("Panel 分区") {
                CommitField(label: "名称", value: panel.title) { value in
                    session.updatePanel(panel.id, name: "重命名 Panel") { $0.title = value }
                }
                Text("\(session.diagram.nodes.filter { $0.panelID==panel.id }.count) " + tr("图形")).font(
                    .system(size: 11)
                ).foregroundStyle(.secondary)
            }
            Divider()
            InspectorSection("位置与尺寸") {
                HStack {
                    number("X", panel.frame.x, 0)
                    number("Y", panel.frame.y, 1)
                }
                HStack {
                    number("W", panel.frame.width, 2)
                    number("H", panel.frame.height, 3)
                }
            }.disabled(panel.isLocked)
            Divider()
            InspectorSection("外观") { PalettePicker(session: session, selected: panel.color) }.disabled(panel.isLocked)
            Divider()
            InspectorSection("操作") {
                Toggle(
                    tr("锁定分区"),
                    isOn: Binding(
                        get: { panel.isLocked },
                        set: { value in session.updatePanel(panel.id, name: "锁定分区") { $0.isLocked = value } })
                ).toggleStyle(.checkbox)
                Button(tr("复制整个分区")) { session.duplicateSelection() }
                Button(tr("移入回收箱"), role: .destructive) { session.deleteSelection() }.disabled(panel.isLocked)
                Text(tr("移动分区会带动其中全部图形；调整尺寸不会缩放内容。")).font(.system(size: 11)).foregroundStyle(.secondary)
            }.font(.system(size: 11))
        }
    }
    private func number(_ label: String, _ value: Double, _ field: Int) -> some View {
        CommitField(label: label, value: String(format: "%.0f", value)) { text in
            guard let n = Double(text), n.isFinite else {
                session.errorMessage = "请输入有效数字。"
                return
            }
            session.updatePanel(panel.id, name: "调整 Panel") { p in
                switch field {
                case 0: p.frame.x = n
                case 1: p.frame.y = n
                case 2: p.frame.width = n
                default: p.frame.height = n
                }
            }
        }
    }
}
private struct NodeInspector: View {
    let node: DiagramNode
    let session: DocumentSession
    var body: some View {
        VStack(spacing: 0) {
            InspectorSection(node.kind.title) {
                Picker(
                    tr("图形类型"),
                    selection: Binding(
                        get: { node.kind },
                        set: { kind in
                            session.updateNode(node.id, name: "更改图形类型") { item in
                                item.kind = kind
                                item.frame.width = max(item.frame.width, kind.minimumWidth)
                                item.frame.height = max(item.frame.height, kind.minimumHeight)
                            }
                        })
                ) {
                    ForEach(ShapeKind.allCases, id: \.self) { kind in Text(tr(kind.title)).tag(kind) }
                }
                CommitField(label: "文字", value: node.title) { value in
                    session.updateNode(node.id, name: "编辑文字") { $0.title = value }
                }
            }.disabled(session.diagram.isLocked(node))
            Divider()
            InspectorSection("位置与尺寸") {
                HStack {
                    number("X", node.frame.x, 0)
                    number("Y", node.frame.y, 1)
                }
                HStack {
                    number("W", node.frame.width, 2)
                    number("H", node.frame.height, 3)
                }
            }.disabled(session.diagram.isLocked(node))
            Divider()
            if node.kind.isClass {
                UMLDetailsEditor(node: node, session: session).disabled(session.diagram.isLocked(node))
                Divider()
            }
            InspectorSection("外观") {
                PalettePicker(session: session, selected: node.color)
                CommitField(label: "描边", value: String(format: "%.1f", node.effectiveStrokeWidth)) { text in
                    guard let value = Double(text), (0...12).contains(value) else {
                        session.errorMessage = tr("描边宽度请输入 0 到 12 之间的数字。")
                        return
                    }
                    session.updateNode(node.id, name: "更改描边宽度") { $0.strokeWidth = value }
                }
                CommitField(label: "透明度", value: String(Int(node.effectiveOpacity * 100))) { text in
                    guard let value = Double(text), (5...100).contains(value) else {
                        session.errorMessage = tr("透明度请输入 5 到 100 之间的数字。")
                        return
                    }
                    session.updateNode(node.id, name: "更改透明度") { $0.opacity = value / 100 }
                }
                if node.kind == .rounded {
                    CommitField(label: "圆角", value: String(Int(node.effectiveCornerRadius))) { text in
                        guard let value = Double(text), (0...96).contains(value) else {
                            session.errorMessage = tr("圆角请输入 0 到 96 之间的数字。")
                            return
                        }
                        session.updateNode(node.id, name: "更改圆角") { $0.cornerRadius = value }
                    }
                }
            }.disabled(session.diagram.isLocked(node))
            Divider()
            InspectorSection("文字") {
                CommitField(label: "字号", value: String(Int(node.fontSize))) { text in
                    if let size = Double(text), (8...96).contains(size) {
                        session.updateNode(node.id, name: "更改字号") { $0.fontSize = size }
                    } else {
                        session.errorMessage = "字号请输入 8 到 96 之间的数字。"
                    }
                }
                Picker(
                    tr("对齐"),
                    selection: Binding(
                        get: { node.effectiveTextAlignment },
                        set: { value in session.updateNode(node.id, name: "更改文字对齐") { $0.textAlignment = value } })
                ) {
                    ForEach(DiagramTextAlignment.allCases, id: \.self) { value in
                        Text(tr(value.title)).tag(value)
                    }
                }.pickerStyle(.segmented)
            }.disabled(session.diagram.isLocked(node))
            Divider()
            InspectorSection("所属分区") {
                Picker("Panel", selection: Binding(get: { node.panelID }, set: { session.assignSelection(to: $0) })) {
                    Text(tr("自由画布")).tag(Optional<UUID>.none)
                    ForEach(session.diagram.panels) { panel in Text(panel.title).tag(Optional(panel.id)) }
                }.labelsHidden()
            }.disabled(session.diagram.isLocked(node))
            Divider()
            InspectorSection("操作") {
                Toggle(
                    tr("锁定图形"),
                    isOn: Binding(
                        get: { node.isLocked },
                        set: { value in session.updateNode(node.id, name: "锁定图形") { $0.isLocked = value } })
                ).toggleStyle(.checkbox)
                Toggle(
                    tr("隐藏图形"),
                    isOn: Binding(
                        get: { node.isHidden },
                        set: { value in session.updateNode(node.id, name: "显示或隐藏图形") { $0.isHidden = value } })
                ).toggleStyle(.checkbox)
                Button(tr("就地复制")) { session.duplicateSelection() }
                Button(tr("移入回收箱"), role: .destructive) { session.deleteSelection() }.disabled(
                    session.diagram.isLocked(node))
            }.font(.system(size: 11))
        }
    }
    private func number(_ label: String, _ value: Double, _ field: Int) -> some View {
        CommitField(label: label, value: String(format: "%.0f", value)) { text in
            guard let n = Double(text), n.isFinite else {
                session.errorMessage = "请输入有效数字。"
                return
            }
            session.updateNode(node.id, name: "调整图形") { p in
                switch field {
                case 0: p.frame.x = n
                case 1: p.frame.y = n
                case 2: p.frame.width = n
                default: p.frame.height = n
                }
            }
        }
    }
}
private struct UMLDetailsEditor: View {
    let node: DiagramNode
    let session: DocumentSession
    @State private var attributes = ""
    @State private var operations = ""
    @State private var stereotype = ""
    var body: some View {
        InspectorSection("UML 成员") {
            TextField(tr("构造型（可选）"), text: $stereotype).textFieldStyle(.roundedBorder).font(.system(size: 11))
            Text(tr("属性 · 每行一个")).font(.system(size: 10)).foregroundStyle(.secondary)
            TextEditor(text: $attributes).font(.system(size: 11, design: .monospaced)).frame(height: 70).border(
                Color.primary.opacity(0.1))
            Text(tr("操作 · 每行一个")).font(.system(size: 10)).foregroundStyle(.secondary)
            TextEditor(text: $operations).font(.system(size: 11, design: .monospaced)).frame(height: 70).border(
                Color.primary.opacity(0.1))
            Button(tr("应用成员修改")) {
                session.updateNode(node.id, name: "编辑 UML 成员") { n in
                    n.attributes = attributes.components(separatedBy: .newlines).filter { !$0.isEmpty }
                    n.operations = operations.components(separatedBy: .newlines).filter { !$0.isEmpty }
                    n.stereotype = stereotype.isEmpty ? nil : stereotype
                }
            }.font(.system(size: 11))
        }.onAppear { sync() }.onChange(of: node.attributes) { _, _ in sync() }.onChange(of: node.operations) { _, _ in
            sync()
        }.onChange(of: node.stereotype) { _, _ in sync() }
    }
    private func sync() {
        attributes = (node.attributes ?? []).joined(separator: "\n")
        operations = (node.operations ?? []).joined(separator: "\n")
        stereotype = node.stereotype ?? ""
    }
}
private struct CommitField: View {
    let label: String
    let value: String
    let onCommit: (String) -> Void
    @State private var draft = ""
    @FocusState private var focused: Bool
    var body: some View {
        HStack(spacing: 8) {
            Text(tr(label)).font(.system(size: 10)).foregroundStyle(.secondary).frame(minWidth: 12, alignment: .leading)
            TextField(tr(label), text: $draft).textFieldStyle(.roundedBorder).font(.system(size: 11)).focused($focused)
                .onAppear { draft = value }.onChange(of: value) { _, new in if !focused { draft = new } }.onSubmit {
                    commit()
                }.onChange(of: focused) { _, new in if !new { commit() } }.onExitCommand {
                    draft = value
                    focused = false
                }
        }
    }
    private func commit() {
        if draft != value { onCommit(draft) }
        draft = value
    }
}

/// 承载「重命名页面」弹窗的目标页面 ID，满足 SwiftUI `.sheet(item:)` 的 Identifiable 约束。
private struct PageRenameRequest: Identifiable {
    let id: UUID
}

/// 缩放百分比可直接输入：聚焦时编辑数字，回车或失焦应用，夹取到 5%–800%。
private struct ZoomControl: View {
    @Bindable var session: DocumentSession
    @State private var text = ""
    @State private var editing = false
    @FocusState private var focused: Bool
    private var percent: Int { Int((session.camera.scale * 100).rounded()) }
    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.plain)
            .multilineTextAlignment(.center)
            .font(.system(size: 10).monospacedDigit())
            .frame(width: 42)
            .focused($focused)
            .onSubmit { apply() }
            .onAppear { text = "\(percent)%" }
            .onChange(of: focused) { _, now in
                editing = now
                if now { text = "\(percent)" } else { apply() }
            }
            .onChange(of: session.camera.scale) { _, _ in if !editing { text = "\(percent)%" } }
            .help(tr("输入缩放百分比后回车"))
    }
    private func apply() {
        let digits = text.filter { $0.isNumber }
        guard let value = Int(digits), (5...800).contains(value) else {
            text = "\(percent)%"
            return
        }
        session.camera.zoom(to: Double(value) / 100, at: session.screenCenter)
        text = "\(percent)%"
    }
}
