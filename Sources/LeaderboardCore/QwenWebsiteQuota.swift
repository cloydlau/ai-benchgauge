import LeaderboardKit
import Foundation

public struct QwenWebsiteQuota: Equatable, Sendable {
    public let periodLabel: String
    public let remainingPercent: Double
    /// Reset of the selected usage pool, never a subscription deadline.
    public let resetsAt: Date?
    public let expiresAt: Date?
    public let isCached: Bool
    public let capturedAt: Date?

    public init(
        periodLabel: String,
        remainingPercent: Double,
        resetsAt: Date?,
        expiresAt: Date? = nil,
        isCached: Bool = false,
        capturedAt: Date? = nil
    ) {
        self.periodLabel = periodLabel
        self.remainingPercent = remainingPercent
        self.resetsAt = resetsAt
        self.expiresAt = expiresAt
        self.isCached = isCached
        self.capturedAt = capturedAt
    }
}

/// Reads each usage pool together with its own percentage and reset time.
/// When the page reports both periods, the card prefers the monthly pool.
public enum QwenWebsiteQuotaParser {
    public static func parse(_ data: Data) -> QwenWebsiteQuota? {
        if let stored = try? JSONDecoder().decode(StoredQuota.self, from: data),
           [1, 2].contains(stored.version),
           stored.remainingPercent.isFinite,
           (0...100).contains(stored.remainingPercent),
           ["7d", "1mo"].contains(currentPeriodLabel(stored.periodLabel)) {
            return QwenWebsiteQuota(
                periodLabel: currentPeriodLabel(stored.periodLabel),
                remainingPercent: stored.remainingPercent,
                // Version 1 took the first reset anywhere on the page, so its
                // date cannot safely be associated with the saved percentage.
                resetsAt: stored.version == 2 ? stored.resetsAt : nil,
                expiresAt: stored.version == 2 ? stored.expiresAt : nil,
                isCached: true,
                capturedAt: stored.capturedAt
            )
        }
        guard let text = String(data: data, encoding: .utf8),
              let headers = try? NSRegularExpression(pattern: #"7\s*天限[额額]|月[额額]度|7 Days Usage Limit|Monthly Quota"#) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        let matches = headers.matches(in: text, range: range)
        var pools: [QwenWebsiteQuota] = []
        for (index, header) in matches.enumerated() {
            let end = index + 1 < matches.count ? matches[index + 1].range.location : range.length
            let sectionRange = NSRange(location: header.range.location, length: end - header.range.location)
            guard let swiftRange = Range(sectionRange, in: text),
                  let labelRange = Range(header.range, in: text) else { continue }
            let section = String(text[swiftRange]).components(separatedBy: "加油包")[0]
                .components(separatedBy: "Credit Pack")[0]
            guard let percentText = capture(#"(?:剩[余餘]量|Remaining)\s*([0-9]+(?:\.[0-9]+)?)\s*%"#, in: String(section.prefix(240))),
                  let percent = Double(percentText), percent.isFinite, (0...100).contains(percent) else { continue }
            let reset = capture(#"(?:重置[时時][间間]|Reset time)\s*([0-9]{4}-[0-9]{2}-[0-9]{2}\s+[0-9]{2}:[0-9]{2}:[0-9]{2})"#, in: section).flatMap(shanghaiDate)
            pools.append(QwenWebsiteQuota(
                periodLabel: text[labelRange].contains("月") || text[labelRange] == "Monthly Quota" ? "1mo" : "7d",
                remainingPercent: percent,
                resetsAt: reset
            ))
        }
        guard let selected = pools.first(where: { $0.periodLabel == "1mo" }) ?? pools.first else { return nil }
        let expiry = capture(#"(?:套餐到期时间|套餐有效期至|有效期至|到期日期)\s*([0-9]{4}-[0-9]{2}-[0-9]{2}(?:\s+[0-9]{2}:[0-9]{2}:[0-9]{2})?)"#, in: text).flatMap(shanghaiDate)
        return QwenWebsiteQuota(periodLabel: selected.periodLabel, remainingPercent: selected.remainingPercent, resetsAt: selected.resetsAt, expiresAt: expiry)
    }

    /// Only fixed, rendered site messages determine failures. Missing quota
    /// text alone is never evidence that the account is signed out.
    public static func failureStatus(in data: Data) -> AccountQuotaChip.Status? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let lines = Set(text.components(separatedBy: .newlines).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        })
        if !lines.isDisjoint(with: ["您当前还未登录，登录后可使用完整服务",
                                   "You are currently not logged in. Log in to access all services."]) {
            return .message(AccountQuotaMessage.reauthRequired)
        }
        if !lines.isDisjoint(with: ["暂无个人版套餐", "套餐已失效", "No Individual Plan", "Plan expired"]) {
            return .note(text: AccountQuotaMessage.qwenNoPlan, help: AccountQuotaMessage.qwenNoPlanHelp)
        }
        if !lines.isDisjoint(with: ["用量加载失败，请稍后重试", "Failed to load usage. Please try again later."]) {
            return .message(AccountQuotaMessage.queryFailed)
        }
        return nil
    }

    /// Stores parsed fields only; authenticated page text is never saved.
    public static func persistedData(for quota: QwenWebsiteQuota, capturedAt: Date = Date()) -> Data? {
        try? JSONEncoder().encode(StoredQuota(version: 2, periodLabel: quota.periodLabel,
            remainingPercent: quota.remainingPercent, resetsAt: quota.resetsAt,
            expiresAt: quota.expiresAt, capturedAt: capturedAt))
    }

    private static func capture(_ pattern: String, in text: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    private static func shanghaiDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = text.count == 10 ? "yyyy-MM-dd" : "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: text)
    }

    private static func currentPeriodLabel(_ stored: String) -> String {
        switch stored {
        case "月度", "1个月": "1mo"
        case "7天": "7d"
        default: stored
        }
    }

    private struct StoredQuota: Codable {
        let version: Int
        let periodLabel: String
        let remainingPercent: Double
        let resetsAt: Date?
        let expiresAt: Date?
        let capturedAt: Date
    }
}
