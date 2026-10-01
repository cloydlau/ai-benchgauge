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
