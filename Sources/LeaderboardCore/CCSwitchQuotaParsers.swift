import LeaderboardKit
import Foundation
#if canImport(CoreFoundation)
import CoreFoundation
#endif

/// Response-body parsers for CC Switch Codex quota providers.
///
/// These functions never see credentials. Callers map `.rejected` to the
/// fixed "查询失败" string and must not surface raw response text.
public enum CCSwitchQuotaParsers {
    /// Account-only app-server response. Select the Codex bucket explicitly;
    /// other metered limits must not replace the account's coding quota.
    public static func parseOpenAIAppServer(_ data: Data) -> ProviderQuotaParseResult {
        guard let body = jsonObject(data) else { return .rejected }
        let byID = body["rateLimitsByLimitId"] as? [String: Any]
        let limit = (byID?["codex"] as? [String: Any]) ?? (body["rateLimits"] as? [String: Any])
        guard let limit, (limit["limitId"] as? String).map({ $0 == "codex" }) ?? true else { return .rejected }
        let windows = ["primary", "secondary"].compactMap { key -> ParsedQuotaWindow? in
            guard let window = limit[key] as? [String: Any],
                  let used = jsonDouble(window["usedPercent"]), used.isFinite else { return nil }
            let minutes = jsonInt(window["windowDurationMins"]) ?? 0
            guard minutes >= 0, minutes <= Int64.max / 60 else { return nil }
            return ParsedQuotaWindow(
                name: windowName(seconds: minutes * 60, fallback: key == "primary" ? "five_hour" : "weekly_limit"),
                utilization: min(max(used, 0), 100), resetsAt: resetDate(window["resetsAt"])
            )
        }
        return .windows(windows)
    }

    /// Parses the Codex official `backend-api/wham/usage` response.
    public static func parseOpenAI(_ data: Data) -> ProviderQuotaParseResult {
        guard let body = jsonObject(data),
              let rateLimit = body["rate_limit"] as? [String: Any] else {
            return .rejected
        }
        let preferred = ["primary_window", "secondary_window"]
        let keys = preferred + rateLimit.keys.filter { !preferred.contains($0) }.sorted()
        let windows = keys.compactMap { openAIWindow(key: $0, value: rateLimit[$0]) }
        return .windows(windows)
    }

    /// `primary_window` then `secondary_window`. Dictionary iteration is not
    /// JSON order, and must not swap the 5-hour and 7-day windows.
    private static func openAIWindow(key: String, value: Any?) -> ParsedQuotaWindow? {
        guard let object = value as? [String: Any],
              let used = jsonDouble(object["used_percent"]),
              used.isFinite else { return nil }
        let name: String
        switch key {
        case "primary_window":
            name = windowName(seconds: jsonInt(object["limit_window_seconds"]) ?? 0, fallback: "five_hour")
        case "secondary_window":
            name = windowName(seconds: jsonInt(object["limit_window_seconds"]) ?? 0, fallback: "weekly_limit")
        default:
            name = key
        }
        return ParsedQuotaWindow(
            name: name,
            utilization: min(max(used, 0), 100),
            resetsAt: resetDate(object["reset_at"])
        )
    }

    /// Entitlement boundary from `GET /backend-api/accounts/check/v4-2023-04-27`.
    /// Only `entitlement.expires_at` of the account the request was made for,
    /// which ChatGPT keys `default` rather than by its id. Neither date
    /// establishes cancellation or renewal status. `renews_at` is a billing
    /// date, not this entitlement boundary. A plan without an active
    /// subscription reports a far-future placeholder instead of a boundary.
    /// Nil when the account does not match or the field is missing, so the
    /// usage card still succeeds.
    public static func parseOpenAIPlanExpiry(_ data: Data, accountID: String) -> ParsedQuotaWindow? {
        let accountID = accountID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !accountID.isEmpty,
              let body = jsonObject(data),
              let accounts = body["accounts"] as? [String: Any],
              let account = openAIAccount(
                  in: accounts,
                  accountID: accountID,
                  selectedKey: accountIdentifier(body["last_account_id"])
              ),
              let entitlement = account["entitlement"] as? [String: Any],
              entitlement["has_active_subscription"] as? Bool != false,
              let expiresAt = resetDate(entitlement["expires_at"]) else {
            return nil
        }
        return ParsedQuotaWindow(
            name: ParsedQuotaWindow.planExpiryName,
            utilization: 0,
            resetsAt: expiresAt
        )
    }

    /// The entry that belongs to `accountID`. A real response keys the signed
    /// in account `default` and repeats that key in `last_account_id`, so an
    /// entry qualifies by the id it names, by its own id key, or by a self key.
    /// An entry naming a different id is never used, so another account's date
    /// cannot be shown.
    private static func openAIAccount(
        in accounts: [String: Any],
        accountID: String,
        selectedKey: String?
    ) -> [String: Any]? {
        let entries = accounts.compactMap { key, value -> (key: String, id: String?, account: [String: Any])? in
            guard let account = value as? [String: Any] else { return nil }
            return (key, accountIdentifier(account["account_id"]), account)
        }.filter { $0.id == nil || $0.id == accountID }
        if let named = entries.first(where: { $0.id == accountID }) { return named.account }
        for key in [accountID, selectedKey, "default"].compactMap({ $0 }) {
            let keyed = entries.filter { $0.key == key }
            if keyed.count == 1 { return keyed[0].account }
        }
        return nil
    }

    private static func accountIdentifier(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Kimi Code `GET /coding/v1/usages`, the CLI `quota.usages` body, and the
    /// web `usages[]` list. Ratio pools win for the windows they report.
    /// A zero 5-hour or weekly ratio falls back to a same-duration count only
    /// when that count has usage, the weekly count is reliable, there is no
    /// monthly ratio, and the resets differ by at most two seconds. A reset
    /// that does not parse stays nil.
    public static func parseKimi(_ data: Data) -> ProviderQuotaParseResult {
        guard let body = jsonObject(data) else { return .rejected }
        if let usages = body["usages"] as? [Any] {
            guard let coding = usages.compactMap({ $0 as? [String: Any] }).first(where: {
                ($0["scope"] as? String) == "FEATURE_CODING"
            }) else {
                return .windows([])
            }
            return .windows(kimiCountWindows(from: coding).map(\.window))
        }
        let counts = kimiCountWindows(from: body)
        guard let pools = kimiRatioPools(in: body) else {
            return .windows(counts.map(\.window))
        }
        let ratios = kimiRatioWindows(pools)
        guard !ratios.isEmpty else {
            return .windows(counts.map(\.window))
        }
        return .windows(kimiMergedWindows(ratios: ratios, counts: counts))
    }

    /// Count windows keep the old source order: each `limits` item, then the
    /// weekly `usage` (or web `detail`). A missing window stays `five_hour`.
    private static func kimiCountWindows(from body: [String: Any]) -> [KimiCountWindow] {
        var windows: [KimiCountWindow] = []
        if let limits = body["limits"] as? [Any] {
            for item in limits {
                guard let object = item as? [String: Any],
                      let detail = object["detail"] as? [String: Any] else { continue }
                let minutes = sessionMatchMinutes(object)
                let stats = reliableUsedCount(detail)
                windows.append(
                    KimiCountWindow(
                        role: minutes == 300 ? .session : (minutes == 10_080 ? .weekly : .other),
                        name: minutes == 300 ? "five_hour" : (minutes == 10_080 ? "weekly_limit" : (minutes == 43_200 ? "monthly" : "credits")),
                        matchMinutes: minutes,
                        utilization: countUtilization(detail),
                        resetsAt: kimiResetDate(detail),
                        used: stats?.used ?? 0,
                        reliable: stats?.reliable == true
                    )
                )
            }
        }
        if let usage = body["usage"] as? [String: Any] {
            windows.append(kimiWeeklyCount(usage))
        } else if let detail = body["detail"] as? [String: Any],
                  detail["limit"] != nil || detail["remaining"] != nil || detail["used"] != nil {
            windows.append(kimiWeeklyCount(detail))
        }
        return windows
    }

    private static func kimiWeeklyCount(_ detail: [String: Any]) -> KimiCountWindow {
        let stats = reliableUsedCount(detail)
        return KimiCountWindow(
            role: .weekly,
            name: "weekly_limit",
            matchMinutes: 10_080,
            utilization: countUtilization(detail),
            resetsAt: kimiResetDate(detail),
            used: stats?.used ?? 0,
            reliable: stats?.reliable == true
        )
    }

    /// `remaining` stays authoritative so older count fixtures keep their
    /// percentages. `used` fills in only when remaining is absent.
    private static func countUtilization(_ detail: [String: Any]) -> Double {
        if detail["remaining"] != nil {
            return utilization(limit: detail["limit"], remaining: detail["remaining"])
        }
        if let used = jsonDouble(detail["used"]),
           let limit = jsonDouble(detail["limit"]),
           limit > 0 {
            return max(used, 0) / limit * 100
        }
        return utilization(limit: detail["limit"], remaining: detail["remaining"])
    }

    /// Integer counters only. A valid limit with no usable used/remaining is
    /// not reliable, so a zero ratio cannot borrow it.
    private static func reliableUsedCount(_ detail: [String: Any]) -> (used: Int, reliable: Bool)? {
        guard let limit = exactInt(detail["limit"]), limit > 0 else { return nil }
        if let used = exactInt(detail["used"]), used >= 0 {
            return (used, true)
        }
        if let remaining = exactInt(detail["remaining"]), (0...limit).contains(remaining) {
            return (limit - remaining, true)
        }
        return (0, false)
    }

    private static func exactInt(_ value: Any?) -> Int? {
        if value is NSNull || value.map(CCSwitchJSON.isBoolean) == true { return nil }
        if let text = value as? String {
            return Int(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        guard let number = value as? NSNumber else { return nil }
        let double = number.doubleValue
        guard double.isFinite else { return nil }
        return Int(exactly: double)
    }

    /// Missing window matches the 5-hour ratio. An unreadable window does not,
    /// so a different period cannot borrow the count.
    private static func sessionMatchMinutes(_ item: [String: Any]) -> Int? {
        guard item["window"] != nil, !(item["window"] is NSNull) else { return 300 }
        return windowMinutes(item["window"])
    }

    private static func windowMinutes(_ value: Any?) -> Int? {
        guard let window = value as? [String: Any] else { return nil }
        guard let duration = exactInt(window["duration"] ?? window["durationMinutes"]), duration > 0 else {
            return nil
        }
        let unit = (window["timeUnit"] as? String) ?? (window["time_unit"] as? String) ?? ""
        let multiplier: Int
        switch unit {
        case "TIME_UNIT_MINUTE": multiplier = 1
        case "TIME_UNIT_HOUR": multiplier = 60
        case "TIME_UNIT_DAY": multiplier = 24 * 60
        default: return nil
        }
        guard duration <= Int.max / multiplier else { return nil }
        let minutes = duration * multiplier
        return minutes > 0 ? minutes : nil
    }

    private static func kimiRatioPools(in body: [String: Any]) -> [String: Any]? {
        if let usages = body["usages"] as? [String: Any] { return usages }
        if let quota = body["quota"] as? [String: Any],
           let usages = quota["usages"] as? [String: Any] { return usages }
        guard let data = body["data"] as? [String: Any] else { return nil }
        if let quota = data["quota"] as? [String: Any],
           let usages = quota["usages"] as? [String: Any] { return usages }
        return data["usages"] as? [String: Any]
    }

    private static func kimiRatioWindows(_ pools: [String: Any]) -> KimiRatioSet {
        KimiRatioSet(
            session: kimiRatioWindow(pools, keys: ["limit_5h", "limit5h"], name: "five_hour"),
            weekly: kimiRatioWindow(pools, keys: ["limit_7d", "limit7d"], name: "weekly_limit"),
            monthly: kimiRatioWindow(pools, keys: ["limit_month_total", "monthTotal"], name: "monthly")
                ?? kimiRatioWindow(pools, keys: ["limit_month_code", "monthCode"], name: "monthly")
        )
    }

    /// 0...1 ratios become percents. Values above 1 clamp to 1 before scaling,
    /// so a ratio is never treated as an already-scaled percent.
    private static func kimiRatioWindow(
        _ pools: [String: Any],
        keys: [String],
        name: String
    ) -> ParsedQuotaWindow? {
        guard let entry = keys.lazy.compactMap({ pools[$0] as? [String: Any] }).first else { return nil }
        guard let ratio = jsonDouble(firstPresent(entry, keys: ["used_ratio", "usedRatio"])),
              ratio.isFinite else { return nil }
        return ParsedQuotaWindow(
            name: name,
            utilization: min(max(ratio, 0), 1) * 100,
            resetsAt: kimiResetDate(entry)
        )
    }

    private static func kimiMergedWindows(
        ratios: KimiRatioSet,
        counts: [KimiCountWindow]
    ) -> [ParsedQuotaWindow] {
        let sessions = counts.filter { $0.role == .session }
        let weeklyCount = counts.last { $0.role == .weekly }
        let weeklyReliable = weeklyCount?.reliable == true
        var windows: [ParsedQuotaWindow] = []
        if let session = ratios.session {
            if kimiShouldUseCount(
                ratio: session,
                count: sessions.first,
                expectedMinutes: 300,
                weeklyReliable: weeklyReliable,
                monthlyPresent: ratios.monthly != nil
            ), let count = sessions.first {
                windows.append(count.window)
            } else {
                windows.append(session)
            }
        } else {
            windows.append(contentsOf: sessions.map(\.window))
        }
        if let weekly = ratios.weekly {
            if kimiShouldUseCount(
                ratio: weekly,
                count: weeklyCount,
                expectedMinutes: 10_080,
                weeklyReliable: weeklyReliable,
                monthlyPresent: ratios.monthly != nil
            ), let weeklyCount {
                windows.append(weeklyCount.window)
            } else {
                windows.append(weekly)
            }
        } else if let weeklyCount {
            windows.append(weeklyCount.window)
        }
        windows.append(contentsOf: counts.filter {
            $0.role == .other && ($0.name != "monthly" || ratios.monthly == nil)
        }.map(\.window))
        if let monthly = ratios.monthly {
            windows.append(monthly)
        }
        return windows
    }

    private static func kimiShouldUseCount(
        ratio: ParsedQuotaWindow,
        count: KimiCountWindow?,
        expectedMinutes: Int,
        weeklyReliable: Bool,
        monthlyPresent: Bool
    ) -> Bool {
        guard ratio.utilization == 0, !monthlyPresent, weeklyReliable else { return false }
        guard let count, count.reliable, count.used > 0, count.matchMinutes == expectedMinutes else {
            return false
        }
        guard let ratioReset = ratio.resetsAt, let countReset = count.resetsAt else { return false }
        return abs(countReset.timeIntervalSince(ratioReset)) <= 2
    }

    private static func kimiResetDate(_ object: [String: Any]) -> Date? {
        resetDate(firstPresent(object, keys: ["resetTime", "resetAt", "reset_time", "reset_at"]))
    }

    private static func firstPresent(_ object: [String: Any], keys: [String]) -> Any? {
        for key in keys {
            if let value = object[key], !(value is NSNull) {
                return value
            }
        }
        return nil
    }

    private struct KimiCountWindow {
        enum Role { case session, weekly, other }
        var role: Role
        var name: String
        var matchMinutes: Int?
        var utilization: Double
        var resetsAt: Date?
        var used: Int
        var reliable: Bool

        var window: ParsedQuotaWindow {
            ParsedQuotaWindow(name: name, utilization: utilization, resetsAt: resetsAt)
        }
    }

    private struct KimiRatioSet {
        var session: ParsedQuotaWindow?
        var weekly: ParsedQuotaWindow?
        var monthly: ParsedQuotaWindow?

        var isEmpty: Bool { session == nil && weekly == nil && monthly == nil }
    }

    public static func parseZhipu(_ data: Data) -> ProviderQuotaParseResult {
        guard let body = jsonObject(data) else { return .rejected }
        if (body["success"] as? Bool) == false {
            return .rejected
        }
        guard let payload = body["data"] as? [String: Any] else { return .rejected }
        return .windows(zhipuWindows(payload))
    }

    /// Coding-plan period boundary from `subscription/list`. The overview page shows
    /// 「有效期至」 from the first current plan's `nextRenewTime`
    /// (`yyyy-MM-dd` or `yyyy-MM-dd HH:mm:ss`, Asia/Shanghai). `valid`'s end
    /// is only the fallback when that field is missing; it is the next
    /// period, not the date on the page. Nil when there is no current valid
    /// period, so callers keep the quota windows instead of failing the card.
    public static func parseZhipuSubscription(_ data: Data) -> ParsedQuotaWindow? {
        guard let body = jsonObject(data),
              (body["success"] as? Bool) != false,
              let items = body["data"] as? [Any] else {
            return nil
        }
        for item in items {
            guard let object = item as? [String: Any],
                  (object["status"] as? String)?.uppercased() == "VALID",
                  (object["inCurrentPeriod"] as? Bool) == true,
                  let end = zhipuPlanEnd(object) else {
                continue
            }
            return ParsedQuotaWindow(
                name: ParsedQuotaWindow.planExpiryName,
                utilization: 0,
                resetsAt: end,
                isAutoRenewing: zhipuAutoRenewing(object)
            )
        }
        return nil
    }

    /// The subscription API reports this as boolean-like data, with `1` meaning
    /// enabled. Unknown or absent values must not be inferred from the date.
    private static func zhipuAutoRenewing(_ object: [String: Any]) -> Bool {
        let value = object["autoRenew"]
        guard let value else { return false }
        if CCSwitchJSON.isBoolean(value) {
            return (value as? Bool) ?? false
        }
        return jsonInt(value) == 1
    }

    public static func parseDeepSeek(_ data: Data) -> ProviderQuotaParseResult {
        guard let body = jsonObject(data) else { return .rejected }
        var balances: [ParsedBalance] = []
        if let infos = body["balance_infos"] as? [Any] {
            for item in infos {
                guard let info = item as? [String: Any] else { continue }
                guard let amount = jsonDouble(info["total_balance"]) else { continue }
                let currency = (info["currency"] as? String).flatMap { value in
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? nil : trimmed
                } ?? "CNY"
                balances.append(ParsedBalance(currency: currency, amount: amount))
            }
        }
        return .balances(balances)
    }

    private static func utilization(limit: Any?, remaining: Any?) -> Double {
        let limitValue = jsonDouble(limit) ?? 1
        let remainingValue = jsonDouble(remaining) ?? 0
        let used = max(limitValue - remainingValue, 0)
        guard limitValue > 0 else { return 0 }
        return (used / limitValue) * 100
    }

    /// ISO 8601 string, or seconds/milliseconds. Numeric strings use the same
    /// second/millisecond split as JSON numbers. `<= 0` means no reset.
    private static func resetDate(_ value: Any?) -> Date? {
        if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let date = isoDate(trimmed) { return date }
            if let number = Int64(trimmed) { return timestampDate(number) }
            return nil
        }
        guard let number = jsonInt(value) else { return nil }
        return timestampDate(number)
    }

    private static func timestampDate(_ number: Int64) -> Date? {
        guard number > 0 else { return nil }
        let milliseconds = number < 1_000_000_000_000 ? number * 1000 : number
        return Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000)
    }

    private static func windowName(seconds: Int64, fallback: String) -> String {
        switch seconds {
        case 18_000: return "five_hour"
        case 604_800: return "weekly_limit"
        case 2_592_000: return "monthly"
        default:
            guard seconds > 0 else { return fallback }
            let hours = seconds / 3_600
            return hours >= 24 ? "\(hours / 24)_day" : "\(hours)_hour"
        }
    }

    private static func zhipuWindows(_ data: [String: Any]) -> [ParsedQuotaWindow] {
        guard let limits = data["limits"] as? [Any] else { return [] }
        var fiveHour: ZhipuEntry?
        var weekly: ZhipuEntry?
        var unclassified: [ZhipuEntry] = []

        for item in limits {
            guard let object = item as? [String: Any] else { continue }
            let type = (object["type"] as? String)?.lowercased() ?? ""
            guard type == "tokens_limit" || type == "credit_limit" else { continue }
            let entry = ZhipuEntry(
                resetMilliseconds: jsonInt(object["nextResetTime"]),
                percentage: jsonDouble(object["percentage"]) ?? 0
            )
            switch zhipuWindow(object) {
            case .fiveHour where fiveHour == nil:
                fiveHour = entry
            case .weekly where weekly == nil:
                weekly = entry
            default:
                unclassified.append(entry)
            }
        }

        // Missing or unknown period metadata stays unclassified; reset order
        // cannot establish whether this is an hourly, weekly or monthly pool.
        var windows: [ParsedQuotaWindow] = []
        if let fiveHour {
            windows.append(fiveHour.window(named: "five_hour"))
        }
        if let weekly {
            windows.append(weekly.window(named: "weekly_limit"))
        }
        windows.append(contentsOf: unclassified.map { $0.window(named: "credits") })
        return windows
    }

    private enum ZhipuWindow {
        case fiveHour
        case weekly
    }

    private struct ZhipuEntry {
        var resetMilliseconds: Int64?
        var percentage: Double

        func window(named name: String) -> ParsedQuotaWindow {
            ParsedQuotaWindow(
                name: name,
                utilization: percentage,
                resetsAt: resetMilliseconds.map {
                    Date(timeIntervalSince1970: TimeInterval($0) / 1000)
                }
            )
        }
    }

    /// Page `getNextRenewTime`: `nextRenewTime`, else the end of `valid`.
    /// A date-only renew time keeps that calendar day and must not borrow a
    /// clock from `valid`, which is not the day-granular date shown on the page.
    private static func zhipuPlanEnd(_ object: [String: Any]) -> Date? {
        if let renew = object["nextRenewTime"] as? String {
            let trimmed = renew.trimmingCharacters(in: .whitespacesAndNewlines)
            if let date = zhipuRenewTime(trimmed) {
                return date
            }
        }
        return (object["valid"] as? String).flatMap(zhipuValidRange)?.end
    }

    /// Date-only values are midnight in Shanghai, the calendar day the page
    /// prints as `MM月DD日`.
    private static func zhipuRenewTime(_ value: String) -> Date? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count == 19, let date = shanghaiTimestamp(text) {
            return date
        }
        if text.count == 10, let date = shanghaiDay(text) {
            return date
        }
        return isoDate(text)
    }

    /// `2026-10-03 10:00:00-2026-11-03 10:00:00` → start and end.
    private static func zhipuValidRange(_ value: String) -> (start: Date, end: Date)? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count == 39 else { return nil }
        let middle = text.index(text.startIndex, offsetBy: 19)
        guard text[middle] == "-" else { return nil }
        let startText = String(text[..<middle])
        let endText = String(text[text.index(after: middle)...])
        guard let start = shanghaiTimestamp(startText),
              let end = shanghaiTimestamp(endText) else {
            return nil
        }
        return (start, end)
    }

    private static func shanghaiTimestamp(_ text: String) -> Date? {
        shanghaiDate(text, format: "yyyy-MM-dd HH:mm:ss")
    }

    private static func shanghaiDay(_ text: String) -> Date? {
        shanghaiDate(text, format: "yyyy-MM-dd")
    }

    private static func shanghaiDate(_ text: String, format: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
            ?? TimeZone(secondsFromGMT: 8 * 3_600)
        formatter.dateFormat = format
        return formatter.date(from: text)
    }

    /// Explicit known period metadata only. Unknown units are never inferred
    /// from reset dates, nor assigned to an hourly/weekly slot.
    private static func zhipuWindow(_ item: [String: Any]) -> ZhipuWindow? {
        guard let unit = jsonInt(item["unit"]) else { return nil }
        switch unit {
        case 3 where item["number"] == nil || jsonInt(item["number"]) == 5: return .fiveHour
        case 6 where item["number"] == nil || jsonInt(item["number"]) == 1: return .weekly
        default: return nil
        }
    }
}

public enum GrokBillingParser {
    public struct Snapshot: Equatable, Sendable {
        public let usedPercent: Double
        public let resetsAt: Date?
        public let windowName: String

        public init(usedPercent: Double, resetsAt: Date?, windowName: String = "credits") {
            self.usedPercent = usedPercent
            self.resetsAt = resetsAt
            self.windowName = windowName
        }
    }

    public static func parse(_ data: Data, now: Date) -> Snapshot? {
        let bytes = [UInt8](data)
        var payloads = grpcWebDataFrames(bytes)
        if payloads.isEmpty, looksLikeProtobuf(bytes) {
            payloads = [bytes]
        }
        guard !payloads.isEmpty else { return nil }

        var scan = ProtobufScan()
        for payload in payloads {
            scanProtobuf(payload, depth: 0, path: [], order: 0, scan: &scan)
        }

        // GrokCreditsConfig.credit_usage_percent is field 1. Product usage
        // and history percentages belong to different pools.
        let parsedPercent = scan.fixed32.first { $0.path == [1, 1] }?.value
        guard parsedPercent.map({ $0.isFinite && (0...100).contains($0) }) ?? true else { return nil }
        let periodType = scan.varints.first { $0.path == [1, 8, 1] }?.value
        let name: String
        switch periodType {
        case 1: name = "monthly"
        case 2: name = "weekly_limit"
        default: name = "credits"
        }
        // current_period.end is authoritative for usage; the legacy billing
        // end can also be weekly. Neither is the subscription's expiry.
        func timestamp(at path: [UInt64]) -> Date? {
            guard let seconds = scan.varints.first(where: { $0.path == path })?.value,
                  seconds > 0, seconds <= 253_402_300_799 else { return nil }
            return Date(timeIntervalSince1970: TimeInterval(seconds))
        }
        let reset = timestamp(at: [1, 8, 3, 1]) ?? timestamp(at: [1, 5, 1])
        // Proto3 omits a zero percentage. A typed current period establishes
        // a valid zero-usage config, without borrowing history or product usage.
        guard parsedPercent != nil || (reset != nil && (periodType == 1 || periodType == 2)) else { return nil }
        return Snapshot(usedPercent: Double(parsedPercent ?? 0), resetsAt: reset, windowName: name)
    }

    /// `GET https://grok.com/rest/subscriptions`: billingPeriodEnd on an
    /// active Grok subscription is its monthly/annual billing-period boundary.
    /// Active status does not establish whether the next period will renew.
    /// Inactive history and usage reset timestamps must not supply this date.
    public static func parseSubscriptionExpiry(_ data: Data, accountID: String? = nil) -> ParsedQuotaWindow? {
        guard let body = CCSwitchJSON.object(data),
              let subscriptions = body["subscriptions"] as? [[String: Any]] else { return nil }
        let ends = subscriptions.compactMap { subscription -> Date? in
            // The identity endpoint establishes that the whole website response
            // belongs to the current login. Some records omit the redundant user
            // ID; an explicit mismatch is still fatal.
            if let accountID, let recordAccountID = subscription["xaiUserId"] as? String,
               recordAccountID != accountID { return nil }
            guard subscription["status"] as? String == "SUBSCRIPTION_STATUS_ACTIVE",
                  let tier = subscription["tier"] as? String,
                  tier.hasPrefix("SUBSCRIPTION_TIER_GROK_") || tier.hasPrefix("SUBSCRIPTION_TIER_SUPER_GROK_"),
                  let end = subscription["billingPeriodEnd"] as? String else { return nil }
            return CCSwitchJSON.isoDate(end)
        }
        guard let end = ends.max() else { return nil }
        return ParsedQuotaWindow(name: ParsedQuotaWindow.planExpiryName, utilization: 0, resetsAt: end)
    }

    /// Classifies an HTTP status and optional grpc-status before the body is trusted.
    public static func classify(
        httpStatus: Int,
        grpcStatus: Int?,
        grpcMessage: String = ""
    ) -> GrokRPCOutcome {
        if httpStatus == 401 || httpStatus == 403 {
            return .reauth
        }
        if httpStatus == 408 || httpStatus == 429 || (500...599).contains(httpStatus) {
            return .transient
        }
        if let grpcStatus, grpcStatus != 0 {
            return classifyGRPC(status: grpcStatus, message: grpcMessage)
        }
        if !(200...299).contains(httpStatus) {
            return .failed
        }
        return .ok
    }

    public static func trailerFields(_ data: Data) -> [String: String] {
        var fields: [String: String] = [:]
        let bytes = [UInt8](data)
        var index = 0
        while index + 5 <= bytes.count {
            let flags = bytes[index]
            let length = Int(UInt32(bytes[index + 1]) << 24
                | UInt32(bytes[index + 2]) << 16
                | UInt32(bytes[index + 3]) << 8
                | UInt32(bytes[index + 4]))
            let start = index + 5
            let end = start + length
            guard end <= bytes.count else { break }
            if flags & 0x80 != 0 {
                let text = String(decoding: bytes[start..<end], as: UTF8.self)
                for line in text.split(whereSeparator: \.isNewline) where !line.isEmpty {
                    guard let separator = line.firstIndex(of: ":") else { continue }
                    let key = line[..<separator].trimmingCharacters(in: .whitespaces).lowercased()
                    let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
                    fields[key] = percentDecode(String(value))
                }
            }
            index = end
        }
        return fields
    }

    public static func percentDecode(_ input: String) -> String {
        var output: [UInt8] = []
        let bytes = Array(input.utf8)
        var index = 0
        while index < bytes.count {
            if bytes[index] == UInt8(ascii: "%"), index + 2 < bytes.count,
               let decoded = UInt8(String(decoding: bytes[(index + 1)...(index + 2)], as: UTF8.self), radix: 16) {
                output.append(decoded)
                index += 3
                continue
            }
            output.append(bytes[index])
            index += 1
        }
        return String(decoding: output, as: UTF8.self)
    }

    private static func classifyGRPC(status: Int, message: String) -> GrokRPCOutcome {
        let decoded = percentDecode(message)
        if isAuthFailure(status: status, message: decoded) {
            return .reauth
        }
        if isTransient(status: status, message: decoded) {
            return .transient
        }
        return .failed
    }

    private static func isAuthFailure(status: Int, message: String) -> Bool {
        if status == 16 { return true }
        guard status == 7 else { return false }
        let lower = message.lowercased()
        if lower.contains("bad-credentials") || lower.contains("unauthenticated") {
            return true
        }
        if lower.contains("oauth2"), lower.contains("could not be validated") {
            return true
        }
        if lower.contains("access token"),
           lower.contains("invalid") || lower.contains("expired") || lower.contains("could not be validated") {
            return true
        }
        return false
    }

    private static func isTransient(status: Int, message: String) -> Bool {
        switch status {
        case 4, 14:
            return true
        case 1:
            let lower = message.lowercased()
            return lower.contains("timeout") || lower.contains("deadline") || lower.contains("expired")
        default:
            return false
        }
    }

    private struct Fixed32Field {
        var path: [UInt64]
        var value: Float
        var order: Int
    }

    private struct VarintField {
        var path: [UInt64]
        var value: UInt64
    }

    private struct ProtobufScan {
        var fixed32: [Fixed32Field] = []
        var varints: [VarintField] = []
    }

    private static func readVarint(_ bytes: [UInt8], index: inout Int) -> UInt64? {
        var value: UInt64 = 0
        var shift: UInt32 = 0
        while index < bytes.count, shift < 64 {
            let byte = bytes[index]
            index += 1
            value |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 {
                return value
            }
            shift += 7
        }
        return nil
    }

    @discardableResult
    private static func scanProtobuf(
        _ bytes: [UInt8],
        depth: Int,
        path: [UInt64],
        order: Int,
        scan: inout ProtobufScan
    ) -> Int {
        var index = 0
        var nextOrder = order
        while index < bytes.count {
            let fieldStart = index
            guard let key = readVarint(bytes, index: &index), key != 0 else {
                index = fieldStart + 1
                continue
            }
            let fieldNumber = key >> 3
            let wireType = key & 0x07
            var fieldPath = path
            fieldPath.append(fieldNumber)
            switch wireType {
            case 0:
                if let value = readVarint(bytes, index: &index) {
                    scan.varints.append(VarintField(path: fieldPath, value: value))
                } else {
                    index = fieldStart + 1
                }
            case 1:
                guard index + 8 <= bytes.count else { return nextOrder }
                index += 8
            case 2:
                guard let length = readVarint(bytes, index: &index),
                      length <= UInt64(bytes.count - index) else {
                    index = fieldStart + 1
                    continue
                }
                let end = index + Int(length)
                if depth < 4 {
                    nextOrder = scanProtobuf(
                        Array(bytes[index..<end]),
                        depth: depth + 1,
                        path: fieldPath,
                        order: nextOrder,
                        scan: &scan
                    )
                }
                index = end
            case 5:
                guard index + 4 <= bytes.count else { return nextOrder }
                let bits = UInt32(bytes[index])
                    | UInt32(bytes[index + 1]) << 8
                    | UInt32(bytes[index + 2]) << 16
                    | UInt32(bytes[index + 3]) << 24
                scan.fixed32.append(
                    Fixed32Field(path: fieldPath, value: Float(bitPattern: bits), order: nextOrder)
                )
                nextOrder += 1
                index += 4
            default:
                index = fieldStart + 1
            }
        }
        return nextOrder
    }

    private static func grpcWebDataFrames(_ data: [UInt8]) -> [[UInt8]] {
        var frames: [[UInt8]] = []
        var index = 0
        while index < data.count {
            guard index + 5 <= data.count else { return [] }
            let flags = data[index]
            let length = Int(UInt32(data[index + 1]) << 24
                | UInt32(data[index + 2]) << 16
                | UInt32(data[index + 3]) << 8
                | UInt32(data[index + 4]))
            let start = index + 5
            let end = start + length
            guard end <= data.count else { return [] }
            if flags & 0x80 == 0 {
                frames.append(Array(data[start..<end]))
            }
            index = end
        }
        return frames
    }

    private static func looksLikeProtobuf(_ data: [UInt8]) -> Bool {
        guard let first = data.first else { return false }
        let fieldNumber = first >> 3
        let wireType = first & 0x07
        return fieldNumber > 0 && (wireType == 0 || wireType == 1 || wireType == 2 || wireType == 5)
    }
}

enum CCSwitchJSON {
    static func object(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// JSON `true`/`false` are CFBooleans. Integer 0 and 1 are also `is Bool`
    /// through NSNumber bridging, so that check drops real zeros and ones.
    static func isBoolean(_ value: Any) -> Bool {
        guard let number = value as? NSNumber else { return false }
        #if canImport(CoreFoundation)
        return CFGetTypeID(number) == CFBooleanGetTypeID()
        #else
        // Windows Foundation does not export CoreFoundation. JSON numbers use
        // integer/floating encodings; JSON booleans use the boolean encoding.
        let encoding = String(cString: number.objCType)
        return encoding == "c" || encoding == "B"
        #endif
    }

    static func double(_ value: Any?) -> Double? {
        guard let value, !isBoolean(value) else { return nil }
        if let number = value as? NSNumber {
            let parsed = number.doubleValue
            return parsed.isFinite ? parsed : nil
        }
        if let text = value as? String {
            return Double(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    static func int(_ value: Any?) -> Int64? {
        guard let value, !isBoolean(value) else { return nil }
        if let number = value as? NSNumber {
            return number.int64Value
        }
        return nil
    }

    /// Internet datetime. More than 3 fractional digits are cut to milliseconds
    /// before parsing. Apple can accept a very long fraction as the wrong
    /// second; truncation does not round. Ordinary ISO dates are unchanged.
    static func isoDate(_ text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let truncated = millisecondsISO(trimmed), let date = internetDate(from: truncated) {
            return date
        }
        return internetDate(from: trimmed)
    }

    private static func internetDate(from text: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: text) { return date }
        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        return basic.date(from: text)
    }

    /// `2026-01-09T15:23:13.716839300Z` → `2026-01-09T15:23:13.716Z`.
    private static func millisecondsISO(_ text: String) -> String? {
        guard let t = text.firstIndex(of: "T") else { return nil }
        let time = text.index(after: t)
        guard time < text.endIndex, let dot = text[time...].firstIndex(of: ".") else { return nil }
        var index = text.index(after: dot)
        let fractionStart = index
        while index < text.endIndex, text[index].isNumber {
            index = text.index(after: index)
        }
        guard text.distance(from: fractionStart, to: index) > 3 else { return nil }
        if index < text.endIndex {
            let marker = text[index]
            guard marker == "Z" || marker == "z" || marker == "+" || marker == "-" else { return nil }
        }
        let end = text.index(fractionStart, offsetBy: 3)
        return String(text[..<end] + text[index...])
    }
}

private func jsonObject(_ data: Data) -> [String: Any]? {
    CCSwitchJSON.object(data)
}

private func jsonDouble(_ value: Any?) -> Double? {
    CCSwitchJSON.double(value)
}

private func jsonInt(_ value: Any?) -> Int64? {
    CCSwitchJSON.int(value)
}

private func isoDate(_ text: String) -> Date? {
    CCSwitchJSON.isoDate(text)
}
