import Foundation
import Testing
@testable import LeaderboardCore

private actor ManagedBoundaryRPC: OpenAIAccountRPC {
    var response: Data
    let error: OpenAIConnectionError?
    init(_ response: String, error: OpenAIConnectionError? = nil) { self.response = Data(response.utf8); self.error = error }
    func request(_ method: String, params: Data) async throws -> Data {
        if let error { throw error }
        return response
    }
    func waitForLogin(_ id: String) async throws {}
    func stop() async {}
}

struct OpenAIManagedBoundaryTests {
    private var target: CCSwitchQuotaTarget { .init(id: "fixture", shortName: "Fixture", websiteURL: nil, kind: .officialNote, isCurrent: true, apiKey: nil, baseURL: nil) }
    @Test func defaultsConstructAnIdleSessionWithoutStartingTheInstalledHelper() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = OpenAIManagedQuotaSource(rootURL: root)
        let idle = await source.session(for: "fixture")
        await idle.stop()
        let server = OpenAIAppServer(profileURL: root)
        _ = await server.availableExecutable() // Read-only executable discovery, never a request.
        await server.stop()
        _ = OpenAIManagedQuotaSource()
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }

    @Test func malformedBrowserResponsesReleaseTheirLoginReservation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        for body in ["{}", "[]", #"{"loginId":"fixture","authUrl":"https://evil.invalid"}"#, #"{"loginId":"fixture","authUrl":"https://["}"#, "invalid"] {
            let rpc = ManagedBoundaryRPC(body)
            let source = OpenAIManagedQuotaSource(rootURL: root, sessionFactory: { _ in rpc })
            await #expect(throws: (any Error).self) { try await source.startLogin(for: target) }
            await #expect(throws: (any Error).self) { try await source.startLogin(for: target) }
            await source.cancelLogin(for: "missing")
        }
        let wrong = CCSwitchQuotaTarget(id: "fixture", shortName: "Fixture", websiteURL: nil, kind: .kimi, isCurrent: true, apiKey: nil, baseURL: nil)
        let rpc = ManagedBoundaryRPC("{}")
        let source = OpenAIManagedQuotaSource(rootURL: root, sessionFactory: { _ in rpc })
        #expect(try await source.loadQuota(for: wrong) == nil)
        await #expect(throws: OpenAIConnectionError.invalidResponse) { try await source.startLogin(for: wrong) }
        for text in ["https:auth.openai.com", "https://auth.openai.com:443/login"] {
            #expect(OpenAIManagedQuotaSource.isTrustedAuthorizationURL(URL(string: text)!) == text.contains(":443"))
        }
    }

    @Test func savedBindingsAndServiceFailuresRemainScopedToTheSameAccount() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        for (error, expected) in [(OpenAIConnectionError.helperMissing, AccountQuotaMessage.queryFailed), (.serviceFailed, AccountQuotaMessage.network)] {
            let rpc = ManagedBoundaryRPC("{}", error: error)
            let source = OpenAIManagedQuotaSource(rootURL: root, sessionFactory: { _ in rpc })
            let profile = await source.profileURL(for: "fixture")
            try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
            let binding = profile.appendingPathComponent("binding.json"), auth = profile.appendingPathComponent("auth.json")
            try Data("invalid".utf8).write(to: binding)
            #expect(try await source.loadQuota(for: target) == nil)
            try Data(#"{"accountID":"fixture-account"}"#.utf8).write(to: binding)
            try Data(#"{"tokens":{"account_id":"fixture-account"}}"#.utf8).write(to: auth)
            #expect(try await source.loadQuota(for: target)?.status == .message(expected))
        }
        let rpc = ManagedBoundaryRPC(#"{"loginId":"fixture","authUrl":"https://auth.openai.com/login"}"#)
        let source = OpenAIManagedQuotaSource(rootURL: root.appendingPathComponent("missing-auth"), sessionFactory: { _ in rpc })
        let attempt = try await source.startLogin(for: target)
        await #expect(throws: OpenAIConnectionError.serviceFailed) { try await source.startLogin(for: target) }
        await #expect(throws: OpenAIConnectionError.invalidResponse) { try await source.finishLogin(attempt, for: target) }
    }
}

private actor ManagedRefreshBoundaryRPC: OpenAIAccountRPC {
    let mode: String
    let auth: URL
    var quotaReads = 0
    init(mode: String, auth: URL) { self.mode = mode; self.auth = auth }
    func request(_ method: String, params: Data) async throws -> Data {
        if mode == "cancelled" { throw CancellationError() }
        if method == "account/read" && mode == "wrong-account-type" { return Data("{}".utf8) }
        if method == "account/read" { return Data(#"{"account":{"type":"chatgpt"}}"#.utf8) }
        quotaReads += 1
        if mode == "revoked" && quotaReads == 1 { throw OpenAIConnectionError.reauthRequired }
        if mode == "missing-auth" { try FileManager.default.removeItem(at: auth) }
        if mode == "bad-quota" { return Data("{}".utf8) }
        return Data(#"{"rateLimits":{"limitId":"codex","primary":{"usedPercent":20,"windowDurationMins":300}}}"#.utf8)
    }
    func waitForLogin(_ id: String) async throws {}
    func stop() async {}
}

struct ManagedRefreshBoundaryTests {
    @Test func refreshRetriesRevocationAndRejectsCredentialsRemovedBetweenRequests() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let target = CCSwitchQuotaTarget(id: "fixture", shortName: "Fixture", websiteURL: nil, kind: .officialNote, isCurrent: true, apiKey: nil, baseURL: nil)
        for mode in ["revoked", "missing-auth", "bad-quota", "cancelled", "wrong-account-type"] {
            let sourceRoot = root.appendingPathComponent(mode)
            let probe = OpenAIManagedQuotaSource(rootURL: sourceRoot)
            let profile = await probe.profileURL(for: "fixture")
            try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
            let auth = profile.appendingPathComponent("auth.json")
            try Data(#"{"tokens":{"account_id":"fixture-account"}}"#.utf8).write(to: auth)
            try Data(#"{"accountID":"fixture-account"}"#.utf8).write(to: profile.appendingPathComponent("binding.json"))
            let rpc = ManagedRefreshBoundaryRPC(mode: mode, auth: auth)
            let source = OpenAIManagedQuotaSource(rootURL: sourceRoot, sessionFactory: { _ in rpc })
            if mode == "cancelled" { await #expect(throws: CancellationError.self) { try await source.loadQuota(for: target) } }
            else {
                let chip = try #require(await source.loadQuota(for: target))
                if mode == "missing-auth" || mode == "wrong-account-type" { #expect(chip.status == .message(AccountQuotaMessage.reauthRequired)) }
                else if mode == "bad-quota" { #expect(chip.status == .message(AccountQuotaMessage.queryFailed)) }
                else {
                    if case .windows(let windows) = chip.status { #expect(windows.first?.utilization == 20) }
                    else { Issue.record("A successful retry lost the bound account quota") }
                    #expect(await rpc.quotaReads == 2)
                }
            }
        }
    }
    @Test func cancellingAnUnregisteredCompletionCannotBindTheAccount() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let rpc = ManagedBoundaryRPC(#"{"loginId":"fixture","authUrl":"https://auth.openai.com/login"}"#)
        let source = OpenAIManagedQuotaSource(rootURL: root, sessionFactory: { _ in rpc })
        let target = CCSwitchQuotaTarget(id: "fixture", shortName: "Fixture", websiteURL: nil, kind: .officialNote, isCurrent: true, apiKey: nil, baseURL: nil)
        let attempt = try await source.startLogin(for: target)
        await source.cancelLogin(for: "fixture")
        await #expect(throws: CancellationError.self) { try await source.finishLogin(attempt, for: target) }
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }
}


private actor GatedManagedBoundaryRPC: OpenAIAccountRPC {
    var blocked = false
    var ready: CheckedContinuation<Void, Never>?
    var release: CheckedContinuation<Data, Never>?
    func request(_ method: String, params: Data) async throws -> Data {
        blocked = true; ready?.resume(); ready = nil
        return await withCheckedContinuation { release = $0 }
    }
    func waitUntilBlocked() async { if !blocked { await withCheckedContinuation { ready = $0 } } }
    func unblock() { release?.resume(returning: Data(#"{"loginId":"fixture","authUrl":"https://auth.openai.com/login"}"#.utf8)); release = nil }
    func waitForLogin(_ id: String) async throws {}
    func stop() async {}
}

extension OpenAIManagedBoundaryTests {
    @Test func cancellingAStartingLoginRejectsTheLateBrowserReply() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let rpc = GatedManagedBoundaryRPC()
        let source = OpenAIManagedQuotaSource(rootURL: root, sessionFactory: { _ in rpc })
        let starting = Task { try await source.startLogin(for: target) }
        await rpc.waitUntilBlocked()
        let waiting = try await source.loadQuota(for: target)
        #expect(waiting?.status == .note(text: "等待授权", help: "请在浏览器中完成 OpenAI 授权"))
        await source.cancelLogin(for: target.id); await rpc.unblock()
        await #expect(throws: CancellationError.self) { try await starting.value }
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }
}
