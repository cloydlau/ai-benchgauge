import AppKit
import LeaderboardCore

/// Retains measurements, never views or account clients. Quota/task updates
/// must not re-rank every company in every board just to reopen the panel.
@MainActor
final class PanelLayoutCache {
    private struct WidthKey: Equatable {
        let revision: UInt64
        let language: AppLanguage
    }
    private struct HeightKey: Equatable {
        let revision: UInt64
        let width: CGFloat
        let maximumWidth: CGFloat
        let language: AppLanguage
        let category: LeaderboardCategory
        let grouping: LeaderboardGrouping
        let kinds: [LeaderboardKind]
        let countries: [LeaderboardKind: LeaderboardCountryFilter]
        let openness: [LeaderboardKind: LeaderboardOpennessFilter]
        let chips: [AccountQuotaChip]
        let emptyState: CCSwitchState?
        let quotaUpdatedAt: Date?
        let quotaUnavailable: Bool
        let connectingID: String?
        let panelMode: PanelMode
        let showsTasks: Bool
        let minute: Int
    }
    private var widthValue: (WidthKey, CGFloat)?
    private var heightValue: (HeightKey, CGFloat)?
    private(set) var widthMeasurementCount = 0
    private(set) var heightMeasurementCount = 0

    func columnWidth(revision: UInt64, language: AppLanguage, measure: () -> CGFloat) -> CGFloat {
        let key = WidthKey(revision: revision, language: language)
        if let (previous, value) = widthValue, previous == key { return value }
        let value = measure()
        widthValue = (key, value)
        widthMeasurementCount += 1
        return value
    }

    func height(for state: AppState, width: CGFloat, maximumWidth: CGFloat,
                now: Date = Date(), measure: () -> CGFloat) -> CGFloat {
        let key = HeightKey(revision: state.snapshotRevision, width: width, maximumWidth: maximumWidth,
            language: state.selectedLanguage, category: state.selectedCategory, grouping: state.selectedGrouping,
            kinds: state.visibleBoardKinds, countries: state.countryFilters, openness: state.opennessFilters,
            chips: state.quotaChips, emptyState: state.ccSwitchEmptyState, quotaUpdatedAt: state.quotaUpdatedAt,
            quotaUnavailable: state.quotaUnavailable, connectingID: state.connectingOpenAIProviderID,
            panelMode: state.panelMode, showsTasks: state.showsCodexTaskStatus,
            minute: Int(now.timeIntervalSince1970 / 60))
        if let (previous, value) = heightValue, previous == key { return value }
        let value = measure()
        heightValue = (key, value)
        heightMeasurementCount += 1
        return value
    }
}
