import Foundation
import Observation

public enum AppLanguage: String, CaseIterable, Sendable {
    case system
    case simplifiedChinese = "zh-Hans"
    case english = "en"
    public var identifier: String {
        if self != .system { return rawValue }
        return Locale.preferredLanguages.first?.hasPrefix("zh") == true ? "zh-Hans" : "en"
    }
    public var displayName: String {
        switch self {
        case .system: "跟随系统 / System"
        case .simplifiedChinese: "简体中文"
        case .english: "English"
        }
    }
}

@MainActor @Observable public final class Localization {
    public static let shared = Localization()
    public var language: AppLanguage = .system
    private init() {}
    public func text(_ source: String) -> String { Self.text(source, language: language) }
    public nonisolated static func text(_ source: String, language: AppLanguage) -> String {
        guard let path = Bundle.module.path(forResource: language.identifier, ofType: "lproj"),
            let bundle = Bundle(path: path)
        else { return source }
        return bundle.localizedString(forKey: source, value: source, table: "Localizable")
    }
}
@MainActor public func tr(_ source: String) -> String { Localization.shared.text(source) }
