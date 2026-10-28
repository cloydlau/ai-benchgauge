#if canImport(AppKit)
import AppKit
import CoreText
import SwiftUI
import Testing
@testable import LeaderboardKit

@MainActor
struct BrandHeadingTests {
    @Test func measuredTitleWidthMatchesItsNativeLayout() {
        _ = NSApplication.shared
        for size in [17.0, 21.0, 30.0] {
            let english = NSHostingView(rootView: EnglishBrandTitle(fontSize: size))
            #expect(abs(BrandTitleMetrics.layoutWidth(language: .english, fontSize: size) - english.fittingSize.width) < 1)
            let chinese = NSHostingView(rootView: ChineseBrandTitle())
            for language in [AppLanguage.chinese, .traditionalChinese] {
                // NSHostingView rounds its fitting size to display pixels;
                // the metric retains the fractional glyph width before scaling.
                #expect(abs(BrandTitleMetrics.layoutWidth(language: language, fontSize: size) - chinese.fittingSize.width * size / 21) < size / 21)
            }
        }
    }

    @Test func englishDesktopMatchesIOSAtEverySizeAndAlignment() throws {
        _ = NSApplication.shared
        for size in [21.0, 25.0, 32.0] {
            for alignment in [VerticalAlignment.top, .center, .bottom, .firstTextBaseline] {
                let before = NSHostingView(rootView: HStack(alignment: alignment, spacing: 6) {
                    MobileBrandTitle(language: .english, fontSize: size)
                    Text("Subtitle").font(.system(size: 12))
                })
                let after = NSHostingView(rootView: HStack(alignment: alignment, spacing: 6) {
                    EnglishBrandTitle(fontSize: size)
                    Text("Subtitle").font(.system(size: 12))
                })
                let expected = before.fittingSize
                #expect(abs(BrandTitleMetrics.layoutWidth(language: .english, fontSize: size)
                    - MobileBrandMetrics.layoutWidth(language: .english, fontSize: size)) < 0.001)
                #expect(abs(BrandTitleMetrics.inkHeight(language: .english, fontSize: size)
                    - MobileBrandMetrics.inkHeight(language: .english, fontSize: size)) < 0.001)
                #expect(abs(after.fittingSize.width - expected.width) < 0.01)
                #expect(abs(after.fittingSize.height - expected.height) < 0.01)
                after.frame = CGRect(origin: .zero, size: expected)
                let image = try #require(after.bitmapImageRepForCachingDisplay(in: after.bounds))
                after.cacheDisplay(in: after.bounds, to: image)
                #expect(image.pixelsWide > 100)
                before.frame = CGRect(origin: .zero, size: expected)
                let reference = try #require(before.bitmapImageRepForCachingDisplay(in: before.bounds))
                before.cacheDisplay(in: before.bounds, to: reference)
                #expect(image.representation(using: .png, properties: [:])
                    == reference.representation(using: .png, properties: [:]))
            }
        }
        let title = ChineseBrandLayout.make()
        for pair in zip(title.glyphBounds, title.glyphBounds.dropFirst()) {
            #expect(abs(pair.1.minX - pair.0.maxX - 2.5) < 0.001)
        }
    }

    @Test func headerArtworkIsOnlyTheNetworkWithoutOutsidePadding() throws {
        for name in ["header-logo", "header-logo-dark"] {
            let url = try #require(Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Brand"))
            let bitmap = try #require(NSBitmapImageRep(data: Data(contentsOf: url)))
            #expect(bitmap.pixelsWide == 284 && bitmap.pixelsHigh == 332)
            #expect(CGFloat(bitmap.pixelsWide) / CGFloat(bitmap.pixelsHigh) == BrandLogo.aspectRatio)
            for (x, y) in [(0, 0), (283, 0), (0, 331), (283, 331)] {
                #expect(try #require(bitmap.colorAt(x: x, y: y)).alphaComponent == 0)
            }
            for edge in [
                (0..<332).map { (0, $0) }, (0..<332).map { (283, $0) },
                (0..<284).map { ($0, 0) }, (0..<284).map { ($0, 331) },
            ] {
                #expect(edge.contains { bitmap.colorAt(x: $0.0, y: $0.1)!.alphaComponent > 0 })
            }
        }
    }
}
#endif
