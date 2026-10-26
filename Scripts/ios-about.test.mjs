import assert from 'node:assert/strict'
import test from 'node:test'
import { iosAboutContent } from './ios-about.mjs'
import { copy, text } from '../apps/weapp/src/core/catalog.js'
import { investmentContent, investmentSchedule } from '../apps/weapp/src/core/investment.js'
import { syncInvestmentRuntime } from '../apps/weapp/scripts/engineering-investment.mjs'
import { aboutPlatforms } from '../apps/weapp/src/core/about-platforms.js'

test('mini-program and native cost adapters match the configured Calmmit source', () => {
  assert.deepEqual(syncInvestmentRuntime({ check: true }), [])
})

test('iOS About exports the same localized descriptions, metrics and cost definitions as the mini-program', () => {
  const stats = { commitCount: 1234, codeLineCount: 56789 }
  const content = iosAboutContent(stats)
  assert.equal(content.sources.length, 6)
  assert.equal(content.desktopDownloadURL, 'https://github.com/cloydlau/ai-benchgauge/releases/latest')
  assert.equal(content.repositoryURL, 'https://github.com/cloydlau/ai-benchgauge')
  for (const language of ['en', 'zh-CN', 'zh-TW']) {
    const entry = content.languages[language]
    assert.equal(entry.descriptionLines.join(language === 'en' ? ' ' : ''), text(copy.description, language))
    assert.deepEqual(entry.investment.metrics.map(metric => metric.value), ['1,234', '56,789'])
    assert.deepEqual(entry.investment, investmentContent(stats, language, { now: investmentSchedule.startedAt }))
    assert.deepEqual(entry.platforms, aboutPlatforms(language))
    const development = entry.investment.groups.find(group => group.id === 'development')
    assert.equal(development.items.find(item => item.id === 'tokens').monthlyAmount, 2000)
    assert.equal(development.items.find(item => item.id === 'staff').amount, null)
  }
  assert.deepEqual(content.schedule, investmentSchedule)
})
