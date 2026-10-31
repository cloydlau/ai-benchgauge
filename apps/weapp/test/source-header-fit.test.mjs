import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { fitSourceHeader } from '../src/core/source-header-fit.js'

test('header fitting caps both fonts at their original sizes and restores them after widening', () => {
  const metrics = { headingWidth: 92, variantWidth: 100, chromeWidth: 60 }
  const narrow = fitSourceHeader({ ...metrics, width: 180 })
  assert.ok(narrow.variantScale < 1)
  assert.ok(narrow.headingScale <= 1)
  assert.deepEqual(fitSourceHeader({ ...metrics, width: 400 }), { headingScale: 1, variantScale: 1 })
})

test('single-line headers fit short speech names, long streaming names and English labels', () => {
  for (const headingWidth of [78, 92]) for (const variantWidth of [18, 36, 72, 126, 180]) for (const width of [150, 180, 238, 400]) {
    const { headingScale, variantScale } = fitSourceHeader({ width, headingWidth, variantWidth, chromeWidth: 60 })
    assert.ok(headingScale > 0 && headingScale <= 1)
    assert.ok(variantScale > 0 && variantScale <= 1)
    assert.ok(headingWidth * headingScale + variantWidth * variantScale + 60 <= width)
  }
  const fit = fitSourceHeader({ width: 240, headingWidth: 92, variantWidth: 100, chromeWidth: 60 })
  assert.equal(fit.headingScale, 1, 'Prefer shrinking the task label when there is enough room')
  assert.ok(fit.variantScale < 1)
})

test('missing measurements keep the original font instead of propagating invalid sizes', () => {
  for (const width of [0, undefined, NaN]) assert.deepEqual(fitSourceHeader({ width, headingWidth: 92 }), { headingScale: 1, variantScale: 1 })
  const fit = fitSourceHeader({ width: 70, headingWidth: 92, chromeWidth: 28 })
  assert.ok(fit.headingScale < 1)
  assert.equal(fit.variantScale, 1)
})

// Real 375px company-header measurements. Read the actual control budget so a
// style regression cannot silently reserve the speech label's space again.
test('speech labels keep their original font when the compact search leaves enough room', () => {
  const css = readFileSync(new URL('../src/pages/leaderboard/index.css', import.meta.url), 'utf8')
  const compactSearch = css.match(/\.source-heading-details:not\(\.no-variants\) \.model-filter-toggle\s*\{([^}]+)\}/)?.[1]
  const searchWidth = Number(compactSearch?.match(/width:\s*(\d+)px/)?.[1])
  assert.ok(searchWidth >= 13, 'The search glyph must fit in its control')
  for (const variantWidth of [91.5, 82.5, 73.5]) {
    assert.deepEqual(fitSourceHeader({ width: 238, headingWidth: 82.4375,
      variantWidth, chromeWidth: searchWidth + 30 + 12 }), { headingScale: 1, variantScale: 1 })
  }
})


test('narrow model headers share shrinking so the speech option stays readable instead of retaining the full brand size', () => {
  const { headingScale, variantScale } = fitSourceHeader({ width: 206, headingWidth: 82.4375, variantWidth: 91.5, chromeWidth: 62 })
  assert.ok(headingScale < 1)
  assert.ok(variantScale > 0.8 && variantScale <= 1)
  assert.equal(headingScale, variantScale)
  assert.ok(82.4375 * headingScale + 91.5 * variantScale + 62 + 1 <= 206)
})
