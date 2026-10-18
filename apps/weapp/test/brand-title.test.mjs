import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import { brandGlyphs } from '../src/core/brand-glyphs.js'
import { brandTitleLayout, createBrandMeasurer, drawBrandGlyphs, drawBrandLogo } from '../src/core/brand-title.js'
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
    assert.equal(h.commands.filter(([method]) => method === 'createLinearGradient').length, 1)
    assert.ok(h.commands.some(([method]) => method === 'bezierCurveTo' || method === 'quadraticCurveTo'))
    const numeric = new Set(['moveTo', 'lineTo', 'quadraticCurveTo', 'bezierCurveTo'])
    assert.ok(h.commands.filter(([method]) => numeric.has(method)).every(command => command.slice(1).every(Number.isFinite)))
    assert.ok(!h.commands.some(([method]) => method === 'fillText'))
    for (const glyph of title.glyphs) {
      const outline = brandGlyphs[glyph.key]
      for (const dark of [false, true]) {
        const svg = readFileSync(new URL(`../assets/brand-glyphs/${glyph.key}${dark ? '-dark' : ''}.svg`, import.meta.url), 'utf8')
        const tokens = svg.match(/ d="([^"]+)"/)[1].split(/\s+/).map(token => /^[MLQCZ]$/.test(token) ? token : Number(token))
        assert.deepEqual(tokens, outline.commands.flat())
        assert.deepEqual(svg.match(/viewBox="([^"]+)"/)[1].split(' ').map(Number), [0, 0, outline.width, outline.height])
        assert.ok(svg.includes('fill="url(#brand)"'))
        assert.ok(svg.includes(dark ? '#F5F7FA' : '#303945'))
        assert.ok(svg.includes(dark ? '#8D99A8' : '#6C7888'))
        const themed = canvasHarness()
        drawBrandGlyphs(themed.context, title, 10, 20, { dark })
        const stops = [...svg.matchAll(/<stop offset="([^"]+)" stop-color="([^"]+)"/g)]
          .map(([, offset, color]) => ['addColorStop', Number(offset), color])
        assert.deepEqual(themed.commands.filter(([method]) => method === 'addColorStop'), stops)
      }
    }
  }
})

test('the English A leans right in both renderers without clipping, touching I or changing its height', () => {
  for (const size of [14, 21, 42]) {
    const title = brandTitleLayout(null, 'AI BenchGauge', size), h = canvasHarness(), image = {}
    const angle = Number(title.logoStyle.match(/skewX\(([-\d.]+)deg\)/)[1])
    assert.ok(angle < 0 && angle >= -20)
    drawBrandLogo(h.context, image, title, 10, 20)
    assert.deepEqual(h.commands.map(([method]) => method), ['save', 'transform', 'drawImage', 'restore'])
    const [, a, b, c, d, tx, ty] = h.commands[1]
    assert.equal(c, Math.tan(angle * Math.PI / 180))
    const corners = [[0, 0], [title.logoWidth, 0], [0, title.logoHeight], [title.logoWidth, title.logoHeight]]
      .map(([x, y]) => [a * x + c * y + tx, b * x + d * y + ty])
    assert.ok(Math.min(...corners.map(([x]) => x)) >= 10 - 1e-9)
    assert.ok(Math.max(...corners.map(([x]) => x)) < 10 + title.glyphs[0].x)
    assert.equal(Math.min(...corners.map(([, y]) => y)), 20 + title.logoTop)
    assert.equal(Math.max(...corners.map(([, y]) => y)), 20 + title.logoTop + title.logoHeight)
  }
  const chinese = brandTitleLayout(null, 'AI 天梯', 21), h = canvasHarness(), image = {}
  assert.ok(!chinese.logoStyle.includes('transform:'))
  drawBrandLogo(h.context, image, chinese, 10, 20)
  assert.deepEqual(h.commands, [['drawImage', image, 10, 20 + chinese.logoTop, chinese.logoWidth, chinese.logoHeight]])
})
