@testable import LeaderboardKit
import Testing
#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI
import AppKit
#endif

struct AppFeatureCopyTests {
    #if canImport(SwiftUI) && canImport(AppKit)
    @Test func emptySubtitleHasNoInkAndPreservesItsAllocatedHeight() {
        let artwork = FeatureSubtitleArtwork.make(rows: [], height: 24)
        #expect(artwork.letters.isEmpty)
        #expect(artwork.symbols.isEmpty)
        #expect(artwork.size == CGSize(width: 0, height: 24))
    }

    @MainActor @Test func nativeSubtitleRendersInEveryLanguageAndAppearance() throws {
        _ = NSApplication.shared
        for language in AppLanguage.allCases {
            for multiline in [false, true] {
                let height = BrandTitleMetrics.inkHeight(language: language)
                let artwork = FeatureSubtitleArtwork.make(language: language, height: height, multiline: multiline)
                let bounds = artwork.letters.boundingBoxOfPath.union(artwork.symbols.boundingBoxOfPath)
                #expect(abs(bounds.midY - height / 2) < 0.01)
                #expect(bounds.minY >= -0.01)
                #expect(bounds.maxY <= height + 0.01)
                let narrowWidth = artwork.size.width * 0.65
                let fitted = artwork.fitted(toWidth: narrowWidth)
                let fittedBounds = fitted.letters.boundingBoxOfPath.union(fitted.symbols.boundingBoxOfPath)
                #expect(fittedBounds.minX >= -0.01)
                #expect(fittedBounds.maxX <= narrowWidth + 0.01)
                #expect(abs(fittedBounds.midY - height / 2) < 0.01)
                #expect(abs(fittedBounds.height - bounds.height * 0.65) < 0.01)
                for scheme in [ColorScheme.light, .dark] {
                    for width in [CGFloat(320), ceil(narrowWidth)] {
                        let view = FeatureSubtitle(language: language, height: height, multiline: multiline)
                            .foregroundStyle(scheme == .dark ? Color.white : Color.black)
                            .frame(width: width, height: 28)
                            .environment(\.colorScheme, scheme)
                        let image = try #require(ImageRenderer(content: view).cgImage)
                        #expect(image.width == Int(width))
                        #expect(image.height == 28)
                        let data = try #require(image.dataProvider?.data)
                        #expect((data as Data).contains { $0 != 0 })
                        if let root = ProcessInfo.processInfo.environment["BENCHGAUGE_CAPTION_CAPTURE_ROOT"] {
                            let folder = URL(fileURLWithPath: root)
                            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                            let png = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
                            try png.write(to: folder.appendingPathComponent("\(language.rawValue)-\(multiline ? "mobile" : "desktop")-\(scheme)-\(Int(width)).png"))
                        }
                    }
                }
            }
        }
    }
    #endif

    @Test func featureLabelsAndDesktopAvailabilityFollowTheSelectedLanguage() {
        for language in AppLanguage.allCases {
            let subtitle = AppFeatureCopy.subtitle(language: language)
            let rows = AppFeatureCopy.subtitleRows(language: language)
            #expect(rows.count == 2)
            #expect(rows.joined(separator: language == .english ? " " : "") == subtitle)
            #expect(!subtitle.contains("\n"))
            #expect(rows[0].hasSuffix(language == .english ? ";" : "；"))
            let title = AppFeatureCopy.quotaTitle(language: language)
            let help = AppFeatureCopy.quotaHelpLabel(language: language)
            let message = AppFeatureCopy.quotaMessage(language: language)
            #expect(message.contains("PC"))
            #expect(!message.contains("Windows"))
            #expect(!message.contains("Mac"))
            #expect(message.contains(language.appName))
            switch language {
            case .english:
                #expect(subtitle.contains("Compare leaderboards"))
                #expect(title.lowercased().contains("quota"))
                #expect(help.contains("About"))
                #expect(message.contains("desktop app"))
            case .chinese:
                #expect(subtitle.contains("多榜"))
                #expect(title.contains("余量"))
                #expect(help.contains("了解"))
                #expect(message.contains("电脑"))
            case .traditionalChinese:
                #expect(subtitle.contains("多榜"))
                #expect(title.contains("餘量"))
                #expect(help.contains("瞭解"))
                #expect(message.contains("電腦"))
            }
        }
    }
}
