import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import LeaderboardKit
import Testing
@testable import LeaderboardCore

private actor CreditsTransport: AccountQuotaTransport {
    var offline = false
    let body: String
    init(_ body: String) { self.body = body }
    func setOffline() { offline = true }
    func data(for request: URLRequest) async throws -> AccountQuotaHTTPResponse {
        if offline { throw URLError(.notConnectedToInternet) }
        return .init(statusCode: 200, headers: [:], body: Data(body.utf8))
    }
}

private actor CreditsRPC: OpenAIAccountRPC {
    let quota: String
    init(_ quota: String) { self.quota = quota }
    func request(_ method: String, params: Data) async throws -> Data {
        Data((method == "account/read" ? #"{"account":{"type":"chatgpt"}}"# : quota).utf8)
    }
    func waitForLogin(_ id: String) async throws {}
    func stop() async {}
}

struct OpenAICreditsTests {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    let funded = OpenAICredits(hasCredits: true, unlimited: false, balance: 120.5)
    private func chip(used: Double = 100, weekly: Double = 20, credits: OpenAICredits? = nil,
                      kind: CCSwitchQuotaKind = .officialNote) -> AccountQuotaChip {
        .init(id: "official", shortName: "OpenAI", websiteURL: nil, kind: kind, isCurrent: true,
              status: .windows([
                .init(name: "five_hour", utilization: used, resetsAt: now.addingTimeInterval(3600)),
                .init(name: "weekly_limit", utilization: weekly, resetsAt: now.addingTimeInterval(86400)),
              ]), credits: credits)
    }
    private func target() -> CCSwitchQuotaTarget {
        .init(id: "official", shortName: "OpenAI", websiteURL: nil, kind: .officialNote,
              isCurrent: true, apiKey: nil, baseURL: nil, accessToken: "synthetic-token")
    }

    @Test func parsesCreditAmountsWithoutConvertingToDollarsOrPercentages() {
        for value in ["120.5", #""120.5""#] {
            let data = Data("{\"credits\":{\"has_credits\":true,\"unlimited\":false,\"balance\":\(value)}}".utf8)
            #expect(CCSwitchQuotaParsers.parseOpenAICredits(data) == funded)
        }
        #expect(CCSwitchQuotaParsers.parseOpenAICredits(Data(#"{"credits":{"has_credits":true,"unlimited":true,"balance":null}}"#.utf8))?.unlimited == true)
        #expect(CCSwitchQuotaParsers.parseOpenAICredits(Data(#"{"credits":{"has_credits":true,"unlimited":false}}"#.utf8))?.balance == nil)
        for raw in ["true", "-1", #""NaN""#, #""infinity""#, #""invalid""#, "[]"] {
            #expect(CCSwitchQuotaParsers.parseOpenAICredits(Data("{\"credits\":{\"has_credits\":true,\"unlimited\":false,\"balance\":\(raw)}}".utf8)) == nil)
        }
        for raw in ["invalid", "[]", "{}", #"{"credits":{}}"#,
                    #"{"credits":{"has_credits":1,"unlimited":false}}"#,
                    #"{"credits":{"has_credits":true,"unlimited":0}}"#] {
            #expect(CCSwitchQuotaParsers.parseOpenAICredits(Data(raw.utf8)) == nil)
        }
        #expect(OpenAICredits(hasCredits: true, unlimited: false, balance: .infinity).balance == nil)
    }

    @Test func appServerCreditsBelongToTheSelectedCodexBucket() {
        let data = Data(#"{"rateLimits":{"limitId":"other","credits":{"hasCredits":true,"unlimited":true}},"rateLimitsByLimitId":{"codex":{"credits":{"hasCredits":true,"unlimited":false,"balance":"120.5"}}}}"#.utf8)
        #expect(CCSwitchQuotaParsers.parseOpenAICredits(data, appServer: true) == funded)
        for raw in ["invalid", "{}", #"{"rateLimits":{"limitId":"other","credits":{"hasCredits":true,"unlimited":true}}}"#] {
            #expect(CCSwitchQuotaParsers.parseOpenAICredits(Data(raw.utf8), appServer: true) == nil)
        }
        let legacy = Data(#"{"rateLimits":{"credits":{"hasCredits":false,"unlimited":false,"balance":"0"}}}"#.utf8)
        #expect(CCSwitchQuotaParsers.parseOpenAICredits(legacy, appServer: true)?.balance == 0)
    }

    @Test func switchesOnlyAfterAnIncludedWindowIsActuallyExhausted() {
        for value in [chip(credits: funded), chip(used: 20, weekly: 100, credits: funded)] {
            #expect(AccountQuotaFormatting.plainSummary(for: value, now: now) == "额度 120.50")
            #expect(AccountQuotaFormatting.compactMenuBarQuota(for: value) == "额度 120.50")
            #expect(!AccountQuotaFormatting.isExhausted(value))
            #expect(!AccountQuotaFormatting.isDimmed(value))
            #expect(AccountQuotaFormatting.lowestRemainingPercent(for: value) == nil)
            #expect(AccountQuotaFormatting.colorLevel(for: value) == nil)
            #expect(QuotaAlerts.alerts(for: value, now: now).allSatisfy { $0.reason != .lowRemaining })
            let help = AccountQuotaFormatting.help(for: value, now: now)
            #expect(help.contains("5h") && help.contains("7d") && help.contains("120.50"))
        }
        for value in [chip(used: 20, credits: funded), chip(used: 99.99, credits: funded), chip(), chip(credits: funded, kind: .kimi)] {
            #expect(!AccountQuotaFormatting.usesOpenAICredits(value))
            #expect(AccountQuotaFormatting.plainSummary(for: value, now: now).contains("5h"))
        }
        let pending = AccountQuotaChip(id: "official", shortName: "OpenAI", websiteURL: nil, kind: .officialNote,
            isCurrent: true, status: .message(AccountQuotaMessage.network), credits: funded)
        #expect(!AccountQuotaFormatting.usesOpenAICredits(pending))
        let creditOnly = AccountQuotaChip(id: "official", shortName: "OpenAI", websiteURL: nil, kind: .officialNote,
            isCurrent: true, status: .windows([]), credits: funded)
        #expect(AccountQuotaFormatting.compactMenuBarQuota(for: creditOnly) == "额度 120.50")
    }

    @Test func handlesUnlimitedUnquantifiedEmptyAndTinyBalancesHonestly() {
        let cases: [(OpenAICredits, String, Bool)] = [
            (.init(hasCredits: false, unlimited: true, balance: nil), "额度不限", true),
            (.init(hasCredits: true, unlimited: false, balance: nil), "额度可用", true),
            (.init(hasCredits: false, unlimited: false, balance: nil), "额度 0", false),
            (.init(hasCredits: false, unlimited: false, balance: 0), "额度 0", false),
            (.init(hasCredits: true, unlimited: false, balance: 0), "额度 0", false),
            (.init(hasCredits: true, unlimited: false, balance: 2), "额度 2", true),
            (.init(hasCredits: true, unlimited: false, balance: 0.001), "额度 <0.01", true),
        ]
        for (credits, text, usable) in cases {
            let value = chip(credits: credits)
            #expect(AccountQuotaFormatting.plainSummary(for: value, now: now) == text)
            #expect(AccountQuotaFormatting.isExhausted(value) == !usable)
            #expect(AccountQuotaFormatting.isDimmed(value) == !usable)
            #expect(AccountQuotaFormatting.colorLevel(for: value) == (usable ? nil : 0))
        }
        let zero = chip(credits: .init(hasCredits: false, unlimited: false, balance: 0))
        #expect(QuotaAlerts.alerts(for: zero, now: now).contains { $0.reason == .lowRemaining })
        let plan = chip(used: 20)
        let balance = chip(credits: funded)
        #expect(AccountQuotaFormatting.sortedChips([zero, balance, plan]).map(\.credits) == [nil, funded, zero.credits])
        let dated = AccountQuotaChip(id: "official", shortName: "OpenAI", websiteURL: nil, kind: .officialNote,
            isCurrent: true, status: .windows([
                .init(name: "five_hour", utilization: 100, resetsAt: nil),
                .init(name: ParsedQuotaWindow.planExpiryName, utilization: 0, resetsAt: now.addingTimeInterval(864000)),
            ]), credits: funded)
        #expect(AccountQuotaFormatting.plainSummary(for: dated, now: now).hasPrefix("额度 120.50 · 至"))
    }

    @Test func creditCopyIsLocalizedAndRoutingPreservesTheCreditBalance() {
        #expect(AppLanguage.english.quotaText("额度 120.50") == "credits 120.50")
        #expect(AppLanguage.english.quotaText("额度不限") == "Unlimited credits")
        #expect(AppLanguage.english.quotaText("额度可用") == "Credits available")
        #expect(AppLanguage.traditionalChinese.quotaText("额度可用") == "額度可用")
        #expect(AppLanguage.english.quotaText("套餐额度用尽后，可使用剩余额度继续工作；额度不是美元或套餐剩余百分比。").hasPrefix("After included limits"))
        let config = CodexModelConfiguration(model: "gpt-fixture", provider: "openai")
        #expect(config.menuBarText(for: [chip(credits: funded)], targets: [target()])?.quota == "额度 120.50")
    }

    @Test func directUsageAndNetworkFallbackRetainCredits() async throws {
        let transport = CreditsTransport(#"{"rate_limit":{"primary_window":{"used_percent":100,"limit_window_seconds":18000}},"credits":{"has_credits":true,"unlimited":false,"balance":"120.5"}}"#)
        let client = AccountQuotaClient(transport: transport,
            authFileURL: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
        let fresh = try await client.refresh(targets: [target()])
        #expect(fresh.first?.credits == funded)
        await transport.setOffline()
        let stale = try await client.refresh(targets: [target()], previous: fresh)
        #expect(stale.first?.isStale == true)
        #expect(stale.first?.credits == funded)
    }

    @Test func managedLoginLoadsCreditsWithoutRequiringUsageWindows() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "credits-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let rpc = CreditsRPC(#"{"rateLimits":{"limitId":"codex","credits":{"hasCredits":true,"unlimited":false,"balance":"120.5"}}}"#)
        let source = OpenAIManagedQuotaSource(rootURL: root, transport: CreditsTransport("{}"), sessionFactory: { _ in rpc })
        let profile = await source.profileURL(for: "official")
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        try Data(#"{"accountID":"fixture-account"}"#.utf8).write(to: profile.appending(path: "binding.json"))
        try Data(#"{"tokens":{"account_id":"fixture-account","access_token":"fixture-token"}}"#.utf8).write(to: profile.appending(path: "auth.json"))
        let value = try await source.loadQuota(for: target())
        #expect(value?.credits == funded)
        #expect(value.map { AccountQuotaFormatting.plainSummary(for: $0, now: now) } == "额度 120.50")
    }
}
