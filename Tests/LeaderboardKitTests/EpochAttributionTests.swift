import Testing
import LeaderboardKit

@Test func epochDataAttributionIsBundledAndOnlyAppendedToItsOwnSourceHelp() {
    for language in AppLanguage.allCases {
        let notice = EpochAttribution.fullText(language: language)
        #expect(notice.contains("Epoch AI · Epoch Capabilities Index · CC BY 4.0"))
        #expect(notice.contains("https://epoch.ai/eci"))
        #expect(notice.contains("https://creativecommons.org/licenses/by/4.0/"))
        #expect(!EpochAttribution.changes(language: language).isEmpty)
        #expect(LeaderboardPresentation.sourceHelp(.epochECI, language: language, board: nil).contains(notice))
        #expect(!LeaderboardPresentation.sourceHelp(.artificialAnalysis, language: language, board: nil).contains("CC BY"))
        #expect(!LeaderboardPresentation.sourceHelp(.arenaText, language: language, board: nil).contains("CC BY"))
    }
}

@Test func sourceNameHelpIncludesCompleteOfflineTermsForItsOwnData() {
    for language in AppLanguage.allCases {
        let license = CCBYLicense.text(language: language)
        for kind in [LeaderboardKind.epochECI, .openRouterUsage, .vercelUsage] {
            let note = "Current \(kind.rawValue) snapshot"
            let board = Leaderboard(kind: kind, title: "Fixture", sourceNote: note, entries: [])
            let help = LeaderboardPresentation.sourceHelp(kind, language: language, board: board, includesAgreement: true)
            #expect(help.contains(license))
            if kind.isUsage { #expect(help.contains(note)) }
            #expect(LeaderboardPresentation.sourceAgreement(kind, language: language, board: nil)?.contains(license) == true)
        }
        let dataset = Leaderboard(kind: .arenaText, title: "Arena", sourceNote: ArenaAttribution.sourceURL, entries: [])
        #expect(LeaderboardPresentation.sourceAgreement(.arenaText, language: language, board: dataset)?.contains(license) == true)
        #expect(LeaderboardPresentation.sourceAgreement(.arenaText, language: language, board: nil) == nil)
        #expect(LeaderboardPresentation.sourceAgreement(.artificialAnalysis, language: language, board: nil) == nil)
        let cloud = Leaderboard(kind: .cloudbaseUsage, title: "Tencent", sourceNote: "Tencent current snapshot", entries: [])
        let notice = LeaderboardPresentation.sourceAgreement(.cloudbaseUsage, language: language, board: cloud)
        #expect(notice?.contains("Tencent current snapshot") == true)
        #expect(notice?.contains(license) == false)
        #expect(notice?.contains("creativecommons.org/licenses/") == false)
    }
}
