import Foundation
import Testing
import LeaderboardKit

@Test func modelFactsAndProviderPricesSurviveSharedDecodingAndOfflineCaching() throws {
    let metadata: [String: Any] = [
        "id": "lab/new-model", "name": "New Model", "source": "models.dev",
        "sourceURL": "https://models.dev/catalog.json?type=all", "revision": String(repeating: "a", count: 64),
        "fetchedAt": "2026-10-19T00:00:00Z", "limit": ["context": 200000],
        "openWeights": true, "license": "Apache-2.0", "offers": [
            ["provider": "host-a", "providerName": "Host A", "modelID": "new", "name": "New Model",
             "limit": ["context": 100000], "currency": "USD", "unit": "per-million-tokens",
             "cost": ["input": 0.0, "output": 2.5, "cache_read": 0.1,
                      "context_over_200k": ["input": 3.0, "output": 5.0],
                      "tiers": [["tier": ["type": "context", "size": 200000], "input": 3.0, "output": 5.0]]]]
        ]
    ]
    let provenance = ["source": "models.dev", "sourceURL": metadata["sourceURL"] as! String,
                      "revision": metadata["revision"] as! String, "fetchedAt": metadata["fetchedAt"] as! String,
                      "license": "MIT License\nCopyright (c) 2025 models.dev\nPermission notice fixture"]
    let value: [String: Any] = ["kind": "arenaText", "title": "Text Arena", "fetchedAt": "2026-10-18T00:00:00Z",
        "sourceUpdatedAt": "2026-10-15T00:00:00Z", "modelMetadataSource": provenance,
        "entries": [["rank": 1, "name": "New Model", "score": 1400.25, "modelMetadata": metadata, "voteCount": 2000]]]
    let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
    let board = try decoder.decode(Leaderboard.self, from: JSONSerialization.data(withJSONObject: value))
    let entry = try #require(board.entries.first), model = try #require(entry.modelMetadata)
    #expect(entry.resolvedOpenness == .open)
    #expect(entry.voteCount == 2000 && entry.rank == 1 && entry.score == 1400.25)
    #expect(model.limit.context == 200000 && model.license == "Apache-2.0")
    #expect(model.offers[0].limit.context == 100000)
    #expect(model.offers[0].cost?.input == 0 && model.offers[0].cost?.output == 2.5)
    #expect(model.offers[0].cost?.tiers?.first?.tier.size == 200000)
    #expect(model.offers[0].cost?.context_over_200k?.input == 3)
    #expect(board.modelMetadataSource?.license == provenance["license"])
    #expect(try JSONDecoder().decode(Leaderboard.self, from: JSONEncoder().encode(board)) == board)
    #expect(LeaderboardEntry(rank: 1, name: entry.name, score: 1, openness: .closed, modelMetadata: model).resolvedOpenness == .closed)
    let old = Leaderboard(kind: .arenaText, title: board.title, sourceUpdatedAt: board.sourceUpdatedAt, fetchedAt: board.fetchedAt,
                          entries: [LeaderboardEntry(rank: 1, name: entry.name, score: entry.score)])
    #expect(board.canReplace(old))
    #expect(try JSONDecoder().decode(Leaderboard.self, from: JSONEncoder().encode(old)).entries[0].modelMetadata == nil)
}

@Test func modelDetailsPreserveCapabilitiesFutureFieldsAndIndependentProviderTerms() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    let data = try Data(contentsOf: root.appending(path: "fixtures/model-details.json"))
    struct Fixture: Decodable { let entry: LeaderboardEntry }
    let entry = try JSONDecoder().decode(Fixture.self, from: data).entry
    for language in [AppLanguage.english, .chinese, .traditionalChinese] {
        let sections = ModelDetails.sections(for: entry, language: language)
        let values = sections.flatMap(\.rows).map(\.value)
        #expect(values.contains("Apache-2.0") && values.contains("2026-06"))
        #expect(values.contains("Preserved future field") && values.contains("0"))
        #expect(sections.first(where: { $0.id == "capabilities" })?.rows.contains(where: { $0.value == ModelDetails.text("false", language: language) }) == true)
        let provider = try #require(sections.first(where: { $0.id == "provider-0" }))
        #expect(provider.summary?.contains("$0") == true && provider.summary?.contains("$2.5") == true)
        #expect(provider.rows.contains(where: { $0.value == "200,000" }))
        #expect(!provider.rows.contains(where: { $0.value == "$200,000" }))
        #expect(sections.first(where: { $0.id == "provider-1" })?.summary == ModelDetails.text("unknown", language: language))
        #expect(sections.flatMap(\.rows).first(where: { $0.value == "javascript:alert(1)" })?.url == nil)
        #expect(sections.flatMap(\.rows).contains(where: { $0.url == "https://example.com/docs" }))
        #expect(sections.first(where: { $0.id == "benchmark-0" })?.rows.contains(where: { $0.value == "1,000" }) == true)
    }
    #expect(ModelDetails.sections(for: LeaderboardEntry(rank: 2, name: "Missing", score: 1), language: .english).isEmpty)
    #expect(try JSONDecoder().decode(LeaderboardEntry.self, from: JSONEncoder().encode(entry)) == entry)
}

@Test func appleAndWindowsMiniDetailProjectionsShareTheSameFixture() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    struct Fixture: Decodable {
        struct State: Decodable { struct Board: Decodable { let entries: [LeaderboardEntry] }; let boards: [Board] }
        let state: State
        let modelDetails: [String: [ModelDetailSection]]
    }
    let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: root.appending(path: "fixtures/visual-state.json")))
    for language in AppLanguage.allCases {
        #expect(ModelDetails.sections(for: fixture.state.boards[0].entries[0], language: language, timeZone: .gmt) == fixture.modelDetails[language.rawValue])
    }
}

@Test func modelSyncTimeUsesFullLocalCalendarAndSeconds() {
    let zone = TimeZone(identifier: "Asia/Shanghai")!
    #expect(ModelDetails.syncTime("2025-04-01T04:00:01.564Z", timeZone: zone) == "2025-04-01 12:00:01")
    #expect(ModelDetails.syncTime("2024-02-29T23:59:59-05:00", timeZone: zone) == "2024-03-01 12:59:59")
    #expect(ModelDetails.syncTime("2025-04-01T12:00:01+08:00", timeZone: .gmt) == "2025-04-01 04:00:01")
    #expect(ModelDetails.syncTime("invalid", timeZone: zone) == "invalid")
    #expect(ModelDetails.syncTime("", timeZone: zone) == "—")
}
