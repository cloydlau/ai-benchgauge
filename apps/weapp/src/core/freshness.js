export const boardFreshnessInterval = 24 * 60 * 60 * 1000
export const automaticRetryInterval = 5 * 60 * 1000

// Publication age and successful acquisition control request scheduling. The
// separately displayed content-change time must not cause repeated network checks.
export function shouldAutoRefresh(board, lastAttempt, now = Date.now()) {
  if (lastAttempt != null && now - lastAttempt >= 0 && now - lastAttempt < automaticRetryInterval) return false
  if (!board) return true
  const timestamp = Date.parse(board.sourceUpdatedAt || board.fetchedAt)
  return !Number.isFinite(timestamp) || now - timestamp >= boardFreshnessInterval
}
