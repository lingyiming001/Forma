import AppKit
import FormaApplication
import FormaLocalization
import FormaWorkspaceFeature
import Observation
import SwiftUI

@MainActor final class SettingsWindowController: NSWindowController {
    init(preferences: AppPreferences) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 520), styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false)
        window.title = tr("设置")
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.contentViewController = NSHostingController(rootView: SettingsView(preferences: preferences))
        window.center()
        observeTitle()
    }
    private func observeTitle() {
        let language = withObservationTracking {
            Localization.shared.language
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeTitle() }
        }
        window?.title = Localization.text("设置", language: language)
    }
    required init?(coder: NSCoder) { fatalError("未使用") }
}
