import assert from 'node:assert/strict'
import test from 'node:test'
import { readFileSync, readdirSync } from 'node:fs'
import { bundledFlags } from '../src/core/flag-catalog.js'
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
    time: side ? '10/14 23:00 Updated' : '10/14 22:00 Published', isSourceTime: !side,
    filterLabel: 'Country: All · Source: All', empty: 'No matching entries',
    rows: Array.from({ length: count }, (_, index) => rowView({ rank: index + 1,
      name: `A very detailed model ${index + 1} with complete parameters and parentheses (High, Default Fallback)`,
      score: count - index, openness: index % 2 ? 'open' : 'closed', developerCountry: { countryCode: 'US' } }, { dark })) })),
})

test('exports draw exactly one timestamp per board, including the fetch-only fallback', () => {
  for (const dark of [false, true]) {
    const h = canvasHarness(), source = model([0, 0], dark)
    drawScreenshot(h.context, source, planScreenshot(h.context, source), new Map())
    const times = h.commands.filter(([name, value]) => name === 'fillText' && / (Published|Updated)$/.test(value))
    assert.equal(times.length, 2)
    for (const [index, board] of source.boards.entries()) {
      assert.equal(times[index][1], board.time)
      assert.equal(times[index][3], 132)
    }
  }
})

test('exported score shares sit below the score without changing row geometry', () => {
  for (const dark of [false, true]) {
    const h = canvasHarness(), source = model([2, 0], dark)
    const before = planScreenshot(h.context, source)
    source.boards[0].rows[1].scoreShare = '50%'
    const image = planScreenshot(h.context, source)
    assert.deepEqual(image.rows.map(row => [row.y, row.height]), before.rows.map(row => [row.y, row.height]))
    drawScreenshot(h.context, source, image, new Map())
    const share = h.commands.find(([name, value]) => name === 'fillText' && value === '50%')
    const row = image.rows[1]
    assert.equal(share[3], row.y + row.height / 2 + 12)
    assert.ok(share[3] + 5 < row.y + row.height)
  }
})

test('exported score bars span every column after rank without narrowing name layout', () => {
  for (const dark of [false, true]) for (const grouping of ['model', 'company']) {
    const h = canvasHarness(), source = model([3, 0], dark)
    source.grouping = grouping
    const before = planScreenshot(h.context, source)
    source.boards[0].rows = [100, 50, 0].map((score, index) => rowView({
      rank: index + 1, name: source.boards[0].rows[index].name, score,
    }, { dark, leaderScore: 100 }))
    const image = planScreenshot(h.context, source)
    assert.deepEqual(image.rows.map(row => [row.y, row.height, row.pair[0].lines]),
      before.rows.map(row => [row.y, row.height, row.pair[0].lines]))
    drawScreenshot(h.context, source, image, new Map())
    for (const [index, width] of [410, 205, 0].entries()) {
      const y = image.rows[index].y + 4
      const start = h.commands.findIndex(([name, x, top]) => name === 'moveTo' && x === 77 && top === y)
      if (!width) assert.equal(start, -1)
      else assert.deepEqual(h.commands[start + 1], ['lineTo', 72 + width - 5, y])
    }
  }
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
    for (const value of ['No matching entries', source.labels.name, '10/14 22:00 Published', '10/14 23:00 Updated', 'US']) assert.ok(text.includes(value))
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

test('bundled country flags are valid PNGs and obey shared country normalization', () => {
  const directory = new URL('../assets/flags/', import.meta.url)
  assert.deepEqual(readdirSync(directory).filter(name => name.endsWith('.png')).sort(), [...bundledFlags].map(code => `${code.toLowerCase()}.png`).sort())
  for (const code of bundledFlags) {
    const png = readFileSync(new URL(`${code.toLowerCase()}.png`, directory))
    assert.deepEqual([...png.subarray(0, 8)], [137, 80, 78, 71, 13, 10, 26, 10], code)
    assert.equal(png.readUInt32BE(16), 64, code); assert.equal(png.readUInt32BE(20), 48, code)
  }
  for (const code of ['CN', 'HK', 'MO', 'TW', ' cn ']) {
    const row = rowView({ rank: 1, name: 'Model', score: 1, developerCountry: { countryCode: code } })
    assert.equal(row.countryCode, 'CN'); assert.equal(row.flagImage, '/assets/flags/cn.png')
  }
  for (const code of ['HK', 'MO', 'TW']) assert.ok(!bundledFlags.has(code))
  assert.match(readFileSync(new URL('LICENSE', directory), 'utf8'), /MIT License/)
})

test('country raster assets render in both columns, themes and groupings, including later strips', async () => {
  for (const dark of [false, true]) for (const grouping of ['model', 'company']) {
    const h = canvasHarness(), source = model([35, 35], dark)
    source.grouping = grouping
    const codes = ['US', 'CN', 'FR', 'CA', 'GB', 'JP']
    for (const board of source.boards) board.rows = board.rows.map((row, index) => ({ ...row,
      ...rowView({ rank: row.rank, name: row.name, score: row.score, developerCountry: { countryCode: codes[index % codes.length] } }, { dark }) }))
    const plan = planScreenshot(h.context, source)
    await exportScreenshot({ ...h, model: source })
    const draws = h.commands.filter(([name, image]) => name === 'drawImage' && image.src?.startsWith('/assets/flags/'))
    for (const [index, row] of plan.rows.entries()) for (const column of [0, 1]) {
      const x = 24 + column * 486 + 466 - 122 + (grouping === 'company' ? 47 : 0)
      assert.ok(draws.some(([, image, left, top, width, height]) => image.src === `/assets/flags/${codes[index % codes.length].toLowerCase()}.png`
        && left === x - 12 && top === row.y + row.height / 2 - 9 && width === 24 && height === 18))
    }
    assert.ok(plan.rows.at(-1).y > screenshotStripHeight)
    assert.ok(!h.commands.some(([name, value]) => name === 'fillText' && /[\u{1F1E6}-\u{1F1FF}]/u.test(value)))
  }
})

test('unavailable flag images and unknown countries export readable fallbacks', async () => {
  const h = canvasHarness(), source = model([3, 0])
  source.boards[0].rows = ['US', 'ZZ', null].map((code, index) => rowView({ rank: index + 1, name: 'Model', score: 1,
    developerCountry: { countryCode: code } }))
  source.boards[0].rows[0].flagImage = '/assets/flags/missing.png'
  assert.equal(source.boards[0].rows[1].flagImage, '')
  await exportScreenshot({ ...h, model: source })
  const values = h.commands.filter(([name]) => name === 'fillText').map(([, value]) => value)
  for (const value of ['US', 'ZZ', '?']) assert.ok(values.includes(value))
  assert.ok(!values.some(value => /[\u{1F1E6}-\u{1F1FF}]/u.test(value)))
})
