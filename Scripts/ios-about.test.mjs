import assert from 'node:assert/strict'
import test from 'node:test'
import { iosAboutContent } from './ios-about.mjs'
import { copy, text } from '../apps/weapp/src/core/catalog.js'
import { investmentContent, investmentSchedule } from '../apps/weapp/src/core/investment.js'

test('iOS About exports the same localized descriptions, metrics and cost definitions as the mini-program', () => {
  const stats = { commitCount: 1234, codeLineCount: 56789 }
  const content = iosAboutContent(stats)
  assert.equal(content.sources.length, 5)
  assert.equal(content.desktopDownloadURL, 'https://github.com/cloydlau/ai-benchgauge/releases/latest')
  for (const language of ['en', 'zh-CN', 'zh-TW']) {
    const entry = content.languages[language]
    assert.equal(entry.descriptionLines.join(language === 'en' ? ' ' : ''), text(copy.description, language))
    assert.deepEqual(entry.investment.metrics.map(metric => metric.value), ['1,234', '56,789'])
    assert.deepEqual(entry.investment, investmentContent(stats, language, { now: investmentSchedule.startedAt }))
    const development = entry.investment.groups.find(group => group.id === 'development')
    assert.equal(development.items.find(item => item.id === 'tokens').monthlyAmount, 2000)
    assert.equal(development.items.find(item => item.id === 'staff').amount, null)
  }
  assert.deepEqual(content.schedule, investmentSchedule)
})
