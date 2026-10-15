import assert from 'node:assert/strict'
import test from 'node:test'
import { planScreenshots, drawScreenshot, screenshotMaxHeight } from '../src/core/screenshot.js'
import { exportScreenshots } from '../src/services/screenshot.js'
import { rowView } from '../src/core/leaderboard.js'
import { copy, text } from '../src/core/catalog.js'
import { canvasHarness } from './helpers/canvas.mjs'

const model = (counts = [415, 32], dark = false) => ({
  labels: Object.fromEntries(Object.entries(copy).map(([key, value]) => [key, text(value, 'en')])),
  dark, groupingLabel: 'Models', categoryLabel: 'General',
  boards: counts.map((count, side) => ({ title: side ? 'Text Arena' : 'Artificial Analysis',
    tab: side ? 'User votes' : 'Task benchmarks', summary: 'Comparable scores for this source.',
    time: '10/14 23:00', filterLabel: 'Country: All · Source: All', empty: 'No matching entries',
    rows: Array.from({ length: count }, (_, index) => rowView({ rank: index + 1,
      name: `A very detailed model ${index + 1} with complete parameters and parentheses (High, Default Fallback)`,
      score: count - index, openness: index % 2 ? 'open' : 'closed', developerCountry: { countryCode: 'US' } }, { dark })) })),
})

test('complete comparison exports paginate within canvas bounds and retain every name and rank', () => {
  const h = canvasHarness(), source = model(), pages = planScreenshots(h.context, source)
  assert.ok(pages.length > 1)
  for (const page of pages) assert.ok(page.height <= screenshotMaxHeight)
  for (let column = 0; column < 2; column++) {
    const rows = pages.flatMap(page => page.rows.map(row => row.pair[column]).filter(Boolean))
    assert.deepEqual(rows.map(row => row.rank), source.boards[column].rows.map(row => row.rank))
    assert.deepEqual(rows.map(row => row.lines.join('')), source.boards[column].rows.map(row => row.name))
  }
  for (const dark of [false, true]) {
    const source = model([4, 0], dark), page = planScreenshots(h.context, source)[0]
    drawScreenshot(h.context, source, page, new Map())
    const text = h.commands.filter(([name]) => name === 'fillText').map(command => command[1])
    assert.ok(text.includes('No matching entries'))
    assert.ok(text.includes(source.labels.name))
    assert.ok(text.includes('10/14 23:00'))
    assert.ok(text.includes('1 / 1'))
    assert.ok(text.includes('🇺🇸'))
  }
})

test('empty filters still export readable source metadata and a single image', () => {
  const h = canvasHarness(), source = model([0, 0])
  const pages = planScreenshots(h.context, source)
  assert.equal(pages.length, 1)
  assert.equal(pages[0].rows.length, 0)
  assert.ok(pages[0].height > 300)
})

test('export uses real PNG assets with fallback, bounded sequential canvases and temporary cleanup', async () => {
  const h = canvasHarness(), source = model([140, 0]), progress = []
  source.boards[0].rows[0].logo = 'data:image/png;base64,aGVsbG8='
  source.boards[0].rows[1].logo = '/assets/logos/missing.png'
  source.boards[0].rows[2].logo = 'https://untrusted.invalid/image.png'
  const paths = await exportScreenshots({ ...h, model: source, progress: (index, count) => progress.push([index, count]) })
  assert.ok(paths.length > 1)
  assert.equal(paths.length, h.exported.length)
  assert.deepEqual(progress.map(([index]) => index), paths.map((_, index) => index + 1))
  assert.ok(h.exported.every(page => page.width === 2000 && page.height <= screenshotMaxHeight * 2))
  assert.equal(h.files.size, 0)
  assert.equal(h.canvas.width, 1)
  assert.equal(h.canvas.height, 1)
  assert.ok(h.commands.some(([name]) => name === 'drawImage'))
})

test('failed and cancelled exports release their canvas and temporary assets', async () => {
  for (const cancelled of [false, true]) {
    const h = canvasHarness()
    if (!cancelled) h.platform.canvasToTempFilePath = options => options.fail({ errMsg: 'export failed' })
    await assert.rejects(exportScreenshots({ ...h, model: model([100, 0]), isActive: () => !cancelled }))
    assert.equal(h.files.size, 0)
    assert.equal(h.canvas.width, 1)
    assert.equal(h.canvas.height, 1)
  }
})
