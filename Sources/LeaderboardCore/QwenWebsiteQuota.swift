import Foundation

public struct QwenWebsiteQuota: Equatable, Sendable {
    public let periodLabel: String
    public let remainingPercent: Double
    public let resetsAt: Date?
    public let isCached: Bool
    public let capturedAt: Date?

    public init(
        periodLabel: String,
        remainingPercent: Double,
        resetsAt: Date?,
        isCached: Bool = false,
        capturedAt: Date? = nil
    ) {
        self.periodLabel = periodLabel
        self.remainingPercent = remainingPercent
        self.resetsAt = resetsAt
        self.isCached = isCached
        self.capturedAt = capturedAt
    }
}

/// Parses the figures rendered by the user's authenticated Token Plan page.
/// The page shows a rounded percentage, so no exact Credits are inferred.
public enum QwenWebsiteQuotaParser {
    public static func parse(_ data: Data) -> QwenWebsiteQuota? {
        if let stored = try? JSONDecoder().decode(StoredQuota.self, from: data),
           stored.version == 1,
           stored.remainingPercent.isFinite,
           (0...100).contains(stored.remainingPercent) {
            return QwenWebsiteQuota(
                periodLabel: stored.periodLabel,
                remainingPercent: stored.remainingPercent,
                resetsAt: stored.resetsAt,
                isCached: true,
                capturedAt: stored.capturedAt
            )
        }
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let pattern = #"(7\s*天限额|月额度)[\s\S]{0,100}?剩余量\s*([0-9]+(?:\.[0-9]+)?)\s*%"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let labelRange = Range(match.range(at: 1), in: text),
              let percentRange = Range(match.range(at: 2), in: text),
              let percent = Double(text[percentRange]),
              percent.isFinite, (0...100).contains(percent) else { return nil }
        let periodLabel = text[labelRange].contains("月") ? "1个月" : "7天"
        let resetPattern = #"重置时间\s*([0-9]{4}-[0-9]{2}-[0-9]{2}\s+[0-9]{2}:[0-9]{2}:[0-9]{2})"#
        var resetsAt: Date?
        if let resetExpression = try? NSRegularExpression(pattern: resetPattern),
           let resetMatch = resetExpression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let resetRange = Range(resetMatch.range(at: 1), in: text) {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            resetsAt = formatter.date(from: String(text[resetRange]))
        }
        return QwenWebsiteQuota(
            periodLabel: periodLabel,
            remainingPercent: percent,
            resetsAt: resetsAt
        )
    }

    /// Stores only the parsed quota fields, never the authenticated page text
    /// that could contain account details.
    public static func persistedData(
        for quota: QwenWebsiteQuota,
        capturedAt: Date = Date()
    ) -> Data? {
        try? JSONEncoder().encode(
            StoredQuota(
                version: 1,
                periodLabel: quota.periodLabel,
                remainingPercent: quota.remainingPercent,
                resetsAt: quota.resetsAt,
                capturedAt: capturedAt
            )
        )
    }

    private struct StoredQuota: Codable {
        let version: Int
        let periodLabel: String
        let remainingPercent: Double
        let resetsAt: Date?
        let capturedAt: Date
    }
}
