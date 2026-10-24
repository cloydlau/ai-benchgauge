import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import LeaderboardCore
@testable import benchgauge_engine

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
    override func startLoading() {
        let kind = (request.url!.lastPathComponent == "refresh" ? request.url!.deletingLastPathComponent().lastPathComponent : request.url!.lastPathComponent)
        if Self.log.record(kind) { return }
        let board = Leaderboard(kind: LeaderboardKind(rawValue: kind)!, title: "Synthetic board", fetchedAt: Date(),
            entries: [LeaderboardEntry(rank: 1, name: "Synthetic model", score: 100)])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try! JSONSerialization.data(withJSONObject: ["board": JSONSerialization.jsonObject(with: encoder.encode(board))])
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { Self.log.cancel((request.url!.lastPathComponent == "refresh" ? request.url!.deletingLastPathComponent().lastPathComponent : request.url!.lastPathComponent)) }
}

@Suite(.serialized)
struct DesktopBridgeBoardTests {
    private func waitFor(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(condition())
    }
    @Test func boardEntryUsesPublicationAgeAndManualRefreshBypassesAutomaticBackoff() async throws {
        BoardVisibilityHTTP.log.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BoardVisibilityHTTP.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let file = FileManager.default.temporaryDirectory.appending(path: "bridge-age-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let now = Date()
        let entries = [LeaderboardEntry(rank: 1, name: "Saved", score: 90)]
        LeaderboardCache(fileURL: file).save(.init(boards: [
            .artificialAnalysis: Leaderboard(kind: .artificialAnalysis, title: "Fresh", fetchedAt: now, entries: entries),
            .arenaText: Leaderboard(kind: .arenaText, title: "Expired", sourceUpdatedAt: now.addingTimeInterval(-86401), fetchedAt: now, entries: entries),
            .epochECI: Leaderboard(kind: .epochECI, title: "Fresh publication", sourceUpdatedAt: now, fetchedAt: now.addingTimeInterval(-86400), entries: entries)
        ]))
        let engine = try Engine(cacheFile: file, fetcher: LeaderboardFetcher(session: session, sharedEndpoint: URL(string: "https://synthetic.invalid")!))
        _ = await engine.handle(Request(id: 1, command: "refreshBoardsIfStale"))
        #expect(BoardVisibilityHTTP.log.read().requests == ["arenaText"])
        _ = await engine.handle(Request(id: 2, command: "refreshBoardsIfStale"))
        #expect(BoardVisibilityHTTP.log.read().requests == ["arenaText"])
        _ = await engine.handle(Request(id: 3, command: "refreshBoards", boards: ["arenaText"]))
        #expect(BoardVisibilityHTTP.log.read().requests == ["arenaText", "arenaText"])
    }

    @Test func manualRefreshJoinsAnAutomaticRequestInsteadOfStartingAnother() async throws {
        BoardVisibilityHTTP.log.reset(stalled: ["epochECI"])
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BoardVisibilityHTTP.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let file = FileManager.default.temporaryDirectory.appending(path: "bridge-join-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let engine = try Engine(cacheFile: file, fetcher: LeaderboardFetcher(session: session, sharedEndpoint: URL(string: "https://synthetic.invalid")!))
        let automatic = Task { await engine.handle(Request(id: 1, command: "refreshBoardsIfStale", boards: ["epochECI"])) }
        try await waitFor { BoardVisibilityHTTP.log.read().requests == ["epochECI"] }
        let manual = Task { await engine.handle(Request(id: 2, command: "refreshBoards", boards: ["epochECI"])) }
        await Task.yield()
        #expect(BoardVisibilityHTTP.log.read().requests == ["epochECI"])
        _ = await engine.handle(Request(id: 3, command: "state", boards: ["artificialAnalysis"]))
        _ = await automatic.value
        _ = await manual.value
        #expect(BoardVisibilityHTTP.log.read().requests == ["epochECI"])
    }

    @Test func bridgeProjectsAndFetchesOnlySelectedBoardsIncludingCacheReads() async throws {
        BoardVisibilityHTTP.log.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BoardVisibilityHTTP.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let file = FileManager.default.temporaryDirectory.appending(path: "bridge-visibility-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let engine = try Engine(cacheFile: file, fetcher: LeaderboardFetcher(session: session, sharedEndpoint: URL(string: "https://synthetic.invalid")!))
        let one = await engine.handle(Request(id: 1, command: "refreshBoardsIfStale", boards: ["epochECI"]))
        #expect(one.result?.boards.map(\.kind) == ["epochECI"])
        #expect(BoardVisibilityHTTP.log.read().requests == ["epochECI"])
        let two = await engine.handle(Request(id: 2, command: "refreshBoardsIfStale", boards: ["artificialAnalysis", "epochECI"]))
        #expect(two.result?.boards.map(\.kind) == ["artificialAnalysis", "epochECI"])
        #expect(BoardVisibilityHTTP.log.read().requests == ["epochECI", "artificialAnalysis"])
        _ = await engine.handle(Request(id: 3, command: "refreshBoardsIfStale", boards: ["artificialAnalysis", "epochECI"]))
        #expect(BoardVisibilityHTTP.log.read().requests.count == 2)
        _ = await engine.handle(Request(id: 1, command: "refreshBoardsIfStale")) // An older queued request cannot re-enable Arena.
        #expect(BoardVisibilityHTTP.log.read().requests.count == 2)
        _ = await engine.handle(Request(id: 4, command: "cachedBoards", boards: ["epochECI"]))
        #expect(BoardVisibilityHTTP.log.read().requests == ["epochECI", "artificialAnalysis", "epochECI"])
        let defaults = await engine.handle(Request(id: 5, command: "state"))
        #expect(defaults.result?.boards.map(\.kind) == ["artificialAnalysis", "arenaText", "epochECI"])
        let invalid = await engine.handle(Request(id: 6, command: "state", boards: []))
        #expect(invalid.result?.boards.count == 3)
        let company = await engine.handle(Request(id: 7, command: "state", grouping: "company", boards: ["artificialAnalysis"], sources: ["artificialAnalysis": "open"], countries: ["artificialAnalysis": "china"]))
        #expect(company.result?.boards.first?.entries.isEmpty == true)
        #expect(company.result?.boards.first?.distribution?.total == 1)
        #expect(company.result?.boards.first?.distribution?.sources.last?.count == 1)
    }
    @Test func aNewSelectionCancelsTheDisabledBridgeRequest() async throws {
        BoardVisibilityHTTP.log.reset(stalled: ["artificialAnalysis"])
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BoardVisibilityHTTP.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let file = FileManager.default.temporaryDirectory.appending(path: "bridge-cancel-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let engine = try Engine(cacheFile: file, fetcher: LeaderboardFetcher(session: session, sharedEndpoint: URL(string: "https://synthetic.invalid")!))
        let refreshing = Task { await engine.handle(Request(id: 1, command: "refreshBoardsIfStale", boards: ["artificialAnalysis", "epochECI"])) }
        try await waitFor { BoardVisibilityHTTP.log.read().requests.count == 2 }
        let selected = await engine.handle(Request(id: 2, command: "state", boards: ["epochECI"]))
        #expect(selected.result?.boards.map(\.kind) == ["epochECI"])
        _ = await refreshing.value
        try await waitFor { BoardVisibilityHTTP.log.read().cancellations.contains("artificialAnalysis") }
        BoardVisibilityHTTP.log.allow("artificialAnalysis")
        _ = await engine.handle(Request(id: 3, command: "refreshBoardsIfStale", boards: ["artificialAnalysis", "epochECI"]))
        #expect(BoardVisibilityHTTP.log.read().requests.count == 3)
    }
    @Test func changingSelectionAlsoCancelsTheSharedCacheRead() async throws {
        BoardVisibilityHTTP.log.reset(stalled: ["artificialAnalysis"])
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BoardVisibilityHTTP.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let file = FileManager.default.temporaryDirectory.appending(path: "bridge-cache-cancel-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let engine = try Engine(cacheFile: file, fetcher: LeaderboardFetcher(session: session, sharedEndpoint: URL(string: "https://synthetic.invalid")!))
        let reading = Task { await engine.handle(Request(id: 1, command: "cachedBoards", boards: ["artificialAnalysis", "epochECI"])) }
        try await waitFor { BoardVisibilityHTTP.log.read().requests.count == 2 }
        _ = await engine.handle(Request(id: 2, command: "state", boards: ["epochECI"]))
        _ = await reading.value
        try await waitFor { BoardVisibilityHTTP.log.read().cancellations.contains("artificialAnalysis") }
        #expect(BoardVisibilityHTTP.log.read().requests.count == 2)
    }

}
