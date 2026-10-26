import test from 'node:test'
import assert from 'node:assert/strict'
import { normalizeBoard, canReplace, visibleRows, countryCode } from '../src/core/leaderboard.js'
import { createBoardStore } from '../src/services/boards.js'

test('model facts and provider prices survive normalization and offline JSON caching without changing ranking dates', () => {
  const metadata = { id: 'lab/new-model', name: 'New Model', source: 'models.dev', sourceURL: 'https://models.dev/catalog.json?type=all',
    revision: 'a'.repeat(64), fetchedAt: '2026-10-19T00:00:00Z', openWeights: true, license: 'Apache-2.0', limit: { context: 200000 },
    offers: [{ provider: 'host-a', providerName: 'Host A', modelID: 'new', name: 'New Model', limit: { context: 100000 },
      currency: 'USD', unit: 'per-million-tokens', cost: { input: 0, output: 2.5, tiers: [{ tier: { type: 'context', size: 200000 }, input: 3, output: 5 }] } }] }
  const source = { source: 'models.dev', license: 'MIT License\nCopyright (c) 2025 models.dev', revision: metadata.revision, fetchedAt: metadata.fetchedAt }
  const value = { kind: 'artificialAnalysis', fetchedAt: '2026-10-18T00:00:00Z', sourceUpdatedAt: '2026-10-15T00:00:00Z', modelMetadataSource: source,
    entries: [{ rank: 1, name: 'New Model', score: 50, voteCount: 2000, modelMetadata: metadata, developerCountry: { countryCode: 'HK' } },
      { rank: 2, name: 'Explicit closed', score: 40, openness: 'closed', modelMetadata: metadata },
      { rank: 3, name: 'Unmatched', score: 30 }] }
  const old = { ...value, entries: value.entries.map(({ modelMetadata, ...entry }) => entry) }
  const board = normalizeBoard(JSON.parse(JSON.stringify(value)), value.kind)
  assert.deepEqual(board.entries[0].modelMetadata, metadata)
  assert.deepEqual(board.modelMetadataSource, source)
  assert.equal(board.fetchedAt, value.fetchedAt); assert.equal(board.sourceUpdatedAt, value.sourceUpdatedAt)
  assert.equal(board.entries[0].voteCount, 2000); assert.equal(countryCode(board.entries[0]), 'CN')
  assert.deepEqual(visibleRows(board, { openness: 'open' }).map(e => e.rank), [1])
  assert.deepEqual(visibleRows(board, { openness: 'closed' }).map(e => e.rank), [2])
  assert.deepEqual(visibleRows(board, { openness: 'unknown' }).map(e => e.rank), [3])
  assert.equal(canReplace(board, old), true)
  assert.deepEqual(normalizeBoard(JSON.parse(JSON.stringify(board)), board.kind), board)
})

test('large provider catalogs persist across restart and an interrupted replacement preserves the last valid file', async () => {
  const files = new Map(), path = '/user/benchgauge-boards-v1.json'
  let interrupted = false, legacyWrites = 0, next
  const fs = {
    readFileSync(p) { if (!files.has(p)) throw Error('No file'); return files.get(p) },
    writeFileSync(p, value) { files.set(p, value) },
    renameSync(from, to) { if (interrupted) throw Error('Disk unavailable'); files.set(to, files.get(from)); files.delete(from) },
  }
  const platform = { env: { USER_DATA_PATH: '/user' }, getFileSystemManager: () => fs, getStorageSync: () => null,
    setStorageSync() { legacyWrites++; throw Error('Storage key too large') },
    request(options) { queueMicrotask(() => options.success({ statusCode: 200, data: { board: next } })); return {} } }
  next = { kind: 'artificialAnalysis', fetchedAt: '2026-10-18T00:00:00Z', entries: [{ rank: 1, name: 'New', score: 1,
    modelMetadata: { source: 'models.dev', note: 'x'.repeat(1100000), offers: [{ cost: { input: 0, output: 2 } }] } }] }
  const create = () => createBoardStore({ platform, endpoint: 'https://shared.example' })
  await create().fetch(next.kind)
  assert.equal(legacyWrites, 0); assert.ok(files.get(path).length > 1048576)
  assert.deepEqual(create().read(next.kind), normalizeBoard(next, next.kind))
  const good = files.get(path); interrupted = true
  next = { ...next, fetchedAt: '2026-10-19T00:00:00Z' }
  await create().fetch(next.kind)
  assert.equal(files.get(path), good); assert.equal(legacyWrites, 1)
  assert.equal(create().read(next.kind).fetchedAt, '2026-10-18T00:00:00Z')
})

test('details retain future facts, false and zero values, independent prices, safe links and token tier units', async () => {
  const { readFile } = await import('node:fs/promises')
  const { modelDetailSections, detailText, safeDetailURL } = await import('../src/core/model-details.js')
  const { entry } = JSON.parse(await readFile(new URL('../../../Tests/fixtures/model-details.json', import.meta.url)))
  const original = JSON.stringify(entry)
  for (const language of ['en', 'zh', 'zh-Hant']) {
    const sections = modelDetailSections(entry, language), values = sections.flatMap(s => s.rows).map(r => r.value)
    assert.ok(values.includes('Apache-2.0') && values.includes('2026-06') && values.includes('Preserved future field'))
    assert.ok(values.includes('0') && values.includes(detailText('false', language)))
    const provider = sections.find(s => s.id === 'provider-0')
    assert.match(provider.summary, /\$0.*\$2\.5/)
    assert.ok(provider.rows.some(r => r.value === '200,000'))
    assert.ok(!provider.rows.some(r => r.value === '$200,000'))
    assert.equal(sections.find(s => s.id === 'provider-1').summary, detailText('unknown', language))
    assert.equal(sections.flatMap(s => s.rows).find(r => r.value === 'javascript:alert(1)').url, null)
    assert.ok(sections.flatMap(s => s.rows).some(r => r.url === 'https://example.com/docs'))
    assert.ok(sections.find(s => s.id === 'benchmark-0').rows.some(r => r.value === '1,000'))
  }
  assert.equal(JSON.stringify(entry), original)
  assert.deepEqual(modelDetailSections({ name: 'Missing' }), [])
  for (const url of ['http://example.com', 'javascript:alert(1)', 'https://user@example.com']) assert.equal(safeDetailURL(url), null)
})

test('model page receives the selected entry and only its copy icon writes the original name', async () => {
  const { registerHooks } = await import('node:module'), { readFile } = await import('node:fs/promises')
  const { entry } = JSON.parse(await readFile(new URL('../../../Tests/fixtures/model-details.json', import.meta.url)))
  let factory, receive, onScroll, scrolls = [], clipboard = [], toast = []
  globalThis.__modelFactory = fn => { factory = fn }; globalThis.__modelScroll = fn => { onScroll = fn }
  const hooks = registerHooks({
    resolve(s, c, next) { return s === '@vue-mini/core' ? { url: 'test:model-vue', shortCircuit: true } : next(s, c) },
    load(url, c, next) { return url === 'test:model-vue' ? { format: 'module', shortCircuit: true, source: `export const onPageScroll = fn => globalThis.__modelScroll(fn); export const definePage = fn => globalThis.__modelFactory(fn); export const ref = value => ({value}); export const computed = fn => ({get value(){return fn()}})` } : next(url, c) },
  })
  try { await import('../src/pages/model/index.js') } finally { hooks.deregister() }
  globalThis.wx = { getStorageSync: () => ({ language: 'en', languageMode: 'manual' }), getAppBaseInfo: () => ({ language: 'en' }),
    getWindowInfo: () => ({ statusBarHeight: 24 }), setClipboardData: o => { clipboard.push(o.data); o.success() }, showToast: o => toast.push(o.title), navigateBack() {}, pageScrollTo: o => scrolls.push(o) }
  const page = factory({}, { getOpenerEventChannel: () => ({ on: (event, fn) => { assert.equal(event, 'modelDetails'); receive = fn } }) })
  assert.deepEqual(page.sections.value, [])
  receive({ entry }); assert.ok(page.sections.value.length > 5); assert.deepEqual(clipboard, [])
  const offer = page.sections.value.find(s => s.id === 'provider-0'); assert.equal(offer.expanded, false)
  page.toggle({ currentTarget: { dataset: { id: offer.id } } }); assert.equal(page.sections.value.find(s => s.id === offer.id).expanded, true)
  page.copyName(); assert.deepEqual(clipboard, [entry.name]); assert.equal(page.copied.value, true); assert.deepEqual(toast, ['Copied'])
  page.copyLink({ currentTarget: { dataset: { url: 'javascript:alert(1)' } } }); assert.equal(clipboard.length, 1)
  onScroll({ scrollTop: 600 }); assert.equal(page.backToTop.value, true)
  page.top(); assert.deepEqual(scrolls, [{ scrollTop: 0, duration: 250 }])
  onScroll({ scrollTop: 0 }); assert.equal(page.backToTop.value, false)
  assert.equal(page.sections.value.find(s => s.id === 'general').expanded, false)
  assert.equal(page.sections.value.find(s => s.id === 'limits').expanded, true)
  delete globalThis.__modelScroll
  delete globalThis.__modelFactory
})


test('model sync time uses a full local calendar timestamp with seconds and handles offsets', async () => {
  const { modelSyncTime } = await import('../src/core/model-details.js')
  const zone = process.env.TZ
  try {
    process.env.TZ = 'Asia/Shanghai'
    assert.equal(modelSyncTime('2025-04-01T04:00:01.564Z'), '2025-04-01 12:00:01')
    assert.equal(modelSyncTime('2024-02-29T23:59:59-05:00'), '2024-03-01 12:59:59')
    process.env.TZ = 'UTC'
    assert.equal(modelSyncTime('2025-04-01T12:00:01+08:00'), '2025-04-01 04:00:01')
    assert.equal(modelSyncTime('invalid'), 'invalid')
    assert.equal(modelSyncTime(undefined), '—')
  } finally { if (zone === undefined) delete process.env.TZ; else process.env.TZ = zone }
})
