import Foundation

public enum LeaderboardFailure: Equatable, Sendable {
    case offline, sourceUnavailable

    public func message(language: AppLanguage, hasCachedBoard: Bool) -> String {
        let reason = self == .offline
            ? language.text("No internet connection.", "网络未连接。")
            : language.text("This source could not be refreshed.", "暂时无法更新这个来源。")
        return reason + " " + (hasCachedBoard
            ? language.text("Showing the last saved results.", "正在显示上次保存的结果。")
            : language.text("Connect and try refreshing again.", "请联网后重新刷新。"))
    }
}

public struct LeaderboardRefreshResult: Sendable {
    public let snapshot: LeaderboardSnapshot
    public let failures: [LeaderboardKind: LeaderboardFailure]
}

/// Refreshes sources independently. One source failing must never erase another
/// source, another category, or the offline copy of the failed board.
public struct LeaderboardService: Sendable {
    public typealias Fetch = @Sendable (LeaderboardKind) async throws -> Leaderboard
    private let fetch: Fetch

    public init(fetch: @escaping Fetch = { try await LeaderboardFetcher().fetch($0) }) {
        self.fetch = fetch
    }

    public func refresh(_ kinds: [LeaderboardKind], keeping previous: LeaderboardSnapshot) async -> LeaderboardRefreshResult {
        await withTaskGroup(of: (LeaderboardKind, Leaderboard?, LeaderboardFailure?).self) { group in
            for kind in Set(kinds) {
                group.addTask {
                    do {
                        let board = try await fetch(kind)
                        guard board.kind == kind, !board.entries.isEmpty else {
                            return (kind, nil, .sourceUnavailable)
                        }
                        return (kind, board, nil)
                    } catch let error as URLError where [.notConnectedToInternet, .networkConnectionLost, .dataNotAllowed].contains(error.code) {
                        return (kind, nil, .offline)
                    } catch {
                        return (kind, nil, .sourceUnavailable)
                    }
                }
            }
            var snapshot = previous
            var failures: [LeaderboardKind: LeaderboardFailure] = [:]
            for await (kind, board, failure) in group {
                if let board { snapshot.boards[kind] = board }
                if let failure { failures[kind] = failure }
            }
            return LeaderboardRefreshResult(snapshot: snapshot, failures: failures)
        }
    }
}

public enum LeaderboardFreshness {
    public static let interval: TimeInterval = 24 * 60 * 60
    public static let retryInterval: TimeInterval = 5 * 60

    /// iPadOS controls background execution. Check on foreground activation and
    /// category changes, with a short backoff after failures. Pull to refresh
    /// bypasses this policy.
    public static func dueKinds(_ kinds: [LeaderboardKind], snapshot: LeaderboardSnapshot,
                                lastAttempts: [LeaderboardKind: Date], now: Date = Date()) -> [LeaderboardKind] {
        kinds.filter { kind in
            if let attempt = lastAttempts[kind], now.timeIntervalSince(attempt) < retryInterval { return false }
            guard let board = snapshot.boards[kind] else { return true }
            let age = now.timeIntervalSince(board.fetchedAt)
            return age < 0 || age >= interval
        }
    }
}
