import FormaLocalization
import Foundation
import Observation

public enum AppAppearance: String, CaseIterable, Sendable { case system, light, dark }

/// 主题强调色预设（仅存 RGB 分量，由 UI 层映射为颜色）。
public enum ThemeAccent: String, CaseIterable, Sendable {
    case indigo, blue, teal, purple, rose, orange
    public var title: String {
        switch self {
        case .indigo: "蓝紫"; case .blue: "蓝色"; case .teal: "青绿"
        case .purple: "紫色"; case .rose: "玫红"; case .orange: "橙色"
        }
    }
    public var rgb: (red: Double, green: Double, blue: Double) {
        switch self {
        case .indigo: (0.30, 0.36, 0.93)
        case .blue: (0.16, 0.45, 0.96)
        case .teal: (0.10, 0.66, 0.62)
        case .purple: (0.55, 0.32, 0.92)
        case .rose: (0.90, 0.28, 0.51)
        case .orange: (0.96, 0.55, 0.13)
        }
    }
}

@MainActor @Observable public final class AppPreferences {
    private let defaults: UserDefaults
    public var language: AppLanguage {
        didSet {
            defaults.set(language.rawValue, forKey: "interface.language")
            Localization.shared.language = language
        }
    }
    public var appearance: AppAppearance {
        didSet { defaults.set(appearance.rawValue, forKey: "interface.appearance") }
    }
    public var accent: ThemeAccent {
        didSet { defaults.set(accent.rawValue, forKey: "theme.accent") }
    }
    public var defaultShowGrid: Bool { didSet { defaults.set(defaultShowGrid, forKey: "editor.showGrid") } }
    public var defaultSnapToGrid: Bool { didSet { defaults.set(defaultSnapToGrid, forKey: "editor.snapGrid") } }
    public var startInWorkspace: Bool { didSet { defaults.set(startInWorkspace, forKey: "startup.workspace") } }
    public var pngScale: Double { didSet { defaults.set(pngScale, forKey: "export.pngScale") } }
    public var aiConfig: AIModelConfig { didSet { persist(aiConfig, forKey: "ai.config") } }
    public var mcpServers: [MCPServer] { didSet { persist(mcpServers, forKey: "ai.mcp") } }
    public var apiKey: String { didSet { AIKeychain.set(apiKey) } }
    private func persist<T: Encodable>(_ value: T, forKey key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        language = AppLanguage(rawValue: defaults.string(forKey: "interface.language") ?? "system") ?? .system
        appearance = AppAppearance(rawValue: defaults.string(forKey: "interface.appearance") ?? "system") ?? .system
        accent = ThemeAccent(rawValue: defaults.string(forKey: "theme.accent") ?? "indigo") ?? .indigo
        defaultShowGrid = defaults.object(forKey: "editor.showGrid") as? Bool ?? true
        defaultSnapToGrid = defaults.object(forKey: "editor.snapGrid") as? Bool ?? true
        startInWorkspace = defaults.object(forKey: "startup.workspace") as? Bool ?? true
        let scale = defaults.double(forKey: "export.pngScale")
        pngScale = [1.0, 2.0].contains(scale) ? scale : 2
        if let data = defaults.data(forKey: "ai.config"),
            let config = try? JSONDecoder().decode(AIModelConfig.self, from: data)
        { aiConfig = config } else { aiConfig = .default }
        if let data = defaults.data(forKey: "ai.mcp"),
            let servers = try? JSONDecoder().decode([MCPServer].self, from: data)
        { mcpServers = servers } else { mcpServers = [] }
        apiKey = AIKeychain.get()
        Localization.shared.language = language
    }
}
