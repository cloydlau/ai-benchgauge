import Foundation

public enum OrganizationCountry: String, CaseIterable, Sendable {
    case china, unitedStates, canada, france, germany, singapore

    public var regionCode: String {
        switch self {
        case .china: "CN"
        case .unitedStates: "US"
        case .canada: "CA"
        case .france: "FR"
        case .germany: "DE"
        case .singapore: "SG"
        }
    }

    public var flagEmoji: String {
        let regionalIndicatorBase: UInt32 = 0x1F1E6
        let scalars = regionCode.utf8.map { byte in
            Unicode.Scalar(regionalIndicatorBase + UInt32(byte - 65))!
        }
        return String(String.UnicodeScalarView(scalars))
    }

    /// System locale data supplies the hover and accessibility name.
    public func localizedName(language: AppLanguage) -> String {
        language.locale.localizedString(forRegionCode: regionCode) ?? regionCode
    }
}

/// Country of the model developer's headquarters. Coding harnesses follow
/// the lead model, while a company row follows the company's own key.
public enum OrganizationRegion {
    public static func country(_ organization: String?, modelName: String? = nil) -> OrganizationCountry? {
        guard let key = OrganizationLogoCatalog.developerKey(
            organization: organization,
            modelName: modelName
        ) else { return nil }
        switch key {
        case "qwen", "zai", "stepfun", "kimi", "deepseek", "tencent", "minimax",
             "bytedance", "xiaomi", "klingai":
            return .china
        case "anthropic", "openai", "spacexai", "google", "meta", "nvidia",
             "microsoftai", "krea", "runway", "luma", "fal", "opencode",
             "devin", "reve", "thinkingmachines", "github":
            return .unitedStates
        case "ideogram": return .canada
        case "mistral": return .france
        case "blackforestlabs": return .germany
        case "pixverse", "videorebirth": return .singapore
        default: return nil
        }
    }

    public static func isChinese(_ organization: String?, modelName: String? = nil) -> Bool {
        country(organization, modelName: modelName) == .china
    }
}
