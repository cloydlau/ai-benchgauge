import assert from 'node:assert/strict'
import test from 'node:test'
import { parseBoard } from '../fc/parser.mjs'
import { attachGeneralTaskCosts } from '../fc/aa-general-cost.mjs'
import { withContentTimestamp } from '../fc/domain.mjs'
const now = Date.parse('2026-10-28T00:00:00Z')
const html = rows => `<script>self.__next_f.push([1,${JSON.stringify(JSON.stringify({ rows }))}])</script>`
test('AA general throughput and coding task duration use their own official fields', () => {
  const general = Array.from({length: 20}, (_, i) => ({ name: `Model ${i}`, intelligenceIndex: 20 - i, timescaleData: { medianOutputSpeed: [200, 0, -1, '5'][i % 4] } }))
  const board = parseBoard('artificialAnalysis', html(general), now)
  assert.deepEqual(board.entries.slice(0, 4).map(x => x.speed), [200, undefined, undefined, undefined])
  const coding = Array.from({length: 10}, (_, i) => ({ displayLabel: `Agent ${i}`, indexScore: (10 - i) / 10, mean: { agentWallTimeSec: [240, null, -5, '2'][i % 4] } }))
  const agents = parseBoard('artificialAnalysisCodingAgent', html(coding), now)
  assert.deepEqual(agents.entries.slice(0, 4).map(x => x.speed), [240, undefined, undefined, undefined])
})
test('general speed joins on exact name and score, and changes update content time', () => {
  const base = { kind: 'artificialAnalysis', fetchedAt: new Date(now).toISOString(), entries: [{name: 'A', score: 1, rank: 1}] }
  const updated = attachGeneralTaskCosts(base, {kind: base.kind, entries: [{name: 'A', score: 1, speed: 120}]})
  assert.equal(updated.entries[0].speed, 120)
  assert.equal(attachGeneralTaskCosts(base, {kind: base.kind, entries: [{name: 'A', score: 2, speed: 120}]}).entries[0].speed, undefined)
  const later = { ...updated, fetchedAt: new Date(now + 1000).toISOString() }
  assert.equal(withContentTimestamp(later, base).contentUpdatedAt, later.fetchedAt)
})
