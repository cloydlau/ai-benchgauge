import test from 'node:test'
import assert from 'node:assert/strict'
import { createMetricGuide } from '../src/core/metric-guide.js'

test('guidance stays until a tap and remembers each eligible board independently', t => {
  t.mock.timers.enable({ apis: ['setTimeout'] })
  let saved = [], shown = null, visible = true
  const guide = createMetricGuide({ supports: kind => ['aa', 'openrouter'].includes(kind),
    read: () => saved, write: value => { saved = value }, show: value => { shown = value }, readyNow: () => visible })
  guide.update('arena', true); t.mock.timers.tick(1200); assert.deepEqual(saved, [])
  guide.update('aa', true); t.mock.timers.tick(500); guide.stop(); t.mock.timers.tick(1000)
  assert.deepEqual(saved, []); assert.equal(shown, null)
  guide.update('aa', true); t.mock.timers.tick(1000)
  assert.deepEqual(saved, []); assert.equal(shown, 'aa')
  t.mock.timers.tick(60000); assert.equal(shown, 'aa'); assert.deepEqual(saved, [])
  guide.stop(); guide.update('aa', true); t.mock.timers.tick(1000); assert.equal(shown, 'aa')
  guide.acknowledge('aa'); assert.deepEqual(saved, ['aa']); assert.equal(shown, null)
  guide.update('aa', true); t.mock.timers.tick(1000); assert.equal(shown, null)
  guide.update('openrouter', true); visible = false; t.mock.timers.tick(1000)
  assert.deepEqual(saved, ['aa']); assert.equal(shown, null)
  visible = true; guide.update('openrouter', true); t.mock.timers.tick(1000)
  assert.deepEqual(saved, ['aa']); assert.equal(shown, 'openrouter')
  guide.acknowledge('openrouter'); assert.deepEqual(saved, ['aa', 'openrouter']); guide.stop()
})

test('opening the selector before the hint counts as discovery', t => {
  t.mock.timers.enable({ apis: ['setTimeout'] })
  let saved = [], shown = null
  const guide = createMetricGuide({ supports: () => true, read: () => saved, write: value => { saved = value }, show: value => { shown = value } })
  guide.update('aa', true); guide.acknowledge('aa'); t.mock.timers.tick(2000)
  assert.deepEqual(saved, ['aa']); assert.equal(shown, null)
})
