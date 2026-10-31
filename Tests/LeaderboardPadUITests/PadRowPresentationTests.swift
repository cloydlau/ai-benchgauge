import Foundation
import Testing
import LeaderboardKit
@testable import LeaderboardPadUI

@MainActor @Test func usageWidthIncludesPrecisionAndTokenUnitInBothGroupings() {
    let board = Leaderboard(kind: .openRouterUsage, title: "OpenRouter", entries: [
        LeaderboardEntry(rank: 1, name: "openai/a", score: 123.456, organization: "OpenAI", totalTokens: "123456000000"),
        LeaderboardEntry(rank: 2, name: "openai/b", score: 23.21, organization: "OpenAI", totalTokens: "23210000000")
    ])
    for grouping in LeaderboardGrouping.allCases {
        let presentation = PadRowPresentation(board: board, grouping: grouping, country: .all, openness: .all, language: .english)
        #expect(presentation.scoreWidthReference == (grouping == .model ? "123.46B" : "146.67B"))
        #expect(presentation.page(0..<1).scoreWidthReference == presentation.scoreWidthReference)
    }
}

@MainActor @Test func groupingSearchesKeepIndependentQueriesAcrossBoardsCategoriesAndExports() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let cache = LeaderboardCache(fileURL: directory.appending(path: "boards.json"))
    let entries = [
        LeaderboardEntry(rank: 1, name: "Leader", score: 100, organization: "Alpha Labs", openness: .closed),
        LeaderboardEntry(rank: 2, name: "Alpha Pro", score: 80, organization: "Maker One", openness: .open),
        LeaderboardEntry(rank: 3, name: "Alpha Mini", score: 70, organization: "Maker Two", openness: .closed),
    ]
    cache.save(LeaderboardSnapshot(boards: Dictionary(uniqueKeysWithValues: LeaderboardKind.allCases.map {
        ($0, Leaderboard(kind: $0, title: "Fixture", entries: entries))
    })))
    let suite = UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = LeaderboardPadStore(defaults: defaults, cache: cache)
    let initial = store.rowPresentation(for: .artificialAnalysis)
    store.modelSearchQuery = " ALPHA pro "
    store.modelSearchPresented = true
    for kind in LeaderboardKind.allCases {
        let rows = store.rowPresentation(for: kind)
        #expect(rows.rows.map(\.rank) == [2])
        #expect(rows.leaderScore == 100)
        #expect(rows.page(0..<1).leaderScore == 100)
        #expect(LeaderboardPresentation.scoreShareText(rows.rows[0].score, leaderScore: rows.leaderScore) == "80%")
    }
    #expect(initial !== store.rowPresentation(for: .artificialAnalysis))
    let searched = store.rowPresentation(for: .arenaText)
    store.selectedSource = 1
    store.category = .coding
    #expect(store.modelSearchQuery == " ALPHA pro ")
    #expect(store.modelSearchPresented)
    #expect(searched === store.rowPresentation(for: .arenaText))
    store.grouping = .company
    #expect(store.rowPresentation(for: .arenaText).rows.count == 3)
    #expect(store.modelSearchQuery.isEmpty)
    store.modelSearchQuery = "maker ONE"
    let companies = store.rowPresentation(for: .arenaText)
    #expect(companies.rows.map(\.name) == ["Maker One"])
    #expect(companies.rows.map(\.rank) == [2])
    #expect(companies.leaderScore == 100)
    let frozen = LeaderboardPadStore(exporting: store)
    #expect(frozen.rowPresentation(for: .arenaText).rows.map(\.name) == ["Maker One"])
    #expect(frozen.modelSearchQuery == "maker ONE")
    store.grouping = .model
    #expect(store.rowPresentation(for: .arenaText).rows.map(\.rank) == [2])
    store.modelSearchQuery = "Alpha"
    store.setOpennessFilter(.closed, for: .arenaText)
    #expect(store.rowPresentation(for: .arenaText).rows.map(\.rank) == [3])
    store.modelSearchQuery = "Maker"
    #expect(store.rowPresentation(for: .arenaText).rows.isEmpty)
    store.modelSearchQuery = ""
    #expect(store.rowPresentation(for: .arenaText).rows.map(\.rank) == [1, 3])
    store.grouping = .company
    #expect(store.modelSearchQuery == "maker ONE")
    #expect(store.rowPresentation(for: .arenaText).rows.isEmpty)
    store.setOpennessFilter(.all, for: .arenaText)
    #expect(store.rowPresentation(for: .arenaText).rows.map(\.name) == ["Maker One"])
    store.clearSearchQueries()
    #expect(store.modelSearchQuery.isEmpty)
    store.grouping = .model
    #expect(store.modelSearchQuery.isEmpty)
    #expect(store.rowPresentation(for: .arenaText).rows.count == 3)
    let relaunched = LeaderboardPadStore(defaults: defaults, cache: cache)
    #expect(relaunched.modelSearchQuery.isEmpty)

}

@MainActor @Test func longBoardPresentationIsReusedUntilDataOrFiltersChange() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let cache = LeaderboardCache(fileURL: directory.appending(path: "boards.json"))
    let entries = (1...5000).map { rank in
        LeaderboardEntry(rank: rank, name: "Model \(rank)", score: Double(10000 - rank),
            organization: "Maker \(rank)", openness: rank.isMultiple(of: 2) ? .open : .closed)
    }
    cache.save(LeaderboardSnapshot(boards: [.arenaText: Leaderboard(kind: .arenaText, title: "Fixture", entries: entries)]))
    let name = UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let store = LeaderboardPadStore(defaults: defaults, cache: cache)
    let first = store.rowPresentation(for: .arenaText)
    #expect(first.rows.count == 5000)
    #expect(first.rows.last?.rank == 5000)
    let page = first.page(480..<504)
    #expect(page.rows.count == 24)
    #expect(page.rows.first?.rank == 481)
    #expect(page.rows.last?.rank == 504)
    #expect(page.scoreWidthReference == first.scoreWidthReference)
    #expect(first.page(5000..<5024).rows.isEmpty)
    let ranges = LeaderboardPadView(store: store).screenshotPageRanges()
    #expect(ranges.count == 209)
    #expect(ranges.flatMap(Array.init) == Array(0..<5000))
    #expect(first === store.rowPresentation(for: .arenaText))
    store.appearance = "dark"
    #expect(first === store.rowPresentation(for: .arenaText))
    store.setOpennessFilter(.open, for: .arenaText)
    let filtered = store.rowPresentation(for: .arenaText)
    #expect(filtered !== first)
    #expect(filtered.rows.count == 2500)
    #expect(filtered.rows.last?.rank == 5000)
    store.grouping = .company
    let company = store.rowPresentation(for: .arenaText)
    #expect(company.rows.count == 2500)
    #expect(company.rows.last?.name == "Maker 5000")
    store.language = .english
    #expect(company !== store.rowPresentation(for: .arenaText))
    store.setCountryFilter(.country(.unitedStates), for: .arenaText)
    #expect(store.rowPresentation(for: .arenaText).rows.isEmpty)
}

@MainActor @Test func priceColumnReservesLabelsAndTheLargerOutputAmount() {
    let board = Leaderboard(kind: .openRouterUsage, title: "OpenRouter", entries: [
        LeaderboardEntry(rank: 1, name: "A", score: 10, organization: "Alpha", taskCostUSD: 0, outputPriceUSD: 123.45)
    ])
    for language in AppLanguage.allCases {
        for grouping in LeaderboardGrouping.allCases {
            let presentation = PadRowPresentation(board: board, grouping: grouping, country: .all, openness: .all, language: language, costOrder: true)
            #expect(presentation.scoreWidthReference == LeaderboardPresentation.tokenPriceLine(123.45, output: true, language: language))
            #expect(presentation.page(0..<1).scoreWidthReference == presentation.scoreWidthReference)
            #expect(presentation.rows.first?.rank == 1)
        }
    }
}
