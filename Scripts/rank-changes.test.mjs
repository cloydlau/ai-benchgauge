import assert from 'node:assert/strict'
import test from 'node:test'
import { withRankChanges, companyRows } from '../fc/domain.mjs'
import { SharedLeaderboards } from '../fc/service.mjs'
import { parseBoard } from '../fc/parser.mjs'

const entry = (name, rank, score, organization = 'OpenAI') => ({ name, modelID: name, rank, score, organization })
const board = (entries, kind = 'artificialAnalysis') => ({ kind, entries, fetchedAt: '2026-10-28T00:00:00Z' })

test('compare before replacing: rises, falls, new models and removed models with separate company positions', () => {
  const old = board([entry('A', 1, 100), entry('B', 2, 90, 'Google'), entry('Gone', 3, 80)])
  const next = board([entry('B', 1, 101, 'Google'), entry('New', 2, 95, 'Anthropic'), entry('A', 3, 90)])
  const saved = JSON.stringify(old)
  const result = withRankChanges(next, old)
  assert.deepEqual(result.entries.map(row => row.rankChange), [{ delta: 1 }, { isNew: true }, { delta: -2 }])
  assert.deepEqual(companyRows(result.entries).map(row => row.rankChange), [{ delta: 1 }, { isNew: true }, { delta: -2 }])
  assert.equal(result.entries.some(row => row.name === 'Gone'), false)
  assert.equal(JSON.stringify(old), saved)
  const refreshed = withRankChanges({ ...next, fetchedAt: '2026-10-28T01:00:00Z', entries: [...next.entries].reverse() }, result)
  assert.deepEqual(refreshed.entries.map(row => row.rankChange), [{ delta: -2 }, { isNew: true }, { delta: 1 }])
  assert.equal(refreshed.fetchedAt, '2026-10-28T01:00:00Z')
})

test('no baseline has no badges, unchanged fetches preserve them, and next real update clears settled ranks', () => {
  const next = board([entry('A', 1, 100), entry('B', 2, 90)])
  for (const previous of [undefined, board([]), board(next.entries, 'epochECI')]) {
    assert.equal(withRankChanges(next, previous).entries[0].rankChange, undefined)
  }
  const same = withRankChanges(next, next)
  assert.deepEqual(same, next)
  const marked = { ...next, entries: next.entries.map(row => ({ ...row, rankChange: { isNew: true }, companyRankChange: { delta: 2 } })) }
  const updated = withRankChanges(board([entry('A', 1, 101), entry('B', 2, 90)]), marked)
  assert.ok(updated.entries.every(row => !row.rankChange && !row.companyRankChange))
  assert.equal(companyRows([{ ...entry('A', 1, 100), rankChange: { delta: 5 } }])[0].rankChange, undefined)
  const dirty = board([{ ...entry('A', 1, 100), rankChange: { isNew: true }, companyRankChange: { isNew: true } }])
  assert.equal(withRankChanges(dirty, undefined).entries[0].rankChange, undefined)
})

test('model IDs survive renames and Arena synthetic rank suffixes; ambiguous duplicates never invent movements', () => {
  const old = board([{ ...entry('A', 1, 100), modelID: 'stable' }, { ...entry('B', 2, 90), modelID: 'B#arena-rank-2' }])
  const next = board([{ ...entry('B', 1, 101), modelID: 'B#arena-rank-1' }, { ...entry('Renamed', 2, 99), modelID: 'stable' }])
  assert.deepEqual(withRankChanges(next, old).entries.map(row => row.rankChange), [{ delta: 1 }, { delta: -1 }])
  const duplicates = board([entry('A', 1, 100), entry('A', 2, 99), entry('A', 3, 98)])
  assert.ok(withRankChanges(duplicates, old).entries.every(row => !row.rankChange))
  assert.equal(withRankChanges(board([entry('A', 1, 101)]), duplicates).entries[0].rankChange, undefined)
  const anonymous = { rank: 1, name: 'No ID', score: 90 }
  assert.equal(withRankChanges(board([{ ...anonymous, score: 91 }]), board([anonymous])).entries[0].rankChange, undefined)
})

test('usage companies compare summed shares, hosted companies use their own stable identity', () => {
  const old = board([entry('A', 1, 60), entry('B', 2, 40, 'Google'), entry('C', 3, 30, 'Google')], 'vercelUsage')
  const next = board([entry('A', 1, 80), entry('B', 2, 40, 'Google'), entry('C', 3, 30, 'Google')], 'vercelUsage')
  const companies = companyRows(withRankChanges(next, old).entries, { summingUsage: true })
  assert.deepEqual(companies.map(row => row.rankChange), [{ delta: 1 }, { delta: -1 }])
  const hosted = board([{ ...entry('Claude Code - Qwen3.8 Max', 1, 90, 'Anthropic'), modelID: undefined }])
  assert.equal(companyRows(withRankChanges(board([{ ...hosted.entries[0], score: 91 }]), hosted).entries)[0].rankChange, undefined)
  const noCompany = board([{ rank: 1, name: 'Unattributed', score: 90 }])
  assert.equal(withRankChanges(board([{ ...noCompany.entries[0], score: 91 }]), noCompany).entries[0].companyRankChange, undefined)
})

test('API acquisitions persist comparison before exposing the replacement and retain it through cold reads', async () => {
  for (const kind of ['arenaText', 'openRouterUsage', 'vercelUsage', 'cloudbaseUsage']) {
    let now = Date.parse('2026-10-28T00:00:00Z')
    const sourceNote = kind === 'arenaText' ? 'https://huggingface.co/datasets/lmarena-ai/arena-leaderboard' : undefined
    let saved = { ...board([entry('A', 1, 100), entry('B', 2, 90, 'Google')], kind), sourceNote }
    const next = { ...board([entry('B', 1, 101, 'Google'), entry('A', 2, 99)], kind), sourceNote }
    let state = null
    const store = {
      async readBoard(key) { return key === kind ? saved : null },
      async readState() { return { position: 0, state } },
      async appendState(key, position, value) { state = value; return true },
      async writeBoard(key, value) { assert.deepEqual(value.entries[0].rankChange, { delta: 1 }); saved = value },
    }
    const options = { clock: () => now, openRouterConfigured: () => true,
      arenaDataset: async () => next, openRouterUsage: async () => next, vercelUsage: async () => next, cloudbaseUsage: async () => next }
    // Arena's official attribution is validated independently by its loader.
    if (kind === 'arenaText') {
      const { default: notice } = await import('../fc/arena-attribution.json', { with: { type: 'json' } })
      saved.sourceNote = next.sourceNote = notice.sourceURL
    }
    const service = new SharedLeaderboards(store, options)
    const result = await service.refresh(kind)
    assert.deepEqual(result.board.entries[0].rankChange, { delta: 1 })
    assert.deepEqual((await new SharedLeaderboards(store, options).read(kind)).board.entries[0].rankChange, { delta: 1 })
    now += 2 * 86400000
    assert.deepEqual((await service.refresh(kind)).board.entries[0].rankChange, { delta: 1 })
  }
})

test('HTML contributions compare the last durable board and failed writes leave it intact', async () => {
  const now = Date.parse('2026-10-28T00:00:00Z')
  const csv = swap => 'Model,Display name,eci,Organization,Country (of organization),Accessibility group\n'
    + Array.from({length:22}, (_, i) => `model-${i},Model ${i},${100 - (swap && i < 2 ? 1-i : i)},OpenAI,US,Closed weights`).join('\n')
  let saved = parseBoard('epochECI', csv(false), now - 1000), state = null, fail = true
  const previous = saved
  const store = {
    async readBoard() { return saved }, async readState() { return {position:0,state} },
    async appendState(key, position, value) { state = value; return true },
    async writeBoard(key, value) {
      assert.deepEqual(value.entries.map(row => row.rankChange).slice(0,2), [{delta:1}, {delta:-1}])
      if (fail) throw Error('Unavailable storage')
      saved = value
    },
  }
  const service = new SharedLeaderboards(store, {clock:()=>now})
  let grant = (await service.refresh('epochECI')).grant
  await assert.rejects(service.contribute('epochECI',grant.token,csv(true)), /Unavailable storage/)
  assert.equal(saved, previous)
  state = null; fail = false
  grant = (await service.refresh('epochECI')).grant
  const result = await service.contribute('epochECI',grant.token,csv(true))
  assert.deepEqual(result.board.entries[0].rankChange, {delta:1})
  assert.equal(saved.entries[0].modelID, 'model-1')
})
