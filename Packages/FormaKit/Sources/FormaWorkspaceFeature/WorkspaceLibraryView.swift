import FormaApplication
import FormaDesignSystem
import FormaLocalization
import SwiftUI
import UniformTypeIdentifiers

public struct WorkspaceLibraryView: View {
    @Bindable var library: WorkspaceLibrary
    @AppStorage("Forma.workspaceSidebarCollapsed") private var sidebarCollapsed = false
    @AppStorage("Forma.collapsedWorkspacePages") private var collapsedPageStorage = ""
    @State private var sidebarToggleHovered = false
    @State private var naming: NamingRequest?
    @State private var confirmingEmptyTrash = false
    @State private var draggedPageID: UUID?
    @State private var pageDropHint: PageDropHint?
    @State private var editingWorkspace = false
    @State private var confirmingDeleteWorkspace = false
    @AppStorage("Forma.workspaceFileLayout") private var fileLayout = WorkspaceFileLayout.list.rawValue
    @AppStorage("Forma.workspaceFileSort") private var fileSort = WorkspaceFileSort.modifiedNewest.rawValue
    @AppStorage("Forma.favoriteWorkspaceFiles") private var favoriteWorkspaceFiles = ""
    @State private var hoveredFileID: UUID?
    @State private var filePendingPermanentDeletion: WorkspaceFile?
    @FocusState private var searchFocused: Bool
    public init(library: WorkspaceLibrary) { self.library = library }
    public var body: some View {
        HStack(spacing: 0) {
            if !sidebarCollapsed {
                VStack(alignment: .leading, spacing: 20) {
                    Menu {
                        Section(tr("切换工作空间")) {
                            ForEach(library.workspaces) { workspace in
                                Button {
                                    library.showingTrash = false
                                    Task { await library.select(workspace.id) }
                                } label: {
                                    if library.selectedWorkspaceID == workspace.id {
                                        Label(workspace.name, systemImage: "checkmark")
                                    } else {
                                        Label(workspace.name, systemImage: workspace.symbol)
                                    }
                                }
                            }
                        }
                        Divider()
                        Button(tr("新建工作空间…")) {
                            naming = NamingRequest(kind: .createWorkspace, title: "新建工作空间", initial: "")
                        }
                        Button(tr("编辑当前工作空间…")) { editingWorkspace = true }
                        Button(tr("在 Finder 中显示")) {
                            if let id = library.selectedWorkspaceID { library.revealWorkspaceAction?(id) }
                        }
                        Button(tr("刷新")) { Task { await library.reload() } }
                        Divider()
                        Button(tr("备份所有工作空间…")) { library.backupAction?() }
                        Button(tr("从备份恢复…")) { library.restoreBackupAction?() }
                        Divider()
                        Button(tr("删除当前工作空间…"), role: .destructive) { confirmingDeleteWorkspace = true }
                            .disabled(library.workspaces.count <= 1)
                    } label: {
                        VStack(spacing: 7) {
                            HStack(spacing: 8) {
                                Image(systemName: library.currentWorkspace?.symbol ?? "square.stack.3d.up.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                Text(library.currentName).lineLimit(1).font(.system(size: 17, weight: .bold))
                            }.foregroundStyle(.primary)
                            if let summary = library.currentWorkspace?.summary, !summary.isEmpty {
                                Text(summary).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
                                    .multilineTextAlignment(.center)
                            }
                            Text(String(format: tr("%d 个图表"), library.workspaceFiles.count))
                                .font(.system(size: 9, weight: .medium).monospacedDigit()).foregroundStyle(.tertiary)
                        }.frame(maxWidth: .infinity)
                    }.menuStyle(.borderlessButton).menuIndicator(.hidden)
                        .contextMenu {
                            Section(tr("切换工作空间")) {
                                ForEach(library.workspaces) { workspace in
                                    Button {
                                        library.showingTrash = false
                                        Task { await library.select(workspace.id) }
                                    } label: {
                                        Label(
                                            workspace.name,
                                            systemImage: library.selectedWorkspaceID == workspace.id
                                                ? "checkmark" : workspace.symbol)
                                    }
                                }
                            }
                            Divider()
                            Button(tr("新建工作空间…")) {
                                naming = NamingRequest(kind: .createWorkspace, title: "新建工作空间", initial: "")
                            }
                            Button(tr("编辑当前工作空间…")) { editingWorkspace = true }
                            Button(tr("在 Finder 中显示")) {
                                if let id = library.selectedWorkspaceID { library.revealWorkspaceAction?(id) }
                            }
                            Button(tr("刷新")) { Task { await library.reload() } }
                            Divider()
                            Button(tr("备份所有工作空间…")) { library.backupAction?() }
                            Button(tr("从备份恢复…")) { library.restoreBackupAction?() }
                            Divider()
                            Button(tr("删除当前工作空间…"), role: .destructive) { confirmingDeleteWorkspace = true }
                                .disabled(library.workspaces.count <= 1)
                        }
                        .onDrop(of: [UTType.text], isTargeted: nil) { _ in
                            guard let draggedPageID else { return false }
                            Task { await library.movePage(draggedPageID, under: nil) }
                            self.draggedPageID = nil
                            return true
                        }
                    Menu {
                        Button {
                            if let id = library.selectedWorkspaceID { library.createAction?("blank", id) }
                        } label: {
                            Label(tr("空白画布"), systemImage: "doc.badge.plus")
                        }
                        Divider()
                        Section(tr("从模板创建")) {
                            ForEach(library.templates.filter { $0.id != "blank" }) { template in
                                Button {
                                    if let id = library.selectedWorkspaceID {
                                        library.createAction?(template.id, id)
                                    }
                                } label: {
                                    Label(tr(template.title), systemImage: template.symbol)
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "plus").font(.system(size: 14, weight: .semibold))
                            Text(tr("新建图表")).font(.system(size: 13, weight: .semibold))
                            Spacer()
                            Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).opacity(0.8)
                        }.foregroundStyle(.white).padding(.horizontal, 14).frame(height: 44)
                            .background(FormaTheme.accent, in: RoundedRectangle(cornerRadius: 10))
                    }.menuStyle(.borderlessButton).menuIndicator(.hidden)
                        .disabled(library.selectedWorkspaceID == nil || library.isBusy)
                    Button {
                        Task { await library.showAllFiles() }
                    } label: {
                        HStack {
                            Text(tr("全部图表")).font(.system(size: 10, weight: .semibold))
                            Spacer()
                            Text("\(library.workspaceFiles.count)").font(.system(size: 10).monospacedDigit())
                        }.foregroundStyle(
                            library.activeSession == nil && !library.showingTrash ? FormaTheme.accent : Color.secondary
                        )
                        .padding(.horizontal, 10).frame(height: 30).contentShape(Rectangle())
                        .background(
                            library.activeSession == nil && !library.showingTrash
                                ? FormaTheme.accent.opacity(0.10) : .clear,
                            in: RoundedRectangle(cornerRadius: 7))
                    }.buttonStyle(.plain)
                    HStack(spacing: 12) {
                        Button(tr("全部折叠")) {
                            collapsedPageStorage = collapsedPageIDs.union(
                                library.workspaceFiles.filter { childCount(of: $0) > 0 }.map(\.id)
                            ).map(\.uuidString).sorted().joined(separator: ",")
                        }
                        Button(tr("全部展开")) {
                            collapsedPageStorage = collapsedPageIDs.subtracting(library.workspaceFiles.map(\.id)).map(
                                \.uuidString
                            ).sorted().joined(separator: ",")
                        }
                        Spacer(minLength: 0)
                    }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(visibleTreeItems, id: \.element.id) { index, item in
                                Button {
                                    openFile(item.file)
                                } label: {
                                    HStack(spacing: 7) {
                                        Image(systemName: childCount(of: item.file) > 0 ? "folder.fill" : "doc.text")
                                            .font(.system(size: 11))
                                            .foregroundStyle(
                                                childCount(of: item.file) > 0 ? FormaTheme.accent : .primary)
                                        Text(item.file.title).lineLimit(1).font(.system(size: 12))
                                        Spacer()
                                        if isFavorite(item.file) {
                                            Image(systemName: "star.fill").font(.system(size: 8)).foregroundStyle(
                                                FormaTheme.accent)
                                        }
                                        if item.file.pageCount > 1 {
                                            Text("\(item.file.pageCount)").font(.system(size: 9).monospacedDigit())
                                                .foregroundStyle(.tertiary)
                                        }
                                        if childCount(of: item.file) > 0 {
                                            Text("\(childCount(of: item.file))").font(
                                                .system(size: 9).monospacedDigit()
                                            )
                                            .foregroundStyle(.tertiary)
                                        }
                                    }.padding(.leading, 27 + CGFloat(item.depth * 16)).padding(.trailing, 10)
                                        .padding(.vertical, 6).contentShape(Rectangle())
                                }
                                .buttonStyle(.plain).foregroundStyle(.primary)
                                .overlay(alignment: .leading) {
                                    if childCount(of: item.file) > 0 {
                                        Button {
                                            togglePage(item.file.id)
                                        } label: {
                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 9, weight: .semibold))
                                                .rotationEffect(
                                                    .degrees(collapsedPageIDs.contains(item.file.id) ? 0 : 90)
                                                )
                                                .foregroundStyle(.secondary).frame(width: 22, height: 26)
                                                .contentShape(Rectangle())
                                        }.buttonStyle(.plain)
                                            .help(tr(collapsedPageIDs.contains(item.file.id) ? "展开子项" : "折叠子项"))
                                            .accessibilityLabel(
                                                tr(collapsedPageIDs.contains(item.file.id) ? "展开子项" : "折叠子项") + " "
                                                    + item.file.title
                                            )
                                            .padding(.leading, CGFloat(item.depth * 16))
                                    }
                                }
                                .onDrag {
                                    draggedPageID = item.file.id
                                    return NSItemProvider(object: item.file.id.uuidString as NSString)
                                }
                                .background(
                                    pageDropHint?.targetID == item.file.id && pageDropHint?.position == .inside
                                        ? FormaTheme.accent.opacity(0.12) : .clear,
                                    in: RoundedRectangle(cornerRadius: 6)
                                )
                                .overlay(alignment: .top) {
                                    if pageDropHint?.targetID == item.file.id && pageDropHint?.position == .before {
                                        Rectangle().fill(FormaTheme.accent).frame(height: 2)
                                    }
                                }
                                .overlay(alignment: .bottom) {
                                    if pageDropHint?.targetID == item.file.id && pageDropHint?.position == .after {
                                        Rectangle().fill(FormaTheme.accent).frame(height: 2)
                                    }
                                }
                                .onDrop(
                                    of: [UTType.text],
                                    delegate: PageHierarchyDropDelegate(
                                        targetID: item.file.id, draggedPageID: $draggedPageID,
                                        hint: $pageDropHint, library: library)
                                )
                                .contextMenu {
                                    fileContextMenu(item.file)
                                    Divider()
                                    if let parentID = item.file.parentID {
                                        Button(tr("左移一级")) {
                                            Task {
                                                await library.repositionPage(
                                                    item.file.id, relativeTo: parentID, position: .after)
                                            }
                                        }
                                    }
                                    if let previous = previousSibling(
                                        before: index, depth: item.depth, parentID: item.file.parentID)
                                    {
                                        Button(tr("右移一级")) {
                                            Task {
                                                await library.repositionPage(
                                                    item.file.id, relativeTo: previous.file.id, position: .inside)
                                            }
                                        }
                                    }
                                    if item.depth > 0 {
                                        Button(tr("移到顶层")) { Task { await library.movePage(item.file.id, under: nil) } }
                                    }
                                }
                                .background(
                                    library.activeFileURL?.standardizedFileURL == item.file.url.standardizedFileURL
                                        ? FormaTheme.accent.opacity(0.12) : .clear,
                                    in: RoundedRectangle(cornerRadius: 6)
                                )
                                .help(tr("拖动页面以建立层级关系"))
                            }
                        }
                    }
                    if !favoriteFiles.isEmpty {
                        VStack(alignment: .leading, spacing: 7) {
                            Label(tr("收藏"), systemImage: "star.fill")
                                .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                            ForEach(favoriteFiles.prefix(3)) { file in
                                Button {
                                    openFile(file)
                                } label: {
                                    HStack(spacing: 7) {
                                        Image(systemName: "doc.text").foregroundStyle(FormaTheme.accent)
                                        Text(file.title).lineLimit(1)
                                        Spacer()
                                    }.font(.system(size: 11)).padding(.vertical, 3)
                                }.buttonStyle(.plain).contextMenu { fileContextMenu(file) }
                            }
                        }
                    }
                    Divider()
                    Button {
                        let visible = !library.showingTrash
                        Task { await library.setTrashVisible(visible) }
                    } label: {
                        sidebarUtilityLabel(
                            "回收箱", symbol: library.showingTrash ? "trash.fill" : "trash",
                            selected: library.showingTrash)
                    }.buttonStyle(.plain)
                    Button {
                        library.settingsAction?()
                    } label: {
                        sidebarUtilityLabel("设置", symbol: "gearshape", selected: false)
                    }.buttonStyle(.plain)
                    Label(tr("本机存储 · 无需登录"), systemImage: "internaldrive").font(.system(size: 10)).foregroundStyle(
                        .tertiary
                    )
                    .padding(.bottom, 18)
                }.padding(.horizontal, 18).padding(.top, 42).frame(width: 220).background(FormaTheme.panel)
                    .overlay(alignment: .topTrailing) {
                        sidebarToggle.padding(.top, 8).padding(.trailing, 8)
                    }
            } else {
                VStack(spacing: 0) {
                    sidebarToggle.padding(.top, 10)
                    Spacer(minLength: 0)
                }.frame(width: 44).background(FormaTheme.panel)
            }
            Divider()
            if let session = library.activeSession, !library.showingTrash, session.showSidebar {
                WorkspaceView(session: session).sidebarContent
                    .padding(.top, 22)
                    .frame(width: 224)
                    .background(FormaTheme.panel)
                Divider()
            }
            VStack(alignment: .leading, spacing: 0) {
                if library.showingTrash {
                    HStack {
                        Text(tr("回收箱")).font(.system(size: 18, weight: .semibold))
                        Spacer()
                        Button(tr("全部恢复")) { Task { await library.restoreAll() } }.disabled(
                            library.visibleFiles.isEmpty || library.isBusy)
                        Button(tr("清空回收箱"), role: .destructive) { confirmingEmptyTrash = true }.disabled(
                            library.visibleFiles.isEmpty || library.isBusy)
                    }.padding(.horizontal, 28).padding(.top, 24)
                }
                if library.activeSession == nil || library.showingTrash {
                    HStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 7) {
                                Text(tr(library.showingTrash ? "可恢复的图表" : "全部图表"))
                                    .font(.system(size: 14, weight: .semibold))
                                Text("\(library.visibleFiles.count)").font(
                                    .system(size: 10, weight: .medium).monospacedDigit()
                                )
                                .foregroundStyle(.secondary).padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.primary.opacity(0.06), in: Capsule())
                            }
                            Text(tr(library.showingTrash ? "按需恢复或永久清理文件" : "浏览、搜索和管理工作空间中的图表"))
                                .font(.system(size: 10)).foregroundStyle(.tertiary)
                        }
                        Spacer(minLength: 24)
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                            TextField(tr("搜索图表"), text: $library.search)
                                .textFieldStyle(.plain).font(.system(size: 12)).focused($searchFocused)
                            if !library.search.isEmpty {
                                Button {
                                    library.search = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                                }.buttonStyle(.plain)
                            }
                        }.padding(.horizontal, 11).frame(width: 236, height: 34)
                            .background(
                                Color.primary.opacity(searchFocused ? 0.055 : 0.035),
                                in: RoundedRectangle(cornerRadius: 10)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10).strokeBorder(
                                    searchFocused ? FormaTheme.accent.opacity(0.55) : Color.primary.opacity(0.07)))
                        HStack(spacing: 2) {
                            Menu {
                                ForEach(WorkspaceFileSort.allCases) { option in
                                    Button {
                                        fileSort = option.rawValue
                                    } label: {
                                        if selectedFileSort == option {
                                            Label(tr(option.title), systemImage: "checkmark")
                                        } else {
                                            Text(tr(option.title))
                                        }
                                    }
                                }
                            } label: {
                                Image(systemName: "arrow.up.arrow.down").frame(width: 30, height: 28)
                            }.menuStyle(.borderlessButton).menuIndicator(.hidden).help(tr("排序"))
                            Divider().frame(height: 18).padding(.horizontal, 2)
                            layoutButton(.list, systemName: "list.bullet")
                            layoutButton(.grid, systemName: "square.grid.2x2")
                        }.padding(3)
                            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.055)))
                    }.padding(.horizontal, 28)
                        .padding(.top, library.showingTrash ? 14 : 28)
                        .padding(.bottom, 16)
                    Divider().padding(.horizontal, 28)
                }
                if let session = library.activeSession, !library.showingTrash {
                    VStack(spacing: 0) {
                        HStack(spacing: 10) {
                            Spacer()
                            ForEach([CanvasTool.select, .rounded, .connector, .text, .panel, .hand], id: \.self) {
                                tool in
                                Button {
                                    session.tool = tool
                                } label: {
                                    Image(systemName: tool.symbol).frame(width: 28, height: 26)
                                        .foregroundStyle(session.tool == tool ? FormaTheme.accent : .secondary)
                                        .background(
                                            session.tool == tool ? FormaTheme.accent.opacity(0.12) : .clear,
                                            in: RoundedRectangle(cornerRadius: 6))
                                }.buttonStyle(.plain).help(tr(tool.title))
                            }
                            Divider().frame(height: 18)
                            Button {
                                session.undoManager?.undo()
                            } label: {
                                Image(systemName: "arrow.uturn.backward").frame(width: 24, height: 26)
                            }.buttonStyle(.plain).disabled(session.undoManager?.canUndo != true).help(tr("撤销"))
                            Button {
                                session.undoManager?.redo()
                            } label: {
                                Image(systemName: "arrow.uturn.forward").frame(width: 24, height: 26)
                            }.buttonStyle(.plain).disabled(session.undoManager?.canRedo != true).help(tr("重做"))
                            Button {
                                session.showInspector.toggle()
                            } label: {
                                Image(systemName: "sidebar.right").frame(width: 24, height: 26)
                            }.buttonStyle(.plain).help(tr("检查器"))
                            if let url = library.activeFileURL {
                                Button {
                                    library.openInNewWindowAction?(url)
                                } label: {
                                    Image(systemName: "macwindow.on.rectangle").frame(width: 24, height: 26)
                                }.buttonStyle(.plain).help(tr("在新窗口打开"))
                            }
                        }.padding(.horizontal, 16).frame(height: 42).background(FormaTheme.panel)
                        Divider()
                        WorkspaceView(session: session, showsOwnSidebar: false)
                            .id(library.activeFileURL)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else if library.visibleFiles.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: library.showingTrash ? "trash" : "doc.badge.plus").font(
                            .system(size: 36, weight: .ultraLight)
                        ).foregroundStyle(FormaTheme.gradient)
                        Text(tr(library.search.isEmpty ? (library.showingTrash ? "回收箱是空的" : "从一张好图开始") : "没有匹配的图表"))
                            .font(.system(size: 18, weight: .medium))
                        Text(tr(library.showingTrash ? "移入回收箱的文档会保留在本机，直到你恢复它们。" : "选择上方的模板，或将编辑器中的文档副本存入当前工作空间。"))
                            .font(
                                .system(size: 12)
                            ).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        if selectedFileLayout == .grid {
                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 250, maximum: 360), spacing: 16)],
                                alignment: .leading,
                                spacing: 16
                            ) {
                                ForEach(sortedVisibleFiles) { file in fileCard(file).disabled(library.isBusy) }
                            }.padding(28)
                        } else {
                            LazyVStack(spacing: 0) {
                                fileListHeader
                                ForEach(sortedVisibleFiles) { file in
                                    fileRow(file).disabled(library.isBusy)
                                    Divider().padding(.leading, 58)
                                }
                            }.padding(.horizontal, 28).padding(.vertical, 14)
                        }
                    }
                }
            }.background(Color(nsColor: .textBackgroundColor))
        }.transaction { transaction in
            // 导航会替换大块画布、侧栏和列表；禁用隐式过渡，避免条件视图交叉淡入淡出造成闪烁。
            transaction.animation = nil
            transaction.disablesAnimations = true
        }.environment(\.locale, Locale(identifier: Localization.shared.language.identifier)).tint(FormaTheme.accent)
            .frame(minWidth: 960, minHeight: 640)
            .task { await library.reload() }
            .task(id: pageDropHint?.refreshID) {
                guard pageDropHint != nil else { return }
                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled else { return }
                pageDropHint = nil
            }
            .alert(
                tr("无法完成操作"),
                isPresented: Binding(
                    get: { library.errorMessage != nil }, set: { if !$0 { library.errorMessage = nil } })
            ) {
                Button(tr("好")) { library.errorMessage = nil }
            } message: {
                Text(tr(library.errorMessage ?? ""))
            }
            .alert(
                tr("操作完成"),
                isPresented: Binding(
                    get: { library.noticeMessage != nil }, set: { if !$0 { library.noticeMessage = nil } })
            ) {
                Button(tr("好")) { library.noticeMessage = nil }
            } message: {
                Text(library.noticeMessage ?? "")
            }
            .sheet(isPresented: $confirmingEmptyTrash) {
                VStack(alignment: .leading, spacing: 20) {
                    Text(tr("清空回收箱")).font(.system(size: 19, weight: .semibold))
                    Text(
                        String(
                            format: tr("将永久删除回收箱中的 %d 个图表，此操作无法撤销。"),
                            library.visibleFiles.count)
                    ).font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    HStack {
                        Spacer()
                        Button(tr("取消")) { confirmingEmptyTrash = false }
                        Button(tr("永久删除"), role: .destructive) {
                            confirmingEmptyTrash = false
                            Task { await library.emptyTrash() }
                        }.disabled(library.isBusy)
                    }
                }.padding(28).frame(width: 400)
            }
            .sheet(item: $naming) { request in
                NamingSheet(title: request.title, initial: request.initial) { value in
                    naming = nil
                    Task {
                        switch request.kind {
                        case .createWorkspace: await library.createWorkspace(value)
                        case .renameWorkspace: await library.renameWorkspace(value)
                        case .renameFile: if let file = request.file { await library.rename(file, title: value) }
                        }
                    }
                }
            }
            .sheet(isPresented: $editingWorkspace) {
                if let workspace = library.currentWorkspace {
                    WorkspaceProfileSheet(workspace: workspace) { name, symbol, summary in
                        editingWorkspace = false
                        Task { await library.updateWorkspace(name: name, symbol: symbol, summary: summary) }
                    }
                }
            }
            .sheet(isPresented: $confirmingDeleteWorkspace) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 12) {
                        Image(systemName: "trash.fill").font(.system(size: 22)).foregroundStyle(.red)
                        Text(tr("删除工作空间")).font(.system(size: 20, weight: .semibold))
                    }
                    Text(
                        String(
                            format: tr("将永久删除工作空间「%@」及其中的 %d 个图表。此操作无法撤销。"),
                            library.currentName, library.workspaceFiles.count)
                    ).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Spacer()
                        Button(tr("取消")) { confirmingDeleteWorkspace = false }
                        Button(tr("删除"), role: .destructive) {
                            confirmingDeleteWorkspace = false
                            Task { await library.deleteCurrentWorkspace() }
                        }.disabled(library.isBusy || library.workspaces.count <= 1)
                    }
                }.padding(28).frame(width: 430)
            }
            .sheet(item: $filePendingPermanentDeletion) { file in
                VStack(alignment: .leading, spacing: 18) {
                    Text(tr("永久删除图表")).font(.system(size: 20, weight: .semibold))
                    Text(String(format: tr("将永久删除图表「%@」。此操作无法撤销。"), file.title))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    HStack {
                        Spacer()
                        Button(tr("取消")) { filePendingPermanentDeletion = nil }
                        Button(tr("永久删除"), role: .destructive) {
                            filePendingPermanentDeletion = nil
                            Task { await library.permanentlyDelete(file) }
                        }.keyboardShortcut(.defaultAction)
                    }
                }.padding(28).frame(width: 410)
            }
    }
    private func previousSibling(before index: Int, depth: Int, parentID: UUID?) -> WorkspaceTreeItem? {
        guard index > 0 else { return nil }
        return library.workspaceTree[..<index].last { $0.depth == depth && $0.file.parentID == parentID }
    }
    private var collapsedPageIDs: Set<UUID> {
        Set(collapsedPageStorage.split(separator: ",").compactMap { UUID(uuidString: String($0)) })
    }
    private func togglePage(_ id: UUID) {
        var ids = collapsedPageIDs
        if !ids.insert(id).inserted { ids.remove(id) }
        collapsedPageStorage = ids.map(\.uuidString).sorted().joined(separator: ",")
    }
    private var visibleTreeItems: [(offset: Int, element: WorkspaceTreeItem)] {
        let parents = Dictionary(uniqueKeysWithValues: library.workspaceFiles.map { ($0.id, $0.parentID) })
        let collapsed = collapsedPageIDs
        return Array(library.workspaceTree.enumerated()).filter { _, item in
            var parent = item.file.parentID
            var visited = Set<UUID>()
            while let id = parent, visited.insert(id).inserted {
                if collapsed.contains(id) { return false }
                parent = parents[id] ?? nil
            }
            return true
        }
    }
    private var sidebarToggle: some View {
        Button {
            sidebarToggleHovered = false
            sidebarCollapsed.toggle()
        } label: {
            Image(systemName: "sidebar.left")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(sidebarToggleHovered ? FormaTheme.accent : Color.secondary)
                .frame(width: 28, height: 26)
                .background(
                    sidebarToggleHovered ? FormaTheme.accent.opacity(0.09) : Color.primary.opacity(0.035),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color.primary.opacity(sidebarToggleHovered ? 0.08 : 0.045), lineWidth: 0.5)
                }
                .contentShape(RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(.plain)
            .onHover { sidebarToggleHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: sidebarToggleHovered)
            .help(tr(sidebarCollapsed ? "展开文件侧栏" : "折叠文件侧栏"))
            .accessibilityLabel(tr(sidebarCollapsed ? "展开文件侧栏" : "折叠文件侧栏"))
    }
    private func sidebarUtilityLabel(_ title: String, symbol: String, selected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).frame(width: 18, alignment: .center)
            Text(tr(title))
            Spacer()
        }.font(.system(size: 12)).padding(.horizontal, 10).frame(height: 38)
            .background(selected ? FormaTheme.accent.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
    }
    private func childCount(of file: WorkspaceFile) -> Int {
        library.workspaceFiles.lazy.filter { $0.parentID == file.id }.count
    }
    private var selectedFileLayout: WorkspaceFileLayout { WorkspaceFileLayout(rawValue: fileLayout) ?? .list }
    private func layoutButton(_ layout: WorkspaceFileLayout, systemName: String) -> some View {
        Button {
            fileLayout = layout.rawValue
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 30, height: 28)
                .foregroundStyle(selectedFileLayout == layout ? Color.white : Color.secondary)
                .background(
                    selectedFileLayout == layout ? FormaTheme.accent : Color.clear,
                    in: RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(.plain).help(tr(layout == .list ? "列表视图" : "网格视图"))
    }
    private var favoriteIDs: Set<UUID> {
        Set(favoriteWorkspaceFiles.split(separator: ",").compactMap { UUID(uuidString: String($0)) })
    }
    private var favoriteFiles: [WorkspaceFile] {
        library.workspaceFiles.filter { favoriteIDs.contains($0.id) }.sorted { $0.modifiedAt > $1.modifiedAt }
    }
    private func isFavorite(_ file: WorkspaceFile) -> Bool { favoriteIDs.contains(file.id) }
    private func toggleFavorite(_ file: WorkspaceFile) {
        var values = favoriteIDs
        if values.contains(file.id) { values.remove(file.id) } else { values.insert(file.id) }
        favoriteWorkspaceFiles = values.map(\.uuidString).sorted().joined(separator: ",")
    }
    private var selectedFileSort: WorkspaceFileSort { WorkspaceFileSort(rawValue: fileSort) ?? .modifiedNewest }
    private var sortedVisibleFiles: [WorkspaceFile] {
        library.visibleFiles.sorted {
            switch selectedFileSort {
            case .modifiedNewest: $0.modifiedAt > $1.modifiedAt
            case .modifiedOldest: $0.modifiedAt < $1.modifiedAt
            case .nameAscending: $0.title.localizedStandardCompare($1.title) == .orderedAscending
            case .nameDescending: $0.title.localizedStandardCompare($1.title) == .orderedDescending
            }
        }
    }
    private var fileListHeader: some View {
        HStack {
            Text(tr("名称")).frame(maxWidth: .infinity, alignment: .leading)
            Text(tr("更新时间")).frame(width: 150, alignment: .leading)
            Text(tr("操作")).frame(width: 76, alignment: .trailing)
        }.font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary).padding(.horizontal, 12)
            .padding(.bottom, 8)
    }
    private func fileRow(_ file: WorkspaceFile) -> some View {
        HStack(spacing: 12) {
            Image(systemName: file.isTrashed ? "doc.badge.clock" : "point.3.connected.trianglepath.dotted")
                .font(.system(size: 18, weight: .light)).foregroundStyle(FormaTheme.gradient).frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(file.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text(
                    String(
                        format: tr(file.pageCount == 1 ? "%d 个 Sheet" : "%d 个 Sheets"),
                        file.pageCount)
                )
                .font(.system(size: 9)).foregroundStyle(.tertiary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Text(formattedDate(file.modifiedAt)).font(.system(size: 10)).foregroundStyle(.secondary)
                .frame(width: 150, alignment: .leading)
            HStack(spacing: 8) {
                if file.isTrashed {
                    Button(tr("恢复")) { Task { await library.restore(file) } }.buttonStyle(.borderless)
                } else if hoveredFileID == file.id {
                    Button(tr("打开")) { openFile(file) }.buttonStyle(.borderless)
                }
                fileActionMenu(file)
            }.frame(width: 76, alignment: .trailing)
        }.padding(.horizontal, 12).frame(height: 58).contentShape(Rectangle())
            .background(
                hoveredFileID == file.id ? FormaTheme.accent.opacity(0.055) : .clear,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .onHover { hoveredFileID = $0 ? file.id : nil }
            .onTapGesture(count: 2) { if !file.isTrashed { openFile(file) } }
            .contextMenu { fileContextMenu(file) }
    }
    private func formattedDate(_ date: Date) -> String {
        date.formatted(
            .dateTime.year().month(.abbreviated).day().hour().minute().locale(
                Locale(identifier: Localization.shared.language.identifier)))
    }
    @ViewBuilder private func fileActionMenu(_ file: WorkspaceFile) -> some View {
        Menu {
            fileContextMenu(file)
        } label: {
            Image(systemName: "ellipsis").frame(width: 22, height: 22)
        }.menuStyle(.borderlessButton).menuIndicator(.hidden).help(tr("更多操作"))
    }
    @ViewBuilder private func fileContextMenu(_ file: WorkspaceFile) -> some View {
        if file.isTrashed {
            Button(tr("恢复")) { Task { await library.restore(file) } }
            Divider()
            Button(tr("永久删除…"), role: .destructive) { filePendingPermanentDeletion = file }
        } else {
            Button(tr("打开")) { openFile(file) }
            Button(tr("在新窗口打开")) { library.openInNewWindowAction?(file.url) }
                .disabled(library.openInNewWindowAction == nil)
            Button(tr("重命名…")) {
                naming = NamingRequest(kind: .renameFile, title: "重命名图表", initial: file.title, file: file)
            }
            Button(tr("创建副本")) { Task { await library.duplicate(file) } }
            Button(tr(isFavorite(file) ? "从收藏移除" : "添加到收藏")) { toggleFavorite(file) }
            Button(tr("在 Finder 中显示")) { library.revealFileAction?(file.url) }
            Menu(tr("移动到")) {
                ForEach(library.workspaces.filter { $0.id != file.workspaceID }) { space in
                    Button(space.name) { Task { await library.move(file, to: space.id) } }
                }
            }
            Divider()
            Button(tr("移入回收箱"), role: .destructive) { Task { await library.trash(file) } }
        }
    }
    private func fileCard(_ file: WorkspaceFile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: file.isTrashed ? "doc.badge.clock" : "point.3.connected.trianglepath.dotted").font(
                    .system(size: 22, weight: .light)
                ).foregroundStyle(FormaTheme.gradient)
                Spacer()
                if file.isTrashed {
                    Button(tr("恢复")) { Task { await library.restore(file) } }.buttonStyle(.bordered).controlSize(.small)
                } else {
                    fileActionMenu(file)
                }
            }.frame(height: 28)
            Text(file.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
            HStack(spacing: 7) {
                Text(String(format: tr(file.pageCount == 1 ? "%d 个 Sheet" : "%d 个 Sheets"), file.pageCount))
                Circle().frame(width: 3, height: 3)
                Text(formattedDate(file.modifiedAt))
                Spacer(minLength: 8)
                if !file.isTrashed && hoveredFileID == file.id {
                    Text(tr("打开")).fontWeight(.medium).foregroundStyle(FormaTheme.accent)
                }
            }.font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1)
        }.padding(16).frame(maxWidth: .infinity, minHeight: 112, maxHeight: 112, alignment: .leading)
            .background(
                hoveredFileID == file.id ? FormaTheme.accent.opacity(0.055) : FormaTheme.panel,
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12).strokeBorder(
                    hoveredFileID == file.id ? FormaTheme.accent.opacity(0.35) : Color.primary.opacity(0.07))
            )
            .onHover { hoveredFileID = $0 ? file.id : nil }
            .onTapGesture(count: 2) { if !file.isTrashed { openFile(file) } }
            .contextMenu { fileContextMenu(file) }
    }
    private func openFile(_ file: WorkspaceFile) {
        library.showingTrash = false
        library.openAction?(file.url)
    }
}
private enum WorkspaceFileLayout: String { case list, grid }
private enum WorkspaceFileSort: String, CaseIterable, Identifiable {
    case modifiedNewest, modifiedOldest, nameAscending, nameDescending
    var id: String { rawValue }
    var title: String {
        switch self {
        case .modifiedNewest: "最近更新"
        case .modifiedOldest: "最早更新"
        case .nameAscending: "名称 A–Z"
        case .nameDescending: "名称 Z–A"
        }
    }
}
private struct NamingRequest: Identifiable {
    enum Kind { case createWorkspace, renameWorkspace, renameFile }
    let id = UUID()
    let kind: Kind
    let title: String
    let initial: String
    var file: WorkspaceFile?
}
struct NamingSheet: View {
    let title: String
    let initial: String
    let commit: (String) -> Void
    @State private var value = ""
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(tr(title)).font(.system(size: 19, weight: .semibold))
            TextField(tr("名称"), text: $value).textFieldStyle(.roundedBorder).focused($focused).onSubmit {
                if valid { commit(value) }
            }
            HStack {
                Text(tr("1–80 个字符")).font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button(tr("取消")) { dismiss() }
                Button(tr("保存")) { commit(value) }.buttonStyle(.borderedProminent).disabled(!valid).keyboardShortcut(
                    .defaultAction)
            }
        }.padding(28).frame(width: 400).onAppear {
            value = initial
            focused = true
        }
    }
    private var valid: Bool { !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.count <= 80 }
}

private struct WorkspaceProfileSheet: View {
    private static let symbols = [
        "square.stack.3d.up.fill", "square.grid.2x2.fill", "folder.fill", "building.2.fill",
        "network", "shippingbox.fill", "lightbulb.fill", "point.3.connected.trianglepath.dotted",
    ]
    let workspace: LocalWorkspace
    let commit: (String, String, String) -> Void
    @State private var name: String
    @State private var symbol: String
    @State private var summary: String
    @Environment(\.dismiss) private var dismiss
    @FocusState private var nameFocused: Bool

    init(workspace: LocalWorkspace, commit: @escaping (String, String, String) -> Void) {
        self.workspace = workspace
        self.commit = commit
        _name = State(initialValue: workspace.name)
        _symbol = State(initialValue: workspace.symbol)
        _summary = State(initialValue: workspace.summary)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(tr("编辑工作空间")).font(.system(size: 20, weight: .semibold))
            VStack(alignment: .leading, spacing: 8) {
                Text(tr("工作空间图标")).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                HStack(spacing: 9) {
                    ForEach(Self.symbols, id: \.self) { candidate in
                        Button {
                            symbol = candidate
                        } label: {
                            Image(systemName: candidate).font(.system(size: 17)).frame(width: 34, height: 34)
                                .background(
                                    symbol == candidate ? FormaTheme.accent.opacity(0.16) : Color.primary.opacity(0.04),
                                    in: RoundedRectangle(cornerRadius: 8)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8).strokeBorder(
                                        symbol == candidate ? FormaTheme.accent : .clear, lineWidth: 1.5))
                        }.buttonStyle(.plain)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(tr("名称")).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                TextField(tr("工作空间名称"), text: $name).textFieldStyle(.roundedBorder).focused($nameFocused)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(tr("描述")).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(summary.count)/240").font(.system(size: 10).monospacedDigit()).foregroundStyle(.tertiary)
                }
                TextEditor(text: $summary).font(.system(size: 12)).scrollContentBackground(.hidden).padding(8)
                    .frame(height: 82).background(
                        Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8)
                    )
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.08)))
                    .onChange(of: summary) { _, value in
                        if value.count > 240 { summary = String(value.prefix(240)) }
                    }
            }
            HStack {
                Spacer()
                Button(tr("取消")) { dismiss() }
                Button(tr("保存")) { commit(name, symbol, summary) }.buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 80)
                    .keyboardShortcut(.defaultAction)
            }
        }.padding(28).frame(width: 460).onAppear { nameFocused = true }
    }
}

private struct PageDropHint: Equatable {
    var targetID: UUID
    var position: WorkspacePageMovePosition
    var refreshID = UUID()
}

private struct PageHierarchyDropDelegate: DropDelegate {
    let targetID: UUID
    @Binding var draggedPageID: UUID?
    @Binding var hint: PageDropHint?
    let library: WorkspaceLibrary

    func dropEntered(info: DropInfo) { updateHint(info) }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateHint(info)
        return DropProposal(operation: .move)
    }
    func dropExited(info: DropInfo) {
        if hint?.targetID == targetID { hint = nil }
    }
    func validateDrop(info: DropInfo) -> Bool { draggedPageID != nil && draggedPageID != targetID }
    func performDrop(info: DropInfo) -> Bool {
        guard let draggedPageID, draggedPageID != targetID else { return false }
        let position = position(for: info)
        self.draggedPageID = nil
        hint = nil
        Task { @MainActor in
            await library.repositionPage(draggedPageID, relativeTo: targetID, position: position)
        }
        return true
    }
    private func updateHint(_ info: DropInfo) {
        guard draggedPageID != targetID else {
            hint = nil
            return
        }
        hint = PageDropHint(targetID: targetID, position: position(for: info))
    }
    private func position(for info: DropInfo) -> WorkspacePageMovePosition {
        if info.location.y < 10 { return .before }
        if info.location.y > 24 { return .after }
        return .inside
    }
}
