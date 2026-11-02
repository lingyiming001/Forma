import FormaLocalization
import SwiftUI

public enum FormaTheme {
    /// 当前强调色分量，可由设置面板切换主题时写入（仅主线程访问）。
    @MainActor public static var accentRGB: (red: Double, green: Double, blue: Double) = (0.30, 0.36, 0.93)
    @MainActor public static var accent: Color {
        Color(red: accentRGB.red, green: accentRGB.green, blue: accentRGB.blue)
    }
    @MainActor public static func setAccent(red: Double, green: Double, blue: Double) {
        accentRGB = (red, green, blue)
    }
    public static let gradient = LinearGradient(
        colors: [
            Color(red: 0.20, green: 0.35, blue: 1), Color(red: 0.45, green: 0.34, blue: 0.98),
            Color(red: 0.39, green: 0.77, blue: 0.98),
        ], startPoint: .bottomLeading, endPoint: .topTrailing)
    public static let panel = Color(nsColor: .windowBackgroundColor)
}

public struct InspectorSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    public init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tr(title)).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            content()
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
    }
}

public struct ToolIcon: View {
    let symbol: String
    let title: String
    let selected: Bool
    let action: () -> Void
    public init(_ symbol: String, title: String, selected: Bool = false, action: @escaping () -> Void) {
        self.symbol = symbol
        self.title = title
        self.selected = selected
        self.action = action
    }
    public var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 15, weight: .medium)).frame(width: 32, height: 30)
                .foregroundStyle(selected ? FormaTheme.accent : Color.primary)
                .background(
                    selected ? FormaTheme.accent.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain).help(tr(title)).accessibilityLabel(tr(title)).accessibilityAddTraits(
            selected ? .isSelected : [])
    }
}
