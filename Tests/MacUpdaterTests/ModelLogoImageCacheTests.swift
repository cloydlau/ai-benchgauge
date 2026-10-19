import AppKit
import Testing
@testable import leaderboard_menu

@Suite(.serialized)
@MainActor
struct ModelLogoImageCacheTests {
    private func png(_ color: NSColor) throws -> Data {
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        color.setFill()
        NSRect(x: 0, y: 0, width: 64, height: 64).fill()
        NSGraphicsContext.restoreGraphicsState()
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }

    @Test func recycledCellsReuseTheDecodedBundledImage() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let logos = root.appending(path: "logos")
        try FileManager.default.createDirectory(at: logos, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = logos.appending(path: "fixture.png")
        try png(.blue).write(to: file)
        let cache = ModelLogoImageCache(resourceURL: root)
        let first = try #require(cache.bundledImage(key: "fixture"))
        try FileManager.default.removeItem(at: file)
        #expect(cache.bundledImage(key: "fixture") === first)
    }

    @Test func refreshedProviderImageUsesItsNewContents() throws {
        let cache = ModelLogoImageCache(resourceURL: nil)
        let blue = try png(.blue), red = try png(.red)
        let first = try #require(cache.image(data: blue))
        #expect(cache.image(data: Data(blue)) === first)
        let changed = try #require(cache.image(data: red))
        #expect(changed !== first)
        #expect(cache.image(data: red) === changed)
    }

    @Test func missingOrInvalidImagesStillAllowTheFallback() {
        let cache = ModelLogoImageCache(resourceURL: nil)
        #expect(cache.bundledImage(key: "missing") == nil)
        #expect(cache.image(data: Data("not an image".utf8)) == nil)
    }
}
