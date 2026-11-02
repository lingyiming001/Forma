import AppKit
import FormaApplication
import FormaCanvasEngine
import FormaDesignSystem
import FormaGeometry
import FormaLocalization
import FormaWorkspaceFeature
import Observation
import SwiftUI

@MainActor final class WorkspaceWindowController: NSWindowController, NSToolbarDelegate, NSToolbarItemValidation {
    let session: DocumentSession
    private var toolGroup: NSToolbarItemGroup?
    private let tools: [CanvasTool] = [.select, .rounded, .connector, .text, .panel, .hand]
    init(session: DocumentSession) {
        self.session = session
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1440, height: 900),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.minSize = NSSize(width: 1024, height: 680)
        window.title = "Forma"
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = true
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.contentViewController = NSHostingController(rootView: WorkspaceView(session: session))
        let toolbar = NSToolbar(identifier: "Forma.WorkspaceToolbar.v2")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        window.toolbarStyle = .unifiedCompact
        window.center()
        window.setFrameAutosaveName("Forma.Workspace.v2")
        observeTool()
    }
    func refreshLocalizedUI() {
        let toolbar = NSToolbar(identifier: "Forma.WorkspaceToolbar.v2")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window?.toolbar = toolbar
    }
    required init?(coder: NSCoder) { fatalError("未使用") }
    override func windowTitle(forDocumentDisplayName displayName: String) -> String {
        (document as? FormaDocument)?.workspaceDisplayName
            ?? (document as? FormaDocument)?.fileURL?.deletingPathExtension().lastPathComponent
            ?? displayName
    }
    private func observeTool() {
        withObservationTracking {
            let tool = session.tool
            toolGroup?.selectedIndex = tools.firstIndex(of: tool) ?? (tool.shape != nil ? 1 : 0)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeTool() }
        }
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .init("workspace"), .init("sidebar"), .flexibleSpace, .init("undo"), .init("redo"), .init("tools"),
            .init("duplicate"), .init("delete"), .flexibleSpace, .init("fit"), .init("export"), .init("inspector"),
        ]
    }
    func toolbar(
        _ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        if id.rawValue == "tools" {
            let images = tools.map {
                NSImage(systemSymbolName: $0.symbol, accessibilityDescription: tr($0.title)) ?? NSImage()
            }
            let group = NSToolbarItemGroup(
                itemIdentifier: id, images: images, selectionMode: .selectOne, labels: tools.map { tr($0.title) },
                target: self, action: #selector(selectTool(_:)))
            group.label = tr("绘图工具")
            group.controlRepresentation = .expanded
            group.selectedIndex = tools.firstIndex(of: session.tool) ?? 0
            toolGroup = group
            return group
        }
        let item = NSToolbarItem(itemIdentifier: id)
        item.target = self
        let title: String
        let symbol: String
        let action: Selector
        switch id.rawValue {
        case "workspace":
            title = "工作空间"
            symbol = "square.grid.2x2"
            action = #selector(showWorkspace(_:))
        case "sidebar":
            title = "侧栏"
            symbol = "sidebar.left"
            action = #selector(toggleSidebar(_:))
        case "fit":
            title = "适合全部"
            symbol = "viewfinder"
            action = #selector(fitContent(_:))
        case "undo":
            title = "撤销"
            symbol = "arrow.uturn.backward"
            action = #selector(undo(_:))
        case "redo":
            title = "重做"
            symbol = "arrow.uturn.forward"
            action = #selector(redo(_:))
        case "duplicate":
            title = "就地复制"
            symbol = "square.on.square"
            action = #selector(duplicate(_:))
        case "delete":
            title = "移入回收箱"
            symbol = "trash"
            action = #selector(deleteSelection(_:))
        case "export":
            title = "导出"
            symbol = "square.and.arrow.up"
            action = #selector(showExportMenu(_:))
        case "inspector":
            title = "检查器"
            symbol = "sidebar.right"
            action = #selector(toggleInspector(_:))
        default: return nil
        }
        item.label = tr(title)
        item.toolTip = tr(title)
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tr(title))
        item.action = action
        return item
    }
    @objc private func selectTool(_ group: NSToolbarItemGroup) {
        guard tools.indices.contains(group.selectedIndex) else { return }
        window?.makeFirstResponder(nil)
        session.tool = tools[group.selectedIndex]
    }
    @objc private func showWorkspace(_ sender: Any?) { session.workspaceAction?() }
    @objc func toggleInspector(_ sender: Any?) { session.showInspector.toggle() }
    @objc func toggleSidebar(_ sender: Any?) { session.showSidebar.toggle() }
    @objc func fitContent(_ sender: Any?) { session.fitRequest += 1 }
    @objc func actualSize(_ sender: Any?) { session.camera.zoom(to: 1, at: session.screenCenter) }
    @objc func zoomIn(_ sender: Any?) { session.camera.zoom(to: session.camera.scale * 1.25, at: session.screenCenter) }
    @objc func zoomOut(_ sender: Any?) { session.camera.zoom(to: session.camera.scale * 0.8, at: session.screenCenter) }
    @objc func duplicate(_ sender: Any?) { session.duplicateSelection() }
    @objc private func deleteSelection(_ sender: Any?) {
        window?.makeFirstResponder(nil)
        session.deleteSelection()
    }
    @objc private func undo(_ sender: Any?) {
        window?.makeFirstResponder(nil)
        session.undoManager?.undo()
    }
    @objc private func redo(_ sender: Any?) {
        window?.makeFirstResponder(nil)
        session.undoManager?.redo()
    }
    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        switch item.itemIdentifier.rawValue {
        case "undo": session.undoManager?.canUndo == true
        case "redo": session.undoManager?.canRedo == true
        case "duplicate", "delete": !session.selection.isEmpty
        default: true
        }
    }
    @objc func exportPDF(_ sender: Any?) { session.exportAction?(false) }
    @objc func exportPNG(_ sender: Any?) { session.exportAction?(true) }
    @objc func showExportMenu(_ sender: Any?) {
        let menu = NSMenu()
        for (title, action) in [("导出 PDF…", #selector(exportPDF(_:))), ("导出 PNG…", #selector(exportPNG(_:)))] {
            let item = menu.addItem(withTitle: tr(title), action: action, keyEquivalent: "")
            item.target = self
        }
        if let view = window?.contentView {
            menu.popUp(positioning: nil, at: NSPoint(x: view.bounds.width - 160, y: view.bounds.height - 8), in: view)
        }
    }
}
