import Foundation
import Testing
@testable import LeaderboardCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private actor XAIQuotaBoundaryTransport: AccountQuotaTransport {
    enum Step: Sendable { case response(Int, [String: String], Data), error(URLError.Code), cancel }
    var steps: [Step]
    init(_ steps: [Step]) { self.steps = steps }
    func data(for request: URLRequest) async throws -> AccountQuotaHTTPResponse {
        guard !steps.isEmpty else { throw URLError(.badServerResponse) }
        switch steps.removeFirst() {
        case .response(let code, let headers, let body): return .init(statusCode: code, headers: headers, body: body)
        case .error(let code): throw URLError(code)
        case .cancel: throw CancellationError()
        }
    }
}

struct XAIQuotaBoundaryTests {
    private func bytes(_ text: String) -> Data { Data(text.utf8) }
    private var discovery: XAIQuotaBoundaryTransport.Step { .response(200, [:], bytes(#"{"issuer":"https://auth.x.ai","token_endpoint":"https://auth.x.ai/oauth2/token"}"#)) }
    private var token: XAIQuotaBoundaryTransport.Step { .response(200, [:], bytes(#"{"access_token":"fixture-access"}"#)) }
    private var target: CCSwitchQuotaTarget { .init(id: "fixture", shortName: "Fixture", websiteURL: nil, kind: .xaiOAuth, isCurrent: true, apiKey: nil, baseURL: nil) }
    private func fixture(_ steps: [XAIQuotaBoundaryTransport.Step], reauth: Bool = false) throws -> (URL, AccountQuotaClient) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let auth = root.appendingPathComponent("auth.json")
        try bytes("{\"default_account_id\":\"fixture\",\"accounts\":{\"fixture\":{\"account_id\":\"fixture\",\"refresh_token\":\"fixture-refresh\",\"requires_reauth\":\(reauth)}}}").write(to: auth)
        return (root, AccountQuotaClient(transport: XAIQuotaBoundaryTransport(steps), authFileURL: auth))
    }

    @Test func missingLoginAndDiscoveryFailuresHaveExplicitKeepaliveOutcomes() async throws {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("missing-auth-\(UUID()).json")
        #expect(try await AccountQuotaClient(transport: XAIQuotaBoundaryTransport([]), authFileURL: missing).keepAliveXAI() == .loginRequired)
        let (reauthRoot, reauth) = try fixture([], reauth: true)
        defer { try? FileManager.default.removeItem(at: reauthRoot) }
        #expect(try await reauth.keepAliveXAI() == .loginRequired)
        let bad = ["{}", "[]", "invalid", #"{"issuer":"https://evil.invalid","token_endpoint":"https://auth.x.ai/oauth2/token"}"#, #"{"issuer":"https://auth.x.ai"}"#, #"{"issuer":"https://auth.x.ai","token_endpoint":"https://evil.invalid/token"}"#]
        var steps: [XAIQuotaBoundaryTransport.Step] = bad.map { .response(200, [:], bytes($0)) }
        steps += [.response(408, [:], bytes("{}")), .response(429, [:], bytes("{}")), .response(500, [:], bytes("{}")), .response(404, [:], bytes("{}")), .response(200, [:], Data(repeating: 32, count: 1_048_577)), .error(.timedOut)]
        for step in steps {
            let (root, client) = try fixture([step]); defer { try? FileManager.default.removeItem(at: root) }
            #expect(try await client.keepAliveXAI() == .retry)
        }
        for step: XAIQuotaBoundaryTransport.Step in [.cancel, .error(.cancelled)] {
            let (root, client) = try fixture([step]); defer { try? FileManager.default.removeItem(at: root) }
            await #expect(throws: CancellationError.self) { try await client.keepAliveXAI() }
        }
    }

    @Test func tokenRefreshDoesNotTreatMalformedOrRejectedTokensAsASuccess() async throws {
        let failures: [(XAIQuotaBoundaryTransport.Step, XAIOAuthKeepAliveOutcome)] = [
            (.response(401, [:], bytes("{}")), .loginRequired), (.response(403, [:], bytes("{}")), .loginRequired),
            (.response(400, [:], bytes("invalid")), .loginRequired),
            (.response(200, [:], bytes(#"{"error":"INVALID_TOKEN"}"#)), .loginRequired),
            (.response(408, [:], bytes("{}")), .retry), (.response(429, [:], bytes("{}")), .retry),
            (.response(500, [:], bytes("{}")), .retry), (.response(404, [:], bytes("{}")), .retry),
            (.response(200, [:], bytes(#"{"error":"other"}"#)), .retry),
            (.response(200, [:], bytes("{}")), .retry), (.response(200, [:], bytes("[]")), .retry),
            (.response(200, [:], bytes(#"{"access_token":" "}"#)), .retry),
            (.response(200, [:], Data(repeating: 32, count: 1_048_577)), .retry), (.error(.timedOut), .retry)
        ]
        for (step, expected) in failures {
            let (root, client) = try fixture([discovery, step]); defer { try? FileManager.default.removeItem(at: root) }
            #expect(try await client.keepAliveXAI() == expected)
        }
        for step: XAIQuotaBoundaryTransport.Step in [.cancel, .error(.cancelled)] {
            let (root, client) = try fixture([discovery, step]); defer { try? FileManager.default.removeItem(at: root) }
            await #expect(throws: CancellationError.self) { try await client.keepAliveXAI() }
        }
        for value in [#"{"access_token":"fixture","refresh_token":" "}"#, #"{"access_token":"fixture","refresh_token":"fixture-refresh","expires_in":0}"#] {
            let (root, client) = try fixture([discovery, .response(200, [:], bytes(value))]); defer { try? FileManager.default.removeItem(at: root) }
            #expect(try await client.keepAliveXAI() == .renewed)
        }
    }

    @Test func billingClassifiesBothHeadersAndTrailersAndPropagatesCancellation() async throws {
        let cases: [(XAIQuotaBoundaryTransport.Step, String)] = [
            (.error(.cannotConnectToHost), AccountQuotaMessage.network),
            (.response(200, [:], Data(repeating: 32, count: 1_048_577)), AccountQuotaMessage.queryFailed),
            (.response(200, ["grpc-status": "16"], Data()), AccountQuotaMessage.reauthRequired),
            (.response(200, ["grpc-status": "14"], Data()), AccountQuotaMessage.network),
            (.response(200, ["grpc-status": "9"], Data()), AccountQuotaMessage.queryFailed)
        ]
        for (step, message) in cases {
            let (root, client) = try fixture([discovery, token, step]); defer { try? FileManager.default.removeItem(at: root) }
            #expect(try await client.refresh(targets: [target]).first?.status == .message(message))
        }
        for (status, message) in [(16, AccountQuotaMessage.reauthRequired), (14, AccountQuotaMessage.network), (9, AccountQuotaMessage.queryFailed)] {
            let text = bytes("grpc-status: \(status)\r\n")
            let body = Data([0x80, 0, 0, 0, UInt8(text.count)]) + text
            let (root, client) = try fixture([discovery, token, .response(200, [:], body)]); defer { try? FileManager.default.removeItem(at: root) }
            #expect(try await client.refresh(targets: [target]).first?.status == .message(message))
        }
        for step: XAIQuotaBoundaryTransport.Step in [.cancel, .error(.cancelled)] {
            let (root, client) = try fixture([discovery, token, step]); defer { try? FileManager.default.removeItem(at: root) }
            await #expect(throws: CancellationError.self) { try await client.refresh(targets: [target]) }
        }
    }
}

#if !os(Windows)
struct XAITokenWriteBoundaryTests {
    @Test func tokenRotationFailsClosedAtEachFilesystemBoundaryWithoutLosingTheOldToken() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("auth.json")
        let original = Data(#"{"default_account_id":"fixture","accounts":{"fixture":{"account_id":"fixture","refresh_token":"old"}}}"#.utf8)
        #expect(!XaiAuthFile.commitRefreshTokenReplacement(at: file, accountID: "fixture", oldToken: "old", newToken: "new"))
        for failure in ["create", "write", "zero-write", "flush", "protect", "replace", "restrict"] {
            try original.write(to: file)
            var io = XaiAuthFile.RefreshTokenIO()
            switch failure {
            case "create": io.create = { _ in -1 }
            case "write": io.writeBytes = { _, _, _ in -1 }
            case "zero-write": io.writeBytes = { _, _, _ in 0 }
            case "flush": io.flush = { _ in -1 }
            case "protect": io.protect = { _ in -1 }
            case "replace": io.replace = { _, _ in throw CocoaError(.fileWriteUnknown) }
            default: io.restrict = { _ in throw CocoaError(.fileWriteNoPermission) }
            }
            #expect(!XaiAuthFile.commitRefreshTokenReplacement(at: file, accountID: "fixture", oldToken: "old", newToken: "new", io: io))
            if failure != "restrict" { #expect(try Data(contentsOf: file) == original) }
            #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["auth.json"])
        }
        try original.write(to: file)
        #expect(!XaiAuthFile.commitRefreshTokenReplacement(at: file, accountID: "fixture", oldToken: "wrong", newToken: "new"))
        #expect(try Data(contentsOf: file) == original)
    }


}
#endif

extension XAIQuotaBoundaryTests {
    @Test func missingSubscriptionIdentityAndRejectedRotationNeverReturnAnotherAccount() async throws {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID())")
        let tokens = XAIAccessTokens()
        #expect(try await tokens.subscriptionUserID(transport: XAIQuotaBoundaryTransport([]), authFileURL: missing, now: Date()) == nil)
        let (root, _) = try fixture([])
        defer { try? FileManager.default.removeItem(at: root) }
        let auth = root.appendingPathComponent("auth.json")
        #expect(try await tokens.subscriptionUserID(transport: XAIQuotaBoundaryTransport([discovery, .response(401, [:], bytes("{}"))]), authFileURL: auth, now: Date()) == nil)
        let failed = XAIAccessTokens(rotateRefreshToken: { _, _, _, _ in false })
        let result = try await failed.forceRefresh(transport: XAIQuotaBoundaryTransport([discovery, .response(200, [:], bytes(#"{"access_token":"fixture","refresh_token":"rotated"}"#))]), authFileURL: auth, now: Date())
        if case .failure(.failed) = result {} else { Issue.record("A rejected atomic token replacement was accepted") }
        #expect(String(decoding: try Data(contentsOf: auth), as: UTF8.self).contains("fixture-refresh"))
    }
}

private actor GatedXAIQuotaBoundaryTransport: AccountQuotaTransport {
    var replies: [XAIQuotaBoundaryTransport.Step]
    var ready: CheckedContinuation<Void, Never>?
    var release: CheckedContinuation<Void, Never>?
    var blocked = false
    var calls = 0
    init(_ replies: [XAIQuotaBoundaryTransport.Step]) { self.replies = replies }
    func data(for request: URLRequest) async throws -> AccountQuotaHTTPResponse {
        calls += 1
        if calls == 1 {
            blocked = true; ready?.resume(); ready = nil
            await withCheckedContinuation { release = $0 }
        }
        guard !replies.isEmpty else { throw URLError(.badServerResponse) }
        let step = replies.removeFirst()
        guard case let .response(code, headers, body) = step else { throw URLError(.badServerResponse) }
        return .init(statusCode: code, headers: headers, body: body)
    }
    func waitUntilBlocked() async { if !blocked { await withCheckedContinuation { ready = $0 } } }
    func unblock() { release?.resume(); release = nil }
}

extension XAIQuotaBoundaryTests {
    @Test func concurrentRefreshesForDifferentLoginFilesKeepTheirOwnIdentity() async throws {
        for _ in 0..<5 {
            let (one, _) = try fixture([]), (two, _) = try fixture([])
            defer { try? FileManager.default.removeItem(at: one); try? FileManager.default.removeItem(at: two) }
            let transport = GatedXAIQuotaBoundaryTransport([discovery, .response(200, [:], bytes(#"{"access_token":"one","refresh_token":"first"}"#)), .response(200, [:], bytes(#"{"access_token":"two","refresh_token":"second"}"#))])
            let tokens = XAIAccessTokens()
            let first = Task { try await tokens.forceRefresh(transport: transport, authFileURL: one.appendingPathComponent("auth.json"), now: Date()) }
            await transport.waitUntilBlocked()
            let second = Task { try await tokens.forceRefresh(transport: transport, authFileURL: two.appendingPathComponent("auth.json"), now: Date()) }
            try await Task.sleep(for: .milliseconds(20))
            await transport.unblock()
            let a = try await first.value, b = try await second.value
            if case .token("one") = a {} else { Issue.record("First login lost its access token") }
            if case .token("two") = b {} else { Issue.record("Second login did not receive its own refreshed token") }
            #expect(await transport.calls == 3)
        }
    }
}
