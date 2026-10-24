import AppKit
import Testing
import LeaderboardCore
@testable import leaderboard_menu

@Suite(.serialized) @MainActor
struct PanelLayoutCacheTests {
    @Test func widthMeasurementTracksDataAndLanguageRatherThanQuotaUpdates() {
        let cache = PanelLayoutCache()
        var calls = 0
        func value(_ revision: UInt64, _ language: AppLanguage) -> CGFloat {
            cache.columnWidth(revision: revision, language: language) { calls += 1; return CGFloat(calls * 10) }
        }
        #expect(value(1, .chinese) == 10)
        #expect(value(1, .chinese) == 10)
        #expect(value(1, .english) == 20)
        #expect(value(2, .english) == 30)
        #expect(cache.widthMeasurementCount == 3)
    }

    @Test func heightReusesIdenticalInputsButInvalidatesForWrappingFiltersAndTime() {
        let suite = "panel-layout.\(UUID())", defaults = UserDefaults(suiteName: suite)!
        let previousGrouping = GroupingPreference.load()
        defer { defaults.removePersistentDomain(forName: suite); GroupingPreference.save(previousGrouping) }
        let state = AppState(cache: LeaderboardCache(fileURL: FileManager.default.temporaryDirectory.appending(path: "\(UUID()).json")), defaults: defaults)
        state.applyVisualFixture(snapshot: .init(), chips: [], language: .chinese, errors: [:], emptyState: nil)
        defer { state.beginQuitting() }
        let cache = state.panelLayoutCache, date = Date(timeIntervalSince1970: 120)
        var calls = 0
        func height(_ width: CGFloat = 900, _ now: Date? = nil) -> CGFloat {
            cache.height(for: state, width: width, maximumWidth: 1100, now: now ?? date) { calls += 1; return CGFloat(calls) }
        }
        #expect(height() == 1)
        #expect(height() == 1)
        let revision = state.snapshotRevision
        state.applyVisualQuotaUpdate([])
        #expect(height() == 1)
        #expect(state.snapshotRevision == revision)
        state.applyVisualQuotaUpdate([.init(id: "test", shortName: "Provider", websiteURL: nil, kind: .claude, isCurrent: true, status: .pending)])
        #expect(height() == 2)
        #expect(height() == 2)
        #expect(height(800) == 3)
        state.selectCountryFilter(.country(.china), for: .artificialAnalysis)
        #expect(height(800) == 4)
        state.selectGrouping(.company)
        #expect(height(800) == 5)
        #expect(height(800, date.addingTimeInterval(60)) == 6)
        state.applyVisualFixture(snapshot: .init(), chips: [], language: .chinese, errors: [:], emptyState: nil)
        #expect(state.snapshotRevision > revision)
        #expect(height(800, date.addingTimeInterval(60)) == 7)
        #expect(cache.heightMeasurementCount == 7)
    }
}
