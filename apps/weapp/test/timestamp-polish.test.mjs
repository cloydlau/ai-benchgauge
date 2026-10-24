import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { createTimestampPolish, polishDuration, polishInterval } from '../src/core/timestamp-polish.js'

test('timestamp loading replaces the caption without removing its layout space', () => {
  const template = readFileSync(new URL('../src/pages/leaderboard/index.wxml', import.meta.url), 'utf8')
  const css = readFileSync(new URL('../src/pages/leaderboard/index.css', import.meta.url), 'utf8')
  assert.match(template, /class="time-caption \{\{card.loading \? 'time-caption-loading' : ''\}\}"/)
  assert.match(template, /<text class="time-label">\{\{card.timeLabel\}\}<\/text><view wx:if="\{\{card.loading\}\}" class="time-loading"/)
  assert.match(css, /\.time-caption-loading \.time-label\s*\{\s*visibility: hidden;/)
  assert.match(css, /\.time-loading\s*\{[^}]*position: absolute;/)
})

test('one pass after loading, every 30 seconds, without restarting on renders', () => {
  let now = 0, serial = 0
  const timers = new Map(), events = []
  const polish = createTimestampPolish(kind => events.push([now, kind]), {
    later(fn, ms) { const id = ++serial; timers.set(id, { fn, at: now + ms }); return id },
    cancel(id) { timers.delete(id) },
  })
  function advance(to) {
    while (true) {
      const due = [...timers].sort((a, b) => a[1].at - b[1].at)[0]
      if (!due || due[1].at > to) break
      now = due[1].at; timers.delete(due[0]); due[1].fn()
    }
    now = to
  }
  assert.equal(polishDuration, 1100); assert.equal(polishInterval, 30000)
  polish.update('aa', false)
  assert.equal(timers.size, 0)
  polish.update('aa', true)
  assert.deepEqual(events.at(-1), [0, 'aa'])
  advance(1100); assert.deepEqual(events.at(-1), [1100, null])
  polish.update('aa', true)
  advance(29999); assert.equal(events.filter(([, kind]) => kind).length, 1)
  advance(30000); assert.deepEqual(events.at(-1), [30000, 'aa'])
  polish.update('aa', false); assert.equal(timers.size, 0)
  advance(31000); polish.update('aa', true)
  assert.deepEqual(events.at(-1), [31000, 'aa'])
  polish.update('arena', true); assert.deepEqual(events.at(-1), [31000, 'arena'])
  polish.stop(); assert.equal(timers.size, 0)
  advance(100000); assert.deepEqual(events.at(-1), [31000, null])
  polish.update('arena', true); assert.deepEqual(events.at(-1), [100000, 'arena'])
  polish.stop()
})
