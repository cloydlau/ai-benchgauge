import assert from 'node:assert/strict'
import test from 'node:test'
import { arenaAttribution } from '../src/core/arena-attribution.js'
import { planScreenshot, drawScreenshot, screenshotWidth } from '../src/core/screenshot.js'
import { canvasHarness } from './helpers/canvas.mjs'

test('official Arena dataset credits survive empty filters and fit exported images in every language/theme', () => {
  for (const language of ['en', 'zh-CN', 'zh-TW']) for (const dark of [false, true]) {
    const { context, commands } = canvasHarness()
    const notice = arenaAttribution(language)
    const model = { language, dark, labels: { name: 'AI BenchGauge', subtitle: 'Models & quotas', rank: 'Rank', country: 'Country', source: 'Source', score: 'Score' },
      grouping: 'model', groupingLabel: 'Models', categoryLabel: 'General',
      boards: [{ kind: 'arenaText', sourceNote: notice.sourceURL, title: 'Text Arena', tab: 'Arena', summary: 'Blind votes',
        time: '10/19', filterLabel: 'Unknown', empty: 'No matching entries', rows: [] }] }
    const image = planScreenshot(context, model)
    assert.equal(image.attributionLines.join(''), notice.fullText.replaceAll('\n', ''))
    context.font = '11px sans-serif'
    assert.ok(image.attributionLines.every(line => context.measureText(line).width <= screenshotWidth - 48))
    drawScreenshot(context, model, image, new Map())
    for (const line of image.attributionLines) {
      const command = commands.find(([name, value]) => name === 'fillText' && value === line)
      assert.ok(command); assert.ok(command[3] + 6 < image.height)
    }
    delete model.boards[0].sourceNote
    assert.equal(planScreenshot(context, model).attributionLines.length, 0, 'Website caches must not acquire a dataset license label')
    model.boards[0].kind = 'artificialAnalysis'; model.boards[0].sourceNote = notice.sourceURL
    assert.equal(planScreenshot(context, model).attributionLines.length, 0)
  }
})
