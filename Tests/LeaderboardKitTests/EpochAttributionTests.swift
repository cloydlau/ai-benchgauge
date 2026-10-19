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
