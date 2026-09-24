import Foundation
import LeaderboardCore
import XCTest

final class CCSwitchQuotaCatalogTests: XCTestCase {
    func testBuildsVisibleProvidersInCCSwitchOrderAndMarksTheSelectedOneCurrent() {
        let records = [
            record(
                id: "qwen",
                name: "千问",
                createdAt: 1,
                meta: #"{"usage_script":{"enabled":false,"templateType":"balance"}}"#,
                settings: settings(key: "should-not-be-used", toml: "https://api.deepseek.com")
            ),
            record(
                id: "codex-official",
                name: "OpenAI Official",
                website: "https://chatgpt.com/codex",
                sortIndex: 0,
                createdAt: 2,
                isCurrent: true,
                meta: #"{"usage_script":{"enabled":true,"templateType":"official_subscription"}}"#,
                settings: settings(
                    key: "official-key-must-not-leave",
                    toml: "https://api.openai.com/v1",
                    accessToken: "stored-official-login",
                    accountID: "acct-1"
                )
            ),
            record(
                id: "kimi",
                name: "Kimi For Coding",
                website: "https://www.kimi.com/code",
                createdAt: 3,
                meta: #"{"usage_script":{"enabled":true,"templateType":"token_plan","codingPlanProvider":"kimi"}}"#,
                settings: settings(key: "unit-test-key", toml: "https://api.kimi.com/coding/v1")
            ),
            record(
                id: "deepseek",
                name: "DeepSeek",
                website: "https://platform.deepseek.com",
                createdAt: 4,
                meta: #"{"usage_script":{"enabled":true,"templateType":"balance"}}"#,
                settings: settings(key: "deepseek-key", configObject: ["base_url": "https://api.deepseek.com"])
            ),
            record(
                id: "xai",
                name: "xAI (Grok) OAuth",
                website: "https://x.ai/grok",
                createdAt: 5,
                meta: #"{"providerType":"xai_oauth"}"#
            ),
            record(
                id: "zhipu",
                name: "Zhipu GLM",
                website: "https://open.bigmodel.cn",
                createdAt: 6,
                meta: #"{"usage_script":{"enabled":true,"codingPlanProvider":"zhipu"}}"#,
                settings: settings(key: "zhipu-key", toml: "https://open.bigmodel.cn/api/paas/v4")
            ),
        ]

        let targets = CCSwitchQuotaCatalog.targets(from: records, currentProviderID: "xai")

        XCTAssertEqual(targets.map(\.id), ["codex-official", "kimi", "deepseek", "xai", "zhipu"])
        XCTAssertEqual(targets.map(\.kind), [.officialNote, .kimi, .deepseek, .xaiOAuth, .zhipu])
        XCTAssertEqual(targets.map(\.shortName), ["OpenAI", "Kimi", "DeepSeek", "xAI", "GLM"])
        XCTAssertEqual(targets.map(\.isCurrent), [false, false, false, true, false])
        XCTAssertNil(targets[0].apiKey)
        XCTAssertEqual(targets[0].accessToken, "stored-official-login")
        XCTAssertEqual(targets[0].accountID, "acct-1")
        XCTAssertEqual(targets[1].apiKey, "unit-test-key")
        XCTAssertEqual(targets[1].baseURL, "https://api.kimi.com/coding/v1")
        XCTAssertEqual(targets[2].baseURL, "https://api.deepseek.com")
        XCTAssertNil(targets[3].apiKey)
        XCTAssertEqual(targets[4].baseURL, "https://open.bigmodel.cn/api/paas/v4")
        XCTAssertEqual(
            CCSwitchQuotaCatalog.zhipuQuotaURL(baseURL: targets[4].baseURL).absoluteString,
            "https://open.bigmodel.cn/api/monitor/usage/quota/limit"
        )
        XCTAssertEqual(
            CCSwitchQuotaCatalog.zhipuSubscriptionURL(baseURL: targets[4].baseURL).absoluteString,
            "https://open.bigmodel.cn/api/biz/subscription/list"
        )
    }

    func testOfficialWithoutStoredLoginIsOmittedAndDoesNotRequireCodex() {
        let targets = CCSwitchQuotaCatalog.targets(
            from: [
                record(
                    id: "codex-official",
                    name: "OpenAI Official",
                    website: "https://chatgpt.com/codex",
                    isCurrent: true,
                    meta: #"{"usage_script":{"enabled":true,"templateType":"official_subscription"}}"#,
                    settings: settings(key: "must-not-be-sent", toml: "https://api.openai.com/v1")
                ),
                record(
                    id: "blank-official",
                    name: "OpenAI Official",
                    meta: #"{"usage_script":{"templateType":"official_subscription"}}"#,
                    settings: settings(
                        key: nil,
                        toml: "https://api.openai.com/v1",
                        accessToken: "   "
                    )
                ),
                record(
                    id: "proxy-official",
                    name: "OpenAI Official",
                    meta: #"{"usage_script":{"templateType":"official_subscription"}}"#,
                    settings: settings(
                        key: nil,
                        toml: "https://api.openai.com/v1",
                        accessToken: "proxy-local"
                    )
                ),
                record(
                    id: "kimi",
                    name: "Kimi",
                    meta: #"{"usage_script":{"codingPlanProvider":"kimi"}}"#,
                    settings: settings(key: "unit-test-key", toml: "https://api.kimi.com/coding/v1")
                ),
            ],
            currentProviderID: "codex-official"
        )

        XCTAssertEqual(targets.map(\.id), ["kimi"])
        XCTAssertFalse(targets[0].isCurrent)
        XCTAssertNil(targets[0].accessToken)
    }

    func testHiddenCurrentProviderFallsBackToTheDatabaseFlag() {
        let records = [
            record(id: "hidden", name: "千问", meta: #"{"usage_script":{"enabled":false}}"#),
            record(
                id: "kimi",
                name: "Kimi",
                isCurrent: true,
                meta: #"{"usage_script":{"codingPlanProvider":"kimi"}}"#,
                settings: settings(key: "unit-test-key", toml: "https://api.kimi.com/coding/v1")
            ),
        ]

        let targets = CCSwitchQuotaCatalog.targets(from: records, currentProviderID: "hidden")

        XCTAssertEqual(targets.map(\.id), ["kimi"])
        XCTAssertTrue(targets[0].isCurrent)
    }

    func testRecognizesQwenTokenPlanProvider() {
        let targets = CCSwitchQuotaCatalog.targets(
            from: [
                record(
                    id: "qwen",
                    name: "通义千问 Token Plan",
                    meta: #"{"usage_script":{"enabled":true,"codingPlanProvider":"qwen"}}"#,
                    settings: settings(
                        key: "qwen-key",
                        toml: "https://token-plan.cn-beijing.maas.aliyuncs.com/compatible-mode/v1"
                    )
                ),
            ],
            currentProviderID: nil
        )

        XCTAssertEqual(targets.map(\.kind), [.qwen])
        XCTAssertEqual(targets.first?.shortName, "Qwen")
        XCTAssertEqual(targets.first?.apiKey, "qwen-key")
    }

    func testDisabledMislabeledScriptStillShowsQwenHostWithoutSendingItsKey() {
        let targets = CCSwitchQuotaCatalog.targets(
            from: [
                record(
                    id: "qwen",
                    name: "千问",
                    meta: #"{"usage_script":{"enabled":false,"templateType":"general","codingPlanProvider":"kimi"}}"#,
                    settings: settings(
                        key: "must-not-become-a-kimi-key",
                        toml: "https://token-plan.cn-beijing.maas.aliyuncs.com/compatible-mode/v1"
                    )
                ),
                record(
                    id: "off",
                    name: "DeepSeek off",
                    meta: #"{"usage_script":{"enabled":false,"templateType":"balance"}}"#,
                    settings: settings(key: "should-stay-hidden", toml: "https://api.deepseek.com")
                ),
            ],
            currentProviderID: nil
        )

        XCTAssertEqual(targets.map(\.id), ["qwen"])
        XCTAssertEqual(targets.map(\.kind), [.qwen])
        XCTAssertEqual(targets.first?.apiKey, "must-not-become-a-kimi-key")
    }

    func testReadsKimiBearerTokenFromCodexConfig() {
        let targets = CCSwitchQuotaCatalog.targets(
            from: [
                record(
                    id: "kimi",
                    name: "Kimi For Coding",
                    meta: #"{"usage_script":{"enabled":true,"codingPlanProvider":"kimi"}}"#,
                    settings: settings(
                        key: nil,
                        toml: """
                        model_provider = "custom"
                        [model_providers.custom]
                        base_url = "https://api.kimi.com/coding/v1"
                        experimental_bearer_token = "kimi-bearer"
                        """
                    )
                ),
            ],
            currentProviderID: nil
        )

        XCTAssertEqual(targets.first?.kind, .kimi)
        XCTAssertEqual(targets.first?.apiKey, "kimi-bearer")
    }

    func testDropsProxyKeysLoopbackURLsAndDisambiguatesDuplicateNames() {
        let records = [
            record(
                id: "kimi-a",
                name: "Kimi A",
                createdAt: 1,
                meta: #"{"usage_script":{"codingPlanProvider":"kimi"}}"#,
                settings: settings(key: "proxy-local", toml: "http://127.0.0.1:9/v1")
            ),
            record(
                id: "kimi-b",
                name: "Kimi B",
                createdAt: 2,
                meta: #"{"usage_script":{"codingPlanProvider":"kimi"}}"#,
                settings: settings(key: "unit-test-key", toml: "https://api.kimi.com/coding/v1")
            ),
        ]

        let targets = CCSwitchQuotaCatalog.targets(from: records, currentProviderID: nil)

        XCTAssertEqual(targets.map(\.shortName), ["Kimi", "Kimi 2"])
        XCTAssertNil(targets[0].apiKey)
        XCTAssertNil(targets[0].baseURL)
        XCTAssertEqual(targets[1].apiKey, "unit-test-key")
        XCTAssertEqual(
            CCSwitchQuotaCatalog.zhipuQuotaURL(baseURL: nil).absoluteString,
            "https://api.z.ai/api/monitor/usage/quota/limit"
        )
        XCTAssertEqual(
            CCSwitchQuotaCatalog.zhipuSubscriptionURL(baseURL: nil).absoluteString,
            "https://api.z.ai/api/biz/subscription/list"
        )
    }
}

final class AccountQuotaFormattingTests: XCTestCase {
    func testMenuBarUsesTheShortestSuccessfulWindow() {
        let windows = [
            ParsedQuotaWindow(name: "monthly", utilization: 40, resetsAt: nil),
            ParsedQuotaWindow(name: "weekly_limit", utilization: 20, resetsAt: nil),
            ParsedQuotaWindow(name: "five_hour", utilization: 13, resetsAt: nil),
        ]
        func summary(_ windows: [ParsedQuotaWindow]) -> String? {
            AccountQuotaFormatting.compactMenuBarQuota(
                for: chip(kind: .officialNote, isCurrent: true, status: .windows(windows)),
                language: .chinese
            )
        }
        XCTAssertEqual(summary(windows), "5小时 87%")
        XCTAssertEqual(summary(Array(windows.prefix(2))), "7天 80%")
        XCTAssertEqual(summary(Array(windows.prefix(1))), "1个月 60%")
        XCTAssertNil(summary([ParsedQuotaWindow(
            name: ParsedQuotaWindow.planExpiryName, utilization: 0, resetsAt: nil
        )]))
    }

    func testMenuBarHidesUnqueriedAndStaleQuota() {
        let pending = chip(kind: .officialNote, status: .pending)
        XCTAssertNil(AccountQuotaFormatting.compactMenuBarQuota(for: pending, language: .chinese))
        let stale = AccountQuotaChip(
            id: "current", shortName: "OpenAI", websiteURL: nil,
            kind: .officialNote, isCurrent: true,
            status: .windows([ParsedQuotaWindow(name: "five_hour", utilization: 25, resetsAt: nil)]),
            isStale: true
        )
        XCTAssertNil(AccountQuotaFormatting.compactMenuBarQuota(for: stale, language: .chinese))
        let cachedQwen = chip(
            kind: .qwen,
            status: .qwenWebsite(QwenWebsiteQuota(
                periodLabel: "7天", remainingPercent: 88, resetsAt: nil, isCached: true
            ))
        )
        XCTAssertNil(AccountQuotaFormatting.compactMenuBarQuota(for: cachedQwen, language: .chinese))
    }

    func testFormatsQuotasTheWayCCSwitchShowsThem() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let kimi = chip(
            kind: .kimi,
            status: .windows([
                ParsedQuotaWindow(
                    name: "five_hour",
                    utilization: 0,
                    resetsAt: now.addingTimeInterval(4 * 3600 + 37 * 60)
                ),
            ])
        )
        let kimiExpiry = AccountQuotaFormatting.planExpiryPhrase(
            until: now.addingTimeInterval(4 * 3600 + 37 * 60),
            now: now
        )!
        XCTAssertEqual(
            AccountQuotaFormatting.plainSummary(for: kimi, now: now),
            "5h 100% · \(kimiExpiry)"
        )
        XCTAssertEqual(
            AccountQuotaFormatting.runs(for: kimi, now: now).map(\.tone),
            [.secondary, .green, .secondary, .secondary]
        )
        let kimiHelp = AccountQuotaFormatting.help(for: kimi, now: now)
        XCTAssertTrue(kimiHelp.contains("5h 100%"))
        XCTAssertTrue(kimiHelp.contains(kimiExpiry))
        XCTAssertFalse(kimiHelp.contains("后重置"))
        XCTAssertFalse(kimiHelp.contains("总到期"))
        XCTAssertFalse(AccountQuotaFormatting.plainSummary(for: kimi, now: now).contains("4h37m"))

        let xai = chip(
            kind: .xaiOAuth,
            isCurrent: true,
            status: .windows([
                ParsedQuotaWindow(
                    name: "weekly_limit",
                    utilization: 13,
                    resetsAt: now.addingTimeInterval((6 * 24 + 2) * 3600)
                ),
            ])
        )
        let xaiExpiry = AccountQuotaFormatting.planExpiryPhrase(
            until: now.addingTimeInterval((6 * 24 + 2) * 3600),
            now: now
        )!
        XCTAssertEqual(
            AccountQuotaFormatting.plainSummary(for: xai, now: now),
            "7d 87% · \(xaiExpiry)"
        )
        XCTAssertTrue(AccountQuotaFormatting.help(for: xai, now: now).contains("当前供应商"))
        let xaiHelp = AccountQuotaFormatting.help(for: xai, now: now)
        XCTAssertTrue(xaiHelp.contains("7d 87%"))
        XCTAssertTrue(xaiHelp.contains(xaiExpiry))
        XCTAssertFalse(xaiHelp.contains("后重置"))
        XCTAssertFalse(xaiHelp.contains("总到期"))
        XCTAssertFalse(AccountQuotaFormatting.plainSummary(for: xai, now: now).contains("6d2h"))

        let planEnd = now.addingTimeInterval((40 * 24 + 4) * 3600)
        let zhipu = chip(
            kind: .zhipu,
            status: .windows([
                ParsedQuotaWindow(name: "weekly_limit", utilization: 100, resetsAt: now.addingTimeInterval((2 * 24 + 3) * 3600)),
                ParsedQuotaWindow(name: ParsedQuotaWindow.planExpiryName, utilization: 0, resetsAt: planEnd),
                ParsedQuotaWindow(name: "five_hour", utilization: 0, resetsAt: nil),
            ])
        )
        let planText = AccountQuotaFormatting.planExpiryPhrase(until: planEnd, now: now)!
        XCTAssertEqual(
            AccountQuotaFormatting.plainSummary(for: zhipu, now: now),
            "5h 100% · 7d 0% · \(planText)"
        )
        XCTAssertFalse(AccountQuotaFormatting.plainSummary(for: zhipu, now: now).contains("总到期"))
        XCTAssertEqual(
            AccountQuotaFormatting.runs(for: zhipu, now: now).map(\.tone),
            [.secondary, .green, .secondary, .secondary, .red, .secondary, .secondary]
        )
        let zhipuHelp = AccountQuotaFormatting.help(for: zhipu, now: now)
        XCTAssertTrue(zhipuHelp.contains("5h 100%"))
        XCTAssertTrue(zhipuHelp.contains("7d 0%"))
        XCTAssertFalse(zhipuHelp.contains("后重置"))
        XCTAssertFalse(zhipuHelp.contains("5h 100%，"))
        XCTAssertTrue(zhipuHelp.contains(planText))
        XCTAssertFalse(zhipuHelp.contains("总到期"))
        XCTAssertFalse(zhipuHelp.contains("后到期"))
<<<<<<< Updated upstream
        XCTAssertFalse(zhipuHelp.contains("1个月"))
        XCTAssertFalse(AccountQuotaFormatting.plainSummary(for: zhipu, now: now).contains("1个月"))
=======
        XCTAssertFalse(zhipuHelp.contains("1mo"))
        XCTAssertFalse(AccountQuotaFormatting.plainSummary(for: zhipu, now: now).contains("1mo"))
>>>>>>> Stashed changes
        XCTAssertFalse(AccountQuotaFormatting.plainSummary(for: zhipu, now: now).contains("2d3h"))
        XCTAssertFalse(zhipuHelp.contains("2天3小时后重置"))
        let five = zhipuHelp.range(of: "5h")!
        let week = zhipuHelp.range(of: "7d")!
        let plan = zhipuHelp.range(of: planText)!
        XCTAssertLessThan(five.lowerBound, week.lowerBound)
        XCTAssertLessThan(week.lowerBound, plan.lowerBound)

        let laterReset = now.addingTimeInterval(6 * 86_400)
        let soonerReset = now.addingTimeInterval(3_600)
        let mixed = chip(
            kind: .kimi,
            status: .windows([
                ParsedQuotaWindow(name: "monthly", utilization: 40, resetsAt: laterReset),
                ParsedQuotaWindow(name: "weekly_limit", utilization: 20, resetsAt: laterReset),
                ParsedQuotaWindow(name: "five_hour", utilization: 10, resetsAt: soonerReset),
                ParsedQuotaWindow(name: "credits", utilization: 30, resetsAt: nil),
            ])
        )
        let mixedExpiry = AccountQuotaFormatting.planExpiryPhrase(until: laterReset, now: now)!
        XCTAssertEqual(
            AccountQuotaFormatting.plainSummary(for: mixed, now: now),
<<<<<<< Updated upstream
            "5小时 90% · 7天 80% · 1个月 60% · 额度 70% · \(mixedExpiry)"
        )
        let mixedHelp = AccountQuotaFormatting.help(for: mixed, now: now)
        XCTAssertLessThan(mixedHelp.range(of: "5小时")!.lowerBound, mixedHelp.range(of: "7天")!.lowerBound)
        XCTAssertLessThan(mixedHelp.range(of: "7天")!.lowerBound, mixedHelp.range(of: "1个月")!.lowerBound)
        XCTAssertLessThan(mixedHelp.range(of: "1个月")!.lowerBound, mixedHelp.range(of: mixedExpiry)!.lowerBound)
=======
            "5h 90% · 7d 80% · 1mo 60% · 额度 70% · \(mixedExpiry)"
        )
        let mixedHelp = AccountQuotaFormatting.help(for: mixed, now: now)
        XCTAssertLessThan(mixedHelp.range(of: "5h")!.lowerBound, mixedHelp.range(of: "7d")!.lowerBound)
        XCTAssertLessThan(mixedHelp.range(of: "7d")!.lowerBound, mixedHelp.range(of: "1mo")!.lowerBound)
        XCTAssertLessThan(mixedHelp.range(of: "1mo")!.lowerBound, mixedHelp.range(of: mixedExpiry)!.lowerBound)
>>>>>>> Stashed changes

        let expiredPlan = chip(
            kind: .zhipu,
            status: .windows([
                ParsedQuotaWindow(name: ParsedQuotaWindow.planExpiryName, utilization: 0, resetsAt: now.addingTimeInterval(-60)),
            ])
        )
        XCTAssertEqual(AccountQuotaFormatting.plainSummary(for: expiredPlan, now: now), "已到期")
        // Chip help appends the provider site on its own line. Expired plan
        // copy is only the expiry sentence: no percent, no reset verb.
        XCTAssertEqual(
            AccountQuotaFormatting.help(for: expiredPlan, now: now),
            "已到期\nhttps://example.com"
        )

        let deepseek = chip(
            kind: .deepseek,
            status: .balances([
                ParsedBalance(currency: "USD", amount: 0),
                ParsedBalance(currency: "CNY", amount: 12.36),
            ])
        )
        XCTAssertEqual(AccountQuotaFormatting.plainSummary(for: deepseek, now: now), "余额 12.36 CNY")

        let qwen = chip(
            kind: .qwen,
            status: .note(
                text: AccountQuotaMessage.connectOfficial,
                help: AccountQuotaMessage.connectOfficialHelp
            )
        )
        XCTAssertEqual(AccountQuotaFormatting.plainSummary(for: qwen, now: now), "未连接")
        XCTAssertTrue(AccountQuotaFormatting.help(for: qwen, now: now).contains("不统计本机请求"))
        XCTAssertFalse(AccountQuotaFormatting.help(for: qwen, now: now).contains("本地"))

        let officialQwen = chip(
            kind: .qwen,
            status: .qwenPlan(QwenPlanQuota(
                usedPercent: 28,
                remainingCredits: 18_000,
                totalCredits: 25_000,
                resetsAt: now.addingTimeInterval(2 * 86_400)
            ))
        )
        let qwenPlanEnd = now.addingTimeInterval(2 * 86_400)
        let qwenText = AccountQuotaFormatting.planExpiryPhrase(until: qwenPlanEnd, now: now)!
        XCTAssertEqual(
            AccountQuotaFormatting.plainSummary(for: officialQwen, now: now),
            "7d 72% · \(qwenText)"
        )
        XCTAssertTrue(AccountQuotaFormatting.help(for: officialQwen, now: now).contains("千问官网套餐额度"))
        let qwenHelp = AccountQuotaFormatting.help(for: officialQwen, now: now)
        XCTAssertTrue(qwenHelp.contains("7d 72%"))
        XCTAssertTrue(qwenHelp.contains("剩余 18,000/25,000 Credits"))
        XCTAssertTrue(qwenHelp.contains(qwenText))
        XCTAssertFalse(qwenHelp.contains("总到期"))
        XCTAssertFalse(qwenHelp.contains("后到期"))
        XCTAssertFalse(qwenHelp.contains("后重置"))

        let websiteQwen = chip(
            kind: .qwen,
            status: .qwenWebsite(QwenWebsiteQuota(
<<<<<<< Updated upstream
                periodLabel: "1个月",
=======
                periodLabel: "1mo",
>>>>>>> Stashed changes
                remainingPercent: 6.8,
                resetsAt: now.addingTimeInterval(45 * 60)
            ))
        )
        let websiteExpiry = AccountQuotaFormatting.planExpiryPhrase(
            until: now.addingTimeInterval(45 * 60),
            now: now
        )!
        XCTAssertEqual(
            AccountQuotaFormatting.plainSummary(for: websiteQwen, now: now),
<<<<<<< Updated upstream
            "1个月 6.8% · \(websiteExpiry)"
        )
        let websiteHelp = AccountQuotaFormatting.help(for: websiteQwen, now: now)
        XCTAssertTrue(websiteHelp.contains("1个月 6.8%"))
=======
            "1mo 6.8% · \(websiteExpiry)"
        )
        let websiteHelp = AccountQuotaFormatting.help(for: websiteQwen, now: now)
        XCTAssertTrue(websiteHelp.contains("1mo 6.8%"))
>>>>>>> Stashed changes
        XCTAssertTrue(websiteHelp.contains(websiteExpiry))
        XCTAssertFalse(websiteHelp.contains("后重置"))
        XCTAssertFalse(websiteHelp.contains("总到期"))
        XCTAssertFalse(AccountQuotaFormatting.plainSummary(for: websiteQwen, now: now).contains("45m"))
        XCTAssertFalse(AccountQuotaFormatting.help(for: deepseek, now: now).contains("后重置"))
        XCTAssertFalse(AccountQuotaFormatting.help(for: qwen, now: now).contains("后重置"))

        let qwenWithoutEnd = chip(
            kind: .qwen,
            status: .qwenPlan(QwenPlanQuota(
                usedPercent: 28,
                remainingCredits: 18_000,
                totalCredits: 25_000,
                resetsAt: nil
            ))
        )
        XCTAssertEqual(
            AccountQuotaFormatting.plainSummary(for: qwenWithoutEnd, now: now),
            "7d 72%"
        )
        XCTAssertFalse(AccountQuotaFormatting.help(for: qwenWithoutEnd, now: now).contains("总到期"))
    }

    func testCountdownBoundariesAndUtilizationTones() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertNil(AccountQuotaFormatting.countdown(until: now, now: now))
        XCTAssertNil(AccountQuotaFormatting.countdown(until: now.addingTimeInterval(-1), now: now))
        XCTAssertEqual(AccountQuotaFormatting.countdown(until: now.addingTimeInterval(45 * 60), now: now), "45m")
        XCTAssertEqual(AccountQuotaFormatting.countdown(until: now.addingTimeInterval(90 * 60), now: now), "1h30m")
        XCTAssertEqual(AccountQuotaFormatting.countdown(until: now.addingTimeInterval(24 * 3600), now: now), "24h0m")
        XCTAssertEqual(AccountQuotaFormatting.countdown(until: now.addingTimeInterval(25 * 3600), now: now), "1d1h")
        XCTAssertNil(AccountQuotaFormatting.resetClock(until: now, now: now))
        XCTAssertNil(AccountQuotaFormatting.resetDateText(now.addingTimeInterval(-1), now: now))
        XCTAssertNil(AccountQuotaFormatting.chineseCountdown(until: now, now: now))
        XCTAssertEqual(AccountQuotaFormatting.resetClock(until: now.addingTimeInterval(45 * 60), now: now), "06:58")
        XCTAssertEqual(
            AccountQuotaFormatting.resetDateText(now.addingTimeInterval(45 * 60), now: now),
            "11月15日 06:58"
        )
        XCTAssertEqual(AccountQuotaFormatting.chineseCountdown(until: now.addingTimeInterval(45 * 60), now: now), "45分钟")
        XCTAssertEqual(AccountQuotaFormatting.chineseCountdown(until: now.addingTimeInterval(90 * 60), now: now), "1小时30分")
        XCTAssertEqual(AccountQuotaFormatting.chineseCountdown(until: now.addingTimeInterval(24 * 3600), now: now), "24小时0分")
        XCTAssertEqual(
            AccountQuotaFormatting.resetClock(until: now.addingTimeInterval(24 * 3600), now: now),
            "11月16日 06:13"
        )
        XCTAssertEqual(AccountQuotaFormatting.chineseCountdown(until: now.addingTimeInterval(25 * 3600), now: now), "1天1小时")
        XCTAssertEqual(AccountQuotaFormatting.chineseCountdown(until: now.addingTimeInterval(48 * 3600), now: now), "2天")

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let evening = calendar.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 22, minute: 0))!
        let overnight = calendar.date(from: DateComponents(year: 2026, month: 9, day: 24, hour: 2, minute: 0))!
        XCTAssertEqual(AccountQuotaFormatting.resetClock(until: overnight, now: evening), "9月24日 02:00")
        XCTAssertEqual(AccountQuotaFormatting.resetDateText(overnight, now: evening), "9月24日 02:00")
        XCTAssertEqual(AccountQuotaFormatting.chineseCountdown(until: overnight, now: evening), "4小时0分")
        XCTAssertNil(AccountQuotaFormatting.resetClock(until: evening, now: overnight))
        let sameHour = calendar.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 23, minute: 0))!
        XCTAssertEqual(
            AccountQuotaFormatting.planExpiryPhrase(until: sameHour, now: evening),
            "截至9月23日23时"
        )
        let sameDayWithMinutes = calendar.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 23, minute: 37))!
        XCTAssertEqual(
            AccountQuotaFormatting.planExpiryPhrase(until: sameDayWithMinutes, now: evening),
            "截至9月23日23时37分"
        )
        XCTAssertEqual(
            AccountQuotaFormatting.planExpiryPhrase(until: overnight, now: evening),
            "截至9月24日"
        )
        let withMinutes = calendar.date(from: DateComponents(year: 2026, month: 9, day: 24, hour: 2, minute: 7))!
        XCTAssertEqual(
            AccountQuotaFormatting.planExpiryPhrase(until: withMinutes, now: evening),
            "截至9月24日"
        )
        let midnight = calendar.date(from: DateComponents(year: 2026, month: 9, day: 24, hour: 0, minute: 0))!
        XCTAssertEqual(
            AccountQuotaFormatting.planExpiryPhrase(until: midnight, now: evening),
            "截至9月24日"
        )
        XCTAssertNil(AccountQuotaFormatting.planExpiryPhrase(until: evening, now: overnight))

        let expired = chip(
            kind: .kimi,
            status: .windows([
                ParsedQuotaWindow(name: "five_hour", utilization: 12, resetsAt: now.addingTimeInterval(-60)),
            ])
        )
        XCTAssertEqual(AccountQuotaFormatting.plainSummary(for: expired, now: now), "5h 88%")
        XCTAssertFalse(AccountQuotaFormatting.plainSummary(for: expired, now: now).contains("已到期"))
        XCTAssertFalse(AccountQuotaFormatting.help(for: expired, now: now).contains("后重置"))
        XCTAssertFalse(AccountQuotaFormatting.help(for: expired, now: now).contains("已到期"))

        XCTAssertEqual(AccountQuotaFormatting.tone(forUtilization: 69.4), .green)
        XCTAssertEqual(AccountQuotaFormatting.tone(forUtilization: 69.5), .orange)
        XCTAssertEqual(AccountQuotaFormatting.tone(forUtilization: 89.4), .orange)
        XCTAssertEqual(AccountQuotaFormatting.tone(forUtilization: 89.5), .red)
        XCTAssertEqual(AccountQuotaFormatting.plainSummary(for: chip(kind: .deepseek, status: .balances([
            ParsedBalance(currency: "CNY", amount: 0),
        ])), now: now), AccountQuotaMessage.emptyBalance)
        XCTAssertEqual(
            AccountQuotaFormatting.plainSummary(for: chip(kind: .kimi, status: .windows([])), now: now),
            AccountQuotaMessage.queryFailed
        )
    }

    func testExhaustedWhenAnyUsageWindowHasNoRemaining() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let exhaustedWeekly = chip(
            kind: .zhipu,
            status: .windows([
                ParsedQuotaWindow(name: "five_hour", utilization: 0, resetsAt: nil),
                ParsedQuotaWindow(name: "weekly_limit", utilization: 100, resetsAt: now.addingTimeInterval(86_400)),
            ])
        )
        XCTAssertTrue(AccountQuotaFormatting.isExhausted(exhaustedWeekly))

        let overdrawn = chip(
            kind: .kimi,
            status: .windows([
                ParsedQuotaWindow(name: "monthly", utilization: 140, resetsAt: nil),
            ])
        )
        XCTAssertTrue(AccountQuotaFormatting.isExhausted(overdrawn))

        let usable = chip(
            kind: .kimi,
            status: .windows([
                ParsedQuotaWindow(name: "five_hour", utilization: 12, resetsAt: nil),
                ParsedQuotaWindow(name: "weekly_limit", utilization: 99, resetsAt: nil),
            ])
        )
        XCTAssertFalse(AccountQuotaFormatting.isExhausted(usable))

        // Plan expiry is a date, not usage: a lapsed plan alone does not mark
        // the provider exhausted, and a live plan does not rescue an empty window.
        let lapsedPlanOnly = chip(
            kind: .zhipu,
            status: .windows([
                ParsedQuotaWindow(name: ParsedQuotaWindow.planExpiryName, utilization: 0, resetsAt: now.addingTimeInterval(-60)),
            ])
        )
        XCTAssertFalse(AccountQuotaFormatting.isExhausted(lapsedPlanOnly))

        let exhaustedPlan = chip(
            kind: .qwen,
            status: .qwenPlan(QwenPlanQuota(usedPercent: 100, remainingCredits: 0, totalCredits: 100, resetsAt: nil))
        )
        XCTAssertTrue(AccountQuotaFormatting.isExhausted(exhaustedPlan))
        let usablePlan = chip(
            kind: .qwen,
            status: .qwenPlan(QwenPlanQuota(usedPercent: 10, remainingCredits: 90, totalCredits: 100, resetsAt: nil))
        )
        XCTAssertFalse(AccountQuotaFormatting.isExhausted(usablePlan))

        let exhaustedWebsite = chip(
            kind: .qwen,
            status: .qwenWebsite(QwenWebsiteQuota(periodLabel: "1mo", remainingPercent: 0, resetsAt: nil))
        )
        XCTAssertTrue(AccountQuotaFormatting.isExhausted(exhaustedWebsite))

        XCTAssertTrue(AccountQuotaFormatting.isExhausted(chip(kind: .deepseek, status: .balances([
            ParsedBalance(currency: "CNY", amount: 0),
        ]))))
        XCTAssertFalse(AccountQuotaFormatting.isExhausted(chip(kind: .deepseek, status: .balances([
            ParsedBalance(currency: "CNY", amount: 0.5),
        ]))))
        XCTAssertFalse(AccountQuotaFormatting.isExhausted(chip(kind: .kimi, status: .windows([]))))
        XCTAssertFalse(AccountQuotaFormatting.isExhausted(chip(kind: .kimi, status: .message(AccountQuotaMessage.queryFailed))))
    }

    func testSortsWindowsByLatestResetFirst() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let soon = now.addingTimeInterval(3_600)
        let later = now.addingTimeInterval(6 * 86_400)
        let windows = [
            ParsedQuotaWindow(name: "five_hour", utilization: 10, resetsAt: soon),
            ParsedQuotaWindow(name: "weekly_limit", utilization: 20, resetsAt: later),
            ParsedQuotaWindow(name: "credits", utilization: 30, resetsAt: nil),
            ParsedQuotaWindow(name: "monthly", utilization: 40, resetsAt: later),
        ]
        XCTAssertEqual(
            AccountQuotaFormatting.sortedWindows(windows).map(\.name),
            ["weekly_limit", "monthly", "five_hour", "credits"]
        )

        let fiveHourLater = [
            ParsedQuotaWindow(name: "weekly_limit", utilization: 1, resetsAt: soon),
            ParsedQuotaWindow(name: "five_hour", utilization: 1, resetsAt: later),
        ]
        XCTAssertEqual(
            AccountQuotaFormatting.sortedWindows(fiveHourLater).map(\.name),
            ["five_hour", "weekly_limit"]
        )
    }

    func testSortsChipsByEarliestExpiryFirstWithoutPinningCurrent() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let soon = now.addingTimeInterval(3_600)
        let mid = now.addingTimeInterval(3 * 86_400)
        let late = now.addingTimeInterval(10 * 86_400)
        let chips = [
            quotaChip(id: "note", kind: .xaiOAuth, status: .note(text: "未连接", help: "help")),
            quotaChip(
                id: "current",
                kind: .kimi,
                isCurrent: true,
                status: .windows([
                    ParsedQuotaWindow(name: "five_hour", utilization: 1, resetsAt: soon),
                    ParsedQuotaWindow(name: "weekly_limit", utilization: 1, resetsAt: mid),
                ])
            ),
            quotaChip(
                id: "balance",
                kind: .deepseek,
                status: .balances([ParsedBalance(currency: "CNY", amount: 1)])
            ),
            quotaChip(
                id: "plan",
                kind: .qwen,
                status: .qwenPlan(QwenPlanQuota(
                    usedPercent: 10,
                    remainingCredits: 90,
                    totalCredits: 100,
                    resetsAt: mid
                ))
            ),
            quotaChip(
                id: "website",
                kind: .officialNote,
                status: .qwenWebsite(QwenWebsiteQuota(
                    periodLabel: "7d",
                    remainingPercent: 50,
                    resetsAt: soon
                ))
            ),
            quotaChip(
                id: "latest",
                kind: .zhipu,
                status: .windows([
                    ParsedQuotaWindow(name: "five_hour", utilization: 1, resetsAt: soon),
                    ParsedQuotaWindow(name: "weekly_limit", utilization: 1, resetsAt: late),
                ])
            ),
            quotaChip(
                id: "same",
                kind: .kimi,
                status: .windows([
                    ParsedQuotaWindow(name: "weekly_limit", utilization: 1, resetsAt: mid),
                ])
            ),
        ]

        XCTAssertEqual(
            AccountQuotaFormatting.sortedChips(chips).map(\.id),
            ["website", "current", "plan", "same", "latest", "note", "balance"]
        )
    }

    func testZhipuPlanExpiryIsTheCardExpiryForProviderOrder() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let weekly = now.addingTimeInterval(7 * 86_400)
        let other = now.addingTimeInterval(20 * 86_400)
        let planEnd = now.addingTimeInterval(40 * 86_400)
        let chips = [
            quotaChip(
                id: "other",
                kind: .kimi,
                status: .windows([
                    ParsedQuotaWindow(name: "weekly_limit", utilization: 1, resetsAt: other),
                ])
            ),
            quotaChip(
                id: "zhipu",
                kind: .zhipu,
                status: .windows([
                    ParsedQuotaWindow(name: "weekly_limit", utilization: 10, resetsAt: weekly),
                    ParsedQuotaWindow(name: ParsedQuotaWindow.planExpiryName, utilization: 0, resetsAt: planEnd),
                ])
            ),
        ]
        XCTAssertEqual(AccountQuotaFormatting.sortedChips(chips).map(\.id), ["other", "zhipu"])
    }
}

private func quotaChip(
    id: String,
    kind: CCSwitchQuotaKind,
    isCurrent: Bool = false,
    status: AccountQuotaChip.Status
) -> AccountQuotaChip {
    AccountQuotaChip(
        id: id,
        shortName: id,
        websiteURL: nil,
        kind: kind,
        isCurrent: isCurrent,
        status: status
    )
}

final class CCSwitchQuotaParserTests: XCTestCase {
    func testParsesOfficialQwenPlanCredits() {
        let data = Data(#"""
        {"token_plan":{"subscribed":true,"totalCredits":25000,"remainingCredits":18000,"usedPct":28,"resetDate":"2026-08-01T00:00:00.000Z"}}
        """#.utf8)
        XCTAssertEqual(
            QwenPlanQuotaParser.parse(data),
            QwenPlanQuota(
                usedPercent: 28,
                remainingCredits: 18_000,
                totalCredits: 25_000,
                resetsAt: ISO8601DateFormatter().date(from: "2026-08-01T00:00:00Z")
            )
        )
        XCTAssertNil(QwenPlanQuotaParser.parse(Data(#"{"token_plan":{"subscribed":false}}"#.utf8)))
    }

    func testParsesQwenWebsiteQuotaText() {
        let data = Data("个人版 Pro 套餐\n月额度 剩余量 6.8 %\n重置时间 2026-10-05 00:00:00".utf8)
        let quota = QwenWebsiteQuotaParser.parse(data)
<<<<<<< Updated upstream
        XCTAssertEqual(quota?.periodLabel, "1个月")
=======
        XCTAssertEqual(quota?.periodLabel, "1mo")
>>>>>>> Stashed changes
        XCTAssertEqual(quota?.remainingPercent, 6.8)
        XCTAssertEqual(
            quota?.resetsAt?.timeIntervalSince1970,
            ISO8601DateFormatter().date(from: "2026-10-04T16:00:00Z")?.timeIntervalSince1970
        )
        let capturedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let persisted = quota.flatMap {
            QwenWebsiteQuotaParser.persistedData(for: $0, capturedAt: capturedAt)
        }
        let cached = persisted.flatMap(QwenWebsiteQuotaParser.parse)
<<<<<<< Updated upstream
        XCTAssertEqual(cached?.periodLabel, "1个月")
=======
        XCTAssertEqual(cached?.periodLabel, "1mo")
>>>>>>> Stashed changes
        XCTAssertEqual(cached?.remainingPercent, 6.8)
        XCTAssertEqual(cached?.capturedAt, capturedAt)
        XCTAssertEqual(cached?.isCached, true)
    }

    func testParsesKimiZhipuAndDeepSeekBodiesWithoutKeepingRawText() {
        let kimi = CCSwitchQuotaParsers.parseKimi(Data(#"""
        {"limits":[{"detail":{"limit":100,"remaining":100,"resetTime":"2026-09-22T08:37:00Z"}}],"usage":{"limit":200,"remaining":50,"resetTime":1760000000}}
        """#.utf8))
        guard case let .windows(kimiWindows) = kimi else {
            return XCTFail("expected kimi windows")
        }
        XCTAssertEqual(kimiWindows.map(\.name), ["five_hour", "weekly_limit"])
        XCTAssertEqual(kimiWindows.map { AccountQuotaFormatting.roundedPercent($0.utilization) }, [0, 75])
        XCTAssertNotNil(kimiWindows[0].resetsAt)
        XCTAssertNotNil(kimiWindows[1].resetsAt)

        let zhipu = CCSwitchQuotaParsers.parseZhipu(Data(#"""
        {"success":true,"data":{"limits":[{"type":"tokens_limit","unit":3,"percentage":0,"nextResetTime":1700000000000},{"type":"tokens_limit","unit":6,"percentage":100,"nextResetTime":1700200000000}]}}
        """#.utf8))
        guard case let .windows(zhipuWindows) = zhipu else {
            return XCTFail("expected zhipu windows")
        }
        XCTAssertEqual(zhipuWindows.map(\.name), ["five_hour", "weekly_limit"])
        XCTAssertEqual(zhipuWindows.map(\.utilization), [0, 100])

        let deepseek = CCSwitchQuotaParsers.parseDeepSeek(Data(#"""
        {"balance_infos":[{"currency":"CNY","total_balance":"12.36"},{"currency":"USD","total_balance":0}]}
        """#.utf8))
        guard case let .balances(balances) = deepseek else {
            return XCTFail("expected balances")
        }
        XCTAssertEqual(balances, [
            ParsedBalance(currency: "CNY", amount: 12.36),
            ParsedBalance(currency: "USD", amount: 0),
        ])
    }

    func testRejectsMalformedBodies() {
        XCTAssertEqual(CCSwitchQuotaParsers.parseKimi(Data("not-json".utf8)), .rejected)
        XCTAssertEqual(CCSwitchQuotaParsers.parseZhipu(Data(#"{"success":false}"#.utf8)), .rejected)
        XCTAssertEqual(CCSwitchQuotaParsers.parseDeepSeek(Data("[]".utf8)), .rejected)
        XCTAssertEqual(CCSwitchQuotaParsers.parseKimi(Data(#"{}"#.utf8)), .windows([]))
    }

    func testParsesKimiResetDatesFromCountRatioAndCLIBodies() {
        let counted = CCSwitchQuotaParsers.parseKimi(Data(#"""
        {"usage":{"limit":"2048","used":"10","remaining":"1834","resetTime":"2026-01-09T15:23:13.716839300Z"},"limits":[{"window":{"duration":300,"timeUnit":"TIME_UNIT_MINUTE"},"detail":{"limit":"200","used":"1","remaining":"61","resetTime":"2026-01-06T13:33:02.717479433Z"}}]}
        """#.utf8))
        guard case let .windows(countedWindows) = counted else {
            return XCTFail("expected counted kimi windows")
        }
        XCTAssertEqual(countedWindows.map(\.name), ["five_hour", "weekly_limit"])
        XCTAssertEqual(countedWindows[0].utilization, 69.5, accuracy: 0.0001)
        XCTAssertEqual(countedWindows[1].utilization, Double(2048 - 1834) / 2048 * 100, accuracy: 0.0001)
        assertReset(countedWindows[0].resetsAt, equals: "2026-01-06T13:33:02.717Z")
        assertReset(countedWindows[1].resetsAt, equals: "2026-01-09T15:23:13.716Z")

        let longFraction = "2026-01-09T15:23:13.716" + String(repeating: "8", count: 15) + "Z"
        let truncated = CCSwitchQuotaParsers.parseKimi(Data("""
        {"usage":{"limit":100,"remaining":100,"resetTime":"\(longFraction)"}}
        """.utf8))
        guard case let .windows(truncatedWindows) = truncated else {
            return XCTFail("expected truncated kimi reset")
        }
        assertReset(truncatedWindows.first?.resetsAt, equals: "2026-01-09T15:23:13.716Z")

        let alternateKeys = CCSwitchQuotaParsers.parseKimi(Data(#"""
        {"limits":[{"detail":{"limit":"100","remaining":"25","reset_at":"1760000000"}}],"usage":{"limit":80,"used":20,"resetAt":"1760000000000"}}
        """#.utf8))
        guard case let .windows(alternateWindows) = alternateKeys else {
            return XCTFail("expected alternate kimi reset keys")
        }
        XCTAssertEqual(alternateWindows.map(\.name), ["five_hour", "weekly_limit"])
        XCTAssertEqual(alternateWindows.map { AccountQuotaFormatting.roundedPercent($0.utilization) }, [75, 25])
        XCTAssertEqual(alternateWindows[0].resetsAt, Date(timeIntervalSince1970: 1_760_000_000))
        XCTAssertEqual(alternateWindows[1].resetsAt, Date(timeIntervalSince1970: 1_760_000_000))

        let missingReset = CCSwitchQuotaParsers.parseKimi(Data(#"""
        {"limits":[{"detail":{"limit":100,"remaining":40,"resetTime":"not-a-date"}}],"usage":{"limit":80,"remaining":20,"resetTime":""}}
        """#.utf8))
        guard case let .windows(missingWindows) = missingReset else {
            return XCTFail("expected kimi windows without resets")
        }
        XCTAssertEqual(missingWindows.map(\.name), ["five_hour", "weekly_limit"])
        XCTAssertEqual(missingWindows.map { AccountQuotaFormatting.roundedPercent($0.utilization) }, [60, 75])
        XCTAssertNil(missingWindows[0].resetsAt)
        XCTAssertNil(missingWindows[1].resetsAt)

        let ratios = CCSwitchQuotaParsers.parseKimi(Data(#"""
        {"usages":{"limit_5h":{"used_ratio":0.5,"reset_time":"2026-09-22T08:37:00Z"},"limit_7d":{"used_ratio":1.4,"reset_time":"2026-09-29T08:37:00Z"},"limit_month_total":{"used_ratio":"0.25","reset_time":1760500000}},"limits":[{"detail":{"limit":100,"remaining":0,"resetTime":"2026-09-22T08:37:00Z"}}],"usage":{"limit":200,"remaining":0,"resetTime":"2026-09-29T08:37:00Z"}}
        """#.utf8))
        guard case let .windows(ratioWindows) = ratios else {
            return XCTFail("expected kimi ratio windows")
        }
        XCTAssertEqual(ratioWindows.map(\.name), ["five_hour", "weekly_limit", "monthly"])
        XCTAssertEqual(ratioWindows[0].utilization, 50, accuracy: 0.0001)
        XCTAssertEqual(ratioWindows[1].utilization, 100, accuracy: 0.0001)
        XCTAssertEqual(ratioWindows[2].utilization, 25, accuracy: 0.0001)
        XCTAssertEqual(ratioWindows[2].resetsAt, Date(timeIntervalSince1970: 1_760_500_000))
        XCTAssertNotNil(ratioWindows[0].resetsAt)
        XCTAssertNotNil(ratioWindows[1].resetsAt)

        let weeklyOnly = CCSwitchQuotaParsers.parseKimi(Data(#"""
        {"usages":{"limit_7d":{"used_ratio":0.2,"reset_time":"2026-09-29T08:37:00Z"}}}
        """#.utf8))
        guard case let .windows(weeklyOnlyWindows) = weeklyOnly else {
            return XCTFail("expected weekly-only ratio")
        }
        XCTAssertEqual(weeklyOnlyWindows.map(\.name), ["weekly_limit"])
        XCTAssertEqual(weeklyOnlyWindows[0].utilization, 20, accuracy: 0.0001)

        let fallback = CCSwitchQuotaParsers.parseKimi(Data(#"""
        {"usages":{"limit_5h":{"used_ratio":0,"reset_time":"2026-09-22T08:37:00Z"},"limit_7d":{"used_ratio":0,"reset_time":"2026-09-29T08:37:00Z"}},"limits":[{"window":{"duration":300,"timeUnit":"TIME_UNIT_MINUTE"},"detail":{"limit":100,"used":60,"remaining":40,"resetTime":"2026-09-22T08:37:01Z"}}],"usage":{"limit":200,"used":150,"remaining":50,"resetTime":"2026-09-29T08:37:01.500Z"}}
        """#.utf8))
        guard case let .windows(fallbackWindows) = fallback else {
            return XCTFail("expected kimi count fallback")
        }
        XCTAssertEqual(fallbackWindows.map(\.name), ["five_hour", "weekly_limit"])
        XCTAssertEqual(fallbackWindows.map { AccountQuotaFormatting.roundedPercent($0.utilization) }, [60, 75])

        let monthlyKeepsZero = CCSwitchQuotaParsers.parseKimi(Data(#"""
        {"usages":{"limit_5h":{"used_ratio":0,"reset_time":"2026-09-22T08:37:00Z"},"limit_month_total":{"used_ratio":0.4,"reset_time":"2026-10-22T08:37:00Z"}},"limits":[{"detail":{"limit":100,"remaining":40,"resetTime":"2026-09-22T08:37:00Z"}}],"usage":{"limit":200,"remaining":50,"resetTime":"2026-09-29T08:37:00Z"}}
        """#.utf8))
        guard case let .windows(monthlyWindows) = monthlyKeepsZero else {
            return XCTFail("expected monthly ratio to keep the zero session")
        }
        XCTAssertEqual(monthlyWindows.map(\.name), ["five_hour", "weekly_limit", "monthly"])
        XCTAssertEqual(monthlyWindows.map { AccountQuotaFormatting.roundedPercent($0.utilization) }, [0, 75, 40])

        let mismatched = CCSwitchQuotaParsers.parseKimi(Data(#"""
        {"usages":{"limit_5h":{"used_ratio":0,"reset_time":"2026-09-22T08:37:00Z"}},"limits":[{"window":{"duration":7,"timeUnit":"TIME_UNIT_DAY"},"detail":{"limit":100,"remaining":40,"resetTime":"2026-09-22T08:37:00Z"}}],"usage":{"limit":200,"remaining":50,"resetTime":"2026-09-29T08:37:00Z"}}
        """#.utf8))
        guard case let .windows(mismatchedWindows) = mismatched else {
            return XCTFail("expected mismatched period to keep the zero ratio")
        }
        XCTAssertEqual(mismatchedWindows.map(\.name), ["five_hour", "weekly_limit"])
        XCTAssertEqual(mismatchedWindows.map { AccountQuotaFormatting.roundedPercent($0.utilization) }, [0, 75])

        let drifted = CCSwitchQuotaParsers.parseKimi(Data(#"""
        {"usages":{"limit_5h":{"used_ratio":0,"reset_time":"2026-09-22T08:37:00Z"},"limit_7d":{"used_ratio":0,"reset_time":"2026-09-29T08:37:00Z"}},"limits":[{"detail":{"limit":100,"remaining":40,"resetTime":"2026-09-22T08:37:03Z"}}],"usage":{"limit":200,"remaining":50,"resetTime":"2026-09-29T08:37:03Z"}}
        """#.utf8))
        guard case let .windows(driftedWindows) = drifted else {
            return XCTFail("expected drifted resets to keep zero ratios")
        }
        XCTAssertEqual(driftedWindows.map { AccountQuotaFormatting.roundedPercent($0.utilization) }, [0, 0])

        let cli = CCSwitchQuotaParsers.parseKimi(Data(#"""
        {"data":{"quota":{"usages":{"limit5h":{"usedRatio":0.1,"resetAt":"2026-09-22T08:37:00Z"},"limit7d":{"usedRatio":0.2,"resetAt":1760000000},"monthTotal":{"usedRatio":0.3,"resetAt":"2026-10-22T08:37:00Z"},"monthCode":{"usedRatio":0.9,"resetAt":"2026-10-01T00:00:00Z"}}}}}
        """#.utf8))
        guard case let .windows(cliWindows) = cli else {
            return XCTFail("expected kimi cli windows")
        }
        XCTAssertEqual(cliWindows.map(\.name), ["five_hour", "weekly_limit", "monthly"])
        XCTAssertEqual(cliWindows.map { AccountQuotaFormatting.roundedPercent($0.utilization) }, [10, 20, 30])
        XCTAssertNotNil(cliWindows[0].resetsAt)
        XCTAssertEqual(cliWindows[1].resetsAt, Date(timeIntervalSince1970: 1_760_000_000))
        XCTAssertNotNil(cliWindows[2].resetsAt)

        let web = CCSwitchQuotaParsers.parseKimi(Data(#"""
        {"usages":[{"scope":"FEATURE_OTHER","detail":{"limit":1,"remaining":0}},{"scope":"FEATURE_CODING","detail":{"limit":"2048","remaining":"1834","resetTime":"2026-01-09T15:23:13.716839300Z"},"limits":[{"window":{"duration":300,"timeUnit":"TIME_UNIT_MINUTE"},"detail":{"limit":"200","remaining":"61","resetTime":"2026-01-06T13:33:02.717479433Z"}}]}]}
        """#.utf8))
        guard case let .windows(webWindows) = web else {
            return XCTFail("expected kimi web windows")
        }
        XCTAssertEqual(webWindows.map(\.name), ["five_hour", "weekly_limit"])
        XCTAssertEqual(webWindows[0].utilization, 69.5, accuracy: 0.0001)
        assertReset(webWindows[0].resetsAt, equals: "2026-01-06T13:33:02.717Z")
        assertReset(webWindows[1].resetsAt, equals: "2026-01-09T15:23:13.716Z")
        XCTAssertEqual(
            CCSwitchQuotaParsers.parseKimi(Data(#"""
            {"usages":[{"scope":"FEATURE_OTHER","detail":{"limit":1,"remaining":0}}]}
            """#.utf8)),
            .windows([])
        )
    }

    func testKeepsOrdinaryISOResetDates() {
        let parsed = CCSwitchQuotaParsers.parseOpenAI(Data(#"""
        {"rate_limit":{"primary_window":{"used_percent":1,"limit_window_seconds":18000,"reset_at":"2026-09-22T08:37:00Z"},"secondary_window":{"used_percent":2,"limit_window_seconds":604800,"reset_at":"2026-09-22T08:37:00.500Z"}}}
        """#.utf8))
        guard case let .windows(windows) = parsed else {
            return XCTFail("expected openai windows")
        }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        XCTAssertEqual(
            windows.first { $0.name == "five_hour" }?.resetsAt,
            plain.date(from: "2026-09-22T08:37:00Z")
        )
        XCTAssertEqual(
            windows.first { $0.name == "weekly_limit" }?.resetsAt,
            fractional.date(from: "2026-09-22T08:37:00.500Z")
        )
    }

    private func assertReset(
        _ date: Date?,
        equals iso: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date, let expected = formatter.date(from: iso) else {
            return XCTFail("missing reset \(String(describing: date)) expected \(iso)", file: file, line: line)
        }
        XCTAssertEqual(date.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 0.001, file: file, line: line)
    }

    private func shanghaiFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }

    func testParsesZhipuPlanExpiryFromNextRenewTime() {
        let body = Data(#"""
        {"success":true,"data":[
          {"status":"VALID","inCurrentPeriod":false,"valid":"2026-10-03 10:00:00-2026-12-03 10:00:00","nextRenewTime":"2026-12-03"},
          {"status":"INVALID","inCurrentPeriod":true,"valid":"2026-10-03 10:00:00-2027-01-03 10:00:00","nextRenewTime":"2027-01-03"},
          {"status":"VALID","inCurrentPeriod":true,"valid":"2026-10-03 10:00:00-2026-11-03 10:00:00","nextRenewTime":"2026-10-03"},
          {"status":"VALID","inCurrentPeriod":true,"valid":"2026-09-03 10:00:00-2026-10-03 10:00:00","nextRenewTime":"2099-01-01"}
        ]}
        """#.utf8)
        let window = CCSwitchQuotaParsers.parseZhipuSubscription(body)
        XCTAssertEqual(window?.name, ParsedQuotaWindow.planExpiryName)
        XCTAssertEqual(window?.utilization, 0)
        let formatter = shanghaiFormatter()
        XCTAssertEqual(window?.resetsAt, formatter.date(from: "2026-10-03 10:00:00"))
        XCTAssertNotEqual(window?.resetsAt, formatter.date(from: "2026-10-03 00:00:00"))
        XCTAssertNotEqual(window?.resetsAt, formatter.date(from: "2026-11-03 10:00:00"))
        XCTAssertNotEqual(window?.resetsAt, formatter.date(from: "2026-09-24 21:12:00"))
        XCTAssertNotEqual(window?.resetsAt, formatter.date(from: "2099-01-01 00:00:00"))

        let timed = CCSwitchQuotaParsers.parseZhipuSubscription(Data(
            #"{"success":true,"data":[{"status":"VALID","inCurrentPeriod":true,"valid":"2026-10-03 10:00:00-2026-11-03 10:00:00","nextRenewTime":"2026-10-03 21:12:47"}]}"#.utf8
        ))
        XCTAssertEqual(timed?.resetsAt, formatter.date(from: "2026-10-03 21:12:47"))

        let dateOnly = CCSwitchQuotaParsers.parseZhipuSubscription(Data(
            #"{"success":true,"data":[{"status":"VALID","inCurrentPeriod":true,"nextRenewTime":"2026-10-03"}]}"#.utf8
        ))
        XCTAssertEqual(dateOnly?.resetsAt, formatter.date(from: "2026-10-03 00:00:00"))

        let otherDay = CCSwitchQuotaParsers.parseZhipuSubscription(Data(
            #"{"success":true,"data":[{"status":"VALID","inCurrentPeriod":true,"valid":"2026-09-03 21:12:47-2026-10-03 21:12:47","nextRenewTime":"2026-10-03"}]}"#.utf8
        ))
        XCTAssertEqual(otherDay?.resetsAt, formatter.date(from: "2026-10-03 00:00:00"))
        XCTAssertNotEqual(otherDay?.resetsAt, formatter.date(from: "2026-10-03 21:12:47"))
    }

    func testZhipuPlanExpiryFallsBackToTheValidRangeEnd() {
        let body = Data(#"""
        {"success":true,"data":[
          {"status":"VALID","inCurrentPeriod":true,"valid":"2026-10-03 10:00:00-2026-11-03 10:00:00","nextRenewTime":" "},
          {"status":"VALID","inCurrentPeriod":true,"valid":"2099-01-01 00:00:00-2099-02-01 00:00:00","nextRenewTime":"2099-01-01"}
        ]}
        """#.utf8)
        let window = CCSwitchQuotaParsers.parseZhipuSubscription(body)
        XCTAssertEqual(window?.resetsAt, shanghaiFormatter().date(from: "2026-11-03 10:00:00"))
    }

    func testZhipuSubscriptionWithoutACurrentPeriodAddsNothing() {
        XCTAssertNil(CCSwitchQuotaParsers.parseZhipuSubscription(Data(#"{"success":false}"#.utf8)))
        XCTAssertNil(CCSwitchQuotaParsers.parseZhipuSubscription(Data("not-json".utf8)))
        XCTAssertNil(CCSwitchQuotaParsers.parseZhipuSubscription(Data(
            #"{"success":true,"data":[{"status":"VALID","inCurrentPeriod":false,"valid":"2026-10-03 10:00:00-2026-12-03 10:00:00","nextRenewTime":"2026-10-03"}]}"#.utf8
        )))
    }

    func testParsesOpenAIPlanExpiryOnlyFromTheMatchingAccount() {
        let iso = Data(#"""
        {"accounts":{
          "other":{"entitlement":{"expires_at":"2026-01-01T00:00:00Z","renews_at":"2026-12-01T00:00:00Z"}},
          "account-id":{"entitlement":{"expires_at":"2026-10-15T00:00:00Z","renews_at":"2026-09-15T00:00:00Z"}}
        },"account_ordering":["other","account-id"]}
        """#.utf8)
        let window = CCSwitchQuotaParsers.parseOpenAIPlanExpiry(iso, accountID: "account-id")
        XCTAssertEqual(window?.name, ParsedQuotaWindow.planExpiryName)
        XCTAssertEqual(window?.utilization, 0)
        XCTAssertEqual(window?.resetsAt, ISO8601DateFormatter().date(from: "2026-10-15T00:00:00Z"))
        XCTAssertNotEqual(window?.resetsAt, ISO8601DateFormatter().date(from: "2026-09-15T00:00:00Z"))
        XCTAssertNotEqual(window?.resetsAt, ISO8601DateFormatter().date(from: "2026-01-01T00:00:00Z"))

        let millis = Data(#"""
        {"accounts":{"account-id":{"entitlement":{"expires_at":1790000000000,"renews_at":1700000000}}}}
        """#.utf8)
        XCTAssertEqual(
            CCSwitchQuotaParsers.parseOpenAIPlanExpiry(millis, accountID: "account-id")?.resetsAt,
            Date(timeIntervalSince1970: 1_790_000_000)
        )
        XCTAssertNil(CCSwitchQuotaParsers.parseOpenAIPlanExpiry(iso, accountID: "missing"))
        XCTAssertNil(CCSwitchQuotaParsers.parseOpenAIPlanExpiry(iso, accountID: "  "))
        XCTAssertNil(CCSwitchQuotaParsers.parseOpenAIPlanExpiry(
            Data(#"{"accounts":{"account-id":{"entitlement":{"renews_at":"2026-10-15T00:00:00Z"}}}}"#.utf8),
            accountID: "account-id"
        ))
        XCTAssertNil(CCSwitchQuotaParsers.parseOpenAIPlanExpiry(Data("not-json".utf8), accountID: "account-id"))
    }
}

final class AccountQuotaClientTests: XCTestCase {
    func testQueriesOnlyTheProviderHostAndKeepsTargetOrder() async throws {
        let transport = ScriptedQuotaTransport { request in
            let body: String
            switch request.url?.host {
            case "chatgpt.com":
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer official-token")
                XCTAssertEqual(request.value(forHTTPHeaderField: "ChatGPT-Account-ID"), "account-id")
                switch request.url?.path {
                case "/backend-api/wham/usage":
                    body = #"{"rate_limit":{"primary_window":{"used_percent":42,"limit_window_seconds":18000,"reset_at":1760000000},"secondary_window":{"used_percent":13,"limit_window_seconds":604800,"reset_at":1760500000}}}"#
                case "/backend-api/accounts/check/v4-2023-04-27":
                    body = "{}"
                default:
                    XCTFail("unexpected official path \(request.url?.path ?? "")")
                    body = "{}"
                }
            case "api.kimi.com":
                XCTAssertEqual(request.url?.path, "/coding/v1/usages")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer unit-test-key")
                body = #"{"limits":[{"detail":{"limit":100,"remaining":100,"resetTime":1760000000000}}]}"#
            case "api.deepseek.com":
                XCTAssertEqual(request.url?.path, "/user/balance")
                body = #"{"balance_infos":[{"currency":"CNY","total_balance":"12.36"}]}"#
            default:
                XCTFail("unexpected host \(request.url?.absoluteString ?? "")")
                body = "{}"
            }
            return AccountQuotaHTTPResponse(statusCode: 200, headers: [:], body: Data(body.utf8))
        }
        let client = AccountQuotaClient(
            transport: transport,
            authFileURL: URL(fileURLWithPath: "/tmp/missing-xai-auth-\(UUID().uuidString).json")
        )
        let targets = [
            quotaTarget(
                id: "official",
                name: "OpenAI",
                kind: .officialNote,
                key: "must-not-be-sent",
                accessToken: "official-token",
                accountID: "account-id"
            ),
            quotaTarget(id: "kimi", name: "Kimi", kind: .kimi, key: "unit-test-key"),
            quotaTarget(id: "deepseek", name: "DeepSeek", kind: .deepseek, key: "unit-test-key", baseURL: "https://api.deepseek.com"),
        ]

        let chips = try await client.refresh(targets: targets)

        XCTAssertEqual(chips.map(\.id), ["official", "kimi", "deepseek"])
        XCTAssertEqual(chips.map(\.status), [
            .windows([
                ParsedQuotaWindow(
                    name: "five_hour",
                    utilization: 42,
                    resetsAt: Date(timeIntervalSince1970: 1_760_000_000)
                ),
                ParsedQuotaWindow(
                    name: "weekly_limit",
                    utilization: 13,
                    resetsAt: Date(timeIntervalSince1970: 1_760_500_000)
                ),
            ]),
            .windows([
                ParsedQuotaWindow(
                    name: "five_hour",
                    utilization: 0,
                    resetsAt: Date(timeIntervalSince1970: 1_760_000_000)
                ),
            ]),
            .balances([ParsedBalance(currency: "CNY", amount: 12.36)]),
        ])
        let hosts = transport.requests.compactMap { $0.url?.host }
        XCTAssertEqual(hosts.sorted(), ["api.deepseek.com", "api.kimi.com", "chatgpt.com", "chatgpt.com"])
        XCTAssertEqual(
            transport.requests.compactMap { request -> String? in
                guard request.url?.host == "chatgpt.com" else { return nil }
                return request.url?.path
            },
            [
                "/backend-api/wham/usage",
                "/backend-api/accounts/check/v4-2023-04-27",
            ]
        )
        XCTAssertFalse(chips.contains { AccountQuotaFormatting.plainSummary(for: $0, now: Date()).contains("unit-test-key") })
    }

    func testOfficialPlanExpiryUsesTheMatchingAccountAndKeepsUsageIfCheckFails() async throws {
        let usage = #"{"rate_limit":{"primary_window":{"used_percent":42,"limit_window_seconds":18000,"reset_at":1760000000},"secondary_window":{"used_percent":13,"limit_window_seconds":604800,"reset_at":1760500000}}}"#
        let usageWindows = [
            ParsedQuotaWindow(name: "five_hour", utilization: 42, resetsAt: Date(timeIntervalSince1970: 1_760_000_000)),
            ParsedQuotaWindow(name: "weekly_limit", utilization: 13, resetsAt: Date(timeIntervalSince1970: 1_760_500_000)),
        ]
        let check = #"""
        {"accounts":{
          "other-account":{"entitlement":{"expires_at":"2026-01-01T00:00:00Z","renews_at":"2026-12-31T00:00:00Z"}},
          "account-id":{"entitlement":{"expires_at":"2026-10-15T00:00:00Z","renews_at":"2026-09-15T00:00:00Z"}}
        },"account_ordering":["other-account"]}
        """#
        let matched = ScriptedQuotaTransport { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer official-token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "ChatGPT-Account-ID"), "account-id")
            let body = request.url?.path == "/backend-api/accounts/check/v4-2023-04-27" ? check : usage
            return AccountQuotaHTTPResponse(statusCode: 200, headers: [:], body: Data(body.utf8))
        }
        let matchedChips = try await AccountQuotaClient(transport: matched).refresh(targets: [
            quotaTarget(
                id: "official",
                name: "OpenAI",
                kind: .officialNote,
                key: "must-not-be-sent",
                accessToken: "official-token",
                accountID: "account-id"
            ),
        ])
        XCTAssertEqual(matched.requests.map { $0.url?.path }, [
            "/backend-api/wham/usage",
            "/backend-api/accounts/check/v4-2023-04-27",
        ])
        XCTAssertEqual(matchedChips.map(\.status), [
            .windows(usageWindows + [
                ParsedQuotaWindow(
                    name: ParsedQuotaWindow.planExpiryName,
                    utilization: 0,
                    resetsAt: ISO8601DateFormatter().date(from: "2026-10-15T00:00:00Z")
                ),
            ]),
        ])
        let summary = AccountQuotaFormatting.plainSummary(
            for: matchedChips[0],
            now: Date(timeIntervalSince1970: 1_758_600_000)
        )
        XCTAssertTrue(summary.contains("5h 58%"))
        XCTAssertTrue(summary.contains("7d 87%"))
        XCTAssertLessThan(summary.range(of: "5h")!.lowerBound, summary.range(of: "7d")!.lowerBound)
        XCTAssertTrue(summary.contains("截至10月15日"))
        XCTAssertFalse(summary.contains("总到期"))
        XCTAssertFalse(summary.contains("后重置"))
        XCTAssertFalse(summary.contains("must-not-be-sent"))
        XCTAssertFalse(summary.contains("official-token"))

        let timedOut = ScriptedQuotaTransport { request in
            if request.url?.path == "/backend-api/accounts/check/v4-2023-04-27" {
                throw URLError(.timedOut)
            }
            return AccountQuotaHTTPResponse(statusCode: 200, headers: [:], body: Data(usage.utf8))
        }
        let timedOutChips = try await AccountQuotaClient(transport: timedOut).refresh(targets: [
            quotaTarget(id: "official", name: "OpenAI", kind: .officialNote, key: nil, accessToken: "official-token", accountID: "account-id"),
        ])
        XCTAssertEqual(timedOutChips.map(\.status), [.windows(usageWindows)])

        let rejected = ScriptedQuotaTransport { request in
            if request.url?.path == "/backend-api/accounts/check/v4-2023-04-27" {
                return AccountQuotaHTTPResponse(statusCode: 401, headers: [:], body: Data(#"{"error":"no"}"#.utf8))
            }
            return AccountQuotaHTTPResponse(statusCode: 200, headers: [:], body: Data(usage.utf8))
        }
        let rejectedChips = try await AccountQuotaClient(transport: rejected).refresh(targets: [
            quotaTarget(id: "official", name: "OpenAI", kind: .officialNote, key: nil, accessToken: "official-token", accountID: "account-id"),
        ])
        XCTAssertEqual(rejectedChips.map(\.status), [.windows(usageWindows)])

        let mismatch = ScriptedQuotaTransport { request in
            let body = request.url?.path == "/backend-api/accounts/check/v4-2023-04-27" ? check : usage
            return AccountQuotaHTTPResponse(statusCode: 200, headers: [:], body: Data(body.utf8))
        }
        let mismatchChips = try await AccountQuotaClient(transport: mismatch).refresh(targets: [
            quotaTarget(id: "official", name: "OpenAI", kind: .officialNote, key: nil, accessToken: "official-token", accountID: "missing-account"),
        ])
        XCTAssertEqual(mismatchChips.map(\.status), [.windows(usageWindows)])
        XCTAssertFalse(
            AccountQuotaFormatting.plainSummary(for: mismatchChips[0], now: Date()).contains("总到期")
        )

        let renewsOnly = #"{"accounts":{"account-id":{"entitlement":{"renews_at":"2026-10-15T00:00:00Z"}}}}"#
        let renews = ScriptedQuotaTransport { request in
            let body = request.url?.path == "/backend-api/accounts/check/v4-2023-04-27" ? renewsOnly : usage
            return AccountQuotaHTTPResponse(statusCode: 200, headers: [:], body: Data(body.utf8))
        }
        let renewsChips = try await AccountQuotaClient(transport: renews).refresh(targets: [
            quotaTarget(id: "official", name: "OpenAI", kind: .officialNote, key: nil, accessToken: "official-token", accountID: "account-id"),
        ])
        XCTAssertEqual(renewsChips.map(\.status), [.windows(usageWindows)])

        let noAccount = ScriptedQuotaTransport { request in
            XCTAssertEqual(request.url?.path, "/backend-api/wham/usage")
            XCTAssertNil(request.value(forHTTPHeaderField: "ChatGPT-Account-ID"))
            return AccountQuotaHTTPResponse(statusCode: 200, headers: [:], body: Data(usage.utf8))
        }
        let noAccountChips = try await AccountQuotaClient(transport: noAccount).refresh(targets: [
            quotaTarget(id: "official", name: "OpenAI", kind: .officialNote, key: nil, accessToken: "official-token"),
        ])
        XCTAssertEqual(noAccount.requests.map { $0.url?.path }, ["/backend-api/wham/usage"])
        XCTAssertEqual(noAccountChips.map(\.status), [.windows(usageWindows)])
    }

    func testBadKeyDoesNotKeepAStaleQuotaButNetworkLossDoes() async throws {
        let previous = AccountQuotaChip(
            id: "kimi",
            shortName: "Kimi",
            websiteURL: URL(string: "https://www.kimi.com/code"),
            kind: .kimi,
            isCurrent: false,
            status: .windows([ParsedQuotaWindow(name: "five_hour", utilization: 0, resetsAt: nil)])
        )
        let unauthorized = ScriptedQuotaTransport { _ in
            AccountQuotaHTTPResponse(statusCode: 401, headers: [:], body: Data("{}".utf8))
        }
        let unauthorizedClient = AccountQuotaClient(transport: unauthorized)
        let failed = try await unauthorizedClient.refresh(
            targets: [quotaTarget(id: "kimi", name: "Kimi", kind: .kimi, key: "unit-test-key", current: true)],
            previous: [previous]
        )
        XCTAssertEqual(failed.map(\.status), [.message(AccountQuotaMessage.queryFailed)])
        XCTAssertEqual(failed.map(\.isCurrent), [true])

        let offline = ScriptedQuotaTransport { _ in
            throw URLError(.timedOut)
        }
        let offlineClient = AccountQuotaClient(transport: offline)
        let kept = try await offlineClient.refresh(
            targets: [quotaTarget(id: "kimi", name: "Kimi", kind: .kimi, key: "unit-test-key", current: true)],
            previous: [previous]
        )
        XCTAssertEqual(kept.map(\.status), [previous.status])
        XCTAssertEqual(kept.first?.isCurrent, true)
        XCTAssertEqual(kept.first?.isStale, true)
    }

    func testMissingXAILoginDoesNotCallTheNetwork() async throws {
        let transport = ScriptedQuotaTransport { request in
            XCTFail("unexpected request \(request.url?.absoluteString ?? "")")
            return AccountQuotaHTTPResponse(statusCode: 500, headers: [:], body: Data())
        }
        let client = AccountQuotaClient(
            transport: transport,
            authFileURL: URL(fileURLWithPath: "/tmp/missing-xai-auth-\(UUID().uuidString).json")
        )
        let chips = try await client.refresh(targets: [
            quotaTarget(id: "xai", name: "xAI", kind: .xaiOAuth, key: nil),
        ])
        XCTAssertEqual(chips.map(\.status), [
            .note(text: AccountQuotaMessage.notLoggedIn, help: AccountQuotaMessage.notLoggedInHelp),
        ])
        XCTAssertEqual(
            AccountQuotaFormatting.runs(for: chips[0], now: Date()).map(\.tone),
            [.secondary]
        )
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testZhipuUsesTheHostThatMatchesItsBaseURL() async throws {
        let baseURL = "https://open.bigmodel.cn/api/paas/v4"
        let transport = ScriptedQuotaTransport { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "unit-test-key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept-Language"), "en-US,en")
            switch request.url?.path {
            case "/api/monitor/usage/quota/limit":
                return AccountQuotaHTTPResponse(
                    statusCode: 200,
                    headers: [:],
                    body: Data(#"{"success":true,"data":{"limits":[{"type":"CREDIT_LIMIT","unit":3,"percentage":0},{"type":"CREDIT_LIMIT","unit":6,"percentage":100,"nextResetTime":1790255529998}]}}"#.utf8)
                )
            case "/api/biz/subscription/list":
                return AccountQuotaHTTPResponse(
                    statusCode: 200,
                    headers: [:],
                    body: Data(#"{"success":true,"data":[{"status":"VALID","inCurrentPeriod":true,"valid":"2026-10-03 10:00:00-2026-11-03 10:00:00","nextRenewTime":"2026-10-03"}]}"#.utf8)
                )
            default:
                XCTFail("unexpected \(request.url?.absoluteString ?? "")")
                return AccountQuotaHTTPResponse(statusCode: 500, headers: [:], body: Data())
            }
        }
        let client = AccountQuotaClient(transport: transport)
        let chips = try await client.refresh(targets: [
            quotaTarget(
                id: "zhipu",
                name: "智谱",
                kind: .zhipu,
                key: "unit-test-key",
                baseURL: baseURL
            ),
        ])
        XCTAssertEqual(
            transport.requests.map { $0.url?.absoluteString },
            [
                CCSwitchQuotaCatalog.zhipuQuotaURL(baseURL: baseURL).absoluteString,
                CCSwitchQuotaCatalog.zhipuSubscriptionURL(baseURL: baseURL).absoluteString,
            ]
        )
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        XCTAssertEqual(chips.map(\.status), [
            .windows([
                ParsedQuotaWindow(name: "five_hour", utilization: 0, resetsAt: nil),
                ParsedQuotaWindow(
                    name: "weekly_limit",
                    utilization: 100,
                    resetsAt: Date(timeIntervalSince1970: TimeInterval(1_790_255_529_998) / 1000)
                ),
                ParsedQuotaWindow(
                    name: ParsedQuotaWindow.planExpiryName,
                    utilization: 0,
                    resetsAt: formatter.date(from: "2026-10-03 10:00:00")
                ),
            ]),
        ])
        let summary = AccountQuotaFormatting.plainSummary(for: chips[0], now: Date(timeIntervalSince1970: 1_758_600_000))
        XCTAssertTrue(summary.hasPrefix("5h 100% · 7d 0%"))
        XCTAssertTrue(summary.contains("截至10月3日"))
        XCTAssertFalse(summary.contains("总到期"))
<<<<<<< Updated upstream
        XCTAssertFalse(summary.contains("1个月"))
=======
        XCTAssertFalse(summary.contains("1mo"))
>>>>>>> Stashed changes
        XCTAssertFalse(summary.contains("unit-test-key"))
    }

    func testZhipuKeepsQuotaWindowsWhenSubscriptionFails() async throws {
        let quota = Data(#"{"success":true,"data":{"limits":[{"type":"tokens_limit","unit":3,"percentage":12},{"type":"tokens_limit","unit":6,"percentage":34}]}}"#.utf8)
        let unauthorized = ScriptedQuotaTransport { request in
            if request.url?.path == "/api/biz/subscription/list" {
                return AccountQuotaHTTPResponse(statusCode: 401, headers: [:], body: Data(#"{"success":false}"#.utf8))
            }
            return AccountQuotaHTTPResponse(statusCode: 200, headers: [:], body: quota)
        }
        let unauthorizedChips = try await AccountQuotaClient(transport: unauthorized).refresh(targets: [
            quotaTarget(id: "zhipu", name: "智谱", kind: .zhipu, key: "unit-test-key", baseURL: "https://open.bigmodel.cn/api/paas/v4"),
        ])
        XCTAssertEqual(unauthorizedChips.map(\.status), [
            .windows([
                ParsedQuotaWindow(name: "five_hour", utilization: 12, resetsAt: nil),
                ParsedQuotaWindow(name: "weekly_limit", utilization: 34, resetsAt: nil),
            ]),
        ])

        let offline = ScriptedQuotaTransport { request in
            if request.url?.path == "/api/biz/subscription/list" {
                throw URLError(.timedOut)
            }
            return AccountQuotaHTTPResponse(statusCode: 200, headers: [:], body: quota)
        }
        let offlineChips = try await AccountQuotaClient(transport: offline).refresh(targets: [
            quotaTarget(id: "zhipu", name: "智谱", kind: .zhipu, key: "unit-test-key"),
        ])
        XCTAssertEqual(offlineChips.map(\.status), unauthorizedChips.map(\.status))
        XCTAssertEqual(offline.requests.map { $0.url?.host }, ["api.z.ai", "api.z.ai"])
    }

    func testZhipuDoesNotQuerySubscriptionWhenQuotaFails() async throws {
        let rejected = ScriptedQuotaTransport { request in
            XCTAssertEqual(request.url?.path, "/api/monitor/usage/quota/limit")
            return AccountQuotaHTTPResponse(statusCode: 200, headers: [:], body: Data(#"{"success":false}"#.utf8))
        }
        let chips = try await AccountQuotaClient(transport: rejected).refresh(targets: [
            quotaTarget(id: "zhipu", name: "智谱", kind: .zhipu, key: "unit-test-key", baseURL: "https://open.bigmodel.cn/api/paas/v4"),
        ])
        XCTAssertEqual(chips.map(\.status), [.message(AccountQuotaMessage.queryFailed)])
        XCTAssertEqual(rejected.requests.count, 1)

        let unauthorized = ScriptedQuotaTransport { request in
            return AccountQuotaHTTPResponse(statusCode: 401, headers: [:], body: Data("{}".utf8))
        }
        let failed = try await AccountQuotaClient(transport: unauthorized).refresh(targets: [
            quotaTarget(id: "zhipu", name: "智谱", kind: .zhipu, key: "unit-test-key"),
        ])
        XCTAssertEqual(failed.map(\.status), [.message(AccountQuotaMessage.queryFailed)])
        XCTAssertEqual(unauthorized.requests.count, 1)
    }

    func testOfficialWithoutALoginDoesNotCallTheNetworkOrRequireCodex() async throws {
        let missingCodexAuth = URL(fileURLWithPath: "/tmp/missing-codex-\(UUID().uuidString)/auth.json")
        let transport = ScriptedQuotaTransport { request in
            XCTFail("unexpected request \(request.url?.absoluteString ?? "")")
            return AccountQuotaHTTPResponse(statusCode: 500, headers: [:], body: Data())
        }
        let client = AccountQuotaClient(transport: transport, authFileURL: missingCodexAuth)
        let chips = try await client.refresh(
            targets: [
                quotaTarget(id: "official", name: "OpenAI", kind: .officialNote, key: "must-not-be-sent"),
                quotaTarget(
                    id: "proxy",
                    name: "OpenAI",
                    kind: .officialNote,
                    key: nil,
                    accessToken: "proxy-placeholder"
                ),
                quotaTarget(
                    id: "blank",
                    name: "OpenAI",
                    kind: .officialNote,
                    key: nil,
                    accessToken: "  "
                ),
            ],
            authFileURL: missingCodexAuth
        )
        XCTAssertTrue(chips.isEmpty)
        XCTAssertTrue(transport.requests.isEmpty)
        let rendered = chips.map {
            AccountQuotaFormatting.plainSummary(for: $0, now: Date())
                + AccountQuotaFormatting.help(for: $0, now: Date())
        }.joined()
        XCTAssertFalse(rendered.localizedCaseInsensitiveContains("codex"))
        XCTAssertFalse(rendered.contains("安装"))
        XCTAssertFalse(rendered.contains("查询失败"))
    }

    func testMissingOrPlaceholderKeyDoesNotCallTheNetwork() async throws {
        let transport = ScriptedQuotaTransport { request in
            XCTFail("unexpected request \(request.url?.absoluteString ?? "")")
            return AccountQuotaHTTPResponse(statusCode: 500, headers: [:], body: Data())
        }
        let client = AccountQuotaClient(
            transport: transport,
            authFileURL: URL(fileURLWithPath: "/tmp/unused-xai-auth-\(UUID().uuidString).json")
        )
        let chips = try await client.refresh(targets: [
            quotaTarget(id: "blank", name: "Kimi", kind: .kimi, key: "  "),
            quotaTarget(id: "proxy", name: "Kimi 2", kind: .kimi, key: " proxy-local"),
            quotaTarget(id: "none", name: "DeepSeek", kind: .deepseek, key: nil),
        ])

        let expected = AccountQuotaChip.Status.note(
            text: AccountQuotaMessage.notConfigured,
            help: AccountQuotaMessage.notConfiguredHelp
        )
        XCTAssertEqual(chips.map(\.status), [expected, expected, expected])
        XCTAssertTrue(transport.requests.isEmpty)
        for chip in chips {
            XCTAssertEqual(
                AccountQuotaFormatting.runs(for: chip, now: Date()).map(\.tone),
                [.secondary]
            )
        }
    }

    func testRefreshAuthFileOverridesTheClientURL() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "xai-auth-override-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let reauthURL = directory.appending(path: "reauth.json")
        try Data(xaiAuthJSON(requiresReauth: true).utf8).write(to: reauthURL)
        let missingURL = directory.appending(path: "missing.json")

        let transport = ScriptedQuotaTransport { request in
            XCTFail("unexpected request \(request.url?.absoluteString ?? "")")
            return AccountQuotaHTTPResponse(statusCode: 500, headers: [:], body: Data())
        }
        let loggedOutClient = AccountQuotaClient(transport: transport, authFileURL: reauthURL)
        let loggedOut = try await loggedOutClient.refresh(
            targets: [quotaTarget(id: "xai", name: "xAI", kind: .xaiOAuth, key: nil)],
            authFileURL: missingURL
        )
        XCTAssertEqual(loggedOut.map(\.status), [
            .note(text: AccountQuotaMessage.notLoggedIn, help: AccountQuotaMessage.notLoggedInHelp),
        ])
        XCTAssertEqual(
            AccountQuotaFormatting.runs(for: loggedOut[0], now: Date()).map(\.tone),
            [.secondary]
        )

        let reauthClient = AccountQuotaClient(transport: transport, authFileURL: missingURL)
        let reauth = try await reauthClient.refresh(
            targets: [quotaTarget(id: "xai", name: "xAI", kind: .xaiOAuth, key: nil)],
            authFileURL: reauthURL
        )
        XCTAssertEqual(reauth.map(\.status), [.message(AccountQuotaMessage.reauthRequired)])
        XCTAssertEqual(
            AccountQuotaFormatting.runs(for: reauth[0], now: Date()).map(\.tone),
            [.orange]
        )
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testInvalidGrantAfterARealLoginStaysReauth() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "xai-invalid-grant-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let authURL = directory.appending(path: "xai_oauth_auth.json")
        try Data(xaiAuthJSON(requiresReauth: false).utf8).write(to: authURL)

        let transport = ScriptedQuotaTransport { request in
            switch request.url?.absoluteString {
            case "https://auth.x.ai/.well-known/openid-configuration":
                return AccountQuotaHTTPResponse(
                    statusCode: 200,
                    headers: [:],
                    body: Data(
                        #"{"issuer":"https://auth.x.ai","token_endpoint":"https://auth.x.ai/oauth2/token"}"#.utf8
                    )
                )
            case "https://auth.x.ai/oauth2/token":
                return AccountQuotaHTTPResponse(
                    statusCode: 400,
                    headers: [:],
                    body: Data(#"{"error":"invalid_grant"}"#.utf8)
                )
            default:
                XCTFail("unexpected request \(request.url?.absoluteString ?? "")")
                return AccountQuotaHTTPResponse(statusCode: 500, headers: [:], body: Data())
            }
        }
        let client = AccountQuotaClient(
            transport: transport,
            authFileURL: directory.appending(path: "unused.json")
        )
        let chips = try await client.refresh(
            targets: [quotaTarget(id: "xai", name: "xAI", kind: .xaiOAuth, key: nil)],
            authFileURL: authURL
        )
        XCTAssertEqual(chips.map(\.status), [.message(AccountQuotaMessage.reauthRequired)])
        XCTAssertEqual(
            AccountQuotaFormatting.runs(for: chips[0], now: Date()).map(\.tone),
            [.orange]
        )
        XCTAssertFalse(transport.requests.contains { $0.url?.host == "grok.com" })
    }

    func testQwenWithoutOfficialQuotaAsksToConnectAndDoesNotQueryItsKey() async throws {
        let client = AccountQuotaClient(
            transport: ScriptedQuotaTransport { request in
                XCTFail("unexpected request \(request.url?.absoluteString ?? "")")
                return AccountQuotaHTTPResponse(statusCode: 500, headers: [:], body: Data())
            },
            qwenQuotaSource: FixedQwenQuotaSource(data: nil),
            now: { Date() }
        )
        let chips = try await client.refresh(targets: [
            quotaTarget(
                id: "qwen",
                name: "千问",
                kind: .qwen,
                key: "qwen-key",
                baseURL: "https://token-plan.cn-beijing.maas.aliyuncs.com/compatible-mode/v1"
            ),
        ])
        XCTAssertEqual(
            chips.first?.status,
            .note(
                text: AccountQuotaMessage.connectOfficial,
                help: AccountQuotaMessage.connectOfficialHelp
            )
        )
    }

    func testQwenUsesOfficialPlanWhenSummaryIsSubscribed() async throws {
        let summary = Data(#"""
        {"token_plan":{"subscribed":true,"totalCredits":25000,"remainingCredits":18000,"usedPct":28}}
        """#.utf8)
        let client = AccountQuotaClient(
            qwenQuotaSource: FixedQwenQuotaSource(data: summary)
        )
        let chips = try await client.refresh(targets: [
            quotaTarget(id: "qwen", name: "千问", kind: .qwen, key: "model-key"),
        ])
        XCTAssertEqual(
            chips.first?.status,
            .qwenPlan(QwenPlanQuota(
                usedPercent: 28,
                remainingCredits: 18_000,
                totalCredits: 25_000,
                resetsAt: nil
            ))
        )
    }
}

final class CCSwitchProviderStoreTests: XCTestCase {
    func testMissingOrUnusableDatabaseIsAbsent() throws {
        let missing = FileManager.default.temporaryDirectory
            .appending(path: "missing-cc-switch-\(UUID().uuidString).db")
        XCTAssertEqual(CCSwitchProviderStore.loadCodexProviders(databaseURL: missing), .absent)

        let directory = FileManager.default.temporaryDirectory
            .appending(path: "not-a-db-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertEqual(CCSwitchProviderStore.loadCodexProviders(databaseURL: directory), .absent)

        let textFile = directory.appending(path: "notes.db")
        try Data("not a database".utf8).write(to: textFile)
        XCTAssertEqual(CCSwitchProviderStore.loadCodexProviders(databaseURL: textFile), .absent)

        let fakeSQLite = directory.appending(path: "fake.db")
        var header = Data("SQLite format 3\0".utf8)
        header.append(Data(repeating: 0, count: 64))
        try header.write(to: fakeSQLite)
        XCTAssertEqual(CCSwitchProviderStore.loadCodexProviders(databaseURL: fakeSQLite), .absent)

        let otherTable = directory.appending(path: "other.db")
        try Data().write(to: otherTable)
        try runSQLite("CREATE TABLE notes (id TEXT);", database: otherTable)
        XCTAssertEqual(CCSwitchProviderStore.loadCodexProviders(databaseURL: otherTable), .absent)

        let missingColumn = directory.appending(path: "partial.db")
        try Data().write(to: missingColumn)
        try runSQLite(
            """
            CREATE TABLE providers (
                id TEXT,
                app_type TEXT,
                name TEXT
            );
            """,
            database: missingColumn
        )
        XCTAssertEqual(CCSwitchProviderStore.loadCodexProviders(databaseURL: missingColumn), .absent)

        let noCodex = directory.appending(path: "claude-only.db")
        try Data().write(to: noCodex)
        try runSQLite(
            """
            CREATE TABLE providers (
                id TEXT NOT NULL,
                app_type TEXT NOT NULL,
                name TEXT NOT NULL,
                settings_config TEXT NOT NULL,
                website_url TEXT,
                created_at INTEGER,
                sort_index INTEGER,
                meta TEXT NOT NULL DEFAULT '{}',
                is_current INTEGER NOT NULL DEFAULT 0
            );
            INSERT INTO providers (id, app_type, name, settings_config)
            VALUES ('claude-1', 'claude', 'Claude', '{}');
            """,
            database: noCodex
        )
        XCTAssertEqual(CCSwitchProviderStore.loadCodexProviders(databaseURL: noCodex), .records([]))
    }

    func testUnreadableDatabaseIsUnavailable() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "unreadable-cc-switch-\(UUID().uuidString).db")
        try Data("present but unreadable".utf8).write(to: url)
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o644],
                ofItemAtPath: url.path(percentEncoded: false)
            )
            try? FileManager.default.removeItem(at: url)
        }
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o000],
            ofItemAtPath: url.path(percentEncoded: false)
        )
        XCTAssertEqual(CCSwitchProviderStore.loadCodexProviders(databaseURL: url), .unavailable)
    }

    func testLoadsOnlyCodexRowsAndTheSelectedProviderID() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "cc-switch-store-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appending(path: "cc-switch.db")
        let settingsURL = directory.appending(path: "settings.json")
        try Data(#"{"currentProviderCodex":" xai ","currentProviderClaude":"ignored"}"#.utf8)
            .write(to: settingsURL)
        XCTAssertEqual(CCSwitchProviderStore.currentCodexProviderID(settingsURL: settingsURL), "xai")
        XCTAssertNil(CCSwitchProviderStore.currentCodexProviderID(settingsURL: directory.appending(path: "missing.json")))

        let kimiSettings = settings(key: "unit-test-key", toml: "https://api.kimi.com/coding/v1")
        let sql = """
        CREATE TABLE providers (
            id TEXT NOT NULL,
            app_type TEXT NOT NULL,
            name TEXT NOT NULL,
            settings_config TEXT NOT NULL,
            website_url TEXT,
            created_at INTEGER,
            sort_index INTEGER,
            meta TEXT NOT NULL DEFAULT '{}',
            is_current INTEGER NOT NULL DEFAULT 0
        );
        INSERT INTO providers (id, app_type, name, settings_config, website_url, created_at, sort_index, meta, is_current)
        VALUES ('claude-1', 'claude', 'Claude', '{}', NULL, 1, NULL, '{}', 1);
        INSERT INTO providers (id, app_type, name, settings_config, website_url, created_at, sort_index, meta, is_current)
        VALUES ('kimi', 'codex', 'Kimi For Coding', \(sqlLiteral(kimiSettings)), 'https://www.kimi.com/code', 2, NULL, '{"usage_script":{"codingPlanProvider":"kimi"}}', 0);
        INSERT INTO providers (id, app_type, name, settings_config, website_url, created_at, sort_index, meta, is_current)
        VALUES ('xai', 'codex', 'xAI', '{}', NULL, 3, NULL, '{"providerType":"xai_oauth"}', 0);
        """
        try runSQLite(sql, database: databaseURL)

        let loaded = CCSwitchProviderStore.loadCodexProviders(databaseURL: databaseURL)
        guard case let .records(records) = loaded else {
            return XCTFail("expected records, got \(loaded)")
        }
        let targets = CCSwitchQuotaCatalog.targets(
            from: records,
            currentProviderID: CCSwitchProviderStore.currentCodexProviderID(settingsURL: settingsURL)
        )
        XCTAssertEqual(targets.map(\.id), ["kimi", "xai"])
        XCTAssertEqual(targets.map(\.isCurrent), [false, true])
        XCTAssertEqual(targets[0].apiKey, "unit-test-key")
        XCTAssertNil(targets[1].apiKey)
        XCTAssertNil(targets[1].websiteURL)
    }

    func testInvalidSettingsAreIgnoredAndTheDatabaseFlagRemainsCurrent() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "cc-switch-settings-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let settingsURL = directory.appending(path: "settings.json")

        try Data("not-json".utf8).write(to: settingsURL)
        XCTAssertNil(CCSwitchProviderStore.currentCodexProviderID(settingsURL: settingsURL))
        try Data(#"{"currentProviderCodex":" "}"#.utf8).write(to: settingsURL)
        XCTAssertNil(CCSwitchProviderStore.currentCodexProviderID(settingsURL: settingsURL))
        try Data(#"{"currentProviderCodex":1}"#.utf8).write(to: settingsURL)
        XCTAssertNil(CCSwitchProviderStore.currentCodexProviderID(settingsURL: settingsURL))
        try Data(#"["xai"]"#.utf8).write(to: settingsURL)
        XCTAssertNil(CCSwitchProviderStore.currentCodexProviderID(settingsURL: settingsURL))

        let records = [
            record(
                id: "kimi",
                name: "Kimi",
                isCurrent: true,
                meta: #"{"usage_script":{"codingPlanProvider":"kimi"}}"#,
                settings: settings(key: "unit-test-key", toml: "https://api.kimi.com/coding/v1")
            ),
        ]
        let targets = CCSwitchQuotaCatalog.targets(from: records, currentProviderID: nil)
        XCTAssertEqual(targets.map(\.id), ["kimi"])
        XCTAssertTrue(targets[0].isCurrent)
    }

    func testConfigDirectoryOverrideFallsBackUnlessThePathExists() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "cc-switch-paths-\(UUID().uuidString)", directoryHint: .isDirectory)
        let home = root.appending(path: "home", directoryHint: .isDirectory)
        let appPaths = root.appending(path: "app_paths.json")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fallback = home.appending(path: ".cc-switch", directoryHint: .isDirectory)

        func resolved(writing json: String? = nil) throws -> CCSwitchInstall {
            if let json {
                try Data(json.utf8).write(to: appPaths)
            } else if FileManager.default.fileExists(atPath: appPaths.path(percentEncoded: false)) {
                try FileManager.default.removeItem(at: appPaths)
            }
            return CCSwitchProviderStore.resolveInstall(appPathsURL: appPaths, homeDirectory: home)
        }

        XCTAssertEqual(pathKey(try resolved().root), pathKey(fallback))
        XCTAssertEqual(pathKey(try resolved(writing: "{}").root), pathKey(fallback))
        XCTAssertEqual(pathKey(try resolved(writing: "not-json").root), pathKey(fallback))
        XCTAssertEqual(pathKey(try resolved(writing: #"{"app_config_dir_override":" "}"#).root), pathKey(fallback))
        XCTAssertEqual(pathKey(try resolved(writing: #"{"app_config_dir_override":12}"#).root), pathKey(fallback))
        XCTAssertEqual(
            pathKey(try resolved(writing: #"{"app_config_dir_override":["/tmp"]}"#).root),
            pathKey(fallback)
        )
        let missingOverride = root.appending(path: "missing-override", directoryHint: .isDirectory)
        XCTAssertEqual(
            pathKey(try resolved(writing: #"{"app_config_dir_override":"\#(missingOverride.path(percentEncoded: false))"}"#).root),
            pathKey(fallback)
        )
        XCTAssertEqual(
            pathKey(try resolved(writing: #"{"app_config_dir_override":"~/does-not-exist"}"#).root),
            pathKey(fallback)
        )

        let custom = root.appending(path: "custom-switch", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: custom, withIntermediateDirectories: true)
        let overridden = try resolved(
            writing: #"{"app_config_dir_override":"\#(custom.path(percentEncoded: false))"}"#
        )
        XCTAssertEqual(pathKey(overridden.root), pathKey(custom))
        XCTAssertEqual(pathKey(overridden.databaseURL), pathKey(custom.appending(path: "cc-switch.db")))
        XCTAssertEqual(pathKey(overridden.settingsURL), pathKey(custom.appending(path: "settings.json")))
        XCTAssertEqual(pathKey(overridden.xaiAuthURL), pathKey(custom.appending(path: "xai_oauth_auth.json")))
        XCTAssertFalse(FileManager.default.fileExists(atPath: overridden.databaseURL.path(percentEncoded: false)))

        let tildeTarget = home.appending(path: "tilde-switch", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tildeTarget, withIntermediateDirectories: true)
        XCTAssertEqual(
            pathKey(try resolved(writing: #"{"app_config_dir_override":"~/tilde-switch"}"#).root),
            pathKey(tildeTarget)
        )
        XCTAssertEqual(pathKey(try resolved(writing: #"{"app_config_dir_override":"~"}"#).root), pathKey(home))

        let windowsName = "win\\switch"
        let windowsTarget = home.appending(path: windowsName, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: windowsTarget, withIntermediateDirectories: true)
        XCTAssertEqual(
            pathKey(try resolved(writing: #"{"app_config_dir_override":"~\\win\\switch"}"#).root),
            pathKey(windowsTarget)
        )
    }
}

final class XaiEndpointValidatorTests: XCTestCase {
    func testAcceptsOnlyTheXAIAuthHost() {
        XCTAssertEqual(
            XaiEndpointValidator.trustedTokenEndpoint("https://auth.x.ai/oauth2/token")?.absoluteString,
            "https://auth.x.ai/oauth2/token"
        )
        XCTAssertNil(XaiEndpointValidator.trustedTokenEndpoint("http://auth.x.ai/oauth2/token"))
        XCTAssertNil(XaiEndpointValidator.trustedTokenEndpoint("https://evil.example/oauth2/token"))
        XCTAssertNil(XaiEndpointValidator.trustedTokenEndpoint("https://auth.x.ai.evil/oauth2/token"))
        XCTAssertNil(XaiEndpointValidator.trustedTokenEndpoint("https://user:pass@auth.x.ai/oauth2/token"))
        XCTAssertNil(XaiEndpointValidator.trustedTokenEndpoint("https://auth.x.ai:8443/oauth2/token"))
        XCTAssertTrue(XaiEndpointValidator.isTrustedIssuer("https://auth.x.ai/"))
        XCTAssertFalse(XaiEndpointValidator.isTrustedIssuer("https://auth.x.ai.evil"))
    }

    func testClassifiesGrokFailuresWithoutReadingABody() {
        XCTAssertEqual(GrokBillingParser.classify(httpStatus: 401, grpcStatus: nil), .reauth)
        XCTAssertEqual(GrokBillingParser.classify(httpStatus: 429, grpcStatus: nil), .transient)
        XCTAssertEqual(GrokBillingParser.classify(httpStatus: 200, grpcStatus: 16), .reauth)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(
            GrokBillingParser.tierName(resetsAt: now.addingTimeInterval(7 * 86_400), now: now),
            "weekly_limit"
        )
    }
}

private final class ScriptedQuotaTransport: AccountQuotaTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var seen: [URLRequest] = []
    private let handler: @Sendable (URLRequest) throws -> AccountQuotaHTTPResponse

    init(handler: @escaping @Sendable (URLRequest) throws -> AccountQuotaHTTPResponse) {
        self.handler = handler
    }

    var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return seen
    }

    func data(for request: URLRequest) async throws -> AccountQuotaHTTPResponse {
        record(request)
        return try handler(request)
    }

    private func record(_ request: URLRequest) {
        lock.lock()
        seen.append(request)
        lock.unlock()
    }
}

private struct FixedQwenQuotaSource: QwenQuotaSource {
    let data: Data?

    func loadSummary() async -> Data? { data }
}

private func record(
    id: String,
    name: String,
    website: String? = nil,
    sortIndex: Int? = nil,
    createdAt: Int64 = 0,
    isCurrent: Bool = false,
    meta: String = "{}",
    settings: String = "{}"
) -> CCSwitchProviderRecord {
    CCSwitchProviderRecord(
        id: id,
        name: name,
        websiteURL: website,
        sortIndex: sortIndex,
        createdAt: createdAt,
        isCurrent: isCurrent,
        metaJSON: meta,
        settingsConfigJSON: settings
    )
}

private func settings(
    key: String?,
    toml: String,
    accessToken: String? = nil,
    accountID: String? = nil
) -> String {
    settings(key: key, config: "base_url = \"\(toml)\"", accessToken: accessToken, accountID: accountID)
}

private func settings(
    key: String?,
    config: Any,
    accessToken: String? = nil,
    accountID: String? = nil
) -> String {
    var object: [String: Any] = ["config": config]
    var auth: [String: Any] = [:]
    if let key {
        auth["OPENAI_API_KEY"] = key
    }
    if accessToken != nil || accountID != nil {
        var tokens: [String: Any] = [:]
        if let accessToken {
            tokens["access_token"] = accessToken
        }
        if let accountID {
            tokens["account_id"] = accountID
        }
        auth["tokens"] = tokens
    }
    if !auth.isEmpty {
        object["auth"] = auth
    }
    let data = try! JSONSerialization.data(withJSONObject: object)
    return String(decoding: data, as: UTF8.self)
}

private func settings(key: String?, configObject: [String: Any]) -> String {
    settings(key: key, config: configObject)
}

private func chip(
    kind: CCSwitchQuotaKind,
    isCurrent: Bool = false,
    status: AccountQuotaChip.Status
) -> AccountQuotaChip {
    AccountQuotaChip(
        id: kind.shortTestID,
        shortName: "Name",
        websiteURL: URL(string: "https://example.com"),
        kind: kind,
        isCurrent: isCurrent,
        status: status
    )
}

private func quotaTarget(
    id: String,
    name: String,
    kind: CCSwitchQuotaKind,
    key: String?,
    baseURL: String? = nil,
    current: Bool = false,
    accessToken: String? = nil,
    accountID: String? = nil
) -> CCSwitchQuotaTarget {
    CCSwitchQuotaTarget(
        id: id,
        shortName: name,
        websiteURL: URL(string: "https://example.com/\(id)"),
        kind: kind,
        isCurrent: current,
        apiKey: key,
        baseURL: baseURL,
        accessToken: accessToken,
        accountID: accountID
    )
}

private extension CCSwitchQuotaKind {
    var shortTestID: String {
        switch self {
        case .officialNote: "official"
        case .kimi: "kimi"
        case .zhipu: "zhipu"
        case .deepseek: "deepseek"
        case .qwen: "qwen"
        case .xaiOAuth: "xai"
        }
    }
}


private func xaiAuthJSON(requiresReauth: Bool) -> String {
    """
    {"default_account_id":"acct-1","accounts":{"acct-1":{"account_id":"acct-1","refresh_token":"unit-test-refresh","requires_reauth":\(requiresReauth ? "true" : "false")}}}
    """
}

private func pathKey(_ url: URL) -> String {
    var path = url.standardizedFileURL.path(percentEncoded: false)
    while path.count > 1, path.hasSuffix("/") {
        path.removeLast()
    }
    return path
}

private func sqlLiteral(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "''") + "'"
}

private func runSQLite(_ sql: String, database: URL) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
    process.arguments = [database.path(percentEncoded: false)]
    let input = Pipe()
    let output = Pipe()
    process.standardInput = input
    process.standardOutput = output
    process.standardError = output
    try process.run()
    input.fileHandleForWriting.write(Data(sql.utf8))
    try input.fileHandleForWriting.close()
    process.waitUntilExit()
    if process.terminationStatus != 0 {
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        XCTFail("sqlite3 exited \(process.terminationStatus): \(text)")
    }
}
