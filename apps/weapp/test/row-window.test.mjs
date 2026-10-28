import assert from 'node:assert/strict'
import test from 'node:test'
import { rowGeometry, resolveRowWindow, createRowRenderer } from '../src/core/row-window.js'
import { rowView } from '../src/core/leaderboard.js'

test('compact bridge rows omit disabled details and unused movement styles while preserving active badges', () => {
  const entry = { rank: 2, name: 'Model', score: 99,
    components: [{ rank: 1, name: 'Member', score: 98 }] }
  const compact = change => JSON.parse(JSON.stringify(rowView({ ...entry, rankChange: change }, { details: false })))
  for (const change of [undefined, { delta: 0 }, { delta: NaN }]) {
    const row = compact(change)
    assert.equal(row.rankChangeText, '')
    assert.equal(Object.hasOwn(row, 'rankChangeTone'), false)
    assert.equal(Object.hasOwn(row, 'components'), false)
  }
  for (const [change, text, tone] of [[{ delta: 3 }, '↑3', 'up'], [{ delta: -2 }, '↓2', 'down'], [{ isNew: true }, 'New', 'new']]) {
    const row = compact(change)
    assert.equal(row.rankChangeText, text)
    assert.equal(row.rankChangeTone, tone)
  }
  assert.deepEqual(rowView(entry).components, [{ name: 'Member', rank: 1, score: '98.0' }])
})

test('scroll windows retain the full board leader and refresh their cached ratios after filtering', () => {
  const render = createRowRenderer((entry, entries) => rowView(entry, { leaderScore: entries[0]?.score }))
  const entries = [100, 80, 60, 40].map((score, i) => ({ rank: i + 1, name: `M${i}`, score }))
  const range = { start: 2, end: 4, rowHeight: 48, variant: 'model' }
  assert.deepEqual(render({ entries, ...range }).map(row => row.scoreShare), ['60%', '40%'])
  assert.deepEqual(render({ entries: entries.slice(1), ...range, start: 1, end: 3 }).map(row => row.scoreShare), ['75%', '50%'])
})

test('buffered windows keep every visible row covered without depending on total count', () => {
  for (const width of [320, 375, 414, 834]) {
    const geometry = rowGeometry({ windowWidth: width, windowHeight: 900 })
    for (const count of [0, 1, 20, 5000, 100000]) {
      let range = { start: 0, end: 0 }
      for (const fraction of [0, 0.001, 0.2, 0.95, 1, 0.5, 0]) {
        const scrollTop = fraction * Math.max(0, count * geometry.rowHeight - geometry.viewportHeight) + 250
        range = resolveRowWindow({ count, scrollTop, origin: 250, geometry, ...range })
        assert.ok(range.start >= 0 && range.end <= count)
        assert.ok(range.end - range.start <= Math.max(20, Math.ceil(geometry.viewportHeight / geometry.rowHeight) + 25))
        if (!count) continue
        const first = Math.min(count - 1, Math.floor((scrollTop - 250) / geometry.rowHeight))
        const last = Math.min(count - 1, Math.floor((scrollTop - 250 + geometry.viewportHeight) / geometry.rowHeight))
        assert.ok(first >= range.start && last < range.end)
      }
    }
  }
})

test('edge hysteresis, end clamps, resizing and refresh never leave a stale window', () => {
  const geometry = rowGeometry()
  const initial = resolveRowWindow({ count: 5000, geometry })
  for (const scrollTop of [0.01, 1, 100, 500]) {
    assert.deepEqual(resolveRowWindow({ count: 5000, scrollTop, geometry, ...initial }), initial)
  }
  const tail = resolveRowWindow({ count: 5000, scrollTop: 1e9, geometry })
  assert.equal(tail.end, 5000)
  assert.deepEqual(resolveRowWindow({ count: 2, scrollTop: 1e9, geometry, ...tail, force: true }), { start: 0, end: 2 })
  assert.equal(resolveRowWindow({ count: 5000, scrollTop: -100, geometry, ...tail }).start, 0)
  assert.deepEqual(rowGeometry({ windowWidth: 0, windowHeight: NaN }), geometry)
  assert.equal(rowGeometry({ windowWidth: 414 }).rowHeight, 96 * 414 / 750)
})

test('overlap reuses row objects and only new rows incur presentation work', () => {
  const entries = Array.from({ length: 10000 }, (_, rank) => ({ rank }))
  let mapped = 0
  const render = createRowRenderer(entry => { mapped++; return entry })
  const options = { entries, start: 0, end: 40, rowHeight: 48, variant: 'model:light' }
  const initial = render(options)
  assert.equal(mapped, 40)
  assert.equal(render(options), initial)
  const next = render({ ...options, start: 10, end: 50 })
  assert.equal(mapped, 50)
  assert.equal(next[0], initial[10])
  assert.equal(next.at(-1).top, 49 * 48)
  render({ ...options, variant: 'model:dark' })
  assert.equal(mapped, 90)
  render({ ...options, entries: entries.slice() })
  assert.equal(mapped, 130)
})
