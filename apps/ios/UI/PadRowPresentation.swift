import Foundation
import LeaderboardKit

/// Immutable data shared by the visible cells. Formatting and company sorting
/// happen when data or preferences change, never once per cell or scroll frame.
@MainActor
final class PadRowPresentation {
    let rows: [LeaderboardEntry]
    let scoreWidthReference: String
    let countries: [LeaderboardCountryFilter]

    init(board: Leaderboard?, grouping: LeaderboardGrouping, country: LeaderboardCountryFilter,
         openness: LeaderboardOpennessFilter, language: AppLanguage) {
        rows = LeaderboardPresentation.rows(board, grouping: grouping, filter: country, openness: openness)
        scoreWidthReference = rows.map {
            $0.score.formatted(.number.precision(.fractionLength(1)).locale(language.locale))
        }.max { $0.count < $1.count } ?? "0.0"
        countries = LeaderboardPresentation.countryFilters(board)
    }
}
