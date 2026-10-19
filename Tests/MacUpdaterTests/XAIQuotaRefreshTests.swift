import Foundation
import Testing
import LeaderboardCore
@testable import leaderboard_menu

private actor XAIRefreshTransport: AccountQuotaTransport {
    let holdsBilling: Bool
    let cancelsBilling: Bool
    var billingFinished = false
    var billingStarted = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var released = false
    init(holdsBilling: Bool, cancelsBilling: Bool) {
        self.holdsBilling = holdsBilling
        self.cancelsBilling = cancelsBilling
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
            return .init(statusCode: 401, headers: [:], body: Data())
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
    private func fixture(holdsBilling: Bool, cancelsBilling: Bool = false) throws -> (AppState, XAIRefreshTransport, URL) {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let auth = root.appending(path: "auth.json")
        try Data(#"{"default_account_id":"synthetic","accounts":{"synthetic":{"account_id":"synthetic","refresh_token":"synthetic-refresh"}}}"#.utf8).write(to: auth)
        let xai = CCSwitchQuotaTarget(id: "xai", shortName: "xAI", websiteURL: nil,
            kind: .xaiOAuth, isCurrent: false, apiKey: nil, baseURL: nil)
        let kimi = CCSwitchQuotaTarget(id: "kimi", shortName: "Kimi", websiteURL: nil,
            kind: .kimi, isCurrent: true, apiKey: "synthetic-key", baseURL: "https://quota-fixture.invalid")
        let transport = XAIRefreshTransport(holdsBilling: holdsBilling, cancelsBilling: cancelsBilling)
        let client = AccountQuotaClient(transport: transport, authFileURL: auth, xaiRefreshAllowed: { true })
        let loaded = CCSwitchQuotaLoad(result: .records([]), isInstalled: true,
            currentProviderID: "kimi", xaiAuthURL: auth, officialTargets: [],
            ccSwitchTargets: [kimi, xai], shouldAskClaudeKeychainConsent: false)
        let state = AppState(cache: LeaderboardCache(fileURL: root.appending(path: "cache.json")),
            defaults: UserDefaults(suiteName: "xai-refresh.\(UUID())")!, configuration: .init(previewCCSwitchState: .configured),
            quotaClient: client, quotaProviderLoad: { loaded })
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
}
