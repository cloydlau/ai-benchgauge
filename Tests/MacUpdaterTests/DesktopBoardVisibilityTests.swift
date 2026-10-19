import Foundation
import Testing
import LeaderboardCore
@testable import leaderboard_menu

private final class BoardVisibilityHTTP: URLProtocol, @unchecked Sendable {
    final class Log: @unchecked Sendable {
        let lock = NSLock()
        var requests: [String] = []
        var cancellations: [String] = []
        var stalled: Set<String> = []
        func reset(stalled: Set<String> = []) { lock.lock(); defer { lock.unlock() }; requests = []; cancellations = []; self.stalled = stalled }
        func record(_ kind: String) -> Bool { lock.lock(); defer { lock.unlock() }; requests.append(kind); return stalled.contains(kind) }
        func allow(_ kind: String) { lock.lock(); defer { lock.unlock() }; stalled.remove(kind) }
        func cancel(_ kind: String) { lock.lock(); defer { lock.unlock() }; cancellations.append(kind) }
        func read() -> (requests: [String], cancellations: [String]) { lock.lock(); defer { lock.unlock() }; return (requests, cancellations) }
    }
    static let log = Log()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    private var awaitingResponse = false
    override func startLoading() {
        let kind = (request.url!.lastPathComponent == "refresh" ? request.url!.deletingLastPathComponent().lastPathComponent : request.url!.lastPathComponent)
        if Self.log.record(kind) { awaitingResponse = true; return }
        let board = Leaderboard(kind: LeaderboardKind(rawValue: kind)!, title: "Synthetic board", fetchedAt: Date(),
            entries: [LeaderboardEntry(rank: 1, name: "Synthetic model", score: 100)])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try! JSONSerialization.data(withJSONObject: ["board": JSONSerialization.jsonObject(with: encoder.encode(board))])
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { guard awaitingResponse else { return }; Self.log.cancel((request.url!.lastPathComponent == "refresh" ? request.url!.deletingLastPathComponent().lastPathComponent : request.url!.lastPathComponent)) }
}

@Suite(.serialized) @MainActor
struct DesktopBoardVisibilityTests {
    private func fixture(_ saved: [String: [String]] = [:], stalled: Set<String> = []) -> (AppState, UserDefaults, URLSession) {
        BoardVisibilityHTTP.log.reset(stalled: stalled)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BoardVisibilityHTTP.self]
        let session = URLSession(configuration: configuration)
        let defaults = UserDefaults(suiteName: "board-visibility.\(UUID())")!
        defaults.set(saved, forKey: "desktopBoardSelections")
        let state = AppState(cache: LeaderboardCache(fileURL: FileManager.default.temporaryDirectory.appending(path: "\(UUID()).json")), defaults: defaults,
            fetcher: LeaderboardFetcher(session: session, sharedEndpoint: URL(string: "https://synthetic.invalid")!))
        state.applyVisualFixture(snapshot: LeaderboardSnapshot(), chips: [], language: .english, errors: [:], emptyState: nil, category: .general)
        return (state, defaults, session)
    }
    private func waitFor(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(condition(), "Timed out waiting for the selected boards")
    }
    @Test func checkboxEditsDoNotPersistOrCancelRequestsUntilConfirmed() async throws {
        let (state, defaults, session) = fixture(stalled: ["artificialAnalysis", "arenaText"])
        defer { state.beginQuitting(); session.invalidateAndCancel() }
        state.refreshNow()
        try await waitFor { BoardVisibilityHTTP.log.read().requests.count == 3 }
        let picker = BoardVisibilitySelectionView(language: .english, category: .general,
            selected: state.visibleBoardKinds, onConfirm: { state.setVisibleBoards($0) }, onCancel: {})
        picker.checkboxes[0].performClick(nil)
        picker.checkboxes[1].performClick(nil)
        #expect(state.visibleBoardKinds == LeaderboardCategory.general.boardKinds)
        #expect((defaults.dictionary(forKey: "desktopBoardSelections") ?? [:]).isEmpty)
        #expect(Set(BoardVisibilityHTTP.log.read().cancellations).isDisjoint(with: ["artificialAnalysis", "arenaText"]))
        #expect(!picker.checkboxes[2].isEnabled)
        picker.confirmButton.performClick(nil)
        try await waitFor { Set(BoardVisibilityHTTP.log.read().cancellations).isSuperset(of: ["artificialAnalysis", "arenaText"]) && !state.isRefreshing }
        #expect(state.visibleBoardKinds == [.epochECI])
        #expect(defaults.dictionary(forKey: "desktopBoardSelections") as? [String: [String]] == ["general": ["epochECI"]])
        #expect(BoardVisibilityHTTP.log.read().requests.count == 3)
    }
    @Test func cancellingOrConfirmingUnchangedSelectionDoesNotSaveOrFetch() {
        let (state, defaults, session) = fixture()
        defer { state.beginQuitting(); session.invalidateAndCancel() }
        var cancelled = false
        let picker = BoardVisibilitySelectionView(language: .english, category: .general,
            selected: state.visibleBoardKinds, onConfirm: { state.setVisibleBoards($0) }, onCancel: { cancelled = true })
        picker.checkboxes[0].performClick(nil)
        picker.cancelButton.performClick(nil)
        #expect(cancelled)
        #expect(state.visibleBoardKinds == LeaderboardCategory.general.boardKinds)
        state.setVisibleBoards(state.visibleBoardKinds)
        state.setVisibleBoards([])
        #expect((defaults.dictionary(forKey: "desktopBoardSelections") ?? [:]).isEmpty)
        #expect(BoardVisibilityHTTP.log.read().requests.isEmpty)
    }
    @Test func defaultAllSourcesFetchOnceWithPerSourceThrottling() async throws {
        let (state, _, session) = fixture()
        defer { state.beginQuitting(); session.invalidateAndCancel() }
        state.refreshNow()
        try await waitFor { !state.isRefreshing }
        #expect(Set(BoardVisibilityHTTP.log.read().requests) == Set(["artificialAnalysis", "arenaText", "epochECI"]))
        state.refreshNow()
        #expect(BoardVisibilityHTTP.log.read().requests.count == 3)
    }
    @Test func disabledBoardsAreNotFetchedAndEnablingFetchesWithoutRefreshingTheOthers() async throws {
        let (state, defaults, session) = fixture(["general": ["epochECI"]])
        defer { state.beginQuitting(); session.invalidateAndCancel() }
        state.refreshNow()
        try await waitFor { !state.isRefreshing }
        #expect(BoardVisibilityHTTP.log.read().requests == ["epochECI"])
        state.toggleBoard(.artificialAnalysis)
        try await waitFor { !state.isRefreshing }
        #expect(BoardVisibilityHTTP.log.read().requests == ["epochECI", "artificialAnalysis"])
        #expect(defaults.dictionary(forKey: "desktopBoardSelections") as? [String: [String]] == ["general": ["artificialAnalysis", "epochECI"]])
        state.toggleBoard(.artificialAnalysis)
        state.toggleBoard(.epochECI) // The last selected board stays selected.
        #expect(state.visibleBoardKinds == [.epochECI])
        #expect(BoardVisibilityHTTP.log.read().requests.count == 2)
        let restored = AppState(cache: LeaderboardCache(fileURL: URL(fileURLWithPath: "/nonexistent-fixture")), defaults: defaults)
        #expect(restored.boardKinds(for: .general) == [.epochECI])
        #expect(restored.boardKinds(for: .coding) == LeaderboardCategory.coding.boardKinds)
        restored.beginQuitting()
    }
    @Test func disablingAnInFlightBoardCancelsItsRequest() async throws {
        let (state, _, session) = fixture(["general": ["artificialAnalysis", "epochECI"]], stalled: ["artificialAnalysis"])
        defer { state.beginQuitting(); session.invalidateAndCancel() }
        state.refreshNow()
        try await waitFor { BoardVisibilityHTTP.log.read().requests.count == 2 }
        state.toggleBoard(.artificialAnalysis)
        try await waitFor { BoardVisibilityHTTP.log.read().cancellations.contains("artificialAnalysis") && !state.isRefreshing }
        #expect(state.visibleBoardKinds == [.epochECI])
        #expect(state.snapshot.boards[.artificialAnalysis] == nil)
        #expect(state.lastErrors[.artificialAnalysis] == nil)
        BoardVisibilityHTTP.log.allow("artificialAnalysis")
        state.toggleBoard(.artificialAnalysis)
        try await waitFor { !state.isRefreshing }
        #expect(state.snapshot.boards[.artificialAnalysis]?.entries.count == 1)
        #expect(BoardVisibilityHTTP.log.read().requests.count == 3)
    }
}
