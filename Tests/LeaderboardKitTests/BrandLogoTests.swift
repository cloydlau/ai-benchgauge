import Testing
@testable import LeaderboardKit
#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI
import AppKit

struct BrandLogoTests {
    @MainActor @Test func missingOrInvalidArtworkIsSafeAndBundledArtworkRenders() throws {
        _ = NSApplication.shared
        #expect(BrandLogo.loadImage(at: nil) == nil)
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let invalid = directory.appending(path: "invalid.png")
        try Data("invalid PNG".utf8).write(to: invalid)
        #expect(BrandLogo.loadImage(at: invalid) == nil)
        let blank = try #require(ImageRenderer(content: BrandLogo(image: nil).frame(width: 40, height: 40)).cgImage)
        #expect(blank.width == 40)
        let bundled = try #require(ImageRenderer(content: BrandLogo().frame(width: 40, height: 40)).cgImage)
        #expect(bundled.width == 40)
        let pixels = try #require(bundled.dataProvider?.data)
        #expect((pixels as Data).contains { $0 != 0 })
    }

    @MainActor @Test func englishTitleRendersAtHeaderSizesAndBothAlignments() throws {
        _ = NSApplication.shared
        for size: CGFloat in [12, 21] {
            for alignment in [VerticalAlignment.firstTextBaseline, .bottom] {
                for scheme in [ColorScheme.light, .dark] {
                    let title = HStack(alignment: alignment) {
                        EnglishBrandTitle(fontSize: size)
                        Text("Fixture")
                    }.frame(width: 300, height: 80).environment(\.colorScheme, scheme)
                    let image = try #require(ImageRenderer(content: title).cgImage)
                    #expect(image.width == 300)
                    #expect(image.height == 80)
                    let pixels = try #require(image.dataProvider?.data)
                    #expect((pixels as Data).contains { $0 != 0 })
                }
            }
        }
    }
}
#endif
