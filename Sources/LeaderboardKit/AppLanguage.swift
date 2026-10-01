import Foundation

/// The interface follows the system's preferred languages until the user chooses one.
public enum AppLanguage: String, CaseIterable, Sendable {
    case english = "en"
    case chinese = "zh"
    case traditionalChinese = "zh-Hant"

    public static let preferenceKey = "interfaceLanguage"

    public static func load(
        from defaults: UserDefaults = .standard,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> AppLanguage {
        if let raw = defaults.string(forKey: preferenceKey),
           let saved = AppLanguage(rawValue: raw) {
            return saved
        }
        for identifier in preferredLanguages {
            let language = Locale(identifier: identifier).language
            switch language.languageCode?.identifier {
            case "zh":
                return language.script?.identifier == "Hant" ? .traditionalChinese : .chinese
            case "en":
                return .english
            default:
                continue
            }
        }
        return .english
    }

    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.preferenceKey)
    }

    public func text(_ english: String, _ chinese: String) -> String {
        switch self {
        case .english: english
        case .chinese: chinese
        case .traditionalChinese: Self.traditional(chinese)
        }
    }

    public var locale: Locale {
        switch self {
        case .english: Locale(identifier: "en_US")
        case .chinese: Locale(identifier: "zh_CN")
        case .traditionalChinese: Locale(identifier: "zh_Hant")
        }
    }

    private static func traditional(_ value: String) -> String {
        value.applyingTransform(StringTransform("Hans-Hant"), reverse: false) ?? value
    }

}
