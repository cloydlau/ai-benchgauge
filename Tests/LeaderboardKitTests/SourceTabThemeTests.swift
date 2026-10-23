import Testing
import LeaderboardKit

@Test func nativeSourceTabsKeepEachBrandsColorsAcrossCategoriesAndAppearances() {
    let brands: [([LeaderboardKind], [String], [String])] = [
        ([.artificialAnalysis, .artificialAnalysisCodingAgent, .artificialAnalysisTextToImage, .artificialAnalysisTextToVideo],
         ["#8842FD", "#FFFFFF", "#8842FD"], ["#C394FF", "#43003B", "#C394FF"]),
        ([.arenaText, .codeArenaWebDev, .arenaTextToImage, .arenaTextToVideo],
         ["#1A1919", "#FCFAF7", "#1A1919"], ["#FCFAF7", "#1A1919", "#FCFAF7"]),
        ([.epochECI], ["#70EFD1", "#072B33", "#026B70"], ["#70EFD1", "#072B33", "#70EFD1"]),
        ([.openRouterUsage], ["#7624F4", "#FCFCFE", "#7624F4"], ["#C8FF00", "#03080A", "#C8FF00"]),
        ([.vercelUsage], ["#000000", "#FFFFFF", "#000000"], ["#FFFFFF", "#000000", "#FFFFFF"])
    ]
    #expect(Set(brands.flatMap { $0.0 }) == Set(LeaderboardCategory.allCases.flatMap(\.boardKinds)))
    for (kinds, light, dark) in brands {
        for kind in kinds {
            let lightPalette = SourceTabTheme.palette(for: kind, dark: false)
            let darkPalette = SourceTabTheme.palette(for: kind, dark: true)
            #expect([lightPalette.background, lightPalette.foreground, lightPalette.accent] == light)
            #expect([darkPalette.background, darkPalette.foreground, darkPalette.accent] == dark)
        }
    }
}

@Test func legacyDisabledSourceDoesNotInheritAnActiveSourcesBrand() {
    let light = SourceTabTheme.palette(for: .cloudbaseUsage, dark: false)
    let dark = SourceTabTheme.palette(for: .cloudbaseUsage, dark: true)
    #expect([light.background, light.foreground, light.accent] == ["#414D5C", "#FFFFFF", "#414D5C"])
    #expect([dark.background, dark.foreground, dark.accent] == ["#D1DCE8", "#101216", "#D1DCE8"])
    #expect(light != dark)
    #expect(!LeaderboardCategory.usage.boardKinds.contains(.cloudbaseUsage))
}
