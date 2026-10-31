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
         openness: LeaderboardOpennessFilter, language: AppLanguage, modelQuery: String = "", costOrder: Bool = false, speedOrder: Bool = false, priceAscending: Bool = false) {
        let base = LeaderboardPresentation.rows(board, grouping: grouping, filter: country, openness: openness)
        let unsearched = board?.kind.isPrice == true ? LeaderboardPresentation.priceOrdered(base, ascending: priceAscending) : base
        let showCost = board?.kind.supportsAACost == true && costOrder
        let showSpeed = board.map { LeaderboardPresentation.supportsAASpeed($0.kind) && speedOrder } ?? false
        leaderScore = showCost ? unsearched.compactMap(\.taskCostUSD).filter { $0.isFinite && $0 >= 0 }.max() : showSpeed ? unsearched.compactMap(\.speed).max() : unsearched.map(\.score).max()
        let matches = LeaderboardPresentation.modelNameMatcher(modelQuery)
        rows = unsearched.filter { matches($0.name) }
        let values = rows.flatMap { row in
            let first = showSpeed ? LeaderboardPresentation.speedText(row.speed) : showCost ? LeaderboardPresentation.taskCostText(row.taskCostUSD) : LeaderboardPresentation.scoreText(row.score, kind: board?.kind ?? .artificialAnalysis)
            if board?.kind.isPrice == true || (board?.kind == .openRouterUsage && showCost) {
                return [LeaderboardPresentation.tokenPriceLine(showCost ? row.taskCostUSD : row.score, output: false, language: language),
                        LeaderboardPresentation.tokenPriceLine(row.outputPriceUSD, output: true, language: language)]
            }
            return [first]
        }
        scoreWidthReference = values.max { $0.count < $1.count } ?? "0.0"
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
