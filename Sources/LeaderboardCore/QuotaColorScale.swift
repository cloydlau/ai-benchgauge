import LeaderboardKit
import Foundation

public struct QuotaRGB: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

/// A continuous scale with darker light-mode colors for readable small text.
public enum QuotaColorScale {
    public struct BalanceReference: Equatable, Sendable {
        public let orange: Double
        public let yellow: Double
        public let green: Double
    }

    /// Fixed UI references in the reported currency, not exchange rates or
    /// a prediction of how long the balance will last.
    public static func balanceReference(currency: String) -> BalanceReference? {
        switch currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "CNY", "RMB", "HKD":
            return BalanceReference(orange: 10, yellow: 30, green: 100)
        case "USD", "EUR", "GBP", "CHF", "CAD", "AUD", "SGD":
            return BalanceReference(orange: 2, yellow: 5, green: 20)
        case "TWD":
            return BalanceReference(orange: 50, yellow: 150, green: 500)
        case "JPY":
            return BalanceReference(orange: 200, yellow: 600, green: 2_000)
        case "KRW":
            return BalanceReference(orange: 2_000, yellow: 6_000, green: 20_000)
        case "INR":
            return BalanceReference(orange: 100, yellow: 300, green: 1_000)
        default:
            return nil
        }
    }

    /// Maps money to the shared 0…100 color scale. It is a color level, not
    /// a quota percentage: monetary balances do not report a total allowance.
    public static func balanceLevel(amount: Double, currency: String) -> Double? {
        guard amount.isFinite, let reference = balanceReference(currency: currency) else { return nil }
        let amount = max(0, amount)
        let stops = [(0.0, 0.0), (reference.orange, 25.0), (reference.yellow, 50.0), (reference.green, 100.0)]
        for (lower, upper) in zip(stops, stops.dropFirst()) where amount <= upper.0 {
            return lower.1 + (upper.1 - lower.1) * (amount - lower.0) / (upper.0 - lower.0)
        }
        return 100
    }

    /// Maps time remaining to the same color levels as quotas, without
    /// implying that a passed period boundary means access has expired.
    public static func deadlineLevel(until end: Date, now: Date) -> Double? {
        let days = end.timeIntervalSince(now) / 86_400
        guard days.isFinite else { return nil }
        let remaining = max(0, days)
        let stops = [(0.0, 0.0), (2.0, 25.0), (7.0, 50.0), (14.0, 100.0)]
        for (lower, upper) in zip(stops, stops.dropFirst()) where remaining <= upper.0 {
            return lower.1 + (upper.1 - lower.1) * (remaining - lower.0) / (upper.0 - lower.0)
        }
        return 100
    }

    public static func color(remainingPercent: Double, dark: Bool) -> QuotaRGB {
        let percent = remainingPercent.isFinite ? min(100, max(0, remainingPercent)) : 0
        let stops: [(Double, QuotaRGB)] = dark ? [
            (0, QuotaRGB(red: 1.00, green: 0.45, blue: 0.42)),
            (25, QuotaRGB(red: 1.00, green: 0.60, blue: 0.30)),
            (50, QuotaRGB(red: 0.97, green: 0.79, blue: 0.28)),
            (100, QuotaRGB(red: 0.49, green: 0.84, blue: 0.55)),
        ] : [
            (0, QuotaRGB(red: 0.86, green: 0.16, blue: 0.16)),
            (25, QuotaRGB(red: 0.86, green: 0.36, blue: 0.10)),
            (50, QuotaRGB(red: 0.68, green: 0.51, blue: 0.08)),
            (100, QuotaRGB(red: 0.10, green: 0.52, blue: 0.26)),
        ]
        for (lower, upper) in zip(stops, stops.dropFirst()) where percent <= upper.0 {
            let fraction = (percent - lower.0) / (upper.0 - lower.0)
            return QuotaRGB(
                red: lower.1.red + (upper.1.red - lower.1.red) * fraction,
                green: lower.1.green + (upper.1.green - lower.1.green) * fraction,
                blue: lower.1.blue + (upper.1.blue - lower.1.blue) * fraction
            )
        }
        return stops.last!.1
    }
}
