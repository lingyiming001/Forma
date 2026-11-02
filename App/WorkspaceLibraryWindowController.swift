import AppKit
import FormaApplication
import FormaLocalization
import FormaWorkspaceFeature
import SwiftUI

@MainActor final class WorkspaceLibraryWindowController: NSWindowController, NSWindowDelegate {
    let library: WorkspaceLibrary
    init(library: WorkspaceLibrary) {
        self.library = library
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Forma · " + tr("工作空间")
        window.minSize = NSSize(width: 960, height: 640)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.contentViewController = NSHostingController(rootView: WorkspaceLibraryView(library: library))
        window.center()
        window.setFrameAutosaveName("Forma.Library")
    }
    required init?(coder: NSCoder) { fatalError("未使用") }
    func windowDidBecomeKey(_ notification: Notification) { Task { await library.reload() } }
    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        library.activeSession?.undoManager
    }
}
