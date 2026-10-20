import assert from 'node:assert/strict'
import test from 'node:test'
import { registerHooks } from 'node:module'
import { pagePreferences, sharePath } from '../src/core/share-state.js'
import { copy, text } from '../src/core/catalog.js'

const registration = registerHooks({
  resolve(specifier, context, next) {
    return specifier === '@vue-mini/core' ? { url: 'benchgauge:test-about', shortCircuit: true } : next(specifier, context)
  },
  load(url, context, next) {
    return url !== 'benchgauge:test-about' ? next(url, context) : {
      format: 'module', shortCircuit: true, source: `
        export const definePage = (factory, config) => { globalThis.aboutFactory = factory; globalThis.aboutConfig = config }
        export const ref = value => ({ value })
        export const computed = read => ({ get value() { return read() } })
        export const onShareAppMessage = fn => { globalThis.aboutShare = fn }
      `,
    }
  },
})
await import('../src/pages/about/index.js')
registration.deregister()
const queryFor = path => Object.fromEntries(new URL('https://shared.example' + path).searchParams)

test('about-page menu forwarding and cold-start back navigation retain the originating leaderboard settings', () => {
  const preferences = { category: 'video', grouping: 'company', face: 1, language: 'en', theme: 'system',
    filters: { arenaTextToVideo: { country: 'JP', openness: 'unknown' } } }
  const query = queryFor(sharePath(preferences, 'dark', '/pages/about/index'))
  const writes = [], launches = []
  globalThis.__APP_VERSION__ = '0.0.0'; globalThis.__THIRD_PARTY_NOTICES__ = []
  globalThis.__ENGINEERING_INVESTMENT__ = { commitCount: 1234, codeLineCount: 56789 }
  globalThis.getCurrentPages = () => [{}]
  globalThis.wx = {
    getStorageSync: () => ({ language: 'zh-CN', theme: 'light' }),
    setStorageSync: (key, value) => writes.push(value),
    getWindowInfo: () => ({ statusBarHeight: 24 }),
    getAppBaseInfo: () => ({ theme: 'light' }),
    reLaunch: ({ url }) => launches.push(url),
  }
  const about = globalThis.aboutFactory(query)
  assert.deepEqual(about.items.map(item => [item.id, item.license || null]), [
    ['artificialAnalysis', null],
    ['arena', 'https://creativecommons.org/licenses/by/4.0/'],
    ['epoch', 'https://creativecommons.org/licenses/by/4.0/'],
  ])
  assert.equal(globalThis.aboutConfig.canShareToOthers, true)
  assert.equal(about.dark, true)
  assert.equal(about.labels.about, 'About')
  assert.deepEqual(about.investment.metrics.map(item => item.value), ['1,234', '56,789'])
  assert.equal(about.investment.title, 'Costs and investment')
  assert.equal(about.costGroups.value.every(group => group.collapsed), true)
  const [first, second] = about.costGroups.value
  const toggle = id => about.toggleCostGroup({ currentTarget: { dataset: { id } } })
  toggle(first.id)
  assert.equal(about.costGroups.value[0].collapsed, false)
  assert.equal(about.costGroups.value[1].collapsed, true)
  toggle(second.id)
  assert.equal(about.costGroups.value[0].collapsed, false)
  assert.equal(about.costGroups.value[1].collapsed, false)
  toggle(first.id)
  toggle('unknown')
  assert.equal(about.costGroups.value[0].collapsed, true)
  assert.equal(about.costGroups.value[1].collapsed, false)
  const forwarded = globalThis.aboutShare()
  assert.equal(forwarded.title, `${text(copy.about, 'en')}｜${text(copy.rankingSummary, 'en')}`)
  assert.equal(about.description, text(copy.description, 'en'))
  assert.ok(forwarded.path.startsWith('/pages/about/index?state='))
  const expected = pagePreferences(query)
  assert.deepEqual(pagePreferences(queryFor(forwarded.path)), expected)
  assert.deepEqual(pagePreferences({}, writes[0]), { ...expected, fromShare: false })
  about.back()
  assert.ok(launches[0].startsWith('/pages/leaderboard/index?state='))
  assert.deepEqual(pagePreferences(queryFor(launches[0])), expected)
})

test('about descriptions and share titles reuse common localized copy', () => {
  globalThis.__APP_VERSION__ = '0.0.0'; globalThis.__THIRD_PARTY_NOTICES__ = []
  globalThis.__ENGINEERING_INVESTMENT__ = { commitCount: 1234, codeLineCount: 56789 }
  for (const language of ['en', 'zh-CN', 'zh-TW']) {
    globalThis.wx = {
      getStorageSync: () => ({ language }),
      getWindowInfo: () => ({ statusBarHeight: 24 }),
      getAppBaseInfo: () => ({ theme: 'light' }),
    }
    const about = globalThis.aboutFactory({})
    assert.equal(about.description, text(copy.description, language))
    const title = globalThis.aboutShare().title
    assert.equal(title, `${about.labels.about}｜${text(copy.rankingSummary, language)}`)
    assert.ok(!title.includes(text(copy.tagline, language)))
    assert.ok(about.description.includes(text(copy.tagline, language)))
  }
})
