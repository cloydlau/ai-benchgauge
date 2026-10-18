import Foundation
import LeaderboardKit

/// Immutable data shared by the visible cells. Formatting and company sorting
/// happen when data or preferences change, never once per cell or scroll frame.
@MainActor
final class PadRowPresentation {
    let rows: [LeaderboardEntry]
    let scoreWidthReference: String
    let countries: [LeaderboardCountryFilter]
    let leaderScore: Double?

    init(board: Leaderboard?, grouping: LeaderboardGrouping, country: LeaderboardCountryFilter,
         openness: LeaderboardOpennessFilter, language: AppLanguage, modelQuery: String = "") {
        let unsearched = LeaderboardPresentation.rows(board, grouping: grouping, filter: country, openness: openness)
        leaderScore = board?.kind == .epochECI ? nil : unsearched.first?.score
        rows = grouping == .company ? unsearched : unsearched.filter { LeaderboardPresentation.modelNameMatches($0.name, query: modelQuery) }
        scoreWidthReference = rows.map {
            $0.score.formatted(.number.grouping(.never).precision(.fractionLength(board?.kind == .epochECI ? 2 : 1)).locale(language.locale))
        }.max { $0.count < $1.count } ?? "0.0"
        countries = LeaderboardPresentation.countryFilters(board)
    }
    private init(rows: [LeaderboardEntry], scoreWidthReference: String, countries: [LeaderboardCountryFilter], leaderScore: Double?) {
        self.rows = rows
        self.scoreWidthReference = scoreWidthReference
        self.countries = countries
        self.leaderScore = leaderScore
    }
    func page(_ range: Range<Int>) -> PadRowPresentation {
        PadRowPresentation(rows: Array(rows.dropFirst(range.lowerBound).prefix(range.count)),
            scoreWidthReference: scoreWidthReference, countries: countries, leaderScore: leaderScore)
    }
}
