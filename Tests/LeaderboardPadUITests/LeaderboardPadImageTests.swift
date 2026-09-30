import AppKit
import Foundation
import SwiftUI
import Testing
import LeaderboardKit
@testable import LeaderboardPadUI

@MainActor
@Test func leaderboardImagesRenderWideNarrowAndDarkLayouts() throws {
    _ = NSApplication.shared
    let name = "ipad-images-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    AppLanguage.chinese.save(to: defaults)
    let directory = FileManager.default.temporaryDirectory.appending(path: name)
    defer { try? FileManager.default.removeItem(at: directory) }
    let cache = LeaderboardCache(fileURL: directory.appending(path: "cache.json"))
    let boards = Dictionary(uniqueKeysWithValues: LeaderboardKind.allCases.map { kind in
        (kind, Leaderboard(kind: kind, title: "Fixture", fetchedAt: Date(timeIntervalSince1970: 1_790_726_400), entries: [
            LeaderboardEntry(rank: 1, name: "GPT-6.1 Sol", score: 91, organization: "OpenAI"),
            LeaderboardEntry(rank: 2, name: "Claude Fixture", score: 88, organization: "Anthropic"),
            LeaderboardEntry(rank: 3, name: "DeepSeek Fixture", score: 86, organization: "DeepSeek"),
        ]))
    })
    cache.save(LeaderboardSnapshot(boards: boards))
    let store = LeaderboardPadStore(defaults: defaults, cache: cache)
    let view = LeaderboardPadView(store: store)
    for (label, width, scheme) in [("wide-light", 1000.0, ColorScheme.light), ("narrow-light", 440.0, .light), ("wide-dark", 1000.0, .dark)] {
        let image = try #require(view.renderLeaderboardImage(width: width, scheme: scheme))
        #expect(image.width == Int(width * 2))
        #expect(image.height > 400)
        // ImageRenderer cannot rasterize some native interactive controls.
        // Its yellow disabled placeholders must never enter shared pictures.
        #expect(yellowPlaceholderPixels(in: image) == 0)
        if ProcessInfo.processInfo.environment["BENCHGAUGE_IPAD_PREVIEWS"] == "1" {
            let output = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appending(path: "work/ipad/previews")
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            let png = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
            try png.write(to: output.appending(path: "\(label).png"))
        }
    }
}

private func yellowPlaceholderPixels(in image: CGImage) -> Int {
    var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
    return bytes.withUnsafeMutableBytes { buffer in
        guard let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return -1 }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let pixels = buffer.bindMemory(to: UInt8.self)
        return stride(from: 0, to: pixels.count, by: 4).filter {
            pixels[$0] > 200 && pixels[$0 + 1] > 150 && pixels[$0 + 2] < 60
        }.count
    }
}
