import Foundation
import Testing
import LeaderboardKit
@testable import LeaderboardPadUI

@MainActor @Test func mediaSelectionPersistsAndIsFrozenForExport() throws {
    let name = "media-selection-\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    CategoryPreference.save(.video, to: defaults)
    let service = LeaderboardService { _ in throw URLError(.resourceUnavailable) }
    let store = LeaderboardPadStore(defaults: defaults, service: service)
    store.selectMediaVariant(.artificialAnalysisImageToVideo, replacing: .artificialAnalysisTextToVideo)
    store.selectMediaVariant(.arenaVideoEditing, replacing: .arenaTextToVideo)
    #expect(store.visibleBoardKinds == [.artificialAnalysisImageToVideo, .arenaVideoEditing])
    store.selectMediaVariant(.arenaVideoEditing, replacing: .artificialAnalysisImageToVideo)
    #expect(store.visibleBoardKinds == [.artificialAnalysisImageToVideo, .arenaVideoEditing])
    let restored = LeaderboardPadStore(defaults: defaults, service: service)
    #expect(restored.visibleBoardKinds == store.visibleBoardKinds)
    let frozen = LeaderboardPadStore(exporting: restored)
    restored.selectMediaVariant(.artificialAnalysisTextToVideo, replacing: .artificialAnalysisImageToVideo)
    #expect(frozen.visibleBoardKinds == [.artificialAnalysisImageToVideo, .arenaVideoEditing])
    #expect(restored.visibleBoardKinds == [.artificialAnalysisTextToVideo, .arenaVideoEditing])
}
