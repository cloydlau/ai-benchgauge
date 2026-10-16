@testable import LeaderboardKit
import Testing
#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI
import AppKit
#endif

struct AppFeatureCopyTests {
    #if canImport(SwiftUI) && canImport(AppKit)
    @MainActor @Test func nativeSubtitleRendersInEveryLanguageAndAppearance() throws {
        _ = NSApplication.shared
        for language in AppLanguage.allCases {
            let height = BrandTitleMetrics.inkHeight(language: language)
            let artwork = FeatureSubtitleArtwork.make(language: language, height: height)
            let bounds = artwork.letters.boundingBoxOfPath.union(artwork.symbols.boundingBoxOfPath)
            #expect(abs(bounds.minY) < 0.01)
            #expect(abs(bounds.maxY - height) < 0.01)
            for scheme in [ColorScheme.light, .dark] {
                let view = FeatureSubtitle(language: language, height: height)
                    .foregroundStyle(scheme == .dark ? Color.white : Color.black)
                    .frame(width: 320, height: 28)
                    .environment(\.colorScheme, scheme)
                let image = try #require(ImageRenderer(content: view).cgImage)
                #expect(image.width == 320)
                #expect(image.height == 28)
                let data = try #require(image.dataProvider?.data)
                #expect((data as Data).contains { $0 != 0 })
            }
        }
    }
    #endif

    @Test func featureLabelsAndDesktopAvailabilityFollowTheSelectedLanguage() {
        for language in AppLanguage.allCases {
            let subtitle = AppFeatureCopy.subtitle(language: language)
            let rows = AppFeatureCopy.subtitleRows(language: language)
            #expect(rows.count == 2)
            #expect(rows[0].hasSuffix(" &"))
            #expect(!rows[1].contains("&"))
            let title = AppFeatureCopy.quotaTitle(language: language)
            let help = AppFeatureCopy.quotaHelpLabel(language: language)
            let message = AppFeatureCopy.quotaMessage(language: language)
            #expect(message.contains("Mac"))
            #expect(message.contains("Windows"))
            #expect(message.contains(language.appName))
            switch language {
            case .english:
                #expect(subtitle.contains("Dual boards"))
                #expect(title.lowercased().contains("quota"))
                #expect(help.contains("About"))
                #expect(message.contains("desktop app"))
            case .chinese:
                #expect(subtitle.contains("双榜"))
                #expect(title.contains("余量"))
                #expect(help.contains("了解"))
                #expect(message.contains("电脑"))
            case .traditionalChinese:
                #expect(subtitle.contains("雙榜"))
                #expect(title.contains("餘量"))
                #expect(help.contains("瞭解"))
                #expect(message.contains("電腦"))
            }
        }
    }
}
