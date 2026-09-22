import Foundation

public struct LeaderboardFetcher: Sendable {
    public let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetch(_ kind: LeaderboardKind) async throws -> Leaderboard {
        let html = try await html(kind.sourceURL)
        switch kind {
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
        request.timeoutInterval = 30
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/606.1.36 (KHTML, like Gecko) Version/17.4 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await session.data(for: request)
        if let response = response as? HTTPURLResponse, !(200..<300).contains(response.statusCode) {
            throw URLError(.badServerResponse)
        }
        return String(decoding: data, as: UTF8.self)
    }
}
