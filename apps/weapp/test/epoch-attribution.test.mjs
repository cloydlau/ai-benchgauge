import assert from 'node:assert/strict'
import test from 'node:test'
import { epochAttribution } from '../src/core/epoch-attribution.js'
import { planScreenshot, drawScreenshot, screenshotWidth } from '../src/core/screenshot.js'
import { canvasHarness } from './helpers/canvas.mjs'

test('Epoch image attribution survives filtering to zero rows in every language and theme', () => {
  for (const language of ['en', 'zh-CN', 'zh-TW']) for (const dark of [false, true]) {
    const { context, commands } = canvasHarness()
    const model = { language, dark, labels: { name: 'AI BenchGauge', subtitle: 'Models & quotas', rank: 'Rank', country: 'Country', source: 'Source', score: 'Score' },
      grouping: 'model', groupingLabel: 'Models', categoryLabel: 'General',
      boards: [{ kind: 'epochECI', title: 'Epoch ECI', tab: 'Epoch AI', summary: 'Calibrated tests', time: '10/19', filterLabel: 'Country: Unknown', empty: 'No matching entries', rows: [] }] }
    const image = planScreenshot(context, model)
    assert.equal(image.attributionLines.join(''), epochAttribution(language).fullText.replaceAll('\n', ''))
    context.font = '11px sans-serif'
    assert.ok(image.attributionLines.every(line => context.measureText(line).width <= screenshotWidth - 48))
    drawScreenshot(context, model, image, new Map())
    const rendered = commands.filter(([name]) => name === 'fillText')
    for (const line of image.attributionLines) {
      const command = rendered.find(([, value]) => value === line)
      assert.ok(command, 'Attribution line must be drawn')
      assert.ok(command[3] + 6 < image.height, 'Attribution must fit inside the exported image')
    }
    model.boards[0].kind = 'arenaText'
    assert.equal(planScreenshot(context, model).attributionLines.length, 0, 'Do not imply Arena data is licensed by Epoch')
  }
})
