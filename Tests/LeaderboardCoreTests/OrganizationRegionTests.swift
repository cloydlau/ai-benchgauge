import LeaderboardCore
import XCTest

final class OrganizationRegionTests: XCTestCase {
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
            XCTAssertEqual(OrganizationRegion.country(organization), expected, organization)
        }
        XCTAssertNil(OrganizationRegion.country("Unlisted Organization"))
    }

    func testCodingHarnessUsesLeadModelDeveloper() {
        XCTAssertEqual(
            OrganizationRegion.country("OpenAI", modelName: "Codex - DeepSeek V4 Pro"),
            .china
        )
        XCTAssertEqual(
            OrganizationRegion.country("Opencode", modelName: "Opencode - GPT-6 Astra"),
            .unitedStates
        )
        XCTAssertEqual(
            OrganizationRegion.country(nil, modelName: "Devin Fusion - Claude Opus + Qwen3"),
            .unitedStates
        )
    }

    func testCountryFlagsAndSystemLocalizedNames() {
        XCTAssertEqual(OrganizationCountry.china.flagEmoji, "🇨🇳")
        XCTAssertEqual(OrganizationCountry.unitedStates.flagEmoji, "🇺🇸")
        XCTAssertEqual(OrganizationCountry.canada.flagEmoji, "🇨🇦")
        XCTAssertEqual(OrganizationCountry.france.flagEmoji, "🇫🇷")
        XCTAssertEqual(OrganizationCountry.germany.flagEmoji, "🇩🇪")
        XCTAssertEqual(OrganizationCountry.singapore.flagEmoji, "🇸🇬")
        XCTAssertEqual(OrganizationCountry.unitedStates.localizedName(language: .english), "United States")
    }
}
