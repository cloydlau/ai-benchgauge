import Foundation
import Testing
@testable import LeaderboardKit

@Test func hongKongMacaoTaiwanUseChinaForCachedRowsFlagsAndFilters() throws {
    for code in ["HK", "MO", "TW", " hk ", "mo", "tw", "HKG", "MAC", "TWN", "Hong Kong", "Macao", "Macau", "Taiwan", "香港", "澳门", "澳門", "台湾", "台灣", "臺灣"] {
        let country = try #require(OrganizationCountry(regionCode: code))
        #expect(country == .china)
        #expect(country.flagEmoji == "🇨🇳")
        #expect(country.localizedName(language: .chinese) == "中国")
        #expect(country.localizedName(language: .english) == "China")
        #expect(OrganizationCountry(rawValue: code)?.rawValue == "china")
    }
    #expect(Set(OrganizationCountry.allCases).count == OrganizationCountry.allCases.count)
    #expect(!OrganizationCountry.allCases.contains { ["HK", "MO", "TW"].contains($0.regionCode) })
    let entries = ["CN", "HK", "MO", "TW"].enumerated().map { index, code in
        LeaderboardEntry(rank: index + 1, name: "Model \(code)", score: Double(100 - index), organization: "New Maker",
            developerCountry: .init(key: "newmaker", countryCode: code))
    }
    let board = Leaderboard(kind: .arenaText, title: "Text", entries: entries)
    let cached = try JSONDecoder().decode(Leaderboard.self, from: JSONEncoder().encode(board))
    #expect(cached.entries.allSatisfy { OrganizationRegion.country(for: $0) == .china })
    #expect(LeaderboardPresentation.countryFilters(cached) == [.all, .country(.china)])
    #expect(LeaderboardPresentation.rows(cached, grouping: .model, filter: .country(.china)).map(\.name) == entries.map(\.name))
    let companies = LeaderboardPresentation.rows(cached, grouping: .company, filter: .country(.china))
    #expect(companies.count == 1)
    #expect(companies.first?.score == 100)
    #expect(companies.first.flatMap { OrganizationRegion.country(for: $0) } == .china)
}
@Test func auditedCountryCoverageSurvivesCacheAndFiltersWithoutUsingBaseModelOwners() throws {
    struct Case: Decodable { let name: String; let organization: String?; let key: String?; let countryCode: String? }
    let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "fixtures/country-coverage.json")
    let cases = try JSONDecoder().decode([Case].self, from: Data(contentsOf: file))
    for row in cases {
        let entry = LeaderboardEntry(rank: 1, name: row.name, score: 100, organization: row.organization,
            developerCountry: .init(key: row.key ?? "", countryCode: nil))
        let board = Leaderboard(kind: .arenaText, title: "Text", entries: [entry])
        let saved = try JSONDecoder().decode(Leaderboard.self, from: JSONEncoder().encode(board))
        #expect(OrganizationLogoCatalog.developerKey(organization: row.organization, modelName: row.name) == row.key)
        #expect(OrganizationRegion.country(for: saved.entries[0])?.regionCode == row.countryCode)
        if let code = row.countryCode, let country = OrganizationCountry(regionCode: code) {
            #expect(LeaderboardPresentation.rows(saved, grouping: .model, filter: .country(country)).count == 1)
            let companies = LeaderboardPresentation.rows(saved, grouping: .company, filter: .country(country))
            #expect(companies.count == 1)
            #expect(companies.first.flatMap { OrganizationRegion.country(for: $0) } == country)
        }
    }
    #expect(OrganizationRegion.country(nil, modelName: "gemma-2-9b-it-simpo-finetune") == nil)
    #expect(OrganizationRegion.country("Other Maker", modelName: "yi-lightning") == nil)
    #expect(OrganizationRegion.country(nil, modelName: "llama-unknown-finetune") == nil)
}

@Test func trinityCountryRepairsMissingDeveloperAndSurvivesCacheAndCompanyFiltering() throws {
    let entries = [
        LeaderboardEntry(rank: 1, name: "trinity-large-preview", score: 100,
            developerCountry: .init(key: "", countryCode: nil)),
        LeaderboardEntry(rank: 2, name: "trinity-large-thinking", score: 90),
        LeaderboardEntry(rank: 3, name: "trinity-large-thinking-finetune", score: 80),
        LeaderboardEntry(rank: 4, name: "trinity-large-preview", score: 70, organization: "Other Maker"),
    ]
    let board = Leaderboard(kind: .arenaText, title: "Text", entries: entries)
    let saved = try JSONDecoder().decode(Leaderboard.self, from: JSONEncoder().encode(board))
    #expect(OrganizationRegion.country(for: saved.entries[0]) == .unitedStates)
    #expect(OrganizationRegion.country(for: saved.entries[1]) == .unitedStates)
    #expect(OrganizationRegion.country(for: saved.entries[2]) == nil)
    #expect(OrganizationRegion.country(for: saved.entries[3]) == nil)
    #expect(OrganizationRegion.country("ARCEE AI", modelName: "trinity-large-thinking") == .unitedStates)
    #expect(LeaderboardPresentation.rows(saved, grouping: .model, filter: .country(.unitedStates)).map(\.name) == entries.prefix(2).map(\.name))
    let companies = LeaderboardPresentation.rows(saved, grouping: .company, filter: .country(.unitedStates))
    #expect(companies.count == 1)
    #expect(companies.first?.name == "Arcee AI")
    #expect(companies.first.flatMap { OrganizationRegion.country(for: $0) } == .unitedStates)
}

@Test func solarCountryRepairsMissingDeveloperWithoutGuessingSimilarModels() throws {
    let korea = try #require(OrganizationCountry(regionCode: "KR"))
    let entries = [
        LeaderboardEntry(rank: 1, name: "solar-pro4", score: 100, organization: "Upstage",
            developerCountry: .init(key: "upstage", countryCode: nil)),
        LeaderboardEntry(rank: 2, name: "solar-10.7b-instruct-v1.0", score: 90),
        LeaderboardEntry(rank: 3, name: "solar-10.7b-instruct-v1.0-finetune", score: 80),
        LeaderboardEntry(rank: 4, name: "solar-10.7b-instruct-v1.0", score: 70, organization: "Other Maker"),
    ]
    let board = Leaderboard(kind: .arenaText, title: "Text", entries: entries)
    let saved = try JSONDecoder().decode(Leaderboard.self, from: JSONEncoder().encode(board))
    #expect(OrganizationRegion.country(for: saved.entries[0]) == korea)
    #expect(OrganizationRegion.country(for: saved.entries[1]) == korea)
    #expect(OrganizationRegion.country(for: saved.entries[2]) == nil)
    #expect(OrganizationRegion.country(for: saved.entries[3]) == nil)
    #expect(LeaderboardPresentation.rows(saved, grouping: .model, filter: .country(korea)).map(\.name) == entries.prefix(2).map(\.name))
    let companies = LeaderboardPresentation.rows(saved, grouping: .company, filter: .country(korea))
    #expect(companies.count == 1)
    #expect(companies.first?.name == "Upstage")
    #expect(companies.first.flatMap { OrganizationRegion.country(for: $0) } == korea)
}

@Test func longCatCountrySurvivesFailedMetadataAndCompanyFiltering() throws {
    let entry = LeaderboardEntry(rank: 1, name: "longcat-flash-chat-2602-exp", score: 100,
        organization: "Meituan", developerCountry: .init(key: "meituan", countryCode: nil))
    let board = Leaderboard(kind: .arenaText, title: "Text", entries: [entry])
    let saved = try JSONDecoder().decode(Leaderboard.self, from: JSONEncoder().encode(board))
    #expect(OrganizationRegion.country(for: saved.entries[0]) == .china)
    #expect(OrganizationRegion.country("MEITUAN", modelName: "longcat-flash-chat") == .china)
    #expect(LeaderboardPresentation.rows(saved, grouping: .model, filter: .country(.china)).map(\.name) == [entry.name])
    let companies = LeaderboardPresentation.rows(saved, grouping: .company, filter: .country(.china))
    #expect(companies.count == 1)
    #expect(companies.first.flatMap { OrganizationRegion.country(for: $0) } == .china)
    #expect(OrganizationRegion.country("Unknown Maker", modelName: "longcat") == nil)
}

@Test func amazonNovaCountrySurvivesFailedMetadataAndCompanyFiltering() throws {
    let entry = LeaderboardEntry(rank: 1, name: "amazon-nova-experimental-chat-26-02-10", score: 100,
        organization: "Amazon", developerCountry: .init(key: "amazon", countryCode: nil))
    let board = Leaderboard(kind: .arenaText, title: "Text", entries: [entry])
    let saved = try JSONDecoder().decode(Leaderboard.self, from: JSONEncoder().encode(board))
    #expect(OrganizationRegion.country(for: saved.entries[0]) == .unitedStates)
    #expect(OrganizationRegion.country("AMAZON", modelName: "nova-2-lite") == .unitedStates)
    #expect(LeaderboardPresentation.rows(saved, grouping: .model, filter: .country(.unitedStates)).map(\.name) == [entry.name])
    let companies = LeaderboardPresentation.rows(saved, grouping: .company, filter: .country(.unitedStates))
    #expect(companies.count == 1)
    #expect(companies.first.flatMap { OrganizationRegion.country(for: $0) } == .unitedStates)
    #expect(OrganizationRegion.country("Unknown Maker", modelName: "nova") == nil)
}

@Test func inklingCountryUnifiesThinkyWithThinkingMachinesAfterCacheRoundTrip() throws {
    let entries = [
        LeaderboardEntry(rank: 1, name: "inkling", score: 100, organization: "Thinky",
            developerCountry: .init(key: "thinky", countryCode: nil)),
        LeaderboardEntry(rank: 2, name: "Inkling Small", score: 90, organization: "Thinking Machines Lab"),
        LeaderboardEntry(rank: 3, name: "Unknown Model", score: 80, organization: "Unknown Maker"),
    ]
    let board = Leaderboard(kind: .arenaText, title: "Text", entries: entries)
    let saved = try JSONDecoder().decode(Leaderboard.self, from: JSONEncoder().encode(board))
    #expect(OrganizationRegion.country(for: saved.entries[0]) == .unitedStates)
    #expect(OrganizationRegion.country("THINKY", modelName: "Inkling Small") == .unitedStates)
    #expect(LeaderboardPresentation.rows(saved, grouping: .model, filter: .country(.unitedStates)).map(\.name) == entries.prefix(2).map(\.name))
    let companies = LeaderboardPresentation.rows(saved, grouping: .company, filter: .country(.unitedStates))
    #expect(companies.count == 1)
    #expect(companies.first?.score == 100)
    #expect(companies.first.flatMap { OrganizationRegion.country(for: $0) } == .unitedStates)
    #expect(OrganizationRegion.country("Unknown Maker", modelName: "inkling") == nil)
}

@Test func ernieCountrySurvivesFailedMetadataCacheAndCompanyAggregation() throws {
    let entry = LeaderboardEntry(rank: 1, name: "ernie-5.1", score: 100, organization: "Baidu",
        developerCountry: .init(key: "baidu", countryCode: nil))
    let board = Leaderboard(kind: .arenaText, title: "Text", entries: [entry])
    let saved = try JSONDecoder().decode(Leaderboard.self, from: JSONEncoder().encode(board))
    #expect(OrganizationRegion.country(for: saved.entries[0]) == .china)
    #expect(OrganizationRegion.country("BAIDU", modelName: "ernie-5.0-0110") == .china)
    #expect(LeaderboardPresentation.rows(saved, grouping: .model, filter: .country(.china)).map(\.name) == [entry.name])
    let companies = LeaderboardPresentation.rows(saved, grouping: .company, filter: .country(.china))
    #expect(companies.count == 1)
    #expect(companies.first.flatMap { OrganizationRegion.country(for: $0) } == .china)
    #expect(OrganizationRegion.country("Unknown Maker", modelName: "ernie-like") == nil)
}

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
