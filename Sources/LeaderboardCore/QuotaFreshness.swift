import Foundation

public enum QuotaFreshness {
    /// Reading state or retaining a failed response's cached value does not
    /// create a new data timestamp. Website values keep their capture time.
    public static func updatedAt(afterRefreshing chips: [AccountQuotaChip], previous: Date?, now: Date) -> Date? {
        let dates = chips.compactMap { chip -> Date? in
            guard !chip.isStale else { return nil }
            switch chip.status {
            case .windows(let values): return values.isEmpty ? nil : now
            case .balances(let values): return values.isEmpty ? nil : now
            case .qwenPlan: return now
            case .qwenWebsite(let quota): return quota.capturedAt ?? (quota.isCached ? nil : now)
            case .pending, .note, .message: return nil
            }
        }
        return (dates + (previous.map { [$0] } ?? [])).max()
    }
}
