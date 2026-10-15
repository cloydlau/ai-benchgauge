import Foundation
import Testing
@testable import LeaderboardKit

@Test func sandAICountrySurvivesFailedMetadataCacheAndCompanyAggregation() throws {
    let entries = [
        LeaderboardEntry(rank: 1, name: "MAGI-2 Preview (0912)", score: 100, organization: "Sand.ai",
            developerCountry: .init(key: "sandai", countryCode: nil)),
        LeaderboardEntry(rank: 2, name: "MAGI-1", score: 90, organization: "Sand AI"),
        LeaderboardEntry(rank: 3, name: "Unknown MAGI-like Model", score: 80, organization: "Unknown Maker"),
    ]
    let board = Leaderboard(kind: .artificialAnalysisTextToVideo, title: "Video", entries: entries)
    let saved = try JSONDecoder().decode(Leaderboard.self, from: JSONEncoder().encode(board))
    #expect(OrganizationRegion.country(for: saved.entries[0]) == .china)
    #expect(OrganizationRegion.country("SANDAI", modelName: "GAGA-1") == .china)
    #expect(LeaderboardPresentation.countryFilters(saved) == [.all, .country(.china), .unknown])
    let models = LeaderboardPresentation.rows(saved, grouping: .model, filter: .country(.china))
    #expect(models.map(\.name) == entries.prefix(2).map(\.name))
    #expect(models.map(\.score) == [100, 90])
    let companies = LeaderboardPresentation.rows(saved, grouping: .company, filter: .country(.china))
    #expect(companies.count == 1)
    #expect(companies.first?.score == 100)
    #expect(companies.first.flatMap { OrganizationRegion.country(for: $0) } == .china)
    #expect(LeaderboardPresentation.rows(saved, grouping: .model, filter: .unknown).map(\.name) == [entries[2].name])
}

@Test func dynamicCountrySurvivesCacheAggregationAndIntersectsSourceFilters() throws {
    let japan = try #require(OrganizationCountry(regionCode: "JP"))
    let entries = [
        LeaderboardEntry(rank: 1, name: "Future Closed", score: 100, organization: "New Maker", openness: .closed, developerCountry: .init(key: "newmaker", countryCode: "JP")),
        LeaderboardEntry(rank: 2, name: "Future Open", score: 90, organization: "New Maker", openness: .open, developerCountry: .init(key: "newmaker", countryCode: "JP")),
        LeaderboardEntry(rank: 3, name: "Unknown", score: 80, organization: "Unknown Maker"),
    ]
    let board = Leaderboard(kind: .arenaTextToVideo, title: "Video", entries: entries)
    let saved = try JSONDecoder().decode(Leaderboard.self, from: JSONEncoder().encode(board))
    #expect(OrganizationRegion.country(for: saved.entries[0]) == japan)
    #expect(LeaderboardPresentation.countryFilters(saved) == [.all, .country(japan), .unknown])
    let rows = LeaderboardPresentation.rows(saved, grouping: .company, filter: .country(japan), openness: .open)
    #expect(rows.count == 1)
    #expect(rows.first?.score == 90)
    #expect(rows.first.flatMap { OrganizationRegion.country(for: $0) } == japan)
    #expect(LeaderboardPresentation.rows(saved, grouping: .model, filter: .unknown).map(\.name) == ["Unknown"])
    #expect(japan.flagEmoji == "🇯🇵")
    #expect(japan.localizedName(language: .chinese) == "日本")
}

@Test func dynamicCountryValidatesDeveloperAndPreservesLegacyPreferences() {
    #expect(OrganizationCountry(rawValue: "unitedStates") == .unitedStates)
    #expect(OrganizationCountry(rawValue: "GB")?.regionCode == "GB")
    #expect(OrganizationCountry(rawValue: "china")?.rawValue == "china")
    #expect(OrganizationCountry(regionCode: "ZZ") == nil)
    #expect(OrganizationCountry(regionCode: "bad") == nil)
    let wrong = LeaderboardEntry(rank: 1, name: "Opencode - GPT-9", score: 100, organization: "Opencode", developerCountry: .init(key: "opencode", countryCode: "CN"))
    #expect(OrganizationRegion.country(for: wrong) == .unitedStates)
    let corrected = LeaderboardEntry(rank: 1, name: "GPT", score: 100, organization: "OpenAI", developerCountry: .init(key: "openai", countryCode: "GB"))
    #expect(OrganizationRegion.country(for: corrected)?.regionCode == "GB")
    for (organization, country) in [("Utopai Studios", OrganizationCountry.unitedStates), ("Skywork AI", .singapore), ("Sapiens AI", .singapore)] {
        #expect(OrganizationRegion.country(organization) == country)
    }
}
