import Foundation
import LeaderboardCore
import Testing

struct PurchaseLinkCatalogTests {
    @Test
    func testPurchaseLinksChooseSiteFromInterfaceLanguage() {
        let pairedOrganizations = [
            "Alibaba", "Z.ai", "Tencent", "MiniMax", "KlingAI", "ByteDance Seed", "Xiaomi"
        ]
        for organization in pairedOrganizations {
            let links = PurchaseLinkCatalog.links(forOrganization: organization)
            for choices in [links.codingPlan, links.payAsYouGo] {
                #expect((PurchaseLinkCatalog.preferredLink(from: choices, language: .chinese)?.site) == (.mainlandChina), Comment(rawValue: organization))
                #expect((PurchaseLinkCatalog.preferredLink(from: choices, language: .english)?.site) == (.international), Comment(rawValue: organization))
                #expect((PurchaseLinkCatalog.preferredLink(from: choices, language: .traditionalChinese)?.site) == (.international), Comment(rawValue: organization))
            }
        }
        let tencent = PurchaseLinkCatalog.links(forOrganization: "Tencent")
        #expect((PurchaseLinkCatalog.preferredLink(from: tencent.codingPlan, language: .chinese)?.url.absoluteString) == ("https://console.cloud.tencent.com/tokenhub/tokenplan/hy"))
    }

    @Test
    func testChineseDomainAndSingleSiteFallback() {
        let chinese = PurchaseLink(label: "CN", url: URL(string: "https://example.cn/pricing")!)
        let global = PurchaseLink(label: "Global", url: URL(string: "https://example.com/pricing")!)
        #expect((PurchaseLinkCatalog.preferredLink(from: [global, chinese], language: .chinese)) == (chinese))
        #expect((PurchaseLinkCatalog.preferredLink(from: [global, chinese], language: .english)) == (global))
        #expect((PurchaseLinkCatalog.preferredLink(from: [chinese], language: .traditionalChinese)) == (chinese))
        #expect((PurchaseLinkCatalog.preferredLink(from: [], language: .english)) == nil)
    }

    @Test
    func testAliasesShareOfficialLinks() {
        let xAI = PurchaseLinkCatalog.links(forOrganization: "xAI")
        let spaceX = PurchaseLinkCatalog.links(forOrganization: "SpaceXAI")
        #expect((xAI) == (spaceX))
        #expect((xAI.codingPlan.map(\.url.absoluteString)) == (["https://grok.com/plans"]))
        #expect(!(xAI.payAsYouGo.isEmpty))

        let moonshotAI = PurchaseLinkCatalog.links(forOrganization: "Moonshot AI")
        let kimi = PurchaseLinkCatalog.links(forOrganization: "Kimi")
        #expect((moonshotAI) == (kimi))
        #expect(!(moonshotAI.codingPlan.isEmpty))

        let happyHorse = PurchaseLinkCatalog.links(forOrganization: "Alibaba-ATH")
        let alibaba = PurchaseLinkCatalog.links(forOrganization: "Alibaba")
        #expect((happyHorse) == (alibaba))

        let seed = PurchaseLinkCatalog.links(forOrganization: "ByteDance Seed")
        let bytedance = PurchaseLinkCatalog.links(forOrganization: "Bytedance")
        #expect((seed) == (bytedance))
        #expect((seed.codingPlan.map(\.url.absoluteString)) == ([
                "https://jimeng.jianying.com/ai-tool/home",
                "https://dreamina.capcut.com/pricing/dreamina-price"
            ]))

        let lumaLabs = PurchaseLinkCatalog.links(forOrganization: "Luma Labs")
        let lumaAI = PurchaseLinkCatalog.links(forOrganization: "Luma AI")
        #expect((lumaLabs) == (lumaAI))
        #expect(!(lumaLabs.codingPlan.isEmpty))
        #expect(!(lumaLabs.payAsYouGo.isEmpty))
    }

    @Test
    func testDevinFallsBackToModelNameWhenOrganizationIsMissing() {
        let links = PurchaseLinkCatalog.links(
            forOrganization: nil,
            modelName: "Devin Fusion CLI - Claude Fable 5.1 XHigh + SWE-2 Medium"
        )
        #expect((links.codingPlan.map(\.url.absoluteString)) == (["https://devin.ai/pricing"]))
        #expect((links.payAsYouGo.map(\.url.absoluteString)) == (["https://app.devin.ai/settings/plans"]))

        let unrelated = PurchaseLinkCatalog.links(forOrganization: nil, modelName: "Some Other Model")
        #expect(unrelated.isEmpty)
    }

    @Test
    func testVendorsWithoutAnOfficialPlanOnlyExposePayAsYouGo() {
        let payAsYouGoOnly = ["Black Forest Labs", "Fal", "Opencode", "Microsoft AI", "DeepSeek"]
        for organization in payAsYouGoOnly {
            let links = PurchaseLinkCatalog.links(forOrganization: organization)
            #expect(links.codingPlan.isEmpty, Comment(rawValue: organization))
            #expect(!(links.payAsYouGo.isEmpty), Comment(rawValue: organization))
        }
    }

    @Test
    func testDiscontinuedOrUnconfirmedVendorsStayEmpty() {
        #expect(PurchaseLinkCatalog.links(forOrganization: "Reve").isEmpty)
        #expect(PurchaseLinkCatalog.links(forOrganization: "Video Rebirth").isEmpty)
    }

    @Test
    func testCachedLeaderboardOrganizationsAreCovered() {
        let covered = [
            "Google", "OpenAI", "Anthropic", "Alibaba", "Meta", "Microsoft AI", "SpaceXAI",
            "KlingAI", "Z.ai", "ByteDance Seed", "Bytedance", "MiniMax", "Moonshot", "PixVerse",
            "Xiaomi", "Z AI", "xAI", "Alibaba-ATH", "Black Forest Labs", "DeepSeek", "Fal",
            "Ideogram", "Kimi", "Krea", "Luma AI", "Luma Labs", "Moonshot AI", "Opencode",
            "Runway", "StepFun", "Tencent"
        ]
        for organization in covered {
            #expect(!(PurchaseLinkCatalog.links(forOrganization: organization).isEmpty), Comment(rawValue: organization))
        }
    }

    @Test
    func testPurchaseURLsHaveNoWhitespace() {
        let organizations = [
            "Anthropic", "OpenAI", "Alibaba", "Z.ai", "Meta", "SpaceXAI", "StepFun", "Kimi",
            "Google", "DeepSeek", "Tencent", "MiniMax", "KlingAI", "ByteDance Seed", "Xiaomi",
            "Krea", "Ideogram", "Runway", "Luma Labs", "Black Forest Labs", "Fal", "PixVerse",
            "Opencode", "Microsoft AI", "xAI", "Moonshot AI"
        ]
        for organization in organizations {
            let links = PurchaseLinkCatalog.links(forOrganization: organization)
            for link in links.codingPlan + links.payAsYouGo {
                #expect((link.url.absoluteString.rangeOfCharacter(from: .whitespacesAndNewlines)) == nil)
                #expect((link.url.scheme) == ("https"))
            }
        }
    }

    @Test
    func testChineseBadgeIncludesNewlyLinkedDomesticVendors() {
        #expect(OrganizationRegion.isChinese("Xiaomi"))
        #expect(OrganizationRegion.isChinese("ByteDance Seed"))
        #expect(OrganizationRegion.isChinese("Bytedance"))
        #expect(OrganizationRegion.isChinese("KlingAI"))
        #expect(OrganizationRegion.isChinese("Alibaba-ATH"))
        #expect(OrganizationRegion.isChinese("Moonshot AI"))
        #expect(OrganizationRegion.isChinese("Z.ai"))
        #expect(OrganizationRegion.isChinese("Z AI"))
        #expect(!(OrganizationRegion.isChinese("Fal")))
        #expect(!(OrganizationRegion.isChinese("Video Rebirth")))
        #expect(!(OrganizationRegion.isChinese("Opencode")))
    }

    @Test
    func testChineseBadgeFollowsHostedModelWhenOrganizationIsTheHarness() {
        #expect(OrganizationRegion.isChinese("Opencode", modelName: "Opencode - GLM-5.3"))
        #expect(OrganizationRegion.isChinese(
                "Anthropic",
                modelName: "Claude Code - Qwen3.8 Max"
            ))
        #expect(OrganizationRegion.isChinese(
                "OpenAI",
                modelName: "Codex - DeepSeek V4 Pro 0813 (max)"
            ))
        #expect(!(OrganizationRegion.isChinese(
                "Opencode",
                modelName: "Opencode - GPT-6 Astra (max)"
            )))
        #expect(!(OrganizationRegion.isChinese(
                "Anthropic",
                modelName: "Claude Code - Fable 5.1 (max)"
            )))
        #expect(!(OrganizationRegion.isChinese(nil, modelName: "Some Other Model")))
    }
}
