import Foundation

/// Desktop notifications for the provider that is currently in use.
///
/// 余量 is remaining quota, not the utilization percentage some chips draw.
/// A window's remaining percent is `100 - utilization`. Qwen plan remaining
/// comes from credits, and the Qwen website figure is already remaining.
///
/// A window whose whole period is 2 days or less is not 临期. The 5-hour
/// window is always inside that horizon, so treating it as expiring would
/// notify on every cycle.
public struct QuotaAlert: Equatable, Sendable {
    public enum Reason: String, Equatable, Sendable {
        case highRemaining
        case expiring
    }

    public let chipID: String
    public let reason: Reason
    public let title: String
    public let subtitle: String
    public let body: String
    /// One key per qualifying source and reset time. A later refresh sends
    /// again only when one of these keys has not been delivered.
    public let componentKeys: [String]

    public init(
        chipID: String,
        reason: Reason,
        title: String,
        subtitle: String,
        body: String,
        componentKeys: [String]
    ) {
        self.chipID = chipID
        self.reason = reason
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.componentKeys = componentKeys
    }
}

public enum QuotaAlerts {
    public static let highRemainingPercent = 95
    public static let expiringInterval: TimeInterval = 2 * 24 * 60 * 60

    public static func alerts(for chip: AccountQuotaChip, now: Date) -> [QuotaAlert] {
        guard chip.isCurrent, isConclusive(chip.status) else { return [] }
        let subjects = subjects(for: chip.status)
        var alerts: [QuotaAlert] = []
        if let alert = highRemainingAlert(chip: chip, subjects: subjects) {
            alerts.append(alert)
        }
        if let alert = expiringAlert(chip: chip, subjects: subjects, now: now) {
            alerts.append(alert)
        }
        return alerts
    }

    /// Keeps keys for chips that were not conclusively re-read while current.
    /// A failed, cached, or non-current reading must not forget a delivery,
    /// and must not count as the condition clearing.
    public static func retainedKeys(
        _ delivered: Set<String>,
        evaluatedChips: [AccountQuotaChip],
        activeKeys: Set<String>
    ) -> Set<String> {
        let currentIDs = Set(
            evaluatedChips.filter { $0.isCurrent && isConclusive($0.status) }.map(\.id)
        )
        guard !currentIDs.isEmpty else { return delivered }
        return delivered.filter { key in
            guard let chipID = chipID(in: key), currentIDs.contains(chipID) else { return true }
            return activeKeys.contains(key)
        }
    }

    public static func pendingAlerts(
        _ alerts: [QuotaAlert],
        delivered: Set<String>,
        inFlight: Set<String> = []
    ) -> [QuotaAlert] {
        alerts.filter { alert in
            alert.componentKeys.contains { key in
                !delivered.contains(key) && !inFlight.contains(key)
            }
        }
    }

    private struct Subject {
        let sourceID: String
        let label: String
        let remainingPercent: Double?
        let resetsAt: Date?
        let expiryEligible: Bool
    }

    private static func isConclusive(_ status: AccountQuotaChip.Status) -> Bool {
        switch status {
        case .pending, .note, .message:
            return false
        case let .qwenWebsite(quota) where quota.isCached:
            return false
        case .windows, .balances, .qwenPlan, .qwenWebsite:
            return true
        }
    }

    private static func subjects(for status: AccountQuotaChip.Status) -> [Subject] {
        switch status {
        case let .windows(windows):
            return AccountQuotaFormatting.sortedWindows(windows).map { window in
                Subject(
                    sourceID: window.name,
                    label: AccountQuotaFormatting.label(forWindowName: window.name),
                    remainingPercent: remainingPercent(utilization: window.utilization),
                    resetsAt: window.resetsAt,
                    expiryEligible: !isShortWindow(window.name)
                )
            }
        case let .qwenPlan(plan):
            return [
                Subject(
                    sourceID: "plan",
                    label: "7天",
                    remainingPercent: remainingPercent(plan),
                    resetsAt: plan.resetsAt,
                    expiryEligible: true
                ),
            ]
        case let .qwenWebsite(quota):
            return [
                Subject(
                    sourceID: "website",
                    label: quota.periodLabel,
                    remainingPercent: quota.remainingPercent,
                    resetsAt: quota.resetsAt,
                    expiryEligible: true
                ),
            ]
        case .pending, .note, .balances, .message:
            return []
        }
    }

    private static func remainingPercent(utilization: Double) -> Double? {
        guard utilization.isFinite else { return nil }
        let remaining = 100 - utilization
        return remaining.isFinite ? remaining : nil
    }

    private static func remainingPercent(_ plan: QwenPlanQuota) -> Double? {
        if plan.totalCredits > 0, plan.remainingCredits.isFinite, plan.totalCredits.isFinite {
            let remaining = plan.remainingCredits / plan.totalCredits * 100
            if remaining.isFinite { return remaining }
        }
        guard plan.usedPercent.isFinite else { return nil }
        return 100 - plan.usedPercent
    }

    private static func highRemainingAlert(chip: AccountQuotaChip, subjects: [Subject]) -> QuotaAlert? {
        let qualifying = subjects.compactMap { subject -> (Subject, Int)? in
            guard let remaining = subject.remainingPercent, remaining.isFinite else { return nil }
            let rounded = AccountQuotaFormatting.roundedPercent(remaining)
            guard rounded >= highRemainingPercent else { return nil }
            return (subject, rounded)
        }
        guard !qualifying.isEmpty else { return nil }
        return QuotaAlert(
            chipID: chip.id,
            reason: .highRemaining,
            title: chip.shortName,
            subtitle: "余量达到\(highRemainingPercent)%",
            body: qualifying.map { "\($0.0.label)余量 \($0.1)%" }.joined(separator: "；"),
            componentKeys: qualifying.map {
                componentKey(
                    chipID: chip.id,
                    reason: .highRemaining,
                    sourceID: $0.0.sourceID,
                    resetsAt: $0.0.resetsAt
                )
            }
        )
    }

    private static func expiringAlert(
        chip: AccountQuotaChip,
        subjects: [Subject],
        now: Date
    ) -> QuotaAlert? {
        let qualifying = subjects.compactMap { subject -> (Subject, String)? in
            guard subject.expiryEligible, let resetsAt = subject.resetsAt else { return nil }
            let remaining = resetsAt.timeIntervalSince(now)
            guard remaining > 0, remaining <= expiringInterval else { return nil }
            guard let phrase = countdownPhrase(until: resetsAt, now: now) else { return nil }
            return (subject, phrase)
        }
        guard !qualifying.isEmpty else { return nil }
        let body = qualifying.map { subject, phrase in
            guard let resetsAt = subject.resetsAt,
                  let date = AccountQuotaFormatting.resetDateText(resetsAt, now: now) else {
                return "\(subject.label)额度 \(phrase)后重置"
            }
            return "\(subject.label)额度 \(phrase)后重置，\(date)"
        }.joined(separator: "；")
        return QuotaAlert(
            chipID: chip.id,
            reason: .expiring,
            title: chip.shortName,
            subtitle: "2天内重置",
            body: body,
            componentKeys: qualifying.map {
                componentKey(
                    chipID: chip.id,
                    reason: .expiring,
                    sourceID: $0.0.sourceID,
                    resetsAt: $0.0.resetsAt
                )
            }
        )
    }

    private static func countdownPhrase(until resetsAt: Date, now: Date) -> String? {
        guard let phrase = AccountQuotaFormatting.chineseCountdown(until: resetsAt, now: now) else {
            return nil
        }
        return phrase == "0分钟" ? "不到1分钟" : phrase
    }

    /// Named periods of 2 days or less are always inside the expiry horizon.
    private static func isShortWindow(_ name: String) -> Bool {
        if name == "five_hour" { return true }
        if let hours = prefixedInt(name, suffix: "_hour"),
           TimeInterval(hours) * 60 * 60 <= expiringInterval {
            return true
        }
        if let days = prefixedInt(name, suffix: "_day"),
           TimeInterval(days) * 24 * 60 * 60 <= expiringInterval {
            return true
        }
        return false
    }

    private static func prefixedInt(_ name: String, suffix: String) -> Int? {
        guard name.hasSuffix(suffix) else { return nil }
        let prefix = name.dropLast(suffix.count)
        guard !prefix.isEmpty, prefix.allSatisfy(\.isNumber) else { return nil }
        return Int(prefix)
    }

    private static let keySeparator: Character = "\u{1}"

    private static func componentKey(
        chipID: String,
        reason: QuotaAlert.Reason,
        sourceID: String,
        resetsAt: Date?
    ) -> String {
        let reset = resetsAt.map { String(Int($0.timeIntervalSince1970)) } ?? "none"
        return [reason.rawValue, chipID, sourceID, reset].joined(separator: String(keySeparator))
    }

    private static func chipID(in key: String) -> String? {
        let parts = key.split(separator: keySeparator, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 4, !parts[1].isEmpty else { return nil }
        return parts[1]
    }
}
