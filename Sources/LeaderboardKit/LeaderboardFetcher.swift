import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct LeaderboardFetcher: Sendable {
    public let session: URLSession
    public let sharedEndpoint: URL?
    public let contributionTimeout: TimeInterval

    public init(session: URLSession = .shared, sharedEndpoint: URL? = SharedLeaderboardConfiguration.endpoint,
                contributionTimeout: TimeInterval = 30) {
        self.session = session
        self.sharedEndpoint = sharedEndpoint
        self.contributionTimeout = contributionTimeout
    }

    public func fetch(_ kind: LeaderboardKind, onCachedBoard: LeaderboardService.BoardUpdate? = nil) async throws -> Leaderboard {
        if let sharedEndpoint { return try await shared(kind, endpoint: sharedEndpoint, onCachedBoard: onCachedBoard) }
        // Arena's licensed Parquet snapshots are acquired by the shared service.
        // Never fall back to the website when shared storage is unconfigured.
        if kind == .openRouterUsage { throw LeaderboardConfigurationRequired() }
        if kind == .vercelUsage || kind.sourcePrefix == "Arena" { throw URLError(.resourceUnavailable) }
        return try parse(kind, html: await html(kind.dataURL))
    }

    /// Reads FC only; used to paint the Windows view before its background refresh.
    public func fetchCached(_ kind: LeaderboardKind) async throws -> Leaderboard? {
        guard let sharedEndpoint else { return nil }
        return try await cachedShared(kind, url: sharedEndpoint.appendingPathComponent("v1/boards/\(kind.rawValue)"))
    }

    private struct SharedResponse: Decodable {
        let board: Leaderboard?
        let grant: Grant?
        let configurationRequired: Bool?
    }
    private struct Grant: Decodable {
        let token: String
        let expiresAt: Double
        let sourceURL: URL
    }

    private func shared(_ kind: LeaderboardKind, endpoint: URL, onCachedBoard: LeaderboardService.BoardUpdate?) async throws -> Leaderboard {
        let path = endpoint.appendingPathComponent("v1/boards/\(kind.rawValue)")
        var request = URLRequest(url: path.appendingPathComponent("refresh"))
        request.httpMethod = "POST"
        if kind.sourcePrefix == "Arena" { request.timeoutInterval = 30 }
        let response: SharedResponse
        do {
            response = try await sharedResponse(request)
        } catch {
            try Task.checkCancellation()
            // The read path remains usable when refresh coordination is down.
            // Neither path failing is permission to contact the origin.
            return try await cachedShared(kind, url: path)
        }
        let cached = valid(response.board, kind: kind)
        if let cached { await onCachedBoard?(cached) }
        if response.configurationRequired == true && cached == nil { throw LeaderboardConfigurationRequired() }
        guard let grant = response.grant else {
            if let cached { return cached }
            // Another contributor may be seeding the first snapshot. Poll only
            // the shared read endpoint; never steal or bypass their grant.
            for _ in 0..<3 {
                try await Task.sleep(for: .seconds(2))
                if let board = try? await cachedShared(kind, url: path) { return board }
            }
            throw URLError(.resourceUnavailable)
        }
        do {
            return try await withThrowingTaskGroup(of: Leaderboard.self) { group in
                group.addTask { try await contribute(kind, path: path, grant: grant) }
                group.addTask {
                    try await Task.sleep(for: .seconds(contributionTimeout))
                    throw URLError(.timedOut)
                }
                defer { group.cancelAll() }
                // Both tasks either return a board or throw; the group has two children.
                return try await group.next()!
            }
        } catch {
            try Task.checkCancellation()
            if let cached { return cached }
            // Upload timeout may occur after OSS committed the snapshot.
            if let committed = try? await cachedShared(kind, url: path) { return committed }
            throw error
        }
    }

    private func contribute(_ kind: LeaderboardKind, path: URL, grant: Grant) async throws -> Leaderboard {
        guard kind.sourcePrefix != "Arena", !kind.isUsage else { throw URLError(.badServerResponse) }
        guard grant.sourceURL == kind.dataURL,
              grant.token.utf8.count == 43,
              grant.expiresAt / 1000 > Date().timeIntervalSince1970 else { throw URLError(.badServerResponse) }
        let source = try await html(kind.dataURL)
        // Check local parsing before uploading a login page / block page.
        _ = try parse(kind, html: source)
        guard grant.expiresAt / 1000 > Date().timeIntervalSince1970 else { throw URLError(.timedOut) }
        var upload = URLRequest(url: path.appendingPathComponent("contribute"))
        upload.httpMethod = "POST"
        upload.setValue(kind == .epochECI ? "text/csv; charset=utf-8" : "text/html; charset=utf-8", forHTTPHeaderField: "Content-Type")
        upload.setValue(grant.token, forHTTPHeaderField: "X-BenchGauge-Grant")
        upload.httpBody = Data(source.utf8)
        let accepted = try await sharedResponse(upload)
        guard let board = valid(accepted.board, kind: kind) else { throw URLError(.badServerResponse) }
        return board
    }

    private func valid(_ board: Leaderboard?, kind: LeaderboardKind) -> Leaderboard? {
        guard let board, board.kind == kind, !board.entries.isEmpty,
              board.fetchedAt.timeIntervalSinceNow < 300,
              board.entries.allSatisfy({ $0.rank > 0 && !$0.name.isEmpty && $0.score.isFinite }) else { return nil }
        return board
    }

    private func cachedShared(_ kind: LeaderboardKind, url: URL) async throws -> Leaderboard {
        let response = try await sharedResponse(URLRequest(url: url))
        if response.configurationRequired == true && response.board == nil { throw LeaderboardConfigurationRequired() }
        guard let board = valid(response.board, kind: kind) else { throw URLError(.resourceUnavailable) }
        return board
    }

    private func sharedResponse(_ value: URLRequest) async throws -> SharedResponse {
        var request = value
        request.timeoutInterval = value.timeoutInterval == 30 ? 30 : 10
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), data.count <= 16_000_000 else {
            throw URLError(.badServerResponse)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: value) else { throw URLError(.cannotParseResponse) }
            return date
        }
        return try decoder.decode(SharedResponse.self, from: data)
    }

    func parse(_ kind: LeaderboardKind, html: String) throws -> Leaderboard {
        switch kind {
        case .openRouterUsage, .vercelUsage: throw URLError(.resourceUnavailable)
        case .epochECI:
            return try EpochECIParser.parse(html)
        case .artificialAnalysis:
            return try HTMLLeaderboardParser.artificialAnalysis(fromHTML: html)
        case .artificialAnalysisCodingAgent:
            return try HTMLLeaderboardParser.artificialAnalysisCodingAgent(fromHTML: html)
        case .arenaText:
            return try HTMLLeaderboardParser.arenaText(fromHTML: html)
        case .codeArenaWebDev:
            return try HTMLLeaderboardParser.arenaWebDev(fromHTML: html)
        case .artificialAnalysisTextToImage:
            return try HTMLLeaderboardParser.artificialAnalysisTextToImage(fromHTML: html)
        case .arenaTextToImage:
            return try HTMLLeaderboardParser.arenaTextToImage(fromHTML: html)
        case .artificialAnalysisTextToVideo:
            return try HTMLLeaderboardParser.artificialAnalysisTextToVideo(fromHTML: html)
        case .arenaTextToVideo:
            return try HTMLLeaderboardParser.arenaTextToVideo(fromHTML: html)
        }
    }

    private func html(_ url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/606.1.36 (KHTML, like Gecko) Version/17.4 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue(url.pathExtension == "csv" ? "text/csv" : "text/html", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await session.data(for: request)
        if let response = response as? HTTPURLResponse, !(200..<300).contains(response.statusCode) {
            throw URLError(.badServerResponse)
        }
        return String(decoding: data, as: UTF8.self)
    }
}
