import { readBounded } from './arena-dataset.mjs'
import { parseBoard } from './parser.mjs'

export function attachGeneralTaskCosts(board, costBoard) {
  if (board?.kind !== 'artificialAnalysis' || costBoard?.kind !== board.kind) return board
  const costs = new Map()
  for (const entry of costBoard.entries ?? []) {
    if (typeof entry.name !== 'string' || !Number.isFinite(entry.score)) continue
    const key = `${entry.name}\0${entry.score}`
    // Never guess when the official page repeats the same identity.
    costs.set(key, costs.has(key) ? null : entry)
  }
  return { ...board, entries: board.entries.map(entry => {
    const value = costs.get(`${entry.name}\0${entry.score}`)
    return value ? { ...entry, ...(Number.isFinite(value.taskCostUSD) && value.taskCostUSD >= 0 && { taskCostUSD: value.taskCostUSD }), ...(Number.isFinite(value.speed) && value.speed > 0 && { speed: value.speed }) } : entry
  }) }
}

export async function loadAAGeneralCosts({ now = Date.now(), fetcher = fetch, signal = AbortSignal.timeout(18000) } = {}) {
  const response = await fetcher('https://artificialanalysis.ai/models/', { signal, redirect: 'error' })
  const html = (await readBounded(response, 8 * 1024 * 1024)).toString('utf8')
  const board = parseBoard('artificialAnalysis', html, now)
  if (!board.entries.some(entry => Number.isFinite(entry.taskCostUSD))) throw new Error('AA task costs unavailable')
  return board
}

export async function loadConfiguredAAGeneralCosts({ now = Date.now(), fetcher = fetch, environment = process.env } = {}) {
  if (!environment.ARENA_COLLECTOR_ENDPOINT) return loadAAGeneralCosts({ now, fetcher })
  const endpoint = new URL(environment.ARENA_COLLECTOR_ENDPOINT)
  if (endpoint.protocol !== 'https:' || endpoint.username || endpoint.password || endpoint.pathname !== '/' || endpoint.search || endpoint.hash || endpoint.port
    || !endpoint.hostname.endsWith('.ap-southeast-1.fcapp.run') || !/^[A-Za-z0-9_-]{43}$/.test(environment.ARENA_COLLECTOR_TOKEN ?? '')) throw new Error('Invalid collector configuration')
  const response = await fetcher(new URL('/v1/aa-general-costs', endpoint), { redirect: 'error', signal: AbortSignal.timeout(22000), headers: { 'x-benchgauge-collector-key': environment.ARENA_COLLECTOR_TOKEN } })
  const board = JSON.parse((await readBounded(response, 1024 * 1024)).toString('utf8'))
  const fetched = Date.parse(board.fetchedAt)
  if (board.kind !== 'artificialAnalysis' || !Number.isFinite(fetched) || fetched > now + 300000 || fetched < now - 3600000
    || !Array.isArray(board.entries) || board.entries.length < 20 || board.entries.length > 10000
    || !board.entries.every(entry => typeof entry.name === 'string' && Number.isFinite(entry.score)
      && (entry.taskCostUSD == null || Number.isFinite(entry.taskCostUSD) && entry.taskCostUSD >= 0)
      && (entry.speed == null || Number.isFinite(entry.speed) && entry.speed > 0))) throw new Error('Invalid AA task costs')
  return board
}
