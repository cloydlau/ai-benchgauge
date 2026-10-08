import Foundation
import CSQLite
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import LeaderboardCore
import Testing

struct CCSwitchQuotaCatalogTests {
    @Test
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

        #expect((targets.map(\.id)) == (["codex-official", "kimi", "deepseek", "xai", "zhipu"]))
        #expect((targets.map(\.kind)) == ([.officialNote, .kimi, .deepseek, .xaiOAuth, .zhipu]))
        #expect((targets.map(\.shortName)) == (["OpenAI", "Kimi", "DeepSeek", "xAI", "GLM"]))
        #expect((targets.map(\.isCurrent)) == ([false, false, false, true, false]))
        #expect((targets[0].apiKey) == nil)
        #expect((targets[0].accessToken) == ("stored-official-login"))
        #expect((targets[0].accountID) == ("acct-1"))
        #expect((targets[1].apiKey) == ("unit-test-key"))
        #expect((targets[1].baseURL) == ("https://api.kimi.com/coding/v1"))
        #expect((targets[2].baseURL) == ("https://api.deepseek.com"))
        #expect((targets[3].apiKey) == nil)
        #expect((targets[4].baseURL) == ("https://open.bigmodel.cn/api/paas/v4"))
        #expect((CCSwitchQuotaCatalog.zhipuQuotaURL(baseURL: targets[4].baseURL).absoluteString) == ("https://open.bigmodel.cn/api/monitor/usage/quota/limit"))
        #expect((CCSwitchQuotaCatalog.zhipuSubscriptionURL(baseURL: targets[4].baseURL).absoluteString) == ("https://open.bigmodel.cn/api/biz/subscription/list"))
    }

    @Test
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

        #expect((targets.map(\.id)) == (["kimi"]))
        #expect(!(targets[0].isCurrent))
        #expect((targets[0].accessToken) == nil)
    }

    @Test
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

        #expect((targets.map(\.id)) == (["kimi"]))
        #expect(targets[0].isCurrent)
    }

    @Test
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

        #expect((targets.map(\.kind)) == ([.qwen]))
        #expect((targets.first?.shortName) == ("Qwen"))
        #expect((targets.first?.apiKey) == ("qwen-key"))
    }

    @Test
    func testKeepsTheConfiguredModelForCompactSurfacesWithoutChangingProviderLabels() {
        let targets = CCSwitchQuotaCatalog.targets(
            from: [
                record(
                    id: "zhipu",
                    name: "Zhipu GLM",
                    isCurrent: true,
                    meta: #"{"usage_script":{"enabled":true,"codingPlanProvider":"zhipu"}}"#,
                    settings: settings(
                        key: "zhipu-key",
                        config: """
                        model = "glm-5.3"
                        base_url = "https://open.bigmodel.cn/api/paas/v4"
                        """
                    )
                ),
            ],
            currentProviderID: "zhipu"
        )

        #expect((targets.first?.shortName) == ("GLM"))
        #expect((targets.first?.modelName) == ("glm-5.3"))
    }

    @Test
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

        #expect((targets.map(\.id)) == (["qwen"]))
        #expect((targets.map(\.kind)) == ([.qwen]))
        #expect((targets.first?.apiKey) == ("must-not-become-a-kimi-key"))
    }

    @Test
    func testReadsKimiBearerTokenFromCodexConfig() {
        let targets = CCSwitchQuotaCatalog.targets(
            from: [
                record(
                    id: "kimi",
                    name: "Kimi For Coding",
                    meta: #"{"usage_script":{"enabled":true,"codingPlanProvider":"kimi"}}"#,
                    settings: settings(
                        key: nil,
                        config: """
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

        #expect((targets.first?.kind) == (.kimi))
        #expect((targets.first?.apiKey) == ("kimi-bearer"))
    }

    @Test
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

        #expect((targets.map(\.shortName)) == (["Kimi", "Kimi 2"]))
        #expect((targets[0].apiKey) == nil)
        #expect((targets[0].baseURL) == nil)
        #expect((targets[1].apiKey) == ("unit-test-key"))
        #expect((CCSwitchQuotaCatalog.zhipuQuotaURL(baseURL: nil).absoluteString) == ("https://api.z.ai/api/monitor/usage/quota/limit"))
        #expect((CCSwitchQuotaCatalog.zhipuSubscriptionURL(baseURL: nil).absoluteString) == ("https://api.z.ai/api/biz/subscription/list"))
    }
}

struct AccountQuotaFormattingTests {
    @Test
    func testAllQuotaSurfacesUseAtMostOneDecimalPlace() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let examples: [(AccountQuotaChip.Status, String)] = [
            (.windows([ParsedQuotaWindow(name: "five_hour", utilization: 12.34, resetsAt: nil)]), "5h 87.7%"),
            (.windows([ParsedQuotaWindow(name: "seven_day", utilization: 100, resetsAt: nil)]), "7d 0%"),
            (.windows([ParsedQuotaWindow(name: "monthly", utilization: 0, resetsAt: nil)]), "1mo 100%"),
            (.qwenWebsite(QwenWebsiteQuota(periodLabel: "1mo", remainingPercent: 6.84, resetsAt: nil)), "1mo 6.8%"),
            (.qwenWebsite(QwenWebsiteQuota(periodLabel: "7d", remainingPercent: 42, resetsAt: nil)), "7d 42%"),
            (.qwenWebsite(QwenWebsiteQuota(periodLabel: "7d", remainingPercent: 6.96, resetsAt: nil)), "7d 7%"),
            (.qwenPlan(QwenPlanQuota(usedPercent: 80, remainingCredits: 2, totalCredits: 3, resetsAt: nil)), "额度 66.7%"),
            (.qwenPlan(QwenPlanQuota(usedPercent: 12.34, remainingCredits: 0, totalCredits: 0, resetsAt: nil)), "额度 87.7%"),
        ]
        for (status, expected) in examples {
            let quota = chip(kind: .qwen, isCurrent: true, status: status)
            #expect(AccountQuotaFormatting.menuBarText(forChips: [quota])?.quota == expected)
            #expect(AccountQuotaFormatting.plainSummary(for: quota, now: now) == expected)
            #expect(AccountQuotaFormatting.help(for: quota, now: now).contains(expected))
        }
    }

    @Test
    func testMenuBarUsesTheShortestSuccessfulWindow() {
        let windows = [
            ParsedQuotaWindow(name: "monthly", utilization: 40, resetsAt: nil),
            ParsedQuotaWindow(name: "weekly_limit", utilization: 20, resetsAt: nil),
            ParsedQuotaWindow(name: "five_hour", utilization: 13, resetsAt: nil),
        ]
        func summary(_ windows: [ParsedQuotaWindow]) -> String? {
            AccountQuotaFormatting.compactMenuBarQuota(
                for: chip(kind: .officialNote, isCurrent: true, status: .windows(windows))
            )
        }
        #expect((summary(windows)) == ("5h 87%"))
        #expect((summary(Array(windows.prefix(2)))) == ("7d 80%"))
        #expect((summary(Array(windows.prefix(1)))) == ("1mo 60%"))
        #expect((summary([ParsedQuotaWindow(
            name: ParsedQuotaWindow.planExpiryName, utilization: 0, resetsAt: nil
        )])) == nil)
    }

    /// The panel keeps the last good amount when a refresh fails and the
    /// persisted website result when the live Qwen page read misses. Hiding
    /// either one would leave the menu bar behind the number the panel shows.
    @Test
    func testMenuBarKeepsTheAmountThePanelStillShows() {
        #expect((AccountQuotaFormatting.compactMenuBarQuota(
            for: chip(kind: .officialNote, status: .pending)
        )) == nil)
        #expect((AccountQuotaFormatting.compactMenuBarQuota(
            for: chip(kind: .officialNote, status: .message(AccountQuotaMessage.queryFailed))
        )) == nil)

        let stale = AccountQuotaChip(
            id: "current", shortName: "OpenAI", websiteURL: nil,
            kind: .officialNote, isCurrent: true,
            status: .windows([ParsedQuotaWindow(name: "five_hour", utilization: 25, resetsAt: nil)]),
            isStale: true
        )
        #expect((AccountQuotaFormatting.compactMenuBarQuota(for: stale)) == ("5h 75%"))

        let cachedQwen = chip(
            kind: .qwen,
            status: .qwenWebsite(QwenWebsiteQuota(
                periodLabel: "7d", remainingPercent: 88, resetsAt: nil, isCached: true
            ))
        )
        #expect((AccountQuotaFormatting.compactMenuBarQuota(for: cachedQwen)) == ("7d 88%"))
    }

    @Test
    func testMenuBarTextProjectsTheCurrentChip() {
        let pending = chip(kind: .kimi, status: .pending)
        let current = AccountQuotaChip(
            id: "qwen", shortName: "千问", modelName: "qwen3.8-max", websiteURL: nil,
            kind: .qwen, isCurrent: true,
            status: .qwenWebsite(QwenWebsiteQuota(
                periodLabel: "1mo", remainingPercent: 42, resetsAt: nil
            ))
        )
        #expect((AccountQuotaFormatting.menuBarText(forChips: [pending, current])) == (AccountQuotaMenuBarText(name: "qwen3.8-max", fullName: "qwen3.8-max", quota: "1mo 42%")))
        #expect((AccountQuotaFormatting.menuBarText(forChips: [pending])) == nil)
        #expect((AccountQuotaFormatting.menuBarText(forChips: [])) == nil)

        let longName = String(repeating: "a", count: 30)
        let long = AccountQuotaChip(
            id: "long", shortName: "Kimi", modelName: longName, websiteURL: nil,
            kind: .kimi, isCurrent: true,
            status: .windows([ParsedQuotaWindow(name: "seven_day", utilization: 10, resetsAt: nil)])
        )
        let text = AccountQuotaFormatting.menuBarText(forChips: [long])
        #expect((text?.name) == (String(repeating: "a", count: 23) + "…"))
        #expect((text?.fullName) == (longName))
        #expect((text?.quota) == ("7d 90%"))
    }

    @Test
    func testMenuBarKeepsCurrentModelWhenQuotaIsUnavailable() {
        let statuses: [(AccountQuotaChip.Status, String)] = [
            (.pending, AccountQuotaMessage.querying),
            (.message(AccountQuotaMessage.reauthRequired), AccountQuotaMessage.reauthRequired),
            (.message(AccountQuotaMessage.queryFailed), AccountQuotaMessage.queryFailed),
            (.message(AccountQuotaMessage.network), AccountQuotaMessage.network),
            (.note(text: AccountQuotaMessage.notConfigured, help: "fixture"), AccountQuotaMessage.notConfigured),
            (.windows([]), AccountQuotaMessage.queryFailed),
        ]
        for (status, expected) in statuses {
            let current = AccountQuotaChip(id: "selected", shortName: "OpenAI", modelName: "gpt-6-astra",
                websiteURL: nil, kind: .officialNote, isCurrent: true, status: status)
            let unrelated = chip(kind: .kimi, status: .windows([
                ParsedQuotaWindow(name: "five_hour", utilization: 0, resetsAt: nil)
            ]))
            let text = AccountQuotaFormatting.menuBarText(forChips: [unrelated, current], currentModelName: "gpt-6.1-sol")
            #expect(text?.name == "gpt-6.1-sol")
            #expect(text?.quota == expected)
            #expect(AccountQuotaFormatting.menuBarText(forChips: [unrelated]) == nil)
        }
    }

    @Test
    func testFormatsQuotasWithSeparateResetAndExpiryDates() {
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
        #expect((AccountQuotaFormatting.plainSummary(for: kimi, now: now)) == ("5h 100%"))
        #expect((AccountQuotaFormatting.runs(for: kimi, now: now).map(\.tone)) == ([.secondary, .remaining(100)]))
        let kimiHelp = AccountQuotaFormatting.help(for: kimi, now: now)
        #expect(kimiHelp.contains("5h 100%"))
        #expect(!(kimiHelp.contains(kimiExpiry)))
        #expect(kimiHelp.contains("5h重置"))
        #expect(!(kimiHelp.contains("后重置")))
        #expect(!(kimiHelp.contains("总到期")))
        #expect(!(AccountQuotaFormatting.plainSummary(for: kimi, now: now).contains("4h37m")))

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
        #expect((AccountQuotaFormatting.plainSummary(for: xai, now: now)) == ("7d 87%"))
        #expect(AccountQuotaFormatting.help(for: xai, now: now).contains("当前供应商"))
        let xaiHelp = AccountQuotaFormatting.help(for: xai, now: now)
        #expect(xaiHelp.contains("7d 87%"))
        #expect(!(xaiHelp.contains(xaiExpiry)))
        #expect(xaiHelp.contains("7d重置"))
        #expect(!(xaiHelp.contains("后重置")))
        #expect(!(xaiHelp.contains("总到期")))
        #expect(!(AccountQuotaFormatting.plainSummary(for: xai, now: now).contains("6d2h")))

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
        #expect((AccountQuotaFormatting.plainSummary(for: zhipu, now: now)) == ("5h 100% · 7d 0% · \(planText)"))
        #expect(!(AccountQuotaFormatting.plainSummary(for: zhipu, now: now).contains("总到期")))
        #expect((AccountQuotaFormatting.runs(for: zhipu, now: now).map(\.tone)) == ([.secondary, .remaining(100), .secondary, .secondary, .remaining(0), .secondary, .deadline(100)]))
        let zhipuHelp = AccountQuotaFormatting.help(for: zhipu, now: now)
        #expect(zhipuHelp.contains("5h 100%"))
        #expect(zhipuHelp.contains("7d 0%"))
        #expect(!(zhipuHelp.contains("后重置")))
        #expect(!(zhipuHelp.contains("5h 100%，")))
        #expect(zhipuHelp.contains(planText))
        #expect(!(zhipuHelp.contains("总到期")))
        #expect(!(zhipuHelp.contains("后到期")))
        #expect(!(zhipuHelp.contains("1mo")))
        #expect(!(AccountQuotaFormatting.plainSummary(for: zhipu, now: now).contains("1mo")))
        #expect(!(AccountQuotaFormatting.plainSummary(for: zhipu, now: now).contains("2d3h")))
        #expect(!(zhipuHelp.contains("2天3小时后重置")))
        let five = zhipuHelp.range(of: "5h")!
        let week = zhipuHelp.range(of: "7d")!
        let plan = zhipuHelp.range(of: planText)!
        #expect((five.lowerBound) < (week.lowerBound))
        #expect((week.lowerBound) < (plan.lowerBound))

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
        let mixedExpiry = AccountQuotaFormatting.monthlyResetPhrase(until: laterReset, now: now)!
        #expect((AccountQuotaFormatting.plainSummary(for: mixed, now: now)) == ("5h 90% · 7d 80% · 1mo 60% · 额度 70% · \(mixedExpiry)"))
        let mixedHelp = AccountQuotaFormatting.help(for: mixed, now: now)
        #expect((mixedHelp.range(of: "5h")!.lowerBound) < (mixedHelp.range(of: "7d")!.lowerBound))
        #expect((mixedHelp.range(of: "7d")!.lowerBound) < (mixedHelp.range(of: "1mo")!.lowerBound))
        #expect(mixedHelp.contains("1mo重置"))
        #expect(!(mixedHelp.contains("截至")))

        let expiredPlan = chip(
            kind: .zhipu,
            status: .windows([
                ParsedQuotaWindow(name: ParsedQuotaWindow.planExpiryName, utilization: 0, resetsAt: now.addingTimeInterval(-60)),
            ])
        )
        let passedBoundary = AccountQuotaFormatting.periodEndPhrase(until: now.addingTimeInterval(-60), now: now)
        #expect((AccountQuotaFormatting.plainSummary(for: expiredPlan, now: now)) == (passedBoundary))
        // A passed boundary does not prove access expired or renewal stopped.
        #expect((AccountQuotaFormatting.help(for: expiredPlan, now: now)) == ("\(passedBoundary)\n\(AccountQuotaFormatting.deadlineColorReference)\nhttps://example.com"))

        let deepseek = chip(
            kind: .deepseek,
            status: .balances([
                ParsedBalance(currency: "USD", amount: 0),
                ParsedBalance(currency: "CNY", amount: 12.36),
            ])
        )
        #expect((AccountQuotaFormatting.plainSummary(for: deepseek, now: now)) == ("余 ¥12.36"))

        let qwen = chip(
            kind: .qwen,
            status: .note(
                text: AccountQuotaMessage.connectOfficial,
                help: AccountQuotaMessage.connectOfficialHelp
            )
        )
        #expect((AccountQuotaFormatting.plainSummary(for: qwen, now: now)) == ("未连接"))
        #expect(AccountQuotaFormatting.help(for: qwen, now: now).contains("不统计本机请求"))
        #expect(!(AccountQuotaFormatting.help(for: qwen, now: now).contains("本地")))

        let officialQwen = chip(
            kind: .qwen,
            status: .qwenPlan(QwenPlanQuota(
                usedPercent: 28,
                remainingCredits: 18_000,
                totalCredits: 25_000,
                resetsAt: nil,
                expiresAt: now.addingTimeInterval(2 * 86_400)
            ))
        )
        let qwenPlanEnd = now.addingTimeInterval(2 * 86_400)
        let qwenText = AccountQuotaFormatting.planExpiryPhrase(until: qwenPlanEnd, now: now)!
        #expect((AccountQuotaFormatting.plainSummary(for: officialQwen, now: now)) == ("额度 72% · \(qwenText)"))
        #expect(AccountQuotaFormatting.help(for: officialQwen, now: now).contains("千问官网套餐额度"))
        let qwenHelp = AccountQuotaFormatting.help(for: officialQwen, now: now)
        #expect(qwenHelp.contains("额度 72%"))
        #expect(qwenHelp.contains("剩余 18,000/25,000 Credits"))
        #expect(qwenHelp.contains(qwenText))
        #expect(!(qwenHelp.contains("总到期")))
        #expect(!(qwenHelp.contains("后到期")))
        #expect(!(qwenHelp.contains("后重置")))

        let websiteQwen = chip(
            kind: .qwen,
            status: .qwenWebsite(QwenWebsiteQuota(
                periodLabel: "1mo",
                remainingPercent: 6.8,
                resetsAt: now.addingTimeInterval(45 * 60)
            ))
        )
        let websiteExpiry = AccountQuotaFormatting.monthlyResetPhrase(
            until: now.addingTimeInterval(45 * 60),
            now: now
        )!
        #expect((AccountQuotaFormatting.plainSummary(for: websiteQwen, now: now)) == ("1mo 6.8% · \(websiteExpiry)"))
        let websiteHelp = AccountQuotaFormatting.help(for: websiteQwen, now: now)
        #expect(websiteHelp.contains("1mo 6.8%"))
        #expect(websiteHelp.contains("1mo重置"))
        #expect(!(websiteHelp.contains("截至")))
        #expect(!(websiteHelp.contains("后重置")))
        #expect(!(websiteHelp.contains("总到期")))
        #expect(!(AccountQuotaFormatting.plainSummary(for: websiteQwen, now: now).contains("45m")))
        #expect(!(AccountQuotaFormatting.help(for: deepseek, now: now).contains("后重置")))
        #expect(!(AccountQuotaFormatting.help(for: qwen, now: now).contains("后重置")))

        let qwenWithoutEnd = chip(
            kind: .qwen,
            status: .qwenPlan(QwenPlanQuota(
                usedPercent: 28,
                remainingCredits: 18_000,
                totalCredits: 25_000,
                resetsAt: nil
            ))
        )
        #expect((AccountQuotaFormatting.plainSummary(for: qwenWithoutEnd, now: now)) == ("额度 72%"))
        #expect(!(AccountQuotaFormatting.help(for: qwenWithoutEnd, now: now).contains("总到期")))
    }

    @Test
    func testAutoRenewingCodingPlanHidesOnlyThePlanDate() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let planEnd = now.addingTimeInterval((40 * 24 + 4) * 3600)
        let autoRenewing = chip(
            kind: .zhipu,
            status: .windows([
                ParsedQuotaWindow(name: "weekly_limit", utilization: 25, resetsAt: now.addingTimeInterval(3 * 86_400)),
                ParsedQuotaWindow(name: ParsedQuotaWindow.planExpiryName, utilization: 0, resetsAt: planEnd, isAutoRenewing: true),
            ])
        )
        let planText = AccountQuotaFormatting.planExpiryPhrase(until: planEnd, now: now)!

        #expect(AccountQuotaFormatting.plainSummary(for: autoRenewing, now: now) == "7d 75% · \(AccountQuotaMessage.autoRenewing)")
        #expect(AccountQuotaFormatting.runs(for: autoRenewing, now: now).map(\.tone) == [.secondary, .remaining(75), .secondary, .secondary])
        let help = AccountQuotaFormatting.help(for: autoRenewing, now: now)
        #expect(help.contains(AccountQuotaMessage.autoRenewing))
        #expect(!help.contains(planText))

        let soonAutoEnd = now.addingTimeInterval(86_400)
        let laterManualEnd = now.addingTimeInterval(10 * 86_400)
        let soonAuto = chip(
            kind: .zhipu,
            status: .windows([ParsedQuotaWindow(name: ParsedQuotaWindow.planExpiryName, utilization: 0, resetsAt: soonAutoEnd, isAutoRenewing: true)])
        )
        let laterManual = chip(
            kind: .zhipu,
            status: .windows([ParsedQuotaWindow(name: ParsedQuotaWindow.planExpiryName, utilization: 0, resetsAt: laterManualEnd)])
        )
        #expect(AccountQuotaFormatting.sortedChips([laterManual, soonAuto]).map(\.id) == [soonAuto.id, laterManual.id])

        let alerts = QuotaAlerts.alerts(for: soonAuto, now: now)
        #expect(alerts.map(\.reason) == [.expiring])
        #expect(alerts.map(\.body) == [AccountQuotaMessage.autoRenewing])
    }

    /// The currency is whatever the provider reports, so a US account reads $.
    /// A mapped code becomes its symbol; an unmapped one keeps the ISO code
    /// behind the amount rather than losing the unit.
    @Test
    func testBalanceCurrencyRendersAsItsSymbol() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        func summary(_ currency: String, _ amount: Double) -> String {
            AccountQuotaFormatting.plainSummary(
                for: chip(
                    kind: .deepseek,
                    status: .balances([ParsedBalance(currency: currency, amount: amount)])
                ),
                now: now
            )
        }
        #expect((summary("CNY", 12.36)) == ("余 ¥12.36"))
        #expect((summary("USD", 12.36)) == ("余 $12.36"))
        #expect((summary("CHF", 12.36)) == ("余 12.36 CHF"))
        #expect((AccountQuotaFormatting.compactMenuBarQuota(
                for: chip(
                    kind: .deepseek,
                    isCurrent: true,
                    status: .balances([ParsedBalance(currency: "USD", amount: 4.2)])
                )
            )) == ("$4.20"))
    }

    @Test
    func testCountdownBoundariesAndUtilizationTones() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        #expect((AccountQuotaFormatting.countdown(until: now, now: now)) == nil)
        #expect((AccountQuotaFormatting.countdown(until: now.addingTimeInterval(-1), now: now)) == nil)
        #expect((AccountQuotaFormatting.countdown(until: now.addingTimeInterval(45 * 60), now: now)) == ("45m"))
        #expect((AccountQuotaFormatting.countdown(until: now.addingTimeInterval(90 * 60), now: now)) == ("1h30m"))
        #expect((AccountQuotaFormatting.countdown(until: now.addingTimeInterval(24 * 3600), now: now)) == ("24h0m"))
        #expect((AccountQuotaFormatting.countdown(until: now.addingTimeInterval(25 * 3600), now: now)) == ("1d1h"))
        #expect((AccountQuotaFormatting.resetClock(until: now, now: now)) == nil)
        #expect((AccountQuotaFormatting.resetDateText(now.addingTimeInterval(-1), now: now)) == nil)
        #expect((AccountQuotaFormatting.chineseCountdown(until: now, now: now)) == nil)
        #expect((AccountQuotaFormatting.resetClock(until: now.addingTimeInterval(45 * 60), now: now)) == ("06:58"))
        #expect((AccountQuotaFormatting.resetDateText(now.addingTimeInterval(45 * 60), now: now)) == ("11月15日 06:58"))
        #expect((AccountQuotaFormatting.chineseCountdown(until: now.addingTimeInterval(45 * 60), now: now)) == ("45分钟"))
        #expect((AccountQuotaFormatting.chineseCountdown(until: now.addingTimeInterval(90 * 60), now: now)) == ("1小时30分"))
        #expect((AccountQuotaFormatting.chineseCountdown(until: now.addingTimeInterval(24 * 3600), now: now)) == ("24小时0分"))
        #expect((AccountQuotaFormatting.resetClock(until: now.addingTimeInterval(24 * 3600), now: now)) == ("11月16日 06:13"))
        #expect((AccountQuotaFormatting.chineseCountdown(until: now.addingTimeInterval(25 * 3600), now: now)) == ("1天1小时"))
        #expect((AccountQuotaFormatting.chineseCountdown(until: now.addingTimeInterval(48 * 3600), now: now)) == ("2天"))

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let evening = calendar.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 22, minute: 0))!
        let overnight = calendar.date(from: DateComponents(year: 2026, month: 9, day: 24, hour: 2, minute: 0))!
        #expect((AccountQuotaFormatting.resetClock(until: overnight, now: evening)) == ("9月24日 02:00"))
        #expect((AccountQuotaFormatting.resetDateText(overnight, now: evening)) == ("9月24日 02:00"))
        #expect((AccountQuotaFormatting.chineseCountdown(until: overnight, now: evening)) == ("4小时0分"))
        #expect((AccountQuotaFormatting.resetClock(until: evening, now: overnight)) == nil)
        let sameHour = calendar.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 23, minute: 0))!
        #expect((AccountQuotaFormatting.planExpiryPhrase(until: sameHour, now: evening)) == ("至9月23日23时"))
        let sameDayWithMinutes = calendar.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 23, minute: 37))!
        #expect((AccountQuotaFormatting.planExpiryPhrase(until: sameDayWithMinutes, now: evening)) == ("至9月23日23时37分"))
        #expect((AccountQuotaFormatting.planExpiryPhrase(until: overnight, now: evening)) == ("至9月24日"))
        let withMinutes = calendar.date(from: DateComponents(year: 2026, month: 9, day: 24, hour: 2, minute: 7))!
        #expect((AccountQuotaFormatting.planExpiryPhrase(until: withMinutes, now: evening)) == ("至9月24日"))
        let midnight = calendar.date(from: DateComponents(year: 2026, month: 9, day: 24, hour: 0, minute: 0))!
        #expect((AccountQuotaFormatting.planExpiryPhrase(until: midnight, now: evening)) == ("至9月24日"))
        #expect((AccountQuotaFormatting.planExpiryPhrase(until: evening, now: overnight)) == ("至9月23日"))

        let expired = chip(
            kind: .kimi,
            status: .windows([
                ParsedQuotaWindow(name: "five_hour", utilization: 12, resetsAt: now.addingTimeInterval(-60)),
            ])
        )
        #expect((AccountQuotaFormatting.plainSummary(for: expired, now: now)) == ("5h 88%"))
        #expect(!(AccountQuotaFormatting.plainSummary(for: expired, now: now).contains("已到期")))
        #expect(!(AccountQuotaFormatting.help(for: expired, now: now).contains("后重置")))
        #expect(!(AccountQuotaFormatting.help(for: expired, now: now).contains("已到期")))

        for (used, expected) in [(69.4, 30.6), (69.5, 30.5), (89.4, 10.6), (89.5, 10.5)] {
            guard case let .remaining(percent) = AccountQuotaFormatting.tone(forUtilization: used) else {
                return recordFailure("percentage quotas must carry a continuous color value")
            }
            #expect(abs((percent) - (expected)) <= 0.0001)
        }
        #expect((AccountQuotaFormatting.plainSummary(for: chip(kind: .deepseek, status: .balances([
            ParsedBalance(currency: "CNY", amount: 0),
        ])), now: now)) == (AccountQuotaMessage.emptyBalance))
        #expect((AccountQuotaFormatting.plainSummary(for: chip(kind: .kimi, status: .windows([])), now: now)) == (AccountQuotaMessage.queryFailed))
    }

    @Test
    func testExhaustedWhenAnyUsageWindowHasNoRemaining() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let exhaustedWeekly = chip(
            kind: .zhipu,
            status: .windows([
                ParsedQuotaWindow(name: "five_hour", utilization: 0, resetsAt: nil),
                ParsedQuotaWindow(name: "weekly_limit", utilization: 100, resetsAt: now.addingTimeInterval(86_400)),
            ])
        )
        #expect(AccountQuotaFormatting.isExhausted(exhaustedWeekly))

        let overdrawn = chip(
            kind: .kimi,
            status: .windows([
                ParsedQuotaWindow(name: "monthly", utilization: 140, resetsAt: nil),
            ])
        )
        #expect(AccountQuotaFormatting.isExhausted(overdrawn))

        let usable = chip(
            kind: .kimi,
            status: .windows([
                ParsedQuotaWindow(name: "five_hour", utilization: 12, resetsAt: nil),
                ParsedQuotaWindow(name: "weekly_limit", utilization: 99, resetsAt: nil),
            ])
        )
        #expect(!(AccountQuotaFormatting.isExhausted(usable)))

        // Plan expiry is a date, not usage: a lapsed plan alone does not mark
        // the provider exhausted, and a live plan does not rescue an empty window.
        let lapsedPlanOnly = chip(
            kind: .zhipu,
            status: .windows([
                ParsedQuotaWindow(name: ParsedQuotaWindow.planExpiryName, utilization: 0, resetsAt: now.addingTimeInterval(-60)),
            ])
        )
        #expect(!(AccountQuotaFormatting.isExhausted(lapsedPlanOnly)))

        let exhaustedPlan = chip(
            kind: .qwen,
            status: .qwenPlan(QwenPlanQuota(usedPercent: 100, remainingCredits: 0, totalCredits: 100, resetsAt: nil))
        )
        #expect(AccountQuotaFormatting.isExhausted(exhaustedPlan))
        let usablePlan = chip(
            kind: .qwen,
            status: .qwenPlan(QwenPlanQuota(usedPercent: 10, remainingCredits: 90, totalCredits: 100, resetsAt: nil))
        )
        #expect(!(AccountQuotaFormatting.isExhausted(usablePlan)))

        let exhaustedWebsite = chip(
            kind: .qwen,
            status: .qwenWebsite(QwenWebsiteQuota(periodLabel: "1mo", remainingPercent: 0, resetsAt: nil))
        )
        #expect(AccountQuotaFormatting.isExhausted(exhaustedWebsite))

        #expect(AccountQuotaFormatting.isExhausted(chip(kind: .deepseek, status: .balances([
            ParsedBalance(currency: "CNY", amount: 0),
        ]))))
        #expect(!(AccountQuotaFormatting.isExhausted(chip(kind: .deepseek, status: .balances([
            ParsedBalance(currency: "CNY", amount: 0.5),
        ])))))
        #expect(!(AccountQuotaFormatting.isExhausted(chip(kind: .kimi, status: .windows([])))))
        #expect(!(AccountQuotaFormatting.isExhausted(chip(kind: .kimi, status: .message(AccountQuotaMessage.queryFailed)))))
    }

    @Test
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
        #expect((AccountQuotaFormatting.sortedWindows(windows).map(\.name)) == (["weekly_limit", "monthly", "five_hour", "credits"]))

        let fiveHourLater = [
            ParsedQuotaWindow(name: "weekly_limit", utilization: 1, resetsAt: soon),
            ParsedQuotaWindow(name: "five_hour", utilization: 1, resetsAt: later),
        ]
        #expect((AccountQuotaFormatting.sortedWindows(fiveHourLater).map(\.name)) == (["five_hour", "weekly_limit"]))
    }

    @Test
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
                    ParsedQuotaWindow(name: "monthly", utilization: 1, resetsAt: mid),
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
                    resetsAt: nil,
                    expiresAt: mid
                ))
            ),
            quotaChip(
                id: "website",
                kind: .officialNote,
                status: .qwenWebsite(QwenWebsiteQuota(
                    periodLabel: "1mo",
                    remainingPercent: 50,
                    resetsAt: soon
                ))
            ),
            quotaChip(
                id: "latest",
                kind: .zhipu,
                status: .windows([
                    ParsedQuotaWindow(name: "five_hour", utilization: 1, resetsAt: soon),
                    ParsedQuotaWindow(name: ParsedQuotaWindow.planExpiryName, utilization: 0, resetsAt: late),
                ])
            ),
            quotaChip(
                id: "same",
                kind: .kimi,
                status: .windows([
                    ParsedQuotaWindow(name: "monthly", utilization: 1, resetsAt: mid),
                ])
            ),
        ]

        #expect((AccountQuotaFormatting.sortedChips(chips).map(\.id)) == (["website", "current", "plan", "same", "latest", "note", "balance"]))
    }

    @Test
    func testUndatedAndFailedPlansAlwaysPrecedePayAsYouGoProviders() {
        let plans: [AccountQuotaChip.Status] = [
            .pending, .note(text: AccountQuotaMessage.notConfigured, help: ""),
            .message(AccountQuotaMessage.queryFailed), .message(AccountQuotaMessage.reauthRequired),
            .message(AccountQuotaMessage.notLoggedIn), .message(AccountQuotaMessage.network),
            .windows([ParsedQuotaWindow(name: "weekly_limit", utilization: 25,
                resetsAt: Date(timeIntervalSince1970: 1_700_000_000))]),
            .windows([]),
        ]
        let metered: [AccountQuotaChip.Status] = [
            .pending, .message(AccountQuotaMessage.queryFailed),
            .message(AccountQuotaMessage.notConfigured), .balances([]),
            .balances([ParsedBalance(currency: "CNY", amount: 0)]),
            .balances([ParsedBalance(currency: "CNY", amount: 12.36)]),
        ]
        for planStatus in plans {
            for kind in [CCSwitchQuotaKind.deepseek, .stepfun, .blackForestLabs, .luma] {
                for balanceStatus in metered {
                    let plan = quotaChip(id: "xai", kind: .xaiOAuth, status: planStatus)
                    let balance = quotaChip(id: "metered", kind: kind, isCurrent: true, status: balanceStatus)
                    for input in [[balance, plan], [plan, balance]] {
                        #expect(AccountQuotaFormatting.sortedChips(input).map(\.id) == ["xai", "metered"])
                    }
                }
            }
        }
    }

    @Test
    func testQuotaBillingGroupsPreserveExpiryAndStableTieOrder() {
        let late = Date(timeIntervalSince1970: 1_700_000_000)
        let soon = late.addingTimeInterval(-86_400)
        let chips = [
            quotaChip(id: "deepseek", kind: .deepseek, status: .message(AccountQuotaMessage.queryFailed)),
            quotaChip(id: "xai", kind: .xaiOAuth, status: .pending),
            quotaChip(id: "luma", kind: .luma, status: .balances([ParsedBalance(currency: "USD", amount: 1)])),
            quotaChip(id: "late", kind: .kimi, isCurrent: true, status: .windows([
                ParsedQuotaWindow(name: ParsedQuotaWindow.planExpiryName, utilization: 0, resetsAt: late)])),
            quotaChip(id: "undated", kind: .qwen, status: .message(AccountQuotaMessage.network)),
            quotaChip(id: "soon", kind: .zhipu, status: .windows([
                ParsedQuotaWindow(name: ParsedQuotaWindow.planExpiryName, utilization: 0, resetsAt: soon)])),
            quotaChip(id: "balanceResult", kind: .minimax, status: .balances([ParsedBalance(currency: "CNY", amount: 3)])),
        ]
        #expect(AccountQuotaFormatting.sortedChips(chips).map(\.id) ==
            ["soon", "late", "xai", "undated", "deepseek", "luma", "balanceResult"])
    }

    @Test
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
                    ParsedQuotaWindow(name: "monthly", utilization: 1, resetsAt: other),
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
        #expect((AccountQuotaFormatting.sortedChips(chips).map(\.id)) == (["other", "zhipu"]))
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

struct CCSwitchQuotaParserTests {
    @Test
    func testParsesOfficialQwenPlanCredits() {
        let data = Data(#"""
        {"token_plan":{"subscribed":true,"totalCredits":25000,"remainingCredits":18000,"usedPct":28,"resetDate":"2026-08-01T00:00:00.000Z"}}
        """#.utf8)
        #expect((QwenPlanQuotaParser.parse(data)) == (QwenPlanQuota(
                usedPercent: 28,
                remainingCredits: 18_000,
                totalCredits: 25_000,
                resetsAt: ISO8601DateFormatter().date(from: "2026-08-01T00:00:00Z")
            )))
        #expect((QwenPlanQuotaParser.parse(Data(#"{"token_plan":{"subscribed":false}}"#.utf8))) == nil)
    }

    @Test
    func testParsesQwenWebsiteQuotaText() {
        let data = Data("个人版 Pro 套餐\n月额度 剩余量 6.8 %\n重置时间 2026-10-05 00:00:00".utf8)
        let quota = QwenWebsiteQuotaParser.parse(data)
        #expect((quota?.periodLabel) == ("1mo"))
        #expect((quota?.remainingPercent) == (6.8))
        #expect((quota?.resetsAt?.timeIntervalSince1970) == (ISO8601DateFormatter().date(from: "2026-10-04T16:00:00Z")?.timeIntervalSince1970))
        let capturedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let persisted = quota.flatMap {
            QwenWebsiteQuotaParser.persistedData(for: $0, capturedAt: capturedAt)
        }
        let cached = persisted.flatMap(QwenWebsiteQuotaParser.parse)
        #expect((cached?.periodLabel) == ("1mo"))
        #expect((cached?.remainingPercent) == (6.8))
        #expect((cached?.capturedAt) == (capturedAt))
        #expect((cached?.isCached) == (true))
    }

    @Test
    func testParsesKimiZhipuAndDeepSeekBodiesWithoutKeepingRawText() {
        let kimi = CCSwitchQuotaParsers.parseKimi(Data(#"""
        {"limits":[{"detail":{"limit":100,"remaining":100,"resetTime":"2026-09-22T08:37:00Z"}}],"usage":{"limit":200,"remaining":50,"resetTime":1760000000}}
        """#.utf8))
        guard case let .windows(kimiWindows) = kimi else {
            return recordFailure("expected kimi windows")
        }
        #expect((kimiWindows.map(\.name)) == (["five_hour", "weekly_limit"]))
        #expect((kimiWindows.map { AccountQuotaFormatting.roundedPercent($0.utilization) }) == ([0, 75]))
        #expect((kimiWindows[0].resetsAt) != nil)
        #expect((kimiWindows[1].resetsAt) != nil)

        let zhipu = CCSwitchQuotaParsers.parseZhipu(Data(#"""
        {"success":true,"data":{"limits":[{"type":"tokens_limit","unit":3,"percentage":0,"nextResetTime":1700000000000},{"type":"tokens_limit","unit":6,"percentage":100,"nextResetTime":1700200000000}]}}
        """#.utf8))
        guard case let .windows(zhipuWindows) = zhipu else {
            return recordFailure("expected zhipu windows")
        }
        #expect((zhipuWindows.map(\.name)) == (["five_hour", "weekly_limit"]))
        #expect((zhipuWindows.map(\.utilization)) == ([0, 100]))

        let deepseek = CCSwitchQuotaParsers.parseDeepSeek(Data(#"""
        {"balance_infos":[{"currency":"CNY","total_balance":"12.36"},{"currency":"USD","total_balance":0}]}
        """#.utf8))
        guard case let .balances(balances) = deepseek else {
            return recordFailure("expected balances")
        }
        #expect((balances) == ([
            ParsedBalance(currency: "CNY", amount: 12.36),
            ParsedBalance(currency: "USD", amount: 0),
        ]))
    }

    @Test
    func testRejectsMalformedBodies() {
        #expect((CCSwitchQuotaParsers.parseKimi(Data("not-json".utf8))) == (.rejected))
        #expect((CCSwitchQuotaParsers.parseZhipu(Data(#"{"success":false}"#.utf8))) == (.rejected))
        #expect((CCSwitchQuotaParsers.parseDeepSeek(Data("[]".utf8))) == (.rejected))
        #expect((CCSwitchQuotaParsers.parseKimi(Data(#"{}"#.utf8))) == (.windows([])))
    }

    @Test
    func testParsesKimiResetDatesFromCountRatioAndCLIBodies() {
        let counted = CCSwitchQuotaParsers.parseKimi(Data(#"""
        {"usage":{"limit":"2048","used":"10","remaining":"1834","resetTime":"2026-01-09T15:23:13.716839300Z"},"limits":[{"window":{"duration":300,"timeUnit":"TIME_UNIT_MINUTE"},"detail":{"limit":"200","used":"1","remaining":"61","resetTime":"2026-01-06T13:33:02.717479433Z"}}]}
        """#.utf8))
        guard case let .windows(countedWindows) = counted else {
            return recordFailure("expected counted kimi windows")
        }
        #expect((countedWindows.map(\.name)) == (["five_hour", "weekly_limit"]))
        #expect(abs((countedWindows[0].utilization) - (69.5)) <= 0.0001)
        #expect(abs((countedWindows[1].utilization) - (Double(2048 - 1834) / 2048 * 100)) <= 0.0001)
        assertReset(countedWindows[0].resetsAt, equals: "2026-01-06T13:33:02.717Z")
        assertReset(countedWindows[1].resetsAt, equals: "2026-01-09T15:23:13.716Z")

        let longFraction = "2026-01-09T15:23:13.716" + String(repeating: "8", count: 15) + "Z"
        let truncated = CCSwitchQuotaParsers.parseKimi(Data("""
        {"usage":{"limit":100,"remaining":100,"resetTime":"\(longFraction)"}}
        """.utf8))
        guard case let .windows(truncatedWindows) = truncated else {
            return recordFailure("expected truncated kimi reset")
        }
        assertReset(truncatedWindows.first?.resetsAt, equals: "2026-01-09T15:23:13.716Z")

        let alternateKeys = CCSwitchQuotaParsers.parseKimi(Data(#"""
        {"limits":[{"detail":{"limit":"100","remaining":"25","reset_at":"1760000000"}}],"usage":{"limit":80,"used":20,"resetAt":"1760000000000"}}
        """#.utf8))
        guard case let .windows(alternateWindows) = alternateKeys else {
            return recordFailure("expected alternate kimi reset keys")
        }
        #expect((alternateWindows.map(\.name)) == (["five_hour", "weekly_limit"]))
        #expect((alternateWindows.map { AccountQuotaFormatting.roundedPercent($0.utilization) }) == ([75, 25]))
        #expect((alternateWindows[0].resetsAt) == (Date(timeIntervalSince1970: 1_760_000_000)))
        #expect((alternateWindows[1].resetsAt) == (Date(timeIntervalSince1970: 1_760_000_000)))

        let missingReset = CCSwitchQuotaParsers.parseKimi(Data(#"""
        {"limits":[{"detail":{"limit":100,"remaining":40,"resetTime":"not-a-date"}}],"usage":{"limit":80,"remaining":20,"resetTime":""}}
        """#.utf8))
        guard case let .windows(missingWindows) = missingReset else {
            return recordFailure("expected kimi windows without resets")
        }
        #expect((missingWindows.map(\.name)) == (["five_hour", "weekly_limit"]))
        #expect((missingWindows.map { AccountQuotaFormatting.roundedPercent($0.utilization) }) == ([60, 75]))
        #expect((missingWindows[0].resetsAt) == nil)
        #expect((missingWindows[1].resetsAt) == nil)

        let ratios = CCSwitchQuotaParsers.parseKimi(Data(#"""
        {"usages":{"limit_5h":{"used_ratio":0.5,"reset_time":"2026-09-22T08:37:00Z"},"limit_7d":{"used_ratio":1.4,"reset_time":"2026-09-29T08:37:00Z"},"limit_month_total":{"used_ratio":"0.25","reset_time":1760500000}},"limits":[{"detail":{"limit":100,"remaining":0,"resetTime":"2026-09-22T08:37:00Z"}}],"usage":{"limit":200,"remaining":0,"resetTime":"2026-09-29T08:37:00Z"}}
        """#.utf8))
        guard case let .windows(ratioWindows) = ratios else {
            return recordFailure("expected kimi ratio windows")
        }
        #expect((ratioWindows.map(\.name)) == (["five_hour", "weekly_limit", "monthly"]))
        #expect(abs((ratioWindows[0].utilization) - (50)) <= 0.0001)
        #expect(abs((ratioWindows[1].utilization) - (100)) <= 0.0001)
        #expect(abs((ratioWindows[2].utilization) - (25)) <= 0.0001)
        #expect((ratioWindows[2].resetsAt) == (Date(timeIntervalSince1970: 1_760_500_000)))
        #expect((ratioWindows[0].resetsAt) != nil)
        #expect((ratioWindows[1].resetsAt) != nil)

        let weeklyOnly = CCSwitchQuotaParsers.parseKimi(Data(#"""
        {"usages":{"limit_7d":{"used_ratio":0.2,"reset_time":"2026-09-29T08:37:00Z"}}}
        """#.utf8))
        guard case let .windows(weeklyOnlyWindows) = weeklyOnly else {
            return recordFailure("expected weekly-only ratio")
        }
        #expect((weeklyOnlyWindows.map(\.name)) == (["weekly_limit"]))
        #expect(abs((weeklyOnlyWindows[0].utilization) - (20)) <= 0.0001)

        let fallback = CCSwitchQuotaParsers.parseKimi(Data(#"""
        {"usages":{"limit_5h":{"used_ratio":0,"reset_time":"2026-09-22T08:37:00Z"},"limit_7d":{"used_ratio":0,"reset_time":"2026-09-29T08:37:00Z"}},"limits":[{"window":{"duration":300,"timeUnit":"TIME_UNIT_MINUTE"},"detail":{"limit":100,"used":60,"remaining":40,"resetTime":"2026-09-22T08:37:01Z"}}],"usage":{"limit":200,"used":150,"remaining":50,"resetTime":"2026-09-29T08:37:01.500Z"}}
        """#.utf8))
        guard case let .windows(fallbackWindows) = fallback else {
            return recordFailure("expected kimi count fallback")
        }
        #expect((fallbackWindows.map(\.name)) == (["five_hour", "weekly_limit"]))
        #expect((fallbackWindows.map { AccountQuotaFormatting.roundedPercent($0.utilization) }) == ([60, 75]))

        let monthlyKeepsZero = CCSwitchQuotaParsers.parseKimi(Data(#"""
        {"usages":{"limit_5h":{"used_ratio":0,"reset_time":"2026-09-22T08:37:00Z"},"limit_month_total":{"used_ratio":0.4,"reset_time":"2026-10-22T08:37:00Z"}},"limits":[{"detail":{"limit":100,"remaining":40,"resetTime":"2026-09-22T08:37:00Z"}}],"usage":{"limit":200,"remaining":50,"resetTime":"2026-09-29T08:37:00Z"}}
        """#.utf8))
        guard case let .windows(monthlyWindows) = monthlyKeepsZero else {
            return recordFailure("expected monthly ratio to keep the zero session")
        }
        #expect((monthlyWindows.map(\.name)) == (["five_hour", "weekly_limit", "monthly"]))
        #expect((monthlyWindows.map { AccountQuotaFormatting.roundedPercent($0.utilization) }) == ([0, 75, 40]))

        let mismatched = CCSwitchQuotaParsers.parseKimi(Data(#"""
        {"usages":{"limit_5h":{"used_ratio":0,"reset_time":"2026-09-22T08:37:00Z"}},"limits":[{"window":{"duration":7,"timeUnit":"TIME_UNIT_DAY"},"detail":{"limit":100,"remaining":40,"resetTime":"2026-09-22T08:37:00Z"}}],"usage":{"limit":200,"remaining":50,"resetTime":"2026-09-29T08:37:00Z"}}
        """#.utf8))
        guard case let .windows(mismatchedWindows) = mismatched else {
            return recordFailure("expected mismatched period to keep the zero ratio")
        }
        #expect((mismatchedWindows.map(\.name)) == (["five_hour", "weekly_limit"]))
        #expect((mismatchedWindows.map { AccountQuotaFormatting.roundedPercent($0.utilization) }) == ([0, 75]))

        let drifted = CCSwitchQuotaParsers.parseKimi(Data(#"""
        {"usages":{"limit_5h":{"used_ratio":0,"reset_time":"2026-09-22T08:37:00Z"},"limit_7d":{"used_ratio":0,"reset_time":"2026-09-29T08:37:00Z"}},"limits":[{"detail":{"limit":100,"remaining":40,"resetTime":"2026-09-22T08:37:03Z"}}],"usage":{"limit":200,"remaining":50,"resetTime":"2026-09-29T08:37:03Z"}}
        """#.utf8))
        guard case let .windows(driftedWindows) = drifted else {
            return recordFailure("expected drifted resets to keep zero ratios")
        }
        #expect((driftedWindows.map { AccountQuotaFormatting.roundedPercent($0.utilization) }) == ([0, 0]))

        let cli = CCSwitchQuotaParsers.parseKimi(Data(#"""
        {"data":{"quota":{"usages":{"limit5h":{"usedRatio":0.1,"resetAt":"2026-09-22T08:37:00Z"},"limit7d":{"usedRatio":0.2,"resetAt":1760000000},"monthTotal":{"usedRatio":0.3,"resetAt":"2026-10-22T08:37:00Z"},"monthCode":{"usedRatio":0.9,"resetAt":"2026-10-01T00:00:00Z"}}}}}
        """#.utf8))
        guard case let .windows(cliWindows) = cli else {
            return recordFailure("expected kimi cli windows")
        }
        #expect((cliWindows.map(\.name)) == (["five_hour", "weekly_limit", "monthly"]))
        #expect((cliWindows.map { AccountQuotaFormatting.roundedPercent($0.utilization) }) == ([10, 20, 30]))
        #expect((cliWindows[0].resetsAt) != nil)
        #expect((cliWindows[1].resetsAt) == (Date(timeIntervalSince1970: 1_760_000_000)))
        #expect((cliWindows[2].resetsAt) != nil)

        let web = CCSwitchQuotaParsers.parseKimi(Data(#"""
        {"usages":[{"scope":"FEATURE_OTHER","detail":{"limit":1,"remaining":0}},{"scope":"FEATURE_CODING","detail":{"limit":"2048","remaining":"1834","resetTime":"2026-01-09T15:23:13.716839300Z"},"limits":[{"window":{"duration":300,"timeUnit":"TIME_UNIT_MINUTE"},"detail":{"limit":"200","remaining":"61","resetTime":"2026-01-06T13:33:02.717479433Z"}}]}]}
        """#.utf8))
        guard case let .windows(webWindows) = web else {
            return recordFailure("expected kimi web windows")
        }
        #expect((webWindows.map(\.name)) == (["five_hour", "weekly_limit"]))
        #expect(abs((webWindows[0].utilization) - (69.5)) <= 0.0001)
        assertReset(webWindows[0].resetsAt, equals: "2026-01-06T13:33:02.717Z")
        assertReset(webWindows[1].resetsAt, equals: "2026-01-09T15:23:13.716Z")
        #expect((CCSwitchQuotaParsers.parseKimi(Data(#"""
            {"usages":[{"scope":"FEATURE_OTHER","detail":{"limit":1,"remaining":0}}]}
            """#.utf8))) == (.windows([])))
    }

    @Test
    func testKeepsOrdinaryISOResetDates() {
        let parsed = CCSwitchQuotaParsers.parseOpenAI(Data(#"""
        {"rate_limit":{"primary_window":{"used_percent":1,"limit_window_seconds":18000,"reset_at":"2026-09-22T08:37:00Z"},"secondary_window":{"used_percent":2,"limit_window_seconds":604800,"reset_at":"2026-09-22T08:37:00.500Z"}}}
        """#.utf8))
        guard case let .windows(windows) = parsed else {
            return recordFailure("expected openai windows")
        }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        #expect((windows.first { $0.name == "five_hour" }?.resetsAt) == (plain.date(from: "2026-09-22T08:37:00Z")))
        #expect((windows.first { $0.name == "weekly_limit" }?.resetsAt) == (fractional.date(from: "2026-09-22T08:37:00.500Z")))
    }

    private func assertReset(
        _ date: Date?,
        equals iso: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date, let expected = formatter.date(from: iso) else {
            return recordFailure("missing reset \(String(describing: date)) expected \(iso)", sourceLocation: sourceLocation)
        }
        #expect(abs((date.timeIntervalSince1970) - (expected.timeIntervalSince1970)) <= 0.001, sourceLocation: sourceLocation)
    }

    private func shanghaiFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }

    @Test
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
        #expect((window?.name) == (ParsedQuotaWindow.planExpiryName))
        #expect((window?.utilization) == (0))
        let formatter = shanghaiFormatter()
        #expect((window?.resetsAt) == (formatter.date(from: "2026-10-03 00:00:00")))
        #expect((window?.resetsAt) != (formatter.date(from: "2026-10-03 10:00:00")))
        #expect((window?.resetsAt) != (formatter.date(from: "2026-11-03 10:00:00")))
        #expect((window?.resetsAt) != (formatter.date(from: "2026-09-24 21:12:00")))
        #expect((window?.resetsAt) != (formatter.date(from: "2099-01-01 00:00:00")))

        let sameDayAfternoon = Date(timeIntervalSince1970: 1_791_010_800)
        let sameDayPhrase = AccountQuotaFormatting.periodEndPhrase(
            until: window?.resetsAt ?? Date(),
            now: sameDayAfternoon
        )
        #expect(sameDayPhrase == ("至10月3日"))
        #expect(!(sameDayPhrase.contains("10时")))

        let timed = CCSwitchQuotaParsers.parseZhipuSubscription(Data(
            #"{"success":true,"data":[{"status":"VALID","inCurrentPeriod":true,"valid":"2026-10-03 10:00:00-2026-11-03 10:00:00","nextRenewTime":"2026-10-03 21:12:47"}]}"#.utf8
        ))
        #expect((timed?.resetsAt) == (formatter.date(from: "2026-10-03 21:12:47")))

        let dateOnly = CCSwitchQuotaParsers.parseZhipuSubscription(Data(
            #"{"success":true,"data":[{"status":"VALID","inCurrentPeriod":true,"nextRenewTime":"2026-10-03"}]}"#.utf8
        ))
        #expect((dateOnly?.resetsAt) == (formatter.date(from: "2026-10-03 00:00:00")))

        let otherDay = CCSwitchQuotaParsers.parseZhipuSubscription(Data(
            #"{"success":true,"data":[{"status":"VALID","inCurrentPeriod":true,"valid":"2026-09-03 21:12:47-2026-10-03 21:12:47","nextRenewTime":"2026-10-03"}]}"#.utf8
        ))
        #expect((otherDay?.resetsAt) == (formatter.date(from: "2026-10-03 00:00:00")))
        #expect((otherDay?.resetsAt) != (formatter.date(from: "2026-10-03 21:12:47")))
    }

    @Test
    func testParsesZhipuAutoRenewalOnlyFromExplicitEnabledValues() {
        func subscription(_ autoRenew: String) -> ParsedQuotaWindow? {
            CCSwitchQuotaParsers.parseZhipuSubscription(Data(#"""
            {"success":true,"data":[{"status":"VALID","inCurrentPeriod":true,"valid":"2026-10-03 10:00:00-2026-11-03 10:00:00","nextRenewTime":"2026-10-03","autoRenew":\#(autoRenew)}]}
            """#.utf8))
        }

        #expect(subscription("true")?.isAutoRenewing == true)
        #expect(subscription("1")?.isAutoRenewing == true)
        #expect(subscription("false")?.isAutoRenewing == false)
        #expect(subscription("0")?.isAutoRenewing == false)
        #expect(subscription("2")?.isAutoRenewing == false)
        #expect(subscription(#""1""#)?.isAutoRenewing == false)
        #expect(subscription("null")?.isAutoRenewing == false)

        let missing = CCSwitchQuotaParsers.parseZhipuSubscription(Data(#"""
        {"success":true,"data":[{"status":"VALID","inCurrentPeriod":true,"valid":"2026-10-03 10:00:00-2026-11-03 10:00:00","nextRenewTime":"2026-10-03"}]}
        """#.utf8))
        #expect(missing?.isAutoRenewing == false)

        let current = CCSwitchQuotaParsers.parseZhipuSubscription(Data(#"""
        {"success":true,"data":[
          {"status":"VALID","inCurrentPeriod":false,"valid":"2026-10-03 10:00:00-2026-11-03 10:00:00","nextRenewTime":"2026-10-03","autoRenew":1},
          {"status":"VALID","inCurrentPeriod":true,"valid":"2026-10-03 10:00:00-2026-11-03 10:00:00","nextRenewTime":"2026-10-03","autoRenew":0}
        ]}
        """#.utf8))
        #expect(current?.isAutoRenewing == false)
    }

    @Test
    func testZhipuPlanExpiryFallsBackToTheValidRangeEnd() {
        let body = Data(#"""
        {"success":true,"data":[
          {"status":"VALID","inCurrentPeriod":true,"valid":"2026-10-03 10:00:00-2026-11-03 10:00:00","nextRenewTime":" "},
          {"status":"VALID","inCurrentPeriod":true,"valid":"2099-01-01 00:00:00-2099-02-01 00:00:00","nextRenewTime":"2099-01-01"}
        ]}
        """#.utf8)
        let window = CCSwitchQuotaParsers.parseZhipuSubscription(body)
        #expect((window?.resetsAt) == (shanghaiFormatter().date(from: "2026-11-03 10:00:00")))
    }

    @Test
    func testZhipuSubscriptionWithoutACurrentPeriodAddsNothing() {
        #expect((CCSwitchQuotaParsers.parseZhipuSubscription(Data(#"{"success":false}"#.utf8))) == nil)
        #expect((CCSwitchQuotaParsers.parseZhipuSubscription(Data("not-json".utf8))) == nil)
        #expect((CCSwitchQuotaParsers.parseZhipuSubscription(Data(
            #"{"success":true,"data":[{"status":"VALID","inCurrentPeriod":false,"valid":"2026-10-03 10:00:00-2026-12-03 10:00:00","nextRenewTime":"2026-10-03"}]}"#.utf8
        ))) == nil)
    }

    @Test
    func testParsesOpenAIPlanExpiryOnlyFromTheMatchingAccount() {
        let iso = Data(#"""
        {"accounts":{
          "other":{"entitlement":{"expires_at":"2026-01-01T00:00:00Z","renews_at":"2026-12-01T00:00:00Z"}},
          "account-id":{"entitlement":{"expires_at":"2026-10-15T00:00:00Z","renews_at":"2026-09-15T00:00:00Z"}}
        },"account_ordering":["other","account-id"]}
        """#.utf8)
        let window = CCSwitchQuotaParsers.parseOpenAIPlanExpiry(iso, accountID: "account-id")
        #expect((window?.name) == (ParsedQuotaWindow.planExpiryName))
        #expect((window?.utilization) == (0))
        #expect((window?.resetsAt) == (ISO8601DateFormatter().date(from: "2026-10-15T00:00:00Z")))
        #expect((window?.resetsAt) != (ISO8601DateFormatter().date(from: "2026-09-15T00:00:00Z")))
        #expect((window?.resetsAt) != (ISO8601DateFormatter().date(from: "2026-01-01T00:00:00Z")))

        let millis = Data(#"""
        {"accounts":{"account-id":{"entitlement":{"expires_at":1790000000000,"renews_at":1700000000}}}}
        """#.utf8)
        #expect((CCSwitchQuotaParsers.parseOpenAIPlanExpiry(millis, accountID: "account-id")?.resetsAt) == (Date(timeIntervalSince1970: 1_790_000_000)))
        #expect((CCSwitchQuotaParsers.parseOpenAIPlanExpiry(iso, accountID: "missing")) == nil)
        #expect((CCSwitchQuotaParsers.parseOpenAIPlanExpiry(iso, accountID: "  ")) == nil)
        #expect((CCSwitchQuotaParsers.parseOpenAIPlanExpiry(
            Data(#"{"accounts":{"account-id":{"entitlement":{"renews_at":"2026-10-15T00:00:00Z"}}}}"#.utf8),
            accountID: "account-id"
        )) == nil)
        #expect((CCSwitchQuotaParsers.parseOpenAIPlanExpiry(Data("not-json".utf8), accountID: "account-id")) == nil)
    }

    @Test
    func testParsesOpenAIPlanExpiryFromTheSignedInDefaultAccountEntry() {
        let expires = ISO8601DateFormatter().date(from: "2026-10-15T00:00:00Z")
        // ChatGPT keys the signed-in account `default` and repeats that key in
        // `last_account_id`; it never uses the account id as the key.
        let signedIn = Data(#"""
        {"accounts":{"default":{"account":{"po_id":"org-1"},"plan_type":"pro","entitlement":{
          "subscription_id":"sub_1","has_active_subscription":true,"subscription_plan":"chatgptproplan",
          "expires_at":"2026-10-15T00:00:00Z","renews_at":"2026-10-15T00:00:00Z"}}},
         "last_account_id":"default","is_paid":true}
        """#.utf8)
        #expect((CCSwitchQuotaParsers.parseOpenAIPlanExpiry(signedIn, accountID: "account-id")?.resetsAt) == expires)

        let named = Data(#"{"accounts":{"default":{"account_id":"account-id","entitlement":{"expires_at":"2026-10-15T00:00:00Z"}}}}"#.utf8)
        #expect((CCSwitchQuotaParsers.parseOpenAIPlanExpiry(named, accountID: "account-id")?.resetsAt) == expires)
        #expect((CCSwitchQuotaParsers.parseOpenAIPlanExpiry(named, accountID: "other-account")) == nil)

        let workspace = Data(#"{"accounts":{"team-1":{"entitlement":{"expires_at":"2026-10-15T00:00:00Z"}}},"last_account_id":"team-1"}"#.utf8)
        #expect((CCSwitchQuotaParsers.parseOpenAIPlanExpiry(workspace, accountID: "account-id")?.resetsAt) == expires)

        // A plan without an active subscription reports a placeholder instead
        // of a boundary, and a placeholder is not a deadline.
        let free = Data(#"{"accounts":{"default":{"entitlement":{"has_active_subscription":false,"subscription_plan":"chatgptfreeplan","expires_at":"2999-09-28T13:14:52+00:00"}}}}"#.utf8)
        #expect((CCSwitchQuotaParsers.parseOpenAIPlanExpiry(free, accountID: "account-id")) == nil)

        // The signed-in entry wins over an unrelated one, and an entry naming
        // or keyed by another account is never this account's boundary.
        let withExtra = Data(#"{"accounts":{"other":{"entitlement":{"expires_at":"2026-01-01T00:00:00Z"}},"default":{"entitlement":{"expires_at":"2026-10-15T00:00:00Z"}}}}"#.utf8)
        #expect((CCSwitchQuotaParsers.parseOpenAIPlanExpiry(withExtra, accountID: "account-id")?.resetsAt) == expires)
        let foreign = Data(#"{"accounts":{"other-account":{"entitlement":{"expires_at":"2026-10-15T00:00:00Z"}}}}"#.utf8)
        #expect((CCSwitchQuotaParsers.parseOpenAIPlanExpiry(foreign, accountID: "account-id")) == nil)
        let foreignNamed = Data(#"{"accounts":{"default":{"account_id":"other-account","entitlement":{"expires_at":"2026-10-15T00:00:00Z"}}}}"#.utf8)
        #expect((CCSwitchQuotaParsers.parseOpenAIPlanExpiry(foreignNamed, accountID: "account-id")) == nil)
    }
}

struct AccountQuotaClientTests {
    @Test
    func testQueriesOnlyTheProviderHostAndKeepsTargetOrder() async throws {
        let transport = ScriptedQuotaTransport { request in
            let body: String
            switch request.url?.host {
            case "chatgpt.com":
                #expect((request.value(forHTTPHeaderField: "Authorization")) == ("Bearer official-token"))
                #expect((request.value(forHTTPHeaderField: "ChatGPT-Account-ID")) == ("account-id"))
                switch request.url?.path {
                case "/backend-api/wham/usage":
                    body = #"{"rate_limit":{"primary_window":{"used_percent":42,"limit_window_seconds":18000,"reset_at":1760000000},"secondary_window":{"used_percent":13,"limit_window_seconds":604800,"reset_at":1760500000}}}"#
                case "/backend-api/accounts/check/v4-2023-04-27":
                    body = "{}"
                default:
                    recordFailure("unexpected official path \(request.url?.path ?? "")")
                    body = "{}"
                }
            case "api.kimi.com":
                #expect((request.url?.path) == ("/coding/v1/usages"))
                #expect((request.value(forHTTPHeaderField: "Authorization")) == ("Bearer unit-test-key"))
                body = #"{"limits":[{"detail":{"limit":100,"remaining":100,"resetTime":1760000000000}}]}"#
            case "api.deepseek.com":
                #expect((request.url?.path) == ("/user/balance"))
                body = #"{"balance_infos":[{"currency":"CNY","total_balance":"12.36"}]}"#
            default:
                recordFailure("unexpected host \(request.url?.absoluteString ?? "")")
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

        #expect((chips.map(\.id)) == (["official", "kimi", "deepseek"]))
        #expect((chips.map(\.status)) == ([
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
        ]))
        let hosts = transport.requests.compactMap { $0.url?.host }
        #expect((hosts.sorted()) == (["api.deepseek.com", "api.kimi.com", "chatgpt.com", "chatgpt.com"]))
        #expect((transport.requests.compactMap { request -> String? in
                guard request.url?.host == "chatgpt.com" else { return nil }
                return request.url?.path
            }) == ([
                "/backend-api/wham/usage",
                "/backend-api/accounts/check/v4-2023-04-27",
            ]))
        #expect(!(chips.contains { AccountQuotaFormatting.plainSummary(for: $0, now: Date()).contains("unit-test-key") }))
    }

    @Test
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
            #expect((request.value(forHTTPHeaderField: "Authorization")) == ("Bearer official-token"))
            #expect((request.value(forHTTPHeaderField: "ChatGPT-Account-ID")) == ("account-id"))
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
        #expect((matched.requests.map { $0.url?.path }) == ([
            "/backend-api/wham/usage",
            "/backend-api/accounts/check/v4-2023-04-27",
        ]))
        #expect((matchedChips.map(\.status)) == ([
            .windows(usageWindows + [
                ParsedQuotaWindow(
                    name: ParsedQuotaWindow.planExpiryName,
                    utilization: 0,
                    resetsAt: ISO8601DateFormatter().date(from: "2026-10-15T00:00:00Z")
                ),
            ]),
        ]))
        let summary = AccountQuotaFormatting.plainSummary(
            for: matchedChips[0],
            now: Date(timeIntervalSince1970: 1_758_600_000)
        )
        #expect(summary.contains("5h 58%"))
        #expect(summary.contains("7d 87%"))
        #expect((summary.range(of: "5h")!.lowerBound) < (summary.range(of: "7d")!.lowerBound))
        #expect(summary.contains("至10月15日"))
        #expect(!(summary.contains("总到期")))
        #expect(!(summary.contains("后重置")))
        #expect(!(summary.contains("must-not-be-sent")))
        #expect(!(summary.contains("official-token")))

        let timedOut = ScriptedQuotaTransport { request in
            if request.url?.path == "/backend-api/accounts/check/v4-2023-04-27" {
                throw URLError(.timedOut)
            }
            return AccountQuotaHTTPResponse(statusCode: 200, headers: [:], body: Data(usage.utf8))
        }
        let timedOutChips = try await AccountQuotaClient(transport: timedOut).refresh(targets: [
            quotaTarget(id: "official", name: "OpenAI", kind: .officialNote, key: nil, accessToken: "official-token", accountID: "account-id"),
        ])
        #expect((timedOutChips.map(\.status)) == ([.windows(usageWindows)]))

        let rejected = ScriptedQuotaTransport { request in
            if request.url?.path == "/backend-api/accounts/check/v4-2023-04-27" {
                return AccountQuotaHTTPResponse(statusCode: 401, headers: [:], body: Data(#"{"error":"no"}"#.utf8))
            }
            return AccountQuotaHTTPResponse(statusCode: 200, headers: [:], body: Data(usage.utf8))
        }
        let rejectedChips = try await AccountQuotaClient(transport: rejected).refresh(targets: [
            quotaTarget(id: "official", name: "OpenAI", kind: .officialNote, key: nil, accessToken: "official-token", accountID: "account-id"),
        ])
        #expect((rejectedChips.map(\.status)) == ([.windows(usageWindows)]))

        let mismatch = ScriptedQuotaTransport { request in
            let body = request.url?.path == "/backend-api/accounts/check/v4-2023-04-27" ? check : usage
            return AccountQuotaHTTPResponse(statusCode: 200, headers: [:], body: Data(body.utf8))
        }
        let mismatchChips = try await AccountQuotaClient(transport: mismatch).refresh(targets: [
            quotaTarget(id: "official", name: "OpenAI", kind: .officialNote, key: nil, accessToken: "official-token", accountID: "missing-account"),
        ])
        #expect((mismatchChips.map(\.status)) == ([.windows(usageWindows)]))
        #expect(!(AccountQuotaFormatting.plainSummary(for: mismatchChips[0], now: Date()).contains("总到期")))

        let renewsOnly = #"{"accounts":{"account-id":{"entitlement":{"renews_at":"2026-10-15T00:00:00Z"}}}}"#
        let renews = ScriptedQuotaTransport { request in
            let body = request.url?.path == "/backend-api/accounts/check/v4-2023-04-27" ? renewsOnly : usage
            return AccountQuotaHTTPResponse(statusCode: 200, headers: [:], body: Data(body.utf8))
        }
        let renewsChips = try await AccountQuotaClient(transport: renews).refresh(targets: [
            quotaTarget(id: "official", name: "OpenAI", kind: .officialNote, key: nil, accessToken: "official-token", accountID: "account-id"),
        ])
        #expect((renewsChips.map(\.status)) == ([.windows(usageWindows)]))

        let noAccount = ScriptedQuotaTransport { request in
            #expect((request.url?.path) == ("/backend-api/wham/usage"))
            #expect((request.value(forHTTPHeaderField: "ChatGPT-Account-ID")) == nil)
            return AccountQuotaHTTPResponse(statusCode: 200, headers: [:], body: Data(usage.utf8))
        }
        let noAccountChips = try await AccountQuotaClient(transport: noAccount).refresh(targets: [
            quotaTarget(id: "official", name: "OpenAI", kind: .officialNote, key: nil, accessToken: "official-token"),
        ])
        #expect((noAccount.requests.map { $0.url?.path }) == (["/backend-api/wham/usage"]))
        #expect((noAccountChips.map(\.status)) == ([.windows(usageWindows)]))
    }

    @Test
    func testOfficialCardShowsItsDeadlineFromTheDefaultAccountEntry() async throws {
        let usage = #"{"rate_limit":{"primary_window":{"used_percent":42,"limit_window_seconds":18000,"reset_at":1760000000},"secondary_window":{"used_percent":13,"limit_window_seconds":604800,"reset_at":1760500000}}}"#
        let check = #"{"accounts":{"default":{"entitlement":{"has_active_subscription":true,"expires_at":"2026-10-15T00:00:00Z","renews_at":"2026-10-15T00:00:00Z"}}},"last_account_id":"default"}"#
        let transport = ScriptedQuotaTransport { request in
            let body = request.url?.path == "/backend-api/accounts/check/v4-2023-04-27" ? check : usage
            return AccountQuotaHTTPResponse(statusCode: 200, headers: [:], body: Data(body.utf8))
        }
        let chips = try await AccountQuotaClient(transport: transport).refresh(targets: [
            quotaTarget(id: "official", name: "OpenAI", kind: .officialNote, key: nil, accessToken: "official-token", accountID: "account-id"),
        ])
        let card = try #require(chips.first)
        guard case let .windows(windows) = card.status else { return recordFailure("usage must succeed") }
        #expect((windows.map(\.name)) == (["five_hour", "weekly_limit", ParsedQuotaWindow.planExpiryName]))
        let now = Date(timeIntervalSince1970: 1_758_600_000)
        let summary = AccountQuotaFormatting.plainSummary(for: card, now: now)
        #expect(summary.contains("5h 58%"))
        #expect(summary.contains("7d 87%"))
        #expect(summary.contains("至10月15日"))
        #expect(AccountQuotaFormatting.help(for: card, now: now).contains("7d重置"))
    }

    @Test
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
        #expect((failed.map(\.status)) == ([.message(AccountQuotaMessage.queryFailed)]))
        #expect((failed.map(\.isCurrent)) == ([true]))

        let offline = ScriptedQuotaTransport { _ in
            throw URLError(.timedOut)
        }
        let offlineClient = AccountQuotaClient(transport: offline)
        let kept = try await offlineClient.refresh(
            targets: [quotaTarget(id: "kimi", name: "Kimi", kind: .kimi, key: "unit-test-key", current: true)],
            previous: [previous]
        )
        #expect((kept.map(\.status)) == ([previous.status]))
        #expect((kept.first?.isCurrent) == (true))
        #expect((kept.first?.isStale) == (true))
    }

    @Test
    func testMissingXAILoginDoesNotCallTheNetwork() async throws {
        let transport = ScriptedQuotaTransport { request in
            recordFailure("unexpected request \(request.url?.absoluteString ?? "")")
            return AccountQuotaHTTPResponse(statusCode: 500, headers: [:], body: Data())
        }
        let client = AccountQuotaClient(
            transport: transport,
            authFileURL: URL(fileURLWithPath: "/tmp/missing-xai-auth-\(UUID().uuidString).json")
        )
        let chips = try await client.refresh(targets: [
            quotaTarget(id: "xai", name: "xAI", kind: .xaiOAuth, key: nil),
        ])
        #expect((chips.map(\.status)) == ([
            .note(text: AccountQuotaMessage.notLoggedIn, help: AccountQuotaMessage.notLoggedInHelp),
        ]))
        #expect((AccountQuotaFormatting.runs(for: chips[0], now: Date()).map(\.tone)) == ([.secondary]))
        #expect(transport.requests.isEmpty)
    }

    @Test
    func testXAIKeepAliveForcesRefreshTokenRotationBeyondAccessTokenCache() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "xai-keep-alive-\(UUID().uuidString)", directoryHint: .isDirectory)
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
                    statusCode: 200,
                    headers: [:],
                    body: Data(#"{"access_token":"unit-test-access","expires_in":3600}"#.utf8)
                )
            case "https://grok.com/grok_api_v2.GrokBuildBilling/GetGrokCreditsConfig":
                return AccountQuotaHTTPResponse(statusCode: 200, headers: [:], body: Data())
            default:
                recordFailure("unexpected request \(request.url?.absoluteString ?? "")")
                return AccountQuotaHTTPResponse(statusCode: 500, headers: [:], body: Data())
            }
        }
        let client = AccountQuotaClient(transport: transport, authFileURL: authURL)
        let target = quotaTarget(id: "xai", name: "xAI", kind: .xaiOAuth, key: nil)

        _ = try await client.refresh(targets: [target], authFileURL: authURL)
        let outcome = try await client.keepAliveXAI(authFileURL: authURL)

        #expect((outcome) == (.renewed))
        #expect((transport.requests.filter { $0.url?.absoluteString == "https://auth.x.ai/oauth2/token" }.count) == 2)
        #expect((XAIOAuthKeepAlivePolicy.successInterval) == (6.5 * 24 * 60 * 60))
        #expect((XAIOAuthKeepAlivePolicy.failureRetryInterval) == (60 * 60))

        let scheduleURL = directory.appending(path: "keepalive-schedule.json")
        let scheduleStore = XAIOAuthKeepAliveScheduleStore(fileURL: scheduleURL)
        let next = Date().addingTimeInterval(XAIOAuthKeepAlivePolicy.successInterval)
        scheduleStore.save(accountID: "acct-1", nextAt: next)
        #expect(scheduleStore.nextDate(accountID: "acct-1").map { abs($0.timeIntervalSince(next)) < 1 } == true)
        #expect((scheduleStore.nextDate(accountID: "acct-2")) == (nil))
    }

    @Test
    func testZhipuUsesTheHostThatMatchesItsBaseURL() async throws {
        let baseURL = "https://open.bigmodel.cn/api/paas/v4"
        let transport = ScriptedQuotaTransport { request in
            #expect((request.value(forHTTPHeaderField: "Authorization")) == ("unit-test-key"))
            #expect((request.value(forHTTPHeaderField: "Accept-Language")) == ("en-US,en"))
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
                recordFailure("unexpected \(request.url?.absoluteString ?? "")")
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
        #expect((transport.requests.map { $0.url?.absoluteString }) == ([
                CCSwitchQuotaCatalog.zhipuQuotaURL(baseURL: baseURL).absoluteString,
                CCSwitchQuotaCatalog.zhipuSubscriptionURL(baseURL: baseURL).absoluteString,
            ]))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        #expect((chips.map(\.status)) == ([
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
                    resetsAt: formatter.date(from: "2026-10-03 00:00:00")
                ),
            ]),
        ]))
        let summary = AccountQuotaFormatting.plainSummary(
            for: chips[0],
            now: Date(timeIntervalSince1970: 1_791_010_800)
        )
        #expect(summary.hasPrefix("5h 100% · 7d 0%"))
        #expect(summary.contains("至10月3日"))
        #expect(!(summary.contains("10时")))
        #expect(!(summary.contains("总到期")))
        #expect(!(summary.contains("1mo")))
        #expect(!(summary.contains("unit-test-key")))
    }

    @Test
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
        #expect((unauthorizedChips.map(\.status)) == ([
            .windows([
                ParsedQuotaWindow(name: "five_hour", utilization: 12, resetsAt: nil),
                ParsedQuotaWindow(name: "weekly_limit", utilization: 34, resetsAt: nil),
            ]),
        ]))

        let offline = ScriptedQuotaTransport { request in
            if request.url?.path == "/api/biz/subscription/list" {
                throw URLError(.timedOut)
            }
            return AccountQuotaHTTPResponse(statusCode: 200, headers: [:], body: quota)
        }
        let offlineChips = try await AccountQuotaClient(transport: offline).refresh(targets: [
            quotaTarget(id: "zhipu", name: "智谱", kind: .zhipu, key: "unit-test-key"),
        ])
        #expect((offlineChips.map(\.status)) == (unauthorizedChips.map(\.status)))
        #expect((offline.requests.map { $0.url?.host }) == (["api.z.ai", "api.z.ai"]))
    }

    @Test
    func testZhipuDoesNotQuerySubscriptionWhenQuotaFails() async throws {
        let rejected = ScriptedQuotaTransport { request in
            #expect((request.url?.path) == ("/api/monitor/usage/quota/limit"))
            return AccountQuotaHTTPResponse(statusCode: 200, headers: [:], body: Data(#"{"success":false}"#.utf8))
        }
        let chips = try await AccountQuotaClient(transport: rejected).refresh(targets: [
            quotaTarget(id: "zhipu", name: "智谱", kind: .zhipu, key: "unit-test-key", baseURL: "https://open.bigmodel.cn/api/paas/v4"),
        ])
        #expect((chips.map(\.status)) == ([.message(AccountQuotaMessage.queryFailed)]))
        #expect((rejected.requests.count) == (1))

        let unauthorized = ScriptedQuotaTransport { request in
            return AccountQuotaHTTPResponse(statusCode: 401, headers: [:], body: Data("{}".utf8))
        }
        let failed = try await AccountQuotaClient(transport: unauthorized).refresh(targets: [
            quotaTarget(id: "zhipu", name: "智谱", kind: .zhipu, key: "unit-test-key"),
        ])
        #expect((failed.map(\.status)) == ([.message(AccountQuotaMessage.queryFailed)]))
        #expect((unauthorized.requests.count) == (1))
    }

    @Test
    func testOfficialWithoutALoginDoesNotCallTheNetworkOrRequireCodex() async throws {
        let missingCodexAuth = URL(fileURLWithPath: "/tmp/missing-codex-\(UUID().uuidString)/auth.json")
        let transport = ScriptedQuotaTransport { request in
            recordFailure("unexpected request \(request.url?.absoluteString ?? "")")
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
        #expect(chips.isEmpty)
        #expect(transport.requests.isEmpty)
        let rendered = chips.map {
            AccountQuotaFormatting.plainSummary(for: $0, now: Date())
                + AccountQuotaFormatting.help(for: $0, now: Date())
        }.joined()
        #expect(!(rendered.localizedCaseInsensitiveContains("codex")))
        #expect(!(rendered.contains("安装")))
        #expect(!(rendered.contains("查询失败")))
    }

    @Test
    func testMissingOrPlaceholderKeyDoesNotCallTheNetwork() async throws {
        let transport = ScriptedQuotaTransport { request in
            recordFailure("unexpected request \(request.url?.absoluteString ?? "")")
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
        #expect((chips.map(\.status)) == ([expected, expected, expected]))
        #expect(transport.requests.isEmpty)
        for chip in chips {
            #expect((AccountQuotaFormatting.runs(for: chip, now: Date()).map(\.tone)) == ([.secondary]))
        }
    }

    @Test
    func testRefreshAuthFileOverridesTheClientURL() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "xai-auth-override-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let reauthURL = directory.appending(path: "reauth.json")
        try Data(xaiAuthJSON(requiresReauth: true).utf8).write(to: reauthURL)
        let missingURL = directory.appending(path: "missing.json")

        let transport = ScriptedQuotaTransport { request in
            recordFailure("unexpected request \(request.url?.absoluteString ?? "")")
            return AccountQuotaHTTPResponse(statusCode: 500, headers: [:], body: Data())
        }
        let loggedOutClient = AccountQuotaClient(transport: transport, authFileURL: reauthURL)
        let loggedOut = try await loggedOutClient.refresh(
            targets: [quotaTarget(id: "xai", name: "xAI", kind: .xaiOAuth, key: nil)],
            authFileURL: missingURL
        )
        #expect((loggedOut.map(\.status)) == ([
            .note(text: AccountQuotaMessage.notLoggedIn, help: AccountQuotaMessage.notLoggedInHelp),
        ]))
        #expect((AccountQuotaFormatting.runs(for: loggedOut[0], now: Date()).map(\.tone)) == ([.secondary]))

        let reauthClient = AccountQuotaClient(transport: transport, authFileURL: missingURL)
        let reauth = try await reauthClient.refresh(
            targets: [quotaTarget(id: "xai", name: "xAI", kind: .xaiOAuth, key: nil)],
            authFileURL: reauthURL
        )
        #expect((reauth.map(\.status)) == ([.message(AccountQuotaMessage.reauthRequired)]))
        #expect((AccountQuotaFormatting.runs(for: reauth[0], now: Date()).map(\.tone)) == ([.orange]))
        #expect(transport.requests.isEmpty)
    }

    @Test
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
                recordFailure("unexpected request \(request.url?.absoluteString ?? "")")
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
        #expect((chips.map(\.status)) == ([.message(AccountQuotaMessage.reauthRequired)]))
        #expect((AccountQuotaFormatting.runs(for: chips[0], now: Date()).map(\.tone)) == ([.orange]))
        #expect(!(transport.requests.contains { $0.url?.host == "grok.com" }))
    }

    /// CC Switch owns the Grok login, so a login-required chip sends the user
    /// there. The stored provider website is a product page with no sign-in.
    @Test
    func testXaiSignInChipsPointAtCCSwitchInsteadOfTheWebsite() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let reauth = chip(kind: .xaiOAuth, status: .message(AccountQuotaMessage.reauthRequired))
        let loggedOut = chip(
            kind: .xaiOAuth,
            status: .note(text: AccountQuotaMessage.notLoggedIn, help: AccountQuotaMessage.notLoggedInHelp)
        )
        let signedIn = chip(
            kind: .xaiOAuth,
            status: .windows([ParsedQuotaWindow(name: "weekly_limit", utilization: 20, resetsAt: nil)])
        )
        let openAIReauth = chip(kind: .officialNote, status: .message(AccountQuotaMessage.reauthRequired))

        #expect(AccountQuotaFormatting.requiresCCSwitchSignIn(reauth))
        #expect(AccountQuotaFormatting.requiresCCSwitchSignIn(loggedOut))
        #expect(!(AccountQuotaFormatting.requiresCCSwitchSignIn(signedIn)))
        #expect(!(AccountQuotaFormatting.requiresCCSwitchSignIn(openAIReauth)))

        let reauthHelp = AccountQuotaFormatting.help(for: reauth, now: now)
        #expect(reauthHelp.contains("需要重新登录"))
        #expect(reauthHelp.contains(AccountQuotaMessage.xaiSignInHelp))
        #expect(!(reauthHelp.contains("https://example.com")))
        #expect(AccountQuotaFormatting.help(for: loggedOut, now: now).contains(AccountQuotaMessage.xaiSignInHelp))
        // A working xAI chip and every other provider keep their website line.
        #expect(AccountQuotaFormatting.help(for: signedIn, now: now).contains("https://example.com"))
        #expect(AccountQuotaFormatting.help(for: openAIReauth, now: now).contains("https://example.com"))
    }

    @Test
    func testQwenWithoutOfficialQuotaAsksToConnectAndDoesNotQueryItsKey() async throws {
        let client = AccountQuotaClient(
            transport: ScriptedQuotaTransport { request in
                recordFailure("unexpected request \(request.url?.absoluteString ?? "")")
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
        #expect((chips.first?.status) == (.note(
                text: AccountQuotaMessage.connectOfficial,
                help: AccountQuotaMessage.connectOfficialHelp
            )))
    }

    @Test
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
        #expect((chips.first?.status) == (.qwenPlan(QwenPlanQuota(
                usedPercent: 28,
                remainingCredits: 18_000,
                totalCredits: 25_000,
                resetsAt: nil
            ))))
    }
}

struct CCSwitchProviderStoreTests {
    @Test
    func testMissingOrUnusableDatabaseIsAbsent() throws {
        let missing = FileManager.default.temporaryDirectory
            .appending(path: "missing-cc-switch-\(UUID().uuidString).db")
        #expect((CCSwitchProviderStore.loadCodexProviders(databaseURL: missing)) == (.absent))

        let directory = FileManager.default.temporaryDirectory
            .appending(path: "not-a-db-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect((CCSwitchProviderStore.loadCodexProviders(databaseURL: directory)) == (.absent))

        let textFile = directory.appending(path: "notes.db")
        try Data("not a database".utf8).write(to: textFile)
        #expect((CCSwitchProviderStore.loadCodexProviders(databaseURL: textFile)) == (.absent))

        let fakeSQLite = directory.appending(path: "fake.db")
        var header = Data("SQLite format 3\0".utf8)
        header.append(Data(repeating: 0, count: 64))
        try header.write(to: fakeSQLite)
        #expect((CCSwitchProviderStore.loadCodexProviders(databaseURL: fakeSQLite)) == (.absent))

        let otherTable = directory.appending(path: "other.db")
        try Data().write(to: otherTable)
        try runSQLite("CREATE TABLE notes (id TEXT);", database: otherTable)
        #expect((CCSwitchProviderStore.loadCodexProviders(databaseURL: otherTable)) == (.absent))

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
        #expect((CCSwitchProviderStore.loadCodexProviders(databaseURL: missingColumn)) == (.absent))

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
        #expect((CCSwitchProviderStore.loadCodexProviders(databaseURL: noCodex)) == (.records([])))
    }

    #if os(Windows)
    @Test(.disabled("POSIX permission modes do not apply to Windows; file sharing is tested separately"))
    #else
    @Test
    #endif
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
        #expect((CCSwitchProviderStore.loadCodexProviders(databaseURL: url)) == (.unavailable))
    }

    @Test
    func testLoadsOnlyCodexRowsAndTheSelectedProviderID() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "cc-switch-store-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appending(path: "cc-switch.db")
        let settingsURL = directory.appending(path: "settings.json")
        try Data(#"{"currentProviderCodex":" xai ","currentProviderClaude":"ignored"}"#.utf8)
            .write(to: settingsURL)
        #expect((CCSwitchProviderStore.currentCodexProviderID(settingsURL: settingsURL)) == ("xai"))
        #expect((CCSwitchProviderStore.currentCodexProviderID(settingsURL: directory.appending(path: "missing.json"))) == nil)

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
            return recordFailure("expected records, got \(loaded)")
        }
        let targets = CCSwitchQuotaCatalog.targets(
            from: records,
            currentProviderID: CCSwitchProviderStore.currentCodexProviderID(settingsURL: settingsURL)
        )
        #expect((targets.map(\.id)) == (["kimi", "xai"]))
        #expect((targets.map(\.isCurrent)) == ([false, true]))
        #expect((targets[0].apiKey) == ("unit-test-key"))
        #expect((targets[1].apiKey) == nil)
        #expect((targets[1].websiteURL) == nil)
    }

    @Test
    func testInvalidSettingsAreIgnoredAndTheDatabaseFlagRemainsCurrent() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "cc-switch-settings-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let settingsURL = directory.appending(path: "settings.json")

        try Data("not-json".utf8).write(to: settingsURL)
        #expect((CCSwitchProviderStore.currentCodexProviderID(settingsURL: settingsURL)) == nil)
        try Data(#"{"currentProviderCodex":" "}"#.utf8).write(to: settingsURL)
        #expect((CCSwitchProviderStore.currentCodexProviderID(settingsURL: settingsURL)) == nil)
        try Data(#"{"currentProviderCodex":1}"#.utf8).write(to: settingsURL)
        #expect((CCSwitchProviderStore.currentCodexProviderID(settingsURL: settingsURL)) == nil)
        try Data(#"["xai"]"#.utf8).write(to: settingsURL)
        #expect((CCSwitchProviderStore.currentCodexProviderID(settingsURL: settingsURL)) == nil)

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
        #expect((targets.map(\.id)) == (["kimi"]))
        #expect(targets[0].isCurrent)
    }

    @Test
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

        #expect((pathKey(try resolved().root)) == (pathKey(fallback)))
        #expect((pathKey(try resolved(writing: "{}").root)) == (pathKey(fallback)))
        #expect((pathKey(try resolved(writing: "not-json").root)) == (pathKey(fallback)))
        #expect((pathKey(try resolved(writing: #"{"app_config_dir_override":" "}"#).root)) == (pathKey(fallback)))
        #expect((pathKey(try resolved(writing: #"{"app_config_dir_override":12}"#).root)) == (pathKey(fallback)))
        #expect((pathKey(try resolved(writing: #"{"app_config_dir_override":["/tmp"]}"#).root)) == (pathKey(fallback)))
        let missingOverride = root.appending(path: "missing-override", directoryHint: .isDirectory)
        #expect((pathKey(try resolved(writing: #"{"app_config_dir_override":"\#(missingOverride.path(percentEncoded: false))"}"#).root)) == (pathKey(fallback)))
        #expect((pathKey(try resolved(writing: #"{"app_config_dir_override":"~/does-not-exist"}"#).root)) == (pathKey(fallback)))

        let custom = root.appending(path: "custom-switch", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: custom, withIntermediateDirectories: true)
        let overridden = try resolved(
            writing: #"{"app_config_dir_override":"\#(custom.path(percentEncoded: false))"}"#
        )
        #expect((pathKey(overridden.root)) == (pathKey(custom)))
        #expect((pathKey(overridden.databaseURL)) == (pathKey(custom.appending(path: "cc-switch.db"))))
        #expect((pathKey(overridden.settingsURL)) == (pathKey(custom.appending(path: "settings.json"))))
        #expect((pathKey(overridden.xaiAuthURL)) == (pathKey(custom.appending(path: "xai_oauth_auth.json"))))
        #expect(!(FileManager.default.fileExists(atPath: overridden.databaseURL.path(percentEncoded: false))))

        let tildeTarget = home.appending(path: "tilde-switch", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tildeTarget, withIntermediateDirectories: true)
        #expect((pathKey(try resolved(writing: #"{"app_config_dir_override":"~/tilde-switch"}"#).root)) == (pathKey(tildeTarget)))
        #expect((pathKey(try resolved(writing: #"{"app_config_dir_override":"~"}"#).root)) == (pathKey(home)))

        let windowsName = "win\\switch"
        let windowsTarget = home.appending(path: windowsName, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: windowsTarget, withIntermediateDirectories: true)
        #expect((pathKey(try resolved(writing: #"{"app_config_dir_override":"~\\win\\switch"}"#).root)) == (pathKey(windowsTarget)))
    }
}

struct XaiEndpointValidatorTests {
    @Test
    func testAcceptsOnlyTheXAIAuthHost() {
        #expect((XaiEndpointValidator.trustedTokenEndpoint("https://auth.x.ai/oauth2/token")?.absoluteString) == ("https://auth.x.ai/oauth2/token"))
        #expect((XaiEndpointValidator.trustedTokenEndpoint("http://auth.x.ai/oauth2/token")) == nil)
        #expect((XaiEndpointValidator.trustedTokenEndpoint("https://evil.example/oauth2/token")) == nil)
        #expect((XaiEndpointValidator.trustedTokenEndpoint("https://auth.x.ai.evil/oauth2/token")) == nil)
        #expect((XaiEndpointValidator.trustedTokenEndpoint("https://user:pass@auth.x.ai/oauth2/token")) == nil)
        #expect((XaiEndpointValidator.trustedTokenEndpoint("https://auth.x.ai:8443/oauth2/token")) == nil)
        #expect(XaiEndpointValidator.isTrustedIssuer("https://auth.x.ai/"))
        #expect(!(XaiEndpointValidator.isTrustedIssuer("https://auth.x.ai.evil")))
    }

    @Test
    func testClassifiesGrokFailuresWithoutReadingABody() {
        #expect((GrokBillingParser.classify(httpStatus: 401, grpcStatus: nil)) == (.reauth))
        #expect((GrokBillingParser.classify(httpStatus: 429, grpcStatus: nil)) == (.transient))
        #expect((GrokBillingParser.classify(httpStatus: 200, grpcStatus: 16)) == (.reauth))
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
        case .minimax: "minimax"
        case .stepfun: "stepfun"
        case .blackForestLabs: "bfl"
        case .luma: "luma"
        case .claude: "claude"
        case .gemini: "gemini"
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
    var connection: OpaquePointer?
    guard sqlite3_open(database.path(percentEncoded: false), &connection) == SQLITE_OK,
          let connection else { throw CocoaError(.fileWriteUnknown) }
    defer { sqlite3_close(connection) }
    var error: UnsafeMutablePointer<CChar>?
    let result = sqlite3_exec(connection, sql, nil, nil, &error)
    defer { sqlite3_free(error) }
    guard result == SQLITE_OK else {
        recordFailure("sqlite3 fixture failed: \(error.map { String(cString: $0) } ?? "unknown error")")
        throw CocoaError(.fileWriteUnknown)
    }
}
