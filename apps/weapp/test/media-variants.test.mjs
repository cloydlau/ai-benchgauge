import test from 'node:test'
import { readFileSync } from 'node:fs'
import assert from 'node:assert/strict'
import { boards, copy, text, mobileBoardHeading } from '../src/core/catalog.js'
import { normalizeBoard, visibleRows, isAAImageCost, isAAVideoCost } from '../src/core/leaderboard.js'
import { normalizePreferences, readSharedPreferences, sharePath } from '../src/core/share-state.js'
import { planScreenshot, drawScreenshot } from '../src/core/screenshot.js'
import { canvasHarness } from './helpers/canvas.mjs'

test('new media snapshots retain their source and price units', () => {
  for (const [kind, image, video] of [
    ['artificialAnalysisImageEditing', true, false],
    ['artificialAnalysisImageToVideo', false, true],
    ['artificialAnalysisVideoEditing', false, true],
    ['arenaImageToVideo', false, false],
    ['arenaVideoEditing', false, false],
    ['arenaImageEditing', false, false],
    ['arenaMultiImageEditing', false, false],
    ['artificialAnalysisSpeechProviderVoice', false, false],
    ['artificialAnalysisSpeechControlledVoice', false, false],
    ['artificialAnalysisSpeechAgent', false, false],
    ['artificialAnalysisSpeechToText', false, false],
    ['artificialAnalysisSpeechToTextStreaming', false, false],
  ]) {
    assert.ok(boards[kind].url.startsWith('https://'))
    assert.equal(isAAImageCost(kind), image)
    assert.equal(isAAVideoCost(kind), video)
    const board = normalizeBoard({ kind, fetchedAt: '2026-10-30T00:00:00Z', entries: [
      { rank: 1, name: 'One', score: 1000, taskCostUSD: 2 },
      { rank: 2, name: 'Two', score: 900, taskCostUSD: 1 },
    ] }, kind)
    assert.deepEqual(visibleRows(board).map(row => row.rank), [1, 2])
    if (image || video) assert.deepEqual(visibleRows(board, { sort: 'cost' }).map(row => row.scoreText), ['$2.00', '$1.00'])
  }
})

test('mobile headings abbreviate all Artificial Analysis boards without changing other sources', () => {
  for (const kind of Object.keys(boards).filter(kind => kind.startsWith('artificialAnalysis'))) {
    for (const language of ['en', 'zh-CN', 'zh-TW']) assert.equal(mobileBoardHeading(kind, language), 'AA')
  }
  assert.equal(mobileBoardHeading('arenaText', 'en'), 'Text Arena')
})

test('speech-to-text renders errors as percentages and ranks companies by the lowest WER', () => {
  const board = { kind: 'artificialAnalysisSpeechToText', entries: [
    { rank: 1, name: 'A', organization: 'OpenAI', score: 1.25 },
    { rank: 2, name: 'B', organization: 'Google', score: 2.5 },
    { rank: 3, name: 'C', organization: 'OpenAI', score: 5 },
  ] }
  const models = visibleRows(board)
  assert.deepEqual(models.map(row => row.scoreText), ['1.25%', '2.50%', '5.00%'])
  assert.ok(models.every(row => row.fillPercent === 0 && row.scoreShare === ''))
  const companies = visibleRows(board, { grouping: 'company' })
  assert.deepEqual(companies.map(row => row.name), ['OpenAI', 'Google'])
  assert.deepEqual(companies.map(row => row.scoreText), ['1.25%', '2.50%'])
})

test('variant choices survive share links and reject mismatched families', () => {
  const variants = { artificialAnalysisTextToVideo: 'artificialAnalysisImageToVideo', arenaTextToVideo: 'arenaVideoEditing' }
  const path = sharePath({ category: 'video', variants }, 'light')
  const query = Object.fromEntries(new URL(`https://example.com${path}`).searchParams)
  assert.deepEqual(readSharedPreferences(query).variants, variants)
  assert.equal(normalizePreferences({ variants: { artificialAnalysisTextToVideo: 'arenaVideoEditing' } }).variants, undefined)
})

test('Arena text scoring variants remain distinct and can be shared', () => {
  const variants = { arenaText: 'arenaTextUncontrolled' }
  const query = Object.fromEntries(new URL(`https://example.com${sharePath({ category: 'general', variants }, 'light')}`).searchParams)
  assert.deepEqual(readSharedPreferences(query).variants, variants)
  assert.notEqual(boards.arenaText.summaries[0], boards.arenaTextUncontrolled.summaries[0])
})

test('Arena image-to-code is selected separately from WebDev', () => {
  const variants = { codeArenaWebDev: 'codeArenaImageToWebDev' }
  const query = Object.fromEntries(new URL(`https://example.com${sharePath({ category: 'coding', variants }, 'light')}`).searchParams)
  assert.deepEqual(readSharedPreferences(query).variants, variants)
})

test('variant exports keep the timestamp in metadata and the selected task in the table heading', () => {
  const h = canvasHarness()
  const model = { language: 'en', dark: false, grouping: 'model', groupingLabel: 'Models', categoryLabel: 'Video',
    labels: Object.fromEntries(Object.entries(copy).map(([key, value]) => [key, text(value, 'en')])),
    boards: [{ kind: 'artificialAnalysisImageToVideo', title: 'Artificial Analysis', heading: 'AA', tab: 'Video',
      summary: 'Video ranking', time: 'Today Published', variantLabel: 'Image to video', filterLabel: 'All', rows: [] }] }
  drawScreenshot(h.context, model, planScreenshot(h.context, model), new Map())
  const labels = h.commands.filter(command => command[0] === 'fillText')
  assert.equal(labels.find(command => command[1] === 'Today Published')[3], 132)
  assert.equal(labels.find(command => command[1] === 'Image to video')[3], 223)
  assert.ok(labels.some(command => command[1] === 'AA'))
  assert.ok(!labels.some(command => command[1] === 'Artificial Analysis'))
})


test('every mobile board has one timestamp above the header, independent of variants', () => {
  const template = readFileSync(new URL('../src/pages/leaderboard/index.wxml', import.meta.url), 'utf8')
  const metadata = template.indexOf('<view class="metadata">')
  const timestamp = template.indexOf('<view class="times"', metadata)
  const header = template.indexOf('<view id="head-anchor-', metadata)
  assert.ok(metadata >= 0 && timestamp > metadata && timestamp < header)
  assert.equal((template.match(/class="times"/g) || []).length, 1)
  assert.match(template.slice(timestamp, header), /bindtap="timeHelp"/)
})
