import Foundation
import Testing
@testable import LeaderboardKit

@Test func valsSWEBenchParsingPreservesHarnessAndMetrics() throws {
    let rows = (0..<20).map { index in
        "<tr><td>\(index + 1)</td><th><a href=\"/models/acme_model-1\">Example &amp; Model</a></th><td>Agent \(index)</td><td>\(90 - index)%</td><td>\(index == 0 ? "$0.00" : "—")</td><td>1m</td><td>\(index == 0 ? "1h04m" : "108.54s")</td></tr>"
    }.joined()
    let heads = ["Rank", "Model", "Harness", "Score", "Cost / Test", "Tokens / Test", "Duration / Test"].map { "<th>\($0)</th>" }.joined()
    let html = "Archived Benchmark Updated 9/1/2026 <table aria-labelledby=\"benchmark-leaderboard-title\"><tr>\(heads)</tr>\(rows)</table>"
    let board = try HTMLLeaderboardParser.valsSWEbench(fromHTML: html)
    #expect(board.entries.count == 20)
    #expect(board.entries[0].name == "Example & Model · Agent 0")
    #expect(board.entries[0].taskCostUSD == 0)
    #expect(board.entries[1].taskCostUSD == nil)
    #expect(board.entries[0].speed == 3840)
    #expect(board.entries[1].speed == 108.54)
    #expect(board.entries[0].modelID != board.entries[1].modelID)
    #expect(throws: HTMLLeaderboardParser.ParserError.self) { try HTMLLeaderboardParser.valsSWEbench(fromHTML: html.replacingOccurrences(of: "Archived Benchmark", with: "")) }
}
