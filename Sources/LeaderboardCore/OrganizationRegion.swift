import Foundation

/// Distinguishes Chinese (mainland) model providers from overseas ones
/// so the UI can badge domestic models.
public enum OrganizationRegion {
    public static func isChinese(_ organization: String?) -> Bool {
        chineseKeys.contains(normalized(organization))
    }

    private static let chineseKeys: Set<String> = [
        "alibaba", "zai", "kimi", "deepseek", "stepfun", "tencent", "minimax"
    ]

    private static func normalized(_ organization: String?) -> String {
        let words = (organization ?? "")
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .joined()
        switch words {
        case "moonshot":
            return "kimi"
        default:
            return words
        }
    }
}
