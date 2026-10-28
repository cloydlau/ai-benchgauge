#if canImport(SwiftUI) && canImport(AppKit)
import AppKit
import SwiftUI
import Testing
@testable import LeaderboardKit

@MainActor @Test func rankChangeBadgesRenderAcrossThemes() throws {
    _ = NSApplication.shared
    for scheme in [ColorScheme.light, .dark] {
        for change: LeaderboardRankChange? in [.init(isNew: true), .init(delta: 3), .init(delta: -2), nil] {
            let badge = LeaderboardRankChangeBadge(change, language: .english)
                .frame(width: 40, height: 20).environment(\.colorScheme, scheme)
            let image = try #require(ImageRenderer(content: badge).cgImage)
            #expect(image.width > 0 && image.height > 0)
        }
    }
}
#endif
