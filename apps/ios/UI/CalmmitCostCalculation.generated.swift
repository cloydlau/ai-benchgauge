// Generated from Calmmit; edit the shared source, then regenerate.
import Foundation

// Native adapter for cost-calculation.mjs. Keep rounding and nil semantics in sync.
enum CalmmitCostCalculation {
    static func developmentMonths(startedAt: Double, now: Double, meanMonthMilliseconds: Double) -> Int {
        guard startedAt.isFinite, now.isFinite, meanMonthMilliseconds.isFinite,
              meanMonthMilliseconds > 0 else { return 0 }
        return max(0, Int(floor((now - startedAt) / meanMonthMilliseconds + 0.5)))
    }

    static func itemAmount(_ amount: Int?, monthlyAmount: Int?, months: Int) -> Int? {
        monthlyAmount.map { $0 * months } ?? amount
    }

    static func sumAmounts(_ amounts: [Int?]) -> Int {
        amounts.reduce(0) { $0 + ($1 ?? 0) }
    }
}
