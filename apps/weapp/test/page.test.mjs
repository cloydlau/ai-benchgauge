import assert from 'node:assert/strict'
import test from 'node:test'
import { registerHooks } from 'node:module'
import { readFileSync } from 'node:fs'
import { canvasHarness } from './helpers/canvas.mjs'
import { pagePreferences } from '../src/core/share-state.js'
import { boards, categories, copy, text, desktopDownloadURL } from '../src/core/catalog.js'

// Exercise the real page controller with deterministic lifecycle/network hooks.
// This does not substitute for WeChat's Vue bridge or native visual verification.
const registration = registerHooks({
  resolve(specifier, context, next) {
    return specifier === '@vue-mini/core' ? { url: 'benchgauge:test-vue', shortCircuit: true } : next(specifier, context)
  },
  load(url, context, next) {
    if (url !== 'benchgauge:test-vue') return next(url, context)
    return { format: 'module', shortCircuit: true, source: `
      export const definePage = (factory, config) => { globalThis.__benchPageFactory = factory; globalThis.__benchPageConfig = config }
      export const ref = value => ({ value })
      export const computed = getter => ({ get value() { return getter() } })
      export const onLoad = fn => { globalThis.__benchHooks.load = fn }
      export const onReady = fn => { globalThis.__benchHooks.ready = fn }
      export const onShow = fn => { globalThis.__benchHooks.show = fn }
      export const onHide = fn => { globalThis.__benchHooks.hide = fn }
      export const onUnload = fn => { globalThis.__benchHooks.unload = fn }
      export const onResize = fn => { globalThis.__benchHooks.resize = fn }
      export const onShareAppMessage = fn => { globalThis.__benchHooks.share = fn }
    ` }
  },
})
await import('../src/pages/leaderboard/index.js')
registration.deregister()

function setup(preferences = {}, count = 0, query = {}, systemTheme = 'light', systemLocale = 'zh_CN', cachedBoards = {}) {
  const requests = []; const writes = []; const modals = []; const clipboard = []; const scrolls = []
  globalThis.__SHARED_ENDPOINT__ = 'https://shared.example'
  globalThis.__benchHooks = {}
  let themeListener
  globalThis.wx = {
    getStorageSync: key => key === 'benchgauge.preferences' ? preferences : key === 'benchgauge.boards.v1' ? cachedBoards : {},
    setStorageSync: (key, value) => writes.push({ key, value }),
    getWindowInfo: () => ({ statusBarHeight: 24, windowWidth: 375 }),
    getMenuButtonBoundingClientRect: () => ({ top: 28, bottom: 60, left: 270 }),
    getAppBaseInfo: () => ({ theme: systemTheme, language: systemLocale }),
    onThemeChange: fn => { themeListener = fn }, offThemeChange: () => { themeListener = null },
    setNavigationBarColor() {}, showModal: options => modals.push(options),
    setClipboardData: options => clipboard.push(options.data), navigateTo() {},
    request(options) { const task = { abort() { options.fail(); options.complete() } }; requests.push({ options, task }); return task },
    createSelectorQuery() {
      const results = []
      const query = {
        select: selector => ({
          node() { results.push({ node: { scrollTo: options => scrolls.push({ selector, ...options }) } }); return query },
          fields() { results.push(null); return query },
          boundingClientRect() { results.push(null); return query },
        }),
        exec: callback => callback(results),
      }
      return query
    },
  }
  const page = globalThis.__benchPageFactory(query)
  const respond = index => {
    const request = requests[index]; const kind = request.options.url.split('/').at(-1)
    request.options.success({ statusCode: 200, data: { board: { kind, fetchedAt: '2026-10-13T12:00:00Z', entries: count ? Array.from({ length: count }, (_, i) => ({
      rank: i + 1, name: `Model ${i + 1}`, score: count - i, organization: `Maker ${i + 1}`,
      openness: i % 2 ? 'open' : 'closed',
    })) : [
      { rank: 1, name: 'Closed model', score: 99, organization: 'OpenAI', openness: 'closed', developerCountry: { key: 'openai', countryCode: 'US' } },
      { rank: 2, name: 'Open model', score: 98, organization: 'DeepSeek', openness: 'open', developerCountry: { key: 'deepseek', countryCode: 'CN' } },
    ] } } }); request.options.complete()
  }
  return { page, requests, writes, modals, clipboard, scrolls, respond, theme: theme => themeListener?.({ theme }) }
}
const event = dataset => ({ currentTarget: { dataset } })

test('leaving the page while search bounds are pending cannot expand or focus it later', async () => {
  const h = setup()
  let measured
  wx.createSelectorQuery = () => {
    const query = { select: () => ({ boundingClientRect: () => query }), exec: callback => { measured = callback } }
    return query
  }
  h.page.openModelSearch()
  globalThis.__benchHooks.hide()
  measured([])
  await new Promise(resolve => setTimeout(resolve, 40))
  assert.equal(h.page.modelSearchVisible.value, false)
  assert.equal(h.page.modelSearchFocused.value, false)
  globalThis.__benchHooks.unload()
})

test('one live model query survives source/category/company switches and clearing restores both boards', async () => {
  const h = setup({}, 1000)
  const loading = globalThis.__benchHooks.load(); h.respond(0); h.respond(1); await loading
  const initialRequests = h.requests.length
  h.page.openModelSearch()
  await new Promise(resolve => setTimeout(resolve, 30))
  assert.equal(h.page.modelSearchVisible.value, true)
  h.page.inputModelSearch({ detail: { value: 'Model 997' } })
  for (const card of h.page.cards.value) {
    assert.equal(card.count, 1)
    assert.equal(card.rows[0].rank, 997)
    assert.equal(card.rows[0].top, 0)
    assert.equal(card.rows[0].scoreShare, '0%')
  }
  assert.equal(h.requests.length, initialRequests, 'Filtering must not fetch a board')
  h.page.selectFace(event({ index: 1 }))
  assert.equal(h.page.modelSearchQuery.value, 'Model 997')
  assert.equal(h.page.cards.value[1].count, 1)
  h.page.selectGrouping(event({ id: 'company' }))
  assert.equal(h.page.modelSearchVisible.value, false)
  assert.equal(h.page.cards.value[0].count, 1000)
  h.page.selectGrouping(event({ id: 'model' }))
  assert.equal(h.page.modelSearchVisible.value, false)
  assert.equal(h.page.cards.value[0].count, 1)
  h.page.selectCategory(event({ id: 'coding' }))
  h.respond(initialRequests); h.respond(initialRequests + 1)
  await new Promise(resolve => setTimeout(resolve, 0))
  assert.equal(h.page.modelSearchQuery.value, 'Model 997')
  assert.ok(h.page.cards.value.every(card => card.count === 1))
  h.page.inputModelSearch({ detail: { value: 'no match' } })
  assert.ok(h.page.cards.value.every(card => card.count === 0 && card.filtered))
  h.page.clearFilters()
  assert.equal(h.page.modelSearchQuery.value, '')
  assert.ok(h.page.cards.value.every(card => card.count === 1000))
  h.page.closeModelSearch()
  await new Promise(resolve => setTimeout(resolve, 330))
  assert.equal(h.page.modelSearchVisible.value, false)
  assert.equal(h.page.modelSearchFocused.value, false, 'A pending focus must not reopen the keyboard after cancel')
  globalThis.__benchHooks.unload()
})

test('blur retains a nonempty search and its results without restoring keyboard focus', async () => {
  const h = setup({}, 1000)
  const loading = globalThis.__benchHooks.load(); h.respond(0); h.respond(1); await loading
  h.page.openModelSearch()
  await new Promise(resolve => setTimeout(resolve, 30))
  h.page.inputModelSearch({ detail: { value: 'Model 997' } })
  h.page.deferModelSearchBlur()
  await new Promise(resolve => setTimeout(resolve, 350))
  assert.equal(h.page.modelSearchVisible.value, true)
  assert.equal(h.page.modelSearchFocused.value, false, 'Blur must cancel the pending opening focus')
  assert.equal(h.page.modelSearchQuery.value, 'Model 997')
  assert.equal(h.page.cards.value[0].count, 1)
  h.page.focusModelSearch()
  assert.equal(h.page.modelSearchFocused.value, true)
  h.page.deferModelSearchBlur()
  h.page.clearModelSearch()
  await new Promise(resolve => setTimeout(resolve, 100))
  assert.equal(h.page.modelSearchVisible.value, true)
  assert.equal(h.page.modelSearchFocused.value, true)
  assert.equal(h.page.modelSearchQuery.value, '')
  globalThis.__benchHooks.unload()
})

test('automatic blur exits only when the latest query trims to empty', async () => {
  for (const query of ['', '   ', '\t\n\u3000', 'Model', '  Model \u3000']) {
    const h = setup()
    h.page.openModelSearch()
    await new Promise(resolve => setTimeout(resolve, 30))
    h.page.inputModelSearch({ detail: { value: query } })
    h.page.deferModelSearchBlur()
    await new Promise(resolve => setTimeout(resolve, 100))
    assert.equal(h.page.modelSearchVisible.value, Boolean(query.trim()), JSON.stringify(query))
    assert.equal(h.page.modelSearchFocused.value, false)
    assert.equal(h.page.modelSearchQuery.value, query)
    if (!query.trim()) {
      h.page.focusModelSearch()
      assert.equal(h.page.modelSearchFocused.value, false, 'Late focus must not reopen collapsed search')
    }
    globalThis.__benchHooks.unload()
  }
  const h = setup()
  h.page.openModelSearch()
  await new Promise(resolve => setTimeout(resolve, 30))
  h.page.deferModelSearchBlur()
  h.page.inputModelSearch({ detail: { value: 'arrived after blur' } })
  await new Promise(resolve => setTimeout(resolve, 100))
  assert.equal(h.page.modelSearchVisible.value, true, 'Check the latest query when the delayed blur completes')
  h.page.closeModelSearch()
  assert.equal(h.page.modelSearchVisible.value, false, 'Explicit Cancel still exits a nonempty search')
  assert.equal(h.page.modelSearchQuery.value, '')
  globalThis.__benchHooks.unload()
})

test('clearing keeps search open when the native blur arrives after the clear tap', async () => {
  const h = setup()
  h.page.openModelSearch()
  await new Promise(resolve => setTimeout(resolve, 30))
  h.page.inputModelSearch({ detail: { value: 'Model' } })
  h.page.clearModelSearch()
  h.page.deferModelSearchBlur()
  await new Promise(resolve => setTimeout(resolve, 120))
  assert.equal(h.page.modelSearchQuery.value, '')
  assert.equal(h.page.modelSearchVisible.value, true, 'A delayed blur from Clear must not exit search')
  assert.equal(h.page.modelSearchFocused.value, true)
  h.page.focusModelSearch()
  h.page.inputModelSearch({ detail: { value: 'Again' } })
  assert.equal(h.page.modelSearchQuery.value, 'Again')
  h.page.closeModelSearch()
  await new Promise(resolve => setTimeout(resolve, 120))
  assert.equal(h.page.modelSearchVisible.value, false)
  assert.equal(h.page.modelSearchFocused.value, false)
  globalThis.__benchHooks.unload()
})

test('a slow Clear gesture survives blur, restores all rows and leaves later outside blur unchanged', async () => {
  const h = setup({}, 1000)
  const loading = globalThis.__benchHooks.load(); h.respond(0); h.respond(1); await loading
  h.page.openModelSearch()
  await new Promise(resolve => setTimeout(resolve, 30))
  h.page.inputModelSearch({ detail: { value: 'Model 997' } })
  h.page.beginModelSearchClear()
  h.page.deferModelSearchBlur()
  await new Promise(resolve => setTimeout(resolve, 120))
  assert.equal(h.page.modelSearchVisible.value, true)
  h.page.focusModelSearch()
  h.page.clearModelSearch()
  await new Promise(resolve => setTimeout(resolve, 20))
  assert.equal(h.page.modelSearchVisible.value, true)
  assert.equal(h.page.modelSearchFocused.value, true)
  assert.ok(h.page.cards.value.every(card => card.count === 1000))
  h.page.focusModelSearch()
  h.page.deferModelSearchBlur()
  await new Promise(resolve => setTimeout(resolve, 120))
  assert.equal(h.page.modelSearchVisible.value, false, 'An unrelated outside blur still leaves search')
  globalThis.__benchHooks.unload()
})

test('cancelled Clear gestures and leaving the page cannot leave focus recovery running', async () => {
  for (const leave of ['cancelGesture', 'cancelSearch', 'hide', 'unload']) {
    const h = setup()
    h.page.openModelSearch()
    await new Promise(resolve => setTimeout(resolve, 30))
    h.page.inputModelSearch({ detail: { value: 'Model' } })
    h.page.beginModelSearchClear()
    h.page.deferModelSearchBlur()
    if (leave === 'cancelGesture') h.page.cancelModelSearchClear()
    else if (leave === 'cancelSearch') { h.page.clearModelSearch(); h.page.closeModelSearch() }
    else { h.page.clearModelSearch(); globalThis.__benchHooks[leave]() }
    await new Promise(resolve => setTimeout(resolve, 120))
    assert.equal(h.page.modelSearchVisible.value, leave === 'cancelGesture', leave)
    assert.equal(h.page.modelSearchFocused.value, false, leave)
    globalThis.__benchHooks.unload()
  }
})

test('country and source taps explain the current row in each language without copying or opening details', async () => {
  for (const [language, country, closed, open] of [
    ['zh-CN', '美国', '闭源', '开源'], ['zh-TW', '美國', '閉源', '開源'], ['en', 'United States', 'Closed', 'Open'],
  ]) {
    const h = setup({ language })
    const loading = globalThis.__benchHooks.load(); h.respond(0); h.respond(1); await loading
    const kind = h.page.cards.value[0].kind, toasts = []
    wx.showToast = options => toasts.push(options)
    const tap = (attribute, rank = 1, extra = {}) => h.page.attributeHint(event({ kind, rank, attribute, ...extra }))
    tap('country'); assert.equal(toasts.at(-1).title, country)
    tap('openness'); assert.equal(toasts.at(-1).title, closed)
    tap('openness', 2); assert.equal(toasts.at(-1).title, open)
    assert.ok(toasts.every(toast => toast.icon === 'none' && toast.duration === 1800))
    const count = toasts.length
    tap('country', 999); tap('country', 1, { kind: h.page.cards.value[1].kind }); tap('bad')
    h.page.cubeBusy.value = true; tap('country'); h.page.cubeBusy.value = false
    h.page.quotaHelp(); tap('country'); h.page.closeFeatureHelp()
    assert.equal(toasts.length, count)
    assert.deepEqual(h.clipboard, []); assert.deepEqual(h.modals, [])
    h.page.selectGrouping(event({ id: 'company' }))
    tap('openness'); assert.equal(toasts.length, count)
    tap('country'); assert.equal(toasts.at(-1).title, country)
    assert.equal(h.page.companyDetails.value.open, false)
    globalThis.__benchHooks.unload()
  }
})

test('unknown source taps remain unknown and swiping across an attribute does not show a hint', async () => {
  const h = setup({ language: 'zh-CN' }, 0, {}, 'light', 'zh_CN', {
    artificialAnalysis: { kind: 'artificialAnalysis', fetchedAt: '2026-10-13T12:00:00Z', entries: [
      { rank: 1, name: 'Unverified fixture', score: 80, organization: 'Unverified studio', openness: null },
    ] },
  }), toasts = []
  wx.showToast = options => toasts.push(options)
  const kind = h.page.cards.value[0].kind
  const tap = () => h.page.attributeHint(event({ kind, rank: 1, attribute: 'country' }))
  tap(); assert.equal(toasts.at(-1).title, '未知')
  h.page.attributeHint(event({ kind, rank: 1, attribute: 'openness' }))
  assert.equal(toasts.at(-1).title, '未知')
  const touch = (x, y) => ({ touches: [{ clientX: x, clientY: y }] })
  h.page.cubeStart(touch(280, 200)); h.page.cubeMove(touch(40, 200)); h.page.cubeEnd()
  tap(); assert.equal(toasts.length, 2)
  globalThis.__benchHooks.unload()
})

test('all custom overlays lock the page and native boards without disabling popup content scrolling', () => {
  const template = readFileSync(new URL('../src/pages/leaderboard/index.wxml', import.meta.url), 'utf8')
  assert.match(template, /^<page-meta page-style="\{\{backgroundLocked \? 'overflow:hidden;' : ''\}\}" \/>/)
  const board = template.match(/<scroll-view id="board-scroll-[\s\S]*?>/)[0]
  for (const attribute of ['scroll-y', 'refresher-enabled']) {
    assert.ok(board.includes(`${attribute}="{{!backgroundLocked && (!cubeDragging || face !== card.index)}}"`))
  }
  const overlays = template.match(/<van-(?:dialog|action-sheet|popup)\b[^>]*>/g)
  assert.equal(overlays.length, 4)
  // Intercepting touchstart on Vant's host swallows native taps on its choices
  // and buttons. The board bindings above provide the background scroll lock.
  for (const overlay of overlays) assert.doesNotMatch(overlay, /catch:touchstart/)
  // Catching touchmove on a common ancestor would also suppress inner scrolling.
  assert.doesNotMatch(template, /catch:touchmove/)
  assert.match(template, /hidden="\{\{!backToTop \|\| cubeBusy \|\| backgroundLocked\}\}"/)
})

test('company, filter, settings and help overlays block gestures and refresh while preserving the scroll window', async () => {
  const h = setup({ grouping: 'company' }, 1000)
  const loading = globalThis.__benchHooks.load(); h.respond(0); h.respond(1); await loading
  const kind = h.page.cards.value[0].kind
  h.page.scroll({ currentTarget: { dataset: { kind } }, detail: { scrollTop: 2400 } })
  const rows = h.page.cards.value[0].rows, tabs = h.page.sourceTabsStyle.value, scrollCount = h.scrolls.length
  const touch = (x, y) => ({ touches: [{ clientX: x, clientY: y }] })
  const checkLocked = async () => {
    assert.equal(h.page.backgroundLocked.value, true)
    h.page.cubeStart(touch(280, 200)); h.page.cubeMove(touch(40, 200)); h.page.cubeEnd()
    assert.equal(h.page.face.value, 0)
    assert.equal(h.page.cubeDragging.value, false)
    assert.equal(h.page.cubeBusy.value, false)
    await h.page.pullRefresh()
    assert.equal(h.requests.length, 2)
    assert.equal(h.page.pullRefreshing.value, false)
    assert.deepEqual(h.page.cards.value[0].rows, rows)
    assert.equal(h.page.sourceTabsStyle.value, tabs)
    assert.equal(h.scrolls.length, scrollCount)
  }
  h.page.rowDetails(event({ kind, rank: 51 })); await checkLocked()
  h.page.closeCompanyDetails(); assert.equal(h.page.backgroundLocked.value, false)
  h.page.filterMenu(event({ kind, mode: 'country' })); await checkLocked()
  h.page.closeSheet(); assert.equal(h.page.backgroundLocked.value, false)
  h.page.preferences(event({ mode: 'theme' })); await checkLocked()
  h.page.closeSheet(); assert.equal(h.page.backgroundLocked.value, false)
  h.page.cubeStart(touch(280, 200)); h.page.cubeMove(touch(270, 200))
  h.page.quotaHelp(); await checkLocked()
  h.page.closeFeatureHelp(); assert.equal(h.page.backgroundLocked.value, false)
  assert.equal(h.page.backToTop.value, true)
  // Dismissing one overlay cannot unlock another overlay that is still open.
  h.page.rowDetails(event({ kind, rank: 51 })); h.page.quotaHelp()
  h.page.closeCompanyDetails(); assert.equal(h.page.backgroundLocked.value, true)
  h.page.copyDesktopLink(); assert.equal(h.page.backgroundLocked.value, false)
  h.page.cubeStart(touch(280, 200)); h.page.cubeMove(touch(40, 200))
  assert.equal(h.page.cubeDragging.value, true, 'Gestures resume after dismissal')
  globalThis.__benchHooks.unload()
})

test('company purchase buttons copy the resolved official link with the standard copied message and no name modal', async () => {
  for (const language of ['zh-CN', 'en', 'zh-TW']) {
    const h = setup({ grouping: 'company', language })
    const loading = globalThis.__benchHooks.load()
    h.respond(0); h.respond(1); await loading
    const card = h.page.cards.value[0]
    const row = card.rows.find(row => row.name === 'OpenAI')
    assert.equal(row.purchaseActions.length, 2)
    const copies = [], toasts = []
    wx.setClipboardData = options => { copies.push(options.data); options.success() }
    wx.showToast = options => toasts.push(options)
    for (const action of row.purchaseActions) {
      h.page.copyPurchaseLink(event({ kind: card.kind, rank: row.rank, purchase: action.kind, url: 'https://untrusted.example' }))
      assert.equal(copies.at(-1), action.url)
      assert.equal(toasts.at(-1).title, h.page.labels.value.copied)
      assert.equal(toasts.at(-1).icon, 'none')
    }
    assert.equal(h.modals.length, 0)
    const count = copies.length
    for (const patch of [{ purchase: '__proto__' }, { rank: 99999 }, { kind: 'missing' }]) {
      h.page.copyPurchaseLink(event({ kind: card.kind, rank: row.rank, purchase: 'codingPlan', ...patch }))
    }
    h.page.cubeBusy.value = true
    h.page.copyPurchaseLink(event({ kind: card.kind, rank: row.rank, purchase: 'codingPlan' }))
    h.page.cubeBusy.value = false
    h.page.grouping.value = 'model'
    h.page.copyPurchaseLink(event({ kind: card.kind, rank: row.rank, purchase: 'codingPlan' }))
    assert.equal(copies.length, count)
    h.page.grouping.value = 'company'
    wx.setClipboardData = options => options.fail()
    h.page.copyPurchaseLink(event({ kind: card.kind, rank: row.rank, purchase: 'codingPlan' }))
    assert.equal(toasts.at(-1).title, h.page.labels.value.copyLinkFailed)
    globalThis.__benchHooks.unload()
  }
})

test('purchase links update after switching the interface language inside the same virtual window', async () => {
  const h = setup({ grouping: 'company', language: 'zh-CN' })
  const loading = globalThis.__benchHooks.load()
  for (let index = 0; index < 2; index++) {
    const request = h.requests[index], kind = request.options.url.split('/').at(-1)
    request.options.success({ statusCode: 200, data: { board: { kind, fetchedAt: '2026-10-16T00:00:00Z',
      entries: [{ rank: 1, name: 'MiniMax M', organization: 'MiniMax', score: 99 }] } } })
    request.options.complete()
  }
  await loading
  const before = h.page.cards.value[0].rows[0]
  assert.equal(before.purchaseActions[0].url, 'https://platform.minimax.cn/subscribe/coding-plan')
  h.page.preferences(event({ mode: 'language' }))
  h.page.sheetSelect({ detail: { value: 'en', mode: 'language' } })
  const after = h.page.cards.value[0].rows[0]
  assert.notEqual(after, before)
  assert.equal(after.purchaseActions[0].url, 'https://platform.minimax.io/subscribe/coding-plan')
  assert.equal(after.purchaseActions[0].title, 'Plan')
  globalThis.__benchHooks.unload()
})

test('loading skeletons cover the viewport at startup and after tall or landscape resizing', () => {
  const h = setup()
  const covers = height => {
    const count = h.page.skeletonRows.value.length, rowHeight = h.page.cards.value[0].rowHeight
    assert.ok(count * rowHeight >= height, 'Loading placeholders must reach the bottom of the window')
    assert.ok(count * rowHeight < height + rowHeight * 2, 'Only the visible window and a spare row need placeholders')
  }
  covers(667)
  for (const [windowWidth, windowHeight] of [[375, 1000], [834, 1210], [1210, 834], [375, 560]]) {
    wx.getWindowInfo = () => ({ windowWidth, windowHeight, statusBarHeight: 24 })
    globalThis.__benchHooks.resize()
    covers(windowHeight)
  }
  assert.ok(h.page.cards.value.every(card => !card.hasBoard && card.rows.length === 0))
  globalThis.__benchHooks.unload()
})

test('subtitle help offers dismissal and copies the desktop link only on its link action in every language', () => {
  for (const [language, title, gotIt, desktopLink] of [
    ['en', 'Dual boards & quota tracking', 'Got it', 'PC link'],
    ['zh-CN', '双榜对照 & 余量追踪', '我知道了', 'PC 端链接'],
    ['zh-TW', '雙榜對照 & 餘量追蹤', '我知道了', 'PC 端連結'],
  ]) {
    const h = setup({ language })
    h.page.quotaHelp()
    assert.equal(h.page.showingFeatureHelp.value, true)
    assert.equal(h.page.labels.value.featureDetails, title)
    assert.equal(h.page.quotaHelpContent.value, h.page.labels.value.quotaHelp)
    assert.match(h.page.quotaHelpContent.value, /PC/)
    assert.doesNotMatch(h.page.quotaHelpContent.value, /Mac|Windows/)
    assert.equal(h.page.labels.value.gotIt, gotIt)
    assert.equal(h.page.labels.value.desktopLink, desktopLink)
    h.page.closeFeatureHelp()
    assert.equal(h.page.showingFeatureHelp.value, false)
    assert.deepEqual(h.clipboard, [])
    h.page.quotaHelp()
    h.page.copyDesktopLink()
    assert.equal(h.page.showingFeatureHelp.value, false)
    assert.deepEqual(h.clipboard, [desktopDownloadURL])
    globalThis.__benchHooks.unload()
  }
})

test('header title follows capsule height and fits alongside controls across mobile sizes and languages', () => {
  for (const language of ['zh-CN', 'zh-TW', 'en']) {
    const h = setup({ language })
    const fonts = new Map()
    for (const width of [280, 320, 375, 402, 430]) for (const height of [28, 32, 36]) {
      wx.getWindowInfo = () => ({ statusBarHeight: 24, windowWidth: width })
      wx.getMenuButtonBoundingClientRect = () => ({ top: 28, bottom: 28 + height, height, left: width - 94 })
      globalThis.__benchHooks.resize()
      const title = h.page.brandTitle.value
      assert.equal(h.page.groupingControl.value.height, height)
      assert.ok(h.page.groupingControl.value.fontSize >= height * 0.34)
      assert.ok(title.height > 0 && title.height <= height * (language === 'en' ? 0.8 : 0.85) + 0.001)
      assert.ok(title.subtitleHeight > 0 && title.subtitleHeight <= height + 0.001)
      assert.ok(title.subtitleFontSize > 0)
      const captionWidth = language === 'en' ? title.subtitleFontSize * 10.5 : title.subtitleFontSize * 10.88
      const availableWidth = width - h.page.capsuleWidth.value - h.page.groupingControl.value.width - width / 750 * 38
      assert.ok(title.width + captionWidth <= availableWidth + 0.001)
      if (language !== 'en' && width >= 320) assert.ok(title.subtitleFontSize >= 6.5 - 0.001)
      if (height === 32) fonts.set(width, title.subtitleFontSize)
      assert.ok(title.width < width - 106 - 24 * width / 750)
      if (language !== 'en' && width >= 430 && height <= 32) assert.ok(Math.abs(title.height - height * 0.85) < 0.001)
    }
    if (language !== 'en') {
      assert.ok(fonts.get(280) < fonts.get(430))
      assert.equal(fonts.get(430), 12)
    }
    globalThis.__benchHooks.unload()
  }
})

test('automatic refresh failures quietly retain rows and time; only a manual pull owns the spinner', async () => {
  const h = setup()
  const first = globalThis.__benchHooks.load()
  assert.equal(h.page.pullRefreshing.value, false)
  h.respond(0); h.respond(1); await first
  const before = h.page.cards.value.map(card => ({ rows: card.rows, time: card.time }))
  const retry = h.page.refreshCategory()
  assert.equal(h.page.pullRefreshing.value, false)
  for (const request of h.requests.slice(2)) { request.options.fail(); request.options.complete() }
  await retry
  assert.deepEqual(h.page.cards.value.map(card => ({ rows: card.rows, time: card.time })), before)
  assert.equal(h.modals.length, 0)
  assert.ok(h.page.cards.value.every(card => !card.failed))
  const pull = h.page.pullRefresh()
  assert.equal(h.page.pullRefreshing.value, true)
  for (const request of h.requests.slice(4)) { request.options.fail(); request.options.complete() }
  await pull
  assert.equal(h.page.pullRefreshing.value, false)
  assert.deepEqual(h.page.cards.value.map(card => ({ rows: card.rows, time: card.time })), before)
  globalThis.__benchHooks.unload()
})

test('page lifecycle paints independent sources, honors the new tabs/headings and does not duplicate requests', async () => {
  const h = setup(); const loading = globalThis.__benchHooks.load()
  assert.equal(h.page.headerTop.value, 28)
  assert.equal(h.page.navHeight.value, 68)
  assert.equal(h.page.capsuleWidth.value, 113)
  globalThis.__benchHooks.show()
  assert.equal(h.requests.length, 2)
  assert.deepEqual(h.page.tabs.value, ['任务测评', '用户盲测'])
  h.respond(1); await Promise.resolve(); await Promise.resolve()
  h.respond(0); await loading
  assert.deepEqual(h.page.cards.value.map(card => [card.title, card.rows.length]), [['Artificial Analysis', 2], ['Text Arena', 2]])
  assert.equal(h.page.cards.value[0].updated, '—')
  h.page.selectFace(event({ index: 1 })); assert.equal(h.page.face.value, 1)
  h.page.selectCategory(event({ id: 'video' })); assert.equal(h.requests.length, 4)
  h.respond(2); h.respond(3); await new Promise(resolve => setImmediate(resolve))
  assert.equal(h.page.cards.value[0].kind, 'artificialAnalysisTextToVideo')
  const shared = pagePreferences(Object.fromEntries(new URL('https://shared.example' + globalThis.__benchHooks.share().path).searchParams))
  assert.equal(shared.category, 'video')
  assert.equal(shared.face, 1)
  globalThis.__benchHooks.unload()
})

test('every category and source shares the current page title and common localized tagline', () => {
  for (const language of ['en', 'zh-CN', 'zh-TW']) for (const category of categories) for (const face of [0, 1]) {
    const h = setup({ language, category: category.id, face })
    const message = globalThis.__benchHooks.share()
    assert.equal(message.title, `${text(face ? copy.votes : copy.tasks, language)}｜${text(copy.tagline, language)}`)
    const shared = pagePreferences(Object.fromEntries(new URL('https://shared.example' + message.path).searchParams))
    assert.equal(shared.category, category.id)
    assert.equal(shared.face, face)
    globalThis.__benchHooks.unload()
  }
})

test('menu sharing restores live choices and all filters over conflicting receiver preferences', async () => {
  const sender = setup({ filters: { artificialAnalysis: { country: 'US', openness: 'closed' } } })
  assert.equal(globalThis.__benchPageConfig.canShareToOthers, true)
  sender.page.selectCategory(event({ id: 'video' }))
  sender.respond(0); sender.respond(1); await new Promise(resolve => setImmediate(resolve))
  sender.page.selectGrouping(event({ id: 'company' }))
  sender.page.changeFace({ detail: { current: 1 } })
  sender.page.preferences(event({ mode: 'language' }))
  sender.page.sheetSelect({ detail: { mode: 'language', value: 'zh-TW' } })
  sender.page.preferences(event({ mode: 'theme' }))
  sender.page.sheetSelect({ detail: { mode: 'theme', value: 'dark' } })
  sender.page.filterMenu(event({ kind: 'arenaTextToVideo', mode: 'country' }))
  sender.page.sheetSelect({ detail: { value: 'CN' } })
  sender.page.filterMenu(event({ kind: 'arenaTextToVideo', mode: 'openness' }))
  sender.page.sheetSelect({ detail: { value: 'open' } })
  const message = globalThis.__benchHooks.share()
  assert.equal(message.title, `${text(copy.votes, 'zh-TW')}｜${text(copy.tagline, 'zh-TW')}`)
  const query = Object.fromEntries(new URL('https://shared.example' + message.path).searchParams)
  const expected = pagePreferences(query)
  globalThis.__benchHooks.unload()
  const receiver = setup({ category: 'coding', grouping: 'model', face: 0, language: 'en', theme: 'light',
    filters: { arenaTextToVideo: { country: 'US', openness: 'closed' }, arenaText: { country: 'unknown', openness: 'unknown' } } }, 0, query)
  assert.equal(receiver.page.category.value, 'video')
  assert.equal(receiver.page.grouping.value, 'company')
  assert.equal(receiver.page.face.value, 1)
  assert.equal(receiver.page.dark.value, true)
  assert.equal(receiver.page.labels.value.source, '原始碼')
  const saved = receiver.writes.find(write => write.key === 'benchgauge.preferences').value
  assert.deepEqual(pagePreferences({}, saved), { ...expected, fromShare: false })
  const loaded = globalThis.__benchHooks.load(); receiver.respond(0); receiver.respond(1); await loaded
  assert.equal(receiver.page.cards.value[1].count, 1)
  assert.equal(receiver.page.cards.value[1].rows[0].name, 'DeepSeek')
  assert.equal(receiver.page.cards.value[1].rows[0].flag, '🇨🇳')
  assert.deepEqual(pagePreferences(Object.fromEntries(new URL('https://shared.example' + globalThis.__benchHooks.share().path).searchParams)), expected)
  globalThis.__benchHooks.unload()
  const reopened = setup(saved)
  assert.equal(reopened.page.category.value, 'video')
  assert.equal(reopened.page.face.value, 1)
  globalThis.__benchHooks.unload()
})

test('system appearance shares match the sender initially and respond to later receiver changes', () => {
  setup({ theme: 'system' }, 0, {}, 'dark')
  const message = globalThis.__benchHooks.share()
  const query = Object.fromEntries(new URL('https://shared.example' + message.path).searchParams)
  globalThis.__benchHooks.unload()
  const receiver = setup({ theme: 'light' }, 0, query, 'light')
  assert.equal(receiver.page.dark.value, true)
  assert.equal(receiver.writes[0].value.theme, 'system')
  receiver.theme('light')
  assert.equal(receiver.page.dark.value, false)
  receiver.theme('dark')
  assert.equal(receiver.page.dark.value, true)
  receiver.page.preferences(event({ mode: 'theme' }))
  receiver.page.sheetSelect({ detail: { mode: 'theme', value: 'light' } })
  assert.equal(receiver.page.dark.value, false)
  globalThis.__benchHooks.unload()
})

test('filter highlights update on selection before closing and stay current across reopen and cold start', async () => {
  const h = setup(); const loading = globalThis.__benchHooks.load()
  h.respond(0); h.respond(1); await loading
  const kind = 'artificialAnalysis'
  const check = (page, selected) => {
    assert.deepEqual(page.sheet.value.actions.filter(action => action.color).map(action => action.value), [selected])
    assert.ok(page.sheet.value.actions.every(action => typeof action.color === 'string'))
  }
  h.page.filterMenu(event({ kind, mode: 'country' })); check(h.page, 'all')
  for (const selected of ['CN', 'US', 'all', 'CN']) {
    assert.equal(h.page.backgroundLocked.value, true)
    h.page.sheetSelect({ detail: h.page.sheet.value.actions.find(action => action.value === selected) })
    assert.equal(h.page.sheet.value.open, false)
    assert.equal(h.page.backgroundLocked.value, false)
    check(h.page, selected)
    assert.equal(h.page.cards.value[0].count, selected === 'all' ? 2 : 1)
    h.page.filterMenu(event({ kind, mode: 'country' })); check(h.page, selected)
    h.page.closeSheet()
    h.page.filterMenu(event({ kind, mode: 'country' })); check(h.page, selected)
  }
  h.page.filterMenu(event({ kind: 'arenaText', mode: 'country' })); check(h.page, 'CN')
  h.page.filterMenu(event({ kind, mode: 'country' })); check(h.page, 'CN')
  h.page.filterMenu(event({ kind, mode: 'openness' }))
  h.page.sheetSelect({ detail: h.page.sheet.value.actions.find(action => action.value === 'open') })
  check(h.page, 'open')
  const saved = h.writes.findLast(write => write.key === 'benchgauge.preferences').value
  globalThis.__benchHooks.unload()
  const restored = setup(saved)
  const restoredLoading = globalThis.__benchHooks.load()
  restored.respond(0); restored.respond(1); await restoredLoading
  restored.page.filterMenu(event({ kind, mode: 'country' })); check(restored.page, 'CN')
  restored.page.filterMenu(event({ kind, mode: 'openness' })); check(restored.page, 'open')
  globalThis.__benchHooks.unload()
})

test('both sources share country and openness, union country choices, reset scroll and clear together', async () => {
  const h = setup(); const loading = globalThis.__benchHooks.load()
  const kinds = ['artificialAnalysis', 'arenaText']
  for (const [index, kind] of kinds.entries()) {
    h.requests[index].options.success({ statusCode: 200, data: { board: { kind, fetchedAt: '2026-10-13T12:00:00Z', entries: [
      { rank: 1, name: index ? 'China model' : 'US model', score: 90, openness: index ? 'open' : 'closed',
        organization: index ? 'DeepSeek' : 'OpenAI', developerCountry: { key: index ? 'deepseek' : 'openai', countryCode: index ? 'CN' : 'US' } },
    ] } } }); h.requests[index].options.complete()
  }
  await loading
  h.page.scroll({ ...event({ kind: kinds[0] }), detail: { scrollTop: 700 } })
  h.page.scroll({ ...event({ kind: kinds[1] }), detail: { scrollTop: 800 } })
  h.page.filterMenu(event({ kind: kinds[1], mode: 'country' }))
  assert.deepEqual(h.page.sheet.value.actions.map(action => action.value), ['all', 'CN', 'US'])
  h.page.sheetSelect({ detail: h.page.sheet.value.actions.find(action => action.value === 'CN') })
  assert.deepEqual(h.page.cards.value.map(card => card.count), [0, 1])
  for (const kind of kinds) {
    assert.ok(h.scrolls.some(scroll => scroll.selector === `#board-scroll-${kind}` && scroll.top === 0))
  }
  h.page.changeFace({ detail: { current: 0 } })
  h.page.filterMenu(event({ kind: kinds[0], mode: 'country' }))
  assert.equal(h.page.sheet.value.actions.find(action => action.color).value, 'CN')
  h.page.filterMenu(event({ kind: kinds[0], mode: 'openness' }))
  h.page.sheetSelect({ detail: h.page.sheet.value.actions.find(action => action.value === 'open') })
  h.page.filterMenu(event({ kind: kinds[1], mode: 'openness' }))
  assert.equal(h.page.sheet.value.actions.find(action => action.color).value, 'open')
  const shared = pagePreferences(Object.fromEntries(new URL('https://shared.example' + globalThis.__benchHooks.share().path).searchParams))
  for (const kind of kinds) assert.deepEqual(shared.filters[kind], { country: 'CN', openness: 'open' })
  h.page.clearFilters(event({ kind: kinds[1] }))
  assert.deepEqual(h.page.cards.value.map(card => [card.count, card.filtered]), [[1, false], [1, false]])
  h.page.filterMenu(event({ kind: kinds[0], mode: 'country' }))
  assert.equal(h.page.sheet.value.actions.find(action => action.color).value, 'all')
  globalThis.__benchHooks.unload()
})

test('all categories share filters in both directions, including before data arrives and after clearing', async () => {
  const h = setup(); const loading = globalThis.__benchHooks.load()
  h.respond(0); h.respond(1); await loading
  const select = (kind, mode, value) => {
    h.page.filterMenu(event({ kind, mode }))
    h.page.sheetSelect({ detail: h.page.sheet.value.actions.find(action => action.value === value) })
  }
  select('arenaText', 'country', 'CN'); select('arenaText', 'openness', 'open')
  for (const category of categories.slice(1)) {
    const start = h.requests.length
    h.page.selectCategory(event({ id: category.id }))
    for (const kind of category.kinds) for (const [mode, value] of [['country', 'CN'], ['openness', 'open']]) {
      h.page.filterMenu(event({ kind, mode }))
      assert.equal(h.page.sheet.value.actions.find(action => action.color)?.value, value)
    }
    h.respond(start); h.respond(start + 1); await new Promise(resolve => setImmediate(resolve))
    assert.ok(h.page.cards.value.every(card => card.count === 1 && card.rows[0].flag === '🇨🇳' && card.rows[0].openness === 'open'))
  }
  select('arenaTextToVideo', 'country', 'US'); select('arenaTextToVideo', 'openness', 'closed')
  const saved = h.writes.findLast(write => write.key === 'benchgauge.preferences').value
  for (const kind of Object.keys(boards)) assert.deepEqual(saved.filters[kind], { country: 'US', openness: 'closed' })
  h.page.selectCategory(event({ id: 'general' }))
  assert.ok(h.page.cards.value.every(card => card.count === 1 && card.rows[0].flag === '🇺🇸' && card.rows[0].openness === 'closed'))
  h.page.clearFilters()
  for (const category of categories) {
    h.page.selectCategory(event({ id: category.id }))
    assert.ok(h.page.cards.value.every(card => card.count === 2 && !card.filtered))
    for (const kind of category.kinds) for (const mode of ['country', 'openness']) {
      h.page.filterMenu(event({ kind, mode }))
      assert.equal(h.page.sheet.value.actions.find(action => action.color)?.value, 'all')
    }
  }
  assert.deepEqual(pagePreferences(Object.fromEntries(new URL('https://shared.example' + globalThis.__benchHooks.share().path).searchParams)).filters, {})
  globalThis.__benchHooks.unload()
  const restored = setup(saved)
  restored.page.selectCategory(event({ id: 'coding' }))
  restored.page.filterMenu(event({ kind: 'codeArenaWebDev', mode: 'country' }))
  assert.equal(restored.page.sheet.value.actions.find(action => action.color)?.value, 'US')
  restored.page.filterMenu(event({ kind: 'codeArenaWebDev', mode: 'openness' }))
  assert.equal(restored.page.sheet.value.actions.find(action => action.color)?.value, 'closed')
  globalThis.__benchHooks.unload()
})

test('ten thousand rows only cross the bridge in bounded windows, including fast jumps and filter resets', async () => {
  const h = setup({}, 10000)
  const pending = globalThis.__benchHooks.load(); h.respond(0); h.respond(1); await pending
  let card = h.page.cards.value[0]
  assert.equal(card.count, 10000)
  assert.ok(card.rows.length < 50)
  assert.equal(card.height, 480000)
  assert.ok(JSON.stringify(h.page.cards.value).length < 50000)
  h.page.scroll({ ...event({ kind: card.kind }), detail: { scrollTop: 470000 } })
  card = h.page.cards.value[0]
  assert.ok(card.rows[0].rank > 9700)
  assert.ok(card.rows.length < 50)
  const start = card.rows[0].rank
  h.page.scroll({ ...event({ kind: card.kind }), detail: { scrollTop: 470001 } })
  assert.equal(h.page.cards.value[0].rows[0].rank, start)
  h.page.scroll({ ...event({ kind: card.kind }), detail: { scrollTop: 480000 } })
  assert.equal(h.page.cards.value[0].rows.at(-1).rank, 10000)
  assert.equal(h.page.backToTop.value, true, 'Reaching the last row must keep return-to-top available')
  h.page.top()
  h.page.scroll({ ...event({ kind: card.kind }), detail: { scrollTop: 0 } })
  assert.equal(h.page.cards.value[0].rows[0].rank, 1)
  assert.equal(h.page.backToTop.value, false, 'Returning to the native top hides the floating control')
  h.page.rowDetails(event({ kind: card.kind, rank: 10000 }))
  assert.equal(h.clipboard.at(-1), 'Model 10000')
  assert.equal(h.modals.length, 0)
  h.page.filterMenu(event({ kind: card.kind, mode: 'openness' }))
  h.page.sheetSelect({ detail: h.page.sheet.value.actions.find(action => action.value === 'open') })
  assert.equal(h.page.cards.value[0].count, 5000)
  assert.equal(h.page.cards.value[0].rows[0].rank, 2)
  assert.equal(h.page.backToTop.value, false)
  h.page.selectGrouping(event({ id: 'company' }))
  assert.equal(h.page.cards.value[0].rows[0].name, 'Maker 2')
  assert.equal(h.page.cards.value[0].rows[0].rank, 1)
  globalThis.__benchHooks.unload()
})

test('the selected category returns only the active board to top on a double tap, without refreshing', async t => {
  t.mock.timers.enable({ apis: ['Date', 'setTimeout'], now: 1000 })
  for (const face of [0, 1]) {
    const h = setup({ face }, 1000)
    const loading = globalThis.__benchHooks.load(); h.respond(0); h.respond(1); await loading
    const kind = h.page.cards.value[face].kind
    h.page.scroll({ ...event({ kind }), detail: { scrollTop: 1200 } })
    const rows = h.page.cards.value[face].rows
    const commands = h.scrolls.length, requests = h.requests.length, writes = h.writes.length
    const tap = () => h.page.selectCategory(event({ id: 'general' }))
    tap()
    assert.equal(h.scrolls.length, commands, 'A single tap must preserve the scroll position')
    assert.equal(h.page.backToTop.value, true)
    assert.deepEqual(h.page.cards.value[face].rows, rows)
    t.mock.timers.tick(301); tap()
    assert.equal(h.scrolls.length, commands, 'Separate taps must not count as a double tap')
    t.mock.timers.tick(150); tap()
    assert.deepEqual(h.scrolls.slice(commands), [{ selector: `#board-scroll-${kind}`, top: 0, animated: false }])
    tap()
    assert.equal(h.scrolls.length, commands + 1, 'A third tap starts a new pair')
    assert.equal(h.requests.length, requests)
    assert.equal(h.writes.length, writes)
    globalThis.__benchHooks.hide(); t.mock.timers.tick(100); tap()
    assert.equal(h.scrolls.length, commands + 1, 'Hiding the page clears the pending tap')
    globalThis.__benchHooks.unload()
  }
})

test('measured header origin follows the scroll container and stale layout callbacks are ignored', async () => {
  const h = setup({}, 10000)
  const callbacks = []
  wx.nextTick = action => action()
  wx.createSelectorQuery = () => ({
    select() { return { fields() {}, boundingClientRect() {} } },
    exec: callback => callbacks.push(callback),
  })
  const pending = globalThis.__benchHooks.load(); h.respond(0); h.respond(1); await pending
  const rects = [{ top: 50, height: 480, scrollTop: 0 }, { top: 250 }, { top: 50, height: 0 }, null]
  callbacks.at(-1)(rects)
  const kind = h.page.cards.value[0].kind
  h.page.scroll({ ...event({ kind }), detail: { scrollTop: 24200 } })
  const current = h.page.cards.value[0]
  assert.equal(current.rows[0].rank, 489)
  assert.ok(current.rows.length <= 35)
  assert.equal(current.rows[0].top, 488 * 48)
  globalThis.__benchHooks.unload()
  callbacks.at(-1)([{ top: 0, height: 50 }, { top: -99999 }, null, null])
  assert.equal(h.page.cards.value[0].rows[0].rank, 489)
})
test('scrolling ahead of a pending geometry query cannot move the virtual origin or blank the viewport', async () => {
  const h = setup({}, 10000), callbacks = []
  wx.nextTick = action => action()
  wx.createSelectorQuery = () => ({
    select() { return { fields() {}, boundingClientRect() {} } },
    exec: callback => callbacks.push(callback),
  })
  const loaded = globalThis.__benchHooks.load(); h.respond(0); h.respond(1); await loaded
  const kind = h.page.cards.value[0].kind
  const atTop = [{ top: 50, height: 480, scrollTop: 0 }, { top: 250 }, null, null]
  callbacks.at(-1)(atTop)
  const refresh = h.page.refreshTap(event({ kind })); h.respond(2); await refresh
  h.page.scroll({ ...event({ kind }), detail: { scrollTop: 4300 } })
  callbacks.at(-1)(atTop)
  assert.equal(h.page.cards.value[0].rows[0].rank, 74)
  assert.ok(h.page.cards.value[0].rows.some(row => row.rank === 100))
  const next = h.page.refreshTap(event({ kind })); h.respond(3); await next
  h.page.scroll({ ...event({ kind }), detail: { scrollTop: 5000 } })
  callbacks.at(-1)([{ top: 50, height: 480, scrollTop: 4300 }, { top: -4050 }, null, null])
  assert.equal(h.page.cards.value[0].rows[0].rank, 89)
  h.page.scroll({ ...event({ kind }), detail: { scrollTop: 0 } })
  assert.equal(h.page.cards.value[0].rows[0].rank, 1)
  globalThis.__benchHooks.unload()
})

test('native scroll commands are explicit, repeatable and discard superseded or unloaded callbacks', async () => {
  const h = setup({}, 1000), loaded = globalThis.__benchHooks.load()
  h.respond(0); h.respond(1); await loaded
  const callbacks = [], commands = []
  wx.createSelectorQuery = () => ({
    select() { return { node() {} } },
    exec: callback => callbacks.push(callback),
  })
  h.page.top(); h.page.top()
  const result = [{ node: { scrollTo: value => commands.push(value) } }]
  callbacks[0](result); assert.equal(commands.length, 0)
  callbacks[1](result); assert.deepEqual(commands, [{ top: 0, animated: false }])
  h.page.scroll({ ...event({ kind: 'artificialAnalysis' }), detail: { scrollTop: 4300 } })
  assert.equal(callbacks.length, 2, 'Updating a virtual window must never issue a scroll command')
  h.page.top(); globalThis.__benchHooks.unload(); callbacks[2](result)
  assert.equal(commands.length, 1)
})

test('board headings copy their complete localized titles across categories and grouping modes', () => {
  for (const language of ['en', 'zh-CN', 'zh-TW']) for (const category of categories) for (const grouping of ['model', 'company']) {
    const h = setup({ language, category: category.id, grouping })
    for (const card of h.page.cards.value) h.page.copyBoardTitle(event({ kind: card.kind }))
    assert.deepEqual(h.clipboard, h.page.cards.value.map(card => card.title))
    h.page.copyBoardTitle(event({ kind: 'invalid' }))
    assert.equal(h.clipboard.length, 2)
    assert.equal(h.modals.length, 0)
    globalThis.__benchHooks.unload()
  }
})

test('board-heading copy ignores cube drags and accidental taps immediately after a swipe', t => {
  t.mock.timers.enable({ apis: ['Date', 'setTimeout'], now: 1000 })
  const h = setup()
  const kind = h.page.cards.value[0].kind
  const touch = (x, y) => ({ touches: [{ clientX: x, clientY: y }] })
  h.page.cubeStart(touch(250, 200)); h.page.cubeMove(touch(210, 202))
  h.page.copyBoardTitle(event({ kind }))
  assert.deepEqual(h.clipboard, [])
  h.page.cubeCancel(); t.mock.timers.tick(24); t.mock.timers.tick(341)
  assert.equal(h.page.cubeBusy.value, false)
  h.page.copyBoardTitle(event({ kind }))
  assert.deepEqual(h.clipboard, [])
  t.mock.timers.tick(36)
  h.page.copyBoardTitle(event({ kind }))
  assert.deepEqual(h.clipboard, [h.page.cards.value[0].title])
  globalThis.__benchHooks.unload()
})

test('actual filter/settings handlers share source filters, react to theme, copy full names and repeat back-to-top', async () => {
  const h = setup(); const loading = globalThis.__benchHooks.load(); h.respond(0); h.respond(1); await loading
  h.page.filterMenu(event({ kind: 'artificialAnalysis', mode: 'openness' }))
  h.page.sheetSelect({ detail: h.page.sheet.value.actions.find(action => action.value === 'open') })
  assert.deepEqual(h.page.cards.value.map(card => card.rows.length), [1, 1])
  h.page.selectGrouping(event({ id: 'company' }))
  assert.equal(h.page.cards.value[0].rows[0].name, 'DeepSeek')
  h.page.rowDetails(event({ kind: 'artificialAnalysis', rank: 1 }))
  assert.equal(h.page.companyDetails.value.open, true)
  assert.equal(h.page.companyDetails.value.name, 'DeepSeek')
  assert.equal(h.page.companyDetails.value.content, text(copy.strongest, 'zh-CN'))
  assert.deepEqual(h.page.companyDetails.value.members, [{ rank: 2, name: 'Open model', score: '98.0' }])
  h.page.closeCompanyDetails()
  assert.equal(h.page.companyDetails.value.open, false)
  assert.deepEqual(h.clipboard, [])
  h.page.rowDetails(event({ kind: 'artificialAnalysis', rank: 1 }))
  h.page.copyCompanyName()
  assert.equal(h.page.companyDetails.value.open, false)
  assert.equal(h.clipboard.at(-1), 'DeepSeek')
  h.page.clearFilters(event({ kind: 'artificialAnalysis' }))
  assert.equal(h.page.cards.value[0].rows.length, 2)
  h.theme('dark'); assert.equal(h.page.dark.value, true)
  h.page.preferences(event({ mode: 'language' }))
  assert.equal(h.page.sheet.value.actions.length, 3)
  h.page.sheetSelect({ detail: h.page.sheet.value.actions.find(action => action.value === 'en') })
  h.page.preferences(event({ mode: 'theme' }))
  assert.equal(h.page.sheet.value.actions.length, 3)
  h.page.sheetSelect({ detail: h.page.sheet.value.actions.find(action => action.value === 'dark') })
  assert.ok(h.page.dark.value)
  assert.deepEqual(h.page.tabs.value, ['Task benchmarks', 'User votes'])
  h.page.selectCategory(event({ id: 'image' }))
  assert.equal(h.page.cards.value[0].title, 'Artificial Analysis Text to Image')
  h.respond(2); h.respond(3); await new Promise(resolve => setImmediate(resolve))
  h.page.selectCategory(event({ id: 'general' }))
  h.page.cubeStart({ touches: [{ clientX: 180, clientY: 300 }] })
  h.page.scroll({ currentTarget: { dataset: { kind: 'artificialAnalysis' } }, detail: { scrollTop: 600 } })
  assert.equal(h.page.backToTop.value, true)
  const beforeReturns = h.scrolls.length
  h.page.top(); h.page.top()
  assert.deepEqual(h.scrolls.slice(beforeReturns), Array.from({ length: 2 }, () => ({ selector: '#board-scroll-artificialAnalysis', top: 0, animated: false })))
  assert.ok(h.writes.some(write => write.key === 'benchgauge.preferences' && write.value.language === 'en'))
  globalThis.__benchHooks.unload()
})

test('the screenshot button exports only the current pair as one complete image and retries a denied save', async () => {
  const h = setup({}, 140, {}, 'light', 'zh_CN', { arenaTextToImage: {
    kind: 'arenaTextToImage', fetchedAt: '2026-10-13T12:00:00Z',
    entries: [{ rank: 1, name: 'Do not export another category', score: 100 }],
  } }), canvas = canvasHarness(), toasts = []
  Object.assign(wx, canvas.platform, { showLoading() {}, hideLoading() {},
    showToast: options => toasts.push(options), previewImage: options => { h.preview = options }, openSetting: () => { h.settings = true },
    createSelectorQuery: () => {
      let scroll = false
      const query = {
        select() { return { fields: () => query, boundingClientRect: () => query, node: () => { scroll = true; return query } } },
        exec: callback => callback([{ node: scroll ? { scrollTo() {} } : canvas.canvas }]),
      }
      return query
    },
  })
  const loaded = globalThis.__benchHooks.load(); h.respond(0); h.respond(1); await loaded
  for (const [kind, value] of [['artificialAnalysis', 'open'], ['arenaText', 'closed']]) {
    h.page.filterMenu(event({ kind, mode: 'openness' }))
    h.page.sheetSelect({ detail: h.page.sheet.value.actions.find(action => action.value === value) })
  }
  await h.page.screenshot()
  assert.equal(typeof h.page.capture.value.path, 'string')
  assert.equal('paths' in h.page.capture.value, false)
  assert.equal(h.page.capture.value.open, true)
  assert.equal(h.page.backgroundLocked.value, true)
  assert.equal(h.page.capturing.value, false)
  const names = column => [...new Set(canvas.commands.filter(([command, value, x]) => command === 'fillText' && /^Model \d+$/.test(value) && (x < 500) === (column === 0)).map(command => command[1]))]
  assert.deepEqual(names(0), Array.from({ length: 70 }, (_, index) => `Model ${index * 2 + 1}`))
  assert.deepEqual(names(1), Array.from({ length: 70 }, (_, index) => `Model ${index * 2 + 1}`))
  assert.ok(!canvas.commands.some(([command, value]) => command === 'fillText' && String(value).includes('Do not export another category')))
  const path = h.page.capture.value.path
  h.page.previewScreenshot()
  assert.deepEqual(h.preview, { urls: [path], current: path })
  let attempts = 0
  wx.saveImageToPhotosAlbum = options => {
    if (++attempts === 1) options.fail({ errMsg: 'saveImageToPhotosAlbum:fail auth deny' })
    else { canvas.saved.push(options.filePath); options.success({}) }
  }
  await h.page.saveScreenshot()
  assert.equal(h.page.capture.value.saved, false)
  assert.equal(h.page.capture.value.saving, false)
  assert.match(h.modals.at(-1).content, /允许保存/)
  h.modals.at(-1).success({ confirm: true }); assert.equal(h.settings, true)
  await h.page.saveScreenshot()
  assert.equal(h.page.capture.value.saved, true)
  assert.deepEqual(canvas.saved, [path])
  await h.page.saveScreenshot(); assert.deepEqual(canvas.saved, [path], 'Repeated taps must not save a duplicate')
  assert.equal(toasts.at(-1).icon, 'success')
  h.page.closeCapture(); assert.equal(h.page.capture.value.open, false)
  assert.equal(h.page.backgroundLocked.value, false)
  assert.equal(canvas.files.has(path), false, 'Closing the preview removes its temporary PNG')
  h.page.filterMenu(event({ kind: 'artificialAnalysis', mode: 'country' }))
  h.page.sheetSelect({ detail: h.page.sheet.value.actions.find(action => action.value === 'unknown') })
  await h.page.screenshot()
  assert.ok(canvas.commands.some(([command, value]) => command === 'fillText' && value.includes('国家: 未知')))
  assert.ok(!canvas.commands.some(([command, value]) => command === 'fillText' && /[\u{1F1E6}-\u{1F1FF}]/u.test(value)))
  h.page.closeCapture()
  globalThis.__benchHooks.unload()
})

test('screenshot failure and absent snapshots keep the page usable without a blank preview', async () => {
  const h = setup(), toasts = []
  Object.assign(wx, { showToast: options => toasts.push(options), showLoading() {}, hideLoading() {} })
  await h.page.screenshot(); assert.match(toasts.at(-1).title, /暂未取得/)
  const loaded = globalThis.__benchHooks.load(); h.respond(0); h.respond(1); await loaded
  wx.createSelectorQuery = () => { const query = { select() { return { fields: () => query } }, exec: callback => callback([{}]) }; return query }
  await h.page.screenshot()
  assert.match(toasts.at(-1).title, /生成失败/)
  assert.equal(h.page.capturing.value, false)
  assert.equal(h.page.capture.value.open, false)
  assert.equal(h.page.backgroundLocked.value, false)
  globalThis.__benchHooks.unload()
})

test('cube drag preserves virtual windows and scroll rank, cancels safely and never turns a vertical gesture', async t => {
  t.mock.timers.enable({ apis: ['setTimeout'] })
  const h = setup({}, 1000), loading = globalThis.__benchHooks.load()
  h.respond(0); h.respond(1); await loading
  const touch = (x, y) => ({ touches: [{ clientX: x, clientY: y }] })
  h.page.cubeStart(touch(250, 200))
  h.page.cubeMove(touch(240, 260))
  h.page.cubeMove(touch(20, 300))
  h.page.cubeEnd()
  assert.equal(h.page.face.value, 0); assert.equal(h.page.cubeBusy.value, false)
  const [from, to] = h.page.cards.value.map(card => card.kind)
  h.page.scroll({ currentTarget: { dataset: { kind: from } }, detail: { scrollTop: 2400 } })
  const rows = h.page.cards.value[0].rows
  h.page.cubeStart(touch(280, 200)); h.page.cubeMove(touch(40, 200))
  assert.ok(h.page.cubePosition.value > 0.5)
  assert.equal(h.page.cubeBusy.value, true)
  assert.deepEqual(h.scrolls.at(-1), { selector: `#board-scroll-${to}`, top: 2400, animated: false })
  assert.deepEqual(h.page.cards.value[0].rows, rows)
  assert.ok(h.page.cards.value[1].rows.some(row => row.rank === 51))
  h.page.rowDetails(event({ kind: from, rank: 51 })); assert.equal(h.modals.length, 0)
  assert.equal(h.clipboard.length, 0)
  h.page.cubeEnd(); assert.equal(h.page.face.value, 1)
  t.mock.timers.tick(24); t.mock.timers.tick(340)
  assert.equal(h.page.cubeBusy.value, false); assert.equal(h.page.cubePosition.value, 1)
  h.page.cubeStart(touch(40, 200)); h.page.cubeMove(touch(250, 200)); h.page.cubeCancel()
  assert.equal(h.page.face.value, 1)
  globalThis.__benchHooks.resize()
  assert.equal(h.page.cubeBusy.value, false); assert.equal(h.page.cubePosition.value, 1)
  h.page.selectCategory(event({ id: 'coding' }))
  globalThis.__benchHooks.unload()
  t.mock.timers.tick(390)
  assert.equal(h.page.cubeBusy.value, false); assert.equal(h.page.category.value, 'coding')
})

test('outward cube swipes give one light haptic per gesture at both ends without changing boards or scroll positions', () => {
  for (const face of [0, 1]) {
    const h = setup({ face }), vibrations = []
    wx.vibrateShort = options => { vibrations.push(options.type); options.fail() }
    const touch = (x, y = 200) => ({ touches: [{ clientX: x, clientY: y }] })
    const direction = face === 0 ? 1 : -1
    h.page.cubeStart(touch(180))
    h.page.cubeMove(touch(180 + direction * 18))
    assert.deepEqual(vibrations, [])
    h.page.cubeMove(touch(180 + direction * 30))
    h.page.cubeMove(touch(180 + direction * 90))
    h.page.cubeEnd()
    assert.deepEqual(vibrations, ['light'])
    assert.equal(h.page.face.value, face)
    assert.equal(h.page.cubePosition.value, face)
    assert.equal(h.page.cubeBusy.value, false)
    assert.equal(h.page.cubeDragging.value, false)
    assert.deepEqual(h.scrolls, [])
    assert.deepEqual(h.writes, [])
    h.page.cubeStart(touch(180))
    h.page.cubeMove(touch(180 + direction * 40))
    h.page.cubeCancel()
    assert.deepEqual(vibrations, ['light', 'light'])
    h.page.cubeStart(touch(180))
    h.page.cubeMove(touch(180 + direction * 40, 260))
    h.page.cubeEnd()
    assert.equal(vibrations.length, 2, 'Vertical scrolling must not vibrate')
    h.page.cubeStart(touch(180))
    h.page.cubeMove(touch(180 + direction * 40))
    h.page.cubeMove(touch(180 - direction * 150))
    h.page.cubeEnd()
    assert.equal(vibrations.length, 3)
    assert.equal(h.page.face.value, 1 - face, 'Reversing inward must still turn normally')
    globalThis.__benchHooks.unload()
  }
})

test('unsupported haptics do not interrupt an outward swipe or the next inward turn', () => {
  for (const vibrate of [undefined, () => { throw new Error('unsupported') }]) {
    const h = setup()
    wx.vibrateShort = vibrate
    const touch = x => ({ touches: [{ clientX: x, clientY: 200 }] })
    h.page.cubeStart(touch(180)); h.page.cubeMove(touch(240)); h.page.cubeEnd()
    assert.equal(h.page.cubeBusy.value, false)
    h.page.cubeStart(touch(250)); h.page.cubeMove(touch(40)); h.page.cubeEnd()
    assert.equal(h.page.face.value, 1)
    globalThis.__benchHooks.unload()
  }
})

test('native vertical scroll before direction lock keeps ownership until touch end and the next horizontal swipe still works', async () => {
  const h = setup({}, 1000), loading = globalThis.__benchHooks.load()
  h.respond(0); h.respond(1); await loading
  const touch = (x, y) => ({ touches: [{ clientX: x, clientY: y }] })
  const kind = h.page.cards.value[0].kind
  h.page.cubeStart(touch(280, 200))
  h.page.cubeMove(touch(270, 202))
  assert.equal(h.page.cubeBusy.value, false)
  h.page.scroll({ currentTarget: { dataset: { kind } }, detail: { scrollTop: 80 } })
  assert.equal(h.page.cubeBusy.value, false)
  assert.equal(h.page.cubePosition.value, 0)
  h.page.cubeMove(touch(30, 240))
  h.page.cubeEnd()
  assert.equal(h.page.face.value, 0)
  h.page.cubeStart(touch(280, 200))
  h.page.cubeMove(touch(30, 202))
  h.page.cubeEnd()
  assert.equal(h.page.face.value, 1)
  globalThis.__benchHooks.unload()
})

test('a locked horizontal swipe tolerates native scroll noise and vertical curvature in both directions', async () => {
  for (const face of [0, 1]) {
    const h = setup({ face }, 1000), loading = globalThis.__benchHooks.load()
    h.respond(0); h.respond(1); await loading
    const touch = (x, y) => ({ touches: [{ clientX: x, clientY: y }] })
    const kind = h.page.cards.value[face].kind
    const direction = face === 0 ? -1 : 1
    h.page.scroll({ ...event({ kind }), detail: { scrollTop: 1200 } })
    h.page.cubeStart(touch(200, 200))
    h.page.cubeMove(touch(200 + direction * 12, 209))
    h.page.scroll({ ...event({ kind }), detail: { scrollTop: 1203 } })
    h.page.cubeMove(touch(200 + direction * 24, 216))
    assert.equal(h.page.cubeBusy.value, true)
    assert.equal(h.page.cubeDragging.value, true)
    const position = h.page.cubePosition.value
    h.page.scroll({ ...event({ kind }), detail: { scrollTop: 1206 } })
    assert.equal(h.page.cubeBusy.value, true)
    assert.equal(h.page.cubePosition.value, position)
    h.page.cubeMove(touch(200 + direction * 170, 350))
    h.page.scroll({ ...event({ kind }), detail: { scrollTop: 1208 } })
    h.page.cubeEnd()
    assert.equal(h.page.face.value, 1 - face)
    assert.equal(h.page.cubeDragging.value, false)
    globalThis.__benchHooks.unload()
  }
})

for (const face of [0, 1]) test(`first entrance reveals both faces, fades in and hints without changing saved source ${face}`, async t => {
  t.mock.timers.enable({ apis: ['setTimeout'] })
  const h = setup({ face }), loading = globalThis.__benchHooks.load()
  globalThis.__benchHooks.show()
  h.respond(0); h.respond(1); await loading
  t.mock.timers.tick(1000)
  assert.equal(h.page.cubeBusy.value, false, 'wait until the native page is ready')
  globalThis.__benchHooks.ready()
  t.mock.timers.tick(220)
  assert.equal(h.page.cubePosition.value, face ? 0.91 : 0.09)
  assert.match(h.page.entranceStyle.value, /opacity:0.65/)
  assert.equal(h.page.entranceHintVisible.value, true)
  t.mock.timers.tick(24)
  assert.equal(h.page.face.value, face); assert.equal(h.page.cubeBusy.value, true)
  assert.equal(h.page.cubePosition.value, face ? 0.86 : 0.14); assert.equal(h.page.cubeDuration.value, 420)
  assert.match(h.page.entranceStyle.value, /transform:none/)
  t.mock.timers.tick(550)
  assert.equal(h.page.cubePosition.value, face); assert.equal(h.page.cubeDuration.value, 700)
  t.mock.timers.tick(750)
  assert.equal(h.page.cubeBusy.value, false)
  assert.equal(h.page.entranceHintVisible.value, true)
  t.mock.timers.tick(1600)
  assert.equal(h.page.entranceHintVisible.value, false)
  assert.equal(h.writes.filter(write => write.key === 'benchgauge.preferences').length, 0)
  globalThis.__benchHooks.hide(); globalThis.__benchHooks.show(); t.mock.timers.tick(5000)
  assert.equal(h.page.cubePosition.value, face); assert.equal(h.page.cubeBusy.value, false)
  globalThis.__benchHooks.unload()
})

test('source tabs retain the selected board during the reveal and an unfinished drag', async t => {
  t.mock.timers.enable({ apis: ['setTimeout'] })
  const h = setup(), loading = globalThis.__benchHooks.load()
  t.after(() => globalThis.__benchHooks.unload())
  globalThis.__benchHooks.show(); globalThis.__benchHooks.ready()
  h.respond(0); h.respond(1); await loading
  const initialSelection = h.page.sourceSelection.value
  t.mock.timers.tick(220); t.mock.timers.tick(24)
  assert.equal(h.page.cubePosition.value, 0.14)
  assert.equal(h.page.sourceSelection.value, initialSelection)
  h.page.selectFace(event({ index: 1 }))
  const votedSelection = h.page.sourceSelection.value
  assert.match(votedSelection, /translateX\(100%\)/)
  assert.equal(h.page.entranceHintVisible.value, false)
  t.mock.timers.tick(24); t.mock.timers.tick(340)
  h.page.cubeStart({ touches: [{ clientX: 30, clientY: 200 }] })
  h.page.cubeMove({ touches: [{ clientX: 280, clientY: 200 }] })
  assert.ok(h.page.cubePosition.value < 0.5)
  assert.equal(h.page.face.value, 1)
  assert.equal(h.page.sourceSelection.value, votedSelection)
  h.page.cubeEnd()
  assert.equal(h.page.face.value, 0)
  assert.equal(h.page.sourceSelection.value, initialSelection)
})

test('source tabs scroll out with the active board and return on back-to-top or grouping reset', async t => {
  const h = setup({}, 100), loading = globalThis.__benchHooks.load()
  t.after(() => globalThis.__benchHooks.unload())
  h.respond(0); h.respond(1); await loading
  const scroll = (kind, scrollTop) => h.page.scroll({ currentTarget: { dataset: { kind } }, detail: { scrollTop } })
  assert.match(h.page.sourceTabsStyle.value, /translateY\(-0px\)/)
  scroll('artificialAnalysis', 20)
  assert.match(h.page.sourceTabsStyle.value, /translateY\(-20px\)/)
  scroll('arenaText', 500)
  assert.match(h.page.sourceTabsStyle.value, /translateY\(-20px\)/, 'hidden-board events cannot move the tabs')
  scroll('artificialAnalysis', 600)
  assert.match(h.page.sourceTabsStyle.value, new RegExp(`translateY\\(-${h.page.sourceTabsExtent.value}px\\)`))
  assert.match(h.page.sourceTabsStyle.value, /pointer-events:none/)
  h.page.changeFace({ detail: { current: 1 } })
  assert.match(h.page.sourceTabsStyle.value, /pointer-events:none/)
  h.page.top()
  assert.match(h.page.sourceTabsStyle.value, /translateY\(-0px\)/)
  assert.equal(h.scrolls.at(-1).top, 0)
  scroll('arenaText', 100)
  h.page.selectGrouping(event({ id: 'company' }))
  assert.match(h.page.sourceTabsStyle.value, /translateY\(-0px\)/)
})

test('settled native offsets restore tabs after a delayed scroll event and discard stale measurements', async t => {
  t.mock.timers.enable({ apis: ['setTimeout'] })
  const h = setup({}, 1000), loaded = globalThis.__benchHooks.load()
  h.respond(0); h.respond(1); await loaded
  t.after(() => globalThis.__benchHooks.unload())
  const callbacks = []
  wx.createSelectorQuery = () => {
    const query = { select: () => ({ fields: () => query }), exec: callback => callbacks.push(callback) }
    return query
  }
  const scroll = top => h.page.scroll({ ...event({ kind: 'artificialAnalysis' }), detail: { scrollTop: top } })
  scroll(20); t.mock.timers.tick(96)
  scroll(40); t.mock.timers.tick(96)
  callbacks[0]([{ scrollTop: 0 }])
  assert.match(h.page.sourceTabsStyle.value, /translateY\(-40px\)/, 'An older native query cannot override a newer scroll')
  callbacks[1]([{ scrollTop: 0 }])
  assert.match(h.page.sourceTabsStyle.value, /translateY\(-0px\)/, 'A stale bridge event must not strand tabs above the native top')
  assert.equal(h.page.cards.value[0].rows[0].rank, 1)
  scroll(20); t.mock.timers.tick(96)
  globalThis.__benchHooks.unload()
  callbacks[2]([{ scrollTop: 500 }])
  assert.match(h.page.sourceTabsStyle.value, /translateY\(-20px\)/, 'Unloaded pages ignore outstanding measurements')
})

test('return-to-top rejects queued scroll events while a new touch cancels pending navigation', async t => {
  t.mock.timers.enable({ apis: ['setTimeout'] })
  const h = setup({}, 1000), loaded = globalThis.__benchHooks.load()
  h.respond(0); h.respond(1); await loaded
  t.after(() => globalThis.__benchHooks.unload())
  const callbacks = [], commands = []
  wx.createSelectorQuery = () => {
    const query = { select: () => ({ node: () => query, fields: () => query }), exec: callback => callbacks.push(callback) }
    return query
  }
  const scroll = top => h.page.scroll({ ...event({ kind: 'artificialAnalysis' }), detail: { scrollTop: top } })
  scroll(700)
  h.page.top()
  scroll(20)
  assert.match(h.page.sourceTabsStyle.value, /translateY\(-0px\)/)
  callbacks[0]([{ node: { scrollTo: value => commands.push(value) } }])
  t.mock.timers.tick(96)
  callbacks[1]([{ scrollTop: 0 }])
  assert.match(h.page.sourceTabsStyle.value, /translateY\(-0px\)/)
  assert.equal(h.page.backToTop.value, false)
  assert.equal(h.page.cards.value[0].rows[0].rank, 1)
  h.page.top()
  h.page.cubeStart({ touches: [{ clientX: 180, clientY: 300 }] })
  callbacks[2]([{ node: { scrollTo: value => commands.push(value) } }])
  assert.equal(commands.length, 1, 'A fresh touch must cancel a scroll command still waiting for its node')
  scroll(700)
  assert.equal(h.page.backToTop.value, true, 'The new native gesture must remain responsive')
})

test('the scrolling tab space follows the actual measured tab height', t => {
  const h = setup()
  t.after(() => globalThis.__benchHooks.unload())
  wx.createSelectorQuery = () => {
    const rows = []
    const query = {
      select: selector => ({
        fields() { rows.push(selector === '.source-tabs' ? { height: 58 } : null); return query },
        boundingClientRect() { rows.push(null); return query },
      }),
      exec: callback => callback(rows),
    }
    return query
  }
  globalThis.__benchHooks.ready()
  assert.equal(h.page.sourceTabsExtent.value, 66)
  h.page.scroll({ currentTarget: { dataset: { kind: 'artificialAnalysis' } }, detail: { scrollTop: 200 } })
  assert.match(h.page.sourceTabsStyle.value, /translateY\(-66px\)/)
})

test('cached boards reveal on ready while network requests are still pending', async t => {
  t.mock.timers.enable({ apis: ['setTimeout'] })
  const cache = Object.fromEntries(['artificialAnalysis', 'arenaText'].map(kind => [kind, {
    kind, fetchedAt: '2026-10-13T12:00:00Z', entries: [{ rank: 1, name: 'Cached model', score: 99 }],
  }]))
  const h = setup({ face: 1 }, 0, {}, 'light', 'zh_CN', cache)
  const loading = globalThis.__benchHooks.load()
  globalThis.__benchHooks.show(); globalThis.__benchHooks.ready()
  t.mock.timers.tick(220); t.mock.timers.tick(24)
  assert.equal(h.requests.length, 2)
  assert.equal(h.page.cubePosition.value, 0.86)
  assert.equal(h.page.entranceHintVisible.value, true)
  globalThis.__benchHooks.unload(); await loading
  t.mock.timers.tick(5000)
  assert.equal(h.page.cubeBusy.value, false); assert.equal(h.page.entranceHintVisible.value, false)
})

test('background data cannot start the reveal; touching it cancels all delayed steps', async t => {
  t.mock.timers.enable({ apis: ['setTimeout'] })
  const h = setup(), loading = globalThis.__benchHooks.load()
  globalThis.__benchHooks.show(); globalThis.__benchHooks.ready(); globalThis.__benchHooks.hide()
  h.respond(0); h.respond(1); await loading; t.mock.timers.tick(1000)
  assert.equal(h.page.cubeBusy.value, false)
  globalThis.__benchHooks.show(); t.mock.timers.tick(220); t.mock.timers.tick(24)
  assert.equal(h.page.cubePosition.value, 0.14)
  h.page.cubeStart({ touches: [{ clientX: 200, clientY: 300 }] })
  assert.equal(h.page.cubePosition.value, 0); assert.equal(h.page.entranceHintVisible.value, false)
  t.mock.timers.tick(5000)
  assert.equal(h.page.cubeBusy.value, false); assert.equal(h.page.cubePosition.value, 0)
  globalThis.__benchHooks.unload()
})

test('all controls and global filters survive a local cold start, including manual language', async () => {
  const h = setup({}, 0, {}, 'light', 'en_US')
  assert.equal(h.page.labels.value.name, 'AI BenchGauge')
  const loading = globalThis.__benchHooks.load(); h.respond(0); h.respond(1); await loading
  const expectedFilters = {}
  for (const category of ['general', 'coding', 'image', 'video']) {
    const start = h.requests.length
    const changed = category !== h.page.category.value
    h.page.selectCategory(event({ id: category }))
    assert.equal(h.requests.length, start + (changed ? 2 : 0))
    if (changed) { h.respond(start); h.respond(start + 1) }
    await new Promise(resolve => setImmediate(resolve))
    for (const [index, card] of h.page.cards.value.entries()) {
      const filter = { country: index ? 'CN' : 'US', openness: index ? 'open' : 'closed' }
      h.page.filterMenu(event({ kind: card.kind, mode: 'country' })); h.page.sheetSelect({ detail: { value: filter.country } })
      h.page.filterMenu(event({ kind: card.kind, mode: 'openness' })); h.page.sheetSelect({ detail: { value: filter.openness } })
      for (const kind of Object.keys(boards)) expectedFilters[kind] = filter
    }
  }
  h.page.selectGrouping(event({ id: 'company' })); h.page.changeFace({ detail: { current: 1 } })
  h.page.preferences(event({ mode: 'language' })); h.page.sheetSelect({ detail: { mode: 'language', value: 'zh-TW' } })
  h.page.preferences(event({ mode: 'theme' })); h.page.sheetSelect({ detail: { mode: 'theme', value: 'dark' } })
  const saved = h.writes.at(-1).value
  assert.deepEqual(saved.filters, expectedFilters)
  assert.equal(saved.languageMode, 'manual')
  globalThis.__benchHooks.unload()
  const restarted = setup(saved, 0, {}, 'light', 'en_US')
  assert.equal(restarted.page.labels.value.name, 'AI 天梯')
  assert.equal(restarted.page.labels.value.votes, '使用者盲測')
  assert.equal(restarted.page.category.value, 'video'); assert.equal(restarted.page.grouping.value, 'company')
  assert.equal(restarted.page.face.value, 1); assert.equal(restarted.page.dark.value, true)
  assert.deepEqual(pagePreferences({}, saved, 'en_US').filters, expectedFilters)
  assert.equal(restarted.requests.length, 0)
  globalThis.__benchHooks.unload()
})

test('saving another setting keeps automatic language following the host on a later launch', () => {
  const h = setup({}, 0, {}, 'light', 'en_US')
  h.page.selectGrouping(event({ id: 'company' }))
  const saved = h.writes.at(-1).value
  assert.equal(saved.language, 'en'); assert.equal(saved.languageMode, 'system')
  globalThis.__benchHooks.unload()
  const restarted = setup(saved, 0, {}, 'light', 'zh_TW')
  assert.equal(restarted.page.labels.value.votes, '使用者盲測')
  assert.equal(restarted.page.grouping.value, 'company')
  wx.getAppBaseInfo = () => ({ language: 'en_US', theme: 'light' })
  globalThis.__benchHooks.show()
  assert.equal(restarted.page.labels.value.name, 'AI BenchGauge')
  globalThis.__benchHooks.unload()
})

test('unassigned country help uses the current language and a generic explanation',()=>{
 for(const language of ['en','zh-CN','zh-TW']) {
  const h=setup({language,languageMode:'manual'});h.page.countryHelp();
  assert.equal(h.modals.length,1);assert.equal(h.modals[0].showCancel,false);
  assert.equal(h.modals[0].confirmText,'OK');
  assert.equal(h.modals[0].title,text(copy.unknownCountryTitle,language));
  assert.equal(h.modals[0].content,text(copy.unknownCountryExplanation,language));
 }
});
