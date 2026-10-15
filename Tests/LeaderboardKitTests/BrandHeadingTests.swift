#if canImport(AppKit)
import AppKit
import CoreText
import SwiftUI
import Testing
@testable import LeaderboardKit

@MainActor
struct BrandHeadingTests {
    @Test func replacingInitialKeepsNativeTitleAndBaselineFootprint() throws {
        _ = NSApplication.shared
        for size in [21.0, 25.0, 32.0] {
            for alignment in [VerticalAlignment.top, .center, .bottom, .firstTextBaseline] {
                let before = NSHostingView(rootView: HStack(alignment: alignment, spacing: 6) {
                    Text("AI BenchGauge").font(.custom("SnellRoundhand-Bold", fixedSize: size)).lineLimit(1)
                    Text("Subtitle").font(.system(size: 12))
                })
                let after = NSHostingView(rootView: HStack(alignment: alignment, spacing: 6) {
                    EnglishBrandTitle(fontSize: size)
                    Text("Subtitle").font(.system(size: 12))
                })
                let expected = before.fittingSize
                #expect(abs(after.fittingSize.width - expected.width) < 0.01)
                #expect(abs(after.fittingSize.height - expected.height) < 0.01)
                after.frame = CGRect(origin: .zero, size: expected)
                let image = try #require(after.bitmapImageRepForCachingDisplay(in: after.bounds))
                after.cacheDisplay(in: after.bounds, to: image)
                #expect(image.pixelsWide > 100)
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
