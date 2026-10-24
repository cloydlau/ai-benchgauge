export const boardFreshnessInterval = 24 * 60 * 60 * 1000
export const automaticRetryInterval = 5 * 60 * 1000

// Follow the same timestamp shown in the board header. A recent cache read
// does not make an old source publication fresh.
export function shouldAutoRefresh(board, lastAttempt, now = Date.now()) {
  if (lastAttempt != null && now - lastAttempt >= 0 && now - lastAttempt < automaticRetryInterval) return false
  if (!board) return true
  const timestamp = Date.parse(board.sourceUpdatedAt || board.fetchedAt)
  return !Number.isFinite(timestamp) || now - timestamp >= boardFreshnessInterval
}
