import test from 'node:test'
import assert from 'node:assert/strict'
import { visibleRows } from '../src/core/leaderboard.js'

test('AA speed changes values without changing rank order', () => {
  const rows = [{ rank: 1, name: 'First', score: 90, speed: 100 }, { rank: 2, name: 'Missing', score: 80 }, { rank: 3, name: 'Second', score: 70, speed: 200 }]
  let shown = visibleRows({ kind: 'artificialAnalysis', entries: rows }, { sort: 'speed' })
  assert.deepEqual(shown.map(row => row.rank), [1, 2, 3])
  assert.deepEqual(shown.map(row => row.scoreText), ['100', '—', '200'])
  assert.equal(shown[0].fillPercent, 50)
  shown = visibleRows({ kind: 'artificialAnalysisCodingAgent', entries: rows }, { sort: 'speed' })
  assert.deepEqual(shown.map(row => row.rank), [1, 2, 3])
})
