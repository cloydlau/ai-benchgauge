import Foundation

extension Leaderboard {
    public var contentTimestamp: Date { contentUpdatedAt ?? fetchedAt }

    /// Trust the shared server's durable timestamp. For old servers and direct
    /// acquisition, compare against the local cache without changing fetchedAt.
    public func preservingContentTimestamp(from previous: Leaderboard?) -> Leaderboard {
        guard let previous else { return self }
        guard canReplace(previous) else { return previous }
        guard contentUpdatedAt == nil else { return self }
        let unchanged = !previous.entries.isEmpty && contentRows == previous.contentRows
            && (kind != .vercelUsage || sourceUpdatedAt == previous.sourceUpdatedAt)
            && (kind != .cloudbaseUsage || sourceNote == previous.sourceNote)
        return Leaderboard(kind: kind, title: title, sourceUpdatedAt: sourceUpdatedAt,
            sourceNote: sourceNote, fetchedAt: fetchedAt,
            contentUpdatedAt: unchanged ? previous.contentTimestamp : fetchedAt,
            entries: entries, organizationLogoURLs: organizationLogoURLs,
            modelMetadataSource: modelMetadataSource)
    }

    private struct ContentRow: Equatable {
        let identity: String
        let name: String
        let organization: String?
        let rank: Int
        let score: Double
        let totalTokens: String?
        let voteCount: Int?
    }
    private var contentRows: [ContentRow] {
        entries.sorted { $0.rank < $1.rank }.map {
            let identity = ($0.modelID ?? "\($0.name)\u{0}\($0.organization ?? "")")
                .replacingOccurrences(of: "#arena-rank-\\d+$", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return ContentRow(identity: identity, name: $0.name, organization: $0.organization,
                rank: $0.rank, score: $0.score, totalTokens: $0.totalTokens, voteCount: $0.voteCount)
        }
    }
}
