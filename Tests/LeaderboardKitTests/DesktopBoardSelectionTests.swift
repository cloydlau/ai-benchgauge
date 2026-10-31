import Foundation
import Testing
import LeaderboardKit

@Test func desktopBoardSelectionDefaultsAndRepairsObsoletePreferences() {
    #expect(DesktopBoardSelection.kinds(for: .general, saved: nil) == [.artificialAnalysis, .arenaText, .epochECI])
    #expect(DesktopBoardSelection.kinds(for: .general, saved: []) == [])
    #expect(DesktopBoardSelection.kinds(for: .general, saved: ["retired"]) == LeaderboardCategory.general.boardKinds)
    #expect(DesktopBoardSelection.kinds(for: .general, saved: ["epochECI", "retired", "epochECI"]) == [.epochECI])
    #expect(DesktopBoardSelection.kinds(for: .coding, saved: nil) == [.artificialAnalysisCodingAgent, .codeArenaWebDev, .epochSoftwareECI])
    #expect(!LeaderboardKind.allCases.contains(.valsSWEbench))
    #expect(DesktopBoardSelection.kinds(for: .coding, saved: ["valsSWEbench"]) == [.artificialAnalysisCodingAgent, .codeArenaWebDev, .epochSoftwareECI])
    #expect(DesktopBoardSelection.toggling(.valsSWEbench, in: .coding, selections: [:]) == [:])
}

@Test func retiredBoardDoesNotDiscardOtherCachedBoards() throws {
    let old = Leaderboard(kind: .valsSWEbench, title: "Old", entries: [])
    let current = Leaderboard(kind: .arenaText, title: "Current", entries: [])
    let snapshot = LeaderboardSnapshot(boards: [.valsSWEbench: old, .arenaText: current])
    let decoded = try JSONDecoder().decode(LeaderboardSnapshot.self, from: JSONEncoder().encode(snapshot))
    #expect(decoded.boards[.valsSWEbench] == old)
    #expect(decoded.boards[.arenaText] == current)
}

@Test func desktopBoardSelectionKeepsOneGloballyAndRestoresCatalogOrder() {
    let oneGeneral = ["general": ["epochECI"]]
    #expect(DesktopBoardSelection.toggling(.epochECI, in: .general, selections: oneGeneral)["general"] == [])
    #expect(DesktopBoardSelection.toggling(.artificialAnalysis, in: .general, selections: oneGeneral)["general"] == ["artificialAnalysis", "epochECI"])
    #expect(DesktopBoardSelection.toggling(.arenaText, in: .general, selections: [:])["general"] == ["artificialAnalysis", "epochECI"])
    #expect(DesktopBoardSelection.toggling(.arenaTextToImage, in: .general, selections: oneGeneral) == oneGeneral)
    var selections = Dictionary(uniqueKeysWithValues: LeaderboardCategory.allCases.map { ($0.rawValue, [String]()) })
    #expect(DesktopBoardSelection.normalized(selections).isEmpty)
    selections["speech"] = ["epochMathECI"]
    #expect(DesktopBoardSelection.categories(in: selections) == [.speech])
    #expect(DesktopBoardSelection.count(in: selections) == 1)
    #expect(DesktopBoardSelection.toggling(.epochMathECI, in: .speech, selections: selections) == selections)
    let restored = DesktopBoardSelection.toggling(.epochECI, in: .general, selections: selections)
    #expect(DesktopBoardSelection.categories(in: restored) == [.general, .speech])
}
