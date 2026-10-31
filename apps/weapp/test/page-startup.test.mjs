import test from 'node:test'
import assert from 'node:assert/strict'

// Use the installed Vue Mini implementation: replacing lifecycle hooks with
// callbacks would accept a component-only hook that a real Page never invokes.
let options
globalThis.Page = value => { options = value }
globalThis.__SHARED_ENDPOINT__ = 'https://shared.example'
await import('../src/pages/leaderboard/index.js')

test('real Vue Mini Page starts the uncached first request from its native lifecycle', async t => {
  const requests = []
  globalThis.wx = {
    getStorageSync: () => ({}), setStorageSync() {},
    getWindowInfo: () => ({ statusBarHeight: 24, windowWidth: 375 }),
    getMenuButtonBoundingClientRect: () => ({ top: 28, bottom: 60, left: 270 }),
    getAppBaseInfo: () => ({ theme: 'light', language: 'zh_CN' }),
    setNavigationBarColor() {}, onThemeChange() {}, offThemeChange() {},
    request(value) { requests.push(value); return { abort() { value.fail(); value.complete() } } },
    createSelectorQuery() { const q = { select: () => ({ fields: () => q, boundingClientRect: () => q }), exec: cb => cb([null]) }; return q },
  }
  const page = { data: {}, setData(data, done) { Object.assign(this.data, data); done?.() } }
  for (const name of ['createSelectorQuery', 'createIntersectionObserver', 'createMediaQueryObserver', 'selectComponent', 'selectAllComponents', 'getTabBar', 'getPageId', 'animate', 'clearAnimation', 'getOpenerEventChannel', 'applyAnimatedStyle', 'clearAnimatedStyle', 'setUpdatePerformanceListener', 'getPassiveEvent', 'setPassiveEvent', 'setInitialRenderingCache']) page[name] = () => ({})
  Object.assign(page, options)
  t.after(() => page.onUnload())
  page.onLoad({})
  assert.equal(requests.length, 1, 'A real page load must issue a request before any user interaction')
  assert.equal(requests[0].method, 'GET')
  assert.ok(requests[0].url.endsWith('/artificialAnalysis'))
  page.onShow()
  assert.equal(requests.length, 1, 'onShow must not duplicate the startup request')
  requests[0].success({ statusCode: 200, data: { board: { kind: 'artificialAnalysis', fetchedAt: new Date().toISOString(), entries: [{ rank: 1, name: 'First model', score: 100 }] } } })
  requests[0].complete()
  await new Promise(resolve => setImmediate(resolve))
  assert.equal(page.data.cards[0].hasBoard, true)
  assert.equal(page.data.cards[0].rows[0].name, 'First model')
  assert.equal(page.data.cards[0].loading, false)
  assert.equal(requests.length, 1, 'Fresh shared data does not require origin acquisition')
})
