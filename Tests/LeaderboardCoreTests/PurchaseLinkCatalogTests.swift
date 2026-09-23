import Foundation
import LeaderboardCore
import XCTest

final class PurchaseLinkCatalogTests: XCTestCase {
    func testPurchaseLinksChooseSiteFromInterfaceLanguage() {
        let pairedOrganizations = [
            "Alibaba", "Z.ai", "Tencent", "MiniMax", "KlingAI", "ByteDance Seed", "Xiaomi"
        ]
        for organization in pairedOrganizations {
            let links = PurchaseLinkCatalog.links(forOrganization: organization)
            for choices in [links.codingPlan, links.payAsYouGo] {
                XCTAssertEqual(
                    PurchaseLinkCatalog.preferredLink(from: choices, language: .chinese)?.site,
                    .mainlandChina,
                    organization
                )
                XCTAssertEqual(
                    PurchaseLinkCatalog.preferredLink(from: choices, language: .english)?.site,
                    .international,
                    organization
                )
                XCTAssertEqual(
                    PurchaseLinkCatalog.preferredLink(from: choices, language: .traditionalChinese)?.site,
                    .international,
                    organization
                )
            }
        }
        let tencent = PurchaseLinkCatalog.links(forOrganization: "Tencent")
        XCTAssertEqual(
            PurchaseLinkCatalog.preferredLink(from: tencent.codingPlan, language: .chinese)?.url.absoluteString,
            "https://console.cloud.tencent.com/tokenhub/tokenplan/hy"
        )
    }

    func testChineseDomainAndSingleSiteFallback() {
        let chinese = PurchaseLink(label: "CN", url: URL(string: "https://example.cn/pricing")!)
        let global = PurchaseLink(label: "Global", url: URL(string: "https://example.com/pricing")!)
        XCTAssertEqual(PurchaseLinkCatalog.preferredLink(from: [global, chinese], language: .chinese), chinese)
        XCTAssertEqual(PurchaseLinkCatalog.preferredLink(from: [global, chinese], language: .english), global)
        XCTAssertEqual(PurchaseLinkCatalog.preferredLink(from: [chinese], language: .traditionalChinese), chinese)
        XCTAssertNil(PurchaseLinkCatalog.preferredLink(from: [], language: .english))
    }

    func testAliasesShareOfficialLinks() {
        let xAI = PurchaseLinkCatalog.links(forOrganization: "xAI")
        let spaceX = PurchaseLinkCatalog.links(forOrganization: "SpaceXAI")
        XCTAssertEqual(xAI, spaceX)
        XCTAssertEqual(xAI.codingPlan.map(\.url.absoluteString), ["https://grok.com/plans"])
        XCTAssertFalse(xAI.payAsYouGo.isEmpty)

        let moonshotAI = PurchaseLinkCatalog.links(forOrganization: "Moonshot AI")
        let kimi = PurchaseLinkCatalog.links(forOrganization: "Kimi")
        XCTAssertEqual(moonshotAI, kimi)
        XCTAssertFalse(moonshotAI.codingPlan.isEmpty)

        let happyHorse = PurchaseLinkCatalog.links(forOrganization: "Alibaba-ATH")
        let alibaba = PurchaseLinkCatalog.links(forOrganization: "Alibaba")
        XCTAssertEqual(happyHorse, alibaba)

        let seed = PurchaseLinkCatalog.links(forOrganization: "ByteDance Seed")
        let bytedance = PurchaseLinkCatalog.links(forOrganization: "Bytedance")
        XCTAssertEqual(seed, bytedance)
        XCTAssertEqual(
            seed.codingPlan.map(\.url.absoluteString),
            [
                "https://jimeng.jianying.com/ai-tool/home",
                "https://dreamina.capcut.com/pricing/dreamina-price"
            ]
        )

        let lumaLabs = PurchaseLinkCatalog.links(forOrganization: "Luma Labs")
        let lumaAI = PurchaseLinkCatalog.links(forOrganization: "Luma AI")
        XCTAssertEqual(lumaLabs, lumaAI)
        XCTAssertFalse(lumaLabs.codingPlan.isEmpty)
        XCTAssertFalse(lumaLabs.payAsYouGo.isEmpty)
    }

    func testDevinFallsBackToModelNameWhenOrganizationIsMissing() {
        let links = PurchaseLinkCatalog.links(
            forOrganization: nil,
            modelName: "Devin Fusion CLI - Claude Fable 5.1 XHigh + SWE-2 Medium"
        )
        XCTAssertEqual(links.codingPlan.map(\.url.absoluteString), ["https://devin.ai/pricing"])
        XCTAssertEqual(links.payAsYouGo.map(\.url.absoluteString), ["https://app.devin.ai/settings/plans"])

        let unrelated = PurchaseLinkCatalog.links(forOrganization: nil, modelName: "Some Other Model")
        XCTAssertTrue(unrelated.isEmpty)
    }

    func testVendorsWithoutAnOfficialPlanOnlyExposePayAsYouGo() {
        let payAsYouGoOnly = ["Black Forest Labs", "Fal", "Opencode", "Microsoft AI", "DeepSeek"]
        for organization in payAsYouGoOnly {
            let links = PurchaseLinkCatalog.links(forOrganization: organization)
            XCTAssertTrue(links.codingPlan.isEmpty, organization)
            XCTAssertFalse(links.payAsYouGo.isEmpty, organization)
        }
    }

    func testDiscontinuedOrUnconfirmedVendorsStayEmpty() {
        XCTAssertTrue(PurchaseLinkCatalog.links(forOrganization: "Reve").isEmpty)
        XCTAssertTrue(PurchaseLinkCatalog.links(forOrganization: "Video Rebirth").isEmpty)
    }

    func testCachedLeaderboardOrganizationsAreCovered() {
        let covered = [
            "Google", "OpenAI", "Anthropic", "Alibaba", "Meta", "Microsoft AI", "SpaceXAI",
            "KlingAI", "Z.ai", "ByteDance Seed", "Bytedance", "MiniMax", "Moonshot", "PixVerse",
            "Xiaomi", "Z AI", "xAI", "Alibaba-ATH", "Black Forest Labs", "DeepSeek", "Fal",
            "Ideogram", "Kimi", "Krea", "Luma AI", "Luma Labs", "Moonshot AI", "Opencode",
            "Runway", "StepFun", "Tencent"
        ]
        for organization in covered {
            XCTAssertFalse(
                PurchaseLinkCatalog.links(forOrganization: organization).isEmpty,
                organization
            )
        }
    }

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
                XCTAssertNil(link.url.absoluteString.rangeOfCharacter(from: .whitespacesAndNewlines))
                XCTAssertEqual(link.url.scheme, "https")
            }
        }
    }

    func testChineseBadgeIncludesNewlyLinkedDomesticVendors() {
        XCTAssertTrue(OrganizationRegion.isChinese("Xiaomi"))
        XCTAssertTrue(OrganizationRegion.isChinese("ByteDance Seed"))
        XCTAssertTrue(OrganizationRegion.isChinese("Bytedance"))
        XCTAssertTrue(OrganizationRegion.isChinese("KlingAI"))
        XCTAssertTrue(OrganizationRegion.isChinese("Alibaba-ATH"))
        XCTAssertTrue(OrganizationRegion.isChinese("Moonshot AI"))
        XCTAssertTrue(OrganizationRegion.isChinese("Z.ai"))
        XCTAssertTrue(OrganizationRegion.isChinese("Z AI"))
        XCTAssertFalse(OrganizationRegion.isChinese("Fal"))
        XCTAssertFalse(OrganizationRegion.isChinese("Video Rebirth"))
        XCTAssertFalse(OrganizationRegion.isChinese("Opencode"))
    }

    func testChineseBadgeFollowsHostedModelWhenOrganizationIsTheHarness() {
        XCTAssertTrue(
            OrganizationRegion.isChinese("Opencode", modelName: "Opencode - GLM-5.3")
        )
        XCTAssertTrue(
            OrganizationRegion.isChinese(
                "Anthropic",
                modelName: "Claude Code - Qwen3.8 Max"
            )
        )
        XCTAssertTrue(
            OrganizationRegion.isChinese(
                "OpenAI",
                modelName: "Codex - DeepSeek V4 Pro 0813 (max)"
            )
        )
        XCTAssertFalse(
            OrganizationRegion.isChinese(
                "Opencode",
                modelName: "Opencode - GPT-6 Astra (max)"
            )
        )
        XCTAssertFalse(
            OrganizationRegion.isChinese(
                "Anthropic",
                modelName: "Claude Code - Fable 5.1 (max)"
            )
        )
        XCTAssertFalse(OrganizationRegion.isChinese(nil, modelName: "Some Other Model"))
    }
}
