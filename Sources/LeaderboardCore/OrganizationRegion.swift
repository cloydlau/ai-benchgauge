import Foundation

/// Distinguishes Chinese (mainland) models from overseas ones so the UI can
/// badge domestic models. Coding-agent rows name the harness as the
/// organization (Opencode, Claude Code, Codex), so the hosted model is read
/// from the display name when the organization itself is not Chinese.
public enum OrganizationRegion {
    public static func isChinese(_ organization: String?, modelName: String? = nil) -> Bool {
        if chineseKeys.contains(normalized(organization)) {
            return true
        }
        return modelTokens(modelName).contains(where: isChineseModelToken)
    }

    private static let chineseKeys: Set<String> = [
        "qwen", "zai", "kimi", "deepseek", "stepfun", "tencent", "minimax",
        "xiaomi", "bytedance", "klingai"
    ]

    /// Family tokens. A version may be glued on (`Qwen3.8` → `qwen3`), so a
    /// match is the token itself or the token plus a leading digit.
    private static let chineseModelTokens: Set<String> = [
        "glm", "qwen", "deepseek", "kimi", "minimax", "stepfun", "hunyuan",
        "doubao", "mimo", "kling", "seedance", "seedream", "wan"
    ]

    private static func normalized(_ organization: String?) -> String {
        let words = (organization ?? "")
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .joined()
        switch words {
        case "moonshot", "moonshotai":
            return "kimi"
        case "alibaba", "alibabaath":
            return "qwen"
        case "bytedanceseed":
            return "bytedance"
        default:
            return words
        }
    }

    private static func modelTokens(_ modelName: String?) -> [String] {
        (modelName ?? "")
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
    }

    private static func isChineseModelToken(_ token: String) -> Bool {
        chineseModelTokens.contains { family in
            if token == family { return true }
            guard token.hasPrefix(family), token.count > family.count else { return false }
            return token[token.index(token.startIndex, offsetBy: family.count)].isNumber
        }
    }
}
