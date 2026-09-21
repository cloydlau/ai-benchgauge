import Foundation

public struct LeaderboardFetcher: Sendable {
    public let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func artificialAnalysis() async throws -> Leaderboard {
        let html = try await html(
            URL(string: "https://artificialanalysis.ai/evaluations/artificial-analysis-intelligence-index")!
        )
        return try HTMLLeaderboardParser.artificialAnalysis(fromHTML: html)
    }

    public func arenaWebDev() async throws -> Leaderboard {
        let html = try await html(
            URL(string: "https://arena.ai/leaderboard/code/webdev")!
        )
        return try HTMLLeaderboardParser.arenaWebDev(fromHTML: html)
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
