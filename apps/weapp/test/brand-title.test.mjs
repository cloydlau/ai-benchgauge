import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import { brandGlyphs } from '../src/core/brand-glyphs.js'
import { brandTitleLayout, createBrandMeasurer, drawBrandGlyphs } from '../src/core/brand-title.js'
import { canvasHarness } from './helpers/canvas.mjs'

test('titles use the native font outlines offline and keep the logo aligned with I', () => {
  assert.equal(brandGlyphs['zh-tian'].font, 'BenchGaugeCalligraphy-Regular')
  assert.equal(brandGlyphs['zh-ti'].font, 'BenchGaugeCalligraphy-Regular')
  assert.equal(brandGlyphs['en-name'].font, 'SnellRoundhand-Bold')
  const measure = createBrandMeasurer()
  for (const name of ['AI 天梯', 'AI BenchGauge']) {
    const title = measure(name, 21), larger = measure(name, 42)
    assert.equal(larger.width, title.width * 2)
    assert.equal(larger.height, title.height * 2)
    assert.equal(title.logoTop + title.logoHeight, title.glyphs[0].y + title.glyphs[0].height)
    assert.ok(title.glyphs[0].x > title.logoWidth)
    for (const glyph of title.glyphs) {
      assert.ok(glyph.y >= 0 && glyph.y + glyph.height <= title.height)
      assert.equal(glyph.y + glyph.height / 2, title.height / 2)
    }
  }
})

test('screen SVGs and Canvas exports consume identical native glyph contours in both themes', () => {
  for (const name of ['AI 天梯', 'AI BenchGauge']) {
    const title = brandTitleLayout(null, name, 21), h = canvasHarness()
    drawBrandGlyphs(h.context, title, 10, 20)
    assert.equal(h.commands.filter(([method]) => method === 'fill').length, title.glyphs.length)
    assert.ok(h.commands.some(([method]) => method === 'bezierCurveTo' || method === 'quadraticCurveTo'))
    assert.ok(h.commands.every(command => command.slice(1).every(Number.isFinite)))
    assert.ok(!h.commands.some(([method]) => method === 'fillText'))
    for (const glyph of title.glyphs) {
      const outline = brandGlyphs[glyph.key]
      for (const dark of [false, true]) {
        const svg = readFileSync(new URL(`../assets/brand-glyphs/${glyph.key}${dark ? '-dark' : ''}.svg`, import.meta.url), 'utf8')
        const tokens = svg.match(/ d="([^"]+)"/)[1].split(/\s+/).map(token => /^[MLQCZ]$/.test(token) ? token : Number(token))
        assert.deepEqual(tokens, outline.commands.flat())
        assert.deepEqual(svg.match(/viewBox="([^"]+)"/)[1].split(' ').map(Number), [0, 0, outline.width, outline.height])
        assert.ok(svg.includes(dark ? '#edf2f7' : '#17202c'))
      }
    }
  }
})
