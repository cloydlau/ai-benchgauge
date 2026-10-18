import Foundation
import LeaderboardCore
import Testing

struct OrganizationRegionTests {
    @Test
    func testCountryLabelsCoverEveryBundledOrganization() {
        let examples: [(String, OrganizationCountry)] = [
            ("Alibaba", .china), ("Z.ai", .china), ("StepFun", .china),
            ("Moonshot AI", .china), ("DeepSeek", .china), ("Tencent", .china),
            ("MiniMax", .china), ("ByteDance Seed", .china), ("Xiaomi", .china),
            ("KlingAI", .china),
            ("Anthropic", .unitedStates), ("OpenAI", .unitedStates),
            ("xAI", .unitedStates), ("Google", .unitedStates),
            ("Meta", .unitedStates), ("Nvidia", .unitedStates),
            ("Microsoft AI", .unitedStates), ("Krea", .unitedStates),
            ("Runway", .unitedStates), ("Luma Labs", .unitedStates),
            ("Fal", .unitedStates), ("Opencode", .unitedStates),
            ("Devin", .unitedStates), ("Reve", .unitedStates),
            ("Thinking Machines", .unitedStates), ("GitHub", .unitedStates),
            ("Ideogram", .canada), ("Mistral", .france),
            ("Black Forest Labs", .germany), ("PixVerse", .singapore),
            ("Video Rebirth", .singapore),
        ]
        for (organization, expected) in examples {
            #expect((OrganizationRegion.country(organization)) == (expected), Comment(rawValue: organization))
        }
        #expect((OrganizationRegion.country("Unlisted Organization")) == nil)
    }

    @Test
    func testCodingHarnessUsesLeadModelDeveloper() {
        #expect((OrganizationRegion.country("OpenAI", modelName: "Codex - DeepSeek V4 Pro")) == (.china))
        #expect((OrganizationRegion.country("Opencode", modelName: "Opencode - GPT-6 Astra")) == (.unitedStates))
        #expect((OrganizationRegion.country(nil, modelName: "Devin Fusion - Claude Opus + Qwen3")) == (.unitedStates))
    }

    @Test
    func cachedDisplayNamesResolveByExactID() {
        let entry = LeaderboardEntry(rank: 1, name: "Yi Lightning", score: 80, modelID: "YI-LIGHTNING",
            developerCountry: OrganizationCountryMetadata(key: "", countryCode: nil))
        #expect(OrganizationRegion.country(for: entry) == .china)
        #expect(OrganizationRegion.country(nil, modelName: "Yi Lightning", modelID: "yi-lightning-finetune") == nil)
        #expect(OrganizationRegion.country("Other Maker", modelName: "Yi Lightning", modelID: "yi-lightning") == nil)
        #expect(OrganizationRegion.country(nil, modelName: "Trinity Large Preview", modelID: "trinity-large") == .unitedStates)
        #expect(OrganizationRegion.country(nil, modelName: "OpenChat 3.5", modelID: "openchat-3.5") == nil)
    }

    @Test
    func verifiedPublicWeightsFillOnlyExactMissingMetadata() {
        let entry = LeaderboardEntry(rank: 1, name: "InternLM2.5 20B Chat", score: 80, modelID: "internlm2_5-20b-chat")
        #expect(entry.openness == nil)
        #expect(entry.resolvedOpenness == .open)
        #expect(LeaderboardOpennessFilter.open.matches(entry))
        #expect(!LeaderboardOpennessFilter.unknown.matches(entry))
        let variant = LeaderboardEntry(rank: 1, name: entry.name, score: 80, modelID: "internlm2_5-20b-chat-custom")
        #expect(variant.resolvedOpenness == nil)
    }

    @Test
    func testCountryFlagsAndSystemLocalizedNames() {
        #expect((OrganizationCountry.china.flagEmoji) == ("🇨🇳"))
        #expect((OrganizationCountry.unitedStates.flagEmoji) == ("🇺🇸"))
        #expect((OrganizationCountry.canada.flagEmoji) == ("🇨🇦"))
        #expect((OrganizationCountry.france.flagEmoji) == ("🇫🇷"))
        #expect((OrganizationCountry.germany.flagEmoji) == ("🇩🇪"))
        #expect((OrganizationCountry.singapore.flagEmoji) == ("🇸🇬"))
        #expect((OrganizationCountry.unitedStates.localizedName(language: .english)) == ("United States"))
        #expect(OrganizationCountry.china.localizedName(language: .chinese) == "中国")
        #expect(OrganizationCountry.china.localizedName(language: .traditionalChinese) == "中國")
        #expect(OrganizationCountry.china.localizedName(language: .english) == "China")
    }
}
