import assert from 'node:assert/strict'
import test from 'node:test'
import { execFileSync } from 'node:child_process'
import { purchaseLinks, preferredPurchaseLink } from '../src/core/purchase-links.js'
import { rowView } from '../src/core/leaderboard.js'
import catalog from '../../../fc/purchase-links.json' with { type: 'json' }

test('native and mini-program purchase links share one validated catalog', () => {
  execFileSync(process.execPath, ['Scripts/generate-purchase-links.mjs', '--check'], { cwd: new URL('../../../', import.meta.url) })
  for (const variants of Object.values(catalog.vendors)) for (const links of Object.values(variants)) {
    for (const link of [...(links.codingPlan || []), ...(links.payAsYouGo || [])]) {
      const url = new URL(link.url)
      assert.equal(url.protocol, 'https:')
      assert.ok(url.hostname)
      assert.equal(url.username + url.password, '')
      assert.doesNotMatch(link.url, /\s/)
    }
  }
})

test('language selects mainland or international purchase sites with a single-site fallback', () => {
  for (const organization of ['Alibaba', 'Z.ai', 'Tencent', 'MiniMax', 'KlingAI', 'Xiaomi']) {
    for (const links of Object.values(purchaseLinks(organization))) {
      assert.equal(preferredPurchaseLink(links, 'zh-CN').site, 'mainlandChina')
      for (const language of ['en', 'zh-TW']) assert.equal(preferredPurchaseLink(links, language).site, 'international')
    }
  }
  const only = [{ site: 'mainlandChina', url: 'https://example.cn/pricing' }]
  assert.equal(preferredPurchaseLink(only, 'en'), only[0])
  assert.equal(preferredPurchaseLink([], 'zh-CN'), undefined)
  assert.equal(preferredPurchaseLink(purchaseLinks('ByteDance Seed', { category: 'coding' }).codingPlan, 'en').url,
    'https://www.volcengine.com/activity/codingplan')
  assert.equal(preferredPurchaseLink(purchaseLinks('ByteDance Seed', { category: 'video' }).codingPlan, 'en').url,
    'https://dreamina.capcut.com/pricing/dreamina-price')
  assert.deepEqual(purchaseLinks('Alibaba', { category: 'video' }).codingPlan, [])
  assert.deepEqual(purchaseLinks('StepFun', { category: 'image' }), { codingPlan: [], payAsYouGo: [] })
})

test('organization aliases and missing Devin organizations preserve purchase links', () => {
  for (const [alias, canonical] of Object.entries(catalog.aliases)) assert.deepEqual(purchaseLinks(alias), purchaseLinks(canonical))
  assert.deepEqual(purchaseLinks(null, { modelName: 'Devin CLI' }), purchaseLinks('Devin'))
  for (const organization of ['Unknown maker', 'Reve', 'Video Rebirth', '__proto__', 'constructor']) {
    assert.deepEqual(purchaseLinks(organization), { codingPlan: [], payAsYouGo: [] })
  }
})

test('company actions distinguish MiniMax coding subscriptions from Hailuo video and API pricing', () => {
  const entry = { rank: 1, name: 'MiniMax', organization: 'MiniMax', score: 99 }
  const code = rowView(entry, { company: true, language: 'zh-CN', category: 'coding' })
  assert.deepEqual(code.purchaseActions.map(action => action.title), ['套餐', '按量'])
  assert.equal(code.purchaseActions[0].url, 'https://platform.minimax.cn/subscribe/coding-plan')
  const video = rowView(entry, { company: true, language: 'zh-TW', category: 'video' })
  assert.equal(video.purchaseActions[0].url, 'https://hailuoai.video/subscribe')
  assert.equal(video.purchaseActions[1].url, 'https://platform.minimax.io/docs/pricing/overview')
  assert.deepEqual(rowView(entry).purchaseActions, [])
  assert.deepEqual(rowView({ ...entry, organization: 'Unknown' }, { company: true }).purchaseActions, [])
  assert.deepEqual(rowView({ ...entry, organization: 'DeepSeek' }, { company: true }).purchaseActions.map(action => action.kind), ['payAsYouGo'])
})
