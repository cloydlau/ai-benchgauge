import test from 'node:test'
import assert from 'node:assert/strict'
import { openRouterPriceRows, priceBoard } from '../fc/price-catalog.mjs'
import { withContentTimestamp } from '../fc/domain.mjs'

test('OpenRouter text token prices convert to USD per million without treating free as missing', () => {
  const rows = openRouterPriceRows({ data: [
    { id: 'vendor/model', name: 'Model', architecture: { input_modalities: ['text'], output_modalities: ['text'] }, pricing: { prompt: '0.000001', completion: '5e-6' } },
    { id: 'vendor/free', name: 'Free', architecture: { input_modalities: ['text'], output_modalities: ['text'] }, pricing: { prompt: '0', completion: '0' } },
    { id: 'vendor/image', name: 'Image', architecture: { input_modalities: ['text'], output_modalities: ['image'] }, pricing: { prompt: '1', completion: '1' } },
    { id: 'vendor/invalid', name: 'Invalid', architecture: { input_modalities: ['text'], output_modalities: ['text'] }, pricing: { prompt: '-1', completion: '1' } },
  ] })
  assert.deepEqual(rows.map(row => [row.id, row.input, row.output]), [['vendor/model', 1, 5], ['vendor/free', 0, 0]])
  assert.throws(() => openRouterPriceRows({}), /Invalid/)
})

test('price board validates source and input/output quotes', () => {
  const row = { id: 'a/m', name: 'M', provider: 'OpenRouter', currency: 'USD', unit: 'per-million-tokens', input: 0, output: 2 }
  const catalog = { source: 'OpenRouter', fetchedAt: '2026-10-28T00:00:00Z', rows: [row] }
  assert.equal(priceBoard('openRouterPrice', catalog).entries[0].outputPriceUSD, 2)
  assert.throws(() => priceBoard('openRouterPrice', { ...catalog, source: 'other' }), /Invalid/)
  assert.throws(() => priceBoard('openRouterPrice', { ...catalog, rows: [{ ...row, output: -1 }] }), /Invalid/)
})

test('a change only to output prices advances the content timestamp', () => {
  const before = { kind: 'openRouterPrice', fetchedAt: '2026-10-28T00:00:00Z', entries: [{ rank: 1, name: 'M', score: 1, outputPriceUSD: 2 }] }
  const after = { ...before, fetchedAt: '2026-10-28T01:00:00Z', entries: [{ ...before.entries[0], outputPriceUSD: 3 }] }
  assert.equal(withContentTimestamp(after, before).contentUpdatedAt, after.fetchedAt)
})
