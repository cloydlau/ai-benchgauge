import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import LeaderboardCore
import Testing

struct OpenAIPlanExpiryTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let end = Date(timeIntervalSince1970: 1_800_086_400)

    private func store() -> OpenAIPlanExpiryStore {
        OpenAIPlanExpiryStore(fileURL: FileManager.default.temporaryDirectory
            .appending(path: "openai-expiry-\(UUID().uuidString)/dates.json"))
    }

    @Test func temporaryFailuresRetainOnlyTheSameAccountsFutureDateAcrossRestart() async throws {
        let store = store()
        defer { try? FileManager.default.removeItem(at: store.fileURL.deletingLastPathComponent()) }
        let body = Data(#"{"accounts":{"account-id":{"entitlement":{"expires_at":1800086400}}}}"#.utf8)
        let fresh = try await AccountQuotaClient.officialPlanExpiry(accessToken: "test", accountID: "account-id",
            transport: ExpiryTransport(body: body), store: store, now: now)
        #expect(fresh?.resetsAt == end)
        #expect(fresh?.dateSource == nil)
        let restarted = OpenAIPlanExpiryStore(fileURL: store.fileURL)
        for transport in [ExpiryTransport(status: 403), ExpiryTransport(status: 500),
                          ExpiryTransport(body: Data("not-json".utf8)),
                          ExpiryTransport(failure: URLError(.timedOut)),
                          ExpiryTransport(body: Data(repeating: 0, count: 1_048_577))] {
            let cached = try await AccountQuotaClient.officialPlanExpiry(accessToken: "test", accountID: "account-id",
                transport: transport, store: restarted, now: now)
            #expect(cached?.resetsAt == end)
            #expect(cached?.dateSource == .cached)
        }
        #expect(restarted.cachedWindow(accountID: "another-account", now: now) == nil)
        #expect(restarted.cachedWindow(accountID: "account-id", now: end) == nil)
        #expect(restarted.cachedWindow(accountID: "account-id", now: end.addingTimeInterval(1)) == nil)
    }

    @Test func successfulCheckReplacesOrInvalidatesTheSavedDate() async throws {
        let store = store()
        defer { try? FileManager.default.removeItem(at: store.fileURL.deletingLastPathComponent()) }
        try store.save(accountID: "account-id", expiresAt: end)
        let updated = try await AccountQuotaClient.officialPlanExpiry(accessToken: "test", accountID: "account-id",
            transport: ExpiryTransport(body: Data(#"{"accounts":{"default":{"entitlement":{"expires_at":1800172800}}}}"#.utf8)),
            store: store, now: now)
        #expect(updated?.resetsAt == end.addingTimeInterval(86_400))
        #expect(store.cachedWindow(accountID: "account-id", now: now)?.resetsAt == updated?.resetsAt)
        for body in [
            #"{"accounts":{"default":{"entitlement":{"has_active_subscription":false,"expires_at":1800172800}}}}"#,
            #"{"accounts":{"default":{"entitlement":{"renews_at":1800172800}}}}"#,
            #"{"accounts":{"other":{"account_id":"another-account","entitlement":{"expires_at":1800172800}}}}"#
        ] {
            try store.save(accountID: "account-id", expiresAt: end)
            let missing = try await AccountQuotaClient.officialPlanExpiry(accessToken: "test", accountID: "account-id",
                transport: ExpiryTransport(body: Data(body.utf8)), store: store, now: now)
            #expect(missing == nil)
            #expect(store.cachedWindow(accountID: "account-id", now: now) == nil)
        }
    }

    @Test func cancellationDoesNotReadOrEraseTheSavedDate() async throws {
        let store = store()
        defer { try? FileManager.default.removeItem(at: store.fileURL.deletingLastPathComponent()) }
        try store.save(accountID: "account-id", expiresAt: end)
        await #expect(throws: CancellationError.self) {
            try await AccountQuotaClient.officialPlanExpiry(accessToken: "test", accountID: "account-id",
                transport: ExpiryTransport(failure: CancellationError()), store: store, now: now)
        }
        #expect(store.cachedWindow(accountID: "account-id", now: now)?.resetsAt == end)
    }

    @Test func officialUsageRemainsFreshWhileItsDateUsesTheCache() async throws {
        let store = store()
        defer { try? FileManager.default.removeItem(at: store.fileURL.deletingLastPathComponent()) }
        try store.save(accountID: "account-id", expiresAt: end)
        let target = CCSwitchQuotaTarget(id: "official", shortName: "OpenAI", websiteURL: nil,
            kind: .officialNote, isCurrent: true, apiKey: nil, baseURL: nil, accessToken: "test", accountID: "account-id")
        let client = AccountQuotaClient(transport: ExpiryTransport(status: 403), now: { now }, openAIPlanExpiryStore: store)
        let card = try #require(try await client.refresh(targets: [target]).first)
        guard case let .windows(windows) = card.status else { Issue.record("usage must succeed"); return }
        #expect(windows.first?.utilization == 20)
        #expect(windows.last?.dateSource == .cached)
        #expect(!card.isStale)
        #expect(AccountQuotaFormatting.help(for: card, now: now).contains("已保存的查询结果"))
        #expect(AccountQuotaFormatting.plainSummary(for: card, now: now).contains("至"))
    }
}

private struct ExpiryTransport: AccountQuotaTransport {
    var status = 200
    var body = Data()
    var failure: (any Error)?

    func data(for request: URLRequest) async throws -> AccountQuotaHTTPResponse {
        if request.url?.path == "/backend-api/wham/usage" {
            return AccountQuotaHTTPResponse(statusCode: 200, headers: [:], body:
                Data(#"{"rate_limit":{"primary_window":{"used_percent":20,"limit_window_seconds":18000,"reset_at":1800003600}}}"#.utf8))
        }
        if let failure { throw failure }
        return AccountQuotaHTTPResponse(statusCode: status, headers: [:], body: body)
    }
}
