import assert from 'node:assert/strict'
import test from 'node:test'
import { readFileSync } from 'node:fs'
import { contentTimestamp, withContentTimestamp } from '../fc/domain.mjs'
import { SharedLeaderboards } from '../fc/service.mjs'
import { parseBoard } from '../fc/parser.mjs'
import arena from '../fc/arena-attribution.json' with { type: 'json' }

const samples = JSON.parse(readFileSync(new URL('../Tests/fixtures/content-timestamps.json', import.meta.url)))
test('last new-data time uses the same source comparison across clients', () => {
  for (const sample of samples) {
    const saved = JSON.stringify(sample.previous)
    const result = withContentTimestamp(sample.next, sample.previous)
    assert.equal(contentTimestamp(result), sample.expected, sample.name)
    assert.equal(JSON.stringify(sample.previous), saved, 'do not mutate the durable baseline')
  }
})

test('every API writer retains time on duplicates, advances on changes, and survives cold reads and failed writes', async () => {
  for (const kind of ['arenaText', 'openRouterUsage', 'vercelUsage', 'cloudbaseUsage']) {
    let now = Date.parse('2026-10-28T00:00:00Z'), score = 100, fail = false
    let saved = { ...samples[0].previous, kind, ...(kind === 'arenaText' && { sourceNote: arena.sourceURL }) }
    const store = {
      async readBoard(key) { return key === kind ? saved : null },
      async readState() { return { position: 0, state: null } },
      async appendState() { return true },
      async writeBoard(key, value) { if (fail) throw Error('Storage failed'); saved = structuredClone(value) },
    }
    const load = async () => ({ ...saved, contentUpdatedAt: undefined, fetchedAt: new Date(now).toISOString(),
      entries: saved.entries.map((row, i) => i === 0 ? { ...row, score } : row) })
    const options = { clock: () => now, openRouterConfigured: () => true,
      arenaDataset: load, openRouterUsage: load, vercelUsage: load, cloudbaseUsage: load }
    const refresh = () => new SharedLeaderboards(store, options).refresh(kind)
    const original = saved.fetchedAt
    assert.equal(contentTimestamp((await refresh()).board), original, kind)
    assert.equal(saved.fetchedAt, new Date(now).toISOString(), 'last successful acquisition remains separate')
    now += 86400000; score++
    assert.equal(contentTimestamp((await refresh()).board), new Date(now).toISOString(), kind)
    const changed = saved.contentUpdatedAt
    now += 86400000
    assert.equal(contentTimestamp((await refresh()).board), changed, kind)
    assert.equal(contentTimestamp((await new SharedLeaderboards(store, options).read(kind)).board), changed)
    now += 86400000; score++; fail = true
    assert.equal(contentTimestamp((await refresh()).board), changed, 'failed writes retain the durable timestamp')
    assert.equal(saved.contentUpdatedAt, changed)
  }
})

test('HTML/CSV contributions persist time only when the accepted source data changes', async () => {
  let now = Date.parse('2026-10-28T00:00:00Z'), state = null, fail = false
  const csv = score => 'Model,Display name,eci,Organization,Country (of organization),Accessibility group\n'
    + Array.from({ length: 22 }, (_, i) => `model-${i},Model ${i},${score-i},OpenAI,US,Closed weights`).join('\n')
  let saved = parseBoard('epochECI', csv(100), now - 86400000)
  const original = saved.fetchedAt
  const store = {
    async readBoard() { return saved }, async readState() { return { position: 0, state } },
    async appendState(key, position, value) { state = value; return true },
    async writeBoard(key, value) { if (fail) throw Error('Storage failed'); saved = structuredClone(value) },
  }
  async function contribute(score) {
    state = null
    const service = new SharedLeaderboards(store, { clock: () => now })
    const { grant } = await service.refresh('epochECI')
    return service.contribute('epochECI', grant.token, csv(score))
  }
  assert.equal(contentTimestamp((await contribute(100)).board), original)
  now += 86400000
  assert.equal(contentTimestamp((await contribute(101)).board), new Date(now).toISOString())
  const changed = saved.contentUpdatedAt
  now += 86400000
  assert.equal(contentTimestamp((await contribute(101)).board), changed)
  fail = true; now += 86400000
  await assert.rejects(contribute(102), /Storage failed/)
  assert.equal(saved.contentUpdatedAt, changed)
})
