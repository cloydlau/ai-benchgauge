import test from 'node:test'
import assert from 'node:assert/strict'
import { leaderboardDistribution } from '../../../fc/distributions.mjs'

const entry = (country, openness, score = 1) => ({ name: 'Fixture', score, developerCountry: { countryCode: country }, openness })
test('model shares include unknown metadata, respect China policy, and never weight scores', () => {
  const result = leaderboardDistribution([entry('US', 'closed', 10000), entry('HK', 'open'), entry('TW', 'open'), entry(null)])
  assert.equal(result.total, 4)
  assert.deepEqual(result.countries.map(x => [x.id, x.count]), [['CN', 2], ['US', 1], ['unknown', 1]])
  assert.deepEqual(result.sources.map(x => x.count), [2, 1, 1])
  assert.deepEqual(result.sources.map(x => x.percent), ['50.0%', '25.0%', '25.0%'])
})
test('country tail compaction retains every model and keeps unknown separate', () => {
  const result = leaderboardDistribution(['US', 'CN', 'FR', 'CA', 'DE', 'SG', 'JP', null].map(x => entry(x)))
  assert.equal(result.countries.length, 7)
  assert.equal(result.countries.find(x => x.id === 'other').count, 2)
  assert.equal(result.countries.find(x => x.id === 'unknown').count, 1)
  assert.equal(result.countries.reduce((sum, x) => sum + x.count, 0), result.total)
})
test('empty datasets do not fabricate percentages or closed-source models', () => {
  const result = leaderboardDistribution([])
  assert.deepEqual(result.countries, [])
  assert.deepEqual(result.sources.map(x => x.id), ['open', 'closed'])
  assert.ok(result.sources.every(x => x.percent === '—' && x.fraction === 0))
  const known = leaderboardDistribution([entry('US', 'open')])
  assert.deepEqual(known.countries.map(x => x.id), ['US'])
  assert.deepEqual(known.sources.map(x => [x.id, x.count]), [['open', 1], ['closed', 0]])
  assert.equal(leaderboardDistribution([entry(null)]).sources[2].percent, '100.0%')
})
