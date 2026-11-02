import AppKit
import FormaApplication
import FormaCatalogInfrastructure
import FormaDocumentIO
import FormaDomain
import FormaLocalization
import FormaWorkspaceFeature
import Observation
import UniformTypeIdentifiers

@MainActor final class FormaDocumentController: NSDocumentController {
    static func isWorkspaceDocument(_ url: URL) -> Bool {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Forma/Workspaces", isDirectory: true).standardizedFileURL.path + "/"
        return url.standardizedFileURL.path.hasPrefix(root)
    }
    override func noteNewRecentDocument(_ document: NSDocument) {
        if let url = document.fileURL, Self.isWorkspaceDocument(url) { return }
        super.noteNewRecentDocument(document)
    }
    override func noteNewRecentDocumentURL(_ url: URL) {
        guard !Self.isWorkspaceDocument(url) else { return }
        super.noteNewRecentDocumentURL(url)
    }
    func removeLegacyWorkspaceRecents() {
        let recents = recentDocumentURLs
        guard recents.contains(where: Self.isWorkspaceDocument) else { return }
        clearRecentDocuments(nil)
        for url in recents.reversed() where !Self.isWorkspaceDocument(url) {
            super.noteNewRecentDocumentURL(url)
        }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let preferences = AppPreferences()
    private var settingsWindow: SettingsWindowController?
    private var documents: NSDocumentController { NSDocumentController.shared }
    private lazy var workspaceRepository = LocalWorkspaceRepository(
        root: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Forma/Workspaces", isDirectory: true))
    private lazy var library = WorkspaceLibrary(repository: workspaceRepository)
    private var libraryWindow: WorkspaceLibraryWindowController?
    private var embeddedDocument: FormaDocument?
    /// 用于丢弃快速连续点击文件时已经过期的异步打开回调。
    private var workspaceOpenRequestID = UUID()
    private var aiChatWindow: AIChatWindowController?
    private var libraryConfigured = false
    func applicationWillFinishLaunching(_ notification: Notification) {
        let controller = FormaDocumentController()
        controller.removeLegacyWorkspaceRecents()
        NSApp.mainMenu = makeMenu()
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSDocumentController.shared.autosavingDelay = 5
        if documents.documents.isEmpty {
            if CommandLine.arguments.contains("--verify") {
                createDocument(template: .architecture)
            } else if preferences.startInWorkspace {
                showWorkspace(nil)
            } else {
                createDocument(template: .blank)
            }
        }
        observePreferences()
        NSApp.activate(ignoringOtherApps: true)
        #if DEBUG
            if let index = CommandLine.arguments.firstIndex(of: "--verify"), CommandLine.arguments.count > index + 1,
                let document = documents.documents.first as? FormaDocument
            {
                let output = URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true)
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(700))
                    let status = await DevelopmentVerification.run(document: document, output: output)
                    exit(status)
                }
            }
        #endif
    }
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showWorkspace(nil) }
        return true
    }
    private func observePreferences() {
        let (_, appearance, accent, _) = withObservationTracking {
            (preferences.language, preferences.appearance, preferences.accent, Localization.shared.language)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observePreferences() }
        }
        switch appearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        FormaThemeSync.apply(accent: accent)
        NSApp.mainMenu = makeMenu()
        settingsWindow?.window?.title = tr("设置")
        libraryWindow?.window?.title = "Forma · " + tr("工作空间")
        for document in documents.documents {
            for controller in document.windowControllers {
                (controller as? WorkspaceWindowController)?.refreshLocalizedUI()
            }
        }
    }
    @objc func showSettings(_ sender: Any?) {
        if settingsWindow == nil { settingsWindow = SettingsWindowController(preferences: preferences) }
        settingsWindow?.showWindow(nil)
        settingsWindow?.window?.makeKeyAndOrderFront(nil)
    }
    @objc func showAIChat(_ sender: Any?) {
        if aiChatWindow == nil {
            aiChatWindow = AIChatWindowController(
                preferences: preferences, openSettings: { [weak self] in self?.showSettings(nil) })
        }
        aiChatWindow?.show()
    }
    @objc func showWorkspace(_ sender: Any?) {
        presentWorkspace()
    }
    func showWorkspace(from document: FormaDocument) {
        presentWorkspace()
    }
    private func presentWorkspace() {
        if !libraryConfigured {
            libraryConfigured = true
            library.templates = DiagramTemplate.allCases.map {
                TemplateDescriptor(
                    id: $0.id, title: $0.title, subtitle: $0.subtitle, symbol: $0.symbol, category: $0.category)
            }
            library.settingsAction = { [weak self] in self?.showSettings(nil) }
            library.openAction = { [weak self] url in self?.openWorkspaceDocument(url) }
            library.openInNewWindowAction = { [weak self] url in self?.openWorkspaceDocumentInNewWindow(url) }
            library.createAction = { [weak self] template, id in
                self?.createWorkspaceDocument(template: template, in: id)
            }
            library.canMoveFile = { [weak self] url in
                self?.visibleWorkspaceDocument(for: url) == nil
            }
            library.prepareFileMutation = { [weak self] url in
                try await self?.prepareWorkspaceFileMutation(at: url)
            }
            library.backupAction = { [weak self] in self?.chooseBackupDestination() }
            library.restoreBackupAction = { [weak self] in self?.chooseBackupSource() }
            library.revealFileAction = { url in NSWorkspace.shared.activateFileViewerSelecting([url]) }
            library.revealWorkspaceAction = { [weak self] id in
                guard let root = self?.workspaceRepository.root else { return }
                NSWorkspace.shared.activateFileViewerSelecting([
                    root.appendingPathComponent(id.uuidString, isDirectory: true)
                ])
            }
        }
        if libraryWindow == nil { libraryWindow = WorkspaceLibraryWindowController(library: library) }
        libraryWindow?.showWindow(nil)
        libraryWindow?.window?.makeKeyAndOrderFront(nil)
        Task { await library.reload() }
    }
    private var backupContentType: UTType {
        UTType(exportedAs: "com.forma.backup")
    }
    private func chooseBackupDestination() {
        let panel = NSSavePanel()
        panel.title = tr("备份所有工作空间")
        panel.nameFieldStringValue =
            "Forma-Backup-" + Date.now.formatted(.iso8601.year().month().day())
            + ".formabackup"
        panel.allowedContentTypes = [backupContentType]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do {
                try await saveOpenWorkspaceDocuments()
                await library.createBackup(at: url)
            } catch { library.errorMessage = error.localizedDescription }
        }
    }
    private func chooseBackupSource() {
        let panel = NSOpenPanel()
        panel.title = tr("从备份恢复")
        panel.allowedContentTypes = [backupContentType]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await library.restoreBackup(from: url) }
    }
    private func saveOpenWorkspaceDocuments() async throws {
        let rootPath = workspaceRepository.root.path + "/"
        for document in documents.documents {
            guard let url = document.fileURL?.standardizedFileURL, url.path.hasPrefix(rootPath),
                let type = document.fileType
            else { continue }
            document.windowForSheet?.makeFirstResponder(nil)
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                document.save(to: url, ofType: type, for: .saveOperation) { error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                }
            }
        }
    }
    private func prepareWorkspaceFileMutation(at url: URL) async throws {
        guard let document = documents.documents.first(where: {
            $0.fileURL?.standardizedFileURL == url.standardizedFileURL
        }) else { return }
        guard !document.windowControllers.contains(where: { $0.window?.isVisible == true }) else {
            throw WorkspaceError.fileInUse
        }
        guard let type = document.fileType else { throw WorkspaceError.invalidLocation }
        document.windowForSheet?.makeFirstResponder(nil)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            document.save(to: url, ofType: type, for: .saveOperation) { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
        if embeddedDocument === document {
            embeddedDocument = nil
            library.activeFileURL = nil
            library.activeSession = nil
        }
        document.close()
    }
    private func openWorkspaceDocument(_ url: URL) {
        let requestID = UUID()
        workspaceOpenRequestID = requestID
        if let document = visibleWorkspaceDocument(for: url) {
            focusDocumentWindow(document)
            return
        }
        if let document = embeddedDocument, document.fileURL?.standardizedFileURL == url.standardizedFileURL {
            library.activeFileURL = url
            library.activeSession = document.session
            return
        }
        if let document = embeddedDocument, document.windowControllers.allSatisfy({ $0.window?.isVisible != true }) {
            replaceEmbeddedDocument(document, with: url, requestID: requestID)
            return
        }
        loadEmbeddedDocument(at: url, requestID: requestID)
    }
    private func loadEmbeddedDocument(at url: URL, requestID: UUID) {
        documents.openDocument(withContentsOf: url, display: false) { [weak self] document, _, error in
            guard let self else { return }
            guard self.workspaceOpenRequestID == requestID else { return }
            if let error { self.library.errorMessage = error.localizedDescription; return }
            guard let document = document as? FormaDocument else { return }
            if document.windowControllers.contains(where: { $0.window?.isVisible == true }) {
                self.focusDocumentWindow(document)
                return
            }
            if document.windowControllers.isEmpty { document.makeWindowControllers() }
            document.setWorkspaceDisplayName(self.workspaceName(for: url))
            self.embeddedDocument = document
            document.session.showInspector = false
            self.library.activeFileURL = url
            self.library.activeSession = document.session
        }
    }
    private func openWorkspaceDocumentInNewWindow(_ url: URL) {
        if let document = visibleWorkspaceDocument(for: url) {
            focusDocumentWindow(document)
            return
        }
        if let document = embeddedDocument, document.fileURL?.standardizedFileURL == url.standardizedFileURL {
            showDocumentInNewWindow(document, at: url)
            return
        }
        documents.openDocument(withContentsOf: url, display: false) { [weak self] document, _, error in
            if let error { self?.library.errorMessage = error.localizedDescription }
            if let self, let document = document as? FormaDocument {
                self.showDocumentInNewWindow(document, at: url)
            }
        }
    }
    private func showDocumentInNewWindow(_ document: FormaDocument, at url: URL) {
        if document.windowControllers.isEmpty { document.makeWindowControllers() }
        document.setWorkspaceDisplayName(workspaceName(for: url))
        if embeddedDocument === document {
            embeddedDocument = nil
            library.activeFileURL = nil
            library.activeSession = nil
        }
        document.showWindows()
        document.windowForSheet?.makeKeyAndOrderFront(nil)
    }
    private func visibleWorkspaceDocument(for url: URL) -> FormaDocument? {
        documents.documents.compactMap { $0 as? FormaDocument }.first {
            $0.fileURL?.standardizedFileURL == url.standardizedFileURL
                && $0.windowControllers.contains(where: { $0.window?.isVisible == true })
        }
    }
    private func focusDocumentWindow(_ document: FormaDocument) {
        if embeddedDocument === document {
            embeddedDocument = nil
            library.activeFileURL = nil
            library.activeSession = nil
        }
        document.windowControllers.compactMap(\.window).first(where: \.isVisible)?
            .makeKeyAndOrderFront(nil)
    }
    private func replaceEmbeddedDocument(_ document: FormaDocument, with url: URL, requestID: UUID) {
        let load = { [weak self, weak document] in
            guard let self, self.workspaceOpenRequestID == requestID else { return }
            self.documents.openDocument(withContentsOf: url, display: false) { [weak self, weak document] next, _, error in
                guard let self, self.workspaceOpenRequestID == requestID else { return }
                if let error { self.library.errorMessage = error.localizedDescription; return }
                guard let next = next as? FormaDocument else { return }
                if next.windowControllers.contains(where: { $0.window?.isVisible == true }) {
                    self.focusDocumentWindow(next)
                    return
                }
                if next.windowControllers.isEmpty { next.makeWindowControllers() }
                next.setWorkspaceDisplayName(self.workspaceName(for: url))
                next.session.showInspector = false

                // 新文档完全就绪后再原子替换，避免 activeSession 短暂为 nil 导致侧栏闪烁。
                self.embeddedDocument = next
                self.library.activeFileURL = url
                self.library.activeSession = next.session
                document?.close()
                Task { await self.library.reload() }
            }
        }
        guard document.isDocumentEdited, let currentURL = document.fileURL, let type = document.fileType else {
            load()
            return
        }
        document.save(to: currentURL, ofType: type, for: .saveOperation) { [weak self] error in
            guard let self, self.workspaceOpenRequestID == requestID else { return }
            if let error { self.library.errorMessage = error.localizedDescription } else { load() }
        }
    }
    private func workspaceName(for url: URL) -> String {
        library.workspaceFiles.first { $0.url.standardizedFileURL == url.standardizedFileURL }?.title
            ?? url.deletingPathExtension().lastPathComponent
    }
    func editingWindow(for document: FormaDocument) -> NSWindow? {
        if embeddedDocument === document, libraryWindow?.window?.isKeyWindow == true {
            return libraryWindow?.window
        }
        return document.windowForSheet
    }
    private var currentEditor: FormaDocument? {
        if libraryWindow?.window?.isKeyWindow == true { return embeddedDocument }
        return NSApp.keyWindow?.windowController?.document as? FormaDocument
    }
    @objc private func saveCurrentDiagram(_ sender: Any?) { currentEditor?.save(sender) }
    @objc private func saveCurrentDiagramAs(_ sender: Any?) { currentEditor?.saveAs(sender) }
    @objc private func revertCurrentDiagram(_ sender: Any?) { currentEditor?.revertToSaved(sender) }
    @objc private func exportCurrentPDF(_ sender: Any?) { currentEditor?.session.exportAction?(false) }
    @objc private func exportCurrentPNG(_ sender: Any?) { currentEditor?.session.exportAction?(true) }
    @objc private func duplicateCurrentSelection(_ sender: Any?) { currentEditor?.session.duplicateSelection() }
    @objc private func fitCurrentDiagram(_ sender: Any?) { currentEditor?.session.fitRequest += 1 }
    @objc private func actualSizeCurrentDiagram(_ sender: Any?) {
        guard let session = currentEditor?.session else { return }
        session.camera.zoom(to: 1, at: session.screenCenter)
    }
    @objc private func zoomInCurrentDiagram(_ sender: Any?) {
        guard let session = currentEditor?.session else { return }
        session.camera.zoom(to: session.camera.scale * 1.25, at: session.screenCenter)
    }
    @objc private func zoomOutCurrentDiagram(_ sender: Any?) {
        guard let session = currentEditor?.session else { return }
        session.camera.zoom(to: session.camera.scale * 0.8, at: session.screenCenter)
    }
    @objc private func toggleCurrentSidebar(_ sender: Any?) { currentEditor?.session.showSidebar.toggle() }
    @objc private func toggleCurrentInspector(_ sender: Any?) { currentEditor?.session.showInspector.toggle() }
    private func createWorkspaceDocument(template: String, in id: UUID) {
        Task {
            do {
                let diagram = (DiagramTemplate(rawValue: template) ?? .blank).makeDiagram(
                    language: preferences.language)
                let url = try await workspaceRepository.createDocument(diagram, in: id)
                openWorkspaceDocument(url)
                await library.reload()
            } catch { library.errorMessage = error.localizedDescription }
        }
    }
    func saveCopyToWorkspace(_ document: FormaDocument) {
        document.windowForSheet?.makeFirstResponder(nil)
        showWorkspace(nil)
        var copy = document.session.diagram
        copy.id = UUID()
        copy.title += " " + tr("副本")
        Task {
            await library.reload()
            guard let id = library.selectedWorkspaceID else { return }
            do {
                let url = try await workspaceRepository.createDocument(copy, in: id)
                await library.reload()
                openWorkspaceDocument(url)
            } catch { library.errorMessage = error.localizedDescription }
        }
    }
    @objc private func newEnterpriseDiagram(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String, let template = DiagramTemplate(rawValue: name) else {
            return
        }
        createDocument(template: template)
    }
    @objc func newDocument(_ sender: Any?) { createDocument(template: .blank) }
    @objc func newArchitecture(_ sender: Any?) { createDocument(template: .architecture) }
    @objc func newFlowchart(_ sender: Any?) { createDocument(template: .flowchart) }
    @objc func newMindmap(_ sender: Any?) { createDocument(template: .mindmap) }
    func createDocument(template: DiagramTemplate) {
        let document = FormaDocument()
        document.configure(template.makeDiagram(language: preferences.language))
        documents.addDocument(document)
        document.makeWindowControllers()
        document.showWindows()
    }
    @objc private func openRecent(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        documents.openDocument(withContentsOf: url, display: true) { _, _, error in
            if let error { NSApp.presentError(error) }
        }
    }
    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu.identifier?.rawValue == "windows" {
            for window in NSApp.windows where window.isVisible {
                guard let document = window.windowController?.document as? FormaDocument,
                    let name = document.workspaceDisplayName
                else { continue }
                NSApp.changeWindowsItem(window, title: name, filename: false)
            }
            return
        }
        guard menu.identifier?.rawValue == "recent" else { return }
        menu.removeAllItems()
        let recentURLs = documents.recentDocumentURLs
        for url in recentURLs {
            let item = menu.addItem(
                withTitle: url.deletingPathExtension().lastPathComponent, action: #selector(openRecent(_:)),
                keyEquivalent: "")
            item.target = self
            item.representedObject = url
        }
        if menu.items.isEmpty {
            let item = menu.addItem(withTitle: tr("暂无最近文档"), action: nil, keyEquivalent: "")
            item.isEnabled = false
        }
        menu.addItem(.separator())
        let clearItem = menu.addItem(
            withTitle: tr("清空最近记录"), action: #selector(NSDocumentController.clearRecentDocuments(_:)),
            keyEquivalent: "")
        clearItem.target = documents
        clearItem.isEnabled = !recentURLs.isEmpty
    }
    private func makeMenu() -> NSMenu {
        let main = NSMenu()
        func submenu(_ title: String) -> NSMenu {
            let item = NSMenuItem(title: tr(title), action: nil, keyEquivalent: "")
            let menu = NSMenu(title: tr(title))
            item.submenu = menu
            main.addItem(item)
            return menu
        }
        @discardableResult func add(
            _ menu: NSMenu, _ title: String, _ action: Selector, _ key: String = "",
            _ modifiers: NSEvent.ModifierFlags = .command, _ target: AnyObject? = nil
        ) -> NSMenuItem {
            let item = menu.addItem(withTitle: tr(title), action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
            item.target = target
            return item
        }
        let app = submenu("Forma")
        add(app, "关于 Forma", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), "", .command, NSApp)
        add(app, "设置…", #selector(showSettings(_:)), ",", .command, self)
        add(app, "AI 助手…", #selector(showAIChat(_:)), "a", [.command, .shift], self)
        app.addItem(.separator())
        let services = NSMenu()
        let serviceItem = NSMenuItem(title: tr("服务"), action: nil, keyEquivalent: "")
        serviceItem.submenu = services
        app.addItem(serviceItem)
        NSApp.servicesMenu = services
        app.addItem(.separator())
        add(app, "隐藏 Forma", #selector(NSApplication.hide(_:)), "h", .command, NSApp)
        add(app, "隐藏其他", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option], NSApp)
        add(app, "显示全部", #selector(NSApplication.unhideAllApplications(_:)), "", .command, NSApp)
        app.addItem(.separator())
        add(app, "退出 Forma", #selector(NSApplication.terminate(_:)), "q", .command, NSApp)
        let file = submenu("文件")
        add(file, "工作空间…", #selector(showWorkspace(_:)), "o", [.command, .shift], self)
        add(file, "新建", #selector(newDocument(_:)), "n", .command, self)
        let templates = NSMenu(title: tr("从模板新建"))
        let templateItem = NSMenuItem(title: tr("从模板新建"), action: nil, keyEquivalent: "")
        templateItem.submenu = templates
        file.addItem(templateItem)
        add(templates, "系统架构", #selector(newArchitecture(_:)), "", .command, self)
        add(templates, "业务流程", #selector(newFlowchart(_:)), "", .command, self)
        add(templates, "思维导图", #selector(newMindmap(_:)), "", .command, self)
        for template in DiagramTemplate.allCases
            where ![.blank, .architecture, .flowchart, .mindmap].contains(template) {
            let item = add(templates, template.title, #selector(newEnterpriseDiagram(_:)), "", .command, self)
            item.representedObject = template.rawValue
        }
        add(file, "打开…", #selector(NSDocumentController.openDocument(_:)), "o", .command, documents)
        let recent = NSMenu(title: tr("打开最近使用"))
        let recentItem = NSMenuItem(title: tr("打开最近使用"), action: nil, keyEquivalent: "")
        recentItem.submenu = recent
        file.addItem(recentItem)
        recent.identifier = NSUserInterfaceItemIdentifier("recent")
        recent.delegate = self
        file.addItem(.separator())
        add(file, "关闭", #selector(NSWindow.performClose(_:)), "w")
        add(file, "保存…", #selector(saveCurrentDiagram(_:)), "s", .command, self)
        add(file, "另存为…", #selector(saveCurrentDiagramAs(_:)), "s", [.command, .shift], self)
        add(file, "恢复到上次保存", #selector(revertCurrentDiagram(_:)), "", .command, self)
        file.addItem(.separator())
        add(file, "导出 PDF…", #selector(exportCurrentPDF(_:)), "e", [.command, .shift], self)
        add(file, "导出 PNG…", #selector(exportCurrentPNG(_:)), "", .command, self)
        let edit = submenu("编辑")
        add(edit, "撤销", Selector(("undo:")), "z")
        add(edit, "重做", Selector(("redo:")), "z", [.command, .shift])
        edit.addItem(.separator())
        add(edit, "剪切", #selector(NSText.cut(_:)), "x")
        add(edit, "复制", #selector(NSText.copy(_:)), "c")
        add(edit, "粘贴", #selector(NSText.paste(_:)), "v")
        add(edit, "全选", #selector(NSResponder.selectAll(_:)), "a")
        add(edit, "就地复制", #selector(duplicateCurrentSelection(_:)), "d", .command, self)
        let view = submenu("视图")
        add(view, "适合全部", #selector(fitCurrentDiagram(_:)), "0", .command, self)
        add(view, "实际大小", #selector(actualSizeCurrentDiagram(_:)), "1", .command, self)
        add(view, "放大", #selector(zoomInCurrentDiagram(_:)), "+", .command, self)
        add(view, "缩小", #selector(zoomOutCurrentDiagram(_:)), "-", .command, self)
        view.addItem(.separator())
        add(view, "显示或隐藏侧栏", #selector(toggleCurrentSidebar(_:)), "s", [.control, .command], self)
        add(view, "显示或隐藏检查器", #selector(toggleCurrentInspector(_:)), "i", [.option, .command], self)
        add(view, "进入全屏幕", #selector(NSWindow.toggleFullScreen(_:)), "f", [.control, .command])
        let windows = submenu("窗口")
        add(windows, "最小化", #selector(NSWindow.performMiniaturize(_:)), "m")
        add(windows, "缩放", #selector(NSWindow.performZoom(_:)))
        windows.addItem(.separator())
        add(windows, "全部置于顶层", #selector(NSApplication.arrangeInFront(_:)))
        windows.identifier = NSUserInterfaceItemIdentifier("windows")
        windows.delegate = self
        NSApp.windowsMenu = windows
        return main
    }
}
