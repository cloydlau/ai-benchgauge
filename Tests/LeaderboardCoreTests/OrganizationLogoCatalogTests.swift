import Foundation
import LeaderboardCore
import Testing

struct OrganizationLogoCatalogTests {
    @Test
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
            #expect((Set(keys).count) == (1), Comment(rawValue: group.joined(separator: ", ")))
            #expect((keys[0]) != nil, Comment(rawValue: group.joined(separator: ", ")))
            #expect((Set(colors).count) == (1), Comment(rawValue: group.joined(separator: ", ")))
            #expect((colors[0]) != nil, Comment(rawValue: group.joined(separator: ", ")))
        }

        // Purchase links keep `alibaba`. Logos use the Qwen mark.
        #expect((OrganizationLogoCatalog.bundledLogoKey(forOrganization: "Alibaba")) == ("qwen"))
        #expect((OrganizationLogoCatalog.bundledLogoKey(forOrganization: "Alibaba")) != ("alibaba"))
    }

    @Test
    func testDevinFallsBackToModelNameWhenOrganizationIsMissing() {
        let name = "Devin"
        #expect((OrganizationLogoCatalog.bundledLogoKey(forOrganization: nil, modelName: name)) == ("devin"))
        #expect((OrganizationLogoCatalog.brandColorHex(forOrganization: nil, modelName: name)) == (OrganizationLogoCatalog.brandColorHex(forOrganization: "Devin")))
        #expect((OrganizationLogoCatalog.logoURL(forOrganization: nil, modelName: name)) != nil)

        let other = OrganizationLogoCatalog.resolvedKey(
            organization: nil,
            modelName: "Some Other Model"
        )
        #expect((other) == nil)
        #expect((OrganizationLogoCatalog.bundledLogoKey(forOrganization: nil, modelName: "Some Other Model")) == nil)
        #expect((OrganizationLogoCatalog.brandColorHex(forOrganization: "", modelName: "Some Other Model")) == nil)
    }

    @Test
    func testHostedModelBrandOverridesHarnessOrganization() {
        #expect((OrganizationLogoCatalog.bundledLogoKey(
                forOrganization: "Anthropic",
                modelName: "Claude Code - Qwen3.8 Max"
            )) == ("qwen"))
        #expect((OrganizationLogoCatalog.brandColorHex(
                forOrganization: "Anthropic",
                modelName: "Claude Code - Qwen3.8 Max"
            )) == ("#623AE7"))
        #expect((OrganizationLogoCatalog.bundledLogoKey(
                forOrganization: "OpenAI",
                modelName: "Codex - DeepSeek V4 Pro 0813 (max)"
            )) == ("deepseek"))
        #expect((OrganizationLogoCatalog.brandColorHex(
                forOrganization: "OpenAI",
                modelName: "Codex - DeepSeek V4 Flash 0731 (max)"
            )) == ("#4D6BFE"))
        #expect((OrganizationLogoCatalog.resolvedKey(
                organization: "Opencode",
                modelName: "Opencode - GLM-5.3"
            )) == ("zai"))

        // Same company on both sides of the dash stays with the harness.
        #expect((OrganizationLogoCatalog.bundledLogoKey(
                forOrganization: "Anthropic",
                modelName: "Claude Code - Fable 5.1 (max) (with fallback)"
            )) == ("anthropic"))
        #expect((OrganizationLogoCatalog.brandColorHex(
                forOrganization: "Anthropic",
                modelName: "Claude Code - Opus 5 (max)"
            )) == ("#D97757"))
        // Intelligence-index names are not harness labels.
        #expect((OrganizationLogoCatalog.bundledLogoKey(
                forOrganization: "Alibaba",
                modelName: "Qwen3.8 Max (0902)"
            )) == ("qwen"))
        // Fusion has no organization. The mark stays Devin. The wash follows the lead.
        let claudeFusion = "Devin Fusion CLI - Claude Fable 5.1 XHigh + SWE-2 Medium"
        #expect((OrganizationLogoCatalog.bundledLogoKey(forOrganization: nil, modelName: claudeFusion)) == ("devin"))
        #expect((OrganizationLogoCatalog.brandColorHex(forOrganization: nil, modelName: claudeFusion)) == ("#D97757"))
        let astraFusion = "Devin Fusion CLI - GPT-6 Astra XHigh + SWE-2 Medium"
        #expect((OrganizationLogoCatalog.bundledLogoKey(forOrganization: nil, modelName: astraFusion)) == ("devin"))
        #expect((OrganizationLogoCatalog.brandColorHex(forOrganization: nil, modelName: astraFusion)) == ("#10A37F"))
    }

    @Test
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
            #expect((key) != nil, Comment(rawValue: organization))
            #expect((color) != nil, Comment(rawValue: organization))
        }
    }

    @Test
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
            #expect((OrganizationLogoCatalog.brandColorHex(forOrganization: key)) == (color), Comment(rawValue: key))
            #expect((OrganizationLogoCatalog.bundledLogoKey(forOrganization: key)) == (key))
            let darkColor = OrganizationLogoCatalog.displayBrandColorHex(color, isDark: true)
            if OrganizationLogoCatalog.isAchromaticHex(color) {
                #expect(OrganizationLogoCatalog.isAchromaticHex(darkColor), Comment(rawValue: key))
                #expect((darkColor) != (color), Comment(rawValue: key))
            } else {
                #expect((darkColor) == (color), Comment(rawValue: key))
            }
        }

        for name in ["xAI", "SpaceXAI", "x.ai"] {
            let color = OrganizationLogoCatalog.brandColorHex(forOrganization: name)
            #expect((color) == ("#242424"), Comment(rawValue: name))
            #expect(OrganizationLogoCatalog.isAchromaticHex(color ?? ""))
            #expect((OrganizationLogoCatalog.displayBrandColorHex(color ?? "", isDark: true)) == ("#E6E6E6"), Comment(rawValue: name))
        }
        #expect(!(OrganizationLogoCatalog.isAchromaticHex("#10A37F")))
        #expect(!(OrganizationLogoCatalog.isAchromaticHex("#F59E0B")))
        #expect((OrganizationLogoCatalog.displayBrandColorHex("#000000", isDark: false)) == ("#000000"))
        #expect((OrganizationLogoCatalog.displayBrandColorHex("#000000", isDark: true)) == ("#FFFFFF"))
        #expect((OrganizationLogoCatalog.displayBrandColorHex("#2C2C2C", isDark: true)) == ("#E1E1E1"))
        #expect((OrganizationLogoCatalog.displayBrandColorHex("#10A37F", isDark: true)) == ("#10A37F"))
        #expect((OrganizationLogoCatalog.brandColorHex(forOrganization: "Devin")) != (OrganizationLogoCatalog.brandColorHex(forOrganization: "Qwen")))
    }

    @Test
    func testModelsKeepBrandHueWhileVaryingShade() {
        let brand = OrganizationLogoCatalog.brandColorHex(forOrganization: "Anthropic")!
        let names = ["Claude Fable 5.1", "Claude Opus 4.7", "Claude Opus 5.5", "Claude Sonnet 5"]
        let shades = names.map {
            OrganizationLogoCatalog.displayBrandColorHex(brand, isDark: false, modelName: $0)
        }
        #expect((Set(shades).count) > (1))
        for color in shades {
            let red = Int(color.dropFirst().prefix(2), radix: 16)!
            let green = Int(color.dropFirst(3).prefix(2), radix: 16)!
            let blue = Int(color.dropFirst(5).prefix(2), radix: 16)!
            #expect((red) > (green))
            #expect((green) > (blue))
        }

        let kimi = OrganizationLogoCatalog.brandColorHex(forOrganization: "Kimi")!
        #expect((OrganizationLogoCatalog.displayBrandColorHex(kimi, isDark: false, modelName: "Kimi K3 (max)")) == (OrganizationLogoCatalog.displayBrandColorHex(kimi, isDark: false, modelName: "kimi-k3-max")))
        let xai = OrganizationLogoCatalog.brandColorHex(forOrganization: "xAI")!
        #expect(OrganizationLogoCatalog.isAchromaticHex(
            OrganizationLogoCatalog.displayBrandColorHex(xai, isDark: true, modelName: "Grok 4.7")
        ))
    }
}
