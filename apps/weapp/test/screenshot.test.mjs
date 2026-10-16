import assert from 'node:assert/strict'
import test from 'node:test'
import { planScreenshot, drawScreenshot, screenshotStripHeight, screenshotWidth } from '../src/core/screenshot.js'
import { exportScreenshot, removeScreenshot } from '../src/services/screenshot.js'
import { rowView } from '../src/core/leaderboard.js'
import { copy, text } from '../src/core/catalog.js'
import { canvasHarness } from './helpers/canvas.mjs'
import { decodePNG } from './helpers/png.mjs'

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

test('one complete comparison retains every model and rank without page counters', () => {
  const h = canvasHarness(), source = model(), image = planScreenshot(h.context, source)
  assert.ok(image.height > 10000)
  for (let column = 0; column < 2; column++) {
    const rows = image.rows.map(row => row.pair[column]).filter(Boolean)
    assert.deepEqual(rows.map(row => row.rank), source.boards[column].rows.map(row => row.rank))
    assert.deepEqual(rows.map(row => row.lines.join('')), source.boards[column].rows.map(row => row.name))
  }
  for (const dark of [false, true]) {
    const source = model([4, 0], dark), image = planScreenshot(h.context, source)
    drawScreenshot(h.context, source, image, new Map())
    const text = h.commands.filter(([name]) => name === 'fillText').map(command => command[1])
    for (const value of ['No matching entries', source.labels.name, '10/14 23:00', '🇺🇸']) assert.ok(text.includes(value))
    assert.ok(!text.some(value => /^\d+ \/ \d+$/.test(value)))
  }
})

test('empty filters still export readable source metadata in one image', () => {
  const h = canvasHarness(), image = planScreenshot(h.context, model([0, 0]))
  assert.equal(image.rows.length, 0)
  assert.ok(image.height > 300)
})

test('company exports hide source headings and values and reclaim the column for complete names', () => {
  for (const dark of [false, true]) {
    const source = model([2, 2], dark), renders = []
    for (const grouping of ['model', 'company', 'model']) {
      const h = canvasHarness()
      source.grouping = grouping
      const image = planScreenshot(h.context, source)
      drawScreenshot(h.context, source, image, new Map())
      const text = h.commands.filter(([name]) => name === 'fillText')
      assert.equal(text.filter(command => command[1] === source.labels.source).length, grouping === 'company' ? 0 : 2)
      assert.equal(text.filter(command => [source.labels.open, source.labels.closed].includes(command[1])).length, grouping === 'company' ? 0 : 4)
      for (const board of image.boards) for (const row of board.rows) {
        assert.equal(row.lines.join(''), row.name)
        assert.ok(text.some(command => command[1] === row.scoreText))
      }
      renders.push({ image, countryX: text.find(command => command[1] === source.labels.country)[2] })
    }
    assert.equal(renders[1].countryX - renders[0].countryX, 47)
    assert.ok(renders[1].image.rows[0].height < renders[0].image.rows[0].height)
    assert.deepEqual(renders[2], renders[0])
  }
})

test('bounded canvas strips produce one valid full-height PNG and clean up assets', async () => {
  const h = canvasHarness(), source = model([140, 0]), progress = []
  const old = '/private-test/benchgauge-screenshot-old.png', unrelated = '/private-test/other-image.png'
  h.platform.getFileSystemManager().writeFileSync(old, new ArrayBuffer(8))
  h.files.add(unrelated)
  source.boards[0].rows[0].logo = 'data:image/png;base64,aGVsbG8='
  source.boards[0].rows[1].logo = '/assets/logos/missing.png'
  source.boards[0].rows[2].logo = 'https://untrusted.invalid/image.png'
  const expectedHeight = planScreenshot(h.context, source).height
  const path = await exportScreenshot({ ...h, model: source, progress: value => progress.push(value) })
  assert.equal(typeof path, 'string')
  assert.equal(h.contents.get(path).length, 1, 'The final PNG is written once rather than repeatedly appending to the file quota')
  const png = decodePNG(Buffer.concat(h.contents.get(path)))
  assert.equal(png.width, screenshotWidth); assert.equal(png.height, expectedHeight)
  assert.ok(h.exported.length > 1)
  assert.ok(h.exported.every(strip => strip.width === screenshotWidth && strip.height <= screenshotStripHeight))
  assert.ok(progress.every((value, index) => !index || value >= progress[index - 1])); assert.equal(progress.at(-1), 100)
  assert.deepEqual([...h.files], [unrelated, path], 'Recover orphaned exports without removing unrelated files')
  assert.equal(h.canvas.width, 1); assert.equal(h.canvas.height, 1)
  assert.ok(h.commands.some(([name]) => name === 'drawImage'))
  removeScreenshot(h.platform, path); assert.deepEqual([...h.files], [unrelated])
})

test('failed and cancelled exports release their canvas and partial PNG', async () => {
  for (const mode of ['failure', 'write-failure', 'cancel-before', 'cancel-during']) {
    const h = canvasHarness()
    if (mode === 'failure') h.context.getImageData = () => { throw new Error('Canvas unavailable') }
    if (mode === 'write-failure') {
      const fs = h.platform.getFileSystemManager()
      h.platform.getFileSystemManager = () => ({ ...fs, writeFileSync() { throw new Error('File storage unavailable') } })
    }
    await assert.rejects(exportScreenshot({ ...h, model: model([100, 0]),
      isActive: () => mode !== 'cancel-before' && (mode !== 'cancel-during' || h.exported.length < 2) }))
    assert.equal(h.files.size, 0)
    assert.equal(h.canvas.width, 1); assert.equal(h.canvas.height, 1)
  }
})
