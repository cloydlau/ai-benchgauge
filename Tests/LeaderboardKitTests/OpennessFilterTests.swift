import Testing
import LeaderboardKit
#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI
import AppKit

@MainActor @Test func compactSourceBadgesRenderReadableGlyphsInBothAppearances() throws {
    _ = NSApplication.shared
    for scheme in [ColorScheme.light, .dark] {
        for status in [ModelOpenness.open, .closed] {
            let badge = ModelOpennessBadge(status, language: .chinese,
                colorScheme: scheme, showsTitle: false).padding(4)
                .environment(\.colorScheme, scheme)
            let image = try #require(ImageRenderer(content: badge).cgImage)
            #expect(image.width >= 18)
            #expect(image.height >= 15)
            let data = try #require(image.dataProvider?.data)
            #expect((data as Data).contains { $0 != 0 })
        }
    }
}

#endif

@Test func sourceFilterIntersectsCountryBeforeCompanyAggregation() {
    let entries = [
        LeaderboardEntry(rank: 1, name: "GPT Closed", score: 100, organization: "OpenAI", openness: .closed),
        LeaderboardEntry(rank: 2, name: "GPT Open", score: 90, organization: "OpenAI", openness: .open),
        LeaderboardEntry(rank: 3, name: "DeepSeek Open", score: 80, organization: "DeepSeek", openness: .open),
        LeaderboardEntry(rank: 4, name: "Claude Unknown", score: 70, organization: "Anthropic")
    ]
    let board = Leaderboard(kind: .arenaText, title: "Fixture", entries: entries)
    #expect(LeaderboardPresentation.rows(board, grouping: .model, filter: .all, openness: .open).map(\.name) == ["GPT Open", "DeepSeek Open"])
    #expect(LeaderboardPresentation.rows(board, grouping: .model, filter: .country(.unitedStates), openness: .open).map(\.name) == ["GPT Open"])
    let companies = LeaderboardPresentation.companies(board, filter: .all, openness: .open)
    #expect(companies.map(\.entry.score) == [90, 80])
    #expect(companies.allSatisfy { $0.entry.openness == nil })
    #expect(LeaderboardPresentation.rows(board, grouping: .company, filter: .all, openness: .open) == companies.map(\.entry))
    #expect(LeaderboardPresentation.rows(board, grouping: .model, filter: .all, openness: .unknown).map(\.name) == ["Claude Unknown"])
    #expect(LeaderboardPresentation.rows(board, grouping: .model, filter: .country(.china), openness: .closed).isEmpty)
    #expect(LeaderboardPresentation.rows(board, grouping: .model, filter: .all, openness: .all) == entries)
}
