import Testing
import LeaderboardKit

@Test func nativeSourceTabsKeepEachBrandsColorsAcrossCategoriesAndAppearances() {
    let brands: [([LeaderboardKind], [String], [String])] = [
        ([.artificialAnalysis, .artificialAnalysisCodingAgent, .artificialAnalysisTextToImage, .artificialAnalysisTextToVideo],
         ["#8842FD", "#FFFFFF"], ["#C394FF", "#43003B"]),
        ([.arenaText, .codeArenaWebDev, .arenaTextToImage, .arenaTextToVideo],
         ["#1A1919", "#FCFAF7"], ["#FCFAF7", "#1A1919"]),
        ([.epochECI], ["#70EFD1", "#072B33"], ["#70EFD1", "#072B33"]),
        ([.openRouterUsage], ["#7624F4", "#FCFCFE"], ["#C8FF00", "#03080A"]),
        ([.vercelUsage], ["#000000", "#FFFFFF"], ["#FFFFFF", "#000000"])
    ]
    #expect(Set(brands.flatMap { $0.0 }) == Set(LeaderboardCategory.allCases.flatMap(\.boardKinds)))
    for (kinds, light, dark) in brands {
        for kind in kinds {
            let lightPalette = SourceTabTheme.palette(for: kind, dark: false)
            let darkPalette = SourceTabTheme.palette(for: kind, dark: true)
            #expect([lightPalette.background, lightPalette.foreground] == light)
            #expect([darkPalette.background, darkPalette.foreground] == dark)
        }
    }
}

@Test func legacyDisabledSourceDoesNotInheritAnActiveSourcesBrand() {
    let light = SourceTabTheme.palette(for: .cloudbaseUsage, dark: false)
    let dark = SourceTabTheme.palette(for: .cloudbaseUsage, dark: true)
    #expect([light.background, light.foreground] == ["#414D5C", "#FFFFFF"])
    #expect([dark.background, dark.foreground] == ["#D1DCE8", "#101216"])
    #expect(light != dark)
    #expect(!LeaderboardCategory.usage.boardKinds.contains(.cloudbaseUsage))
}
