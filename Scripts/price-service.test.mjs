import test from 'node:test'
import assert from 'node:assert/strict'
import { createServer } from 'node:http'
import { once } from 'node:events'
import { handler } from '../fc/server.mjs'
import { collectorHandler } from '../fc/arena-collector.mjs'

async function serve(t, handler) {
  const server = createServer(handler); server.listen(0, '127.0.0.1'); await once(server, 'listening')
  t.after(() => { server.closeAllConnections(); server.close() })
  return `http://127.0.0.1:${server.address().port}`
}
test('price endpoints return OpenRouter prices and deduplicate concurrent loads', async t => {
  let calls = 0
  const rows = [{ id: 'a/m', name: 'M', provider: 'OpenRouter', currency: 'USD', unit: 'per-million-tokens', input: 0, output: 3 }]
  const url = await serve(t, handler(async () => ({}), { priceLoader: async () => { calls++; return { source: 'OpenRouter', fetchedAt: '2026-10-28T00:00:00Z', rows } } }))
  const board = (await fetch(url + '/v1/boards/openRouterPrice/refresh', { method: 'POST' }).then(r => r.json())).board
  assert.deepEqual(board.entries.map(row => [row.rank, row.provider, row.score, row.outputPriceUSD]), [[1, 'OpenRouter', 0, 3]])
  const replies = await Promise.all(Array.from({ length: 5 }, () => fetch(url + '/v1/prices/openRouter').then(r => r.json())))
  assert.equal(calls, 1); assert.ok(replies.every(row => row.source === 'OpenRouter'))
  assert.equal((await fetch(url + '/v1/prices/openRouter', { method: 'POST' })).status, 405)
})

test('collector protects the fixed OpenRouter price route and rejects arbitrary paths', async t => {
  const token = 'a'.repeat(43); let calls = 0
  const url = await serve(t, collectorHandler({ token, prices: async () => { calls++; return { source: 'OpenRouter', rows: [] } } }))
  assert.equal((await fetch(url + '/v1/openrouter-prices')).status, 403)
  const headers = { 'x-benchgauge-collector-key': token }
  assert.equal((await fetch(url + '/v1/openrouter-prices?url=https://example.com', { headers })).status, 404)
  assert.equal((await fetch(url + '/v1/openrouter-prices', { headers })).status, 200)
  assert.equal((await fetch(url + '/v1/openrouter-prices', { headers })).status, 200)
  assert.equal(calls, 1)
})
