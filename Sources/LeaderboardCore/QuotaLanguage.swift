import Foundation
import LeaderboardKit

public extension AppLanguage {
    func providerName(_ kind: CCSwitchQuotaKind) -> String {
        switch kind {
        case .officialNote: "OpenAI"
        case .kimi: "Kimi"
        case .deepseek: "DeepSeek"
        case .xaiOAuth: "xAI"
        case .zhipu: "GLM"
        case .qwen: "Qwen"
        case .minimax: "MiniMax"
        case .stepfun: "StepFun"
        case .blackForestLabs: "Black Forest Labs"
        case .luma: "Luma"
        case .claude: "Claude"
        case .gemini: "Gemini"
        }
    }

    /// Quota values arrive as structured data, but the existing formatter also
    /// produces a few fixed Chinese phrases. Convert only that known UI copy.
    /// Model and company names never pass through this function.
    func quotaText(_ value: String) -> String {
        if self == .traditionalChinese {
            // A lone “余” is ambiguous to ICU; this label means remaining balance.
            let copy = value.hasPrefix("余 ") ? "餘 " + value.dropFirst(2) : value
            return text("", copy)
        }
        guard self == .english else { return value }
        let exact: [String: String] = [
            "查询中": "Checking", "查询失败": "Check failed",
            "需要重新登录": "Sign in again", "未配置": "Not configured",
            "未登录": "Not signed in", "网络错误": "Network error",
            "无可用余额": "No balance", "未连接": "Connect",
            AccountQuotaMessage.autoRenewing: "Auto-renew",
            "等待授权": "Waiting for authorization",
            "MiniMax Coding Plan 套餐额度，与海螺视频额度独立": "MiniMax Coding Plan quota; Hailuo video credits are separate",
            "Luma API 余额，与 Dream Machine 网页订阅额度独立": "Luma API balance; Dream Machine subscription credits are separate",
            "StepFun API 账户余额": "StepFun API account balance",
            "Claude 官方订阅额度；登录过期时请在官方客户端重新登录": "Claude subscription quota; sign in again in the official client when the login expires",
            "Gemini Code Assist 额度，与图片和视频 API 计费独立；登录过期时请在官方客户端重新登录": "Gemini Code Assist quota; image/video API billing is separate. Sign in again in the official client when the login expires",
            "请在浏览器中完成 OpenAI 授权": "Complete OpenAI authorization in your browser",
            "正在查询官方用量": "Checking official usage",
            "没有可用的 API Key 或供应商令牌，未发起查询": "No API key or provider token; no query sent",
            "没有可用的 xAI 登录，未发起查询": "No xAI sign-in; no query sent",
            "Grok 登录在 CC Switch 中完成，请在 CC Switch 中登录": "Grok sign-in is completed in CC Switch; sign in there",
            AccountQuotaMessage.xaiSubscriptionHelp: "Click to connect the xAI plan inside the app; dates refresh automatically and are checked against the quota account",
            "只显示千问账号套餐剩余，多设备共用，不统计本机请求": "Shows the Qwen account plan balance shared across devices",
            "当前供应商": "Current provider",
            "套餐日期来自已保存的查询结果；接口暂时不可用": "Plan date from a saved query; the endpoint is temporarily unavailable",
            "千问官网套餐额度（qianwen CLI 当前登录账号）": "Qwen plan quota (current qianwen CLI account)",
            "千问官网个人版用量（网页显示的剩余百分比；网页未提供精确 Credits）": "Qwen personal plan remaining percentage; exact credits are unavailable",
            "本期将在2天内结束": "Current period ends within 2 days",
            AccountQuotaFormatting.deadlineColorReference: "Date colors: 14+ days remaining green, 7 days yellow, 2 days orange, 0 days red; continuous transitions. The date only marks the current period boundary.",
        ]
        if let translated = exact[value] { return translated }
        if value.hasPrefix("重置") {
            return "Resets " + Self.englishDate(in: String(value.dropFirst(2)))
        }
        if value.hasPrefix("余量达到") {
            return value.replacingOccurrences(of: "余量达到", with: "Remaining quota reached ")
        }
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
            ("后重置", " until reset"), ("重置", " resets "),
            ("额度", "credits"), ("余额 ", "Balance "),
            ("剩余 ", "Remaining "), ("余 ", "Balance "), ("截至", "Until "), ("至", "to "),
            ("；", "; "), ("，", ", "),
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
