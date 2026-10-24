import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
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
    func testMissingSubscriptionNeverDisplaysWeeklyResetAsPlanDate() {
        let chip = chip([ParsedQuotaWindow(name: "weekly_limit", utilization: 25, resetsAt: now.addingTimeInterval(7 * 86_400))])
        #expect((AccountQuotaFormatting.plainSummary(for: chip, now: now)) == ("7d 75%"))
        let dated = self.chip([ParsedQuotaWindow(name: ParsedQuotaWindow.planExpiryName, utilization: 0, resetsAt: now.addingTimeInterval(30 * 86_400))])
        #expect(AccountQuotaFormatting.sortedChips([chip, dated]).first?.status == dated.status)
        #expect(AccountQuotaFormatting.compactMenuBarQuota(for: chip) == "7d 75%")
        #expect(!(AccountQuotaFormatting.help(for: chip, now: now).contains("截至")))
    }

    @Test
    func testMissingOrPastWeeklyResetDoesNotInventADate() {
        for reset in [nil, now, now.addingTimeInterval(-60)] as [Date?] {
            let chip = chip([ParsedQuotaWindow(name: "weekly_limit", utilization: 25, resetsAt: reset)])
            #expect(AccountQuotaFormatting.plainSummary(for: chip, now: now) == "7d 75%")
        }
    }

    @Test
    func testCachedPlanDateRetainsTodaysClockAndTranslates() {
        let chip = chip([ParsedQuotaWindow(name: "weekly_limit", utilization: 25, resetsAt: now.addingTimeInterval(7 * 86_400)),
                         ParsedQuotaWindow(name: ParsedQuotaWindow.planExpiryName, utilization: 0,
                            resetsAt: now.addingTimeInterval(90 * 60), dateSource: .cached)])
        let text = AccountQuotaFormatting.runs(for: chip, now: now).last?.text ?? ""
        #expect(text == "至9月28日21时30分")
        #expect(AppLanguage.english.quotaText(text) == "to Sep 28, 21:30")
        #expect(AppLanguage.traditionalChinese.quotaText(text) == "至9月28日21時30分")
        #expect(AppLanguage.english.quotaText("至10月5日") == "to Oct 5")
        #expect(AccountQuotaFormatting.help(for: chip, now: now).contains("已保存的查询结果"))
    }

    @Test
    func testClientFetchesSubscriptionAndKeepsUsageWhenItFails() async throws {
        for status in [200, 401, 403, 503] {
            let auth = FileManager.default.temporaryDirectory.appending(path: "grok-quota-test-\(UUID().uuidString).json")
            try Data(#"{"default_account_id":"test","accounts":{"test":{"account_id":"test","refresh_token":"test-refresh","requires_reauth":false}}}"#.utf8).write(to: auth)
            defer { try? FileManager.default.removeItem(at: auth) }
            let body = credits(type: 2, end: "2026-10-05T12:00:00Z")
            let transport = GrokFixtureTransport(status: status, billingBody: body)
            let fixedNow = now
            let client = AccountQuotaClient(transport: transport, authFileURL: auth, now: { fixedNow }, xaiRefreshAllowed: { true })
            let target = CCSwitchQuotaTarget(id: "xai", shortName: "xAI", websiteURL: nil, kind: .xaiOAuth, isCurrent: false, apiKey: nil, baseURL: nil)
            let result = try await client.refresh(targets: [target])
            let resultChip = try #require(result.first)
            #expect((AccountQuotaFormatting.plainSummary(for: resultChip, now: now)) == (status == 200 ? "7d 75% · 至10月24日" : "7d 75%"))
        }
    }

    @Test
    func testWebsiteDateIsRejectedWhenIdentityQueryFailsOrLoginChanges() async throws {
        for (status, switchAccount) in [(403, false), (503, false), (200, true)] {
            let directory = FileManager.default.temporaryDirectory.appending(path: "grok-web-identity-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let auth = directory.appending(path: "auth.json")
            try Data(#"{"default_account_id":"test","accounts":{"test":{"account_id":"test","refresh_token":"test-refresh","requires_reauth":false}}}"#.utf8).write(to: auth)
            let store = XAISubscriptionDateStore(fileURL: directory.appending(path: "dates.json"))
            let fixedNow = now
            let transport = GrokIdentityFixtureTransport(base: GrokFixtureTransport(status: 403, billingBody: credits(type: 2, end: "2026-10-05T12:00:00Z")),
                identityStatus: status, switchAuth: switchAccount ? auth : nil)
            let client = AccountQuotaClient(transport: transport, authFileURL: auth, now: { fixedNow }, xaiSubscriptionDateStore: store, xaiRefreshAllowed: { true })
            let body = Data(#"{"subscriptions":[{"xaiUserId":"canonical-user","status":"SUBSCRIPTION_STATUS_ACTIVE","tier":"SUBSCRIPTION_TIER_GROK_PRO","billingPeriodEnd":"2026-11-18T12:00:00Z"}]}"#.utf8)
            #expect(try await !client.captureXAIWebsiteSubscription(body))
            #expect(store.record(accountID: "test", now: now) == nil)
            #expect(store.record(accountID: "other", now: now) == nil)
        }
    }

    @Test
    func testWebsiteDateIsVerifiedAgainstTheLiveOAuthAccount() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "grok-web-date-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let auth = directory.appending(path: "auth.json")
        try Data(#"{"default_account_id":"test","accounts":{"test":{"account_id":"test","refresh_token":"test-refresh","requires_reauth":false}}}"#.utf8).write(to: auth)
        let store = XAISubscriptionDateStore(fileURL: directory.appending(path: "dates.json"))
        let fixedNow = now
        let client = AccountQuotaClient(transport: GrokFixtureTransport(status: 403, billingBody: credits(type: 2, end: "2026-10-05T12:00:00Z")),
            authFileURL: auth, now: { fixedNow }, xaiSubscriptionDateStore: store, xaiRefreshAllowed: { true })
        func response(userID: String?, date: String = "2026-11-18T12:00:00Z") throws -> Data {
            var record = ["status": "SUBSCRIPTION_STATUS_ACTIVE", "tier": "SUBSCRIPTION_TIER_GROK_PRO", "billingPeriodEnd": date]
            record["xaiUserId"] = userID
            return try JSONSerialization.data(withJSONObject: ["subscriptions": [record]])
        }
        #expect(try await !client.captureXAIWebsiteSubscription(response(userID: "other-user")))
        #expect(try await client.captureXAIWebsiteSubscription(response(userID: "canonical-user", date: "2026-09-01T12:00:00Z")))
        #expect(store.record(accountID: "test", now: now)?.periodEnd == ISO8601DateFormatter().date(from: "2026-09-01T12:00:00Z"))
        #expect(try await client.captureXAIWebsiteSubscription(response(userID: nil)))
        #expect(store.record(accountID: "test", now: now)?.periodEnd == ISO8601DateFormatter().date(from: "2026-11-18T12:00:00Z"))
        #expect(try await client.captureXAIWebsiteSubscription(response(userID: "canonical-user")))
        let target = CCSwitchQuotaTarget(id: "xai", shortName: "xAI", websiteURL: nil, kind: .xaiOAuth, isCurrent: false, apiKey: nil, baseURL: nil)
        let chip = try #require(try await client.refresh(targets: [target]).first)
        #expect(AccountQuotaFormatting.plainSummary(for: chip, now: now) == "7d 75% · 至11月18日")
        #expect(AccountQuotaFormatting.requiresXAISubscriptionConnection(chip))
        #expect(AccountQuotaFormatting.help(for: chip, now: now).contains(AccountQuotaMessage.xaiSubscriptionHelp))
        #expect(!AccountQuotaFormatting.requiresXAISignIn(chip))
    }

    @Test
    func testDisplayFollowsTheReturnedSubscriptionDate() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "grok-live-date-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let auth = directory.appending(path: "auth.json")
        try Data(#"{"default_account_id":"test","accounts":{"test":{"account_id":"test","refresh_token":"test-refresh","requires_reauth":false}}}"#.utf8).write(to: auth)
        let fixedNow = now
        let client = AccountQuotaClient(transport: GrokFixtureTransport(status: 200,
            billingBody: credits(type: 2, end: "2026-10-05T12:00:00Z"), subscriptionEnd: "2026-11-18T12:00:00Z"),
            authFileURL: auth, now: { fixedNow }, xaiRefreshAllowed: { true })
        let target = CCSwitchQuotaTarget(id: "xai", shortName: "xAI", websiteURL: nil, kind: .xaiOAuth, isCurrent: false, apiKey: nil, baseURL: nil)
        let chip = try #require(try await client.refresh(targets: [target]).first)
        #expect(AccountQuotaFormatting.plainSummary(for: chip, now: now) == "7d 75% · 至11月18日")
    }

    @Test
    func testSubscriptionOutageReusesLastGoodDateForSameClientLogin() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "grok-outage-date-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let auth = directory.appending(path: "auth.json")
        try Data(#"{"default_account_id":"test","accounts":{"test":{"account_id":"test","refresh_token":"test-refresh","requires_reauth":false}}}"#.utf8).write(to: auth)
        let store = XAISubscriptionDateStore(fileURL: directory.appending(path: "dates.json"))
        let fixedNow = now
        let success = GrokFixtureTransport(status: 200, billingBody: credits(type: 2, end: "2026-10-05T12:00:00Z"), subscriptionEnd: "2026-11-18T12:00:00Z")
        let outage = GrokFixtureTransport(status: 503, billingBody: credits(type: 2, end: "2026-10-05T12:00:00Z"))
        let client = AccountQuotaClient(
            transport: GrokSubscriptionOutageTransport(success: success, outage: outage),
            authFileURL: auth,
            now: { fixedNow },
            xaiSubscriptionDateStore: store,
            xaiRefreshAllowed: { true }
        )
        let target = CCSwitchQuotaTarget(id: "xai", shortName: "xAI", websiteURL: nil, kind: .xaiOAuth, isCurrent: false, apiKey: nil, baseURL: nil)
        let live = try #require(try await client.refresh(targets: [target]).first)
        #expect(AccountQuotaFormatting.plainSummary(for: live, now: now) == "7d 75% · 至11月18日")
        #expect(!AccountQuotaFormatting.requiresXAISubscriptionConnection(live))
        try FileManager.default.removeItem(at: store.fileURL)
        let retained = try #require(try await client.refresh(targets: [target]).first)
        #expect(AccountQuotaFormatting.plainSummary(for: retained, now: now) == "7d 75% · 至11月18日")
        #expect(AccountQuotaFormatting.requiresXAISubscriptionConnection(retained))
        #expect(store.record(accountID: "test", now: now)?.periodEnd == ISO8601DateFormatter().date(from: "2026-11-18T12:00:00Z"))
    }

    @Test
    func testLegacyManualDateCannotSupplyAPlanDateAfterSubscriptionFailure() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "grok-manual-date-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let auth = directory.appending(path: "auth.json")
        try Data(#"{"default_account_id":"test","accounts":{"test":{"account_id":"test","refresh_token":"test-refresh","requires_reauth":false}}}"#.utf8).write(to: auth)
        let store = XAISubscriptionDateStore(fileURL: directory.appending(path: "dates.json"))
        try Data(#"[{"accountID":"test","periodEnd":"2026-10-24T12:00:00Z","source":"userConfirmed"},{"accountID":"other","periodEnd":"2026-11-18T12:00:00Z","source":"cached"}]"#.utf8).write(to: store.fileURL)
        #expect(store.record(accountID: "test", now: now) == nil)
        #expect(store.record(accountID: "other", now: now) != nil)
        let fixedNow = now
        let client = AccountQuotaClient(transport: GrokFixtureTransport(status: 403, billingBody: credits(type: 2, end: "2026-10-05T12:00:00Z")),
            authFileURL: auth, now: { fixedNow }, xaiSubscriptionDateStore: store, xaiRefreshAllowed: { true })
        let target = CCSwitchQuotaTarget(id: "xai", shortName: "xAI", websiteURL: nil, kind: .xaiOAuth, isCurrent: false, apiKey: nil, baseURL: nil)
        let chip = try #require(try await client.refresh(targets: [target]).first)
        #expect(AccountQuotaFormatting.plainSummary(for: chip, now: now) == "7d 75%")
    }

    @Test
    func testCachedDateIsAccountScopedAndLiveSubscriptionWins() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "grok-dates-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let auth = directory.appending(path: "auth.json")
        try Data(#"{"default_account_id":"test","accounts":{"test":{"account_id":"test","refresh_token":"test-refresh","requires_reauth":false}}}"#.utf8).write(to: auth)
        let store = XAISubscriptionDateStore(fileURL: directory.appending(path: "dates.json"))
        let end = ISO8601DateFormatter().date(from: "2026-10-24T00:00:00+08:00")!
        let fixedNow = now
        let target = CCSwitchQuotaTarget(id: "xai", shortName: "xAI", websiteURL: nil, kind: .xaiOAuth, isCurrent: false, apiKey: nil, baseURL: nil)
        for (accountID, date, status, expected) in [
            ("other", end, 403, "7d 75%"),
            ("test", now.addingTimeInterval(-60), 403, "7d 75% · 至9月28日19时59分"),
            ("test", end, 403, "7d 75% · 至10月24日"),
            ("test", end.addingTimeInterval(31 * 86_400), 200, "7d 75% · 至10月24日"),
        ] {
            try store.save(.init(accountID: accountID, periodEnd: date, source: .cached))
            let client = AccountQuotaClient(transport: GrokFixtureTransport(status: status, billingBody: credits(type: 2, end: "2026-10-05T12:00:00Z")),
                authFileURL: auth, now: { fixedNow }, xaiSubscriptionDateStore: store, xaiRefreshAllowed: { true })
            let chip = try #require(try await client.refresh(targets: [target]).first)
            #expect(AccountQuotaFormatting.plainSummary(for: chip, now: now) == expected)
            if status == 200 {
                #expect(store.record(accountID: "test", now: now)?.source == .cached)
                #expect(!AccountQuotaFormatting.help(for: chip, now: now).contains("已保存的查询结果"))
            }
        }
        // A later subscription outage reuses the actual API date, not the older cached date.
        let client = AccountQuotaClient(transport: GrokFixtureTransport(status: 403, billingBody: credits(type: 2, end: "2026-10-05T12:00:00Z")),
            authFileURL: auth, now: { fixedNow }, xaiSubscriptionDateStore: store, xaiRefreshAllowed: { true })
        let cached = try #require(try await client.refresh(targets: [target]).first)
        #expect(AccountQuotaFormatting.plainSummary(for: cached, now: now) == "7d 75% · 至10月24日")
        #expect(AccountQuotaFormatting.help(for: cached, now: now).contains("已保存的查询结果"))
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
    var subscriptionEnd: String = "2026-10-24T12:00:00Z"

    func data(for request: URLRequest) async throws -> AccountQuotaHTTPResponse {
        switch request.url?.absoluteString {
        case "https://auth.x.ai/.well-known/openid-configuration":
            return AccountQuotaHTTPResponse(statusCode: 200, headers: [:], body: Data(#"{"issuer":"https://auth.x.ai","token_endpoint":"https://auth.x.ai/oauth2/token"}"#.utf8))
        case "https://auth.x.ai/oauth2/token":
            return AccountQuotaHTTPResponse(statusCode: 200, headers: [:], body: Data(#"{"access_token":"test-access","expires_in":3600}"#.utf8))
        case "https://cli-chat-proxy.grok.com/v1/user?include=subscription":
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-access")
            #expect(request.value(forHTTPHeaderField: "X-XAI-Token-Auth") == "xai-grok-cli")
            return AccountQuotaHTTPResponse(statusCode: 200, headers: [:], body: Data(#"{"userId":"canonical-user","subscriptionTier":"SuperGrok"}"#.utf8))
        case "https://cli-chat-proxy.grok.com/v1/settings":
            return AccountQuotaHTTPResponse(statusCode: 200, headers: [:], body: Data(#"{"subscription_tier_display":"SuperGrok"}"#.utf8))
        case "https://grok.com/grok_api_v2.GrokBuildBilling/GetGrokCreditsConfig":
            return AccountQuotaHTTPResponse(statusCode: 200, headers: [:], body: billingBody)
        case "https://grok.com/rest/subscriptions":
            #expect((request.httpMethod) == ("GET"))
            #expect((request.value(forHTTPHeaderField: "Authorization")) == ("Bearer test-access"))
            let body = try JSONSerialization.data(withJSONObject: ["subscriptions": [[
                "status": "SUBSCRIPTION_STATUS_ACTIVE", "tier": "SUBSCRIPTION_TIER_GROK_PRO", "billingPeriodEnd": subscriptionEnd
            ]]])
            return AccountQuotaHTTPResponse(statusCode: status, headers: [:], body: body)
        default:
            recordFailure("unexpected quota endpoint")
            return AccountQuotaHTTPResponse(statusCode: 500, headers: [:], body: Data())
        }
    }
}

private struct GrokEntitlementTransport: AccountQuotaTransport {
    let base: GrokFixtureTransport
    let settings: String
    var settingsStatus = 200
    var subscriptionBody: String? = nil
    var settingsFailure: URLError.Code? = nil
    func data(for request: URLRequest) async throws -> AccountQuotaHTTPResponse {
        if request.url == XaiEndpointValidator.subscriptionSettingsURL {
            if let settingsFailure { throw URLError(settingsFailure) }
            #expect(request.value(forHTTPHeaderField: "X-XAI-Token-Auth") == "xai-grok-cli")
            return .init(statusCode: settingsStatus, headers: [:], body: Data(settings.utf8))
        }
        if request.url == XaiEndpointValidator.subscriptionsURL, let subscriptionBody {
            return .init(statusCode: 200, headers: [:], body: Data(subscriptionBody.utf8))
        }
        return try await base.data(for: request)
    }
}

extension GrokQuotaTests {
    @Test func aStaleActiveRecordRequiresTheCurrentTierButKeepsItsReportedDate() async throws {
        let auth = FileManager.default.temporaryDirectory.appending(path: "grok-stale-active-\(UUID()).json")
        try Data(#"{"default_account_id":"test","accounts":{"test":{"account_id":"test","refresh_token":"test-refresh"}}}"#.utf8).write(to: auth)
        defer { try? FileManager.default.removeItem(at: auth) }
        for (tier, expected): (String, ParsedSubscriptionState) in [("Free", .inactive), ("SuperGrok", .active)] {
            let transport = GrokEntitlementTransport(base: .init(status: 200,
                billingBody: credits(type: 2, end: "2026-10-05T12:00:00Z", percent: nil), subscriptionEnd: "2026-09-27T12:00:00Z"),
                settings: "{\"subscription_tier_display\":\"\(tier)\"}")
            let tokens = XAIAccessTokens(refreshAllowed: { true })
            guard case let .windows(windows) = try await tokens.billing(transport: transport, authFileURL: auth, now: now) else {
                Issue.record("A stale active record must be checked against current entitlement"); continue
            }
            #expect(windows.last?.subscriptionState == expected)
            #expect(windows.last?.resetsAt == ISO8601DateFormatter().date(from: "2026-09-27T12:00:00Z"))
            #expect(AccountQuotaFormatting.plainSummary(for: chip(windows), now: now)
                == (expected == .inactive ? "订阅已过期" : "7d 100%") + " · 至9月27日")
        }
    }

    @Test func unavailablePlansStayOutOfUsableQuotaOrderingAndExhaustion() {
        func plan(_ id: String, _ state: ParsedSubscriptionState) -> AccountQuotaChip {
            .init(id: id, shortName: "xAI", websiteURL: nil, kind: .xaiOAuth, isCurrent: false,
                status: .windows([.init(name: "weekly_limit", utilization: 0, resetsAt: nil),
                    .init(name: ParsedQuotaWindow.planExpiryName, utilization: 0, resetsAt: nil, subscriptionState: state)]))
        }
        let free = plan("free", .inactive), unknown = plan("unknown", .unverified), paid = plan("paid", .active)
        #expect(AccountQuotaFormatting.plainSummary(for: free, now: now) == "未订购")
        #expect(AccountQuotaFormatting.plainSummary(for: unknown, now: now) == "套餐待核实")
        #expect(!AccountQuotaFormatting.isExhausted(free))
        #expect(!AccountQuotaFormatting.isExhausted(unknown))
        #expect(AccountQuotaFormatting.sortedChips([unknown, free, paid]).map(\.id) == ["paid", "free", "unknown"])
    }

    @Test func anExpiredInMemoryBoundarySurvivesLossOfTheDiskCache() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "grok-memory-boundary-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let auth = root.appending(path: "auth.json")
        try Data(#"{"default_account_id":"test","accounts":{"test":{"account_id":"test","refresh_token":"test-refresh"}}}"#.utf8).write(to: auth)
        let dates = XAISubscriptionDateStore(fileURL: root.appending(path: "dates.json"))
        let body = credits(type: 2, end: "2026-10-05T12:00:00Z", percent: nil)
        let transport = GrokSubscriptionOutageTransport(
            success: .init(status: 200, billingBody: body, subscriptionEnd: "2026-09-27T12:00:00Z"),
            outage: .init(status: 503, billingBody: body), settingsBody: "{}")
        let fixedNow = now
        let client = AccountQuotaClient(transport: transport, authFileURL: auth, now: { fixedNow },
            xaiSubscriptionDateStore: dates, xaiRefreshAllowed: { true })
        let target = CCSwitchQuotaTarget(id: "xai", shortName: "xAI", websiteURL: nil, kind: .xaiOAuth,
            isCurrent: true, apiKey: nil, baseURL: nil)
        let live = try #require(try await client.refresh(targets: [target]).first)
        #expect(AccountQuotaFormatting.plainSummary(for: live, now: now) == "套餐待核实 · 至9月27日")
        try FileManager.default.removeItem(at: dates.fileURL)
        let retained = try #require(try await client.refresh(targets: [target]).first)
        #expect(AccountQuotaFormatting.plainSummary(for: retained, now: now) == "套餐待核实 · 至9月27日")
        #expect(dates.record(accountID: "test", now: now)?.subscriptionState == .unverified)
        #expect(dates.record(accountID: "test", now: now)?.periodEnd == ISO8601DateFormatter().date(from: "2026-09-27T12:00:00Z"))
    }

    @Test func aTierNetworkFailureIsUnverifiedAndCancellationStillPropagates() async throws {
        let auth = FileManager.default.temporaryDirectory.appending(path: "grok-tier-\(UUID()).json")
        try Data(#"{"default_account_id":"test","accounts":{"test":{"account_id":"test","refresh_token":"test-refresh"}}}"#.utf8).write(to: auth)
        defer { try? FileManager.default.removeItem(at: auth) }
        for error: URLError.Code in [.networkConnectionLost, .cancelled] {
            let tokens = XAIAccessTokens(refreshAllowed: { true })
            let transport = GrokEntitlementTransport(base: .init(status: 403,
                billingBody: credits(type: 2, end: "2026-10-05T12:00:00Z", percent: nil)), settings: "{}", settingsFailure: error)
            if error == .cancelled {
                await #expect(throws: CancellationError.self) { try await tokens.billing(transport: transport, authFileURL: auth, now: now) }
            } else {
                guard case let .windows(windows) = try await tokens.billing(transport: transport, authFileURL: auth, now: now) else {
                    Issue.record("An entitlement outage must preserve the independently fetched usage"); continue
                }
                #expect(windows.first?.utilization == 0)
                #expect(windows.last?.subscriptionState == .unverified)
                #expect(AccountQuotaFormatting.plainSummary(for: chip(windows), now: now) == "套餐待核实")
            }
        }
    }

    @Test func expiredCacheSurvivesTheBoundaryAndZeroUsageRequiresCurrentEntitlement() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "grok-expired-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let auth = root.appending(path: "auth.json")
        try Data(#"{"default_account_id":"test","accounts":{"test":{"account_id":"test","refresh_token":"test-refresh"}}}"#.utf8).write(to: auth)
        let end = now.addingTimeInterval(-3600)
        let fixedNow = now
        for (settings, status, expected) in [
            (#"{"subscription_tier_display":"Free"}"#, 200, "订阅已过期"),
            (#"{"subscription_tier_display":"SuperGrok"}"#, 200, "7d 100%"),
            (#"{}"#, 200, "套餐待核实"),
            (#"{"subscription_tier_display":"Free"}"#, 503, "套餐待核实")
        ] {
            let dates = XAISubscriptionDateStore(fileURL: root.appending(path: UUID().uuidString + ".json"))
            try dates.save(.init(accountID: "test", periodEnd: end, source: .cached))
            try dates.save(.init(accountID: "other", periodEnd: now.addingTimeInterval(86400), source: .cached))
            #expect(dates.record(accountID: "test", now: now)?.periodEnd == end)
            let transport = GrokEntitlementTransport(base: .init(status: 403,
                billingBody: credits(type: 2, end: "2026-10-05T12:00:00Z", percent: nil)), settings: settings, settingsStatus: status)
            let client = AccountQuotaClient(transport: transport, authFileURL: auth, now: { fixedNow },
                xaiSubscriptionDateStore: dates, xaiRefreshAllowed: { true })
            let target = CCSwitchQuotaTarget(id: "xai", shortName: "xAI", websiteURL: nil, kind: .xaiOAuth, isCurrent: true, apiKey: nil, baseURL: nil)
            let result = try #require(try await client.refresh(targets: [target]).first)
            let summary = AccountQuotaFormatting.plainSummary(for: result, now: now)
            #expect(summary == expected + " · " + AccountQuotaFormatting.periodEndPhrase(until: end, now: now))
            if expected != "7d 100%" {
                #expect(!summary.contains("100%"))
                #expect(AccountQuotaFormatting.compactMenuBarQuota(for: result) == nil)
                #expect(AccountQuotaFormatting.lowestRemainingPercent(for: result) == nil)
                #expect(!QuotaAlerts.isConclusive(result.status))
                #expect(!AccountQuotaFormatting.help(for: result, now: now).contains("7d 100%"))
            }
            #expect(dates.record(accountID: "other", now: now)?.periodEnd == now.addingTimeInterval(86400))
        }
    }

    @Test func endedSubscriptionRecordsKeepTheirDateButActiveRenewalsWin() throws {
        let ended = #"{"status":"SUBSCRIPTION_STATUS_INACTIVE","tier":"SUBSCRIPTION_TIER_GROK_PRO","billingPeriodEnd":"2026-09-27T12:00:00Z"}"#
        let active = #"{"status":"SUBSCRIPTION_STATUS_ACTIVE","tier":"SUBSCRIPTION_TIER_GROK_PRO","billingPeriodEnd":"2026-10-24T12:00:00Z"}"#
        func parse(_ records: String) -> ParsedQuotaWindow? {
            GrokBillingParser.parseSubscriptionExpiry(Data("{\"subscriptions\":[\(records)]}".utf8), now: now)
        }
        #expect(parse(ended)?.subscriptionState == .inactive)
        #expect(parse(ended)?.resetsAt == ISO8601DateFormatter().date(from: "2026-09-27T12:00:00Z"))
        #expect(parse(ended + "," + active)?.subscriptionState == .active)
        #expect(parse(active + "," + ended)?.subscriptionState == .active)
        let renewed = active.replacingOccurrences(of: "2026-10-24", with: "2026-11-24")
        #expect(parse(active + "," + renewed)?.resetsAt == ISO8601DateFormatter().date(from: "2026-11-24T12:00:00Z"))
        let olderEnded = ended.replacingOccurrences(of: "2026-09-27", with: "2026-08-27")
        #expect(parse(olderEnded + "," + ended)?.resetsAt == ISO8601DateFormatter().date(from: "2026-09-27T12:00:00Z"))
        #expect(parse(ended.replacingOccurrences(of: "2026-09-27", with: "2026-11-27")) == nil)
        #expect(GrokBillingParser.parseSubscriptionExpiry(Data("{\"subscriptions\":[\(ended)]}".utf8), accountID: "test", now: now)?.subscriptionState == .inactive)
        #expect(GrokBillingParser.parseSubscriptionExpiry(Data(#"{"subscriptions":[{"xaiUserId":"other","status":"SUBSCRIPTION_STATUS_INACTIVE","tier":"SUBSCRIPTION_TIER_GROK_PRO","billingPeriodEnd":"2026-09-27T12:00:00Z"}]}"#.utf8), accountID: "test", now: now) == nil)
        #expect(GrokBillingParser.parseSubscriptionState(Data(#"{"subscription_tier_display":"mystery-future-plan"}"#.utf8)) == nil)
        #expect(GrokBillingParser.parseSubscriptionState(Data(#"{"subscription_tier_display":false}"#.utf8)) == nil)
    }

    @Test func liveEndedSubscriptionKeepsItsDateAcrossRestartAndAnOutage() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "grok-ended-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let auth = root.appending(path: "auth.json")
        try Data(#"{"default_account_id":"test","accounts":{"test":{"account_id":"test","refresh_token":"test-refresh"}}}"#.utf8).write(to: auth)
        let dates = XAISubscriptionDateStore(fileURL: root.appending(path: "dates.json"))
        let fixedNow = now
        let target = CCSwitchQuotaTarget(id: "xai", shortName: "xAI", websiteURL: nil, kind: .xaiOAuth, isCurrent: true, apiKey: nil, baseURL: nil)
        let transport = GrokEntitlementTransport(base: .init(status: 403,
            billingBody: credits(type: 2, end: "2026-10-05T12:00:00Z", percent: nil)), settings: "{}",
            subscriptionBody: #"{"subscriptions":[{"status":"SUBSCRIPTION_STATUS_INACTIVE","tier":"SUBSCRIPTION_TIER_GROK_PRO","billingPeriodEnd":"2026-09-27T12:00:00Z"}]}"#)
        let client = AccountQuotaClient(transport: transport, authFileURL: auth, now: { fixedNow },
            xaiSubscriptionDateStore: dates, xaiRefreshAllowed: { true })
        let first = try #require(try await client.refresh(targets: [target]).first)
        #expect(AccountQuotaFormatting.plainSummary(for: first, now: now) == "订阅已过期 · 至9月27日")
        #expect(dates.record(accountID: "test", now: now)?.subscriptionState == .inactive)
        let restarted = AccountQuotaClient(transport: GrokEntitlementTransport(base: .init(status: 403,
            billingBody: credits(type: 2, end: "2026-10-05T12:00:00Z", percent: nil)), settings: "{}", settingsStatus: 503),
            authFileURL: auth, now: { fixedNow }, xaiSubscriptionDateStore: dates, xaiRefreshAllowed: { true })
        let cached = try #require(try await restarted.refresh(targets: [target]).first)
        #expect(AccountQuotaFormatting.plainSummary(for: cached, now: now) == "订阅已过期 · 至9月27日")
        #expect(AccountQuotaFormatting.isDimmed(cached))
        #expect(AppLanguage.english.quotaText("订阅已过期") == "Subscription expired")
        #expect(AppLanguage.english.quotaText("套餐待核实") == "Plan unverified")
    }
}

private actor GrokSubscriptionOutageTransport: AccountQuotaTransport {
    let success: GrokFixtureTransport
    let outage: GrokFixtureTransport
    let settingsBody: String?
    private var hasSucceeded = false

    init(success: GrokFixtureTransport, outage: GrokFixtureTransport, settingsBody: String? = nil) {
        self.success = success
        self.outage = outage
        self.settingsBody = settingsBody
    }

    func data(for request: URLRequest) async throws -> AccountQuotaHTTPResponse {
        if request.url == XaiEndpointValidator.subscriptionSettingsURL, let settingsBody {
            return .init(statusCode: 200, headers: [:], body: Data(settingsBody.utf8))
        }
        let transport = request.url == XaiEndpointValidator.subscriptionsURL && hasSucceeded
            ? outage
            : success
        let result = try await transport.data(for: request)
        if request.url == XaiEndpointValidator.subscriptionsURL { hasSucceeded = true }
        return result
    }
}

private struct GrokIdentityFixtureTransport: AccountQuotaTransport {
    let base: GrokFixtureTransport
    let identityStatus: Int
    let switchAuth: URL?
    func data(for request: URLRequest) async throws -> AccountQuotaHTTPResponse {
        let result = try await base.data(for: request)
        guard request.url == XaiEndpointValidator.subscriptionUserURL else { return result }
        if let switchAuth {
            try Data(#"{"default_account_id":"other","accounts":{"other":{"account_id":"other","refresh_token":"other-refresh","requires_reauth":false}}}"#.utf8).write(to: switchAuth)
        }
        return AccountQuotaHTTPResponse(statusCode: identityStatus, headers: result.headers, body: result.body)
    }
}


private actor GrokOptionalFailureTransport: AccountQuotaTransport {
    let billing: Data
    let cancelled: Bool
    init(billing: Data, cancelled: Bool) { self.billing = billing; self.cancelled = cancelled }
    func data(for request: URLRequest) async throws -> AccountQuotaHTTPResponse {
        if request.url == XaiEndpointValidator.subscriptionsURL {
            if cancelled { throw CancellationError() }
            throw URLError(.cannotConnectToHost)
        }
        let body: Data
        if request.url == XaiEndpointValidator.discoveryURL { body = Data(#"{"issuer":"https://auth.x.ai","token_endpoint":"https://auth.x.ai/oauth2/token"}"#.utf8) }
        else if request.url?.host == "auth.x.ai" { body = Data(#"{"access_token":"fixture"}"#.utf8) }
        else { body = billing }
        return .init(statusCode: 200, headers: [:], body: body)
    }
}

extension GrokQuotaTests {
    @Test func anOptionalSubscriptionNetworkFailureKeepsUsageWhileCancellationPropagates() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let auth = root.appendingPathComponent("auth.json")
        try Data(#"{"accounts":{"fixture":{"refresh_token":"fixture"}}}"#.utf8).write(to: auth)
        for cancelled in [false, true] {
            let tokens = XAIAccessTokens(refreshAllowed: { true })
            let transport = GrokOptionalFailureTransport(billing: credits(type: 2, end: "2026-10-05T12:00:00Z"), cancelled: cancelled)
            if cancelled { await #expect(throws: CancellationError.self) { try await tokens.billing(transport: transport, authFileURL: auth, now: now) } }
            else {
                let result = try await tokens.billing(transport: transport, authFileURL: auth, now: now)
                if case .windows(let windows) = result { #expect(windows.first?.name == "weekly_limit") }
                else { Issue.record("An optional subscription outage erased valid usage") }
            }
        }
    }
}
