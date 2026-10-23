import assert from 'node:assert/strict'
import test from 'node:test'
import { createBoardStore, readCachedBoard } from '../src/services/boards.js'

const kind = 'artificialAnalysis'
const board = (fields = {}) => ({ kind, fetchedAt: '2026-10-13T12:00:00Z',
  entries: [{ rank: 1, name: 'Public model', score: 90, organization: 'A' }], ...fields })
function harness(saved = {}, { storageFails = false } = {}) {
  const requests = []; const writes = []
  const platform = {
    getStorageSync() { if (storageFails) throw new Error('Storage denied'); return saved },
    setStorageSync(key, value) { if (storageFails) throw new Error('Storage full'); writes.push(JSON.parse(JSON.stringify(value))) },
    request(options) {
      const task = { aborted: false, abort() { this.aborted = true; options.fail(); options.complete() } }
      requests.push({ options, task }); return task
    },
  }
  const store = createBoardStore({ platform, endpoint: 'https://shared.example' })
  const respond = (index, value, statusCode = 200) => {
    requests[index].options.success({ statusCode, data: value }); requests[index].options.complete()
  }
  return { store, requests, writes, respond }
}
test('cold start reads valid offline snapshots and ignores corrupt cache independently', () => {
  const h = harness({ [kind]: board(), arenaText: { kind: 'wrong' } })
  assert.equal(h.store.read(kind).entries[0].name, 'Public model')
  assert.equal(h.store.read('arenaText'), null)
  assert.equal(h.requests.length, 0)
})
test('agreement cache reads handle unknown, missing, corrupt and unavailable snapshots offline', () => {
  const platform = { getStorageSync: () => ({ [kind]: board() }) }
  assert.equal(readCachedBoard(platform, kind).entries[0].name, 'Public model')
  assert.equal(readCachedBoard(platform, 'unknown'), null)
  assert.equal(readCachedBoard(platform, 'arenaText'), null)
  platform.getStorageSync = () => ({ [kind]: { kind: 'wrong' } })
  assert.equal(readCachedBoard(platform, kind), null)
  platform.getStorageSync = () => { throw Error('Storage denied') }
  assert.equal(readCachedBoard(platform, kind), null)
})
test('deduplicated reads only contact the shared GET API and preserve its timestamps', async () => {
  const h = harness(); const first = h.store.fetch(kind); const second = h.store.fetch(kind)
  assert.equal(first, second); assert.equal(h.requests.length, 1)
  assert.equal(h.requests[0].options.url, `https://shared.example/v1/boards/${kind}`)
  assert.equal(h.requests[0].options.method, 'GET')
  h.respond(0, { board: board() })
  assert.equal((await first).fetchedAt, '2026-10-13T12:00:00Z')
  assert.equal((await second).sourceUpdatedAt, undefined)
  assert.equal(h.writes.length, 1)
})
test('network, server, empty and invalid responses retain useful cached rows and permit retry', async () => {
  const h = harness({ [kind]: board() })
  for (const response of [{ status: 503, data: {} }, { status: 200, data: { board: null } },
    { status: 200, data: { board: board({ entries: [] }) } }]) {
    const pending = h.store.fetch(kind); const index = h.requests.length - 1
    h.respond(index, response.data, response.status)
    await assert.rejects(pending)
    assert.equal(h.store.read(kind).entries.length, 1)
  }
  const pending = h.store.fetch(kind); h.requests.at(-1).options.fail()
  await assert.rejects(pending)
  assert.equal(h.store.read(kind).fetchedAt, board().fetchedAt)
})
test('a late stale shared response never replaces a newer saved publication', async () => {
  const cached = board({ sourceUpdatedAt: '2026-10-13T11:00:00Z' })
  const h = harness({ [kind]: cached }); const pending = h.store.fetch(kind)
  h.respond(0, { board: board({ fetchedAt: '2026-10-14T12:00:00Z' }) })
  assert.equal((await pending).sourceUpdatedAt, cached.sourceUpdatedAt)
  assert.equal(h.writes.length, 0)
})
test('independent concurrent boards merge cache without overwriting the first completed source', async () => {
  const h = harness(); const a = h.store.fetch(kind); const b = h.store.fetch('arenaText')
  h.respond(1, { board: { ...board(), kind: 'arenaText' } })
  await b
  h.respond(0, { board: board() }); await a
  assert.deepEqual(Object.keys(h.writes.at(-1)).sort(), ['arenaText', kind].sort())
})
test('storage failures do not stop valid network data and page disposal aborts owned requests', async () => {
  const h = harness({}, { storageFails: true }); const pending = h.store.fetch(kind)
  h.respond(0, { board: board() }); assert.equal((await pending).entries.length, 1)
  const other = h.store.fetch('arenaText'); h.store.dispose()
  await assert.rejects(other); assert.equal(h.requests[1].task.aborted, true)
  await assert.rejects(h.store.fetch(kind), /disposed/)
  await assert.rejects(h.store.fetch('constructor'), /Unknown/)
})
