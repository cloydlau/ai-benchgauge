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

    public func providerName(_ kind: CCSwitchQuotaKind) -> String {
        switch kind {
        case .officialNote: "OpenAI"
        case .kimi: "Kimi"
        case .deepseek: "DeepSeek"
        case .xaiOAuth: "xAI"
        case .zhipu: "GLM"
        case .qwen: "Qwen"
        }
    }

    /// Quota values arrive as structured data, but the existing formatter also
    /// produces a few fixed Chinese phrases. Convert only that known UI copy.
    /// Model and company names never pass through this function.
    public func quotaText(_ value: String) -> String {
        if self == .traditionalChinese { return Self.traditional(value) }
        guard self == .english else { return value }
        let exact: [String: String] = [
            "查询中": "Checking", "查询失败": "Check failed",
            "需要重新登录": "Sign in again", "未配置": "Not configured",
            "未登录": "Not signed in", "网络错误": "Network error",
            "无可用余额": "No balance", "未连接": "Connect",
            "正在查询官方用量": "Checking official usage",
            "没有可用的 API Key 或供应商令牌，未发起查询": "No API key or provider token; no query sent",
            "没有可用的 xAI 登录，未发起查询": "No xAI sign-in; no query sent",
            "只显示千问账号套餐剩余，多设备共用，不统计本机请求": "Shows the Qwen account plan balance shared across devices",
            "当前供应商": "Current provider",
            "千问官网套餐额度（qianwen CLI 当前登录账号）": "Qwen plan quota (current qianwen CLI account)",
            "千问官网个人版用量（网页显示的剩余百分比；网页未提供精确 Credits）": "Qwen personal plan remaining percentage; exact credits are unavailable",
            "已到期": "Expired",
        ]
        if let translated = exact[value] { return translated }
        if value.hasPrefix("余量达到") {
            return value.replacingOccurrences(of: "余量达到", with: "Remaining quota reached ")
        }
        if value == "2天内到期" { return "Expires within 2 days" }
        if value == "2天内重置" { return "Resets within 2 days" }
        if value.contains("额度 "), value.contains("后重置") {
            return value.components(separatedBy: "；").map { part in
                guard let quota = part.range(of: "额度 "),
                      let reset = part.range(of: "后重置") else { return quotaText(part) }
                let label = quotaText(String(part[..<quota.lowerBound]))
                let duration = Self.englishDuration(String(part[quota.upperBound..<reset.lowerBound]))
                let after = quotaText(String(part[reset.upperBound...]))
                    .replacingOccurrences(of: "，", with: ", ")
                return "\(label) quota resets in \(duration)\(after)"
            }.joined(separator: "; ")
        }
        if value.hasPrefix("千问官网个人版用量（官网本次读取失败，显示 ") {
            return value
                .replacingOccurrences(of: "千问官网个人版用量（官网本次读取失败，显示 ", with: "Qwen site unavailable; showing saved result from ")
                .replacingOccurrences(of: " 保存的结果）", with: "")
        }
        var result = value
        let replacements = [
            ("5小时", "5h"), ("7天", "7d"), ("1个月", "1 month"), ("月度", "1 month"),
            ("额度", "credits"), ("余额 ", "Balance "),
            ("剩余 ", "Remaining "), ("截至", "Until "),
            ("；", "; "), ("，", ", "), ("后重置", " until reset"),
        ]
        for (source, target) in replacements {
            result = result.replacingOccurrences(of: source, with: target)
        }
        if result.contains("月"), result.contains("日") {
            result = Self.englishDate(in: result)
        }
        return result
    }

    private static func englishDuration(_ value: String) -> String {
        var result = value.replacingOccurrences(of: "不到1分钟", with: "less than 1 minute")
        for (unit, english) in [("天", "d"), ("小时", "h"), ("分钟", "m"), ("分", "m")] {
            result = result.replacingOccurrences(of: unit, with: english)
        }
        return result
    }

    private static func englishDate(in value: String) -> String {
        let pattern = #"([0-9]{1,2})月([0-9]{1,2})日(?:([0-9]{1,2})时(?:([0-9]{1,2})分)?)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return value }
        var result = value
        let matches = regex.matches(in: value, range: NSRange(value.startIndex..., in: value))
        for match in matches.reversed() {
            guard let full = Range(match.range, in: result),
                  let monthRange = Range(match.range(at: 1), in: result),
                  let month = Int(result[monthRange]), (1...12).contains(month),
                  let dayRange = Range(match.range(at: 2), in: result) else { continue }
            let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
            var replacement = "\(months[month - 1]) \(result[dayRange])"
            if let hourRange = Range(match.range(at: 3), in: result) {
                let hour = Int(result[hourRange]) ?? 0
                let minute = Range(match.range(at: 4), in: result).flatMap { Int(result[$0]) } ?? 0
                replacement += String(format: ", %02d:%02d", hour, minute)
            }
            result.replaceSubrange(full, with: replacement)
        }
        return result
    }
}
