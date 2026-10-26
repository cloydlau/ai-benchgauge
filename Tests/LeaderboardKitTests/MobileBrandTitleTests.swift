#if canImport(SwiftUI) && canImport(CoreText)
import Foundation
import Testing
#if canImport(AppKit)
import AppKit
import SwiftUI
#endif
@testable import LeaderboardKit

struct MobileBrandTitleTests {
    @Test func cubicFontOutlinesRetainTheirCurveAndPlacement() throws {
        let json = #"""
        {"baseSize":21,"layouts":{"test":{"width":6,"height":6,"logoWidth":0,"logoHeight":0,
        "logoTop":0,"logoShear":0,"glyphs":[{"key":"curve","x":2,"y":3,"width":4,"height":2.25}]}},
        "glyphs":{"curve":{"commands":[["M",0,0],["C",0,3,4,3,4,0],["Z"]]}}}
        """#
        let specification = try JSONDecoder().decode(MobileBrandArtwork.Specification.self, from: Data(json.utf8))
        let artwork = MobileBrandArtwork.make(key: "test", specification: specification)
        let expected = CGRect(x: 2, y: 3, width: 4, height: 2.25)
        #expect(artwork.letters.boundingBoxOfPath == expected)
        #expect(artwork.glyphBounds == [expected])
        #expect(artwork.letters.contains(CGPoint(x: 4, y: 4)))
        #expect(!artwork.letters.contains(CGPoint(x: 4, y: 5.5)))
    }

    @Test func malformedGlyphCommandsFailDecodingBeforePathConstruction() {
        for json in ["[]", "[\"X\"]", "[\"M\",0]", "[\"M\",0,0,1]", "[\"C\",0,\"bad\"]"] {
            #expect(throws: DecodingError.self) {
                _ = try JSONDecoder().decode(MobileBrandArtwork.Command.self, from: Data(json.utf8))
            }
        }
        #expect(MobileBrandMetrics.layoutWidth(language: .english) > 0)
        #expect(MobileBrandMetrics.inkHeight(language: .english) > 0)
    }
    #if canImport(AppKit)
    @MainActor @Test func mobileTitlesRenderTheirOfflineInkInBothThemesAtEverySize() throws {
        _ = NSApplication.shared
        let standard = NSHostingView(rootView: MobileBrandTitle(language: .english))
        #expect(standard.fittingSize.width > 100)
        for language in AppLanguage.allCases {
            for scheme in [ColorScheme.light, .dark] {
                for size: CGFloat in [14, 21, 32] {
                    let title = NSHostingView(rootView: MobileBrandTitle(language: language, fontSize: size)
                        .environment(\.colorScheme, scheme))
                    let expected = CGSize(width: MobileBrandMetrics.layoutWidth(language: language, fontSize: size),
                        height: MobileBrandMetrics.inkHeight(language: language, fontSize: size))
                    #expect(abs(title.fittingSize.width - expected.width) < 1)
                    #expect(abs(title.fittingSize.height - expected.height) < 1)
                    title.frame = CGRect(origin: .zero, size: expected)
                    let bitmap = try #require(title.bitmapImageRepForCachingDisplay(in: title.bounds))
                    title.cacheDisplay(in: title.bounds, to: bitmap)
                    #expect(bitmap.pixelsWide > 30 && bitmap.pixelsHigh > 10)
                    #expect((0..<bitmap.pixelsWide).contains { x in
                        (0..<bitmap.pixelsHigh).contains { y in
                            (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0
                        }
                    })
                }
            }
        }
    }
    #endif

    @Test func englishRetainsTheSeparateIAndShearsOnlyTheNetworkA() {
        let artwork = MobileBrandArtwork.layout(language: .english)
        let layout = artwork.layout
        #expect(layout.glyphs.map(\.key) == ["en-I", "en-name"])
        #expect(artwork.glyphBounds.count == 2)
        let initialI = artwork.glyphBounds[0]
        #expect(initialI.width > 1 && initialI.height > 10)
        #expect(abs(layout.logoShear - tan(31 * .pi / 180)) < 0.000001)
        #expect(abs(initialI.maxY - layout.logoTop - layout.logoHeight) < 0.001)
        let rightInk = max(layout.logoWidth, layout.logoWidth * 0.7 + layout.logoHeight * layout.logoShear)
        #expect(rightInk < initialI.minX)
        #expect(initialI.maxX < artwork.glyphBounds[1].minX)
        #expect(artwork.letters.boundingBoxOfPath.maxX <= layout.width + 0.001)
        #expect(artwork.letters.boundingBoxOfPath.minY >= 0)
        #expect(artwork.letters.boundingBoxOfPath.maxY <= layout.height + 0.001)
    }

    @Test func bothChineseLanguagesShareTheOfflineArtworkAndEveryTitleScalesLinearly() {
        let simplified = MobileBrandArtwork.layout(language: .chinese)
        let traditional = MobileBrandArtwork.layout(language: .traditionalChinese)
        #expect(simplified.letters == traditional.letters)
        #expect(simplified.layout.logoShear == 0)
        for language in AppLanguage.allCases {
            let artwork = MobileBrandArtwork.layout(language: language)
            #expect(!artwork.letters.isEmpty)
            for size: CGFloat in [14, 21, 24, 32, 42] {
                #expect(abs(MobileBrandMetrics.layoutWidth(language: language, fontSize: size)
                    - artwork.layout.width * size / 21) < 0.001)
                #expect(abs(MobileBrandMetrics.inkHeight(language: language, fontSize: size)
                    - artwork.layout.height * size / 21) < 0.001)
            }
        }
    }
}
#endif
