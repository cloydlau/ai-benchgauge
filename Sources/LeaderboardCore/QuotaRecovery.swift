import Foundation

/// Tracks actual exhaustion, including inactive providers. A reset deadline is
/// a reason to recheck, not evidence that quota has already recovered.
public struct QuotaRecoveryTracker: Codable, Equatable, Sendable {
    private struct Window: Codable, Equatable, Sendable {
        var sourceID: String
        var resetsAt: Date?
    }

    private var exhausted: [String: [Window]] = [:]
    private var pending: [String: QuotaAlert] = [:]

    public init() {}

    public mutating func consider(chips: [AccountQuotaChip]) -> [QuotaAlert] {
        for chip in chips {
            guard !chip.isStale, QuotaAlerts.isConclusive(chip.status) else { continue }
            let subjects = QuotaAlerts.subjects(for: chip).filter { !$0.expiresRatherThanResets }
            let depleted = subjects.filter { $0.remainingPercent.map { $0.isFinite && $0 <= 0 } ?? false }
            if !depleted.isEmpty {
                // Retain missing windows until they are explicitly read again.
                let missing = (exhausted[chip.id] ?? []).filter { old in
                    !subjects.contains { $0.sourceID == old.sourceID }
                }
                exhausted[chip.id] = missing + depleted.map { Window(sourceID: $0.sourceID, resetsAt: $0.resetsAt) }
                pending[chip.id] = nil
                continue
            }
            guard let previous = exhausted[chip.id], !subjects.isEmpty,
                  subjects.allSatisfy({ $0.remainingPercent.map { $0.isFinite && $0 > 0 } ?? false }),
                  previous.allSatisfy({ old in subjects.contains { $0.sourceID == old.sourceID } }) else { continue }
            let recovered = subjects.filter { subject in previous.contains { $0.sourceID == subject.sourceID } }
            pending[chip.id] = QuotaAlert(
                chipID: chip.id, reason: .recovered, title: chip.shortName,
                subtitle: "额度已恢复",
                body: recovered.map {
                    "\($0.label) \(AccountQuotaFormatting.roundedPercent($0.remainingPercent!))%"
                }.joined(separator: "；"),
                componentKeys: ["recovered\u{1}\(chip.id)\u{1}quota\u{1}\(UUID().uuidString)"]
            )
            exhausted[chip.id] = nil
        }
        // A pending delivery also needs a fresh usable reading. Failed queries
        // keep it for retry without posting a potentially obsolete banner.
        return chips.compactMap { chip in
            guard !chip.isStale, QuotaAlerts.isConclusive(chip.status),
                  let alert = pending[chip.id] else { return nil }
            let subjects = QuotaAlerts.subjects(for: chip).filter { !$0.expiresRatherThanResets }
            guard !subjects.isEmpty,
                  subjects.allSatisfy({ $0.remainingPercent.map { $0.isFinite && $0 > 0 } ?? false }) else { return nil }
            return alert
        }
    }

    public mutating func acknowledge(_ keys: Set<String>) {
        pending = pending.filter { !Set($0.value.componentKeys).isSubset(of: keys) }
    }

    /// Recheck at the reported reset, even while idle or switched to another
    /// provider. Missing reset dates and unsuccessful resets retry every 5 min.
    public func refreshDueChipIDs(now: Date, lastAttempts: [String: Date]) -> Set<String> {
        Set(exhausted.compactMap { id, windows in
            guard windows.contains(where: { ($0.resetsAt ?? .distantPast) <= now }),
                  lastAttempts[id].map({ now.timeIntervalSince($0) >= QuotaAutoRefreshPolicy.activeInterval }) ?? true else { return nil }
            return id
        })
    }
}

/// Stores only provider IDs, reset dates and notification copy; no credentials.
public struct QuotaRecoveryStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL = PlatformPaths.applicationSupport.appending(path: "quota-recovery.json")) {
        self.fileURL = fileURL
    }

    public func load() -> QuotaRecoveryTracker {
        guard let data = try? Data(contentsOf: fileURL),
              let tracker = try? JSONDecoder().decode(QuotaRecoveryTracker.self, from: data) else {
            return QuotaRecoveryTracker()
        }
        return tracker
    }

    public func save(_ tracker: QuotaRecoveryTracker) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(tracker).write(to: fileURL, options: .atomic)
        try PlatformPaths.restrictFile(fileURL, permissions: 0o600)
    }
}
