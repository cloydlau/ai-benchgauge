// Generated from Calmmit; edit the shared source, then regenerate.
// Portable calculation only: projects own their budgets, copy and presentation.
export const MEAN_MONTH_MS = (365.2425 / 12) * 24 * 60 * 60 * 1000

export function developmentMonths(
  startedAt,
  now = Date.now(),
  meanMonthMilliseconds = MEAN_MONTH_MS,
) {
  if (
    !Number.isFinite(startedAt) ||
    !Number.isFinite(now) ||
    !Number.isFinite(meanMonthMilliseconds) ||
    meanMonthMilliseconds <= 0
  )
    return 0
  return Math.max(0, Math.round((now - startedAt) / meanMonthMilliseconds))
}

export function nonnegativeInteger(value) {
  return Math.max(0, Math.round(Number(value) || 0))
}

// Estimates are no finer than hundreds of CNY; projects may choose a coarser unit.
// Keep unknown costs distinct from zero; engineering counters use nonnegativeInteger.
export function estimatedCost(value, roundingUnit = 100) {
  if (!Number.isSafeInteger(roundingUnit) || roundingUnit < 100 || roundingUnit % 100 !== 0)
    throw new RangeError('Cost estimates must use hundreds or coarser units')
  if (value == null) return value
  const amount = Number(value)
  return Number.isFinite(amount) ? Math.ceil(Math.max(0, amount) / roundingUnit) * roundingUnit : 0
}

export function costItemAmount(item, months) {
  // Accumulate first, rather than inflating every month independently.
  return estimatedCost(
    item.monthlyAmount == null ? item.amount : months * item.monthlyAmount,
    item.roundingUnit ?? 100,
  )
}

export function sumAmounts(amounts, normalize = false) {
  return amounts.reduce(
    (sum, amount) =>
      sum + (normalize ? nonnegativeInteger(estimatedCost(amount)) : (estimatedCost(amount) ?? 0)),
    0,
  )
}

export function calculateCosts(
  groups,
  { startedAt, now = Date.now(), normalizeAmounts = false } = {},
) {
  const months = developmentMonths(startedAt, now)
  const calculated = groups.map((group) => {
    const items = group.items.map((item) => ({ ...item, amount: costItemAmount(item, months) }))
    return {
      ...group,
      items,
      amount: sumAmounts(
        items.map((item) => item.amount),
        normalizeAmounts,
      ),
    }
  })
  return {
    months,
    groups: calculated,
    total: sumAmounts(calculated.map((group) => group.amount)),
    unaccounted: calculated.flatMap((group) => group.items).filter((item) => item.amount == null),
  }
}
