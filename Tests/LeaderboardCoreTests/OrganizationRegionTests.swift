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
