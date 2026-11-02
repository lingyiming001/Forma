import AppKit
import FormaApplication
import FormaCatalogInfrastructure
import FormaDocumentIO
import FormaDomain
import FormaInterchange
import FormaLocalization

/// NSDocument 可在非主线程请求文件内容。锁只保护不可变值快照，不暴露 UI。
private final class DocumentSnapshot: @unchecked Sendable {
    private let lock = NSLock()
    private var value = DiagramDocument(pages: [Diagram()])
    func get() -> DiagramDocument {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
    func set(_ model: DiagramDocument) {
        lock.lock()
        defer { lock.unlock() }
        value = model
    }
}

@MainActor final class FormaDocument: NSDocument {
    let session = DocumentSession()
    private(set) var workspaceDisplayName: String?
    private nonisolated let snapshot = DocumentSnapshot()
    override init() {
        super.init()
        fileType = "com.forma.diagram"
        hasUndoManager = true
        undoManager?.groupsByEvent = false
        undoManager?.levelsOfUndo = 100
        session.undoManager = undoManager
        session.onChange = { [weak self] in self?.syncSnapshot() }
        session.onUndo = { [weak self] in self?.syncSnapshot() }
        session.onRedo = { [weak self] in self?.syncSnapshot() }
        session.templates = DiagramTemplate.allCases.map {
            TemplateDescriptor(
                id: $0.id, title: $0.title, subtitle: $0.subtitle, symbol: $0.symbol, category: $0.category)
        }
        if let preferences = (NSApp.delegate as? AppDelegate)?.preferences {
            session.showGrid = preferences.defaultShowGrid
            session.snapToGrid = preferences.defaultSnapToGrid
        }
        session.settingsAction = { (NSApp.delegate as? AppDelegate)?.showSettings(nil) }
        session.workspaceAction = { [weak self] in
            guard let self else { return }
            (NSApp.delegate as? AppDelegate)?.showWorkspace(from: self)
        }
        session.saveToWorkspaceAction = { [weak self] in
            if let self { (NSApp.delegate as? AppDelegate)?.saveCopyToWorkspace(self) }
        }
        session.exportAction = { [weak self] png in self?.export(png: png) }
        session.templateAction = { id in
            (NSApp.delegate as? AppDelegate)?.createDocument(template: DiagramTemplate(rawValue: id) ?? .blank)
        }
    }
    override nonisolated class var autosavesInPlace: Bool { true }
    override nonisolated class var autosavesDrafts: Bool { true }
    func configure(_ diagram: Diagram) {
        configure(DiagramDocument(page: diagram))
    }
    func configure(_ document: DiagramDocument) {
        snapshot.set(document)
        session.load(document)
        displayName = fileURL?.deletingPathExtension().lastPathComponent ?? document.activePage.title
    }
    func setWorkspaceDisplayName(_ name: String) {
        workspaceDisplayName = name
        displayName = name
        for controller in windowControllers { controller.synchronizeWindowTitleWithDocumentName() }
    }
    private func syncSnapshot() {
        snapshot.set(DiagramDocument(pages: session.pages, activePageID: session.activePageID))
        if workspaceDisplayName != nil {
            workspaceDisplayName = session.diagram.title
            displayName = session.diagram.title
        }
        for controller in windowControllers { controller.synchronizeWindowTitleWithDocumentName() }
    }
    override func makeWindowControllers() {
        session.load(snapshot.get())
        if fileURL?.pathComponents.contains("Workspaces") == true {
            workspaceDisplayName = session.diagram.title
            displayName = session.diagram.title
        }
        let controller = WorkspaceWindowController(session: session)
        addWindowController(controller)
    }
    override nonisolated func fileWrapper(ofType typeName: String) throws -> FileWrapper {
        try DocumentCodec.encode(snapshot.get())
    }
    override nonisolated func read(from url: URL, ofType typeName: String) throws {
        snapshot.set(try DocumentCodec.read(at: url))
    }
    override nonisolated func read(from fileWrapper: FileWrapper, ofType typeName: String) throws {
        snapshot.set(try DocumentCodec.decode(fileWrapper))
    }
    override func revert(toContentsOf url: URL, ofType typeName: String) throws {
        windowForSheet?.makeFirstResponder(nil)
        try super.revert(toContentsOf: url, ofType: typeName)
        session.load(snapshot.get())
    }
    override func save(_ sender: Any?) {
        windowForSheet?.makeFirstResponder(nil)
        super.save(sender)
    }
    override func saveAs(_ sender: Any?) {
        windowForSheet?.makeFirstResponder(nil)
        super.saveAs(sender)
    }
    override func canClose(
        withDelegate delegate: Any, shouldClose shouldCloseSelector: Selector?, contextInfo: UnsafeMutableRawPointer?
    ) {
        windowForSheet?.makeFirstResponder(nil)
        super.canClose(withDelegate: delegate, shouldClose: shouldCloseSelector, contextInfo: contextInfo)
    }
    override func close() {
        windowForSheet?.makeFirstResponder(nil)
        undoManager?.removeAllActions()
        session.onChange = nil
        session.onUndo = nil
        session.onRedo = nil
        super.close()
    }
    private func export(png: Bool) {
        guard let window = (NSApp.delegate as? AppDelegate)?.editingWindow(for: self) ?? windowForSheet else { return }
        window.makeFirstResponder(nil)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [png ? .png : .pdf]
        panel.nameFieldStringValue = session.diagram.title + (png ? ".png" : ".pdf")
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let self, let url = panel.url else { return }
            guard !self.session.isProcessing else { return }
            let diagram = self.session.diagram
            let scale = (NSApp.delegate as? AppDelegate)?.preferences.pngScale ?? 2
            self.session.isProcessing = true
            Task {
                defer { self.session.isProcessing = false }
                do {
                    let data = try await Task.detached(priority: .userInitiated) {
                        try png ? DiagramExporter.png(diagram, scale: scale) : DiagramExporter.pdf(diagram)
                    }.value
                    try await Task.detached(priority: .utility) {
                        try data.write(to: url, options: .atomic)
                    }.value
                    self.session.statusMessage = tr("导出完成")
                } catch { self.session.errorMessage = error.localizedDescription }
            }
        }
    }
}
