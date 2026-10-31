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
        if kind.isShareUsage || kind.sourcePrefix == "Arena" { throw URLError(.resourceUnavailable) }
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
        let acquisition: Acquisition?
    }
    private struct Acquisition: Decodable, Sendable {
        let resources: [Resource]
    }
    private struct Resource: Decodable, Sendable {
        let url: String
        let maxBytes: Int
        let accept: String
        let revisionFrom: Int?
        let optional: Bool?
    }
    private struct SourceBytes: Encodable {
        let url: String
        let data: String
    }
    private struct SourceBundle: Encodable {
        let resources: [SourceBytes?]
    }

    private func shared(_ kind: LeaderboardKind, endpoint: URL, onCachedBoard: LeaderboardService.BoardUpdate?) async throws -> Leaderboard {
        let path = endpoint.appendingPathComponent("v1/boards/\(kind.rawValue)")
        var request = URLRequest(url: path.appendingPathComponent("refresh"))
        request.httpMethod = "POST"
        request.setValue("client-first", forHTTPHeaderField: "X-BenchGauge-Acquisition")
        if kind.sourcePrefix == "Arena" || kind.isPrice { request.timeoutInterval = 30 }
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
                group.addTask {
                    if let plan = grant.acquisition { return try await acquire(kind, path: path, grant: grant, plan: plan) }
                    return try await contribute(kind, path: path, grant: grant)
                }
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
            if grant.acquisition != nil, validGrant(grant) {
                var fallback = URLRequest(url: path.appendingPathComponent("fallback"))
                fallback.httpMethod = "POST"
                fallback.timeoutInterval = 30
                fallback.setValue(grant.token, forHTTPHeaderField: "X-BenchGauge-Grant")
                if let accepted = try? await sharedResponse(fallback), let board = valid(accepted.board, kind: kind) { return board }
                try Task.checkCancellation()
            }
            if grant.acquisition == nil, let cached { return cached }
            // Upload timeout may occur after OSS committed the snapshot.
            if let committed = try? await cachedShared(kind, url: path) { return committed }
            if let cached { return cached }
            throw error
        }
    }

    private func validGrant(_ grant: Grant) -> Bool {
        grant.token.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil
            && grant.expiresAt / 1000 > Date().timeIntervalSince1970
    }

    private func acquire(_ kind: LeaderboardKind, path: URL, grant: Grant, plan: Acquisition) async throws -> Leaderboard {
        guard validGrant(grant), (1...3).contains(plan.resources.count),
              plan.resources.first?.url == grant.sourceURL.absoluteString else { throw URLError(.badServerResponse) }
        let hosts: Set<String> = ["artificialanalysis.ai", "epoch.ai", "huggingface.co", "vercel.com", "ai-gateway.vercel.sh", "docs.cloudbase.net", "openrouter.ai"]
        var raw: [Data?] = [], resources: [SourceBytes?] = [], total = 0
        for spec in plan.resources {
            var source = spec.url
            if let index = spec.revisionFrom {
                guard raw.indices.contains(index), let data = raw[index],
                      let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let revision = object["sha"] as? String,
                      revision.range(of: "^[a-f0-9]{40}$", options: .regularExpression) != nil else { throw URLError(.badServerResponse) }
                source = source.replacingOccurrences(of: "{revision}", with: revision)
            }
            guard let url = URL(string: source), url.scheme == "https", let host = url.host, hosts.contains(host),
                  url.user == nil, url.password == nil, url.port == nil,
                  spec.maxBytes > 0, spec.maxBytes <= 16 * 1024 * 1024,
                  validGrant(grant) else { throw URLError(.badServerResponse) }
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 10
                request.cachePolicy = .reloadIgnoringLocalCacheData
                request.setValue(spec.accept, forHTTPHeaderField: "Accept")
                request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                      data.count <= spec.maxBytes else { throw URLError(.badServerResponse) }
                total += data.count
                guard total <= 17_000_000 else { throw URLError(.dataLengthExceedsMaximum) }
                raw.append(data); resources.append(SourceBytes(url: source, data: data.base64EncodedString()))
            } catch {
                try Task.checkCancellation()
                guard spec.optional == true else { throw error }
                raw.append(nil); resources.append(nil)
            }
        }
        guard validGrant(grant) else { throw URLError(.timedOut) }
        var upload = URLRequest(url: path.appendingPathComponent("acquire"))
        upload.httpMethod = "POST"
        upload.timeoutInterval = 30
        upload.setValue("application/json", forHTTPHeaderField: "Content-Type")
        upload.setValue(grant.token, forHTTPHeaderField: "X-BenchGauge-Grant")
        upload.httpBody = try JSONEncoder().encode(SourceBundle(resources: resources))
        let accepted = try await sharedResponse(upload)
        guard let board = valid(accepted.board, kind: kind) else { throw URLError(.badServerResponse) }
        return board
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
        var request = URLRequest(url: url)
        request.setValue("client-first", forHTTPHeaderField: "X-BenchGauge-Acquisition")
        let response = try await sharedResponse(request)
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
        case .openRouterUsage, .vercelUsage, .cloudbaseUsage, .openRouterPrice, .epochMathECI, .epochCyberECI, .epochSoftwareECI: throw URLError(.resourceUnavailable)
        case .epochECI:
            return try EpochECIParser.parse(html)
        case .artificialAnalysis:
            return try HTMLLeaderboardParser.artificialAnalysis(fromHTML: html)
        case .valsSWEbench:
            return try HTMLLeaderboardParser.valsSWEbench(fromHTML: html)
        case .artificialAnalysisCodingAgent:
            return try HTMLLeaderboardParser.artificialAnalysisCodingAgent(fromHTML: html)
        case .arenaText:
            return try HTMLLeaderboardParser.arenaText(fromHTML: html)
        case .codeArenaWebDev:
            return try HTMLLeaderboardParser.arenaWebDev(fromHTML: html)
        case .artificialAnalysisTextToImage:
            return try HTMLLeaderboardParser.artificialAnalysisTextToImage(fromHTML: html)
        case .artificialAnalysisImageEditing, .artificialAnalysisImageToVideo, .artificialAnalysisVideoEditing, .artificialAnalysisSpeechProviderVoice, .artificialAnalysisSpeechControlledVoice:
            return try HTMLLeaderboardParser.artificialAnalysisMediaVariant(fromHTML: html, kind: kind)
        case .artificialAnalysisSpeechAgent:
            return try HTMLLeaderboardParser.artificialAnalysisSpeechAgent(fromHTML: html)
        case .artificialAnalysisSpeechToText, .artificialAnalysisSpeechToTextStreaming:
            return try HTMLLeaderboardParser.artificialAnalysisSpeechToText(fromHTML: html, kind: kind)
        case .arenaTextToImage:
            return try HTMLLeaderboardParser.arenaTextToImage(fromHTML: html)
        case .artificialAnalysisTextToVideo:
            return try HTMLLeaderboardParser.artificialAnalysisTextToVideo(fromHTML: html)
        case .arenaTextToVideo:
            return try HTMLLeaderboardParser.arenaTextToVideo(fromHTML: html)
        case .arenaTextUncontrolled, .codeArenaImageToWebDev, .arenaImageEditing, .arenaMultiImageEditing, .arenaImageToVideo, .arenaVideoEditing:
            throw URLError(.resourceUnavailable)
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
