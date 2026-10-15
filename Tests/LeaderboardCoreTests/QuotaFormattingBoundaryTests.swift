import Foundation
import Testing
@testable import LeaderboardCore

struct QuotaFormattingBoundaryTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private func chip(_ status: AccountQuotaChip.Status, kind: CCSwitchQuotaKind = .kimi) -> AccountQuotaChip {
        .init(id: "fixture", shortName: "Fixture", websiteURL: nil, kind: kind, isCurrent: true, status: status)
    }
    @Test func malformedAmountsNeverProduceAValidMenuBarQuota() {
        #expect(AccountQuotaFormatting.menuBarText(forChips: [], maximumNameLength: 4, currentModelName: "LongName")?.name == "Lon…")
        for status: AccountQuotaChip.Status in [.message(""), .note(text: "", help: ""), .windows([]), .balances([])] {
            #expect(AccountQuotaFormatting.menuBarText(forChips: [chip(status)])?.quota == AccountQuotaMessage.queryFailed)
        }
        for value in [Double.nan, .infinity, -1, 101] {
            #expect(AccountQuotaFormatting.compactMenuBarQuota(for: chip(.qwenWebsite(.init(periodLabel: "7d", remainingPercent: value, resetsAt: nil)))) == nil)
        }
        #expect(AccountQuotaFormatting.compactMenuBarQuota(for: chip(.balances([.init(currency: "USD", amount: 0)]))) == "$0.00")
        #expect(AccountQuotaFormatting.roundedPercent(.nan) == 0)
        #expect(AccountQuotaFormatting.lowestRemainingPercent(for: chip(.qwenWebsite(.init(periodLabel: "7d", remainingPercent: .nan, resetsAt: nil)))) == nil)
        for (currency, symbol) in [("EUR", "€"), ("GBP", "£"), ("HKD", "HK$"), ("TWD", "NT$"), ("KRW", "₩"), ("INR", "₹")] {
            #expect(AccountQuotaFormatting.currencySymbol(for: currency) == symbol)
        }
        for name in ["gemini_pro", "gemini_flash", "gemini_flash_lite", "seven_day_opus", "seven_day_sonnet", "seven_day_fable"] {
            #expect(AccountQuotaFormatting.label(forWindowName: name) != name)
        }
        #expect(AccountQuotaFormatting.displayWindows([.init(name: "custom", utilization: 0, resetsAt: nil)], kind: .zhipu).first?.name == "custom")
    }
    @Test func eachProviderExplainsItsAmountWithoutInventingAnExpiry() {
        for kind: CCSwitchQuotaKind in [.minimax, .luma, .blackForestLabs, .stepfun, .claude, .gemini] {
            #expect(AccountQuotaFormatting.help(for: chip(.pending, kind: kind), now: now).contains("当前供应商"))
            let target = CCSwitchQuotaTarget(id: "fixture", shortName: "Fixture", websiteURL: nil, kind: kind, isCurrent: true, apiKey: nil, baseURL: nil)
            #expect(AccountQuotaChip.placeholder(for: target).status == .pending)
        }
        #expect(AccountQuotaFormatting.help(for: chip(.message("")), now: now) == "当前供应商")
        let cached = chip(.qwenWebsite(.init(periodLabel: "7d", remainingPercent: 50, resetsAt: now.addingTimeInterval(60), expiresAt: now.addingTimeInterval(3600), isCached: true, capturedAt: now)), kind: .qwen)
        #expect(AccountQuotaFormatting.help(for: cached, now: now).contains("保存的结果"))
        let invalid = chip(.qwenPlan(.init(usedPercent: .nan, remainingCredits: .infinity, totalCredits: 1, resetsAt: nil)))
        #expect(AccountQuotaFormatting.compactMenuBarQuota(for: invalid) == "额度 100%")
        let overflow = chip(.qwenPlan(.init(usedPercent: 20, remainingCredits: .greatestFiniteMagnitude, totalCredits: .leastNonzeroMagnitude, resetsAt: nil)))
        #expect(AccountQuotaFormatting.compactMenuBarQuota(for: overflow) == "额度 80%")
        let nonfinite = chip(.qwenWebsite(.init(periodLabel: "7d", remainingPercent: .nan, resetsAt: nil, expiresAt: Date(timeIntervalSince1970: .nan))))
        #expect(AccountQuotaFormatting.plainSummary(for: nonfinite, now: now).contains("0%"))
        let plan = chip(.qwenPlan(.init(usedPercent: 10, remainingCredits: 90, totalCredits: 100, resetsAt: now.addingTimeInterval(3600), expiresAt: now.addingTimeInterval(7200))), kind: .qwen)
        #expect(AccountQuotaFormatting.help(for: plan, now: now).contains("额度重置"))
        #expect(AccountQuotaFormatting.plainSummary(for: chip(.windows([.init(name: "custom", utilization: .nan, resetsAt: nil)])), now: now).contains("100%"))
    }
    @Test func catalogReadsAlternateCredentialsAndRejectsMalformedMetadata() throws {
        func record(_ id: String, _ settings: Any, _ meta: Any = [:], website: String? = nil, sort: Int? = nil) throws -> CCSwitchProviderRecord {
            .init(id: id, name: id, websiteURL: website, sortIndex: sort, createdAt: 0, isCurrent: false,
                  metaJSON: String(decoding: try JSONSerialization.data(withJSONObject: meta), as: UTF8.self), settingsConfigJSON: String(decoding: try JSONSerialization.data(withJSONObject: settings), as: UTF8.self))
        }
        let bases = ["https://api.deepseek.com", "https://api.kimi.com/coding", "https://api.z.ai", "https://open.bigmodel.cn", "https://api.stepfun.com", "https://api.bfl.ai", "https://api.lumalabs.ai", "https://api.minimax.io", "https://token-plan.maas.qianwenaiapi.com"]
        for (index, base) in bases.enumerated() {
            let settings: [String: Any] = ["options": ["baseURL": base, "apiKey": "fixture"], "config": ["nested": [["base_url": "http://[::1]"], ["base_url": "http://0.0.0.0"], ["model": "Fixture"], ["model": 3]]]]
            let targets = CCSwitchQuotaCatalog.targets(from: [try record("r\(index)", settings, website: index.isMultiple(of: 2) ? "http://example.test" : "relative")], currentProviderID: nil)
            #expect(targets.count == 1)
            #expect(targets[0].apiKey == "fixture")
        }
        for (id, metadata, expected): (String, [String: Any], CCSwitchQuotaKind) in [
            ("cc-switch:claude:a", ["usage_script": ["templateType": "official_subscription"]], .claude),
            ("cc-switch:gemini:a", ["usage_script": ["templateType": "official_subscription"]], .gemini),
            ("xai", ["authBinding": ["authProvider": "xai_oauth"]], .xaiOAuth),
            ("qwen", ["usage_script": ["codingPlanProvider": "alibaba"]], .qwen),
        ] {
            #expect(CCSwitchQuotaCatalog.targets(from: [try record(id, [:], metadata)], currentProviderID: nil).first?.kind == expected)
        }
        let blankOverride = try record("blank-override", ["baseUrl": "https://api.stepfun.com", "config": ["model": "Fixture"]], ["usage_script": ["templateType": "balance", "baseUrl": ""]])
        #expect(CCSwitchQuotaCatalog.targets(from: [blankOverride], currentProviderID: nil).first?.modelName == "Fixture")
        let unknownPlan = try record("unknown-plan", [:], ["usage_script": ["codingPlanProvider": "unknown"]])
        #expect(CCSwitchQuotaCatalog.targets(from: [unknownPlan], currentProviderID: nil).isEmpty)
        let sorted = try [record("sorted", ["baseUrl": "https://api.kimi.com/coding"], sort: 1), record("unsorted", ["baseUrl": "https://api.kimi.com/coding"])]
        #expect(CCSwitchQuotaCatalog.targets(from: sorted, currentProviderID: nil).first?.id == "sorted")
        let balance = try record("balance", ["baseUrl": "https://api.stepfun.com"], ["usage_script": ["templateType": "balance"]])
        #expect(CCSwitchQuotaCatalog.targets(from: [balance], currentProviderID: nil).first?.kind == .stepfun)
        let invalid = CCSwitchProviderRecord(id: "x", name: "x", websiteURL: "https://[invalid", sortIndex: nil, createdAt: 0, isCurrent: false, metaJSON: "not json", settingsConfigJSON: "not json")
        #expect(CCSwitchQuotaCatalog.targets(from: [invalid], currentProviderID: nil).isEmpty)
        for token in ["'fixture'", #""fixture""#] {
            let config = "# comment\ninvalid\nmodel = x\nmodel = \(token) # trailing\nbase_url = 'https://api.kimi.com/coding'\nexperimental_bearer_token = 'fixture'"
            let targets = CCSwitchQuotaCatalog.targets(from: [try record("toml", ["config": config])], currentProviderID: nil)
            #expect(targets.first?.apiKey == "fixture")
            #expect(targets.first?.modelName == "fixture")
        }
    }
    @Test func alertDescriptionsKeepMissingDatesAndMalformedWindowNamesSafe() {
        #expect(!QuotaAlerts.hasAutoRenewingPlan(.pending))
        #expect(QuotaAlerts.countdownPhrase(until: now, now: now) == nil)
        for name in ["_hour", "bad_hour", "999999999999999999999999999_hour"] { #expect(QuotaAlerts.prefixedInt(name, suffix: "_hour") == nil) }
        let subject = QuotaAlerts.Subject(sourceID: "fixture", label: "额度", remainingPercent: 5, resetsAt: nil, expiryEligible: true, expiresRatherThanResets: true, isAutoRenewing: false)
        #expect(QuotaAlerts.expiryDescription(subject, phrase: "1分钟", now: now) == "")
        let noDate = QuotaAlerts.Subject(sourceID: "fixture", label: "额度", remainingPercent: 5, resetsAt: nil, expiryEligible: true, expiresRatherThanResets: false, isAutoRenewing: false)
        #expect(QuotaAlerts.expiryDescription(noDate, phrase: "1分钟", now: now) == "额度 1分钟后重置")
        let chip = chip(.windows([.init(name: "3_hour", utilization: 95, resetsAt: now.addingTimeInterval(60))]))
        #expect(!QuotaAlerts.alerts(for: chip, now: now).isEmpty)
        #expect(QuotaAlerts.retainedKeys(["malformed"], evaluatedChips: [chip], activeKeys: []) == ["malformed"])
    }
    @Test func explicitFormattingFallbacksPreserveAmounts() {
        #expect(AccountQuotaFormatting.shanghaiTimeZone(named: nil).secondsFromGMT() == 28800)
        #expect(AccountQuotaFormatting.balanceAmountText(1.25, formatted: nil) == "1.25")
        #expect(AccountQuotaFormatting.creditText(1.25, formatted: nil) == "1.25")
    }
    @Test func authAliasesAndTokenReplacementUseTheActualSelectedAccount() throws {
        let data = Data(#"{"accounts":{"alias":{"account_id":"","refresh_token":"old"},"malformed":3,"empty":{"refresh_token":""}}}"#.utf8)
        #expect(XaiAuthFile.selectedAccount(try #require(XaiAuthFile.parse(data)))?.id == "alias")
        let changed = try #require(XaiAuthFile.replacingRefreshToken(in: data, accountID: "alias", oldToken: "old", newToken: "new"))
        #expect(XaiAuthFile.selectedAccount(try #require(XaiAuthFile.parse(changed)))?.refreshToken == "new")
        #expect(XaiAuthFile.replacingRefreshToken(in: data, accountID: "missing", oldToken: "old", newToken: "new") == nil)
        #expect(XaiAuthFile.selectedAccount(.init(defaultAccountID: nil, accounts: [])) == nil)
        #expect(XaiAuthFile.replacingRefreshToken(in: Data("{}".utf8), accountID: "missing", oldToken: "old", newToken: "new") == nil)
        #expect(XaiEndpointValidator.trustedTokenEndpoint("https://[invalid") == nil)
    }
}
