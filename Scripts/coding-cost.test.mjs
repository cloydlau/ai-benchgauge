import assert from 'node:assert/strict'
import test from 'node:test'
import { parseBoard } from '../fc/parser.mjs'
import { companyRows, orderByTaskCost, taskCostText, withContentTimestamp, withRankChanges } from '../fc/domain.mjs'

const kind = 'artificialAnalysisCodingAgent'
const now = Date.parse('2026-10-28T00:00:00Z')
const page = costs => {
  const entries = costs.map((cost, i) => ({ displayLabel: `Agent - Model ${i}`, indexScore: (90 - i) / 100,
    display: { creator: { agent: i % 2 ? 'Anthropic' : 'OpenAI' } }, hostModelSlug: `model-${i}`,
    ...(cost !== undefined && { mean: { costUsd: cost } }),
    sums: { costUsd: 99999 }, percentiles: { costUsd: { p50: 999 } },
    evals: [{ mean: { costUsd: 777 } }],
  }))
  return `<script>self.__next_f.push([1,${JSON.stringify(JSON.stringify({ entries }))}])</script>`
}

test('coding cost uses only the index-level mean, retains zero, and rejects malformed prices', () => {
  const board = parseBoard(kind, page([9.48, .005, 0, null, undefined, -1, '2', true, {}, 12.7]), now)
  assert.deepEqual(board.entries.map(row => row.taskCostUSD), [9.48, .005, 0, undefined, undefined, undefined, undefined, undefined, undefined, 12.7])
  assert.deepEqual(board.entries.map(row => row.rank), Array.from({ length: 10 }, (_, i) => i + 1))
  assert.ok(board.entries.every(row => row.score > 0))
})

test('cost ordering keeps capability rank, scores and movements, with missing last and stronger ties first', () => {
  const rows = parseBoard(kind, page([2, 0, 1, 1, null, .005, .0001, 10, null, 3]), now).entries
    .map(row => ({ ...row, rankChange: { delta: row.rank } }))
  const frozen = structuredClone(rows)
  const sorted = orderByTaskCost(rows, true)
  assert.deepEqual(sorted.map(row => row.rank), [2, 7, 6, 3, 4, 1, 10, 8, 5, 9])
  assert.deepEqual(rows, frozen)
  assert.deepEqual(sorted.find(row => row.rank === 1), frozen[0])
  assert.equal(orderByTaskCost(rows), rows)
  assert.deepEqual([undefined, NaN, Infinity, -1, null, '0', 0, .0001, .005, 9.48].map(taskCostText),
    ['—', '—', '—', '—', '—', '—', '$0', '<$0.001', '$0.005', '$9.48'])
})

test('company cost follows its strongest model, including unknown cost, rather than the cheapest sibling', () => {
  const rows = parseBoard(kind, page([9, null, 0, .1, 1, 2, 3, 4, 5, 6]), now).entries
  const companies = companyRows(rows)
  assert.equal(companies.find(row => row.name === 'OpenAI').taskCostUSD, 9)
  assert.equal(companies.find(row => row.name === 'Anthropic').taskCostUSD, undefined)
  assert.deepEqual(orderByTaskCost(companies, true).map(row => row.name), ['OpenAI', 'Anthropic'])
})

test('price changes advance content time without inventing capability movement', () => {
  const previous = parseBoard(kind, page(Array(10).fill(2)), now)
  const next = parseBoard(kind, page([3, ...Array(9).fill(2)]), now + 86400000)
  const result = withContentTimestamp(withRankChanges(next, previous), previous)
  assert.equal(result.contentUpdatedAt, next.fetchedAt)
  assert.ok(result.entries.every(row => !row.rankChange && !row.companyRankChange))
  const duplicate = { ...result, contentUpdatedAt: undefined, fetchedAt: new Date(now + 172800000).toISOString() }
  assert.equal(withContentTimestamp(duplicate, result).contentUpdatedAt, next.fetchedAt)
})
