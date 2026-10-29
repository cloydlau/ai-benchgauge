import test from 'node:test'
import assert from 'node:assert/strict'
import { attachGeneralTaskCosts, loadAAGeneralCosts } from '../fc/aa-general-cost.mjs'

test('general task costs join only exact benchmark names and scores, keeping zero and rejecting ambiguity', () => {
  const board = { kind: 'artificialAnalysis', entries: [
    { name: 'A', score: 60 }, { name: 'B', score: 50 }, { name: 'C', score: 40 }, { name: 'D', score: 30 },
  ] }
  const costs = { kind: board.kind, entries: [
    { name: 'A', score: 60, taskCostUSD: 0 }, { name: 'B', score: 49, taskCostUSD: 7 },
    { name: 'C', score: 40, taskCostUSD: 1 }, { name: 'C', score: 40, taskCostUSD: 2 },
    { name: 'D', score: 30, taskCostUSD: -1 },
  ] }
  assert.deepEqual(attachGeneralTaskCosts(board, costs).entries.map(row => row.taskCostUSD), [0, undefined, undefined, undefined])
  assert.deepEqual(board.entries.map(row => row.taskCostUSD), [undefined, undefined, undefined, undefined])
  assert.equal(attachGeneralTaskCosts(board, { kind: 'arenaText' }), board)
})

test('general cost loader requests only the fixed AA model page and validates real task metrics', async () => {
  const rows = Array.from({ length: 20 }, (_, i) => ({ name: `Model ${i}`, intelligenceIndex: 100 - i,
    intelligenceIndexCostPerTask: { cost: { total: i } } }))
  const html = `<script>self.__next_f.push([1,${JSON.stringify(JSON.stringify({ rows }))}])</script>`
  let requested
  const board = await loadAAGeneralCosts({ now: Date.parse('2026-10-28T00:00:00Z'), fetcher: async url => { requested = url; return new Response(html) } })
  assert.equal(requested, 'https://artificialanalysis.ai/models/')
  assert.equal(board.entries.length, 20); assert.equal(board.entries[0].taskCostUSD, 0)
  await assert.rejects(loadAAGeneralCosts({ fetcher: async () => new Response('not a leaderboard') }))
})
