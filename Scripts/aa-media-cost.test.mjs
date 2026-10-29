import test from 'node:test'
import assert from 'node:assert/strict'
import { parseBoard } from '../fc/parser.mjs'

const page = entries => `<script>self.__next_f.push([1,${JSON.stringify(JSON.stringify({ entries }))}])</script>`
const now = Date.parse('2026-10-28T00:00:00Z')
test('AA image and video use their source price units and retain unknown values', () => {
  for (const [kind, field, expected] of [
    ['artificialAnalysisTextToImage', 'pricePer1kImages', [0.21, 0, undefined, undefined]],
    ['artificialAnalysisTextToVideo', 'pricePerMinute', [210, 0, undefined, undefined]],
  ]) {
    const prices = [210, 0, null, -1, ...Array(16).fill(10)]
    const records = prices.map((price, i) => ({ formatted: {}, values: { id: `id-${i}`, name: `Model ${i}`, elo: 1000 - i, [field]: price } }))
    const board = parseBoard(kind, page(records), now)
    assert.deepEqual(board.entries.slice(0, 4).map(row => row.taskCostUSD), expected)
  }
})

test('AA general uses the official index-level weighted task cost when available', () => {
  const records = Array.from({ length: 20 }, (_, i) => ({ name: `Model ${i}`, intelligenceIndex: 90 - i,
    intelligenceIndexCostPerTask: { cost: { total: i === 0 ? 2.34 : i === 1 ? 0 : null } }, price1mInputTokens: 123 }))
  const board = parseBoard('artificialAnalysis', page(records), now)
  assert.deepEqual(board.entries.slice(0, 3).map(row => row.taskCostUSD), [2.34, 0, undefined])
})
