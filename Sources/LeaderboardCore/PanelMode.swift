import Foundation

public enum PanelMode: String, CaseIterable, Identifiable, Sendable {
    case clickToClose
    case alwaysOnTop
    case closeOnBlur
    case window

    public var id: String { rawValue }
    public var closesOnFocusLoss: Bool { self == .closeOnBlur }
    public var staysOnTop: Bool { self == .alwaysOnTop }

    public func title(language: AppLanguage) -> String {
        switch self {
        case .clickToClose: language.text("Keep open", "保持打开")
        case .alwaysOnTop: language.text("Always on top", "保持置顶")
        case .closeOnBlur: language.text("Close on blur", "失焦关闭")
        case .window: language.text("Window", "独立窗口")
        }
    }
}

public enum PanelModePreference {
    public static let userDefaultsKey = "AIBenchGauge.panelMode"
    public static let legacyFocusLossKey = "AIBenchGauge.closesOnFocusLoss"

    public static func load(from defaults: UserDefaults = .standard) -> PanelMode {
        if let raw = defaults.string(forKey: userDefaultsKey), let mode = PanelMode(rawValue: raw) {
            return mode
        }
        return defaults.bool(forKey: legacyFocusLossKey) ? .closeOnBlur : .clickToClose
    }

    public static func save(_ mode: PanelMode, to defaults: UserDefaults = .standard) {
        defaults.set(mode.rawValue, forKey: userDefaultsKey)
    }
}
