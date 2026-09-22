import LeaderboardCore
import XCTest

final class OrganizationLogoCatalogTests: XCTestCase {
    func testAliasesShareLogoAndColor() {
        let groups: [[String]] = [
            ["Moonshot", "Moonshot AI", "Kimi"],
            ["xAI", "SpaceXAI", "x.ai"],
            ["Alibaba", "Alibaba-ATH", "Qwen"],
            ["ByteDance Seed", "Bytedance"],
            ["Luma AI", "Luma Labs"],
            ["Z.ai", "Z AI"],
            ["Microsoft AI"],
            ["Black Forest Labs"],
            ["Video Rebirth"],
            ["KlingAI"],
            ["Opencode"],
            ["StepFun"],
            ["Thinking Machines"]
        ]
        for group in groups {
            let keys = group.map {
                OrganizationLogoCatalog.bundledLogoKey(forOrganization: $0)
            }
            let colors = group.map {
                OrganizationLogoCatalog.brandColorHex(forOrganization: $0)
            }
            XCTAssertEqual(Set(keys).count, 1, group.joined(separator: ", "))
            XCTAssertNotNil(keys[0], group.joined(separator: ", "))
            XCTAssertEqual(Set(colors).count, 1, group.joined(separator: ", "))
            XCTAssertNotNil(colors[0], group.joined(separator: ", "))
        }

        // Purchase links keep `alibaba`. Logos use the Qwen mark.
        XCTAssertEqual(OrganizationLogoCatalog.bundledLogoKey(forOrganization: "Alibaba"), "qwen")
        XCTAssertNotEqual(OrganizationLogoCatalog.bundledLogoKey(forOrganization: "Alibaba"), "alibaba")
    }

    func testDevinFallsBackToModelNameWhenOrganizationIsMissing() {
        let name = "Devin Fusion CLI - Claude Fable 5.1 XHigh + SWE-2 Medium"
        XCTAssertEqual(
            OrganizationLogoCatalog.bundledLogoKey(forOrganization: nil, modelName: name),
            "devin"
        )
        XCTAssertEqual(
            OrganizationLogoCatalog.brandColorHex(forOrganization: nil, modelName: name),
            OrganizationLogoCatalog.brandColorHex(forOrganization: "Devin")
        )
        XCTAssertNotNil(OrganizationLogoCatalog.logoURL(forOrganization: nil, modelName: name))

        let other = OrganizationLogoCatalog.resolvedKey(
            organization: nil,
            modelName: "Some Other Model"
        )
        XCTAssertNil(other)
        XCTAssertNil(OrganizationLogoCatalog.bundledLogoKey(forOrganization: nil, modelName: "Some Other Model"))
        XCTAssertNil(OrganizationLogoCatalog.brandColorHex(forOrganization: "", modelName: "Some Other Model"))
    }

    func testHostedModelBrandOverridesHarnessOrganization() {
        XCTAssertEqual(
            OrganizationLogoCatalog.bundledLogoKey(
                forOrganization: "Anthropic",
                modelName: "Claude Code - Qwen3.8 Max"
            ),
            "qwen"
        )
        XCTAssertEqual(
            OrganizationLogoCatalog.brandColorHex(
                forOrganization: "Anthropic",
                modelName: "Claude Code - Qwen3.8 Max"
            ),
            "#623AE7"
        )
        XCTAssertEqual(
            OrganizationLogoCatalog.bundledLogoKey(
                forOrganization: "OpenAI",
                modelName: "Codex - DeepSeek V4 Pro 0813 (max)"
            ),
            "deepseek"
        )
        XCTAssertEqual(
            OrganizationLogoCatalog.brandColorHex(
                forOrganization: "OpenAI",
                modelName: "Codex - DeepSeek V4 Flash 0731 (max)"
            ),
            "#4D6BFE"
        )
        XCTAssertEqual(
            OrganizationLogoCatalog.resolvedKey(
                organization: "Opencode",
                modelName: "Opencode - GLM-5.3"
            ),
            "zai"
        )

        // Same company on both sides of the dash stays with the harness.
        XCTAssertEqual(
            OrganizationLogoCatalog.bundledLogoKey(
                forOrganization: "Anthropic",
                modelName: "Claude Code - Fable 5.1 (max) (with fallback)"
            ),
            "anthropic"
        )
        XCTAssertEqual(
            OrganizationLogoCatalog.brandColorHex(
                forOrganization: "Anthropic",
                modelName: "Claude Code - Opus 5 (max)"
            ),
            "#D97757"
        )
        // Intelligence-index names are not harness labels.
        XCTAssertEqual(
            OrganizationLogoCatalog.bundledLogoKey(
                forOrganization: "Alibaba",
                modelName: "Qwen3.8 Max (0902)"
            ),
            "qwen"
        )
        // Devin Fusion has no organization. Do not steal the mark from the model half.
        XCTAssertEqual(
            OrganizationLogoCatalog.bundledLogoKey(
                forOrganization: nil,
                modelName: "Devin Fusion CLI - Claude Fable 5.1 XHigh + SWE-2 Medium"
            ),
            "devin"
        )
    }

    func testCachedOrganizationsHaveBundledMarksAndRealColors() {
        let organizations = [
            "Google", "OpenAI", "Anthropic", "Alibaba", "Meta", "Microsoft AI", "SpaceXAI",
            "KlingAI", "Z.ai", "ByteDance Seed", "Bytedance", "MiniMax", "Moonshot", "PixVerse",
            "Xiaomi", "Z AI", "xAI", "Alibaba-ATH", "Black Forest Labs", "DeepSeek", "Fal",
            "Ideogram", "Kimi", "Krea", "Luma AI", "Luma Labs", "Moonshot AI", "Opencode",
            "Runway", "StepFun", "Tencent", "Reve", "Video Rebirth"
        ]
        var colors: [String: String] = [:]
        for organization in organizations {
            let key = OrganizationLogoCatalog.bundledLogoKey(forOrganization: organization)
            let color = OrganizationLogoCatalog.brandColorHex(forOrganization: organization)
            XCTAssertNotNil(key, organization)
            XCTAssertNotNil(color, organization)
            guard let key, let color else { continue }
            // Achromatic marks may share black or gray ink. Colored marks may not.
            if !OrganizationLogoCatalog.isAchromaticHex(color), let existing = colors[color] {
                XCTAssertEqual(existing, key, "\(organization) reuses \(color) from \(existing)")
            } else if colors[color] == nil {
                colors[color] = key
            }
            XCTAssertFalse(
                ["#0A0A0A", "#404040", "#71767B", "#1F2937", "#3E63DD", "#F59E0B"].contains(color),
                organization
            )
        }
    }

    func testBrandColorsFollowTheMark() {
        let expected = [
            "anthropic": "#D97757",
            "openai": "#10A37F",
            "qwen": "#623AE7",
            "kimi": "#027AFF",
            "google": "#4285F4",
            "deepseek": "#4D6BFE",
            "tencent": "#0055E9",
            "meta": "#0081FB",
            "minimax": "#E93163",
            "mistral": "#EE792F",
            "nvidia": "#76B900",
            "bytedance": "#3C8CFF",
            "xiaomi": "#FF6900",
            "klingai": "#04A6F0",
            "luma": "#00A2FF",
            "fal": "#EC0648",
            "pixverse": "#9727EF",
            "microsoftai": "#0D91E1",
            "zai": "#2C2C2C",
            "spacexai": "#000000",
            "stepfun": "#111111",
            "krea": "#0C0C0C",
            "ideogram": "#232426",
            "runway": "#000000",
            "blackforestlabs": "#000000",
            "opencode": "#131010",
            "devin": "#000000",
            "reve": "#000000",
            "videorebirth": "#000000",
            "thinkingmachines": "#1C1C1E"
        ]
        for (key, color) in expected {
            XCTAssertEqual(OrganizationLogoCatalog.brandColorHex(forOrganization: key), color, key)
            XCTAssertEqual(OrganizationLogoCatalog.bundledLogoKey(forOrganization: key), key)
        }

        for name in ["xAI", "SpaceXAI", "x.ai"] {
            let color = OrganizationLogoCatalog.brandColorHex(forOrganization: name)
            XCTAssertEqual(color, "#000000", name)
            XCTAssertTrue(OrganizationLogoCatalog.isAchromaticHex(color ?? ""))
        }
        XCTAssertFalse(OrganizationLogoCatalog.isAchromaticHex("#10A37F"))
        XCTAssertFalse(OrganizationLogoCatalog.isAchromaticHex("#F59E0B"))
        XCTAssertEqual(OrganizationLogoCatalog.displayBrandColorHex("#000000", isDark: false), "#000000")
        XCTAssertEqual(OrganizationLogoCatalog.displayBrandColorHex("#000000", isDark: true), "#FFFFFF")
        XCTAssertEqual(OrganizationLogoCatalog.displayBrandColorHex("#2C2C2C", isDark: true), "#FFFFFF")
        XCTAssertEqual(OrganizationLogoCatalog.displayBrandColorHex("#10A37F", isDark: true), "#10A37F")
        XCTAssertNotEqual(
            OrganizationLogoCatalog.brandColorHex(forOrganization: "Devin"),
            OrganizationLogoCatalog.brandColorHex(forOrganization: "Qwen")
        )
    }
}
