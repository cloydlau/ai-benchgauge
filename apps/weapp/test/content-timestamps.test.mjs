import assert from 'node:assert/strict'
import test from 'node:test'
import { createBoardStore, readCachedBoard } from '../src/services/boards.js'
import { contentTimestamp, latestTimestamp, normalizeBoard } from '../src/core/leaderboard.js'
import { copy } from '../src/core/catalog.js'
import { shouldAutoRefresh } from '../src/core/freshness.js'

test('mini-program persists last new-data time through repeated reads and offline/cold starts', async () => {
  let saved = {}, respond
  const platform = {
    getStorageSync: () => saved,
    setStorageSync: (key, value) => { saved = structuredClone(value) },
    request(options) { respond = value => options.success({ statusCode: 200, data: { board: value } }); return {} },
  }
  const kind = 'epochECI', initial = '2026-10-27T00:00:00Z'
  let board = { kind, fetchedAt: initial, entries: [{ name: 'A', rank: 1, score: 100 }] }
  const store = createBoardStore({ platform, endpoint: 'https://example.test' })
  async function acquire() { const request = store.fetch(kind); respond(board); return request }
  assert.equal(contentTimestamp(await acquire()), initial)
  board = { ...board, fetchedAt: '2026-10-28T00:00:00Z' }
  assert.equal(contentTimestamp(await acquire()), initial)
  assert.equal(contentTimestamp(readCachedBoard(platform, kind)), initial)
  board = { ...board, fetchedAt: '2026-10-29T00:00:00Z', entries: [{ ...board.entries[0], score: 101 }] }
  assert.equal(contentTimestamp(await acquire()), board.fetchedAt)
  const cold = createBoardStore({ platform, endpoint: 'https://example.test' })
  assert.equal(contentTimestamp(cold.read(kind)), board.fetchedAt)
  // The server may have observed the content change before this device saw it.
  board = { ...board, fetchedAt: '2026-10-30T00:00:00Z', contentUpdatedAt: '2026-10-28T12:00:00Z' }
  assert.equal(contentTimestamp(await acquire()), board.contentUpdatedAt)
  board = { ...board, fetchedAt: initial, contentUpdatedAt: initial, entries: [{ ...board.entries[0], score: 80 }] }
  assert.equal(contentTimestamp(await acquire()), '2026-10-28T12:00:00Z')
})

test('timestamps validate independently and publication labels retain priority', () => {
  const board = { kind: 'epochECI', fetchedAt: '2026-10-28T00:00:00Z', contentUpdatedAt: '2026-10-27T00:00:00Z',
    entries: [{ name: 'A', rank: 1, score: 100 }] }
  assert.equal(latestTimestamp(normalizeBoard(board, board.kind)), board.contentUpdatedAt)
  assert.equal(shouldAutoRefresh(board, null, Date.parse(board.fetchedAt)), false, 'Old content alone does not trigger more network requests')
  const published = { ...board, sourceUpdatedAt: '2026-10-26T00:00:00Z' }
  assert.equal(latestTimestamp(normalizeBoard(published, board.kind)), published.sourceUpdatedAt)
  for (const contentUpdatedAt of ['invalid', '2026-10-29T00:00:00Z']) {
    assert.throws(() => normalizeBoard({ ...board, contentUpdatedAt }, board.kind), /Invalid content update time/)
  }
  for (const [index, phrase] of ['unchanged', '没有变化', '沒有變化'].entries()) {
    assert.ok(copy.timeExplanation[index].includes(phrase))
  }
})
