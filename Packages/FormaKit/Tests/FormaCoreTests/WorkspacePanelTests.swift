import AppKit
import FormaApplication
import FormaCanvasEngine
import FormaCatalogInfrastructure
import FormaDocumentIO
import FormaDomain
import FormaGeometry
import FormaInterchange
import FormaLocalization
import Foundation
import Testing

struct FormatAndUMLTests {
    @Test func legacyV1WithoutNewFieldsMigratesInMemory() throws {
        let nodeID = "11B98F1C-1B68-4A31-849A-8253F4E65FC1"
        let documentID = "5D52CCBD-22CA-4EBB-8806-1B0A3E420701"
        let data = Data(
            """
            {"id":"\(documentID)","title":"旧版文档","nodes":[{"id":"\(nodeID)","title":"旧版图形","kind":"rounded","frame":{"x":40,"y":80,"width":168,"height":72},"color":"blue","fontSize":14,"isHidden":false,"isLocked":false}],"edges":[]}
            """.utf8)
        let manifest = Data("{\"formatVersion\":1,\"minimumReaderVersion\":1,\"documentID\":\"\(documentID)\"}".utf8)
        let wrapper = FileWrapper(directoryWithFileWrappers: [
            "manifest.json": FileWrapper(regularFileWithContents: manifest),
            "document.json": FileWrapper(regularFileWithContents: data),
        ])
        let model = try DocumentCodec.decode(wrapper).pages[0]
        #expect(model.nodes[0].title == "旧版图形")
        #expect(model.nodes[0].panelID == nil)
        #expect(model.panels.isEmpty)
        #expect(model.recycleBin.isEmpty)
        let upgraded = try DocumentCodec.encode(model)
        let current = try JSONDecoder().decode(
            DocumentManifest.self, from: upgraded.fileWrappers!["manifest.json"]!.regularFileContents!)
        #expect(current.formatVersion == 3)
        #expect(current.minimumReaderVersion == 3)
        #expect(try DocumentCodec.decode(upgraded).pages[0] == model)
    }
    @Test(arguments: [DiagramTemplate.umlClass, .umlUseCase, .umlComponent, .erDiagram, .c4Context, .panelBoard])
    func enterpriseTemplateRoundTrip(_ template: DiagramTemplate) throws {
        let diagram = template.makeDiagram()
        #expect(try DocumentCodec.decode(DocumentCodec.encode(diagram)).pages[0] == diagram)
    }
    @Test @MainActor func everyShapeHasAValidNativeSymbol() {
        for kind in ShapeKind.allCases {
            #expect(
                NSImage(systemSymbolName: kind.symbol, accessibilityDescription: nil)?.isValid == true,
                "Missing symbol: \(kind.symbol)")
        }
    }
    @Test(arguments: [DiagramTemplate.umlClass, .umlUseCase, .umlComponent, .erDiagram, .c4Context, .panelBoard])
    @MainActor func enterpriseTemplatesExport(_ template: DiagramTemplate) throws {
        let diagram = template.makeDiagram()
        let png = try DiagramExporter.png(diagram)
        let pdf = try DiagramExporter.pdf(diagram)
        #expect(NSBitmapImageRep(data: png) != nil)
        #expect(String(data: pdf.prefix(4), encoding: .ascii) == "%PDF")
    }
    @Test func classModelPreservesMembersAndRelationships() throws {
        let model = DiagramTemplate.umlClass.makeDiagram()
        #expect(model.nodes.contains { $0.kind == .umlInterface })
        #expect(model.nodes.contains { ($0.attributes ?? []).contains("- id: UUID") })
        #expect(model.edges.contains { $0.effectiveRelation == .composition })
        #expect(model.edges.contains { $0.effectiveRelation == .realization })
        #expect(try model.validated().panels.count == 1)
    }
    @Test func englishTemplatesDoNotTranslateExistingData() throws {
        let model = DiagramTemplate.umlUseCase.makeDiagram(language: .english)
        #expect(model.title == "UML use case diagram")
        #expect(model.nodes.contains { $0.title == "Customer" })
        var custom = model
        custom.nodes[0].title = "保留用户中文 Customer"
        #expect(
            try DocumentCodec.decode(DocumentCodec.encode(custom)).pages[0].nodes[0].title
                == "保留用户中文 Customer")
    }
    @Test func invalidPanelMembershipRejected() {
        var model = DiagramTemplate.architecture.makeDiagram()
        model.nodes[0].panelID = UUID()
        #expect(throws: DiagramError.self) { try model.validated() }
    }
    @Test func extendedNodeAppearancePersistsAndLegacyDefaultsRemainStable() throws {
        var model = DiagramTemplate.blank.makeDiagram()
        model.nodes = [
            DiagramNode(
                title: "Styled", frame: Rect(x: 20, y: 20, width: 180, height: 80), strokeWidth: 3.5,
                opacity: 0.65, cornerRadius: 24, textAlignment: .leading)
        ]
        let restored = try DocumentCodec.decode(DocumentCodec.encode(model)).pages[0].nodes[0]
        #expect(restored.effectiveStrokeWidth == 3.5)
        #expect(restored.effectiveOpacity == 0.65)
        #expect(restored.effectiveCornerRadius == 24)
        #expect(restored.effectiveTextAlignment == .leading)

        let legacy = DiagramNode(title: "Legacy", frame: Rect(x: 0, y: 0, width: 168, height: 72))
        #expect(legacy.effectiveStrokeWidth == 1.2)
        #expect(legacy.effectiveOpacity == 1)
        #expect(legacy.effectiveCornerRadius == 8)
        #expect(legacy.effectiveTextAlignment == .center)
    }
}

@MainActor struct PanelAndTrashTests {
    private func make() -> DocumentSession {
        let session = DocumentSession(diagram: DiagramTemplate.panelBoard.makeDiagram())
        let history = UndoManager()
        history.groupsByEvent = false
        session.undoManager = history
        return session
    }
    @Test func movingPanelMovesItsContentsExactlyOnce() {
        let s = make()
        let before = s.diagram
        let panel = before.panels[0]
        s.selection = [panel.id, before.nodes[0].id]
        s.moveSelection(dx: 80, dy: 40)
        #expect(s.diagram.panels[0].frame.x == panel.frame.x + 80)
        for n in before.nodes {
            let after = s.diagram.nodes.first { $0.id == n.id }!
            #expect(after.frame.x == n.frame.x + (n.panelID == panel.id ? 80 : 0))
        }
        s.undoManager?.undo()
        #expect(s.diagram == before)
    }
    @Test func inspectorPanelMoveAlsoMovesLockedChildren() {
        let s = make()
        let id = s.diagram.panels[0].id
        let node = s.diagram.nodes[0]
        s.updateNode(node.id, name: "锁定") { $0.isLocked = true }
        s.updatePanel(id, name: "移动") { $0.frame.x += 100 }
        #expect(s.diagram.nodes[0].frame.x == node.frame.x + 100)
    }
    @Test func deletingPanelRecyclesChildrenAndEdgesAndRestores() {
        let s = make()
        let before = s.diagram
        let panel = before.panels[0]
        s.selection = [panel.id]
        s.deleteSelection()
        #expect(s.diagram.recycleBin.count == 1)
        #expect(!s.diagram.nodes.contains { $0.panelID == panel.id })
        s.restoreRecycled()
        #expect(Set(s.diagram.nodes.map(\.id)) == Set(before.nodes.map(\.id)))
        #expect(Set(s.diagram.edges.map(\.id)) == Set(before.edges.map(\.id)))
        #expect(s.diagram.recycleBin.isEmpty)
    }
    @Test func recycleBinSurvivesSaveAndReload() throws {
        let s = make()
        s.selection = [s.diagram.nodes[0].id]
        s.deleteSelection()
        let decoded = try DocumentCodec.decode(DocumentCodec.encode(s.diagram))
        #expect(decoded.pages[0].recycleBin == s.diagram.recycleBin)
        #expect(decoded.pages[0].recycleBin[0].nodes.count == 1)
    }
    @Test func restoreDependenciesFailAtomicallyAndRestoreAllWorks() {
        let s = make()
        let first = s.diagram.nodes[0].id
        let second = s.diagram.nodes[1].id
        s.selection = [first]
        s.deleteSelection()
        let entry = s.diagram.recycleBin[0].id
        s.selection = [second]
        s.deleteSelection()
        let deleted = s.diagram
        let revision = s.revision
        s.restoreRecycled(entry)
        #expect(s.diagram == deleted)
        #expect(s.revision == revision)
        s.restoreRecycled()
        #expect(s.diagram.recycleBin.isEmpty)
        #expect(s.diagram.nodes.contains { $0.id == first })
        #expect(s.diagram.nodes.contains { $0.id == second })
    }
    @Test func duplicatePanelRemapsMembershipAndInternalEdges() throws {
        let s = make()
        let panel = s.diagram.panels[0]
        s.selection = [panel.id]
        let source = s.selectionPayload()
        s.duplicateSelection()
        let copy = s.diagram.panels.last!
        #expect(copy.id != panel.id)
        #expect(s.diagram.nodes.filter { $0.panelID == copy.id }.count == source.nodes.count)
        #expect(s.diagram.edges.count == 5 + source.edges.count)
        _ = try s.diagram.validated()
    }
    @Test func lockedPanelPreventsEditingItsChildren() {
        let s = make()
        let id = s.diagram.panels[0].id
        s.updatePanel(id, name: "锁定") { $0.isLocked = true }
        let before = s.diagram
        s.selection = [before.nodes[0].id, id]
        s.moveSelection(dx: 80, dy: 80)
        s.deleteSelection()
        #expect(s.diagram == before)
    }
}

@MainActor struct MultiPageTests {
    private func make() -> DocumentSession {
        let session = DocumentSession(diagram: DiagramTemplate.blank.makeDiagram())
        let history = UndoManager()
        history.groupsByEvent = false
        session.undoManager = history
        return session
    }
    @Test func addSwitchAndEditPagesIndependently() {
        let s = make()
        let first = s.diagram.id
        #expect(s.addPage())
        #expect(s.pages.count == 2 && s.pageIndex == 2)
        s.add(.rounded, at: Point(x: 100, y: 100))
        s.selectPage(first)
        #expect(s.diagram.id == first && s.diagram.nodes.isEmpty)
        s.add(.ellipse, at: Point(x: 0, y: 0))
        #expect(s.pages.count == 2)
        #expect(s.pages.first { $0.id != first }?.nodes.count == 1)
    }
    @Test func pageOperationsUndoAndRedo() {
        let s = make()
        let first = s.diagram.id
        s.addPage()
        #expect(s.pages.count == 2)
        s.undoManager?.undo()
        #expect(s.pages.count == 1 && s.activePageID == first)
        s.undoManager?.redo()
        #expect(s.pages.count == 2 && s.activePageID != first)
    }
    @Test func duplicateRenamesMoveAndDeletePages() {
        let s = make()
        s.add(.rounded, at: Point(x: 40, y: 40))
        let first = s.diagram.id
        s.duplicatePage(first)
        #expect(s.pages.count == 2)
        let copy = s.diagram
        #expect(copy.id != first && copy.nodes.count == 1 && copy.nodes[0].id != s.pages[0].nodes[0].id)
        #expect(copy.title.contains(tr(" 副本")))
        s.renamePage(copy.id, title: "需求总览")
        #expect(s.diagram.title == "需求总览")
        s.movePage(copy.id, left: true)
        #expect(s.pages[0].id == copy.id && s.pageIndex == 1)
        s.deletePage(first)
        #expect(s.pages.count == 1 && s.activePageID == copy.id)
        s.deletePage(copy.id)
        #expect(s.errorMessage != nil && s.pages.count == 1)
    }
    @Test func multiPageDocumentRoundTrips() throws {
        let s = make()
        s.addPage()
        s.add(.umlClass, at: Point(x: 200, y: 200))
        let document = DiagramDocument(pages: s.pages, activePageID: s.activePageID)
        let decoded = try DocumentCodec.decode(DocumentCodec.encode(document))
        #expect(decoded == document)
        #expect(decoded.pages.count == 2)
        #expect(decoded.activePageID == s.activePageID)
        #expect(decoded.activePage.nodes.count == 1)
    }
    @Test func duplicatePageIDsRejected() {
        let page = DiagramTemplate.blank.makeDiagram()
        var document = DiagramDocument(pages: [page, page])
        #expect(throws: DiagramError.self) { try document.validated() }
        document = DiagramDocument(pages: [page])
        document.activePageID = UUID()
        #expect(throws: DiagramError.self) { try document.validated() }
    }
}

struct LocalWorkspaceTests {
    private func root() -> URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url.appendingPathComponent(".agents/test/workspace-" + UUID().uuidString, isDirectory: true)
    }
    @Test func concurrentBootstrapCreatesOnlyOneWorkspace() async throws {
        let url = root()
        defer { try? FileManager.default.removeItem(at: url) }
        let repository = LocalWorkspaceRepository(root: url)
        try await withThrowingTaskGroup(of: [LocalWorkspace].self) { group in
            for _ in 0..<4 { group.addTask { try await repository.ensureWorkspace(defaultName: "Default") } }
            var ids = Set<UUID>()
            for try await spaces in group { ids.formUnion(spaces.map(\.id)) }
            #expect(ids.count == 1)
        }
        #expect(try await repository.workspaces().count == 1)
    }
    @Test func workspaceCreateRenameAndReopen() async throws {
        let url = root()
        defer { try? FileManager.default.removeItem(at: url) }
        let repo = LocalWorkspaceRepository(root: url)
        let space = try await repo.createWorkspace(name: "架构团队")
        try await repo.renameWorkspace(space.id, name: "Architecture")
        let second = LocalWorkspaceRepository(root: url)
        #expect(try await second.workspaces().first?.name == "Architecture")
    }
    @Test func trashRestoreAndCrossWorkspaceMovePreserveFile() async throws {
        let url = root()
        defer { try? FileManager.default.removeItem(at: url) }
        let repo = LocalWorkspaceRepository(root: url)
        let a = try await repo.createWorkspace(name: "A")
        let b = try await repo.createWorkspace(name: "B")
        let model = DiagramTemplate.umlClass.makeDiagram()
        _ = try await repo.createDocument(model, in: a.id)
        let file = try #require(try await repo.files(in: a.id, trashed: false).first)
        try await repo.trash(file)
        #expect(try await repo.files(in: a.id, trashed: false).isEmpty)
        let trashed = try #require(try await repo.files(in: a.id, trashed: true).first)
        #expect(try DocumentCodec.read(at: trashed.url).pages[0] == model)
        try await repo.restore(trashed)
        let restored = try #require(try await repo.files(in: a.id, trashed: false).first)
        try await repo.move(restored, to: b.id)
        #expect(try await repo.files(in: a.id, trashed: false).isEmpty)
        let moved = try #require(try await repo.files(in: b.id, trashed: false).first)
        #expect(try DocumentCodec.read(at: moved.url).pages[0] == model)
        try await repo.rename(moved, title: "重命名的图表")
        #expect(try DocumentCodec.read(at: moved.url).activePage.title == "重命名的图表")
    }
    @Test @MainActor func renamingKeepsSidebarOrderAfterReload() async throws {
        let url = root()
        defer { try? FileManager.default.removeItem(at: url) }
        let repo = LocalWorkspaceRepository(root: url)
        let space = try await repo.createWorkspace(name: "A")
        var older = DiagramTemplate.blank.makeDiagram()
        older.title = "旧文件"
        let olderURL = try await repo.createDocument(older, in: space.id)
        var newer = DiagramTemplate.blank.makeDiagram()
        newer.title = "新文件"
        let newerURL = try await repo.createDocument(newer, in: space.id)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_600_000_000)], ofItemAtPath: olderURL.path)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_700_000_000)], ofItemAtPath: newerURL.path)

        let library = WorkspaceLibrary(repository: repo)
        await library.reload()
        let originalOrder = library.workspaceTree.map(\.file.id)
        let originalRecentOrder = library.visibleFiles.map(\.id)
        #expect(originalOrder == [newer.id, older.id])
        let file = try #require(library.workspaceFiles.first { $0.id == older.id })
        try await repo.rename(file, title: "重命名后")
        await library.reload()
        #expect(library.workspaceTree.map(\.file.id) == originalOrder)
        #expect(library.visibleFiles.map(\.id) == originalRecentOrder)
        #expect(library.workspaceTree.last?.file.title == "重命名后")

        let reopened = WorkspaceLibrary(repository: LocalWorkspaceRepository(root: url))
        await reopened.reload()
        #expect(reopened.workspaceTree.map(\.file.id) == originalOrder)
        #expect(reopened.visibleFiles.map(\.id) == originalRecentOrder)
    }
    @Test func restoreAllAndEmptyTrash() async throws {
        let url = root()
        defer { try? FileManager.default.removeItem(at: url) }
        let repo = LocalWorkspaceRepository(root: url)
        let space = try await repo.createWorkspace(name: "A")
        for template in [DiagramTemplate.blank, .umlClass, .c4Context] {
            _ = try await repo.createDocument(template.makeDiagram(), in: space.id)
        }
        for file in try await repo.files(in: space.id, trashed: false) { try await repo.trash(file) }
        #expect(try await repo.files(in: space.id, trashed: false).isEmpty)
        #expect(try await repo.restoreAll(in: space.id) == 3)
        #expect(try await repo.files(in: space.id, trashed: false).count == 3)
        #expect(try await repo.files(in: space.id, trashed: true).isEmpty)
        for file in try await repo.files(in: space.id, trashed: false) { try await repo.trash(file) }
        #expect(try await repo.emptyTrash(in: space.id) == 3)
        #expect(try await repo.files(in: space.id, trashed: true).isEmpty)
        #expect(try await repo.files(in: space.id, trashed: false).isEmpty)
    }
    @Test @MainActor func emptyTrashBlockedByOpenDocumentKeepsFiles() async throws {
        let url = root()
        defer { try? FileManager.default.removeItem(at: url) }
        let repo = LocalWorkspaceRepository(root: url)
        let space = try await repo.createWorkspace(name: "A")
        _ = try await repo.createDocument(DiagramTemplate.blank.makeDiagram(), in: space.id)
        var activeDocument = DiagramTemplate.blank.makeDiagram()
        activeDocument.title = "仍在工作空间"
        _ = try await repo.createDocument(activeDocument, in: space.id)
        let file = try #require(
            try await repo.files(in: space.id, trashed: false).first { $0.title != "仍在工作空间" })
        try await repo.trash(file)
        let library = WorkspaceLibrary(repository: repo)
        library.showingTrash = true
        await library.reload()
        #expect(library.visibleFiles.count == 1)
        #expect(library.workspaceFiles.map(\.title) == ["仍在工作空间"])
        library.canMoveFile = { _ in false }
        await library.emptyTrash()
        #expect(library.errorMessage != nil)
        #expect(try await repo.files(in: space.id, trashed: true).count == 1)
        library.canMoveFile = { _ in true }
        await library.emptyTrash()
        #expect(library.errorMessage == nil)
        #expect(library.noticeMessage?.contains("1") == true)
        #expect(try await repo.files(in: space.id, trashed: true).isEmpty)
    }
    @Test func destinationConflictNeverOverwrites() async throws {
        let url = root()
        defer { try? FileManager.default.removeItem(at: url) }
        let repo = LocalWorkspaceRepository(root: url)
        let space = try await repo.createWorkspace(name: "A")
        let model = DiagramTemplate.blank.makeDiagram()
        _ = try await repo.createDocument(model, in: space.id)
        await #expect(throws: WorkspaceError.self) { try await repo.createDocument(model, in: space.id) }
        #expect(try await repo.files(in: space.id, trashed: false).count == 1)
    }
    @Test @MainActor func pageHierarchyPersistsAndRejectsCycles() async throws {
        let url = root()
        defer { try? FileManager.default.removeItem(at: url) }
        let repo = LocalWorkspaceRepository(root: url)
        let space = try await repo.createWorkspace(name: "A")
        for title in ["父页面", "子页面", "孙页面"] {
            var diagram = DiagramTemplate.blank.makeDiagram()
            diagram.title = title
            _ = try await repo.createDocument(diagram, in: space.id)
        }
        let files = try await repo.files(in: space.id, trashed: false)
        let parent = try #require(files.first { $0.title == "父页面" })
        let child = try #require(files.first { $0.title == "子页面" })
        let grandchild = try #require(files.first { $0.title == "孙页面" })
        try await repo.movePage(child.id, under: parent.id, in: space.id)
        try await repo.movePage(grandchild.id, under: child.id, in: space.id)

        let library = WorkspaceLibrary(repository: repo)
        await library.reload()
        #expect(library.workspaceTree.map(\.file.title) == ["父页面", "子页面", "孙页面"])
        #expect(library.workspaceTree.map(\.depth) == [0, 1, 2])
        try await repo.repositionPage(grandchild.id, relativeTo: child.id, position: .before, in: space.id)
        await library.reload()
        #expect(library.workspaceTree.map(\.file.title) == ["父页面", "孙页面", "子页面"])
        #expect(library.workspaceTree.map(\.depth) == [0, 1, 1])
        try await repo.repositionPage(grandchild.id, relativeTo: child.id, position: .after, in: space.id)
        try await repo.repositionPage(grandchild.id, relativeTo: child.id, position: .inside, in: space.id)
        await #expect(throws: WorkspaceError.self) {
            try await repo.movePage(parent.id, under: grandchild.id, in: space.id)
        }
        try await repo.movePage(grandchild.id, under: nil, in: space.id)
        #expect(try await repo.files(in: space.id, trashed: false).first { $0.id == grandchild.id }?.parentID == nil)
    }
    @Test @MainActor func openFileGuardPreventsTrash() async throws {
        let url = root()
        defer { try? FileManager.default.removeItem(at: url) }
        let repo = LocalWorkspaceRepository(root: url)
        let space = try await repo.createWorkspace(name: "A")
        _ = try await repo.createDocument(DiagramTemplate.blank.makeDiagram(), in: space.id)
        let library = WorkspaceLibrary(repository: repo)
        await library.reload()
        library.canMoveFile = { _ in false }
        let file = try #require(library.files.first)
        await library.trash(file)
        #expect(library.errorMessage != nil)
        #expect(try await repo.files(in: space.id, trashed: false).count == 1)
    }
    @Test @MainActor func inlineFileIsPreparedAndReopenedAfterRename() async throws {
        let url = root()
        defer { try? FileManager.default.removeItem(at: url) }
        let repo = LocalWorkspaceRepository(root: url)
        let space = try await repo.createWorkspace(name: "A")
        _ = try await repo.createDocument(DiagramTemplate.blank.makeDiagram(), in: space.id)
        let library = WorkspaceLibrary(repository: repo)
        await library.reload()
        let file = try #require(library.files.first)
        library.activeFileURL = file.url
        var prepared: URL?
        var reopened: URL?
        library.canMoveFile = { _ in true }
        library.prepareFileMutation = { prepared = $0 }
        library.openAction = { reopened = $0 }
        await library.rename(file, title: "新名称")
        #expect(library.errorMessage == nil)
        #expect(prepared == file.url)
        #expect(reopened == file.url)
        #expect(try await repo.files(in: space.id, trashed: false).first?.title == "新名称")
    }
    @Test func backupRestoresDocumentsTrashAndRemapsWorkspaceConflicts() async throws {
        let url = root()
        defer { try? FileManager.default.removeItem(at: url) }
        let repo = LocalWorkspaceRepository(root: url)
        let workspace = try await repo.createWorkspace(name: "Architecture")
        _ = try await repo.createDocument(DiagramTemplate.umlClass.makeDiagram(), in: workspace.id)
        _ = try await repo.createDocument(DiagramTemplate.c4Context.makeDiagram(), in: workspace.id)
        let originalFiles = try await repo.files(in: workspace.id, trashed: false)
        let first = try #require(originalFiles.first)
        let second = try #require(originalFiles.last)
        try await repo.movePage(second.id, under: first.id, in: workspace.id)
        try await repo.trash(second)
        let archive = url.appendingPathComponent("portable.formabackup")
        let created = try await repo.createBackup(at: archive)
        #expect(created == WorkspaceBackupSummary(workspaceCount: 1, documentCount: 2, trashedDocumentCount: 1))
        #expect((try archive.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) > 64)

        let restored = try await repo.restoreBackup(from: archive)
        #expect(restored == created)
        let spaces = try await repo.workspaces()
        #expect(spaces.count == 2)
        #expect(Set(spaces.map(\.id)).count == 2)
        let imported = try #require(spaces.first { $0.id != workspace.id })
        #expect(imported.name == "Architecture")
        let importedActive = try await repo.files(in: imported.id, trashed: false)
        let importedTrash = try await repo.files(in: imported.id, trashed: true)
        #expect(importedActive.count == 1)
        #expect(importedTrash.count == 1)
        #expect(importedTrash.first?.parentID == importedActive.first?.id)
    }
    @Test func backupRoundTripPreservesMultiplePages() async throws {
        let url = root()
        defer { try? FileManager.default.removeItem(at: url) }
        let repo = LocalWorkspaceRepository(root: url)
        let space = try await repo.createWorkspace(name: "A")
        var document = DiagramDocument(page: DiagramTemplate.blank.makeDiagram())
        let second = Diagram(nodes: [DiagramNode(title: "第二页图形", frame: Rect(x: 0, y: 0, width: 168, height: 72))])
        document.pages.append(second)
        document.activePageID = second.id
        _ = try await repo.createDocument(document, in: space.id)
        let file = try #require(try await repo.files(in: space.id, trashed: false).first)
        #expect(try DocumentCodec.read(at: file.url).pages.count == 2)
        let archive = url.appendingPathComponent("pages.formabackup")
        _ = try await repo.createBackup(at: archive)
        _ = try await repo.restoreBackup(from: archive)
        let imported = try #require(try await repo.workspaces().first { $0.id != space.id })
        let restoredFile = try #require(try await repo.files(in: imported.id, trashed: false).first)
        let restoredDocument = try DocumentCodec.read(at: restoredFile.url)
        #expect(restoredDocument.pages.count == 2)
        #expect(restoredDocument.activePage.title == second.title)
        #expect(restoredDocument.pages.contains { $0.nodes.map(\.title) == ["第二页图形"] })
    }
    @Test func damagedBackupIsRejectedBeforeChangingLibrary() async throws {
        let url = root()
        defer { try? FileManager.default.removeItem(at: url) }
        let repo = LocalWorkspaceRepository(root: url)
        let workspace = try await repo.createWorkspace(name: "A")
        _ = try await repo.createDocument(DiagramTemplate.blank.makeDiagram(), in: workspace.id)
        let archive = url.appendingPathComponent("damaged.formabackup")
        _ = try await repo.createBackup(at: archive)
        var bytes = try Data(contentsOf: archive)
        bytes[bytes.count - 1] ^= 0xFF
        try bytes.write(to: archive, options: .atomic)
        let before = try await repo.workspaces()
        await #expect(throws: WorkspaceError.self) { try await repo.restoreBackup(from: archive) }
        #expect(try await repo.workspaces() == before)
    }
}
struct LocalizationTests {
    @Test func bundledChineseEnglishStrings() {
        #expect(Localization.text("工作空间", language: .english) == "Workspace")
        #expect(Localization.text("工作空间", language: .simplifiedChinese) == "工作空间")
        #expect(Localization.text("自定义内容 XYZ", language: .english) == "自定义内容 XYZ")
    }
    @Test @MainActor func settingsPersistWithoutChangingDocument() {
        let suite = "Forma.tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let previous = Localization.shared.language
        defer {
            defaults.removePersistentDomain(forName: suite)
            Localization.shared.language = previous
        }
        let document = DiagramTemplate.umlClass.makeDiagram()
        let session = DocumentSession(diagram: document)
        let settings = AppPreferences(defaults: defaults)
        settings.language = .english
        settings.appearance = .dark
        settings.defaultSnapToGrid = false
        settings.pngScale = 1
        let reloaded = AppPreferences(defaults: defaults)
        #expect(reloaded.language == .english)
        #expect(reloaded.appearance == .dark)
        #expect(!reloaded.defaultSnapToGrid)
        #expect(reloaded.pngScale == 1)
        #expect(session.diagram == document)
        #expect(session.revision == 0)
    }
}

struct WorkspaceProfileTests {
    @Test func legacyWorkspaceMetadataGetsProfileDefaults() throws {
        let id = UUID()
        let data = Data(
            """
            {"id":"\(id.uuidString)","name":"旧空间","createdAt":0}
            """.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let workspace = try decoder.decode(LocalWorkspace.self, from: data)
        #expect(workspace.symbol == "square.stack.3d.up.fill")
        #expect(workspace.summary.isEmpty)
    }
    @Test func workspaceProfilePersistsAndSurvivesBackup() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let repo = LocalWorkspaceRepository(root: url)
        let workspace = try await repo.createWorkspace(name: "A")
        try await repo.updateWorkspace(
            workspace.id, name: "产品设计", symbol: "lightbulb.fill", summary: "团队图表与设计决策")
        let updated = try #require(try await repo.workspaces().first)
        #expect(updated.name == "产品设计")
        #expect(updated.symbol == "lightbulb.fill")
        #expect(updated.summary == "团队图表与设计决策")
        let backup = url.appendingPathComponent("profile.formabackup")
        _ = try await repo.createBackup(at: backup)
        _ = try await repo.restoreBackup(from: backup)
        let restored = try #require(try await repo.workspaces().first { $0.id != workspace.id })
        #expect(restored.symbol == "lightbulb.fill")
        #expect(restored.summary == "团队图表与设计决策")
    }
    @Test func workspaceDeletionRemovesContentsAndKeepsOneWorkspace() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let repo = LocalWorkspaceRepository(root: url)
        let first = try await repo.createWorkspace(name: "保留")
        let removed = try await repo.createWorkspace(name: "删除")
        _ = try await repo.createDocument(DiagramTemplate.blank.makeDiagram(), in: removed.id)
        let removedFolder = url.appendingPathComponent(removed.id.uuidString)
        try await repo.deleteWorkspace(removed.id)
        #expect(!FileManager.default.fileExists(atPath: removedFolder.path))
        #expect(try await repo.workspaces() == [first])
        await #expect(throws: WorkspaceError.self) { try await repo.deleteWorkspace(first.id) }
    }
    @Test func fileMetadataReportsSheetsAndPermanentDeleteRemovesTrashItem() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let repo = LocalWorkspaceRepository(root: url)
        let workspace = try await repo.createWorkspace(name: "A")
        let first = DiagramTemplate.blank.makeDiagram()
        var second = DiagramTemplate.blank.makeDiagram()
        second.title = "Sheet 2"
        let document = DiagramDocument(pages: [first, second], activePageID: second.id)
        _ = try await repo.createDocument(document, in: workspace.id)
        let file = try #require(try await repo.files(in: workspace.id, trashed: false).first)
        #expect(file.pageCount == 2)
        try await repo.trash(file)
        let trashed = try #require(try await repo.files(in: workspace.id, trashed: true).first)
        try await repo.permanentlyDelete(trashed)
        #expect(try await repo.files(in: workspace.id, trashed: true).isEmpty)
    }
    @Test func duplicateFileKeepsSheetsAndCreatesIndependentDocument() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let repo = LocalWorkspaceRepository(root: url)
        let workspace = try await repo.createWorkspace(name: "A")
        var first = DiagramTemplate.blank.makeDiagram()
        first.title = "系统设计"
        let second = DiagramTemplate.flowchart.makeDiagram()
        let sourceDocument = DiagramDocument(pages: [first, second], activePageID: first.id)
        _ = try await repo.createDocument(sourceDocument, in: workspace.id)
        let source = try #require(try await repo.files(in: workspace.id, trashed: false).first)
        try await repo.duplicate(source, suffix: "副本")
        let files = try await repo.files(in: workspace.id, trashed: false)
        #expect(files.count == 2)
        let copy = try #require(files.first { $0.id != source.id })
        let copiedDocument = try DocumentCodec.read(at: copy.url)
        #expect(copiedDocument.pages.count == 2)
        #expect(copiedDocument.activePage.title == "系统设计 副本")
        #expect(Set(copiedDocument.pages.map(\.id)).isDisjoint(with: Set(sourceDocument.pages.map(\.id))))
    }
}

@MainActor struct NodeGroupingTests {
    @Test func groupedSelectionMovesDeletesRestoresAndPersists() throws {
        let a = DiagramNode(title: "A", frame: Rect(x: 0, y: 0, width: 100, height: 60))
        let b = DiagramNode(title: "B", frame: Rect(x: 200, y: 0, width: 100, height: 60))
        let session = DocumentSession(diagram: Diagram(nodes: [a, b]))
        let undo = UndoManager()
        undo.groupsByEvent = false
        session.undoManager = undo
        session.selection = [a.id, b.id]
        session.groupSelection()
        let group = try #require(session.diagram.nodes[0].groupID)
        #expect(session.diagram.nodes[1].groupID == group)
        let decoded = try JSONDecoder().decode(Diagram.self, from: JSONEncoder().encode(session.diagram))
        #expect(decoded.nodes[0].groupID == group)
        session.selection = [b.id]
        #expect(session.selection == [a.id, b.id])
        session.moveSelection(dx: 20, dy: 10)
        #expect(session.diagram.nodes[0].frame.x == 20)
        #expect(session.diagram.nodes[1].frame.x == 220)
        session.duplicateSelection()
        #expect(session.selectedNodes.count == 2)
        #expect(session.selectedNodes[0].groupID != group)
        session.deleteSelection()
        #expect(session.diagram.nodes.count == 2)
        undo.undo()
        #expect(session.diagram.nodes.count == 4)
        session.selection = [a.id]
        session.ungroupSelection()
        session.selection = [a.id]
        #expect(session.selection == [a.id])
        undo.undo()
        session.selection = [a.id]
        #expect(session.selection == [a.id, b.id])
        session.deleteSelection()
        #expect(session.diagram.nodes.count == 2)
    }
}

struct NestedConnectionRoutingTests {
    @Test func mixedAnchorsAvoidTargetInterior() {
        let a = DiagramNode(title: "创建订单", frame: Rect(x: 80, y: 150, width: 120, height: 70))
        let b = DiagramNode(title: "创建支付单", frame: Rect(x: 400, y: 150, width: 120, height: 70))
        var edge = DiagramEdge(source: a.id, target: b.id)
        edge.targetAnchor = EdgeAnchor(side: .top)
        let points = ConnectionGeometry.points(for: edge, nodes: [a.id: a, b.id: b])
        #expect(points.last == Point(x: 460, y: 150))
        for (start, end) in zip(points, points.dropFirst()) {
            #expect(start.x == end.x || start.y == end.y)
            for step in 1..<10 {
                let fraction = Double(step) / 10
                let point = Point(
                    x: start.x + (end.x - start.x) * fraction,
                    y: start.y + (end.y - start.y) * fraction)
                #expect(
                    !(point.x > b.frame.x && point.x < b.frame.maxX
                        && point.y > b.frame.y && point.y < b.frame.maxY))
            }
        }
    }
}

struct ConnectionEndpointStyleTests {
    @Test func endpointOverridesRoundTripIndependently() throws {
        let source = UUID()
        let target = UUID()
        for start in EndpointMarker.allCases {
            for end in EndpointMarker.allCases {
                let edge = DiagramEdge(
                    source: source, target: target, relation: .composition,
                    lineStyle: .dashDot, sourceMarker: start, targetMarker: end)
                let decoded = try JSONDecoder().decode(DiagramEdge.self, from: JSONEncoder().encode(edge))
                #expect(decoded == edge)
                #expect(decoded.effectiveSourceMarker == (start == .automatic ? .filledDiamond : start))
                #expect(decoded.effectiveTargetMarker == (end == .automatic ? .none : end))
            }
        }
    }
    @Test func legacyRelationsAndArrowOverridesRemainCompatible() throws {
        let id = UUID()
        let legacy = Data(
            "{\"id\":\"\(id)\",\"source\":\"\(UUID())\",\"target\":\"\(UUID())\",\"label\":\"\",\"relation\":\"aggregation\"}"
                .utf8)
        var edge = try JSONDecoder().decode(DiagramEdge.self, from: legacy)
        #expect(edge.effectiveSourceMarker == .hollowDiamond)
        #expect(edge.effectiveTargetMarker == .none)
        edge.arrow = .double
        #expect(edge.effectiveSourceMarker == .filledTriangle)
        #expect(edge.effectiveTargetMarker == .filledTriangle)
        edge.sourceMarker = EndpointMarker.none
        #expect(edge.effectiveSourceMarker == .none)
        #expect(edge.effectiveTargetMarker == .filledTriangle)
    }
    @MainActor @Test func endpointEditsUndoAndRedoTogether() {
        let a = DiagramNode(title: "A", frame: Rect(x: 0, y: 0, width: 100, height: 60))
        let b = DiagramNode(title: "B", frame: Rect(x: 300, y: 0, width: 100, height: 60))
        let edge = DiagramEdge(source: a.id, target: b.id)
        let session = DocumentSession(diagram: Diagram(nodes: [a, b], edges: [edge]))
        let undo = UndoManager()
        undo.groupsByEvent = false
        session.undoManager = undo
        session.perform("更改起点箭头") {
            $0.edges[0].sourceMarker = .circle
            $0.edges[0].targetMarker = .hollowTriangle
            $0.edges[0].lineStyle = .dashDot
        }
        undo.undo()
        #expect(session.diagram.edges[0] == edge)
        undo.redo()
        #expect(session.diagram.edges[0].effectiveSourceMarker == .circle)
        #expect(session.diagram.edges[0].effectiveTargetMarker == .hollowTriangle)
        #expect(session.diagram.edges[0].effectiveLineStyle == .dashDot)
    }
}

struct ConnectionWaypointTests {
    @MainActor @Test func customRouteSurvivesSaveUndoAndCopy() throws {
        let a = DiagramNode(title: "A", frame: Rect(x: 0, y: 0, width: 100, height: 60))
        let b = DiagramNode(title: "B", frame: Rect(x: 300, y: 0, width: 100, height: 60))
        let edge = DiagramEdge(source: a.id, target: b.id)
        let session = DocumentSession(diagram: Diagram(nodes: [a, b], edges: [edge]))
        let undo = UndoManager()
        undo.groupsByEvent = false
        session.undoManager = undo
        let points = [Point(x: 150, y: -100), Point(x: 250, y: -100)]
        session.perform("调整连线路径") { $0.edges[0].waypoints = points }
        let decoded = try JSONDecoder().decode(Diagram.self, from: JSONEncoder().encode(session.diagram))
        #expect(decoded.edges[0].waypoints == points)
        #expect(decoded.contentBounds?.y == -100)
        let route = ConnectionGeometry.points(for: edgeWithPoints(edge, points), nodes: [a.id: a, b.id: b])
        #expect(Array(route.dropFirst().dropLast()) == points)
        undo.undo()
        #expect(session.diagram.edges[0].waypoints == nil)
        undo.redo()
        session.selection = [a.id, b.id]
        session.moveSelection(dx: 20, dy: 10)
        #expect(session.diagram.edges[0].waypoints == points.map { $0.offset(x: 20, y: 10) })
        let before = try #require(session.diagram.edges[0].waypoints)
        session.duplicateSelection()
        #expect(session.diagram.edges[1].waypoints == before.map { $0.offset(x: 24, y: 24) })
    }
    private func edgeWithPoints(_ edge: DiagramEdge, _ points: [Point]) -> DiagramEdge {
        var copy = edge
        copy.waypoints = points
        return copy
    }
    @Test func invalidAndExcessiveControlPointsAreRejected() {
        let a = DiagramNode(title: "A", frame: Rect(x: 0, y: 0, width: 100, height: 60))
        let b = DiagramNode(title: "B", frame: Rect(x: 300, y: 0, width: 100, height: 60))
        for points in [[Point(x: .infinity, y: 0)], Array(repeating: Point(x: 200, y: 100), count: 129)] {
            let edge = DiagramEdge(source: a.id, target: b.id, waypoints: points)
            #expect(throws: DiagramError.self) { try Diagram(nodes: [a, b], edges: [edge]).validated() }
        }
    }
}
