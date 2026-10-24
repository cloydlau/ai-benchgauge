import Foundation
import Testing
import LeaderboardCore
@testable import leaderboard_menu

private actor XAIRefreshTransport: AccountQuotaTransport {
    let holdsBilling: Bool
    let cancelsBilling: Bool
    let billingSucceeds: Bool
    var billingFinished = false
    var billingStarted = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var released = false
    init(holdsBilling: Bool, cancelsBilling: Bool, billingSucceeds: Bool) {
        self.holdsBilling = holdsBilling
        self.cancelsBilling = cancelsBilling
        self.billingSucceeds = billingSucceeds
    }

    func data(for request: URLRequest) async throws -> AccountQuotaHTTPResponse {
        switch request.url?.host {
        case "auth.x.ai":
            let json = request.httpMethod == "POST"
                ? #"{"access_token":"synthetic-access","expires_in":3600}"#
                : #"{"issuer":"https://auth.x.ai","token_endpoint":"https://auth.x.ai/oauth2/token"}"#
            return .init(statusCode: 200, headers: [:], body: Data(json.utf8))
        case "grok.com":
            billingStarted = true
            if holdsBilling && !released { await withCheckedContinuation { waiting.append($0) } }
            billingFinished = true
            if cancelsBilling { throw CancellationError() }
            if billingSucceeds {
                // Synthetic gRPC-web GrokCreditsConfig: weekly usage, 25% used.
                let body = request.httpMethod == "POST"
                    ? Data([0, 0, 0, 0, 11, 10, 9, 66, 2, 8, 2, 13, 0, 0, 200, 65])
                    : Data("{}".utf8)
                return .init(statusCode: 200, headers: [:], body: body)
            }
            return .init(statusCode: 401, headers: [:], body: Data())
        case "cli-chat-proxy.grok.com":
            return .init(statusCode: 200, headers: [:], body: Data(#"{"subscription_tier_display":"SuperGrok"}"#.utf8))
        default:
            if !released { await withCheckedContinuation { waiting.append($0) } }
            return .init(statusCode: 200, headers: [:], body: Data("{}".utf8))
        }
    }

    func release() {
        released = true
        let continuations = waiting
        waiting = []
        for continuation in continuations { continuation.resume() }
    }
}

@Suite(.serialized) @MainActor
struct XAIQuotaRefreshTests {
    private func fixture(holdsBilling: Bool, cancelsBilling: Bool = false,
                         billingSucceeds: Bool = false, initialXAIStatus: AccountQuotaChip.Status? = nil) throws -> (AppState, XAIRefreshTransport, URL) {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let auth = root.appending(path: "auth.json")
        try Data(#"{"default_account_id":"synthetic","accounts":{"synthetic":{"account_id":"synthetic","refresh_token":"synthetic-refresh"}}}"#.utf8).write(to: auth)
        let xai = CCSwitchQuotaTarget(id: "xai", shortName: "xAI", websiteURL: nil,
            kind: .xaiOAuth, isCurrent: false, apiKey: nil, baseURL: nil)
        let kimi = CCSwitchQuotaTarget(id: "kimi", shortName: "Kimi", websiteURL: nil,
            kind: .kimi, isCurrent: true, apiKey: "synthetic-key", baseURL: "https://quota-fixture.invalid")
        let transport = XAIRefreshTransport(holdsBilling: holdsBilling, cancelsBilling: cancelsBilling, billingSucceeds: billingSucceeds)
        let client = AccountQuotaClient(transport: transport, authFileURL: auth, xaiRefreshAllowed: { true })
        let loaded = CCSwitchQuotaLoad(result: .records([]), isInstalled: true,
            currentProviderID: "kimi", xaiAuthURL: auth, officialTargets: [],
            ccSwitchTargets: [kimi, xai], shouldAskClaudeKeychainConsent: false)
        let state = AppState(cache: LeaderboardCache(fileURL: root.appending(path: "cache.json")),
            defaults: UserDefaults(suiteName: "xai-refresh.\(UUID())")!, configuration: .init(previewCCSwitchState: .configured),
            quotaClient: client, quotaProviderLoad: { loaded })
        if let initialXAIStatus {
            state.applyVisualFixture(snapshot: .init(), chips: [
                AccountQuotaChip(id: "xai", shortName: "xAI", websiteURL: nil, kind: .xaiOAuth,
                    isCurrent: false, status: initialXAIStatus),
                AccountQuotaChip(id: "kimi", shortName: "Kimi", websiteURL: nil, kind: .kimi,
                    isCurrent: true, status: .windows([.init(name: "weekly_limit", utilization: 10, resetsAt: nil)]))
            ], language: .chinese, errors: [:], emptyState: nil, targets: [kimi, xai])
        }
        return (state, transport, root)
    }

    private func waitFor(_ condition: () async -> Bool) async throws {
        for _ in 0..<200 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("Quota state did not settle")
    }

    @Test func xaiResultAppearsWhileAnotherProviderIsStillChecking() async throws {
        let (state, transport, root) = try fixture(holdsBilling: false)
        defer { state.beginQuitting(); try? FileManager.default.removeItem(at: root) }
        state.refreshQuotas(minimumInterval: 0)
        try await waitFor { await transport.billingFinished }
        try await waitFor { state.quotaChips.first { $0.id == "xai" }?.status != .pending }
        #expect(state.quotaChips.first { $0.id == "xai" }?.status == .message(AccountQuotaMessage.reauthRequired))
        #expect(state.quotaChips.first { $0.id == "kimi" }?.status == .pending)
        await transport.release()
        try await waitFor { state.quotaChips.first { $0.id == "kimi" }?.status != .pending }
        #expect(state.quotaChips.first { $0.id == "xai" }?.status == .message(AccountQuotaMessage.reauthRequired))
    }

    @Test func unrelatedBackgroundRefreshCannotStrandAnInFlightXAIQuery() async throws {
        let (state, transport, root) = try fixture(holdsBilling: true)
        defer { state.beginQuitting(); try? FileManager.default.removeItem(at: root) }
        state.refreshQuotas(minimumInterval: 0)
        try await waitFor { await transport.billingStarted }
        state.refreshQuotas(minimumInterval: 0, inactiveScope: .xaiOAuthOnly)
        await transport.release()
        try await waitFor { state.quotaChips.first { $0.id == "xai" }?.status != .pending }
        #expect(state.quotaChips.first { $0.id == "xai" }?.status == .message(AccountQuotaMessage.reauthRequired))
        await transport.release()
    }

    @Test func backgroundRefreshRecoversAnAlreadyPendingInactiveXAIChip() async throws {
        let (state, transport, root) = try fixture(holdsBilling: false)
        defer { state.beginQuitting(); try? FileManager.default.removeItem(at: root) }
        state.refreshQuotas(minimumInterval: 0, inactiveScope: .xaiOAuthOnly)
        try await waitFor { await transport.billingFinished }
        try await waitFor { state.quotaChips.first { $0.id == "xai" }?.status != .pending }
        #expect(state.quotaChips.first { $0.id == "xai" }?.status == .message(AccountQuotaMessage.reauthRequired))
        await transport.release()
    }

    @Test func transportCancellationCannotLeaveTheChipChecking() async throws {
        let (state, transport, root) = try fixture(holdsBilling: false, cancelsBilling: true)
        defer { state.beginQuitting(); try? FileManager.default.removeItem(at: root) }
        state.refreshQuotas(minimumInterval: 0)
        try await waitFor { await transport.billingFinished }
        try await waitFor { state.quotaChips.first { $0.id == "xai" }?.status != .pending }
        #expect(state.quotaChips.first { $0.id == "xai" }?.status == .message(AccountQuotaMessage.queryFailed))
        await transport.release()
    }

    @Test(arguments: [false, true])
    func authorizationImmediatelyReplacesLoginPromptWhileOnlyXAIIsLoading(succeeds: Bool) async throws {
        let (state, transport, root) = try fixture(holdsBilling: true, billingSucceeds: succeeds,
            initialXAIStatus: .note(text: AccountQuotaMessage.notLoggedIn, help: AccountQuotaMessage.notLoggedInHelp))
        defer { state.beginQuitting(); try? FileManager.default.removeItem(at: root) }
        let kimiBefore = state.quotaChips.first { $0.id == "kimi" }
        state.refreshXAIQuotasAfterAuthorization(authFileURL: root.appending(path: "auth.json"))
        // No suspension or network completion is needed to replace “未登录”.
        #expect(state.quotaChips.first { $0.id == "xai" }?.status == .pending)
        try await waitFor { await transport.billingStarted }
        #expect(state.quotaChips.first { $0.id == "xai" }?.status == .pending)
        #expect(state.quotaChips.first { $0.id == "kimi" } == kimiBefore)
        await transport.release()
        try await waitFor { state.quotaChips.first { $0.id == "xai" }?.status != .pending }
        let status = state.quotaChips.first { $0.id == "xai" }?.status
        if succeeds {
            #expect(status == .windows([.init(name: "weekly_limit", utilization: 25, resetsAt: nil),
                .init(name: ParsedQuotaWindow.planExpiryName, utilization: 0, resetsAt: nil, subscriptionState: .active)]))
        } else {
            #expect(status == .message(AccountQuotaMessage.reauthRequired))
        }
        #expect(state.quotaChips.first { $0.id == "kimi" } == kimiBefore)
    }

    @Test func loginWatcherRefreshAlsoReplacesAnExpiredLoginPrompt() async throws {
        let (state, transport, root) = try fixture(holdsBilling: true,
            initialXAIStatus: .message(AccountQuotaMessage.reauthRequired))
        defer { state.beginQuitting(); try? FileManager.default.removeItem(at: root) }
        // The login-file watcher and provider discovery use the same xAI path.
        state.refreshQuotas(minimumInterval: 0)
        try await waitFor { await transport.billingStarted }
        #expect(state.quotaChips.first { $0.id == "xai" }?.status == .pending)
        await transport.release()
        try await waitFor { state.quotaChips.first { $0.id == "xai" }?.status != .pending }
        #expect(state.quotaChips.first { $0.id == "xai" }?.status == .message(AccountQuotaMessage.reauthRequired))
    }

    @Test func backgroundRefreshKeepsPreviouslyLoadedQuotaVisible() async throws {
        let loaded = AccountQuotaChip.Status.windows([.init(name: "weekly_limit", utilization: 35, resetsAt: nil)])
        let (state, transport, root) = try fixture(holdsBilling: true, initialXAIStatus: loaded)
        defer { state.beginQuitting(); try? FileManager.default.removeItem(at: root) }
        state.refreshQuotas(minimumInterval: 0)
        try await waitFor { await transport.billingStarted }
        #expect(state.quotaChips.first { $0.id == "xai" }?.status == loaded)
        await transport.release()
        try await waitFor { state.quotaChips.first { $0.id == "xai" }?.status != loaded }
    }
}
