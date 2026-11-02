import AppKit
import FormaApplication
import FormaDesignSystem
import FormaLocalization
import Observation
import SwiftUI

/// 将主题强调色同步到设计系统（供 App 层在启动与切换时调用）。
public enum FormaThemeSync {
    @MainActor public static func apply(accent: ThemeAccent) {
        FormaTheme.setAccent(red: accent.rgb.red, green: accent.rgb.green, blue: accent.rgb.blue)
    }
}

@MainActor @Observable final class AIChatViewModel {
    let preferences: AppPreferences
    var messages: [ChatMessage] = []
    var draft = ""
    var isSending = false
    var errorMessage: String?
    init(preferences: AppPreferences) { self.preferences = preferences }
    var isConfigured: Bool { preferences.aiConfig.isReady }
    var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending && isConfigured
    }
    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        guard isConfigured else { errorMessage = tr("请先在设置中配置模型服务。"); return }
        messages.append(ChatMessage(role: .user, text: text))
        draft = ""
        isSending = true
        errorMessage = nil
        let history = messages
        let config = preferences.aiConfig
        let key = preferences.apiKey
        Task {
            do {
                let reply = try await AIChatClient().send(config: config, apiKey: key, history: history)
                messages.append(ChatMessage(role: .assistant, text: reply))
            } catch {
                errorMessage = error.localizedDescription
            }
            isSending = false
        }
    }
    func clear() { messages.removeAll(); errorMessage = nil }
}

public struct AIChatView: View {
    @State private var model: AIChatViewModel
    private let openSettings: () -> Void
    public init(preferences: AppPreferences, openSettings: @escaping () -> Void) {
        _model = State(initialValue: AIChatViewModel(preferences: preferences))
        self.openSettings = openSettings
    }
    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(tr("AI 助手"), systemImage: "bubble.left.and.bubble.right").font(
                    .system(size: 13, weight: .semibold))
                Spacer()
                if !model.messages.isEmpty {
                    Button {
                        model.clear()
                    } label: { Image(systemName: "trash") }.buttonStyle(.borderless).help(tr("清空对话"))
                }
            }.padding(14)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if model.messages.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: "sparkles").font(.system(size: 30, weight: .ultraLight))
                                    .foregroundStyle(FormaTheme.gradient)
                                Text(tr("让 AI 帮你梳理图表与想法。")).font(.system(size: 13)).foregroundStyle(.secondary)
                                if !model.isConfigured {
                                    Button(tr("前往设置")) { openSettings() }.controlSize(.small)
                                }
                            }.frame(maxWidth: .infinity).padding(.top, 60)
                        }
                        ForEach(model.messages) { message in bubble(message) }
                        if model.isSending {
                            HStack {
                                ProgressView().controlSize(.small)
                                Text(tr("正在思考…")).font(.system(size: 12)).foregroundStyle(.secondary)
                            }.id("pending")
                        }
                    }.padding(16)
                }
                .onChange(of: model.messages.count) { _, _ in
                    if let last = model.messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
            if let error = model.errorMessage {
                Text(error).font(.system(size: 11)).foregroundStyle(.red).padding(.horizontal, 16).frame(
                    maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack(alignment: .bottom, spacing: 8) {
                TextField(tr("输入消息…"), text: $model.draft, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(
                    1...5
                ).onSubmit { model.send() }
                Button {
                    model.send()
                } label: { Image(systemName: "arrow.up.circle.fill").font(.system(size: 22)) }.buttonStyle(.plain)
                    .disabled(!model.canSend)
            }.padding(12)
        }.frame(minWidth: 360, minHeight: 420).tint(FormaTheme.accent)
            .environment(\.locale, Locale(identifier: Localization.shared.language.identifier))
    }
    private func bubble(_ message: ChatMessage) -> some View {
        let isUser = message.role == .user
        return HStack {
            if isUser { Spacer(minLength: 40) }
            Text(message.text).font(.system(size: 12)).textSelection(.enabled)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(
                    isUser ? FormaTheme.accent.opacity(0.16) : Color(nsColor: .controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 10))
            if !isUser { Spacer(minLength: 40) }
        }.frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }
}

/// 独立 AI 助手窗口。放在功能层以避免改动 Xcode 工程文件。
@MainActor public final class AIChatWindowController: NSWindowController {
    public init(preferences: AppPreferences, openSettings: @escaping () -> Void) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = tr("AI 助手")
        window.isReleasedWhenClosed = false
        window.tabbingIdentifier = "forma-ai"
        super.init(window: window)
        window.contentViewController = NSHostingController(
            rootView: AIChatView(preferences: preferences, openSettings: openSettings))
        window.setFrameAutosaveName("FormaAIChat")
        window.center()
    }
    required init?(coder: NSCoder) { fatalError("未使用") }
    public func show() { showWindow(nil); window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
}
