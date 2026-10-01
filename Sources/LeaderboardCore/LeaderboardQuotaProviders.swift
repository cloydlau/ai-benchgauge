import Foundation
import LeaderboardKit
#if canImport(CoreFoundation)
import CoreFoundation
#endif

public struct OfficialQuotaProvider: Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let organizationKey: String
    public let kind: CCSwitchQuotaKind
    public let baseURL: String
    public let websiteURL: URL
    public let quotaDescription: String
}

/// Development scope is the union of all four categories, not the selected tab.
/// Existing accounts are never deleted when a model falls out of the top 20.
public enum LeaderboardQuotaProviders {
    public static func rankedOrganizations(in snapshot: LeaderboardSnapshot) -> Set<String> {
        Set(LeaderboardCategory.allCases.flatMap(\.boardKinds).flatMap { kind in
            (snapshot.boards[kind]?.entries ?? []).compactMap { entry in
                OrganizationLogoCatalog.resolvedKey(organization: entry.organization, modelName: entry.name)
            }
        })
    }

    /// Only implemented, credential-backed queries appear in the add-account menu.
    /// Separate region choices preserve the account scope of MiniMax / GLM keys.
    public static let keyProviders: [OfficialQuotaProvider] = [
        provider("kimi", "Kimi Code", "kimi", .kimi, "https://api.kimi.com/coding/v1", "https://www.kimi.com/code", "Kimi Code plan"),
        provider("zhipu-cn", "GLM · China", "zai", .zhipu, "https://open.bigmodel.cn/api/paas/v4", "https://bigmodel.cn/glm-coding", "GLM Coding Plan"),
        provider("zhipu-global", "GLM · Global", "zai", .zhipu, "https://api.z.ai/api/paas/v4", "https://z.ai/subscribe", "GLM Coding Plan"),
        provider("deepseek", "DeepSeek", "deepseek", .deepseek, "https://api.deepseek.com", "https://platform.deepseek.com/top_up", "API balance"),
        provider("minimax-cn", "MiniMax · China", "minimax", .minimax, "https://api.minimaxi.com", "https://platform.minimaxi.com/user-center/payment/coding-plan", "Coding Plan; separate from Hailuo video credits"),
        provider("minimax-global", "MiniMax · Global", "minimax", .minimax, "https://api.minimax.io", "https://platform.minimax.io/user-center/payment/coding-plan", "Coding Plan; separate from Hailuo video credits"),
        provider("stepfun", "StepFun", "stepfun", .stepfun, "https://api.stepfun.com/v1", "https://platform.stepfun.ai", "API balance"),
        provider("bfl", "Black Forest Labs", "blackforestlabs", .blackForestLabs, "https://api.bfl.ai/v1", "https://dashboard.bfl.ai", "API credits"),
        provider("luma", "Luma", "luma", .luma, "https://api.lumalabs.ai/dream-machine/v1", "https://lumalabs.ai/api", "API balance; separate from Dream Machine subscriptions"),
    ]

    public static func kind(forBaseURL value: String) -> CCSwitchQuotaKind? {
        guard let url = URL(string: value), url.scheme?.lowercased() == "https",
              url.user == nil, url.password == nil, url.port == nil || url.port == 443,
              let host = url.host?.lowercased() else { return nil }
        switch host {
        case "api.minimaxi.com", "api.minimax.cn", "api.minimax.io": return .minimax
        case "api.stepfun.com", "api.stepfun.ai": return .stepfun
        case "api.bfl.ai", "api.bfl.ml", "api.us1.bfl.ai", "api.eu1.bfl.ai": return .blackForestLabs
        case "api.lumalabs.ai": return .luma
        default: return nil
        }
    }

    private static func provider(_ id: String, _ name: String, _ key: String, _ kind: CCSwitchQuotaKind,
                                 _ base: String, _ website: String, _ description: String) -> OfficialQuotaProvider {
        OfficialQuotaProvider(id: id, name: name, organizationKey: key, kind: kind,
                              baseURL: base, websiteURL: URL(string: website)!, quotaDescription: description)
    }
}

public enum LeaderboardQuotaParsers {
    public static func claude(_ data: Data) -> ProviderQuotaParseResult {
        guard let root = object(data), root["error"] == nil else { return .rejected }
        let windows = ["five_hour", "seven_day", "seven_day_opus", "seven_day_sonnet", "seven_day_fable"].compactMap { key -> ParsedQuotaWindow? in
            guard let item = root[key] as? [String: Any], let used = percentage(item["utilization"]) else { return nil }
            return ParsedQuotaWindow(name: key, utilization: used,
                                     resetsAt: (item["resets_at"] as? String).flatMap(CCSwitchJSON.isoDate))
        }
        return windows.isEmpty ? .rejected : .windows(windows)
    }

    public static func gemini(_ data: Data) -> ProviderQuotaParseResult {
        guard let root = object(data), let buckets = root["buckets"] as? [[String: Any]] else { return .rejected }
        var byModel: [String: ParsedQuotaWindow] = [:]
        for item in buckets {
            guard let model = item["modelId"] as? String, !model.isEmpty,
                  let remaining = number(item["remainingFraction"]), remaining.isFinite,
                  (0...1).contains(remaining) else { continue }
            let key = model.lowercased().contains("flash-lite") ? "gemini_flash_lite"
                : (model.lowercased().contains("flash") ? "gemini_flash"
                   : (model.lowercased().contains("pro") ? "gemini_pro" : model))
            let window = ParsedQuotaWindow(name: key, utilization: (1 - remaining) * 100,
                                           resetsAt: (item["resetTime"] as? String).flatMap(CCSwitchJSON.isoDate))
            if byModel[key].map({ $0.utilization < window.utilization }) ?? true { byModel[key] = window }
        }
        let windows = byModel.keys.sorted().compactMap { byModel[$0] }
        return windows.isEmpty ? .rejected : .windows(windows)
    }

    /// CC Switch's current MiniMax template selects `general`; `video` is a
    /// different pool and must never be presented as Coding Plan quota.
    public static func miniMax(_ data: Data) -> ProviderQuotaParseResult {
        guard let root = object(data),
              (root["base_resp"] as? [String: Any]).map({ number($0["status_code"]) == 0 }) ?? true,
              let items = root["model_remains"] as? [[String: Any]],
              let item = items.first(where: { $0["model_name"] as? String == "general" }) else { return .rejected }
        var windows: [ParsedQuotaWindow] = []
        if let remaining = percentage(item["current_interval_remaining_percent"]) {
            windows.append(ParsedQuotaWindow(name: "five_hour", utilization: 100 - remaining,
                                             resetsAt: millis(item["end_time"])))
        }
        if number(item["current_weekly_status"]) == 1,
           let remaining = percentage(item["current_weekly_remaining_percent"]) {
            windows.append(ParsedQuotaWindow(name: "weekly_limit", utilization: 100 - remaining,
                                             resetsAt: millis(item["weekly_end_time"])))
        }
        return windows.isEmpty ? .rejected : .windows(windows)
    }

    public static func stepFun(_ data: Data) -> ProviderQuotaParseResult {
        balance(data, field: "balance", currency: "CNY", divisor: 1)
    }

    public static func blackForestLabs(_ data: Data) -> ProviderQuotaParseResult {
        balance(data, field: "credits", currency: "credits", divisor: 1)
    }

    /// Official Luma `credit_balance` is cents USD, not a count of generations.
    public static func luma(_ data: Data) -> ProviderQuotaParseResult {
        balance(data, field: "credit_balance", currency: "USD", divisor: 100)
    }

    private static func balance(_ data: Data, field: String, currency: String, divisor: Double) -> ProviderQuotaParseResult {
        guard let root = object(data), root["error"] == nil,
              let amount = number(root[field]), amount.isFinite, amount >= 0 else { return .rejected }
        return .balances([ParsedBalance(currency: currency, amount: amount / divisor)])
    }

    private static func object(_ data: Data) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func number(_ value: Any?) -> Double? {
        guard let value, !CCSwitchJSON.isBoolean(value) else { return nil }
        if let value = value as? NSNumber {
            return value.doubleValue
        }
        if let value = value as? String { return Double(value) }
        return nil
    }

    private static func percentage(_ value: Any?) -> Double? {
        guard let n = number(value), n.isFinite, (0...100).contains(n) else { return nil }
        return n
    }

    private static func millis(_ value: Any?) -> Date? {
        guard let n = number(value), n.isFinite, n > 0, n < 253_402_300_800_000 else { return nil }
        return Date(timeIntervalSince1970: n / 1000)
    }
}
