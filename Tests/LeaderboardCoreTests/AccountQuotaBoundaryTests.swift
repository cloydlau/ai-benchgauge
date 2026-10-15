import Foundation
import Testing
@testable import LeaderboardCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private actor BoundaryQuotaTransport: AccountQuotaTransport {
    enum Step: Sendable { case response(Int, Data), error(URLError.Code), cancel }
    var steps: [Step]
    var requests: [URLRequest] = []
    init(_ steps: [Step]) { self.steps = steps }
    func data(for request: URLRequest) async throws -> AccountQuotaHTTPResponse {
        requests.append(request)
        guard !steps.isEmpty else { throw URLError(.badServerResponse) }
        switch steps.removeFirst() {
        case .response(let code, let body): return .init(statusCode: code, headers: [:], body: body)
        case .error(let code): throw URLError(code)
        case .cancel: throw CancellationError()
        }
    }
}

private final class BoundaryQuotaURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "quota-fixture.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        let response: URLResponse = url.path == "/plain"
            ? URLResponse(url: url, mimeType: "text/plain", expectedContentLength: 2, textEncodingName: "utf-8")
            : HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["X-Quota": "fixture"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("ok".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

struct AccountQuotaBoundaryTests {
    private func data(_ text: String) -> Data { Data(text.utf8) }
    private func target(_ kind: CCSwitchQuotaKind, key: String? = "fixture", token: String? = nil) -> CCSwitchQuotaTarget {
        .init(id: "fixture", shortName: "Fixture", websiteURL: nil, kind: kind, isCurrent: true, apiKey: key, baseURL: nil, accessToken: token)
    }
    private func client(_ transport: any AccountQuotaTransport) -> AccountQuotaClient {
        AccountQuotaClient(transport: transport, authFileURL: FileManager.default.temporaryDirectory.appendingPathComponent("missing-quota-\(UUID().uuidString).json"))
    }

    @Test func keyProvidersDistinguishAuthenticationNetworkAndUnusableResponses() async throws {
        for code in [401, 403, 408, 429, 500, 599, 404] {
            let transport = BoundaryQuotaTransport([.response(code, data("{}"))])
            let expected = [408, 429, 500, 599].contains(code) ? AccountQuotaMessage.network : AccountQuotaMessage.queryFailed
            #expect(try await client(transport).refresh(targets: [target(.kimi)]).first?.status == .message(expected))
        }
        for step: BoundaryQuotaTransport.Step in [.response(200, Data(repeating: 32, count: 1_048_577)), .error(.notConnectedToInternet)] {
            let expected = if case .error = step { AccountQuotaMessage.network } else { AccountQuotaMessage.queryFailed }
            #expect(try await client(BoundaryQuotaTransport([step])).refresh(targets: [target(.deepseek)]).first?.status == .message(expected))
        }
        let claude = BoundaryQuotaTransport([.response(200, data(#"{"five_hour":{"utilization":20}}"#))])
        let values = try await client(claude).refresh(targets: [target(.claude, token: "fixture-token")])
        #expect(values.first?.status == .windows([.init(name: "five_hour", utilization: 20, resetsAt: nil)]))
        for key in [nil, "", " ", "proxy-fixture"] {
            let transport = BoundaryQuotaTransport([])
            #expect(try await client(transport).refresh(targets: [target(.kimi, key: key)]).first?.status == .note(text: AccountQuotaMessage.notConfigured, help: AccountQuotaMessage.notConfiguredHelp))
            #expect(await transport.requests.isEmpty)
        }
    }

    @Test func geminiProjectLookupRejectsFailuresAndPassesOnlyAValidProject() async throws {
        let target = target(.gemini, token: "fixture-oauth")
        for (step, message): (BoundaryQuotaTransport.Step, String) in [
            (.error(.cannotConnectToHost), AccountQuotaMessage.network),
            (.response(401, data("{}")), AccountQuotaMessage.reauthRequired),
            (.response(403, data("{}")), AccountQuotaMessage.reauthRequired),
            (.response(429, data("{}")), AccountQuotaMessage.network),
            (.response(404, data("{}")), AccountQuotaMessage.queryFailed),
            (.response(200, Data(repeating: 32, count: 1_048_577)), AccountQuotaMessage.queryFailed),
            (.response(200, data("invalid")), AccountQuotaMessage.queryFailed),
            (.response(200, data("[]")), AccountQuotaMessage.queryFailed)
        ] {
            let transport = BoundaryQuotaTransport([step])
            #expect(try await client(transport).refresh(targets: [target]).first?.status == .message(message))
            #expect(await transport.requests.count == 1)
        }
        for body in [#"{"cloudaicompanionProject":"fixture-project"}"#, "{}", #"{"cloudaicompanionProject":{}}"#] {
            let transport = BoundaryQuotaTransport([.response(200, data(body)), .response(200, data(#"{"buckets":[{"modelId":"gemini-pro","remainingFraction":0.5}]}"#))])
            let result = try await client(transport).refresh(targets: [target])
            #expect(result.first?.status == .windows([.init(name: "gemini_pro", utilization: 50, resetsAt: nil)]))
            let requests = await transport.requests
            let posted = try JSONSerialization.jsonObject(with: #require(requests.last?.httpBody)) as? [String: String]
            #expect(posted == (body.contains("fixture-project") ? ["project": "fixture-project"] : [:]))
        }
    }

    @Test func cancellationPropagatesInsteadOfBecomingAQuotaFailure() async throws {
        for kind: CCSwitchQuotaKind in [.gemini, .kimi, .officialNote] {
            for step: BoundaryQuotaTransport.Step in [.cancel, .error(.cancelled)] {
                await #expect(throws: CancellationError.self) {
                    try await client(BoundaryQuotaTransport([step])).refresh(targets: [target(kind, token: "fixture-token")])
                }
            }
        }
        let zhipu = data(#"{"data":{"limits":[{"type":"tokens_limit","unit":3,"number":5,"percentage":20}]}}"#)
        await #expect(throws: CancellationError.self) {
            try await client(BoundaryQuotaTransport([.response(200, zhipu), .cancel])).refresh(targets: [target(.zhipu)])
        }
    }

    @Test func officialFailuresDoNotInventUsageAndNetworkFailuresRetainOnlyUsableHistory() async throws {
        for (step, message): (BoundaryQuotaTransport.Step, String) in [
            (.error(.timedOut), AccountQuotaMessage.network),
            (.response(200, Data(repeating: 32, count: 1_048_577)), AccountQuotaMessage.queryFailed),
            (.response(401, data("{}")), AccountQuotaMessage.reauthRequired),
            (.response(403, data("{}")), AccountQuotaMessage.queryFailed),
            (.response(403, data("<html>Forbidden: challenge required</html>")), AccountQuotaMessage.queryFailed),
            (.response(403, data(#"{"error":{"message":"Forbidden by access policy"}}"#)), AccountQuotaMessage.queryFailed),
            (.response(403, data(#"{"error":{"code":"token_expired"}}"#)), AccountQuotaMessage.reauthRequired),
            (.response(500, data("{}")), AccountQuotaMessage.queryFailed),
            (.response(200, data("{}")), AccountQuotaMessage.queryFailed),
            (.response(200, data(#"{"rate_limit":{}}"#)), AccountQuotaMessage.queryFailed)
        ] {
            #expect(try await client(BoundaryQuotaTransport([step])).refresh(targets: [target(.officialNote, token: "fixture-token")]).first?.status == .message(message))
        }
        for status: AccountQuotaChip.Status in [.pending, .note(text: "fixture", help: "fixture"), .message("fixture")] {
            let previous = AccountQuotaChip(id: "fixture", shortName: "Fixture", websiteURL: nil, kind: .kimi, isCurrent: true, status: status)
            let updated = try await client(BoundaryQuotaTransport([.error(.timedOut)])).refresh(targets: [target(.kimi)], previous: [previous])
            #expect(updated.first?.status == .message(AccountQuotaMessage.network))
            #expect(updated.first?.isStale == false)
        }
    }

    @Test func isolatedURLSessionNormalizesHeadersAndRejectsRedirects() async throws {
        _ = URLSessionAccountQuotaTransport() // Constructing defaults does not start a request.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BoundaryQuotaURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let transport = URLSessionAccountQuotaTransport(session: session)
        let response = try await transport.data(for: URLRequest(url: URL(string: "https://quota-fixture.invalid/http")!))
        #expect(response.statusCode == 200 && response.header("x-quota") == "fixture" && response.body == data("ok"))
        let plain = try await transport.data(for: URLRequest(url: URL(string: "https://quota-fixture.invalid/plain")!))
        #expect(plain.statusCode == 0 && plain.headers.isEmpty)
        let numeric = URLSessionAccountQuotaTransport.response(body: data("ok"), statusCode: 202, headerFields: [1: 2, "X-Test": "value"])
        #expect(numeric.headers == ["1": "2", "x-test": "value"])
        let request = URLRequest(url: URL(string: "https://quota-fixture.invalid/redirect")!)
        let http = HTTPURLResponse(url: request.url!, statusCode: 302, httpVersion: nil, headerFields: [:])!
        QuotaRedirectRejector().urlSession(session, task: session.dataTask(with: request), willPerformHTTPRedirection: http, newRequest: request) { redirected in
            #expect(redirected == nil)
        }
    }

    @Test func keepaliveSchedulesRejectUnencodableDatesAndUnwritableParents() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("file")
        try data("fixture").write(to: file)
        let store = XAIOAuthKeepAliveScheduleStore(fileURL: file.appendingPathComponent("schedule"))
        store.save(accountID: "fixture", nextAt: Date())
        #expect(store.nextDate(accountID: "fixture") == nil)
        store.save(accountID: nil, nextAt: Date(timeIntervalSince1970: .nan))
        #expect(try Data(contentsOf: file) == data("fixture"))
        _ = XAIOAuthKeepAliveScheduleStore()
    }
}

private struct WebsiteBoundaryQwenSource: QwenQuotaSource {
    func loadSummary() async -> Data? { Data("7天限额 剩余量 50%".utf8) }
}

struct AccountQuotaRequestBoundaryTests {
    @Test func unsupportedKeyKindsAreRejectedBeforeSendingOrParsingARequest() async throws {
        for kind: CCSwitchQuotaKind in [.officialNote, .qwen, .xaiOAuth] {
            let target = CCSwitchQuotaTarget(id: "fixture", shortName: "Fixture", websiteURL: nil, kind: kind, isCurrent: true, apiKey: "fixture", baseURL: nil)
            let rejected = try await AccountQuotaClient.queryKeyProvider(target, transport: BoundaryQuotaTransport([]))
            #expect(rejected.status == .message(AccountQuotaMessage.queryFailed))
            let injected = try await AccountQuotaClient.queryKeyProvider(target, transport: BoundaryQuotaTransport([.response(200, Data("{}".utf8))]), requestFactory: { _, _ in URLRequest(url: URL(string: "https://fixture.invalid")!) })
            #expect(injected.status == .message(AccountQuotaMessage.queryFailed))
        }
        let qwen = CCSwitchQuotaTarget(id: "fixture", shortName: "Fixture", websiteURL: nil, kind: .qwen, isCurrent: true, apiKey: nil, baseURL: nil)
        let client = AccountQuotaClient(transport: BoundaryQuotaTransport([]), qwenQuotaSource: WebsiteBoundaryQwenSource())
        let values = try await client.refresh(targets: [qwen])
        #expect(values.first?.status == .qwenWebsite(.init(periodLabel: "7d", remainingPercent: 50, resetsAt: nil)))
        let minimax = CCSwitchQuotaTarget(id: "fixture", shortName: "Fixture", websiteURL: nil, kind: .minimax, isCurrent: true, apiKey: "fixture", baseURL: nil)
        let transport = BoundaryQuotaTransport([.response(200, Data(#"{"model_remains":[{"model_name":"general","current_interval_remaining_percent":50}]}"#.utf8))])
        #expect(try await clientWith(transport).refresh(targets: [minimax]).count == 1)
        #expect(await transport.requests.first?.url?.host == "api.minimaxi.com")
    }
    private func clientWith(_ transport: any AccountQuotaTransport) -> AccountQuotaClient { .init(transport: transport) }
}
