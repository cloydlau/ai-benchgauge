import Foundation
import Testing
@testable import LeaderboardCore

struct GrokQuotaTests {
    private let now = ISO8601DateFormatter().date(from: "2026-09-28T12:00:00Z")!

    @Test
    func testWeeklyResetAndMonthlySubscriptionDeadlineStaySeparate() throws {
        let snapshot = try #require(GrokBillingParser.parse(credits(type: 2, end: "2026-10-05T12:00:00Z"), now: now))
        #expect((snapshot.windowName) == ("weekly_limit"))
        let expiry = try #require(GrokBillingParser.parseSubscriptionExpiry(Data(#"{"subscriptions":[{"status":"SUBSCRIPTION_STATUS_ACTIVE","tier":"SUBSCRIPTION_TIER_GROK_PRO","billingInterval":"BILLING_INTERVAL_MONTHLY","billingPeriodEnd":"2026-10-24T12:00:00Z"}]}"#.utf8)))
        let chip = chip([ParsedQuotaWindow(name: snapshot.windowName, utilization: snapshot.usedPercent, resetsAt: snapshot.resetsAt), expiry])
        #expect((AccountQuotaFormatting.plainSummary(for: chip, now: now)) == ("7d 75% · 至10月24日"))
        #expect((AccountQuotaFormatting.compactMenuBarQuota(for: chip)) == ("7d 75%"))
        #expect(!(AccountQuotaFormatting.isExhausted(chip)))
    }

    @Test
    func testMonthlyPeriodKeepsItsTypeNearTheDeadline() throws {
        let snapshot = try #require(GrokBillingParser.parse(credits(type: 1, end: "2026-09-30T12:00:00Z"), now: now))
        #expect((snapshot.windowName) == ("monthly"))
    }

    @Test
    func testUsageEndWinsOverLegacyAndHistoryDates() throws {
        let history = message(6, message(1, message(3, timestamp("2026-09-29T12:00:00Z"))))
        let snapshot = try #require(GrokBillingParser.parse(credits(type: 2, end: "2026-10-05T12:00:00Z", extra: message(5, timestamp("2026-10-24T12:00:00Z")) + history), now: now))
        #expect((snapshot.resetsAt) == (ISO8601DateFormatter().date(from: "2026-10-05T12:00:00Z")))
    }

    @Test
    func testZeroUsageDoesNotBorrowProductUsage() throws {
        let product = message(7, float(1, 80))
        let snapshot = try #require(GrokBillingParser.parse(credits(type: 2, end: "2026-10-05T12:00:00Z", percent: nil, extra: product), now: now))
        #expect((snapshot.usedPercent) == (0))
    }

    @Test
    func testHistoryOnlyResponseDoesNotInventQuota() {
        let history = message(1, message(6, message(1, timestamp("2026-10-24T12:00:00Z")) + float(1, 30)))
        #expect((GrokBillingParser.parse(history, now: now)) == nil)
    }

    @Test
    func testInactiveAndUnrelatedSubscriptionsDoNotSupplyExpiry() {
        let body = Data(#"{"subscriptions":[{"status":"SUBSCRIPTION_STATUS_INACTIVE","tier":"SUBSCRIPTION_TIER_GROK_PRO","billingPeriodEnd":"2026-12-24T12:00:00Z"},{"status":"SUBSCRIPTION_STATUS_ACTIVE","tier":"SUBSCRIPTION_TIER_X_BASIC","billingPeriodEnd":"2026-11-24T12:00:00Z"},{"status":"SUBSCRIPTION_STATUS_ACTIVE","tier":"SUBSCRIPTION_TIER_GROK_PRO","billingPeriodEnd":"invalid"}]}"#.utf8)
        #expect((GrokBillingParser.parseSubscriptionExpiry(body)) == nil)
    }

    @Test
    func testMissingSubscriptionDoesNotDisplayWeeklyResetAsExpiry() {
        let chip = chip([ParsedQuotaWindow(name: "weekly_limit", utilization: 25, resetsAt: now.addingTimeInterval(7 * 86_400))])
        #expect((AccountQuotaFormatting.plainSummary(for: chip, now: now)) == ("7d 75%"))
        #expect(!(AccountQuotaFormatting.help(for: chip, now: now).contains("截至")))
    }

    @Test
    func testClientFetchesSubscriptionAndKeepsUsageWhenItFails() async throws {
        for status in [200, 401, 503] {
            let auth = FileManager.default.temporaryDirectory.appending(path: "grok-quota-test-\(UUID().uuidString).json")
            try Data(#"{"default_account_id":"test","accounts":{"test":{"account_id":"test","refresh_token":"test-refresh","requires_reauth":false}}}"#.utf8).write(to: auth)
            defer { try? FileManager.default.removeItem(at: auth) }
            let body = credits(type: 2, end: "2026-10-05T12:00:00Z")
            let transport = GrokFixtureTransport(status: status, billingBody: body)
            let client = AccountQuotaClient(transport: transport, authFileURL: auth)
            let target = CCSwitchQuotaTarget(id: "xai", shortName: "xAI", websiteURL: nil, kind: .xaiOAuth, isCurrent: false, apiKey: nil, baseURL: nil)
            let result = try await client.refresh(targets: [target])
            let resultChip = try #require(result.first)
            #expect((AccountQuotaFormatting.plainSummary(for: resultChip, now: now)) == (status == 200 ? "7d 75% · 至10月24日" : "7d 75%"))
        }
    }

    private func chip(_ windows: [ParsedQuotaWindow]) -> AccountQuotaChip {
        AccountQuotaChip(id: "xai", shortName: "xAI", websiteURL: nil, kind: .xaiOAuth, isCurrent: false, status: .windows(windows))
    }

    private func credits(type: UInt64, end: String, percent: Float? = 25, extra: Data = Data()) -> Data {
        var config = extra + message(8, varintField(1, type) + message(2, timestamp("2026-09-28T12:00:00Z")) + message(3, timestamp(end)))
        if let percent { config += float(1, percent) }
        let payload = message(1, config)
        return Data([0, 0, 0, 0, UInt8(payload.count)]) + payload
    }

    private func timestamp(_ text: String) -> Data {
        varintField(1, UInt64(ISO8601DateFormatter().date(from: text)!.timeIntervalSince1970))
    }

    private func varint(_ value: UInt64) -> Data {
        var bytes: [UInt8] = [], value = value
        repeat { bytes.append(UInt8(value & 127) | (value >= 128 ? 128 : 0)); value >>= 7 } while value > 0
        return Data(bytes)
    }

    private func varintField(_ field: UInt64, _ value: UInt64) -> Data {
        varint(field << 3) + varint(value)
    }

    private func message(_ field: UInt64, _ body: Data) -> Data {
        varint(field << 3 | 2) + varint(UInt64(body.count)) + body
    }

    private func float(_ field: UInt64, _ value: Float) -> Data {
        let bits = value.bitPattern
        return varint(field << 3 | 5) + Data((0..<4).map { UInt8(truncatingIfNeeded: bits >> ($0 * 8)) })
    }
}

private struct GrokFixtureTransport: AccountQuotaTransport {
    let status: Int
    let billingBody: Data

    func data(for request: URLRequest) async throws -> AccountQuotaHTTPResponse {
        switch request.url?.absoluteString {
        case "https://auth.x.ai/.well-known/openid-configuration":
            return AccountQuotaHTTPResponse(statusCode: 200, headers: [:], body: Data(#"{"issuer":"https://auth.x.ai","token_endpoint":"https://auth.x.ai/oauth2/token"}"#.utf8))
        case "https://auth.x.ai/oauth2/token":
            return AccountQuotaHTTPResponse(statusCode: 200, headers: [:], body: Data(#"{"access_token":"test-access","expires_in":3600}"#.utf8))
        case "https://grok.com/grok_api_v2.GrokBuildBilling/GetGrokCreditsConfig":
            return AccountQuotaHTTPResponse(statusCode: 200, headers: [:], body: billingBody)
        case "https://grok.com/rest/subscriptions":
            #expect((request.httpMethod) == ("GET"))
            #expect((request.value(forHTTPHeaderField: "Authorization")) == ("Bearer test-access"))
            return AccountQuotaHTTPResponse(statusCode: status, headers: [:], body: Data(#"{"subscriptions":[{"status":"SUBSCRIPTION_STATUS_ACTIVE","tier":"SUBSCRIPTION_TIER_GROK_PRO","billingPeriodEnd":"2026-10-24T12:00:00Z"}]}"#.utf8))
        default:
            recordFailure("unexpected quota endpoint")
            return AccountQuotaHTTPResponse(statusCode: 500, headers: [:], body: Data())
        }
    }
}
