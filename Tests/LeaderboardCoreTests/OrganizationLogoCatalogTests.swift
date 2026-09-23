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
        let name = "Devin"
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
        // Fusion has no organization. The mark stays Devin. The wash follows the lead.
        let claudeFusion = "Devin Fusion CLI - Claude Fable 5.1 XHigh + SWE-2 Medium"
        XCTAssertEqual(
            OrganizationLogoCatalog.bundledLogoKey(forOrganization: nil, modelName: claudeFusion),
            "devin"
        )
        XCTAssertEqual(
            OrganizationLogoCatalog.brandColorHex(forOrganization: nil, modelName: claudeFusion),
            "#D97757"
        )
        let astraFusion = "Devin Fusion CLI - GPT-6 Astra XHigh + SWE-2 Medium"
        XCTAssertEqual(
            OrganizationLogoCatalog.bundledLogoKey(forOrganization: nil, modelName: astraFusion),
            "devin"
        )
        XCTAssertEqual(
            OrganizationLogoCatalog.brandColorHex(forOrganization: nil, modelName: astraFusion),
            "#10A37F"
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
        for organization in organizations {
            let key = OrganizationLogoCatalog.bundledLogoKey(forOrganization: organization)
            let color = OrganizationLogoCatalog.brandColorHex(forOrganization: organization)
            XCTAssertNotNil(key, organization)
            XCTAssertNotNil(color, organization)
        }
    }

    func testBrandColorsFollowTheMark() {
        let expected = [
            "anthropic": "#D97757",
            "openai": "#10A37F",
            "qwen": "#623AE7",
            "kimi": "#007CFF",
            "google": "#4285F4",
            "deepseek": "#4D6BFE",
            "tencent": "#0052D9",
            "meta": "#0068D5",
            "minimax": "#F21985",
            "mistral": "#F29D38",
            "nvidia": "#76B900",
            "bytedance": "#3C8CFF",
            "xiaomi": "#FF6900",
            "klingai": "#009DCB",
            "luma": "#00C8E8",
            "fal": "#EC0648",
            "pixverse": "#A129FF",
            "microsoftai": "#E24B9A",
            "zai": "#3A3A3A",
            "spacexai": "#242424",
            "stepfun": "#505050",
            "krea": "#666666",
            "ideogram": "#404040",
            "runway": "#2C2C2C",
            "blackforestlabs": "#343434",
            "opencode": "#5A5A5A",
            "devin": "#202020",
            "reve": "#484848",
            "videorebirth": "#707070",
            "thinkingmachines": "#606060",
            "github": "#303030"
        ]
        for (key, color) in expected {
            XCTAssertEqual(OrganizationLogoCatalog.brandColorHex(forOrganization: key), color, key)
            XCTAssertEqual(OrganizationLogoCatalog.bundledLogoKey(forOrganization: key), key)
            let darkColor = OrganizationLogoCatalog.displayBrandColorHex(color, isDark: true)
            if OrganizationLogoCatalog.isAchromaticHex(color) {
                XCTAssertTrue(OrganizationLogoCatalog.isAchromaticHex(darkColor), key)
                XCTAssertNotEqual(darkColor, color, key)
            } else {
                XCTAssertEqual(darkColor, color, key)
            }
        }

        for name in ["xAI", "SpaceXAI", "x.ai"] {
            let color = OrganizationLogoCatalog.brandColorHex(forOrganization: name)
            XCTAssertEqual(color, "#242424", name)
            XCTAssertTrue(OrganizationLogoCatalog.isAchromaticHex(color ?? ""))
            XCTAssertEqual(
                OrganizationLogoCatalog.displayBrandColorHex(color ?? "", isDark: true),
                "#E6E6E6",
                name
            )
        }
        XCTAssertFalse(OrganizationLogoCatalog.isAchromaticHex("#10A37F"))
        XCTAssertFalse(OrganizationLogoCatalog.isAchromaticHex("#F59E0B"))
        XCTAssertEqual(OrganizationLogoCatalog.displayBrandColorHex("#000000", isDark: false), "#000000")
        XCTAssertEqual(OrganizationLogoCatalog.displayBrandColorHex("#000000", isDark: true), "#FFFFFF")
        XCTAssertEqual(OrganizationLogoCatalog.displayBrandColorHex("#2C2C2C", isDark: true), "#E1E1E1")
        XCTAssertEqual(OrganizationLogoCatalog.displayBrandColorHex("#10A37F", isDark: true), "#10A37F")
        XCTAssertNotEqual(
            OrganizationLogoCatalog.brandColorHex(forOrganization: "Devin"),
            OrganizationLogoCatalog.brandColorHex(forOrganization: "Qwen")
        )
    }

    func testModelsKeepBrandHueWhileVaryingShade() {
        let brand = OrganizationLogoCatalog.brandColorHex(forOrganization: "Anthropic")!
        let names = ["Claude Fable 5.1", "Claude Opus 4.7", "Claude Opus 5.5", "Claude Sonnet 5"]
        let shades = names.map {
            OrganizationLogoCatalog.displayBrandColorHex(brand, isDark: false, modelName: $0)
        }
        XCTAssertGreaterThan(Set(shades).count, 1)
        for color in shades {
            let red = Int(color.dropFirst().prefix(2), radix: 16)!
            let green = Int(color.dropFirst(3).prefix(2), radix: 16)!
            let blue = Int(color.dropFirst(5).prefix(2), radix: 16)!
            XCTAssertGreaterThan(red, green)
            XCTAssertGreaterThan(green, blue)
        }

        let kimi = OrganizationLogoCatalog.brandColorHex(forOrganization: "Kimi")!
        XCTAssertEqual(
            OrganizationLogoCatalog.displayBrandColorHex(kimi, isDark: false, modelName: "Kimi K3 (max)"),
            OrganizationLogoCatalog.displayBrandColorHex(kimi, isDark: false, modelName: "kimi-k3-max")
        )
        let xai = OrganizationLogoCatalog.brandColorHex(forOrganization: "xAI")!
        XCTAssertTrue(OrganizationLogoCatalog.isAchromaticHex(
            OrganizationLogoCatalog.displayBrandColorHex(xai, isDark: true, modelName: "Grok 4.7")
        ))
    }
}
