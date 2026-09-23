import LeaderboardCore
import XCTest

final class CompanyLeaderboardTests: XCTestCase {
    func testEqualScoresStayEqualForAnyCount() {
        let ranked = CompanyLeaderboard.rank([
            entry(1, "Solo", 90, organization: "Alpha"),
            entry(2, "B1", 90, organization: "Beta"),
            entry(5, "B2", 90, organization: "Beta"),
            entry(9, "B3", 90, organization: "Beta"),
        ])
        XCTAssertEqual(ranked.map(\.entry.name), ["Alpha", "Beta"])
        XCTAssertEqual(ranked[0].entry.score, 90)
        XCTAssertEqual(ranked[1].entry.score, 90)
        XCTAssertEqual(ranked[0].entry.score, ranked[1].entry.score)
        XCTAssertEqual(ranked[0].components.count, 1)
        XCTAssertEqual(ranked[1].components.count, 3)
    }

    func testFlagshipScoreIgnoresTheWeakerModel() {
        let ranked = CompanyLeaderboard.rank([
            entry(4, "Tail", 40, organization: "Alpha"),
            entry(1, "Top", 100, organization: "Alpha"),
        ])
        let standing = try! XCTUnwrap(ranked.first)
        XCTAssertEqual(standing.entry.score, 100, accuracy: 1e-9)
        XCTAssertEqual(standing.components.map(\.name), ["Top", "Tail"])
        XCTAssertEqual(
            CompanyLeaderboard.scoreHelp(for: standing),
            """
            以最强模型分数为准，弱型号不拉低
            Top · 第1名 · 100.0 · 最强
            Tail · 第4名 · 40.0
            """
        )
        XCTAssertFalse(standing.entry.name.contains("2"))
    }

    func testWeakerSiblingDoesNotRankBelowAStrongerFlagship() {
        // Reciprocal-rank mean would score xAI at 72*(4/7)+40*(3/7) ≈ 58.3,
        // behind Xiaomi's 68, even though Grok 4.7 is the stronger model.
        let ranked = CompanyLeaderboard.rank([
            entry(4, "Grok 4.6", 40, organization: "xAI"),
            entry(8, "MiMo 2.6", 68, organization: "Xiaomi"),
            entry(3, "Grok 4.7", 72, organization: "xAI"),
        ])
        XCTAssertEqual(ranked.map(\.entry.name), ["xAI", "Xiaomi"])
        XCTAssertEqual(ranked[0].entry.score, 72, accuracy: 1e-9)
        XCTAssertEqual(ranked[1].entry.score, 68, accuracy: 1e-9)
        XCTAssertEqual(ranked[0].components.map(\.name), ["Grok 4.7", "Grok 4.6"])
    }

    func testWeakerTailDoesNotChangeTheFlagshipScore() {
        let alone = CompanyLeaderboard.rank([
            entry(1, "Top", 100, organization: "Alpha"),
        ])[0].entry.score
        let withTail = CompanyLeaderboard.rank([
            entry(1, "Top", 100, organization: "Alpha"),
            entry(20, "Tail", 10, organization: "Alpha"),
        ])[0].entry.score
        XCTAssertEqual(alone, 100)
        XCTAssertEqual(withTail, alone)
    }

    func testEightAverageModelsDoNotBeatOneStrongModel() {
        var entries = (1...8).map { rank in
            entry(rank, "Average \(rank)", 50, organization: "Crowd")
        }
        entries.append(entry(9, "Solo", 80, organization: "Focused"))
        let ranked = CompanyLeaderboard.rank(entries)
        XCTAssertEqual(ranked.map(\.entry.name), ["Focused", "Crowd"])
        XCTAssertEqual(ranked[0].entry.score, 80, accuracy: 1e-9)
        XCTAssertEqual(ranked[1].entry.score, 50, accuracy: 1e-9)
        XCTAssertEqual(ranked[0].components.count, 1)
        XCTAssertEqual(ranked[1].components.count, 8)
    }

    func testAliasesMergeToOneCanonicalCompany() {
        let ranked = CompanyLeaderboard.rank([
            entry(1, "Qwen3 Max", 80, organization: "Alibaba"),
            entry(3, "Qwen3 Next", 60, organization: "Qwen"),
            entry(2, "Grok 4", 70, organization: "SpaceXAI"),
            entry(4, "Grok 3", 50, organization: "xAI"),
        ])
        XCTAssertEqual(Set(ranked.map(\.entry.name)), ["Alibaba", "xAI"])
        let alibaba = try! XCTUnwrap(ranked.first { $0.entry.name == "Alibaba" })
        XCTAssertEqual(alibaba.entry.organization, "Alibaba")
        XCTAssertEqual(alibaba.components.map(\.name).sorted(), ["Qwen3 Max", "Qwen3 Next"])
        XCTAssertFalse(alibaba.entry.name.contains("×"))
    }

    func testHostedModelCountsForTheModelCompanyNotTheHarness() {
        let ranked = CompanyLeaderboard.rank([
            entry(2, "OpenCode - Qwen3 Max", 70, organization: "Opencode"),
            entry(6, "OpenCode Zen", 40, organization: "Opencode"),
        ])
        XCTAssertEqual(ranked.map(\.entry.name), ["Alibaba", "OpenCode"])
        XCTAssertEqual(ranked[0].components.map(\.name), ["OpenCode - Qwen3 Max"])
        XCTAssertEqual(ranked[1].components.map(\.name), ["OpenCode Zen"])
        XCTAssertEqual(ranked[0].entry.organization, "Alibaba")
        XCTAssertEqual(
            OrganizationLogoCatalog.resolvedKey(
                organization: ranked[0].entry.organization,
                modelName: ranked[0].entry.name
            ),
            "qwen"
        )
        XCTAssertEqual(
            PurchaseLinkCatalog.links(
                forOrganization: ranked[0].entry.organization,
                modelName: ranked[0].entry.name
            ),
            PurchaseLinkCatalog.links(forOrganization: "Alibaba")
        )
        XCTAssertNotEqual(
            PurchaseLinkCatalog.links(forOrganization: ranked[0].entry.organization),
            PurchaseLinkCatalog.links(forOrganization: "Opencode")
        )
        XCTAssertFalse(ranked[0].entry.name.contains("OpenCode"))
    }

    func testUnattributedRowsAreOmittedUnlessDevin() {
        let ranked = CompanyLeaderboard.rank([
            entry(1, "Mystery Model", 99),
            entry(2, "Devin Review", 50),
            entry(3, "Also Mystery", 40, organization: ""),
        ])
        XCTAssertEqual(ranked.map(\.entry.name), ["Devin"])
        XCTAssertEqual(ranked[0].entry.organization, "Devin")
        XCTAssertEqual(ranked[0].components.map(\.name), ["Devin Review"])
    }

    func testTiesBreakByBestRankNotModelCount() {
        let ranked = CompanyLeaderboard.rank([
            entry(2, "A", 70, organization: "Many"),
            entry(3, "B", 70, organization: "Many"),
            entry(4, "C", 70, organization: "Many"),
            entry(1, "Solo", 70, organization: "Few"),
        ])
        XCTAssertEqual(ranked.map(\.entry.name), ["Few", "Many"])
        XCTAssertEqual(ranked[0].components.count, 1)
        XCTAssertEqual(ranked[1].components.count, 3)
        XCTAssertEqual(ranked[0].entry.score, ranked[1].entry.score)
    }

    func testEqualScoreAndBestRankBreakByDisplayName() {
        let ranked = CompanyLeaderboard.rank([
            entry(1, "Zed", 40, organization: "Zeta"),
            entry(1, "Amy", 40, organization: "Alpha"),
        ])
        XCTAssertEqual(ranked.map(\.entry.name), ["Alpha", "Zeta"])
    }

    func testDisplayCapsAtTwentyCompanies() {
        let entries = (1...25).map { rank in
            entry(rank, "M\(rank)", Double(100 - rank), organization: "Org \(rank)")
        }
        let ranked = CompanyLeaderboard.rank(entries)
        XCTAssertEqual(ranked.count, 20)
        XCTAssertEqual(ranked.first?.entry.name, "Org 1")
        XCTAssertEqual(ranked.last?.entry.name, "Org 20")
        XCTAssertEqual(ranked.map(\.entry.rank), Array(1...20))
    }

    func testLogoFollowsTheBestRankedModel() {
        let best = URL(string: "https://example.com/best.png")!
        let other = URL(string: "https://example.com/other.png")!
        let ranked = CompanyLeaderboard.rank([
            entry(4, "Tail", 10, organization: "Qwen", logoURL: other),
            entry(1, "Top", 90, organization: "Alibaba", logoURL: best),
        ])
        XCTAssertEqual(ranked[0].entry.logoURL, best)
        XCTAssertEqual(ranked[0].entry.name, "Alibaba")
    }

    func testNonPositiveRankIsSkipped() {
        let ranked = CompanyLeaderboard.rank([
            entry(0, "Zero", 100, organization: "Zero"),
            entry(1, "One", 10, organization: "One"),
        ])
        XCTAssertEqual(ranked.map(\.entry.name), ["One"])
    }

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
            let standing = try! XCTUnwrap(ranked.first)
            XCTAssertEqual(standing.entry.name, sample.display, sample.key)
            XCTAssertEqual(standing.entry.organization, sample.display, sample.key)
            XCTAssertEqual(
                OrganizationLogoCatalog.resolvedKey(
                    organization: standing.entry.organization,
                    modelName: standing.entry.name
                ),
                sample.key,
                sample.key
            )
            XCTAssertEqual(
                OrganizationLogoCatalog.normalizedKey(standing.entry.name),
                sample.key,
                sample.key
            )
            XCTAssertEqual(
                PurchaseLinkCatalog.links(
                    forOrganization: standing.entry.organization,
                    modelName: standing.entry.name
                ),
                PurchaseLinkCatalog.links(
                    forOrganization: sample.organization,
                    modelName: "Model"
                ),
                sample.key
            )
            XCTAssertEqual(
                OrganizationRegion.isChinese(
                    standing.entry.organization,
                    modelName: standing.entry.name
                ),
                OrganizationRegion.isChinese(sample.organization, modelName: "Model"),
                sample.key
            )
        }
        XCTAssertFalse(PurchaseLinkCatalog.links(forOrganization: "Microsoft AI").isEmpty)
        XCTAssertNotEqual(
            PurchaseLinkCatalog.links(forOrganization: "Microsoft AI"),
            PurchaseLinkCatalog.links(forOrganization: "Microsoft")
        )
    }

    func testGroupingTitlesAndPreference() {
        XCTAssertEqual(LeaderboardGrouping.allCases, [.model, .company])
        XCTAssertEqual(LeaderboardGrouping.model.title, "模型")
        XCTAssertEqual(LeaderboardGrouping.company.title, "公司")

        let suite = "GroupingPreferenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(GroupingPreference.load(from: defaults), .model)

        GroupingPreference.save(.company, to: defaults)
        XCTAssertEqual(GroupingPreference.load(from: defaults), .company)

        defaults.set("not-a-grouping", forKey: GroupingPreference.userDefaultsKey)
        XCTAssertEqual(GroupingPreference.load(from: defaults), .model)
        XCTAssertNil(defaults.string(forKey: GroupingPreference.userDefaultsKey))
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
