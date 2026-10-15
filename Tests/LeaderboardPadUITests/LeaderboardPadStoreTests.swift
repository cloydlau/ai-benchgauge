import Foundation
import Testing
import LeaderboardKit
import LeaderboardPadUI

private actor FetchGate {
    private var continuations: [LeaderboardKind: CheckedContinuation<Leaderboard, Never>] = [:]
    private var observer: CheckedContinuation<Void, Never>?
    func fetch(_ kind: LeaderboardKind) async -> Leaderboard {
        await withCheckedContinuation { continuation in
            continuations[kind] = continuation
            if continuations.count == 2 { observer?.resume(); observer = nil }
        }
    }
    func waitForBoth() async {
        if continuations.count < 2 { await withCheckedContinuation { observer = $0 } }
    }
    func release() {
        for (kind, continuation) in continuations {
            continuation.resume(returning: Leaderboard(kind: kind, title: "Fixture", entries: [
                LeaderboardEntry(rank: 1, name: "GPT", score: 80, organization: "OpenAI")]))
        }
        continuations.removeAll()
    }
}

@MainActor @Test func concurrentCategoryRefreshesMergeWithoutOverwriting() async throws {
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
    let first = Task { await store.refresh(force: true) }
    await gate.waitForBoth()
    // Repeated activation or pulling must not launch duplicate requests.
    await store.refresh(force: true)
    #expect(store.refreshing.count == 2)
    store.category = .image
    await store.refresh(force: true)
    await gate.release()
    await first.value
    #expect(store.snapshot.boards.count == 4)
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
    await store.refresh(force: true)
    #expect(store.snapshot.boards[.arenaText] == cached)
    #expect(store.failures[.arenaText] == .offline)
    store.category = .video
    let relaunched = LeaderboardPadStore(defaults: defaults, cache: cache, service: service)
    #expect(relaunched.category == .video)
    #expect(relaunched.grouping == .company)
    #expect(relaunched.language == .traditionalChinese)
    #expect(relaunched.country(for: .arenaText) == .china)
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
    let refresh = Task { await store.refresh(force: true) }
    let started = ContinuousClock.now
    while store.snapshot.boards[.artificialAnalysis] == nil && started.duration(to: .now) < .seconds(2) { await Task.yield() }
    #expect(store.snapshot.boards[.artificialAnalysis]?.entries.first?.name == "AA new")
    #expect(store.snapshot.boards[.arenaText] == old)
    #expect(store.refreshing.contains(.arenaText))
    #expect(cache.load()?.boards[.artificialAnalysis]?.entries.first?.name == "AA new")
    await gate.release()
    await refresh.value
    #expect(store.snapshot.boards[.arenaText]?.entries.first?.name == "Arena new")
    #expect(store.refreshing.isEmpty)
}

@MainActor @Test func sourceFiltersPersistIndependentlyOfCountryAndOtherBoards() throws {
    let name = "source-filter-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let store = LeaderboardPadStore(defaults: defaults)
    store.setOpennessFilter(.open, for: .artificialAnalysis)
    store.setOpennessFilter(.unknown, for: .arenaText)
    store.setCountryFilter(.country(.china), for: .artificialAnalysis)
    let restored = LeaderboardPadStore(defaults: defaults)
    #expect(restored.opennessFilter(for: .artificialAnalysis) == .open)
    #expect(restored.opennessFilter(for: .arenaText) == .unknown)
    #expect(restored.opennessFilter(for: .arenaTextToVideo) == .all)
    #expect(restored.countryFilter(for: .artificialAnalysis) == .country(.china))
    restored.setOpennessFilter(.all, for: .artificialAnalysis)
    #expect(defaults.string(forKey: "openness.artificialAnalysis") == nil)
    #expect(restored.countryFilter(for: .artificialAnalysis) == .country(.china))
    #expect(restored.opennessFilter(for: .arenaText) == .unknown)
}
