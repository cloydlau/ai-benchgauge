import Testing
import LeaderboardKit

@Test func desktopBoardSelectionDefaultsAndRepairsObsoletePreferences() {
    #expect(DesktopBoardSelection.kinds(for: .general, saved: nil) == [.artificialAnalysis, .arenaText, .epochECI])
    #expect(DesktopBoardSelection.kinds(for: .general, saved: []) == LeaderboardCategory.general.boardKinds)
    #expect(DesktopBoardSelection.kinds(for: .general, saved: ["retired"]) == LeaderboardCategory.general.boardKinds)
    #expect(DesktopBoardSelection.kinds(for: .general, saved: ["epochECI", "retired", "epochECI"]) == [.epochECI])
    #expect(DesktopBoardSelection.kinds(for: .coding, saved: nil) == [.artificialAnalysisCodingAgent, .codeArenaWebDev])
    #expect(DesktopBoardSelection.kinds(for: .coding, saved: ["valsSWEbench"]) == [.valsSWEbench])
    #expect(DesktopBoardSelection.toggling(.valsSWEbench, in: .coding, saved: nil) == ["artificialAnalysisCodingAgent", "codeArenaWebDev", "valsSWEbench"])
}

@Test func desktopBoardSelectionKeepsOneAndRestoresCatalogOrder() {
    #expect(DesktopBoardSelection.toggling(.epochECI, in: .general, saved: ["epochECI"]) == ["epochECI"])
    #expect(DesktopBoardSelection.toggling(.artificialAnalysis, in: .general, saved: ["epochECI"]) == ["artificialAnalysis", "epochECI"])
    #expect(DesktopBoardSelection.toggling(.arenaText, in: .general, saved: nil) == ["artificialAnalysis", "epochECI"])
    #expect(DesktopBoardSelection.toggling(.arenaTextToImage, in: .general, saved: ["epochECI"]) == ["epochECI"])
}
