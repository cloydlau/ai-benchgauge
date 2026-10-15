import Foundation
import Testing
@testable import LeaderboardCore
import LeaderboardKit

struct QuotaUtilityBoundaryTests {
    private func chip(_ status: AccountQuotaChip.Status) -> AccountQuotaChip {
        .init(id: "fixture", shortName: "Fixture", websiteURL: nil, kind: .kimi, isCurrent: true, status: status)
    }
    @Test func everyFreshnessStateAndSupportedCurrencyHasAnExplicitOutcome() {
        let now = Date(timeIntervalSince1970: 1000)
        #expect(QuotaFreshness.updatedAt(afterRefreshing: [chip(.windows([]))], previous: nil, now: now) == nil)
        #expect(QuotaFreshness.updatedAt(afterRefreshing: [chip(.balances([]))], previous: nil, now: now) == nil)
        #expect(QuotaFreshness.updatedAt(afterRefreshing: [chip(.balances([.init(currency: "CNY", amount: 1)]))], previous: nil, now: now) == now)
        for currency in ["TWD", "JPY", "KRW", "INR"] {
            let reference = QuotaColorScale.balanceReference(currency: currency)
            #expect(reference != nil)
            #expect(QuotaColorScale.balanceLevel(amount: reference!.green, currency: currency) == 100)
        }
        #expect(QuotaColorScale.balanceLevel(amount: .nan, currency: "USD") == nil)
        #expect(QuotaColorScale.deadlineLevel(until: Date(timeIntervalSince1970: .nan), now: now) == nil)
        for chinese in [true, false] {
            #expect(!CodexTaskCounts.help(nil, chinese: chinese).isEmpty)
            for failed in [0, 2] {
                let counts = CodexTaskCounts(running: 1, unread: 2, failed: failed)
                #expect(!CodexTaskCounts.help(counts, chinese: chinese).isEmpty)
                #expect(CodexTaskCounts.help(counts, chinese: chinese).contains("2"))
            }
        }
    }

    @Test func brokenConfigurationAndSavedQuotaRecordsUseOnlyTheirOwnFallbacks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("configuration.txt")
        let session = CodexModelConfiguration(model: "fixture")
        try Data("[unterminated".utf8).write(to: file)
        #expect(CodexModelConfiguration.load(from: file, session: session) == session)
        #expect(CodexModelConfiguration.parse("model = \"fixture\" trailing") == nil)
        for url in ["relative/path", "http:", "http:relative", "https:/relative"] {
            #expect(CodexModelConfiguration(model: "fixture", provider: "proxy", baseURL: url).selectingCurrentTarget(in: []).isEmpty)
        }
        _ = CCSwitchProviderStore.defaultDatabaseURL
        _ = CCSwitchProviderStore.defaultSettingsURL
        let store = XAISubscriptionDateStore(fileURL: file)
        for record in [XAISubscriptionDateStore.Record(accountID: "", periodEnd: Date(), source: .cached),
                       .init(accountID: "fixture", periodEnd: Date(timeIntervalSince1970: .nan), source: .cached)] {
            #expect(throws: CocoaError.self) { try store.save(record) }
        }
        try Data("{}".utf8).write(to: file)
        #expect(store.record(accountID: "fixture", now: Date()) == nil)
        let expiry = OpenAIPlanExpiryStore(fileURL: file)
        #expect(expiry.cachedWindow(accountID: "fixture", now: Date()) == nil)
    }

    @Test func geminiQuotaKeepsValidResetAndDropsInvalidShapes() throws {
        let data = try JSONSerialization.data(withJSONObject: ["buckets": [["modelId": "gemini-pro", "remainingFraction": 0.5, "resetTime": "2026-10-13T00:00:00Z"]]])
        if case .windows(let values) = LeaderboardQuotaParsers.gemini(data) {
            #expect(values.count == 1)
            #expect(values[0].resetsAt != nil)
        } else { Issue.record("A valid Gemini quota was rejected") }
        #expect(LeaderboardQuotaParsers.claude(Data("{}".utf8)) == .rejected)
        for url in ["https://api.bfl.ml", "https://api.us1.bfl.ai", "https://api.eu1.bfl.ai"] { #expect(LeaderboardQuotaProviders.kind(forBaseURL: url) == .blackForestLabs) }
    }
}

struct QuotaRemainingBoundaryTests {
    @Test func formattingAndLanguageCoverEveryProviderAndUnusualDate() throws {
        for kind: CCSwitchQuotaKind in [.officialNote, .kimi, .deepseek, .xaiOAuth, .zhipu, .qwen, .minimax, .stepfun, .blackForestLabs, .luma, .claude, .gemini] {
            for language in AppLanguage.allCases { #expect(!language.providerName(kind).isEmpty) }
        }
        #expect(AppLanguage.english.quotaText("重置10月13日2时") == "Resets Oct 13, 02:00")
        #expect(AppLanguage.english.quotaText("重置13月13日") == "Resets 13月13日")
        #expect(AppLanguage.english.quotaText("余量达到20%") == "Remaining quota reached 20%")
        #expect(AppLanguage.english.quotaText("额度 1小时后重置；其他") == " quota resets in 1h; 其他")
        #expect(AppLanguage.english.quotaText("千问官网个人版用量（官网本次读取失败，显示 fixture 保存的结果）") == "Qwen site unavailable; showing saved result from fixture")
        #expect(CodexModelConfiguration.parse(#"model = "fixture\\model""#)?.model == "fixture\\model")
        let now = Date(timeIntervalSince1970: 1000)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = OpenAIPlanExpiryStore(fileURL: root.appendingPathComponent("expiry"))
        try store.save(accountID: "", expiresAt: now)
        #expect(!FileManager.default.fileExists(atPath: root.path))
        for label in ["月度", "1个月", "7天"] {
            let data = Data("{\"version\":2,\"periodLabel\":\"\(label)\",\"remainingPercent\":50,\"capturedAt\":1}".utf8)
            #expect(QwenWebsiteQuotaParser.parse(data)?.periodLabel == (label == "7天" ? "7d" : "1mo"))
        }
        #expect(QwenWebsiteQuotaParser.failureStatus(in: Data([0xff])) == nil)
        #expect(QwenWebsiteQuotaParser.parse(Data("套餐有效期至 2026-10-13\n7天限额 剩余量 50%".utf8))?.expiresAt != nil)
        #expect(LeaderboardQuotaProviders.kind(forBaseURL: "https://api.stepfun.ai") == .stepfun)
        for invalid in ["invalid", "[]", #"{"error":"fixture"}"#] { #expect(LeaderboardQuotaParsers.claude(Data(invalid.utf8)) == .rejected) }
        for invalid in ["invalid", "[]", "{}", #"{"buckets":[]}"#, #"{"buckets":[{"modelId":"gemini-pro","remainingFraction":3}]}"#] { #expect(LeaderboardQuotaParsers.gemini(Data(invalid.utf8)) == .rejected) }
        let gemini = Data(#"{"buckets":[{"modelId":"gemini-flash-lite","remainingFraction":"0.4"},{"modelId":"other","remainingFraction":0.6}]}"#.utf8)
        #expect(LeaderboardQuotaParsers.gemini(gemini) == .windows([.init(name: "gemini_flash_lite", utilization: 60, resetsAt: nil), .init(name: "other", utilization: 40, resetsAt: nil)]))
        let plan = QwenPlanQuota(usedPercent: 20, remainingCredits: 80, totalCredits: 100, resetsAt: nil)
        let chip = AccountQuotaChip(id: "fixture", shortName: "Fixture", websiteURL: nil, kind: .qwen, isCurrent: true, status: .qwenPlan(plan))
        #expect(QuotaFreshness.updatedAt(afterRefreshing: [chip], previous: nil, now: now) == now)
    }
}

struct QuotaRecoveryBoundaryTests {
    @Test func pendingRecoveryRequiresEveryNewReadingToRemainUsable() {
        func chip(_ used: Double, remaining: Double = 0, total: Double = 0) -> AccountQuotaChip {
            .init(id: "fixture", shortName: "Fixture", websiteURL: nil, kind: .qwen, isCurrent: true,
                  status: .qwenPlan(.init(usedPercent: used, remainingCredits: remaining, totalCredits: total, resetsAt: nil)))
        }
        var tracker = QuotaRecoveryTracker()
        #expect(tracker.consider(chips: [chip(100)]).isEmpty)
        #expect(tracker.consider(chips: [chip(50)]).count == 1)
        #expect(tracker.consider(chips: [chip(.nan)]).isEmpty)
        #expect(tracker.consider(chips: [chip(50)]).count == 1, "An invalid read must preserve the pending notification for retry")
        #expect(tracker.consider(chips: [chip(50, remaining: .greatestFiniteMagnitude, total: .leastNonzeroMagnitude)]).count == 1)
        let bad = [#"{"model_remains":[{"model_name":"general"}]}"#, #"{"model_remains":[{"model_name":"general","current_interval_remaining_percent":{},"current_weekly_status":1,"current_weekly_remaining_percent":"nan"}]}"#]
        for text in bad { #expect(LeaderboardQuotaParsers.miniMax(Data(text.utf8)) == .rejected) }
    }
}

struct InvalidWebsiteEncodingTests {
    @Test func invalidUTF8CannotBecomeWebsiteQuota() {
        #expect(QwenWebsiteQuotaParser.parse(Data([0xff])) == nil)
    }
}
