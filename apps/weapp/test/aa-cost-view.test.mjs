import test from 'node:test'
import assert from 'node:assert/strict'
import { visibleRows } from '../src/core/leaderboard.js'

for (const kind of ['artificialAnalysis', 'artificialAnalysisCodingAgent', 'artificialAnalysisTextToImage', 'artificialAnalysisTextToVideo']) {
  test(`${kind} switches to one cost value and scales against the highest price`, () => {
    const board = { kind, entries: [
      { rank: 1, name: 'Expensive', score: 99, taskCostUSD: 10 },
      { rank: 2, name: 'Cheap', score: 90, taskCostUSD: 2.5 },
      { rank: 3, name: 'Unknown', score: 80 },
    ] }
    const score = visibleRows(board)
    assert.deepEqual(score.map(row => row.scoreText), ['99.0', '90.0', '80.0'])
    assert.ok(score.every(row => row.taskCostText === undefined))
    const costs = visibleRows(board, { sort: 'cost' })
    assert.deepEqual(costs.map(row => row.rank), [1, 2, 3])
    assert.deepEqual(costs.map(row => row.scoreText), ['$10.00', '$2.50', '—'])
    assert.deepEqual(costs.map(row => row.fillPercent), [100, 25, 0])
    assert.equal(costs[1].scoreShare, '25%')
  })
}
