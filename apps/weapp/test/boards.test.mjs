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
    arrayBufferToBase64(value) { return Buffer.from(value).toString('base64') },
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
test('deduplicated refresh claims client-first acquisition and preserves shared timestamps', async () => {
  const h = harness(); const first = h.store.fetch(kind); const second = h.store.fetch(kind)
  assert.equal(first, second); assert.equal(h.requests.length, 1)
  assert.equal(h.requests[0].options.url, `https://shared.example/v1/boards/${kind}/refresh`)
  assert.equal(h.requests[0].options.method, 'POST')
  assert.equal(h.requests[0].options.header['X-BenchGauge-Acquisition'], 'client-first')
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

const tick = () => new Promise(resolve => setImmediate(resolve))
const grant = () => ({ token: 'A'.repeat(43), expiresAt: Date.now() + 90000, sourceURL: 'https://epoch.ai/data/eci_scores.csv',
  acquisition: { resources: [{ url: 'https://epoch.ai/data/eci_scores.csv', maxBytes: 8000000, accept: 'text/csv' }] } })
test('origin GET doubles as probe and uploads raw bytes before accepting server validation', async () => {
  const h = harness(); const painted = []; const promise = h.store.fetch('epochECI', value => painted.push(value))
  h.respond(0, { grant: grant(), board: board({ kind: 'epochECI' }) }); await tick()
  assert.equal(h.store.read('epochECI').entries.length, 1)
  assert.equal(painted.length, 1)
  assert.equal(h.requests.length, 2)
  assert.equal(h.requests[1].options.url, 'https://epoch.ai/data/eci_scores.csv')
  assert.equal(h.requests[1].options.method, 'GET')
  const bytes = new TextEncoder().encode('official raw csv').buffer
  h.respond(1, bytes); await tick()
  assert.match(h.requests[2].options.url, /epochECI\/acquire$/)
  assert.equal(Buffer.from(h.requests[2].options.data.resources[0].data, 'base64').toString(), 'official raw csv')
  h.respond(2, { board: board({ kind: 'epochECI', entries: [{ rank: 1, name: 'Validated', score: 91 }] }) })
  assert.equal((await promise).entries[0].name, 'Validated'); assert.equal(h.requests.length, 3)
})
test('blocked origin or rejected upload falls back using the same grant', async () => {
  for (const rejectedUpload of [false, true]) {
    const h = harness(); const promise = h.store.fetch('epochECI'); const g = grant()
    h.respond(0, { grant: g }); await tick()
    if (rejectedUpload) {
      h.respond(1, new TextEncoder().encode('blocked page').buffer); await tick()
      h.respond(2, {}, 422)
    } else h.requests[1].options.fail()
    await tick()
    const fallback = h.requests.at(-1).options
    assert.match(fallback.url, /epochECI\/fallback$/)
    assert.equal(fallback.header['X-BenchGauge-Grant'], g.token)
    h.respond(h.requests.length - 1, { board: board({ kind: 'epochECI' }) })
    assert.equal((await promise).kind, 'epochECI')
    assert.equal(h.requests.filter(r => r.options.url.includes('epoch.ai')).length, 1)
  }
})
test('a disposed store never starts server fallback after aborting the origin', async () => {
  const h = harness(); const promise = h.store.fetch('epochECI')
  h.respond(0, { grant: grant() }); await tick(); h.store.dispose()
  await assert.rejects(promise, /disposed/); assert.equal(h.requests.length, 2)
})

test('origin and backend failure retain cache and a lost upload response re-reads a committed snapshot', async () => {
  for (const committed of [false, true]) {
    const h = harness({ epochECI: board({ kind: 'epochECI' }) })
    const promise = h.store.fetch('epochECI'); h.respond(0, { grant: grant() }); await tick()
    h.requests[1].options.fail(); await tick()
    h.respond(2, {}, 503); await tick()
    assert.match(h.requests[3].options.url, /\/epochECI$/)
    assert.equal(h.requests[3].options.method, 'GET')
    if (committed) h.respond(3, { board: board({ kind: 'epochECI', entries: [{ rank: 1, name: 'Committed', score: 100 }] }) })
    else h.respond(3, {}, 503)
    assert.equal((await promise).entries[0].name, committed ? 'Committed' : 'Public model')
    assert.equal(h.requests.filter(r => r.options.url.endsWith('/refresh')).length, 1)
  }
})


test('uncached entry reads fresh shared data once without claiming or collecting', async () => {
  const h = harness(), paints = []
  const pending = h.store.fetch(kind, cached => paints.push(cached), { readFirst: true })
  assert.equal(h.requests[0].options.method, 'GET')
  assert.equal(h.requests[0].options.url, `https://shared.example/v1/boards/${kind}`)
  assert.equal(h.requests[0].options.timeout, 8000)
  const fresh = board({ fetchedAt: new Date().toISOString() })
  h.respond(0, { board: fresh })
  assert.equal((await pending).entries[0].name, 'Public model')
  assert.equal(paints.length, 1)
  assert.equal(h.requests.length, 1)
})

test('stale shared rows paint before a blocked origin or refresh completes', async () => {
  const h = harness(), paints = []
  const pending = h.store.fetch(kind, cached => paints.push(cached), { readFirst: true })
  h.respond(0, { board: board() }); await tick()
  assert.equal(paints.length, 1)
  assert.equal(h.store.read(kind).entries[0].name, 'Public model')
  assert.ok(h.requests[1].options.url.endsWith('/refresh'))
  h.respond(1, { grant: grant(), board: board() }); await tick()
  assert.equal(h.requests[2].options.url, 'https://epoch.ai/data/eci_scores.csv')
  h.requests[2].options.fail(); await tick()
  h.respond(3, { board: board() })
  assert.equal((await pending).entries[0].name, 'Public model')
})

test('failed first shared read ends without a serial refresh timeout and manual retry remains available', async () => {
  const h = harness()
  const initial = h.store.fetch(kind, undefined, { readFirst: true })
  h.requests[0].options.fail(); h.requests[0].options.complete()
  await assert.rejects(initial)
  assert.equal(h.requests.length, 1)
  const manual = h.store.fetch(kind)
  assert.ok(h.requests[1].options.url.endsWith('/refresh'))
  h.respond(1, { board: board() }); await manual
})
