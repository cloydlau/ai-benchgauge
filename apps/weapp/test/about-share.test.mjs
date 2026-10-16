import assert from 'node:assert/strict'
import test from 'node:test'
import { registerHooks } from 'node:module'
import { pagePreferences, sharePath } from '../src/core/share-state.js'

const registration = registerHooks({
  resolve(specifier, context, next) {
    return specifier === '@vue-mini/core' ? { url: 'benchgauge:test-about', shortCircuit: true } : next(specifier, context)
  },
  load(url, context, next) {
    return url !== 'benchgauge:test-about' ? next(url, context) : {
      format: 'module', shortCircuit: true, source: `
        export const definePage = (factory, config) => { globalThis.aboutFactory = factory; globalThis.aboutConfig = config }
        export const ref = value => ({ value })
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
  assert.equal(globalThis.aboutConfig.canShareToOthers, true)
  assert.equal(about.dark, true)
  assert.equal(about.labels.about, 'About')
  assert.deepEqual(about.investment.metrics.map(item => item.value), ['1,234', '56,789'])
  assert.equal(about.investment.title, 'Costs and investment')
  const forwarded = globalThis.aboutShare()
  assert.ok(forwarded.path.startsWith('/pages/about/index?state='))
  const expected = pagePreferences(query)
  assert.deepEqual(pagePreferences(queryFor(forwarded.path)), expected)
  assert.deepEqual(pagePreferences({}, writes[0]), { ...expected, fromShare: false })
  about.back()
  assert.ok(launches[0].startsWith('/pages/leaderboard/index?state='))
  assert.deepEqual(pagePreferences(queryFor(launches[0])), expected)
})
