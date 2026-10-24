import Foundation

public struct LeaderboardConfigurationRequired: Error, Sendable { public init() {} }

public enum LeaderboardFailure: Equatable, Sendable {
    case offline, sourceUnavailable, configurationRequired

    public func message(language: AppLanguage, hasCachedBoard: Bool) -> String {
        if self == .configurationRequired { return language.text("Data source awaiting configuration. OpenRouter API key is required on the server.", "数据源待配置：服务端尚未配置 OpenRouter API Key。") }
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
    public typealias BoardUpdate = @Sendable (Leaderboard) async -> Void
    private let fetch: @Sendable (LeaderboardKind, BoardUpdate?) async throws -> Leaderboard

    public init(fetch: @escaping Fetch) {
        self.fetch = { kind, _ in try await fetch(kind) }
    }

    public init(fetcher: LeaderboardFetcher = LeaderboardFetcher()) {
        self.fetch = { kind, update in try await fetcher.fetch(kind, onCachedBoard: update) }
    }

    public func refresh(_ kinds: [LeaderboardKind], keeping previous: LeaderboardSnapshot,
                        onBoard: BoardUpdate? = nil) async -> LeaderboardRefreshResult {
        await withTaskGroup(of: (LeaderboardKind, Leaderboard?, LeaderboardFailure?).self) { group in
            for kind in Set(kinds) {
                group.addTask {
                    do {
                        let board = try await fetch(kind, onBoard)
                        guard board.kind == kind, !board.entries.isEmpty else {
                            return (kind, nil, .sourceUnavailable)
                        }
                        return (kind, board, nil)
                    } catch is LeaderboardConfigurationRequired {
                        return (kind, nil, .configurationRequired)
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
                if let board, board.canReplace(snapshot.boards[kind]) {
                    snapshot.boards[kind] = board
                    await onBoard?(board)
                }
                if let failure { failures[kind] = failure }
            }
            return LeaderboardRefreshResult(snapshot: snapshot, failures: failures)
        }
    }
}

public enum LeaderboardFreshness {
    public static let interval: TimeInterval = 24 * 60 * 60
    public static let retryInterval: TimeInterval = 5 * 60

    /// Check only when entering a board. Manual refresh bypasses the age and
    /// retry backoff; callers must still join the board's in-flight request.
    public static func dueKinds(_ kinds: [LeaderboardKind], snapshot: LeaderboardSnapshot,
                                lastAttempts: [LeaderboardKind: Date], now: Date = Date()) -> [LeaderboardKind] {
        kinds.filter { kind in
            if let attempt = lastAttempts[kind], (0..<retryInterval).contains(now.timeIntervalSince(attempt)) { return false }
            guard let board = snapshot.boards[kind] else { return true }
            let age = now.timeIntervalSince(board.sourceUpdatedAt ?? board.fetchedAt)
            return age >= interval
        }
    }
}
