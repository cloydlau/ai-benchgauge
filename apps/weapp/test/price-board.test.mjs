import test from 'node:test'
import assert from 'node:assert/strict'
import { priceBoard } from '../../../fc/price-catalog.mjs'
import { normalizeBoard, visibleRows } from '../src/core/leaderboard.js'
import { categories } from '../src/core/catalog.js'

test('price category shows OpenRouter input and output per million tokens', () => {
  assert.deepEqual(categories.slice(0, 3).map(category => category.id), ['usage', 'general', 'image'])
  const board = priceBoard('openRouterPrice', { source: 'OpenRouter', fetchedAt: '2026-10-28T00:00:00Z', rows: [
    { id: 'a/one', name: 'One', provider: 'OpenRouter', input: 2, output: 3, currency: 'USD', unit: 'per-million-tokens' },
    { id: 'a/two', name: 'Two', provider: 'OpenRouter', input: 1, output: 4, currency: 'USD', unit: 'per-million-tokens' },
  ] })
  const normalized = normalizeBoard(JSON.parse(JSON.stringify(board)), 'openRouterPrice')
  const rows = visibleRows(normalized)
  assert.deepEqual(rows.map(row => [row.name, row.scoreText, row.outputPriceText]), [
    ['One', '$2.00', '$3.00'], ['Two', '$1.00', '$4.00'],
  ])
  assert.deepEqual(rows.map(row => row.fillPercent), [100, 50])
  assert.deepEqual(visibleRows(normalized, { priceAscending: true }).map(row => [row.rank, row.name]), [[1, 'Two'], [2, 'One']])
  assert.deepEqual(rows.map(row => row.rank), [1, 2])
  assert.throws(() => normalizeBoard({ ...board, entries: [{ ...board.entries[0], outputPriceUSD: -1 }] }, 'openRouterPrice'), /Invalid output price/)
})


test('price direction handles zero and equal inputs without changing the input board', () => {
  const entries = [
    {rank: 1, name: 'Free', score: 0, outputPriceUSD: 0},
    {rank: 2, name: 'Low output', score: 3, outputPriceUSD: 2},
    {rank: 3, name: 'High output', score: 3, outputPriceUSD: 9},
  ]
  const board = {kind: 'openRouterPrice', entries}
  assert.deepEqual(visibleRows(board).map(x => x.name), ['High output', 'Low output', 'Free'])
  assert.deepEqual(visibleRows(board, {priceAscending: true}).map(x => x.name), ['Free', 'Low output', 'High output'])
  assert.deepEqual(entries.map(x => x.rank), [1, 2, 3])
})


test('OpenRouter usage toggles price and speed without changing usage ranks', () => {
  const board = { kind: 'openRouterUsage', entries: [
    { rank: 1, name: 'A', score: 12, taskCostUSD: 1, outputPriceUSD: 4, speed: 20 },
    { rank: 2, name: 'B', score: 8, taskCostUSD: 3, outputPriceUSD: 5, speed: 80 },
  ] };
  for (const sort of ['score', 'cost', 'speed']) assert.deepEqual(visibleRows(board, { sort }).map(row => row.rank), [1, 2]);
  assert.deepEqual(visibleRows(board, { sort: 'cost' }).map(row => [row.scoreText, row.outputPriceText]), [['$1.00', '$4.00'], ['$3.00', '$5.00']]);
  assert.deepEqual(visibleRows(board, { sort: 'speed' }).map(row => row.scoreText), ['20', '80']);
});


test('usage price rows reserve the second line for output in model and company views', () => {
  const board = { kind: 'openRouterUsage', entries: [
    { rank: 1, name: 'A', organization: 'Alpha', score: 10, taskCostUSD: 2, outputPriceUSD: 4 },
    { rank: 2, name: 'B', organization: 'Beta', score: 5, taskCostUSD: 1, outputPriceUSD: 3 },
  ] }
  for (const grouping of ['model', 'company']) {
    const prices = visibleRows(board, { grouping, sort: 'cost' })
    assert.deepEqual(prices.map(row => [row.scoreText, row.outputPriceText, row.scoreShare, row.fillPercent]),
      [['$2.00', '$4.00', '', 100], ['$1.00', '$3.00', '', 50]])
    assert.equal(visibleRows(board, { grouping, sort: 'score' })[1].scoreShare, '50%')
  }
})
