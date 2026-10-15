import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import LeaderboardKit

private final class SharedHTTPStub: URLProtocol, @unchecked Sendable {
    final class Routes: @unchecked Sendable {
        let lock = NSLock()
        var handlers: [String: @Sendable (URLRequest) throws -> (Int, Data)] = [:]
        var requests: [String: [URLRequest]] = [:]
        func install(_ id: String, handler: @escaping @Sendable (URLRequest) throws -> (Int, Data)) {
            lock.lock(); defer { lock.unlock() }; handlers[id] = handler; requests[id] = []
        }
        func response(_ request: URLRequest) throws -> (Int, Data) {
            let id = request.value(forHTTPHeaderField: "X-Test-Route") ?? ""
            lock.lock(); let handler = handlers[id]; requests[id, default: []].append(request); lock.unlock()
            guard let handler else { throw URLError(.unsupportedURL) }
            return try handler(request)
        }
        func recorded(_ id: String) -> [URLRequest] {
            lock.lock(); defer { lock.unlock() }; return requests[id] ?? []
        }
        func remove(_ id: String) { lock.lock(); defer { lock.unlock() }; handlers[id] = nil; requests[id] = nil }
    }
    static let routes = Routes()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.routes.response(request)
            if status == 0 { return } // Deliberately stalled origin; cancellation must stop it.
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

private func responseJSON(_ value: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: value) }
private func sharedBoard(date: String = "2026-09-01T00:00:00.000Z", kind: String = "arenaText") -> [String: Any] {
    ["kind": kind, "title": "Arena | Text", "fetchedAt": date,
     "entries": [["rank": 1, "name": "GPT", "score": 100, "organization": "OpenAI"]]]
}
private func withSharedStub<T>(contributionTimeout: TimeInterval = 30, handler: @escaping @Sendable (URLRequest) throws -> (Int, Data),
                              operation: (LeaderboardFetcher, String) async throws -> T) async throws -> T {
    let id = UUID().uuidString
    SharedHTTPStub.routes.install(id, handler: handler)
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [SharedHTTPStub.self]
    config.httpAdditionalHeaders = ["X-Test-Route": id]
    let session = URLSession(configuration: config)
    defer { session.invalidateAndCancel(); SharedHTTPStub.routes.remove(id) }
    return try await operation(LeaderboardFetcher(session: session, sharedEndpoint: URL(string: "https://shared.example")!, contributionTimeout: contributionTimeout), id)
}

@Test func sharedCachePreservesOldDateAndNeverContactsOriginWithoutGrant() async throws {
    try await withSharedStub(handler: { request in
        #expect(request.url?.host == "shared.example")
        return (200, try responseJSON(["board": sharedBoard()]))
    }) { fetcher, id in
        let board = try await fetcher.fetch(.arenaText)
        #expect(board.fetchedAt.timeIntervalSince1970 == 1_788_220_800)
        #expect(SharedHTTPStub.routes.recorded(id).count == 1)
    }
}

@Test func brokenRefreshCoordinationFallsBackToSharedReadAndNeverBypassesGate() async throws {
    try await withSharedStub(handler: { request in
        #expect(request.url?.host == "shared.example")
        return request.httpMethod == "POST" ? (503, Data()) : (200, try responseJSON(["board": sharedBoard()]))
    }) { fetcher, id in
        let board = try await fetcher.fetch(.arenaText)
        #expect(board.entries.first?.name == "GPT")
        #expect(SharedHTTPStub.routes.recorded(id).count == 2)
    }
}

@Test func failedOriginKeepsSharedSnapshotAndDoesNotAttemptAnotherOriginRequest() async throws {
    try await withSharedStub(handler: { request in
        if request.url?.host == "arena.ai" { throw URLError(.cannotConnectToHost) }
        let grant: [String: Any] = ["token": String(repeating: "A", count: 43),
            "expiresAt": (Date().timeIntervalSince1970 + 90) * 1000, "sourceURL": LeaderboardKind.arenaText.sourceURL.absoluteString]
        return (200, try responseJSON(["board": sharedBoard(), "grant": grant]))
    }) { fetcher, id in
        let board = try await fetcher.fetch(.arenaText)
        #expect(board.entries.first?.name == "GPT")
        #expect(SharedHTTPStub.routes.recorded(id).filter { $0.url?.host == "arena.ai" }.count == 1)
    }
}

@Test func wrongSourceOrExpiredGrantCannotSendAnOriginRequest() async throws {
    for invalidURL in ["https://attacker.invalid", LeaderboardKind.arenaText.sourceURL.absoluteString] {
        try await withSharedStub(handler: { request in
            #expect(request.url?.host == "shared.example")
            let grant: [String: Any] = ["token": String(repeating: "A", count: 43),
                "expiresAt": (Date().timeIntervalSince1970 + (invalidURL.contains("attacker") ? 90 : -1)) * 1000, "sourceURL": invalidURL]
            return (200, try responseJSON(["board": sharedBoard(), "grant": grant]))
        }) { fetcher, _ in
            let board = try await fetcher.fetch(.arenaText)
            #expect(board.kind == .arenaText)
        }
    }
}

@Test func successfulContributorUploadsSourceHTMLAndUsesAcceptedServerTimestamp() async throws {
    try await withSharedStub(handler: { request in
        if request.url?.host == "arena.ai" {
            let rows = (1...22).map { ["modelDisplayName": "Model \($0)", "rating": 2000 - $0] as [String: Any] }
            let payload = String(decoding: try JSONSerialization.data(withJSONObject: rows), as: UTF8.self)
            let escaped = String(decoding: try JSONSerialization.data(withJSONObject: [payload]), as: UTF8.self).dropFirst().dropLast()
            return (200, Data("<script>self.__next_f.push([1,\(escaped)])</script>".utf8))
        }
        if request.url?.path.hasSuffix("contribute") == true {
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "text/html; charset=utf-8")
            #expect(request.value(forHTTPHeaderField: "X-BenchGauge-Grant") == String(repeating: "A", count: 43))
            return (200, try responseJSON(["board": sharedBoard(date: "2026-10-11T00:00:00.000Z")]))
        }
        let grant: [String: Any] = ["token": String(repeating: "A", count: 43),
            "expiresAt": (Date().timeIntervalSince1970 + 90) * 1000, "sourceURL": LeaderboardKind.arenaText.sourceURL.absoluteString]
        return (200, try responseJSON(["board": sharedBoard(), "grant": grant]))
    }) { fetcher, id in
        let board = try await fetcher.fetch(.arenaText)
        #expect(board.fetchedAt.timeIntervalSince1970 == 1_791_676_800)
        #expect(SharedHTTPStub.routes.recorded(id).count == 3)
    }
}

@Test func invalidSharedBoardDoesNotReplaceTheLocalFallback() async throws {
    try await withSharedStub(handler: { _ in (200, try responseJSON(["board": sharedBoard(kind: "artificialAnalysis")])) }) { fetcher, _ in
        await #expect(throws: (any Error).self) { try await fetcher.fetch(.arenaText) }
    }
}

private actor CachedBoardRecorder {
    var boards: [Leaderboard] = []
    func record(_ board: Leaderboard) { boards.append(board) }
}

@Test func cachedBoardIsPublishedBeforeSlowOriginAndTimeoutKeepsIt() async throws {
    let recorder = CachedBoardRecorder()
    try await withSharedStub(contributionTimeout: 0.5, handler: { request in
        if request.url?.host == "arena.ai" {
            #expect(request.timeoutInterval == 20)
            return (0, Data())
        }
        let grant: [String: Any] = ["token": String(repeating: "A", count: 43),
            "expiresAt": (Date().timeIntervalSince1970 + 90) * 1000, "sourceURL": LeaderboardKind.arenaText.sourceURL.absoluteString]
        return (200, try responseJSON(["board": sharedBoard(), "grant": grant]))
    }) { fetcher, id in
        let started = ContinuousClock.now
        let board = try await fetcher.fetch(.arenaText, onCachedBoard: { cached in
            // FC's snapshot reaches the view before any origin request starts.
            #expect(SharedHTTPStub.routes.recorded(id).count == 1)
            await recorder.record(cached)
        })
        #expect(started.duration(to: .now) < .seconds(2))
        #expect(board.fetchedAt.timeIntervalSince1970 == 1_788_220_800)
        #expect(await recorder.boards == [board])
        let requests = SharedHTTPStub.routes.recorded(id)
        #expect(requests.filter { $0.url?.host == "arena.ai" }.count == 1)
        #expect(!requests.contains { $0.url?.path.hasSuffix("contribute") == true })
    }
}

@Test func sharedCacheReadNeverClaimsARefreshGrantOrContactsOrigin() async throws {
    try await withSharedStub(handler: { request in
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/v1/boards/arenaText")
        #expect(request.timeoutInterval == 10)
        return (200, try responseJSON(["board": sharedBoard()]))
    }) { fetcher, id in
        let board = try await fetcher.fetchCached(.arenaText)
        #expect(board?.kind == .arenaText)
        #expect(SharedHTTPStub.routes.recorded(id).count == 1)
    }
}

@Test func sharedBrandPNGArrivesWithSnapshotWithoutAnotherImageRequest() async throws {
    let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAMAAACdt4HsAAAAA1BMVEUxn6isBw9yAAAACXBIWXMAAAsTAAALEwEAmpwYAAAAG0lEQVRYw+3BgQAAAADDoPlT3+AEVQEAAAB8AxBAAAEZszF2AAAAAElFTkSuQmCC")!
    try await withSharedStub(handler: { request in
        #expect(request.httpMethod == "GET")
        var board = sharedBoard()
        board["entries"] = [["rank": 1, "name": "New Model", "score": 99, "organization": "New Maker",
                            "brand": ["key": "newmaker", "colorHex": "#319FA8", "pngData": png.base64EncodedString(), "status": "ready"]]]
        return (200, try responseJSON(["board": board]))
    }) { fetcher, id in
        let board = try await fetcher.fetchCached(.arenaText)
        #expect(board?.entries.first?.brand?.validPNGData == png)
        #expect(board?.entries.first?.brand?.colorHex == "#319FA8")
        #expect(SharedHTTPStub.routes.recorded(id).count == 1)
    }
}


@Test func directSourcesAndServiceUseOnlyTheInjectedSession() async throws {
    try await withSharedStub(handler: { request in
        #expect(request.value(forHTTPHeaderField: "Accept") == "text/html")
        return (200, Data("<html>invalid fixture</html>".utf8))
    }) { original, _ in
        let fetcher = LeaderboardFetcher(session: original.session, sharedEndpoint: nil)
        let cached = try await fetcher.fetchCached(.arenaText)
        #expect(cached == nil)
        for kind in LeaderboardKind.allCases {
            await #expect(throws: (any Error).self) { try await fetcher.fetch(kind) }
        }
        let service = LeaderboardService(fetcher: fetcher)
        let result = await service.refresh([.arenaText], keeping: .init())
        #expect(result.failures[.arenaText] == .sourceUnavailable)
    }
    try await withSharedStub(handler: { _ in (503, Data()) }) { original, _ in
        await #expect(throws: URLError(.badServerResponse)) { try await LeaderboardFetcher(session: original.session, sharedEndpoint: nil).fetch(.arenaText) }
    }
}

@Test func sharedReadRejectsInvalidDatesOversizedDocumentsAndInvalidEntries() async throws {
    for mode in ["date", "large", "rank", "name", "score", "future", "empty"] {
        try await withSharedStub(handler: { _ in
            var board = sharedBoard()
            switch mode {
            case "date": board["fetchedAt"] = "invalid"
            case "large": return (200, Data(repeating: 32, count: 16_000_001))
            case "rank": board["entries"] = [["rank": 0, "name": "fixture", "score": 1]]
            case "name": board["entries"] = [["rank": 1, "name": "", "score": 1]]
            case "score": board["entries"] = [["rank": 1, "name": "fixture", "score": "invalid"]]
            case "future": board["fetchedAt"] = "2099-01-01T00:00:00Z"
            default: board["entries"] = []
            }
            return (200, try responseJSON(["board": board]))
        }) { fetcher, _ in
            await #expect(throws: (any Error).self) { try await fetcher.fetchCached(.arenaText) }
        }
    }
}

@Test func anEmptySeedIsPolledWithoutContactingOriginAndContributorErrorsRemainErrors() async throws {
    try await withSharedStub(handler: { request in
        #expect(request.url?.host == "shared.example")
        return request.httpMethod == "POST" ? (200, Data("{}".utf8)) : (200, try responseJSON(["board": sharedBoard()]))
    }) { fetcher, _ in
        let board = try await fetcher.fetch(.arenaText)
        #expect(board.kind == .arenaText)
    }
    try await withSharedStub(handler: { request in
        #expect(request.url?.host == "shared.example")
        return (200, Data("{}".utf8))
    }) { fetcher, _ in
        await #expect(throws: URLError(.resourceUnavailable)) { try await fetcher.fetch(.arenaText) }
    }
    try await withSharedStub(handler: { request in
        if request.httpMethod == "GET" { return (503, Data()) }
        let grant: [String: Any] = ["token": "invalid", "expiresAt": (Date().timeIntervalSince1970 + 60) * 1000, "sourceURL": LeaderboardKind.arenaText.sourceURL.absoluteString]
        return (200, try responseJSON(["grant": grant]))
    }) { fetcher, _ in
        await #expect(throws: URLError(.badServerResponse)) { try await fetcher.fetch(.arenaText) }
    }
}

@Test func cancellationDuringRefreshAndContributionNeverFallsBackToAnotherAccountOrSource() async throws {
    try await withSharedStub(handler: { _ in (0, Data()) }) { fetcher, _ in
        let task = Task { try await fetcher.fetch(.arenaText) }
        try await Task.sleep(for: .milliseconds(20)); task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}

@Test func contributionFailureUsesACommittedReadAndNeverPublishesAnInvalidAcceptance() async throws {
    for mode in ["committed-read", "expired", "invalid-acceptance"] {
        try await withSharedStub(handler: { request in
            if request.url?.host == "arena.ai" {
                if mode == "committed-read" { throw URLError(.cannotConnectToHost) }
                if mode == "expired" { Thread.sleep(forTimeInterval: 1.1) }
                let rows = (1...22).map { ["modelDisplayName": "Model \($0)", "rating": 2000 - $0] as [String: Any] }
                let payload = String(decoding: try JSONSerialization.data(withJSONObject: rows), as: UTF8.self)
                let escaped = String(decoding: try JSONSerialization.data(withJSONObject: [payload]), as: UTF8.self).dropFirst().dropLast()
                return (200, Data("<script>self.__next_f.push([1,\(escaped)])</script>".utf8))
            }
            if request.httpMethod == "GET" { return (200, try responseJSON(["board": sharedBoard()])) }
            if request.url?.path.hasSuffix("contribute") == true { return (200, Data("{}".utf8)) }
            let grant: [String: Any] = ["token": String(repeating: "A", count: 43), "expiresAt": (Date().timeIntervalSince1970 + (mode == "expired" ? 1 : 90)) * 1000, "sourceURL": LeaderboardKind.arenaText.sourceURL.absoluteString]
            return (200, try responseJSON(["grant": grant]))
        }) { fetcher, id in
            let service = LeaderboardService(fetcher: fetcher)
            let result = await service.refresh([.arenaText], keeping: .init(), onBoard: { board in #expect(board.entries.first?.name == "GPT") })
            #expect(result.failures.isEmpty)
            #expect(result.snapshot.boards[.arenaText]?.entries.first?.name == "GPT")
            if mode == "expired" { #expect(!SharedHTTPStub.routes.recorded(id).contains { $0.url?.path.hasSuffix("contribute") == true }) }
        }
    }
}
