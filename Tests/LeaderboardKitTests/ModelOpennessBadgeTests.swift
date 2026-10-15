import LeaderboardKit
import Testing
#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI
import AppKit

struct ModelOpennessBadgeTests {
    @MainActor @Test func inheritedAppearanceMatchesExplicitAppearance() throws {
        _ = NSApplication.shared
        for language in AppLanguage.allCases {
            for openness: ModelOpenness? in [.open, .closed, nil] {
                for showsTitle in [true, false] {
                    var appearances: [Data] = []
                    for scheme in [ColorScheme.light, .dark] {
                        let inherited = ModelOpennessBadge(openness, language: language, showsTitle: showsTitle)
                            .frame(width: 100, height: 30).environment(\.colorScheme, scheme)
                        // An explicit appearance must override a conflicting environment.
                        let explicit = ModelOpennessBadge(openness, language: language,
                            colorScheme: scheme, showsTitle: showsTitle)
                            .frame(width: 100, height: 30)
                            .environment(\.colorScheme, scheme == .light ? .dark : .light)
                        let inheritedImage = try #require(ImageRenderer(content: inherited).cgImage)
                        let explicitImage = try #require(ImageRenderer(content: explicit).cgImage)
                        let inheritedPixels = try #require(inheritedImage.dataProvider?.data) as Data
                        let explicitPixels = try #require(explicitImage.dataProvider?.data) as Data
                        #expect(inheritedImage.width == 100)
                        #expect(inheritedImage.height == 30)
                        #expect(inheritedPixels.contains { $0 != 0 })
                        #expect(explicitPixels.contains { $0 != 0 })
                        // Native glyph antialiasing can differ between adjacent renders.
                        // Compare the rendered tint independently of those edge pixels.
                        let inheritedTint = tint(inheritedImage)
                        let explicitTint = tint(explicitImage)
                        for (actual, expected) in zip(inheritedTint, explicitTint) {
                            #expect(abs(actual - expected) < 0.01)
                        }
                        appearances.append(inheritedPixels)
                    }
                    #expect(appearances[0] != appearances[1])
                }
            }
        }
    }

    private func tint(_ image: CGImage) -> [Double] {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        pixels.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        var sums = [Double](repeating: 0, count: 4)
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            for component in 0..<4 { sums[component] += Double(pixels[offset + component]) }
        }
        return sums.prefix(3).map { $0 / max(1, sums[3]) }
    }
}
#endif
