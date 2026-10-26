import Foundation
import Testing
import LeaderboardKit
@testable import LeaderboardPadUI

@MainActor @Test func mobileBoardSettingsPersistKeepOneAndResetWithoutChangingTheSelectedBoard() throws {
    let name = "board-settings-\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    CategoryPreference.save(.general, to: defaults)
    defaults.set(2, forKey: "mobileSelectedSource")
    let store = LeaderboardPadStore(defaults: defaults)
    #expect(store.selectedKind == .epochECI)
    store.toggleBoard(.artificialAnalysis, in: .general)
    #expect(store.selectedKind == .epochECI && store.selectedSource == 1)
    store.toggleBoard(.arenaText, in: .general)
    #expect(store.visibleBoardKinds == [.epochECI] && store.selectedSource == 0)
    store.toggleBoard(.epochECI, in: .general)
    #expect(store.visibleBoardKinds == [.epochECI])
    store.toggleBoard(.artificialAnalysisCodingAgent, in: .coding)
    #expect(store.boardKinds(for: .coding) == [.codeArenaWebDev])
    #expect(store.visibleBoardKinds == [.epochECI])
    let restored = LeaderboardPadStore(defaults: defaults)
    #expect(restored.visibleBoardKinds == [.epochECI] && restored.selectedKind == .epochECI)
    let frozen = LeaderboardPadStore(exporting: restored)
    #expect(frozen.boardSelections == restored.boardSelections)
    #expect(frozen.visibleBoardKinds == [.epochECI])
    restored.resetBoardSelections()
    #expect(restored.selectedKind == .epochECI && restored.selectedSource == 2)
    #expect(restored.visibleBoardKinds == LeaderboardCategory.general.boardKinds)
    #expect(restored.boardKinds(for: .coding) == LeaderboardCategory.coding.boardKinds)
    restored.toggleBoard(.epochECI, in: .general)
    #expect(restored.selectedKind == .arenaText && restored.selectedSource == 1)
}

@MainActor @Test func mobileBoardSettingsRepairAnEmptyOrRetiredSelectionInEveryCategory() throws {
    let name = "obsolete-board-settings-\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    defaults.set(["general": [], "coding": ["retired"]], forKey: "mobileBoardSelections")
    let store = LeaderboardPadStore(defaults: defaults)
    for category in LeaderboardCategory.allCases {
        #expect(store.boardKinds(for: category) == category.boardKinds)
    }
}

@MainActor @Test func rapidUnchangedRefreshStillSignalsTimestampPolish() async throws {
    let name = "timestamp-polish-\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let directory = FileManager.default.temporaryDirectory.appending(path: name)
    defer { try? FileManager.default.removeItem(at: directory) }
    let cache = LeaderboardCache(fileURL: directory.appending(path: "cache.json"))
    let board = Leaderboard(kind: .artificialAnalysis, title: "Unchanged", fetchedAt: Date(),
        entries: [LeaderboardEntry(rank: 1, name: "Fixture", score: 90)])
    let store = LeaderboardPadStore(defaults: defaults, cache: cache, service: LeaderboardService { _ in board })
    await store.refresh(kind: .artificialAnalysis, force: true)
    #expect(store.timestampPolishRevisions[.artificialAnalysis] == 1)
    await store.refresh(kind: .artificialAnalysis, force: true)
    #expect(store.timestampPolishRevisions[.artificialAnalysis] == 2)
    #expect(store.snapshot.boards[.artificialAnalysis] == board)
    #expect(store.refreshing.isEmpty)
}

private actor FetchGate {
    private var continuations: [LeaderboardKind: CheckedContinuation<Leaderboard, Never>] = [:]
    private var observer: CheckedContinuation<Void, Never>?
    private var expected: Set<LeaderboardKind> = []
    private(set) var requests: [LeaderboardKind] = []
    func fetch(_ kind: LeaderboardKind) async -> Leaderboard {
        requests.append(kind)
        return await withCheckedContinuation { continuation in
            continuations[kind] = continuation
            if expected.isSubset(of: Set(continuations.keys)) { observer?.resume(); observer = nil }
        }
    }
    func waitFor(_ kinds: Set<LeaderboardKind>) async {
        expected = kinds
        if !expected.isSubset(of: Set(continuations.keys)) { await withCheckedContinuation { observer = $0 } }
    }
    func release() {
        for (kind, continuation) in continuations {
            continuation.resume(returning: Leaderboard(kind: kind, title: "Fixture", entries: [
                LeaderboardEntry(rank: 1, name: "GPT", score: 80, organization: "OpenAI")]))
        }
        continuations.removeAll()
    }
}

private actor BoardRequestLog {
    private(set) var kinds: [LeaderboardKind] = []
    func fetch(_ kind: LeaderboardKind) -> Leaderboard {
        kinds.append(kind)
        return Leaderboard(kind: kind, title: "Refreshed", entries: [LeaderboardEntry(rank: 1, name: "Latest", score: 99)])
    }
}

@MainActor @Test func manualBoardRefreshRequestsOnlyItsSourceAcrossCategories() async throws {
    let name = "single-board-refresh-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let directory = FileManager.default.temporaryDirectory.appending(path: name)
    defer { try? FileManager.default.removeItem(at: directory) }
    let cache = LeaderboardCache(fileURL: directory.appending(path: "cache.json"))
    cache.save(LeaderboardSnapshot(boards: Dictionary(uniqueKeysWithValues: LeaderboardKind.allCases.map { kind in
        (kind, Leaderboard(kind: kind, title: "Saved", fetchedAt: Date(timeIntervalSince1970: 1000),
            entries: [LeaderboardEntry(rank: 1, name: "Saved model", score: 80)]))
    })))
    let log = BoardRequestLog()
    let store = LeaderboardPadStore(defaults: defaults, cache: cache, service: LeaderboardService { kind in await log.fetch(kind) })
    var expected: [LeaderboardKind] = []
    for category in LeaderboardCategory.allCases {
        store.category = category
        for (index, kind) in category.boardKinds.enumerated() {
            store.selectedSource = index
            #expect(store.selectedKind == kind)
            let before = store.snapshot.boards.filter { $0.key != kind }
            await store.refresh(kind: kind, force: true)
            expected.append(kind)
            #expect(await log.kinds == expected)
            #expect(store.snapshot.boards[kind]?.entries.first?.name == "Latest")
            #expect(store.snapshot.boards.filter { $0.key != kind } == before)
            #expect(cache.load() == store.snapshot)
            #expect(store.refreshing.isEmpty)
        }
    }
}

@MainActor @Test func sourceEntryRefreshesOnlyAnExpiredPublicationAndManualRefreshBypassesAutomaticBackoff() async throws {
    let name = "board-entry-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let directory = FileManager.default.temporaryDirectory.appending(path: name)
    defer { try? FileManager.default.removeItem(at: directory) }
    let now = Date()
    let entries = [LeaderboardEntry(rank: 1, name: "Saved", score: 80)]
    let cache = LeaderboardCache(fileURL: directory.appending(path: "cache.json"))
    cache.save(.init(boards: [
        .artificialAnalysis: Leaderboard(kind: .artificialAnalysis, title: "Fresh", fetchedAt: now, entries: entries),
        .arenaText: Leaderboard(kind: .arenaText, title: "Expired publication", sourceUpdatedAt: now.addingTimeInterval(-86400), fetchedAt: now, entries: entries),
        .epochECI: Leaderboard(kind: .epochECI, title: "Fresh publication", sourceUpdatedAt: now, fetchedAt: now.addingTimeInterval(-86400), entries: entries)
    ]))
    let log = BoardRequestLog()
    let store = LeaderboardPadStore(defaults: defaults, cache: cache, service: LeaderboardService { kind in await log.fetch(kind) })
    await store.refresh(now: now)
    #expect(await log.kinds.isEmpty)
    store.selectedSource = 1
    await store.refresh(now: now)
    #expect(await log.kinds == [.arenaText])
    await store.refresh(now: now)
    #expect(await log.kinds == [.arenaText])
    await store.refresh(force: true, now: now)
    #expect(await log.kinds == [.arenaText, .arenaText])
    store.selectedSource = 2
    await store.refresh(now: now)
    #expect(await log.kinds == [.arenaText, .arenaText])
    store.category = .video
    await store.refresh(now: now)
    #expect(await log.kinds == [.arenaText, .arenaText, .arenaTextToVideo])
    #expect(store.snapshot.boards[.artificialAnalysis]?.entries.first?.name == "Saved")
}

@MainActor @Test func mergedCountryChoicesKeepUnknownAfterLaterBoardsAndRestoredSelection() throws {
    let name = "country-menu-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let directory = FileManager.default.temporaryDirectory.appending(path: name)
    defer { try? FileManager.default.removeItem(at: directory) }
    let cache = LeaderboardCache(fileURL: directory.appending(path: "cache.json"))
    cache.save(LeaderboardSnapshot(boards: [
        .artificialAnalysis: Leaderboard(kind: .artificialAnalysis, title: "First", entries: [
            LeaderboardEntry(rank: 1, name: "Unassigned", score: 99),
            LeaderboardEntry(rank: 2, name: "DeepSeek", score: 98, organization: "DeepSeek")]),
        .arenaText: Leaderboard(kind: .arenaText, title: "Later", entries: [
            LeaderboardEntry(rank: 1, name: "GPT", score: 99, organization: "OpenAI")])
    ]))
    let store = LeaderboardPadStore(defaults: defaults, cache: cache)
    let expected: [LeaderboardCountryFilter] = [.all, .country(.china), .country(.unitedStates), .unknown]
    #expect(store.availableCountryFilters == expected)
    #expect(store.availableCountryFilters == expected) // Cached union keeps the same order.
    store.setCountry(.france, for: .arenaText)
    #expect(store.availableCountryFilters == Array(expected.dropLast()) + [.country(.france), .unknown])
    let restored = LeaderboardPadStore(defaults: defaults, cache: cache)
    #expect(restored.availableCountryFilters == store.availableCountryFilters)
    restored.setCountry(nil, for: .arenaText)
    #expect(restored.availableCountryFilters == expected)
    restored.setCountryFilter(.unknown, for: .arenaText)
    #expect(restored.availableCountryFilters == expected)
}

@MainActor @Test func aManualPullJoinsItsAutomaticBoardWhileOtherSelectionsRefreshIndependently() async throws {
    let name = "ipad-test-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let directory = FileManager.default.temporaryDirectory.appending(path: name)
    defer { try? FileManager.default.removeItem(at: directory) }
    let gate = FetchGate()
    let service = LeaderboardService { kind in
        if LeaderboardCategory.general.boardKinds.contains(kind) { return await gate.fetch(kind) }
        return Leaderboard(kind: kind, title: "Image", entries: [LeaderboardEntry(rank: 1, name: "Image", score: 99)])
    }
    let store = LeaderboardPadStore(defaults: defaults, cache: LeaderboardCache(fileURL: directory.appending(path: "cache.json")), service: service)
    store.selectedSource = 1
    let first = Task { await store.refresh() }
    await gate.waitFor([.arenaText])
    var pullFinished = false
    let pull = Task { await store.refresh(kind: .arenaText, force: true); pullFinished = true }
    await Task.yield()
    #expect(!pullFinished)
    #expect(await gate.requests == [.arenaText])
    #expect(store.refreshing == [.arenaText])
    store.category = .image
    await store.refresh(force: true)
    await gate.release()
    await first.value
    await pull.value
    #expect(pullFinished)
    #expect(store.snapshot.boards.count == 2)
    #expect(store.snapshot.boards[.arenaTextToImage]?.title == "Image")
    #expect(store.refreshing.isEmpty)
}

@MainActor @Test func preferencesAndOfflineCacheSurviveRelaunch() async throws {
    let name = "ipad-test-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let directory = FileManager.default.temporaryDirectory.appending(path: name)
    defer { try? FileManager.default.removeItem(at: directory) }
    let cache = LeaderboardCache(fileURL: directory.appending(path: "cache.json"))
    let cached = Leaderboard(kind: .arenaText, title: "Saved", entries: [LeaderboardEntry(rank: 1, name: "GPT", score: 88)])
    cache.save(LeaderboardSnapshot(boards: [.arenaText: cached]))
    let service = LeaderboardService { _ in throw URLError(.notConnectedToInternet) }
    let store = LeaderboardPadStore(defaults: defaults, cache: cache, service: service)
    store.grouping = .company
    store.language = .traditionalChinese
    store.setCountry(.china, for: .arenaText)
    store.setCountryFilter(.unknown, for: .artificialAnalysis)
    store.selectedSource = 1
    await store.refresh(force: true)
    #expect(store.snapshot.boards[.arenaText] == cached)
    #expect(store.failures[.arenaText] == .offline)
    store.category = .video
    let relaunched = LeaderboardPadStore(defaults: defaults, cache: cache, service: service)
    #expect(relaunched.category == .video)
    #expect(relaunched.grouping == .company)
    #expect(relaunched.language == .traditionalChinese)
    #expect(relaunched.countryFilter(for: .arenaText) == .unknown)
    #expect(relaunched.countryFilter(for: .artificialAnalysis) == .unknown)
    #expect(relaunched.snapshot.boards[.arenaText] == cached)
}

private actor SlowBoardSource {
    private var released = false
    private var continuation: CheckedContinuation<Void, Never>?
    func fetch(_ kind: LeaderboardKind) async -> Leaderboard {
        if !released { await withCheckedContinuation { continuation = $0 } }
        return Leaderboard(kind: kind, title: "Finished", entries: [LeaderboardEntry(rank: 1, name: "Arena new", score: 100)])
    }
    func release() { released = true; continuation?.resume(); continuation = nil }
}

private actor RecoveringBoardSource {
    private var recovered = false
    func recover() { recovered = true }
    func fetch(_ kind: LeaderboardKind) throws -> Leaderboard {
        guard recovered else { throw URLError(.timedOut) }
        return Leaderboard(kind: kind, title: "Latest", sourceUpdatedAt: Date(timeIntervalSince1970: 1_789_999_000),
            fetchedAt: Date(timeIntervalSince1970: 1_790_000_000),
            entries: [LeaderboardEntry(rank: 1, name: "Latest model", score: 99)])
    }
}

@MainActor @Test func failedAutomaticRefreshPreservesOldDataAndTimestampsUntilRecovery() async throws {
    let name = "silent-refresh-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let directory = FileManager.default.temporaryDirectory.appending(path: name)
    defer { try? FileManager.default.removeItem(at: directory) }
    let cache = LeaderboardCache(fileURL: directory.appending(path: "cache.json"))
    let old = Leaderboard(kind: .arenaText, title: "Saved", sourceUpdatedAt: Date(timeIntervalSince1970: 1000),
        fetchedAt: Date(timeIntervalSince1970: 2000), entries: [LeaderboardEntry(rank: 1, name: "Saved model", score: 88)])
    cache.save(LeaderboardSnapshot(boards: [.arenaText: old]))
    let source = RecoveringBoardSource()
    let service = LeaderboardService { kind in try await source.fetch(kind) }
    let store = LeaderboardPadStore(defaults: defaults, cache: cache, service: service)
    store.selectedSource = 1
    await store.refresh()
    #expect(store.snapshot.boards[.arenaText] == old)
    #expect(cache.load()?.boards[.arenaText] == old)
    #expect(store.refreshing.isEmpty)
    await source.recover()
    await store.refresh(now: Date().addingTimeInterval(LeaderboardFreshness.retryInterval + 1))
    #expect(store.snapshot.boards[.arenaText]?.entries.first?.name == "Latest model")
    #expect(store.snapshot.boards[.arenaText]?.fetchedAt == Date(timeIntervalSince1970: 1_790_000_000))
    #expect(cache.load() == store.snapshot)
}

@MainActor @Test func fastBoardAppearsAndPersistsWhileAnotherSourceIsStillRefreshing() async throws {
    let name = "ipad-test-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let directory = FileManager.default.temporaryDirectory.appending(path: name)
    defer { try? FileManager.default.removeItem(at: directory) }
    let cache = LeaderboardCache(fileURL: directory.appending(path: "cache.json"))
    let old = Leaderboard(kind: .arenaText, title: "Saved", fetchedAt: Date().addingTimeInterval(-3600),
        entries: [LeaderboardEntry(rank: 1, name: "Arena old", score: 80)])
    cache.save(LeaderboardSnapshot(boards: [.arenaText: old]))
    let gate = SlowBoardSource()
    let service = LeaderboardService { kind in
        if kind == .arenaText { return await gate.fetch(kind) }
        return Leaderboard(kind: kind, title: "Fast", entries: [LeaderboardEntry(rank: 1, name: "AA new", score: 99)])
    }
    let store = LeaderboardPadStore(defaults: defaults, cache: cache, service: service)
    let refresh = Task { await store.refresh(kind: .arenaText, force: true) }
    let started = ContinuousClock.now
    while !store.refreshing.contains(.arenaText) && started.duration(to: .now) < .seconds(2) { await Task.yield() }
    await store.refresh(kind: .artificialAnalysis, force: true)
    #expect(store.snapshot.boards[.artificialAnalysis]?.entries.first?.name == "AA new")
    #expect(store.snapshot.boards[.arenaText] == old)
    #expect(store.refreshing.contains(.arenaText))
    #expect(cache.load()?.boards[.artificialAnalysis]?.entries.first?.name == "AA new")
    await gate.release()
    await refresh.value
    #expect(store.snapshot.boards[.arenaText]?.entries.first?.name == "Arena new")
    #expect(store.refreshing.isEmpty)
}

@MainActor @Test func sourceFiltersAreSharedAcrossCategoriesAndPersistIndependentlyOfCountry() throws {
    let name = "source-filter-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let store = LeaderboardPadStore(defaults: defaults)
    store.setOpennessFilter(.open, for: .artificialAnalysis)
    store.setOpennessFilter(.unknown, for: .arenaText)
    store.setCountryFilter(.country(.china), for: .artificialAnalysis)
    let restored = LeaderboardPadStore(defaults: defaults)
    #expect(restored.opennessFilter(for: .artificialAnalysis) == .unknown)
    #expect(restored.opennessFilter(for: .arenaText) == .unknown)
    #expect(restored.opennessFilter(for: .arenaTextToVideo) == .unknown)
    #expect(restored.countryFilter(for: .artificialAnalysis) == .country(.china))
    restored.setOpennessFilter(.all, for: .artificialAnalysis)
    #expect(defaults.string(forKey: "openness.artificialAnalysis") == nil)
    #expect(restored.countryFilter(for: .artificialAnalysis) == .country(.china))
    #expect(restored.opennessFilter(for: .arenaText) == .all)
    for kind in LeaderboardKind.allCases {
        #expect(restored.countryFilter(for: kind) == .country(.china))
        #expect(restored.opennessFilter(for: kind) == .all)
    }
    restored.setCountryFilter(.all, for: .arenaTextToVideo)
    let cleared = LeaderboardPadStore(defaults: defaults)
    #expect(LeaderboardKind.allCases.allSatisfy { cleared.countryFilter(for: $0) == .all })
}

@MainActor @Test func legacyFiltersMigrateFromTheVisibleCategoryAndClearedGlobalFiltersWin() throws {
    let name = "mobile-migration-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    CategoryPreference.save(.video, to: defaults)
    defaults.set("CN", forKey: "country.artificialAnalysisTextToVideo")
    defaults.set("open", forKey: "openness.arenaTextToVideo")
    defaults.set(1, forKey: "mobileSelectedSource")
    let store = LeaderboardPadStore(defaults: defaults)
    #expect(store.selectedSource == 1)
    #expect(LeaderboardKind.allCases.allSatisfy { store.countryFilter(for: $0) == .country(.china) && store.opennessFilter(for: $0) == .open })
    store.category = .image
    let moved = LeaderboardPadStore(defaults: defaults)
    #expect(moved.countryFilter(for: .arenaTextToImage) == .country(.china))
    #expect(moved.opennessFilter(for: .arenaTextToImage) == .open)
    let frozen = LeaderboardPadStore(exporting: store)
    store.setCountryFilter(.all, for: .arenaText)
    store.setOpennessFilter(.all, for: .arenaText)
    #expect(frozen.countryFilter(for: .arenaText) == .country(.china))
    #expect(frozen.opennessFilter(for: .arenaText) == .open)
    defaults.set("CN", forKey: "country.artificialAnalysisTextToVideo")
    let restored = LeaderboardPadStore(defaults: defaults)
    #expect(LeaderboardKind.allCases.allSatisfy { restored.countryFilter(for: $0) == .all && restored.opennessFilter(for: $0) == .all })
}
