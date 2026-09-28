import Foundation
import LeaderboardCore
import Testing

struct CompanyLeaderboardTests {
    @Test
    func testEqualScoresStayEqualForAnyCount() {
        let ranked = CompanyLeaderboard.rank([
            entry(1, "Solo", 90, organization: "Alpha"),
            entry(2, "B1", 90, organization: "Beta"),
            entry(5, "B2", 90, organization: "Beta"),
            entry(9, "B3", 90, organization: "Beta"),
        ])
        #expect((ranked.map(\.entry.name)) == (["Alpha", "Beta"]))
        #expect((ranked[0].entry.score) == (90))
        #expect((ranked[1].entry.score) == (90))
        #expect((ranked[0].entry.score) == (ranked[1].entry.score))
        #expect((ranked[0].components.count) == (1))
        #expect((ranked[1].components.count) == (3))
    }

    @Test
    func testFlagshipScoreIgnoresTheWeakerModel() {
        let ranked = CompanyLeaderboard.rank([
            entry(4, "Tail", 40, organization: "Alpha"),
            entry(1, "Top", 100, organization: "Alpha"),
        ])
        let standing = try! #require(ranked.first)
        #expect(abs((standing.entry.score) - (100)) <= 1e-9)
        #expect((standing.components.map(\.name)) == (["Top", "Tail"]))
        #expect((CompanyLeaderboard.scoreHelp(for: standing)) == ("""
            以最强模型分数为准，弱型号不拉低
            Top · 第1名 · 100.0 · 最强
            Tail · 第4名 · 40.0
            """))
        #expect(!(standing.entry.name.contains("2")))
    }

    @Test
    func testWeakerSiblingDoesNotRankBelowAStrongerFlagship() {
        // Reciprocal-rank mean would score xAI at 72*(4/7)+40*(3/7) ≈ 58.3,
        // behind Xiaomi's 68, even though Grok 4.7 is the stronger model.
        let ranked = CompanyLeaderboard.rank([
            entry(4, "Grok 4.6", 40, organization: "xAI"),
            entry(8, "MiMo 2.6", 68, organization: "Xiaomi"),
            entry(3, "Grok 4.7", 72, organization: "xAI"),
        ])
        #expect((ranked.map(\.entry.name)) == (["xAI", "Xiaomi"]))
        #expect(abs((ranked[0].entry.score) - (72)) <= 1e-9)
        #expect(abs((ranked[1].entry.score) - (68)) <= 1e-9)
        #expect((ranked[0].components.map(\.name)) == (["Grok 4.7", "Grok 4.6"]))
    }

    @Test
    func testWeakerTailDoesNotChangeTheFlagshipScore() {
        let alone = CompanyLeaderboard.rank([
            entry(1, "Top", 100, organization: "Alpha"),
        ])[0].entry.score
        let withTail = CompanyLeaderboard.rank([
            entry(1, "Top", 100, organization: "Alpha"),
            entry(20, "Tail", 10, organization: "Alpha"),
        ])[0].entry.score
        #expect((alone) == (100))
        #expect((withTail) == (alone))
    }

    @Test
    func testEightAverageModelsDoNotBeatOneStrongModel() {
        var entries = (1...8).map { rank in
            entry(rank, "Average \(rank)", 50, organization: "Crowd")
        }
        entries.append(entry(9, "Solo", 80, organization: "Focused"))
        let ranked = CompanyLeaderboard.rank(entries)
        #expect((ranked.map(\.entry.name)) == (["Focused", "Crowd"]))
        #expect(abs((ranked[0].entry.score) - (80)) <= 1e-9)
        #expect(abs((ranked[1].entry.score) - (50)) <= 1e-9)
        #expect((ranked[0].components.count) == (1))
        #expect((ranked[1].components.count) == (8))
    }

    @Test
    func testAliasesMergeToOneCanonicalCompany() {
        let ranked = CompanyLeaderboard.rank([
            entry(1, "Qwen3 Max", 80, organization: "Alibaba"),
            entry(3, "Qwen3 Next", 60, organization: "Qwen"),
            entry(2, "Grok 4", 70, organization: "SpaceXAI"),
            entry(4, "Grok 3", 50, organization: "xAI"),
        ])
        #expect((Set(ranked.map(\.entry.name))) == (["Alibaba", "xAI"]))
        let alibaba = try! #require(ranked.first { $0.entry.name == "Alibaba" })
        #expect((alibaba.entry.organization) == ("Alibaba"))
        #expect((alibaba.components.map(\.name).sorted()) == (["Qwen3 Max", "Qwen3 Next"]))
        #expect(!(alibaba.entry.name.contains("×")))
    }

    @Test
    func testHostedModelCountsForTheModelCompanyNotTheHarness() {
        let ranked = CompanyLeaderboard.rank([
            entry(2, "OpenCode - Qwen3 Max", 70, organization: "Opencode"),
            entry(6, "OpenCode Zen", 40, organization: "Opencode"),
        ])
        #expect((ranked.map(\.entry.name)) == (["Alibaba", "OpenCode"]))
        #expect((ranked[0].components.map(\.name)) == (["OpenCode - Qwen3 Max"]))
        #expect((ranked[1].components.map(\.name)) == (["OpenCode Zen"]))
        #expect((ranked[0].entry.organization) == ("Alibaba"))
        #expect((OrganizationLogoCatalog.resolvedKey(
                organization: ranked[0].entry.organization,
                modelName: ranked[0].entry.name
            )) == ("qwen"))
        #expect((PurchaseLinkCatalog.links(
                forOrganization: ranked[0].entry.organization,
                modelName: ranked[0].entry.name
            )) == (PurchaseLinkCatalog.links(forOrganization: "Alibaba")))
        #expect((PurchaseLinkCatalog.links(forOrganization: ranked[0].entry.organization)) != (PurchaseLinkCatalog.links(forOrganization: "Opencode")))
        #expect(!(ranked[0].entry.name.contains("OpenCode")))
    }

    @Test
    func testUnattributedRowsAreOmittedUnlessDevin() {
        let ranked = CompanyLeaderboard.rank([
            entry(1, "Mystery Model", 99),
            entry(2, "Devin Review", 50),
            entry(3, "Also Mystery", 40, organization: ""),
        ])
        #expect((ranked.map(\.entry.name)) == (["Devin"]))
        #expect((ranked[0].entry.organization) == ("Devin"))
        #expect((ranked[0].components.map(\.name)) == (["Devin Review"]))
    }

    @Test
    func testTiesBreakByBestRankNotModelCount() {
        let ranked = CompanyLeaderboard.rank([
            entry(2, "A", 70, organization: "Many"),
            entry(3, "B", 70, organization: "Many"),
            entry(4, "C", 70, organization: "Many"),
            entry(1, "Solo", 70, organization: "Few"),
        ])
        #expect((ranked.map(\.entry.name)) == (["Few", "Many"]))
        #expect((ranked[0].components.count) == (1))
        #expect((ranked[1].components.count) == (3))
        #expect((ranked[0].entry.score) == (ranked[1].entry.score))
    }

    @Test
    func testEqualScoreAndBestRankBreakByDisplayName() {
        let ranked = CompanyLeaderboard.rank([
            entry(1, "Zed", 40, organization: "Zeta"),
            entry(1, "Amy", 40, organization: "Alpha"),
        ])
        #expect((ranked.map(\.entry.name)) == (["Alpha", "Zeta"]))
    }

    @Test
    func testDisplayCapsAtTwentyCompanies() {
        let entries = (1...25).map { rank in
            entry(rank, "M\(rank)", Double(100 - rank), organization: "Org \(rank)")
        }
        let ranked = CompanyLeaderboard.rank(entries)
        #expect((ranked.count) == (20))
        #expect((ranked.first?.entry.name) == ("Org 1"))
        #expect((ranked.last?.entry.name) == ("Org 20"))
        #expect((ranked.map(\.entry.rank)) == (Array(1...20)))
    }

    @Test
    func testLogoFollowsTheBestRankedModel() {
        let best = URL(string: "https://example.com/best.png")!
        let other = URL(string: "https://example.com/other.png")!
        let ranked = CompanyLeaderboard.rank([
            entry(4, "Tail", 10, organization: "Qwen", logoURL: other),
            entry(1, "Top", 90, organization: "Alibaba", logoURL: best),
        ])
        #expect((ranked[0].entry.logoURL) == (best))
        #expect((ranked[0].entry.name) == ("Alibaba"))
    }

    @Test
    func testNonPositiveRankIsSkipped() {
        let ranked = CompanyLeaderboard.rank([
            entry(0, "Zero", 100, organization: "Zero"),
            entry(1, "One", 10, organization: "One"),
        ])
        #expect((ranked.map(\.entry.name)) == (["One"]))
    }

    @Test
    func testCanonicalNamesRoundTripThroughLogoPurchaseAndRegion() {
        let samples: [(key: String, organization: String, display: String)] = [
            ("anthropic", "Anthropic", "Anthropic"),
            ("openai", "OpenAI", "OpenAI"),
            ("qwen", "Qwen", "Alibaba"),
            ("zai", "Z.ai", "Z.ai"),
            ("spacexai", "xAI", "xAI"),
            ("stepfun", "StepFun", "StepFun"),
            ("kimi", "Moonshot", "Moonshot"),
            ("google", "Google", "Google"),
            ("deepseek", "DeepSeek", "DeepSeek"),
            ("tencent", "Tencent", "Tencent"),
            ("meta", "Meta", "Meta"),
            ("minimax", "MiniMax", "MiniMax"),
            ("mistral", "Mistral", "Mistral"),
            ("nvidia", "Nvidia", "Nvidia"),
            ("bytedance", "ByteDance", "ByteDance"),
            ("xiaomi", "Xiaomi", "Xiaomi"),
            ("klingai", "KlingAI", "KlingAI"),
            ("krea", "Krea", "Krea"),
            ("ideogram", "Ideogram", "Ideogram"),
            ("runway", "Runway", "Runway"),
            ("luma", "Luma", "Luma"),
            ("blackforestlabs", "Black Forest Labs", "Black Forest Labs"),
            ("fal", "Fal", "Fal"),
            ("pixverse", "PixVerse", "PixVerse"),
            ("microsoftai", "Microsoft AI", "Microsoft AI"),
            ("opencode", "Opencode", "OpenCode"),
            ("devin", "Devin", "Devin"),
            ("reve", "Reve", "Reve"),
            ("videorebirth", "Video Rebirth", "Video Rebirth"),
            ("thinkingmachines", "Thinking Machines", "Thinking Machines"),
        ]
        for sample in samples {
            let ranked = CompanyLeaderboard.rank([
                entry(1, "Model", 10, organization: sample.organization),
            ])
            let standing = try! #require(ranked.first)
            #expect((standing.entry.name) == (sample.display), Comment(rawValue: sample.key))
            #expect((standing.entry.organization) == (sample.display), Comment(rawValue: sample.key))
            #expect((OrganizationLogoCatalog.resolvedKey(
                    organization: standing.entry.organization,
                    modelName: standing.entry.name
                )) == (sample.key), Comment(rawValue: sample.key))
            #expect((OrganizationLogoCatalog.normalizedKey(standing.entry.name)) == (sample.key), Comment(rawValue: sample.key))
            #expect((PurchaseLinkCatalog.links(
                    forOrganization: standing.entry.organization,
                    modelName: standing.entry.name
                )) == (PurchaseLinkCatalog.links(
                    forOrganization: sample.organization,
                    modelName: "Model"
                )), Comment(rawValue: sample.key))
            #expect((OrganizationRegion.isChinese(
                    standing.entry.organization,
                    modelName: standing.entry.name
                )) == (OrganizationRegion.isChinese(sample.organization, modelName: "Model")), Comment(rawValue: sample.key))
        }
        #expect(!(PurchaseLinkCatalog.links(forOrganization: "Microsoft AI").isEmpty))
        #expect((PurchaseLinkCatalog.links(forOrganization: "Microsoft AI")) != (PurchaseLinkCatalog.links(forOrganization: "Microsoft")))
    }

    @Test
    func testGroupingTitlesAndPreference() {
        #expect((LeaderboardGrouping.allCases) == ([.model, .company]))
        #expect((LeaderboardGrouping.model.title) == ("模型"))
        #expect((LeaderboardGrouping.company.title) == ("公司"))

        let suite = "GroupingPreferenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect((GroupingPreference.load(from: defaults)) == (.model))

        GroupingPreference.save(.company, to: defaults)
        #expect((GroupingPreference.load(from: defaults)) == (.company))

        defaults.set("not-a-grouping", forKey: GroupingPreference.userDefaultsKey)
        #expect((GroupingPreference.load(from: defaults)) == (.model))
        #expect((defaults.string(forKey: GroupingPreference.userDefaultsKey)) == nil)
    }

    private func entry(
        _ rank: Int,
        _ name: String,
        _ score: Double,
        organization: String? = nil,
        logoURL: URL? = nil
    ) -> LeaderboardEntry {
        LeaderboardEntry(
            rank: rank,
            name: name,
            score: score,
            organization: organization,
            logoURL: logoURL
        )
    }
}
