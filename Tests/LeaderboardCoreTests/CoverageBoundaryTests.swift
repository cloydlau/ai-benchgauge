import Foundation
import LeaderboardCore
import LeaderboardKit
import Testing

struct CoverageBoundaryTests {
    @Test func selectionTitlesAndMissingLeaderboardStates() throws {
        for category in LeaderboardCategory.allCases {
            #expect(category.id == category.rawValue)
            #expect(!category.title.isEmpty)
        }
        for grouping in LeaderboardGrouping.allCases { #expect(grouping.id == grouping.rawValue) }
        for mode in PanelMode.allCases {
            #expect(mode.id == mode.rawValue)
            for language in AppLanguage.allCases { #expect(!mode.title(language: language).isEmpty) }
        }
        for language in AppLanguage.allCases {
            for kind in LeaderboardKind.allCases {
                #expect(!LeaderboardPresentation.sourceHelp(kind, language: language, board: nil).isEmpty)
            }
            for filter in [LeaderboardCountryFilter.all, .unknown, .country(.china)] { #expect(!filter.title(language: language).isEmpty) }
        }
        #expect(LeaderboardPresentation.rows(nil, grouping: .model).isEmpty)
        #expect(LeaderboardPresentation.rows(nil, grouping: .company, filter: .unknown).isEmpty)
        #expect(LeaderboardPresentation.companies(nil, filter: .all).isEmpty)
        #expect(LeaderboardPresentation.countries(nil, grouping: .model).isEmpty)
        #expect(LeaderboardPresentation.countryFilters(nil) == [.all])
        #expect(!BrandFont.licenseText.isEmpty)
        #expect(try LeaderboardCache.defaultFileURL().lastPathComponent == "leaderboards.json")
    }

    @Test func modelEntryCanonicalIDsAndEffortFallbacks() {
        func entry(_ name: String) -> LeaderboardEntry { .init(rank: 1, name: name, score: 1) }
        #expect(ModelMatcher.canonicalModelID(for: entry("GPT-6 Astra (xhigh)")) == "gpt6astraxhigh")
        #expect(ModelMatcher.baseModelID(for: entry("GPT-6 Astra (xhigh)")) == "gpt6astra")
        #expect(ModelMatcher.baseModelID(for: entry("GPT-6 Astra")) == "gpt6astra")
        #expect(ModelMatcher.baseModelID(for: entry("max")) == "max")
        #expect(ModelMatcher.baseModelID(for: entry("")) == nil)
        #expect(ModelMatcher.canonicalModelID(from: "Model (0902) (Reasoning high) (2026)") == "modelhigh09022026")
    }

    @Test func uncapturedWebsiteQuotaIsFreshOnlyWhenItIsLive() {
        let now = Date(timeIntervalSince1970: 1000)
        func chip(_ cached: Bool) -> AccountQuotaChip {
            .init(id: "qwen", shortName: "Qwen", websiteURL: nil, kind: .kimi, isCurrent: true,
                  status: .qwenWebsite(.init(periodLabel: "month", remainingPercent: 50, resetsAt: nil, expiresAt: nil, isCached: cached)))
        }
        #expect(QuotaFreshness.updatedAt(afterRefreshing: [chip(false)], previous: nil, now: now) == now)
        #expect(QuotaFreshness.updatedAt(afterRefreshing: [chip(true)], previous: nil, now: now) == nil)
    }
}
