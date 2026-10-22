import Foundation
import Testing
import LeaderboardKit

@Test func modelNameSearchFoldsCaseAccentsWidthAndWhitespaceWithoutLookingAtProviders() {
    #expect(LeaderboardPresentation.modelNameMatches("Café Ａlpha 中文模型", query: "  CAFE alpha 中文 "))
    #expect(!LeaderboardPresentation.modelNameMatches("Alpha Mini", query: "alpha pro"))
    #expect(LeaderboardPresentation.modelNameMatches("Anything", query: " \n "))
    let entries = [LeaderboardEntry(rank: 1, name: "Unrelated", score: 100, organization: "Alpha Labs"),
                   LeaderboardEntry(rank: 4, name: "Alpha Pro", score: 90, organization: "Other Labs")]
    let board = Leaderboard(kind: .arenaText, title: "Fixture", entries: entries)
    #expect(LeaderboardPresentation.rows(board, grouping: .model, filter: .all, modelQuery: "alpha").map(\.rank) == [4])
    #expect(LeaderboardPresentation.rows(board, grouping: .company, filter: .all, modelQuery: "no match").count == 2)
}
@Test func scoreSharesUseRoundedRatiosAndHideUnusableOrLeadingScores() {
    for (score, leader, expected): (Double, Double?, String) in [
        (56, 57.6, "97%"), (97.5, 100, "98%"), (0, 100, "0%"),
        (100, 100, ""), (99.6, 100, ""), (101, 100, ""), (1, 0, ""),
        (-1, 100, ""), (.nan, 100, ""), (1, .infinity, ""), (.infinity, 1, ""), (1, nil, "")
    ] {
        #expect(LeaderboardPresentation.scoreShareText(score, leaderScore: leader) == expected)
    }
}

@Test func scoreBackgroundsUseExactBoundedRatiosAndKeepInvalidBaselinesFull() {
    for (score, leader, expected): (Double, Double?, Double) in [
        (100, 100, 1), (50, 100, 0.5), (99.6, 100, 0.996), (0, 100, 0),
        (120, 100, 1), (1, 0, 1), (1, nil, 1), (-1, 100, 1),
        (.nan, 100, 1), (.infinity, 100, 1), (1, .infinity, 1), (1, .nan, 1)
    ] {
        #expect(LeaderboardPresentation.scoreFillRatio(score, leaderScore: leader) == expected)
    }
}

@Test func sourceHelpKeepsTheSameExplanationAcrossCompactAndDetailedViews() {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    for kind in LeaderboardKind.allCases {
        for language in AppLanguage.allCases {
            for board in [nil, Leaderboard(kind: kind, title: "Fixture", sourceUpdatedAt: date,
                sourceNote: "Source note", fetchedAt: date.addingTimeInterval(3600), entries: [])] {
                let compact = LeaderboardPresentation.sourceHelp(kind, language: language, board: board, includesFetchTime: false)
                let detailed = LeaderboardPresentation.sourceHelp(kind, language: language, board: board)
                #expect(compact.hasPrefix(LeaderboardPresentation.sourceSummary(kind, language: language)))
                #expect(compact.contains(language.text("Scores are not directly comparable across lists", "各榜分数不直接互比")))
                #expect(detailed == compact + language.text(". ", "。") + LeaderboardPresentation.sourceTimeHelp(board, language: language))
                #expect(compact.contains("Source note") == (board != nil))
            }
        }
    }
}

@Test func sourceAndFetchTimesRemainDistinctWhenPublicationIsMissing() {
    let utc = TimeZone(secondsFromGMT: 0)!
    let fetched = Date(timeIntervalSince1970: 1_700_000_000)
    let unknown = Leaderboard(kind: .artificialAnalysis, title: "AA", fetchedAt: fetched, entries: [])
    let labels = LeaderboardPresentation.sourceTimes(unknown, language: .chinese, timeZone: utc)
    #expect(labels.updated == "数据更新 —")
    #expect(labels.fetched == "抓取 11/14 22:13")
    #expect(LeaderboardPresentation.sourceTimeHelp(unknown, language: .chinese).contains("来源未提供"))
    let coding = Leaderboard(kind: .artificialAnalysisCodingAgent, title: "AA Coding",
        sourceUpdatedAt: fetched.addingTimeInterval(-3600), fetchedAt: fetched, entries: [])
    let known = LeaderboardPresentation.sourceTimes(coding, language: .english, timeZone: utc)
    #expect(known.updated == "Data updated 11/14 21:13")
    #expect(known.fetched == "Fetched 11/14 22:13")
    #expect(!LeaderboardPresentation.sourceTimeHelp(coding, language: .english).contains("Not published"))
    let pending = LeaderboardPresentation.sourceTimes(nil, language: .chinese, timeZone: utc)
    #expect(pending.updated == "数据更新 —")
    #expect(pending.fetched == "抓取 —")
    #expect(LeaderboardPresentation.sourceTimeHelp(nil, language: .english).contains("Waiting for first fetch"))
}

@Test func countryFilteringRetainsEveryMatchingCompany() {
    let entries = [LeaderboardEntry(rank: 1, name: "GPT", score: 100, organization: "OpenAI")]
        + (2...22).map { LeaderboardEntry(rank: $0, name: "Unknown model \($0)", score: Double(100 - $0), organization: "Unknown developer \($0)") }
    let board = Leaderboard(kind: .arenaText, title: "Fixture", entries: entries)
    let companies = LeaderboardPresentation.rows(board, grouping: .company, filter: .unknown)
    #expect(companies.count == 21)
    #expect(companies.first?.score == 98)
    #expect(LeaderboardPresentation.companies(board, filter: .unknown).map(\.entry) == companies)
    #expect(LeaderboardPresentation.countryFilters(board) == [.all, .country(.unitedStates), .unknown])
}

@Test func combinedFiltersApplyBeforeCompanyAggregationAndKeepTheSnapshotIntact() {
    let entries = [
        LeaderboardEntry(rank: 1, name: "GPT closed", score: 100, organization: "OpenAI", openness: .closed),
        LeaderboardEntry(rank: 2, name: "GPT open", score: 80, organization: "OpenAI", openness: .open),
        LeaderboardEntry(rank: 3, name: "Qwen open", score: 90, organization: "Alibaba", openness: .open),
        LeaderboardEntry(rank: 4, name: "Unknown open", score: 85, organization: "Unknown maker", openness: .open),
    ]
    let board = Leaderboard(kind: .arenaText, title: "Fixture", entries: entries)
    let models = LeaderboardPresentation.rows(board, grouping: .model, filter: .country(.unitedStates), openness: .open)
    let companies = LeaderboardPresentation.companies(board, filter: .country(.unitedStates), openness: .open)
    #expect(models.map(\.name) == ["GPT open"])
    #expect(companies.count == 1)
    #expect(companies.first?.entry.score == 80)
    #expect(companies.first?.components.map(\.name) == ["GPT open"])
    #expect(LeaderboardPresentation.rows(board, grouping: .company, filter: .country(.unitedStates), openness: .open) == companies.map(\.entry))
    #expect(LeaderboardPresentation.rows(board, grouping: .model, filter: .unknown, openness: .open).map(\.name) == ["Unknown open"])
    #expect(board.entries == entries)
}

@Test func updateLabelUsesOldestVisibleSourceAndDesktopAgeThresholds() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let left = Leaderboard(kind: .artificialAnalysis, title: "AA", fetchedAt: now.addingTimeInterval(-3600), entries: [])
    let right = Leaderboard(kind: .arenaText, title: "Arena", fetchedAt: now, entries: [])
    let snapshot = LeaderboardSnapshot(boards: [.artificialAnalysis: left, .arenaText: right])
    #expect(LeaderboardPresentation.rankingUpdated(snapshot, category: .general, language: .chinese, now: now) == "榜单 1 小时前")
    #expect(LeaderboardPresentation.rankingUpdated(snapshot, category: .image, language: .english, now: now) == "Rankings pending")
    #expect(LeaderboardPresentation.updateAge(now.addingTimeInterval(-59), language: .english, now: now) == "just now")
    #expect(LeaderboardPresentation.updateAge(now.addingTimeInterval(-60), language: .chinese, now: now) == "1 分钟前")
    #expect(LeaderboardPresentation.updateAge(now.addingTimeInterval(-86_400), language: .english, now: now) == "1 day ago")
}

@Test func rankingAgePrefersSourceTimeEvenWhenTheFetchIsNewer() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    for (sourceAge, fetchAge, expected) in [(7200.0, 0.0, "榜单 2 小时前"),
                                           (3600.0, 7200.0, "榜单 1 小时前")] {
        let board = Leaderboard(kind: .artificialAnalysis, title: "AA",
            sourceUpdatedAt: now.addingTimeInterval(-sourceAge),
            fetchedAt: now.addingTimeInterval(-fetchAge), entries: [])
        let snapshot = LeaderboardSnapshot(boards: [.artificialAnalysis: board])
        #expect(LeaderboardPresentation.rankingUpdated(snapshot, category: .general,
            language: .chinese, now: now) == expected)
    }
}

@Test func completeModelAndCompanyListsKeepTailAndFilters() {
    let entries = (1...45).map { rank in
        LeaderboardEntry(rank: rank, name: "Model \(rank)", score: Double(100 - rank),
                         organization: "Maker \(rank)", openness: rank.isMultiple(of: 2) ? .open : .closed)
    }
    let board = Leaderboard(kind: .arenaText, title: "Full", entries: entries)
    #expect(LeaderboardPresentation.rows(board, grouping: .model).count == 45)
    #expect(LeaderboardPresentation.rows(board, grouping: .model).last?.name == "Model 45")
    #expect(LeaderboardPresentation.rows(board, grouping: .company).count == 45)
    let filtered = LeaderboardPresentation.rows(board, grouping: .company, filter: .unknown, openness: .open)
    #expect(filtered.count == 22)
    #expect(filtered.last?.organization == "Maker 44")
}
