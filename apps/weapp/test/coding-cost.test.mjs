import assert from 'node:assert/strict'
import test from 'node:test'
import { normalizeBoard, rankedEntries, visibleRows } from '../src/core/leaderboard.js'
import { planScreenshot, drawScreenshot } from '../src/core/screenshot.js'
import { copy, text } from '../src/core/catalog.js'
import { canvasHarness } from './helpers/canvas.mjs'

const kind = 'artificialAnalysisCodingAgent'
const board = { kind, fetchedAt: '2026-10-28T00:00:00Z', entries: [
  { rank: 1, name: 'Strong expensive', score: 90, organization: 'OpenAI', taskCostUSD: 9.48 },
  { rank: 2, name: 'Unknown price', score: 80, organization: 'Anthropic' },
  { rank: 3, name: 'Cheaper sibling', score: 70, organization: 'OpenAI', taskCostUSD: .005 },
  { rank: 4, name: 'Free measured run', score: 60, organization: 'Google', taskCostUSD: 0 },
] }

test('offline coding cost view retains rank order, search, companies and source scores', () => {
  const restored = normalizeBoard(JSON.parse(JSON.stringify(board)), kind)
  assert.deepEqual(rankedEntries(restored, { sort: 'cost' }).map(row => row.rank), [1, 2, 3, 4])
  assert.deepEqual(visibleRows(restored, { sort: 'cost' }).map(row => [row.rank, row.scoreText]),
    [[1, '$9.48'], [2, '—'], [3, '$0.005'], [4, '$0']])
  assert.deepEqual(rankedEntries(restored, { sort: 'cost', query: 'strong' }).map(row => row.rank), [1])
  assert.equal(visibleRows(restored, { grouping: 'company', sort: 'cost' }).find(row => row.name === 'OpenAI').scoreText, '$9.48')
  assert.deepEqual(rankedEntries({ ...restored, kind: 'arenaText' }, { sort: 'cost' }).map(row => row.rank), [1, 2, 3, 4])
  for (const invalid of [-1, NaN, Infinity, '0', true]) {
    assert.throws(() => normalizeBoard({ ...board, entries: [{ ...board.entries[0], taskCostUSD: invalid }] }, kind), /Invalid task cost/)
  }
})

test('coding image export shows selected task costs with explicit units and original ranks', () => {
  const h = canvasHarness()
  const model = { labels: Object.fromEntries(Object.entries(copy).map(([key, value]) => [key, text(value, 'en')])),
    language: 'en', dark: false, groupingLabel: 'Models', categoryLabel: 'Coding', boards: [{ kind,
      title: 'Artificial Analysis', tab: 'Tasks', time: 'Today', taskCostLabel: '$/task', filterLabel: 'Cost',
      rows: visibleRows(board, { sort: 'cost' }),
    }] }
  const plan = planScreenshot(h.context, model)
  drawScreenshot(h.context, model, plan, new Map())
  const labels = h.commands.filter(command => command[0] === 'fillText').map(command => command[1])
  for (const expected of ['$/task', '$9.48', '$0.005', '$0', '—']) assert.ok(labels.includes(expected), expected)
  for (const score of ['90.0', '60.0']) assert.ok(!labels.includes(score), score)
  assert.equal(plan.rows.length, 4)
  assert.equal(model.boards[0].rows[0].rank, 1)
})
