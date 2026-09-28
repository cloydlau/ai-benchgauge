import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import LeaderboardCore
import Testing

@MainActor
struct OpenAIConnectionTests {
    private func target(accountID: String = "original-account") -> CCSwitchQuotaTarget {
        CCSwitchQuotaTarget(id: "official", shortName: "OpenAI", websiteURL: URL(string: "https://chatgpt.com/codex"),
                            kind: .officialNote, isCurrent: true, apiKey: nil, baseURL: nil,
                            accessToken: "expired-cc-switch-token", accountID: accountID)
    }

    private func fixture(transport: any AccountQuotaTransport = UnexpectedOpenAITransport()) async throws -> (URL, OpenAIManagedQuotaSource, ScriptedOpenAIAccountRPC) {
        let root = FileManager.default.temporaryDirectory.appending(path: "openai-flow-\(UUID().uuidString)")
        let rpc = ScriptedOpenAIAccountRPC()
        let source = OpenAIManagedQuotaSource(rootURL: root, transport: transport, sessionFactory: { _ in rpc })
        await rpc.setProfile(await source.profileURL(for: "official"))
        return (root, source, rpc)
    }

    @Test
    func testBrowserCallbackPersistsLoginAndQuotaUsesItInsteadOfExpiredCCSwitchCredentials() async throws {
        let (root, source, rpc) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let attempt = try await source.startLogin(for: target())
        #expect((attempt.authorizationURL.host) == ("auth.openai.com"))
        try await source.finishLogin(attempt, for: target())
        let transport = UnexpectedOpenAITransport()
        let chips = try await AccountQuotaClient(transport: transport, officialQuotaSource: source).refresh(targets: [target()])
        #expect((chips.count) == (1))
        #expect((chips.first?.status) == (.windows([
            ParsedQuotaWindow(name: "five_hour", utilization: 20, resetsAt: Date(timeIntervalSince1970: 1_800_000_000)),
            ParsedQuotaWindow(name: "weekly_limit", utilization: 35, resetsAt: Date(timeIntervalSince1970: 1_800_300_000)),
        ])))
        let transportCount = await transport.count()
        #expect((transportCount) == (0))
        let initialFlags = await rpc.refreshFlags()
        #expect((initialFlags) == ([true]))

        // A restarted app must still prefer its authorized login and renew it.
        let restarted = OpenAIManagedQuotaSource(rootURL: root, transport: UnexpectedOpenAITransport(), sessionFactory: { _ in rpc })
        let restored = try await restarted.loadQuota(for: target())
        #expect((restored?.status) == (chips.first?.status))
        let restartedFlags = await rpc.refreshFlags()
        #expect((restartedFlags) == ([true, true]))
    }

    @Test
    func testRejectedRefreshOffersReauthorizationAndSuccessfulRetryRestoresQuota() async throws {
        let (root, source, rpc) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try await source.startLogin(for: target())
        try await source.finishLogin(first, for: target())
        await rpc.rejectRefresh(true)
        let rejected = try await source.loadQuota(for: target())
        #expect((rejected?.status) == (.message(AccountQuotaMessage.reauthRequired)))
        await rpc.rejectRefresh(false)
        let retry = try await source.startLogin(for: target())
        try await source.finishLogin(retry, for: target())
        let restored = try await source.loadQuota(for: target())
        guard case .windows = restored?.status else { return recordFailure("reauthorization must restore usage") }
    }

    @Test
    func testCancellationAndFailureReleaseTheLoginSoTheButtonCanRetry() async throws {
        let (root, source, rpc) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try await source.startLogin(for: target())
        await source.cancelLogin(for: "official")
        let retry = try await source.startLogin(for: target())
        await rpc.failLogin(true)
        do {
            try await source.finishLogin(retry, for: target())
            recordFailure("failed callback must not persist a login")
        } catch { #expect((error as? OpenAIConnectionError) == (.signInFailed)) }
        let beforeLogin = try await source.loadQuota(for: target())
        #expect((beforeLogin) == nil)
        await rpc.failLogin(false)
        let third = try await source.startLogin(for: target())
        try await source.finishLogin(third, for: target())
    }

    @Test
    func testWrongBrowserAccountCannotBeSavedUnderTheOriginalProvider() async throws {
        let (root, source, rpc) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        await rpc.setAccountID("different-account")
        let attempt = try await source.startLogin(for: target())
        do {
            try await source.finishLogin(attempt, for: target())
            recordFailure("wrong account must not be bound to the provider")
        } catch { #expect((error as? OpenAIConnectionError) == (.accountMismatch)) }
        let quota = try await source.loadQuota(for: target())
        #expect((quota) == nil)
        let loggedOut = await rpc.loggedOut()
        #expect(loggedOut)
    }

    @Test
    func testInterruptedAccountChangeCannotReuseAnOldProviderBinding() async throws {
        let (root, source, rpc) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let attempt = try await source.startLogin(for: target())
        try await source.finishLogin(attempt, for: target())
        await rpc.setAccountID("different-account")
        // Simulate a callback writing credentials just as its window is closed.
        try await rpc.waitForLogin("interrupted")
        let rejected = try await source.loadQuota(for: target())
        #expect((rejected?.status) == (.message(AccountQuotaMessage.reauthRequired)))
    }

    @Test
    func testNetworkLossKeepsLastQuotaWhileInvalidRefreshNeverFallsBackToCCSwitch() async throws {
        let (root, source, rpc) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let attempt = try await source.startLogin(for: target())
        try await source.finishLogin(attempt, for: target())
        let transport = UnexpectedOpenAITransport()
        let client = AccountQuotaClient(transport: transport, officialQuotaSource: source)
        let successful = try await client.refresh(targets: [target()])
        await rpc.failUsage(true)
        let offline = try await client.refresh(targets: [target()], previous: successful)
        #expect((offline.first?.status) == (successful.first?.status))
        #expect((offline.first?.isStale) == (true))
        await rpc.failUsage(false)
        await rpc.rejectUsageOnce()
        _ = try await client.refresh(targets: [target()])
        let refreshFlags = await rpc.refreshFlags()
        #expect((refreshFlags) == ([true, false, false, true]))
        let transportCount = await transport.count()
        #expect((transportCount) == (0))
    }

    @Test
    func testManagedQuotaIncludesMatchingAccountExpiryUsingTheRefreshedProfileToken() async throws {
        let transport = OpenAIPlanExpiryTransport(body: Data(#"{"accounts":{"other-account":{"entitlement":{"expires_at":"2026-10-01T00:00:00Z"}},"original-account":{"entitlement":{"expires_at":"2026-10-24T00:00:00Z","renews_at":"2026-10-15T00:00:00Z"}}}}"#.utf8))
        let (root, source, rpc) = try await fixture(transport: transport)
        defer { try? FileManager.default.removeItem(at: root) }
        let attempt = try await source.startLogin(for: target())
        try await source.finishLogin(attempt, for: target())
        await rpc.setRefreshedAccessToken("refreshed-profile-token")
        let fallback = UnexpectedOpenAITransport()
        let chips = try await AccountQuotaClient(transport: fallback, officialQuotaSource: source).refresh(targets: [target()])
        let card = try #require(chips.first)
        guard case let .windows(windows) = card.status else { return recordFailure("usage must succeed") }
        #expect((windows.map(\.name)) == (["five_hour", "weekly_limit", ParsedQuotaWindow.planExpiryName]))
        #expect((windows.last?.resetsAt) == (ISO8601DateFormatter().date(from: "2026-10-24T00:00:00Z")))
        let now = ISO8601DateFormatter().date(from: "2026-09-28T00:00:00Z")!
        #expect(AccountQuotaFormatting.plainSummary(for: card, now: now).contains("至10月24日"))
        let requests = await transport.requests()
        #expect((requests.count) == (1))
        #expect((requests.first?.httpMethod) == ("GET"))
        #expect((requests.first?.url?.absoluteString) == ("https://chatgpt.com/backend-api/accounts/check/v4-2023-04-27"))
        #expect((requests.first?.value(forHTTPHeaderField: "Authorization")) == ("Bearer refreshed-profile-token"))
        #expect((requests.first?.value(forHTTPHeaderField: "ChatGPT-Account-ID")) == ("original-account"))
        let fallbackCount = await fallback.count()
        #expect((fallbackCount) == (0))
    }

    @Test
    func testManagedQuotaKeepsUsageWhenExpiryIsUnavailableAndNeverUsesRenewalOrAnotherAccount() async throws {
        let scenarios: [(Int, Data)] = [
            (200, Data(#"{"accounts":{"original-account":{"entitlement":{"renews_at":"2026-10-24T00:00:00Z"}}}}"#.utf8)),
            (200, Data(#"{"accounts":{"other-account":{"entitlement":{"expires_at":"2026-10-24T00:00:00Z"}}}}"#.utf8)),
            (200, Data("not-json".utf8)),
            (200, Data(repeating: 0, count: 1_048_577)),
            (401, Data()), (403, Data()), (500, Data()),
        ]
        for (status, body) in scenarios {
            let transport = OpenAIPlanExpiryTransport(status: status, body: body)
            let (root, source, _) = try await fixture(transport: transport)
            defer { try? FileManager.default.removeItem(at: root) }
            let attempt = try await source.startLogin(for: target())
            try await source.finishLogin(attempt, for: target())
            let loaded = try await source.loadQuota(for: target())
            let card = try #require(loaded)
            guard case let .windows(windows) = card.status else { return recordFailure("expiry failure must not hide usage") }
            #expect((windows.map(\.name)) == (["five_hour", "weekly_limit"]))
            let now = ISO8601DateFormatter().date(from: "2026-09-28T00:00:00Z")!
            #expect(!(AccountQuotaFormatting.plainSummary(for: card, now: now).contains("截至")))
            #expect(!(card.isStale))
        }
    }

    @Test
    func testManagedExpiryNetworkFailureKeepsUsageAndCancellationPropagates() async throws {
        for cancel in [false, true] {
            let transport = OpenAIPlanExpiryTransport(failure: cancel ? CancellationError() : URLError(.timedOut))
            let (root, source, _) = try await fixture(transport: transport)
            defer { try? FileManager.default.removeItem(at: root) }
            let attempt = try await source.startLogin(for: target())
            try await source.finishLogin(attempt, for: target())
            do {
                let card = try await source.loadQuota(for: target())
                #expect(!(cancel), Comment(rawValue: "cancellation must propagate"))
                guard case let .windows(windows) = card?.status else { return recordFailure("expiry timeout must keep usage") }
                #expect((windows.count) == (2))
            } catch is CancellationError {
                #expect(cancel)
            }
        }
    }

    @Test
    func testTrustedOAuthURLAndCodexBucketSelection() {
        #expect(OpenAIManagedQuotaSource.isTrustedAuthorizationURL(URL(string: "https://auth.openai.com/oauth/authorize?state=example")!))
        for url in ["http://auth.openai.com/", "https://auth.openai.com.evil/", "https://user:pass@chatgpt.com/", "https://chatgpt.com:8443/"] {
            #expect(!(OpenAIManagedQuotaSource.isTrustedAuthorizationURL(URL(string: url)!)))
        }
        let data = Data(#"{"rateLimits":{"limitId":"other","primary":{"usedPercent":99}},"rateLimitsByLimitId":{"codex":{"limitId":"codex","primary":{"usedPercent":20,"windowDurationMins":300,"resetsAt":1800000000}}}}"#.utf8)
        #expect((CCSwitchQuotaParsers.parseOpenAIAppServer(data)) == (.windows([
            ParsedQuotaWindow(name: "five_hour", utilization: 20, resetsAt: Date(timeIntervalSince1970: 1_800_000_000)),
        ])))
    }
}

private actor OpenAIPlanExpiryTransport: AccountQuotaTransport {
    private let status: Int
    private let body: Data
    private let failure: (any Error)?
    private var recordedRequests: [URLRequest] = []

    init(status: Int = 200, body: Data = Data(), failure: (any Error)? = nil) {
        self.status = status
        self.body = body
        self.failure = failure
    }

    func requests() -> [URLRequest] { recordedRequests }

    func data(for request: URLRequest) async throws -> AccountQuotaHTTPResponse {
        recordedRequests.append(request)
        if let failure { throw failure }
        return AccountQuotaHTTPResponse(statusCode: status, headers: [:], body: body)
    }
}

private actor UnexpectedOpenAITransport: AccountQuotaTransport {
    private var calls = 0
    func count() -> Int { calls }
    func data(for request: URLRequest) async throws -> AccountQuotaHTTPResponse {
        calls += 1
        return AccountQuotaHTTPResponse(statusCode: 401, headers: [:], body: Data())
    }
}

private actor ScriptedOpenAIAccountRPC: OpenAIAccountRPC {
    private var profile: URL?
    private var accountID = "original-account"
    private var rejectsRefresh = false
    private var failsLogin = false
    private var failsUsage = false
    private var rejectsUsageOnce = false
    private var flags: [Bool] = []
    private var didLogout = false
    private var sequence = 0
    private var refreshedAccessToken: String?
    func setProfile(_ url: URL) { profile = url }
    func setAccountID(_ id: String) { accountID = id }
    func rejectRefresh(_ value: Bool) { rejectsRefresh = value }
    func failLogin(_ value: Bool) { failsLogin = value }
    func failUsage(_ value: Bool) { failsUsage = value }
    func rejectUsageOnce() { rejectsUsageOnce = true }
    func refreshFlags() -> [Bool] { flags }
    func loggedOut() -> Bool { didLogout }
    func setRefreshedAccessToken(_ token: String) { refreshedAccessToken = token }

    func request(_ method: String, params: Data) async throws -> Data {
        switch method {
        case "account/login/start":
            sequence += 1
            return Data("{\"loginId\":\"login-\(sequence)\",\"authUrl\":\"https://auth.openai.com/oauth/authorize?state=example\"}".utf8)
        case "account/read":
            let object = try JSONSerialization.jsonObject(with: params) as? [String: Any]
            flags.append(object?["refreshToken"] as? Bool ?? false)
            if rejectsRefresh { throw OpenAIConnectionError.reauthRequired }
            if object?["refreshToken"] as? Bool == true, let token = refreshedAccessToken {
                try writeCredentials(accessToken: token)
            }
            return Data(#"{"account":{"type":"chatgpt","planType":"pro"}}"#.utf8)
        case "account/rateLimits/read":
            if failsUsage { throw OpenAIConnectionError.serviceFailed }
            if rejectsUsageOnce { rejectsUsageOnce = false; throw OpenAIConnectionError.reauthRequired }
            return Data(#"{"rateLimits":{"limitId":"codex","primary":{"usedPercent":20,"windowDurationMins":300,"resetsAt":1800000000},"secondary":{"usedPercent":35,"windowDurationMins":10080,"resetsAt":1800300000}}}"#.utf8)
        case "account/logout":
            didLogout = true
            return Data("{}".utf8)
        default:
            throw OpenAIConnectionError.invalidResponse
        }
    }

    func waitForLogin(_ id: String) async throws {
        if failsLogin { throw OpenAIConnectionError.signInFailed }
        try writeCredentials(accessToken: "fixture-token")
    }

    private func writeCredentials(accessToken: String) throws {
        guard let profile else { throw OpenAIConnectionError.invalidResponse }
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: ["tokens": ["account_id": accountID, "access_token": accessToken]])
        try data.write(to: profile.appending(path: "auth.json"))
    }
    func stop() {}
}
