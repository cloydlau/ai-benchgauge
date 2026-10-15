import Foundation
import LeaderboardCore
import Testing

struct OrganizationBrandTests {
    @Test func providerPNGsCannotReplaceKnownModelMarks() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let png = try Data(contentsOf: root.appending(path: "Tests/fixtures/shared-brand-64.png"))
        for (name, organization, key) in [
            ("Claude Opus 5.5", "Anthropic", "anthropic"),
            ("Qwen4-Max", "Alibaba", "qwen"),
            ("Gemini 3.5 Pro", "Google", "google"),
            ("Kimi K3", "Moonshot AI", "kimi"),
            ("DeepSeek V4", "DeepSeek", "deepseek"),
            ("MiniMax M3", "MiniMax", "minimax"),
            ("Claude Code - Qwen3.8 Max", "Anthropic", "qwen")
        ] {
            let provider = OrganizationBrand(key: key, colorHex: "#319FA8", pngData: png)
            let entry = LeaderboardEntry(rank: 1, name: name, score: 99, organization: organization, brand: provider)
            #expect(OrganizationLogoCatalog.rowLogoPNGData(for: entry) == nil)
            #expect(OrganizationLogoCatalog.rowLogoPNGData(for: entry, isCompany: true) == png)
        }
        for (name, organization) in [("New Model", "New Maker"), ("GPT-6", "OpenAI"), ("Veo 3.1", "Google")] {
            let entry = LeaderboardEntry(rank: 1, name: name, score: 99, organization: organization,
                brand: OrganizationBrand(key: organization, colorHex: "#319FA8", pngData: png))
            #expect(OrganizationLogoCatalog.rowLogoPNGData(for: entry) == png)
        }
        let noBrand = LeaderboardEntry(rank: 1, name: "Claude", score: 99, organization: "Anthropic")
        #expect(OrganizationLogoCatalog.rowLogoPNGData(for: noBrand) == nil)
        let explicitModel = LeaderboardEntry(rank: 1, name: "Gemini Omni", score: 99, organization: "Google",
            brand: OrganizationBrand(key: "model-geminiomni", colorHex: "#319FA8", pngData: png))
        #expect(OrganizationLogoCatalog.rowLogoPNGData(for: explicitModel) == png)
        let invalid = LeaderboardEntry(rank: 1, name: "Claude", score: 99, organization: "Anthropic",
            brand: OrganizationBrand(key: "model-claude", colorHex: "#319FA8", pngData: Data("invalid".utf8)))
        #expect(OrganizationLogoCatalog.rowLogoPNGData(for: invalid) == nil)
    }

    @Test func modelAndCompanyMarksSurviveCacheWithoutBeingMixed() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let png = try Data(contentsOf: root.appending(path: "Tests/fixtures/shared-brand-64.png"))
        let model = OrganizationBrand(key: "model-wan", colorHex: "#634FD2", pngData: png)
        let company = OrganizationBrand(key: "qwen", colorHex: "#623AE7", pngData: png)
        let entry = LeaderboardEntry(rank: 1, name: "Wan 3.0", score: 100, organization: "Alibaba", brand: model, organizationBrand: company)
        let decoded = try JSONDecoder().decode(LeaderboardEntry.self, from: JSONEncoder().encode(entry))
        #expect(decoded == entry)
        #expect(OrganizationLogoCatalog.rowBrandColorHex(for: decoded) == "#634FD2")
        let companyRow = try #require(CompanyLeaderboard.rank([decoded]).first?.entry)
        #expect(companyRow.brand == company)
        #expect(OrganizationLogoCatalog.rowBrandColorHex(for: companyRow) == "#623AE7")
    }
    @Test func sharedBrandSurvivesCacheAndCompanyAggregation() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        // A checked-in 64px shared mark exercises the shared payload contract independently of bundled logo sizes.
        let bundled = try Data(contentsOf: root.appending(path: "Tests/fixtures/shared-brand-64.png"))
        let brand = OrganizationBrand(key: "newmaker", colorHex: "#319FA8", pngData: bundled)
        let entry = LeaderboardEntry(rank: 1, name: "New Model", score: 91, organization: "New Maker", brand: brand)
        let decoded = try JSONDecoder().decode(LeaderboardEntry.self, from: JSONEncoder().encode(entry))
        #expect(decoded == entry)
        #expect(CompanyLeaderboard.rank([entry]).first?.entry.brand == brand)
        #expect(OrganizationLogoCatalog.rowBrandColorHex(for: decoded) == "#319FA8")
        let old = try JSONDecoder().decode(LeaderboardEntry.self, from: Data(#"{"rank":1,"name":"Old Model","score":91,"organization":"New Maker"}"#.utf8))
        #expect(old.brand == nil)
        #expect(OrganizationLogoCatalog.rowBrandColorHex(for: old) == OrganizationLogoCatalog.fallbackColorHex(for: "newmaker"))
    }
    @Test func knownColorsWinAndInvalidMetadataFallsBack() {
        let remote = OrganizationBrand(key: "openai", colorHex: "#319FA8")
        let known = LeaderboardEntry(rank: 1, name: "GPT New", score: 91, organization: "OpenAI", brand: remote)
        #expect(OrganizationLogoCatalog.rowBrandColorHex(for: known) == "#10A37F")
        let invalid = LeaderboardEntry(rank: 1, name: "Other", score: 91, organization: "New Maker", brand: OrganizationBrand(key: "newmaker", colorHex: "garbage"))
        #expect(OrganizationLogoCatalog.rowBrandColorHex(for: invalid) == OrganizationLogoCatalog.fallbackColorHex(for: "New Maker"))
        let wrong = LeaderboardEntry(rank: 1, name: "Other", score: 91, organization: "New Maker", brand: remote)
        #expect(OrganizationLogoCatalog.rowBrandColorHex(for: wrong) == OrganizationLogoCatalog.fallbackColorHex(for: "New Maker"))
        #expect(OrganizationLogoCatalog.fallbackColorHex(for: "Skywork AI") == "#B55C7B")
        #expect(OrganizationLogoCatalog.fallbackColorHex(for: "New-Maker") == OrganizationLogoCatalog.fallbackColorHex(for: "newmaker"))
    }
    @Test func initialsAndInvalidPNGsNeverLeaveAnEmptyPlaceholder() {
        #expect(OrganizationLogoCatalog.initial(organization: " New Maker", modelName: "Other") == "N")
        #expect(OrganizationLogoCatalog.initial(organization: "Unknown", modelName: "New Model") == "N")
        #expect(OrganizationLogoCatalog.initial(organization: "", modelName: "视频模型") == "视")
        #expect(OrganizationLogoCatalog.initial(organization: nil, modelName: "") == "?")
        #expect(OrganizationLogoCatalog.resolvedKey(organization: "Unknown", modelName: "Other") == nil)
        #expect(OrganizationLogoCatalog.resolvedKey(organization: nil, modelName: "Claude Code - Sonnet 5.5 (max)") == "anthropic")
        #expect(OrganizationLogoCatalog.initial(organization: "Anthropic", modelName: "Claude Code - Qwen3.8 Max") == "Q")
        let malformed = OrganizationBrand(key: "newmaker", colorHex: "#319FA8", pngData: Data("not an image".utf8))
        #expect(malformed.validPNGData == nil)
    }
}
