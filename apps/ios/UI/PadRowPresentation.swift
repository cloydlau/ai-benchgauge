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
            $0.score.formatted(.number.grouping(.never).precision(.fractionLength(1)).locale(language.locale))
        }.max { $0.count < $1.count } ?? "0.0"
        countries = LeaderboardPresentation.countryFilters(board)
    }
    private init(rows: [LeaderboardEntry], scoreWidthReference: String, countries: [LeaderboardCountryFilter]) {
        self.rows = rows
        self.scoreWidthReference = scoreWidthReference
        self.countries = countries
    }
    func page(_ range: Range<Int>) -> PadRowPresentation {
        PadRowPresentation(rows: Array(rows.dropFirst(range.lowerBound).prefix(range.count)),
            scoreWidthReference: scoreWidthReference, countries: countries)
    }
}
