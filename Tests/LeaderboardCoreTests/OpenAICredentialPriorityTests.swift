import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import LeaderboardCore
import Testing

struct OpenAICredentialPriorityTests {
    private func token(expiresIn: TimeInterval) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: ["exp": Date().addingTimeInterval(expiresIn).timeIntervalSince1970])
        let payload = data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        return "fixture.\(payload).signature"
    }

    private func target(token: String, accountID: String? = "same-account") -> CCSwitchQuotaTarget {
        CCSwitchQuotaTarget(id: "selected", shortName: "OpenAI", modelName: "gpt-fixture",
            websiteURL: nil, kind: .officialNote, isCurrent: true, apiKey: nil, baseURL: nil,
            accessToken: token, accountID: accountID)
    }

    private func saveProfile(_ source: OpenAIManagedQuotaSource, token: String, accountID: String = "same-account") async throws -> URL {
        let profile = await source.profileURL(for: "selected")
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        try Data(#"{"accountID":"same-account"}"#.utf8).write(to: profile.appending(path: "binding.json"))
        try JSONSerialization.data(withJSONObject: ["tokens": ["account_id": accountID, "access_token": token]])
            .write(to: profile.appending(path: "auth.json"))
        return profile.appending(path: "auth.json")
    }

    @Test(arguments: [200, 401])
    func renewedCodexLoginSupersedesAnOlderRevokedAppProfile(statusCode: Int) async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "openai-priority-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let old = try token(expiresIn: 3600), renewed = try token(expiresIn: 7200)
        let rpc = RejectedOldOpenAIProfile()
        let transport = RenewedOpenAITransport(accessToken: renewed, statusCode: statusCode)
        let source = OpenAIManagedQuotaSource(rootURL: root.appending(path: "app"),
            transport: transport, sessionFactory: { _ in rpc })
        let profileAuth = try await saveProfile(source, token: old)
        let originalAuth = try Data(contentsOf: profileAuth)
        let codexRoot = root.appending(path: ".codex")
        try FileManager.default.createDirectory(at: codexRoot, withIntermediateDirectories: true)
        let localAuth = codexRoot.appending(path: "auth.json")
        try JSONSerialization.data(withJSONObject: ["tokens": ["account_id": "same-account", "access_token": renewed]])
            .write(to: localAuth)
        let originalLocalAuth = try Data(contentsOf: localAuth)
        let discovered = OfficialQuotaDiscovery.targets(home: root, environment: [:])
        let merged = OfficialQuotaDiscovery.merge(ccSwitch: [target(token: old)], official: discovered)
        #expect(merged.count == 1)
        #expect(merged.first?.accessToken == renewed)
        let chips = try await AccountQuotaClient(transport: transport, officialQuotaSource: source,
            openAIPlanExpiryStore: OpenAIPlanExpiryStore(fileURL: root.appending(path: "expiry.json")))
            .refresh(targets: merged)
        let chip = try #require(chips.first)
        if statusCode == 200 {
            #expect(chip.status == .windows([ParsedQuotaWindow(name: "five_hour", utilization: 100, resetsAt: nil)]))
            #expect(AccountQuotaFormatting.plainSummary(for: chip, now: Date()) == "5h 0%")
        } else {
            // A newer token is a candidate, not proof of authentication. The
            // endpoint still decides whether it can be used.
            #expect(chip.status == .message(AccountQuotaMessage.reauthRequired))
        }
        #expect(chip.id == "selected")
        #expect(chip.isCurrent)
        #expect(chip.modelName == "gpt-fixture")
        #expect(await rpc.requestCount == 0)
        #expect(try Data(contentsOf: profileAuth) == originalAuth)
        #expect(try Data(contentsOf: localAuth) == originalLocalAuth)
    }

    @Test func olderExpiredOrUnscopedCredentialsCannotOverrideTheManagedLogin() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "openai-priority-boundary-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let old = try token(expiresIn: 3600)
        for candidate in [try token(expiresIn: 1800), try token(expiresIn: -60), "opaque-token"] {
            let rpc = RejectedOldOpenAIProfile()
            let source = OpenAIManagedQuotaSource(rootURL: root, sessionFactory: { _ in rpc })
            _ = try await saveProfile(source, token: old)
            #expect(try await source.loadQuota(for: target(token: candidate))?.status == .message(AccountQuotaMessage.reauthRequired))
            #expect(await rpc.requestCount == 1)
        }
        for accountID in [nil, ""] as [String?] {
            let rpc = RejectedOldOpenAIProfile()
            let source = OpenAIManagedQuotaSource(rootURL: root, sessionFactory: { _ in rpc })
            _ = try await saveProfile(source, token: old)
            #expect(try await source.loadQuota(for: target(token: try token(expiresIn: 7200), accountID: accountID))?.status
                == .message(AccountQuotaMessage.reauthRequired))
            #expect(await rpc.requestCount == 1)
        }
        let rpc = RejectedOldOpenAIProfile()
        let source = OpenAIManagedQuotaSource(rootURL: root, sessionFactory: { _ in rpc })
        _ = try await saveProfile(source, token: old, accountID: "interrupted-other-account")
        #expect(try await source.loadQuota(for: target(token: try token(expiresIn: 7200)))?.status
            == .message(AccountQuotaMessage.reauthRequired))
        #expect(await rpc.requestCount == 0)
    }
}

private actor RejectedOldOpenAIProfile: OpenAIAccountRPC {
    var requestCount = 0
    func request(_ method: String, params: Data) async throws -> Data {
        requestCount += 1
        throw OpenAIConnectionError.reauthRequired
    }
    func waitForLogin(_ id: String) async throws { throw OpenAIConnectionError.reauthRequired }
    func stop() async {}
}

private struct RenewedOpenAITransport: AccountQuotaTransport {
    let accessToken: String
    let statusCode: Int
    func data(for request: URLRequest) async throws -> AccountQuotaHTTPResponse {
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(accessToken)")
        #expect(request.value(forHTTPHeaderField: "ChatGPT-Account-ID") == "same-account")
        if request.url?.path == "/backend-api/accounts/check/v4-2023-04-27" {
            return AccountQuotaHTTPResponse(statusCode: 200, headers: [:], body: Data(#"{"accounts":{}}"#.utf8))
        }
        #expect(request.url?.absoluteString == "https://chatgpt.com/backend-api/wham/usage")
        return AccountQuotaHTTPResponse(statusCode: statusCode, headers: [:], body: Data(
            (statusCode == 200 ? #"{"rate_limit":{"primary_window":{"used_percent":100}}}"#
                : #"{"error":{"code":"token_revoked"}}"#).utf8))
    }
}
