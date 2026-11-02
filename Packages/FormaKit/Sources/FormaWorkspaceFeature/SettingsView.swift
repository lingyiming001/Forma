import FormaApplication
import FormaDesignSystem
import FormaLocalization
import SwiftUI

public struct SettingsView: View {
    @Bindable var preferences: AppPreferences
    @State private var testStatus: String?
    @State private var isTesting = false
    public init(preferences: AppPreferences) { self.preferences = preferences }
    public var body: some View {
        TabView {
            generalTab
            themeTab
            editorTab
            aiTab
            mcpTab
            aboutTab
        }.padding(18).frame(width: 640, height: 520).tint(FormaTheme.accent)
            .environment(\.locale, Locale(identifier: preferences.language.identifier))
    }

    private var generalTab: some View {
        Form {
            Section {
                Picker(tr("界面语言"), selection: $preferences.language) {
                    ForEach(AppLanguage.allCases, id: \.self) { language in Text(language.displayName).tag(language) }
                }
                Toggle(tr("启动时打开工作空间"), isOn: $preferences.startInWorkspace)
            } footer: {
                Text(tr("图表默认在工作空间中打开。可通过文件快捷菜单选择在新窗口打开。")).font(.system(size: 11)).foregroundStyle(
                    .secondary)
            }
            Section {
                Text(tr("语言与外观属于应用设置，不会改写已有图表内容。")).font(.system(size: 11)).foregroundStyle(
                    .secondary)
            }
        }.formStyle(.grouped).tabItem { Label(tr("通用"), systemImage: "gearshape") }
    }

    private var themeTab: some View {
        Form {
            Section(tr("外观")) {
                Picker(tr("外观"), selection: $preferences.appearance) {
                    Text(tr("跟随系统")).tag(AppAppearance.system)
                    Text(tr("浅色")).tag(AppAppearance.light)
                    Text(tr("深色")).tag(AppAppearance.dark)
                }
            }
            Section(tr("强调色")) {
                HStack(spacing: 14) {
                    ForEach(ThemeAccent.allCases, id: \.self) { accent in
                        let color = Color(red: accent.rgb.red, green: accent.rgb.green, blue: accent.rgb.blue)
                        Button {
                            preferences.accent = accent
                        } label: {
                            Circle().fill(color).frame(width: 26, height: 26).overlay(
                                Circle().strokeBorder(
                                    preferences.accent == accent ? Color.primary : Color.clear, lineWidth: 2))
                        }.buttonStyle(.plain).help(tr(accent.title))
                    }
                    Spacer()
                }
            }
            Section {
                Text(tr("强调色用于按钮、选中项与画布高亮，切换后对新打开的界面生效。")).font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).tabItem { Label(tr("主题"), systemImage: "paintpalette") }
    }

    private var editorTab: some View {
        Form {
            Section(tr("新建文档默认值")) {
                Toggle(tr("显示网格"), isOn: $preferences.defaultShowGrid)
                Toggle(tr("吸附到网格"), isOn: $preferences.defaultSnapToGrid)
            }
            Section(tr("导出")) {
                Picker(tr("PNG 导出倍率"), selection: $preferences.pngScale) {
                    Text("1×").tag(1.0)
                    Text("2× Retina").tag(2.0)
                }
            }
            Section {
                Text(tr("默认值用于新建的编辑窗口；当前文档可在检查器单独调整。")).font(.system(size: 11)).foregroundStyle(
                    .secondary)
            }
        }.formStyle(.grouped).tabItem { Label(tr("编辑器"), systemImage: "slider.horizontal.3") }
    }

    private var aiTab: some View {
        Form {
            Section {
                Picker(tr("服务商"), selection: Binding(
                    get: { preferences.aiConfig.provider },
                    set: { provider in
                        var config = preferences.aiConfig
                        config.provider = provider
                        config.baseURL = provider.defaultBaseURL
                        config.model = provider.defaultModel
                        preferences.aiConfig = config
                    })) {
                    ForEach(AIProvider.allCases, id: \.self) { provider in Text(tr(provider.title)).tag(provider) }
                }
                TextField(tr("接口地址 (Base URL)"), text: $preferences.aiConfig.baseURL, prompt: Text("https://…/v1"))
                TextField(tr("模型名称"), text: $preferences.aiConfig.model, prompt: Text("gpt-4o-mini"))
                SecureField(tr("API 密钥（保存在本机钥匙串）"), text: $preferences.apiKey)
            } header: {
                Text(tr("模型服务"))
            } footer: {
                Text(tr("使用 OpenAI 兼容的 /chat/completions 接口；密钥仅存于本机钥匙串，只在你主动发送时上传。"))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Section(tr("生成参数")) {
                VStack(alignment: .leading) {
                    HStack(spacing: 4) {
                        Text(tr("温度")).font(.system(size: 11))
                        Text(preferences.aiConfig.temperature, format: .number.precision(.fractionLength(1))).font(
                            .system(size: 11)).foregroundStyle(.secondary)
                    }
                    Slider(value: $preferences.aiConfig.temperature, in: 0...2, step: 0.1)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("系统提示词")).font(.system(size: 11))
                    TextEditor(text: $preferences.aiConfig.systemPrompt).font(.system(size: 12)).frame(height: 60)
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.1)))
                }
            }
            Section {
                HStack {
                    Button(tr("测试连接")) { testConnection() }.disabled(isTesting || !preferences.aiConfig.isReady)
                    if isTesting { ProgressView().controlSize(.small) }
                    if let testStatus { Text(testStatus).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2) }
                    Spacer()
                }
            }
        }.formStyle(.grouped).tabItem { Label(tr("AI 模型"), systemImage: "brain") }
    }

    private var mcpTab: some View {
        Form {
            Section {
                ForEach($preferences.mcpServers) { $server in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Toggle("", isOn: $server.enabled).labelsHidden().frame(width: 30)
                            TextField(tr("服务器名称"), text: $server.name).font(.system(size: 12, weight: .medium))
                            Picker("", selection: $server.transport) {
                                ForEach(MCPTransport.allCases, id: \.self) { Text(tr($0.title)).tag($0) }
                            }.labelsHidden().frame(width: 150)
                            Button(role: .destructive) {
                                preferences.mcpServers.removeAll { $0.id == server.id }
                            } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                        }
                        if server.transport == .stdio {
                            TextField(tr("启动命令"), text: $server.command, prompt: Text("npx -y @modelcontextprotocol/server"))
                            TextField(tr("参数"), text: $server.arguments)
                        } else {
                            TextField(tr("服务地址 (URL)"), text: $server.url, prompt: Text("http://localhost:3000/sse"))
                        }
                    }.padding(.vertical, 4)
                    Divider()
                }
                Button {
                    preferences.mcpServers.append(MCPServer())
                } label: { Label(tr("添加服务器"), systemImage: "plus") }
            } header: {
                Text(tr("MCP 服务器"))
            } footer: {
                Text(tr("当前版本仅在本机保存这些配置，实际连接与工具调用将在后续版本提供。")).font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).tabItem { Label("MCP", systemImage: "powerplug") }
    }

    private var aboutTab: some View {
        VStack(spacing: 14) {
            Image("BrandLogo", bundle: .main).resizable().frame(width: 84, height: 84).clipShape(
                RoundedRectangle(cornerRadius: 20))
            Text("Forma").font(.system(size: 27, weight: .bold, design: .rounded))
            Text("0.2.0 · " + tr("开发预览")).font(.system(size: 12)).foregroundStyle(.secondary)
            Text(tr("为清晰的表达，留出空间。")).font(.system(size: 15))
            Text(tr("本地工作空间 · 多 Panel · UML 建模")).font(.system(size: 11)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).tabItem { Label(tr("关于"), systemImage: "info.circle") }
    }

    private func testConnection() {
        isTesting = true
        testStatus = nil
        let config = preferences.aiConfig
        let key = preferences.apiKey
        Task {
            do {
                let reply = try await AIChatClient().send(
                    config: config, apiKey: key, history: [ChatMessage(role: .user, text: "ping")])
                testStatus = "✓ " + String(reply.prefix(60))
            } catch {
                testStatus = "✗ " + (error.localizedDescription)
            }
            isTesting = false
        }
    }
}
