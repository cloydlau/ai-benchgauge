// Generated from Calmmit; edit the shared source, then regenerate.
import Foundation

// Native adapter for cost-calculation.mjs. Keep rounding and nil semantics in sync.
enum CalmmitCostCalculation {
    static func developmentMonths(startedAt: Double, now: Double, meanMonthMilliseconds: Double) -> Int {
        guard startedAt.isFinite, now.isFinite, meanMonthMilliseconds.isFinite,
              meanMonthMilliseconds > 0 else { return 0 }
        return max(0, Int(floor((now - startedAt) / meanMonthMilliseconds + 0.5)))
    }

    static func estimatedCost(_ amount: Int?, roundingUnit: Int = 100) -> Int? {
        precondition(roundingUnit >= 100 && roundingUnit % 100 == 0)
        guard let amount else { return nil }
        let nonnegative = max(0, amount)
        return (nonnegative / roundingUnit + (nonnegative % roundingUnit == 0 ? 0 : 1)) * roundingUnit
    }

    static func itemAmount(_ amount: Int?, monthlyAmount: Int?, months: Int, roundingUnit: Int = 100) -> Int? {
        estimatedCost(monthlyAmount.map { $0 * months } ?? amount, roundingUnit: roundingUnit)
    }

    static func sumAmounts(_ amounts: [Int?]) -> Int {
        amounts.reduce(0) { $0 + (estimatedCost($1) ?? 0) }
    }
}
