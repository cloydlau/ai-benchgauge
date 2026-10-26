import assert from 'node:assert/strict'
import test from 'node:test'
import { registerHooks } from 'node:module'
import { readFileSync } from 'node:fs'
import { canvasHarness } from './helpers/canvas.mjs'
import { pagePreferences } from '../src/core/share-state.js'
import { boards, categories, copy, text, desktopDownloadURL } from '../src/core/catalog.js'
import { formatTime } from '../src/core/leaderboard.js'
import { sourceTabTheme } from '../src/core/source-tab-theme.js'

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
  const respond = (index, metadata = {}) => {
    const request = requests[index]; request.responded = true; const kind = request.options.url.split('/').at(-1)
    request.options.success({ statusCode: 200, data: { board: { kind, fetchedAt: '2026-10-13T12:00:00Z', entries: count ? Array.from({ length: count }, (_, i) => ({
      rank: i + 1, name: `Model ${i + 1}`, score: count - i, organization: `Maker ${i + 1}`,
      openness: i % 2 ? 'open' : 'closed',
    })) : [
      { rank: 1, name: 'Closed model', score: 99, organization: 'OpenAI', openness: 'closed', developerCountry: { key: 'openai', countryCode: 'US' } },
      { rank: 2, name: 'Open model', score: 98, organization: 'DeepSeek', openness: 'open', developerCountry: { key: 'deepseek', countryCode: 'CN' } },
    ], ...metadata } } }); request.options.complete()
  }
  const respondAll = () => requests.forEach((request, index) => { if (!request.responded) { request.responded = true; respond(index) } })
  // Data/filter/layout fixtures explicitly populate every displayed source via
  // manual requests. Lifecycle/refresh-policy tests below use enter/respondAll
  // to exercise production's lazy, single-board loading instead.
  const requestCategory = () => Promise.all(page.cards.value.map(card => page.refreshTap({ currentTarget: { dataset: { kind: card.kind } } })))
  const enter = globalThis.__benchHooks.load
  const loadCategory = () => { const loading = requestCategory(); return Promise.all([loading, enter()]) }
  const respondCategory = () => { requestCategory(); respondAll() }
  return { page, requests, writes, modals, clipboard, scrolls, respond, respondAll, respondCategory, requestCategory, loadCategory, enter, theme: theme => themeListener?.({ theme }) }
}
const event = dataset => ({ currentTarget: { dataset } })

test('timestamp polish follows load completion, thirty-second cadence and page visibility', async t => {
  t.mock.timers.enable({ apis: ['setTimeout', 'Date'], now: Date.parse('2026-10-24T05:00:00Z') })
  const h = setup()
  t.after(() => globalThis.__benchHooks.unload())
  globalThis.__benchHooks.ready(); globalThis.__benchHooks.show()
  const loading = h.enter()
  const card = () => h.page.cards.value.find(item => item.kind === 'artificialAnalysis')
  assert.equal(card().polishing, false)
  h.respond(0); await loading
  assert.equal(card().polishing, true)
  t.mock.timers.tick(1100); assert.equal(card().polishing, false)
  t.mock.timers.tick(28899); assert.equal(card().polishing, false)
  t.mock.timers.tick(1); assert.equal(card().polishing, true)
  const refreshing = h.page.refreshTap(event({ kind: 'artificialAnalysis' }))
  assert.equal(card().polishing, false)
  h.respond(1); await refreshing
  assert.equal(card().polishing, true, 'An unchanged timestamp still polishes after loading')
  globalThis.__benchHooks.hide(); assert.equal(card().polishing, false)
  t.mock.timers.tick(60000); assert.equal(card().polishing, false)
  globalThis.__benchHooks.show(); assert.equal(card().polishing, true)
  globalThis.__benchHooks.unload(); assert.equal(card().polishing, false)
})

test('headers and help select only source time, falling back to fetch time when absent', async t => {
  t.mock.timers.enable({ apis: ['Date'], now: Date.parse('2026-10-25T06:00:00Z') })
  const fetchedAt = '2026-10-22T12:00:00Z'
  for (const language of ['en', 'zh-CN', 'zh-TW']) {
    for (const sourceUpdatedAt of [undefined, '2026-10-21T12:00:00Z', fetchedAt, '2026-10-23T12:00:00Z']) {
      const h = setup({ language }), loading = h.loadCategory()
      assert.ok(h.page.cards.value.every(card => !card.isSourceTime && card.time === '—'))
      for (let index = 0; index < h.requests.length; index++) h.respond(index, { sourceUpdatedAt, fetchedAt,
        sourceNote: 'https://huggingface.co/datasets/lmarena-ai/leaderboard-dataset' })
      await loading
      for (const card of h.page.cards.value) {
        const isSource = !!sourceUpdatedAt
        const label = isSource ? 'published' : 'updated'
        const opposite = isSource ? 'updated' : 'published'
        assert.equal(card.timeLabel, text(copy[label], language))
        assert.equal(card.isSourceTime, !!isSource)
        assert.equal(card.time, formatTime(isSource ? sourceUpdatedAt : fetchedAt, language, new Date(),
          { dateOnly: isSource && card.kind === 'arenaText', utc: isSource && card.kind === 'arenaText' }))
        assert.equal(card.timeAccessibility, `${card.time} ${card.timeLabel}`)
        assert.doesNotMatch(card.timeAccessibility, /Fetched|抓取|擷取|Data updated|数据更新|資料更新|数据发布|資料發佈/)
        assert.equal('fetched' in card || 'updated' in card, false, 'Do not bridge a second timestamp')
        h.page.sourceHelp(event({ kind: card.kind }))
        const content = h.modals.at(-1).content
        assert.ok(content.includes(`${card.time} ${card.timeLabel}`))
        assert.ok(!content.includes(`${card.time} ${text(copy[opposite], language)}`))
      }
      globalThis.__benchHooks.unload()
    }
  }
})

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
  const loading = h.loadCategory(); h.respondCategory(); await loading
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
  h.respondCategory()
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

test('company search opens, filters all sources and retains an independent query across grouping and category switches', async () => {
  const h = setup({}, 30)
  const loading = h.loadCategory(); h.respondCategory(); await loading
  h.page.inputModelSearch({ detail: { value: 'Model 29' } })
  h.page.selectGrouping(event({ id: 'company' }))
  assert.equal(h.page.modelSearchQuery.value, '')
  assert.ok(h.page.cards.value.every(card => card.count === 30))
  const initialRequests = h.requests.length
  h.page.openModelSearch()
  await new Promise(resolve => setTimeout(resolve, 30))
  assert.equal(h.page.modelSearchVisible.value, true)
  h.page.inputModelSearch({ detail: { value: 'MAKER 28' } })
  assert.ok(h.page.cards.value.every(card => card.count === 1 && card.rows[0].rank === 28 && card.rows[0].name === 'Maker 28' && card.filtered))
  assert.equal(h.requests.length, initialRequests, 'Company filtering stays local')
  h.page.selectFace(event({ index: 1 }))
  assert.equal(h.page.modelSearchQuery.value, 'MAKER 28')
  h.page.selectGrouping(event({ id: 'model' }))
  assert.equal(h.page.modelSearchVisible.value, false)
  assert.equal(h.page.modelSearchQuery.value, 'Model 29')
  assert.equal(h.page.cards.value[0].rows[0].name, 'Model 29')
  h.page.selectGrouping(event({ id: 'company' }))
  assert.equal(h.page.modelSearchQuery.value, 'MAKER 28')
  h.page.selectCategory(event({ id: 'coding' })); h.respondCategory()
  await new Promise(resolve => setTimeout(resolve, 0))
  assert.ok(h.page.cards.value.every(card => card.count === 1 && card.rows[0].name === 'Maker 28'))
  h.page.openModelSearch()
  await new Promise(resolve => setTimeout(resolve, 30))
  h.page.inputModelSearch({ detail: { value: 'no such company' } })
  assert.ok(h.page.cards.value.every(card => card.count === 0 && card.filtered && card.height > 0))
  h.page.clearModelSearch()
  assert.equal(h.page.modelSearchVisible.value, true)
  assert.ok(h.page.cards.value.every(card => card.count === 30))
  h.page.inputModelSearch({ detail: { value: 'Maker 28' } })
  h.page.closeModelSearch()
  assert.equal(h.page.modelSearchQuery.value, '')
  assert.equal(h.page.modelSearchVisible.value, false)
  h.page.inputModelSearch({ detail: { value: 'Maker 28' } })
  h.page.clearFilters()
  assert.equal(h.page.modelSearchQuery.value, '')
  h.page.selectGrouping(event({ id: 'model' }))
  assert.equal(h.page.modelSearchQuery.value, '', 'Global reset also clears the retained model query')
  assert.ok(h.page.cards.value.every(card => card.count === 30))
  globalThis.__benchHooks.unload()
})

test('switching grouping cancels company search while its starting bounds are still pending', async () => {
  const h = setup()
  h.page.selectGrouping(event({ id: 'company' }))
  let measured
  const createSelectorQuery = wx.createSelectorQuery
  wx.createSelectorQuery = () => {
    const query = { select: () => ({ boundingClientRect: () => query }), exec: callback => { measured = callback } }
    return query
  }
  h.page.openModelSearch()
  wx.createSelectorQuery = createSelectorQuery
  h.page.selectGrouping(event({ id: 'model' }))
  measured([])
  await new Promise(resolve => setTimeout(resolve, 40))
  assert.equal(h.page.modelSearchVisible.value, false)
  assert.equal(h.page.modelSearchFocused.value, false)
  globalThis.__benchHooks.unload()
})

test('blur retains a nonempty search and its results without restoring keyboard focus', async () => {
  const h = setup({}, 1000)
  const loading = h.loadCategory(); h.respondCategory(); await loading
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
  const loading = h.loadCategory(); h.respondCategory(); await loading
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
    const loading = h.loadCategory(); h.respondCategory(); await loading
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
  const loading = h.loadCategory(); h.respondCategory(); await loading
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
    assert.equal(h.requests.length, 3)
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
    const loading = h.loadCategory()
    h.respondCategory(); await loading
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
  const loading = h.loadCategory()
  for (let index = 0; index < h.requests.length; index++) {
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
    ['en', 'Multiple leaderboards & quota tracking', 'Got it', 'PC link'],
    ['zh-CN', '多榜对照 & 余量追踪', '我知道了', 'PC 端链接'],
    ['zh-TW', '多榜對照 & 餘量追蹤', '我知道了', 'PC 端連結'],
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

    for (const width of [280, 320, 375, 402, 430, 744, 1024]) for (const height of [28, 32, 36]) {
      wx.getWindowInfo = () => ({ statusBarHeight: 24, windowWidth: width })
      wx.getMenuButtonBoundingClientRect = () => ({ top: 28, bottom: 28 + height, height, left: width - 94 })
      globalThis.__benchHooks.resize()
      const title = h.page.brandTitle.value
      assert.equal(h.page.groupingControl.value.height, height)
      assert.ok(h.page.groupingControl.value.fontSize >= height * 0.34)
      assert.ok(title.height > 0 && title.height <= height * (language === 'en' ? 0.8 : 0.85) + 0.001)
      assert.ok(Math.abs(title.height - title.subtitleHeight - 3 * title.headingScale) < 0.0001)
      assert.ok(title.subtitleFontSize > 0 && title.subtitleFontSize <= 11)
      assert.ok(title.subtitleHeight + 0.0001 >= title.subtitleFontSize * 2 + title.headingScale)
      assert.ok(Math.abs(title.scale * 21 / title.baseTitleFontSize - title.subtitleFontSize / title.subtitleBaseFontSize) < 0.0001)
      assert.equal(title.showSubtitle, language !== 'en')
      const widestCaption = language === 'en' ? 0 : Math.max(...h.page.subtitleParts.value.map(row => [...row].reduce((sum, c) => sum + (/[^\x00-\x7F]/.test(c) ? 12 : 7.2), 0)))
      assert.ok(Math.abs(widestCaption * title.subtitleFontSize / 12 - title.subtitleWidth) < 0.001)
      const finalRowWidth = [...h.page.subtitleParts.value[1]].reduce((sum, c) => sum + (/[^\x00-\x7F]/.test(c) ? 12 : 7.2), 0) * title.subtitleFontSize / 12
      const helpRight = finalRowWidth + (title.subtitleHelpOffset + 1) * title.subtitleFontSize
      if (language !== 'en') assert.ok(helpRight <= title.subtitleWidth + 8 + 0.001)
      assert.equal(h.page.subtitleParts.value.length, 2)
      assert.equal(h.page.subtitleParts.value.join(language === 'en' ? ' ' : ''), h.page.labels.value.tagline)
      const availableWidth = width - h.page.capsuleWidth.value - h.page.groupingControl.value.width - width / 750 * 30 - 8
      assert.ok(title.width + title.subtitleWidth <= availableWidth + 0.001)
    }
    globalThis.__benchHooks.unload()
  }
})

test('automatic refresh failures quietly retain rows and time; only a manual pull owns the spinner', async () => {
  const h = setup()
  const first = h.loadCategory()
  assert.equal(h.page.pullRefreshing.value, false)
  h.respondCategory(); await first
  const metadata = card => ({ rows: card.rows, time: card.time, timeLabel: card.timeLabel, isSourceTime: card.isSourceTime })
  const before = h.page.cards.value.map(metadata)
  const retry = h.requestCategory()
  assert.equal(h.page.pullRefreshing.value, false)
  for (const request of h.requests.slice(2)) { request.options.fail(); request.options.complete() }
  await retry
  assert.deepEqual(h.page.cards.value.map(metadata), before)
  assert.equal(h.modals.length, 0)
  assert.ok(h.page.cards.value.every(card => !card.failed))
  const pull = h.page.pullRefresh()
  assert.equal(h.page.pullRefreshing.value, true)
  for (const request of h.requests.slice(4)) { request.options.fail(); request.options.complete() }
  await pull
  assert.equal(h.page.pullRefreshing.value, false)
  assert.deepEqual(h.page.cards.value.map(metadata), before)
  globalThis.__benchHooks.unload()
})

test('pulling joins only its originating board while sibling requests are still in flight', async t => {
  t.mock.timers.enable({ apis: ['setTimeout', 'Date'] })
  const h = setup(), loading = h.loadCategory()
  t.after(() => globalThis.__benchHooks.unload())
  const pull = h.page.pullRefresh(event({ kind: 'arenaText' }))
  assert.equal(h.requests.length, 3, 'A manual pull joins its existing request without starting another batch')
  assert.equal(h.page.pullRefreshKind.value, 'arenaText')
  h.page.finishPullRefresh(event({ kind: 'arenaText' }))
  assert.equal(h.page.pullRefreshKind.value, 'arenaText', 'An early native restore cannot erase active loading feedback')
  t.mock.timers.tick(350)
  h.respond(0); await Promise.resolve()
  assert.equal(h.page.pullRefreshing.value, true, 'A sibling response cannot finish this pull')
  h.respond(1); await pull
  assert.equal(h.page.pullRefreshing.value, false)
  assert.equal(h.requests[2].responded, undefined, 'The pull finishes without waiting for Epoch')
  assert.equal(h.page.pullRefreshKind.value, 'arenaText', 'Keep the feedback host through native restoration')
  h.page.finishPullRefresh(event({ kind: 'artificialAnalysis' }))
  assert.equal(h.page.pullRefreshKind.value, 'arenaText')
  h.page.finishPullRefresh(event({ kind: 'arenaText' }))
  assert.equal(h.page.pullRefreshKind.value, '')
  h.respondCategory(); await loading
})

test('an immediate pull response paints a brief loading state before restoration and failure keeps existing rows', async t => {
  t.mock.timers.enable({ apis: ['setTimeout', 'Date'] })
  const h = setup(), loading = h.loadCategory()
  t.after(() => globalThis.__benchHooks.unload())
  h.respondCategory(); await loading
  const before = h.page.cards.value.map(card => card.rows)
  const pull = h.page.pullRefresh(event({ kind: 'artificialAnalysis' }))
  for (const request of h.requests.slice(3)) { request.options.fail(); request.options.complete() }
  await h.page.refreshTap(event({ kind: 'artificialAnalysis' }))
  t.mock.timers.tick(299)
  assert.equal(h.page.pullRefreshing.value, true)
  t.mock.timers.tick(1); await pull
  assert.equal(h.page.pullRefreshing.value, false)
  assert.deepEqual(h.page.cards.value.map(card => card.rows), before)
  assert.equal(h.modals.length, 0)
  h.page.finishPullRefresh(event({ kind: 'artificialAnalysis' }))
  assert.equal(h.page.pullRefreshKind.value, '')
})

test('pulling each source requests exactly that board and leaves sibling snapshots unchanged', async t => {
  t.mock.timers.enable({ apis: ['setTimeout', 'Date'] })
  const h = setup(), loading = h.loadCategory()
  t.after(() => globalThis.__benchHooks.unload())
  h.respondCategory(); await loading
  for (const category of categories) {
    h.page.selectCategory(event({ id: category.id }))
    const categoryLoading = h.requestCategory()
    h.respondCategory(); await categoryLoading
    for (const kind of category.kinds) {
      const before = h.page.cards.value.map(card => ({ kind: card.kind, rows: card.rows, time: card.time }))
      const index = h.requests.length
      const pull = h.page.pullRefresh(event({ kind }))
      assert.equal(h.requests.length, index + 1)
      assert.equal(h.requests[index].options.url, `https://shared.example/v1/boards/${kind}`)
      const duplicate = h.page.pullRefresh(event({ kind }))
      assert.equal(h.requests.length, index + 1, 'Repeated pull cannot duplicate the board request')
      t.mock.timers.tick(350)
      h.respond(index, { fetchedAt: '2026-10-24T12:00:00Z' }); await pull; await duplicate
      assert.deepEqual(h.page.cards.value.filter(card => card.kind !== kind).map(card => ({ kind: card.kind, rows: card.rows, time: card.time })), before.filter(card => card.kind !== kind))
      h.page.finishPullRefresh(event({ kind }))
    }
  }
})

test('page entry and category switches load only the active source, with no foreground polling', async () => {
  const h = setup(); const loading = h.enter()
  assert.equal(h.page.headerTop.value, 28)
  assert.equal(h.page.navHeight.value, 68)
  assert.equal(h.page.capsuleWidth.value, 113)
  globalThis.__benchHooks.show()
  assert.equal(h.requests.length, 1)
  assert.ok(h.requests[0].options.url.endsWith('/artificialAnalysis'))
  assert.deepEqual(h.page.tabs.value, ['任务测评', '用户盲测', '难度校准'])
  h.respond(0); await loading
  assert.deepEqual(h.page.cards.value.map(card => [card.title, card.rows.length]), [['Artificial Analysis', 2], ['Text Arena', 0], ['Epoch ECI', 0]])
  assert.notEqual(h.page.cards.value[0].time, '—')
  assert.equal(h.page.cards.value[0].timeLabel, '刷新')
  assert.equal(h.page.cards.value[0].isSourceTime, false)
  h.page.selectFace(event({ index: 1 })); assert.equal(h.page.face.value, 1)
  assert.equal(h.requests.length, 2)
  assert.ok(h.requests[1].options.url.endsWith('/arenaText'))
  h.page.selectCategory(event({ id: 'video' })); assert.equal(h.requests.length, 3)
  assert.ok(h.requests[2].options.url.endsWith('/arenaTextToVideo'))
  h.respondAll(); await new Promise(resolve => setImmediate(resolve))
  assert.equal(h.page.cards.value[0].kind, 'artificialAnalysisTextToVideo')
  const shared = pagePreferences(Object.fromEntries(new URL('https://shared.example' + globalThis.__benchHooks.share().path).searchParams))
  assert.equal(shared.category, 'video')
  assert.equal(shared.face, 1)
  globalThis.__benchHooks.unload()
})

test('entering an expired publication joins a manual pull and only a later board entry can trigger another automatic request', async t => {
  const now = Date.parse('2026-10-24T12:00:00Z')
  t.mock.timers.enable({ apis: ['Date', 'setTimeout'], now })
  const cached = (kind, sourceUpdatedAt, fetchedAt = new Date(now).toISOString()) => ({ kind, sourceUpdatedAt, fetchedAt,
    entries: [{ rank: 1, name: 'Saved model', score: 90 }] })
  const h = setup({}, 0, {}, 'light', 'zh_CN', {
    artificialAnalysis: cached('artificialAnalysis', undefined),
    arenaText: cached('arenaText', new Date(now - 86400000).toISOString()),
    epochECI: cached('epochECI', new Date(now - 23 * 3600000).toISOString()),
  })
  t.after(() => globalThis.__benchHooks.unload())
  await h.enter()
  assert.equal(h.requests.length, 0, 'Fresh cached boards do not fetch on entry')
  h.page.changeFace({ detail: { current: 1 } })
  assert.equal(h.requests.length, 1, 'A recent fetch cannot hide an old publication')
  const automatic = h.page.autoRefresh()
  const pull = h.page.pullRefresh(event({ kind: 'arenaText' }))
  assert.equal(h.requests.length, 1, 'Manual and automatic refresh share one request')
  t.mock.timers.tick(350)
  assert.equal(h.page.pullRefreshing.value, true)
  h.respond(0, { sourceUpdatedAt: new Date(now - 86400000).toISOString(), fetchedAt: new Date(now).toISOString() })
  await automatic; await pull
  t.mock.timers.tick(500)
  h.page.changeFace({ detail: { current: 2 } })
  assert.equal(h.requests.length, 1, 'A publication younger than 24 hours is fresh')
  t.mock.timers.tick(24); t.mock.timers.tick(441)
  h.page.changeFace({ detail: { current: 1 } })
  assert.equal(h.requests.length, 1, 'Rapid re-entry backs off when the publication is unchanged')
  t.mock.timers.tick(24); t.mock.timers.tick(441)
  t.mock.timers.tick(2 * 86400000)
  globalThis.__benchHooks.hide(); globalThis.__benchHooks.show()
  assert.equal(h.requests.length, 1, 'Elapsed time and foreground activation cannot poll rankings')
  h.page.changeFace({ detail: { current: 2 } })
  assert.equal(h.requests.length, 2)
  assert.ok(h.requests[1].options.url.endsWith('/epochECI'))
  h.respondAll(); await h.page.autoRefresh()
})

test('failed entry refresh preserves cache, automatic retries back off, and manual refresh bypasses that backoff', async t => {
  const now = Date.parse('2026-10-24T12:00:00Z')
  t.mock.timers.enable({ apis: ['Date', 'setTimeout'], now })
  const h = setup({}, 0, {}, 'light', 'zh_CN', { artificialAnalysis: { kind: 'artificialAnalysis', fetchedAt: '2026-10-20T00:00:00Z', entries: [{ rank: 1, name: 'Saved', score: 90 }] } })
  t.after(() => globalThis.__benchHooks.unload())
  const before = h.page.cards.value[0].rows
  const entry = h.enter()
  h.requests[0].options.fail(); h.requests[0].options.complete(); await entry
  await h.page.autoRefresh()
  assert.equal(h.requests.length, 1)
  assert.deepEqual(h.page.cards.value[0].rows, before)
  const pull = h.page.pullRefresh()
  assert.equal(h.requests.length, 2)
  t.mock.timers.tick(350); h.respond(1, { fetchedAt: new Date(now).toISOString() }); await pull
  assert.equal(h.page.cards.value[0].rows[0].name, 'Closed model')
  await h.page.autoRefresh()
  assert.equal(h.requests.length, 2)
})

test('every category and source shares the current page title and only the localized ranking summary', () => {
  for (const language of ['en', 'zh-CN', 'zh-TW']) for (const category of categories) for (const face of category.kinds.keys()) {
    const h = setup({ language, category: category.id, face })
    const message = globalThis.__benchHooks.share()
    const title = category.id === 'usage' ? text([copy.dailyUsage, copy.dailyShare, copy.cumulativeShare][face], language) : text([copy.tasks, copy.votes, copy.capabilityIndex][face], language)
    assert.equal(message.title, `${title}｜${text(copy.rankingSummary, language)}`)
    assert.ok(!message.title.includes(text(copy.tagline, language)))
    const shared = pagePreferences(Object.fromEntries(new URL('https://shared.example' + message.path).searchParams))
    assert.equal(shared.category, category.id)
    assert.equal(shared.face, face)
    globalThis.__benchHooks.unload()
  }
})

test('timestamp help explains both labels in all languages without refreshing data', async () => {
  for (const language of ['en', 'zh-CN', 'zh-TW']) {
    const h = setup({ language })
    const requests = h.requests.length
    h.page.timeHelp()
    assert.deepEqual(h.modals.at(-1), {
      title: text(copy.timeExplanationTitle, language),
      content: text(copy.timeExplanation, language), showCancel: false,
    })
    assert.equal(h.requests.length, requests)
    assert.doesNotMatch(h.modals.at(-1).content, /抓取|擷取|retriev|fetch/i)
    globalThis.__benchHooks.unload()
  }
})

test('usage headers show retrieval time while source help retains statistical coverage', async () => {
  const fetchedAt = '2026-10-24T12:34:00Z'
  for (const language of ['en', 'zh-CN', 'zh-TW']) {
    const h = setup({ category: 'usage', language }), loading = h.loadCategory()
    for (let index = 0; index < h.requests.length; index++) h.respond(index,
      { sourceUpdatedAt: '2026-10-22T00:00:00Z', fetchedAt })
    await loading
    for (const kind of ['vercelUsage', 'cloudbaseUsage']) {
      const card = h.page.cards.value.find(item => item.kind === kind)
      assert.equal(card.time, formatTime(fetchedAt, language))
      assert.equal(card.timeLabel, text(copy.updated, language))
      assert.equal(card.isSourceTime, false)
      h.page.sourceHelp(event({ kind }))
      const content = h.modals.at(-1).content
      assert.ok(content.includes(text(copy.timeExplanation, language)))
      if (kind === 'vercelUsage') {
        assert.match(content, /2026-10-22/)
        assert.match(content, /UTC/)
      } else assert.match(content, language === 'en' ? /sampled Beijing-time days/ : language === 'zh-TW' ? /抽樣統計日/ : /抽样统计日/)
    }
    globalThis.__benchHooks.unload()
  }
})

test('usage restores Tencent, keeps failures independent and recovers OpenRouter configuration', async () => {
  const h = setup({ category: 'usage', language: 'zh-CN', face: 2 })
  assert.equal(h.page.face.value, 2, 'Restored Tencent selection is retained')
  const loading = h.loadCategory()
  assert.equal(h.requests.length, 3)
  assert.deepEqual(h.page.tabs.value, ['每日用量', '每日占比', '累计占比'])
  h.requests[0].options.success({ statusCode: 200, data: { board: null, configurationRequired: true } })
  h.requests[0].options.complete()
  h.respond(1, { sourceUpdatedAt: '2026-10-22T00:00:00Z', entries: [{ rank: 1, name: 'DeepSeek V4.1 Flash', score: 16.3389, organization: 'DeepSeek' }] })
  h.respond(2, { sourceUpdatedAt: undefined, entries: [{ rank: 1, name: 'Kimi K3', score: 1.1 }] })
  await loading
  assert.equal(h.page.cards.value[2].time, formatTime('2026-10-13T12:00:00Z'))
  assert.equal(h.page.cards.value[2].timeLabel, '刷新')
  assert.equal(h.page.cards.value[2].rows[0].scoreText, "1.10%")
  assert.equal(h.page.cards.value[0].pendingConfiguration, true)
  assert.equal(h.page.cards.value[0].hasBoard, false)
  assert.equal(h.page.cards.value[0].scoreLabel, '用量')
  assert.equal(h.page.cards.value[1].scoreLabel, '占比')
  assert.equal(h.page.cards.value[1].time, formatTime('2026-10-13T12:00:00Z'))
  assert.equal(h.page.cards.value[1].timeLabel, '刷新')
  assert.equal(h.page.cards.value[1].isSourceTime, false)
  assert.equal(h.page.cards.value[1].rows[0].scoreText, '16.34%')
  assert.equal(h.page.cards.value[1].rows[0].scoreShare, '')
  h.page.changeFace({ detail: { current: 1 } })
  assert.equal(h.page.face.value, 1)
  const retry = h.page.pullRefresh(event({ kind: 'openRouterUsage' }))
  assert.equal(h.requests.length, 4)
  const siblings = h.page.cards.value.slice(1).map(card => card.rows)
  const notice = 'Source: OpenRouter · Licensed under CC BY 4.0.'
  h.respond(3, { sourceNote: notice })
  await retry
  assert.deepEqual(h.page.cards.value.slice(1).map(card => card.rows), siblings)
  assert.equal(h.page.cards.value[0].pendingConfiguration, false)
  assert.equal(h.page.cards.value[0].rows[0].scoreText, '99.00B')
  h.page.sourceHelp(event({ kind: 'openRouterUsage' }))
  assert.ok(!h.modals.at(-1).content.includes(notice))
  h.page.sourceHelp(event({ kind: 'vercelUsage' }))
  assert.ok(h.modals.at(-1).content.includes('缓存'))
  assert.ok(h.modals.at(-1).content.includes('https://vercel.com/ai-gateway/leaderboards/models'))
  globalThis.__benchHooks.unload()
})

test('menu sharing restores live choices and all filters over conflicting receiver preferences', async () => {
  const sender = setup({ filters: { artificialAnalysis: { country: 'US', openness: 'closed' } } })
  assert.equal(globalThis.__benchPageConfig.canShareToOthers, true)
  sender.page.selectCategory(event({ id: 'video' }))
  sender.respondCategory(); await new Promise(resolve => setImmediate(resolve))
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
  assert.equal(message.title, `${text(copy.votes, 'zh-TW')}｜${text(copy.rankingSummary, 'zh-TW')}`)
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
  const loaded = receiver.loadCategory(); receiver.respondCategory(); await loaded
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
  const h = setup(); const loading = h.loadCategory()
  h.respondCategory(); await loading
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
  const restoredLoading = restored.loadCategory()
  restored.respondCategory(); await restoredLoading
  restored.page.filterMenu(event({ kind, mode: 'country' })); check(restored.page, 'CN')
  restored.page.filterMenu(event({ kind, mode: 'openness' })); check(restored.page, 'open')
  globalThis.__benchHooks.unload()
})

test('both sources share country and openness, union country choices, reset scroll and clear together', async () => {
  const h = setup(); const loading = h.loadCategory()
  const kinds = ['artificialAnalysis', 'arenaText', 'epochECI']
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
  assert.deepEqual(h.page.cards.value.map(card => card.count), [0, 1, 1])
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
  assert.deepEqual(h.page.cards.value.map(card => [card.count, card.filtered]), [[1, false], [1, false], [1, false]])
  h.page.filterMenu(event({ kind: kinds[0], mode: 'country' }))
  assert.equal(h.page.sheet.value.actions.find(action => action.color).value, 'all')
  globalThis.__benchHooks.unload()
})

test('all categories share filters in both directions, including before data arrives and after clearing', async () => {
  const h = setup(); const loading = h.loadCategory()
  h.respondCategory(); await loading
  const select = (kind, mode, value) => {
    h.page.filterMenu(event({ kind, mode }))
    h.page.sheetSelect({ detail: h.page.sheet.value.actions.find(action => action.value === value) })
  }
  select('arenaText', 'country', 'CN'); select('arenaText', 'openness', 'open')
  for (const category of categories.filter(item => item.id !== 'general')) {
    const start = h.requests.length
    h.page.selectCategory(event({ id: category.id }))
    for (const kind of category.kinds) for (const [mode, value] of [['country', 'CN'], ['openness', 'open']]) {
      h.page.filterMenu(event({ kind, mode }))
      assert.equal(h.page.sheet.value.actions.find(action => action.color)?.value, value)
    }
    h.respondCategory(); await new Promise(resolve => setImmediate(resolve))
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

function expandRankings(h) {
  for (const card of h.page.cards.value) if (card.hasMore) h.page.toggleRanking(event({ kind: card.kind }))
}

test('rankings show twenty by default, expand independently and reset after search or filtering', async () => {
  for (const count of [19, 20, 21]) {
    const h = setup({}, count)
    const loaded = h.loadCategory(); h.respondCategory(); await loaded
    const first = h.page.cards.value[0], second = h.page.cards.value[1]
    assert.equal(first.shownCount, Math.min(20, count))
    assert.equal(first.height, Math.min(20, count) * 48)
    assert.equal(first.hasMore, count > 20)
    assert.equal(first.expanded, false)
    assert.equal(first.rows.at(-1).rank, Math.min(20, count))
    h.page.toggleRanking(event({ kind: first.kind }))
    assert.equal(h.page.cards.value[0].expanded, count > 20)
    assert.equal(h.page.cards.value[0].shownCount, count)
    assert.equal(h.page.cards.value[1].expanded, false)
    assert.equal(h.page.cards.value[1].shownCount, Math.min(20, count))
    if (count > 20) {
      assert.match(first.expansionLabel, /21/)
      assert.equal(h.page.cards.value[0].rows.at(-1).rank, 21)
      h.page.toggleRanking(event({ kind: first.kind }))
      assert.equal(h.page.cards.value[0].shownCount, 20)
      assert.equal(h.page.cards.value[0].rows.at(-1).rank, 20)
      h.page.toggleRanking(event({ kind: first.kind }))
      h.page.inputModelSearch({ detail: { value: 'Model 21' } })
      assert.equal(h.page.cards.value[0].hasMore, false)
      assert.equal(h.page.cards.value[0].shownCount, 1)
      assert.equal(h.page.cards.value[0].rows[0].rank, 21, 'Search includes collapsed models')
      h.page.inputModelSearch({ detail: { value: '' } })
      assert.equal(h.page.cards.value[0].shownCount, 20)
      expandRankings(h)
      h.page.filterMenu(event({ kind: second.kind, mode: 'openness' }))
      h.page.sheetSelect({ detail: h.page.sheet.value.actions.find(action => action.value === 'open') })
      assert.ok(h.page.cards.value.every(card => !card.expanded && !card.hasMore))
      h.page.clearFilters(event({ kind: first.kind }))
      expandRankings(h)
      h.page.selectGrouping(event({ id: 'company' }))
      assert.ok(h.page.cards.value.every(card => !card.expanded && card.shownCount === 20))
    }
    globalThis.__benchHooks.unload()
  }
})

test('ten thousand rows only cross the bridge in bounded windows, including fast jumps and filter resets', async () => {
  const h = setup({}, 10000)
  const pending = h.loadCategory(); h.respondCategory(); await pending
  expandRankings(h)
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
  let detail
  wx.navigateTo = options => { assert.ok(options.url.startsWith('/pages/model/index')); options.success({ eventChannel: { emit: (name, data) => { assert.equal(name, 'modelDetails'); detail = data.entry } } }) }
  h.page.rowDetails(event({ kind: card.kind, rank: 10000 }))
  assert.equal(detail.name, 'Model 10000')
  assert.deepEqual(h.clipboard, [])
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
    const loading = h.loadCategory(); h.respondCategory(); await loading
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
  const pending = h.loadCategory(); h.respondCategory(); await pending
  expandRankings(h)
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
  const loaded = h.loadCategory(); h.respondCategory(); await loaded
  expandRankings(h)
  const kind = h.page.cards.value[0].kind
  const atTop = [{ top: 50, height: 480, scrollTop: 0 }, { top: 250 }, null, null]
  callbacks.at(-1)(atTop)
  const refresh = h.page.refreshTap(event({ kind })); h.respond(3); await refresh
  h.page.scroll({ ...event({ kind }), detail: { scrollTop: 4300 } })
  callbacks.at(-1)(atTop)
  assert.equal(h.page.cards.value[0].rows[0].rank, 74)
  assert.ok(h.page.cards.value[0].rows.some(row => row.rank === 100))
  const next = h.page.refreshTap(event({ kind })); h.respond(4); await next
  h.page.scroll({ ...event({ kind }), detail: { scrollTop: 5000 } })
  callbacks.at(-1)([{ top: 50, height: 480, scrollTop: 4300 }, { top: -4050 }, null, null])
  assert.equal(h.page.cards.value[0].rows[0].rank, 89)
  h.page.scroll({ ...event({ kind }), detail: { scrollTop: 0 } })
  assert.equal(h.page.cards.value[0].rows[0].rank, 1)
  globalThis.__benchHooks.unload()
})

test('native scroll commands are explicit, repeatable and discard superseded or unloaded callbacks', async () => {
  const h = setup({}, 1000), loaded = h.loadCategory()
  h.respondCategory(); await loaded
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
    assert.equal(h.clipboard.length, category.kinds.length)
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
  h.page.cubeCancel(); t.mock.timers.tick(24); t.mock.timers.tick(441)
  assert.equal(h.page.cubeBusy.value, false)
  h.page.copyBoardTitle(event({ kind }))
  assert.deepEqual(h.clipboard, [])
  t.mock.timers.tick(36)
  h.page.copyBoardTitle(event({ kind }))
  assert.deepEqual(h.clipboard, [h.page.cards.value[0].title])
  globalThis.__benchHooks.unload()
})

test('actual filter/settings handlers share source filters, react to theme, copy full names and repeat back-to-top', async () => {
  const h = setup(); const loading = h.loadCategory(); h.respondCategory(); await loading
  h.page.filterMenu(event({ kind: 'artificialAnalysis', mode: 'openness' }))
  h.page.sheetSelect({ detail: h.page.sheet.value.actions.find(action => action.value === 'open') })
  assert.deepEqual(h.page.cards.value.map(card => card.rows.length), [1, 1, 1])
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
  assert.deepEqual(h.page.tabs.value, ['Task benchmarks', 'User votes', 'Calibrated tests'])
  h.page.selectCategory(event({ id: 'image' }))
  assert.equal(h.page.cards.value[0].title, 'Artificial Analysis Text to Image')
  h.respondCategory(); await new Promise(resolve => setImmediate(resolve))
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
  const loaded = h.loadCategory(); h.respondCategory(); await loaded
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
  const loaded = h.loadCategory(); h.respondCategory(); await loaded
  wx.createSelectorQuery = () => { const query = { select() { return { fields: () => query } }, exec: callback => callback([{}]) }; return query }
  await h.page.screenshot()
  assert.match(toasts.at(-1).title, /生成失败/)
  assert.equal(h.page.capturing.value, false)
  assert.equal(h.page.capture.value.open, false)
  assert.equal(h.page.backgroundLocked.value, false)
  globalThis.__benchHooks.unload()
})

test('edge exit gestures never rotate, prepare another board or persist a selection on end, cancel or hide', async t => {
  t.mock.timers.enable({ apis: ['setTimeout'] })
  const touch = x => ({ touches: [{ clientX: x, clientY: 200 }] })
  for (const category of ['general', 'coding']) {
    const count = category === 'general' ? 3 : 2
    for (let face = 0; face < count; face++) for (const ending of ['end', 'cancel', 'hide']) {
      const h = setup({ category, face }, 1000)
      const loading = h.loadCategory(); h.respondCategory(); await loading
      const kind = h.page.cards.value[face].kind
      h.page.scroll({ ...event({ kind }), detail: { scrollTop: 2400 } })
      const styles = h.page.cubeFaces.value, selection = h.page.sourceSelection.value
      const scrolls = h.scrolls.length, writes = h.writes.length
      h.page.cubeStart(touch(16))
      for (const x of [17, 80, 300, -60]) {
        h.page.cubeMove(touch(x))
        assert.equal(h.page.cubeDragging.value, false)
        assert.equal(h.page.cubeBusy.value, false)
        assert.equal(h.page.cubePosition.value, face)
        assert.deepEqual(h.page.cubeFaces.value, styles)
        assert.equal(h.page.sourceSelection.value, selection)
      }
      if (ending === 'end') h.page.cubeEnd()
      else if (ending === 'cancel') { h.page.cubeCancel(); h.page.cubeEnd() }
      else { globalThis.__benchHooks.hide(); h.page.cubeEnd() }
      h.page.selectFace(event({ index: (face + 1) % count }))
      t.mock.timers.tick(1000)
      assert.equal(h.page.face.value, face)
      assert.equal(h.page.cubePosition.value, face)
      assert.equal(h.page.cubeBusy.value, false)
      assert.equal(h.page.cubeDuration.value, 0)
      assert.equal(h.scrolls.length, scrolls)
      assert.equal(h.writes.length, writes)
      globalThis.__benchHooks.unload()
    }
  }
})

test('cube drag preserves virtual windows and scroll rank, cancels safely and never turns a vertical gesture', async t => {
  t.mock.timers.enable({ apis: ['setTimeout'] })
  const h = setup({}, 1000), loading = h.loadCategory()
  h.respondCategory(); await loading
  expandRankings(h)
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
  t.mock.timers.tick(24); t.mock.timers.tick(440)
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

function delayedNativeScroll(states) {
  const commands = []
  wx.createSelectorQuery = () => {
    const results = []
    const query = {
      select: selector => ({
        node() { results.push({ node: { scrollTo: value => commands.push({ selector, ...value }) } }); return query },
        fields() { results.push(states[selector.replace('#board-scroll-', '')] ? { ...states[selector.replace('#board-scroll-', '')] } : null); return query },
        boundingClientRect() { results.push(null); return query },
      }),
      exec: callback => callback(results),
    }
    return query
  }
  return commands
}
function unequalBoards() {
  return Object.fromEntries([['artificialAnalysis', 32], ['arenaText', 140], ['epochECI', 120]].map(([kind, count]) => [kind, {
    kind, fetchedAt: '2026-10-18T00:00:00Z', entries: Array.from({ length: count }, (_, index) => ({ rank: index + 1, name: `Model ${index + 1}`, score: count - index })),
  }]))
}

test('long-to-short turns wait for the clamped native offset to stay stable before exposing the incoming face', t => {
  t.mock.timers.enable({ apis: ['setTimeout', 'Date'] })
  const h = setup({ face: 1 }, 0, {}, 'light', 'zh_CN', unequalBoards())
  expandRankings(h)
  t.after(() => globalThis.__benchHooks.unload())
  const states = { artificialAnalysis: { scrollTop: 0, height: 721, scrollHeight: 1885 } }
  const commands = delayedNativeScroll(states)
  h.page.scroll({ ...event({ kind: 'arenaText' }), detail: { scrollTop: 9000 } })
  h.page.selectFace(event({ index: 0 }))
  assert.equal(h.page.sourceTabIndex.value, 1, 'The tab must wait with the outgoing cube face during native scroll preparation')
  assert.ok(commands.at(-1).top > 1164, 'The requested rank lies beyond the shorter native viewport')
  h.page.scroll({ ...event({ kind: 'artificialAnalysis' }), detail: { scrollTop: 0 } })
  t.mock.timers.tick(96)
  assert.equal(h.page.cubeDuration.value, 0)
  assert.equal(h.page.sourceTabIndex.value, 1)
  assert.match(h.page.cubeFaces.value[1].style, /transform:none/, 'Keep the outgoing board on screen while native scroll is pending')
  assert.match(h.page.sourceTabsStyle.value, /translateY\(-50px\)/, 'A queued old native offset cannot reopen the tabs')
  states.artificialAnalysis.scrollTop = 1164
  t.mock.timers.tick(32)
  assert.equal(h.page.cubeDuration.value, 0, 'One acknowledgement is not enough while the compact header is still settling')
  t.mock.timers.tick(32); t.mock.timers.tick(24)
  assert.equal(h.page.cubeDuration.value, 420)
  assert.equal(h.page.sourceTabIndex.value, 0, 'The visual tab changes only when the cube can start rotating')
  assert.doesNotMatch(h.page.sourceTabsStyle.value, /--source-transition-duration:/, 'Cube preparation must not disable the tab transition')
  assert.match(h.page.cubeFaces.value[0].style, /transform:none/)
  assert.equal(states.artificialAnalysis.scrollTop, 1164)
  t.mock.timers.tick(440)
  assert.equal(h.page.face.value, 0)
  assert.equal(h.page.cubeBusy.value, false)
  assert.equal(h.page.backToTop.value, true)
})

test('releasing or cancelling a swipe before native preparation cannot reveal old rows or revive a stopped turn', t => {
  t.mock.timers.enable({ apis: ['setTimeout', 'Date'] })
  const touch = x => ({ touches: [{ clientX: x, clientY: 200 }] })
  for (const cancel of [false, true]) {
    const h = setup({ face: 1 }, 0, {}, 'light', 'zh_CN', unequalBoards())
    expandRankings(h)
    const states = { artificialAnalysis: { scrollTop: 0, height: 721, scrollHeight: 1885 } }
    delayedNativeScroll(states)
    h.page.scroll({ ...event({ kind: 'arenaText' }), detail: { scrollTop: 9000 } })
    h.page.cubeStart(touch(180)); h.page.cubeMove(touch(420))
    assert.match(h.page.cubeFaces.value[1].style, /transform:none/)
    if (cancel) h.page.cubeCancel()
    else h.page.cubeEnd()
    t.mock.timers.tick(24)
    assert.match(h.page.cubeFaces.value[1].style, /transform:none/, 'Release must not flash the partially dragged target before it is ready')
    states.artificialAnalysis.scrollTop = 1164
    t.mock.timers.tick(32); t.mock.timers.tick(32); t.mock.timers.tick(24); t.mock.timers.tick(440)
    assert.equal(h.page.face.value, cancel ? 1 : 0)
    assert.equal(h.page.cubeBusy.value, false)
    globalThis.__benchHooks.unload()
  }
  const h = setup({ face: 1 }, 0, {}, 'light', 'zh_CN', unequalBoards())
  const states = { artificialAnalysis: { scrollTop: 0, height: 721, scrollHeight: 1885 } }
  delayedNativeScroll(states)
  h.page.scroll({ ...event({ kind: 'arenaText' }), detail: { scrollTop: 9000 } })
  h.page.selectFace(event({ index: 0 }))
  globalThis.__benchHooks.hide()
  states.artificialAnalysis.scrollTop = 1164
  t.mock.timers.tick(1000)
  assert.equal(h.page.cubeBusy.value, false)
  assert.equal(h.page.cubeDuration.value, 0)
  globalThis.__benchHooks.unload()
})

test('a native scroll that never reaches its destination cancels the turn instead of revealing unsettled rows', t => {
  t.mock.timers.enable({ apis: ['setTimeout', 'Date'] })
  const h = setup({ face: 1 }, 0, {}, 'light', 'zh_CN', unequalBoards())
  t.after(() => globalThis.__benchHooks.unload())
  delayedNativeScroll({ artificialAnalysis: { scrollTop: 0, height: 721, scrollHeight: 1885 } })
  h.page.scroll({ ...event({ kind: 'arenaText' }), detail: { scrollTop: 9000 } })
  h.page.selectFace(event({ index: 0 }))
  t.mock.timers.tick(640)
  assert.equal(h.page.face.value, 1)
  assert.equal(h.page.cubeBusy.value, false)
  assert.equal(h.page.cubePosition.value, 1)
  assert.match(h.page.sourceTabsStyle.value, /translateY\(-50px\)/)
  assert.equal(h.writes.filter(write => write.key === 'benchgauge.preferences').at(-1).value.face, 1)
})

test('rapid tab changes reuse the visible origin while waiting and finish an in-flight rotation before the next one', t => {
  t.mock.timers.enable({ apis: ['setTimeout', 'Date'] })
  const h = setup({ face: 1 }, 0, {}, 'light', 'zh_CN', unequalBoards())
  expandRankings(h)
  t.after(() => globalThis.__benchHooks.unload())
  const states = { artificialAnalysis: { scrollTop: 0, height: 721, scrollHeight: 1885 }, epochECI: { scrollTop: 0, height: 721, scrollHeight: 6500 } }
  delayedNativeScroll(states)
  h.page.scroll({ ...event({ kind: 'arenaText' }), detail: { scrollTop: 9000 } })
  h.page.selectFace(event({ index: 0 }))
  h.page.selectFace(event({ index: 1 }))
  t.mock.timers.tick(80)
  assert.equal(h.page.face.value, 1)
  assert.equal(h.page.cubeBusy.value, false)
  assert.match(h.page.cubeFaces.value[1].style, /transform:none/)
  h.page.selectFace(event({ index: 0 }))
  states.artificialAnalysis.scrollTop = 1164
  t.mock.timers.tick(32); t.mock.timers.tick(32); t.mock.timers.tick(24)
  h.page.selectFace(event({ index: 2 }))
  assert.equal(h.page.face.value, 0, 'Do not snap to a different origin halfway through the current rotation')
  t.mock.timers.tick(440)
  assert.equal(h.page.face.value, 2, 'The most recent tab selection starts after the prior rotation finishes')
  states.epochECI.scrollTop = 1200
  t.mock.timers.tick(32); t.mock.timers.tick(32); t.mock.timers.tick(24); t.mock.timers.tick(440)
  assert.equal(h.page.cubeBusy.value, false)
  assert.equal(h.page.face.value, 2)
})

test('a board shorter than the viewport opens its tab space together with the rotation instead of jumping beforehand', t => {
  t.mock.timers.enable({ apis: ['setTimeout', 'Date'] })
  const cache = unequalBoards()
  cache.artificialAnalysis.entries = cache.artificialAnalysis.entries.slice(0, 3)
  const h = setup({ face: 1 }, 0, {}, 'light', 'zh_CN', cache)
  t.after(() => globalThis.__benchHooks.unload())
  delayedNativeScroll({ artificialAnalysis: { scrollTop: 0, height: 721, scrollHeight: 650 } })
  h.page.scroll({ ...event({ kind: 'arenaText' }), detail: { scrollTop: 9000 } })
  h.page.selectFace(event({ index: 0 }))
  t.mock.timers.tick(32)
  assert.match(h.page.cubeViewportStyle.value, /--cube-top:0px;/, 'Keep the outgoing clip while the incoming scroll view is preparing')
  t.mock.timers.tick(24)
  assert.match(h.page.cubeViewportStyle.value, /--cube-top:50px;--cube-layout-duration:420ms;/)
  t.mock.timers.tick(440)
  assert.equal(h.page.face.value, 0)
  assert.equal(h.page.cubeBusy.value, false)
  assert.equal(h.page.backToTop.value, false)
})

test('cube traverses every source and category in both directions, only wrapping category tabs', async t => {
  t.mock.timers.enable({ apis: ['setTimeout'] })
  const touch = x => ({ touches: [{ clientX: x, clientY: 200 }] })
  const expand = h => h.page.cards.value.filter(card => card.hasMore && !card.expanded)
    .forEach(card => h.page.toggleRanking(event({ kind: card.kind })))
  const sequence = categories.flatMap(item => item.kinds.map((kind, face) => ({ category: item.id, face, kind })))
  for (const direction of [-1, 1]) {
    let index = direction > 0 ? 0 : sequence.length - 1
    const initial = sequence[index], h = setup(initial, 1000)
    const loading = h.loadCategory(); h.respondCategory(); await loading
    expand(h)
    for (let turn = 0; turn < sequence.length * 2; turn++) {
      const origin = sequence[index]
      const next = sequence[(index + direction + sequence.length) % sequence.length]
      const boundary = origin.category !== next.category
      const kind = origin.kind
      h.page.cubeStart(touch(180))
      h.page.scroll({ currentTarget: { dataset: { kind } }, detail: { scrollTop: 2400 } })
      h.page.cubeStart(touch(180)); h.page.cubeMove(touch(180 - direction * 240))
      assert.equal(h.page.cubeDragging.value, true)
      if (boundary) {
        assert.equal(h.page.cubePosition.value, origin.face, 'Boundary holds the current board flat')
        assert.equal(h.page.cubeBusy.value, false)
      } else {
        assert.equal(h.page.cubeBusy.value, true)
        assert.equal(h.scrolls.at(-1).top, 2400, `${direction} ${turn} ${kind} -> ${next.kind}: ${h.page.cards.value[next.face].shownCount} rows`)
        assert.ok(h.page.cards.value[next.face].rows.some(row => row.rank === 51))
      }
      h.page.cubeEnd()
      assert.equal(h.page.category.value, next.category)
      assert.equal(h.page.face.value, next.face)
      const saved = h.writes.filter(write => write.key === 'benchgauge.preferences').at(-1).value
      assert.equal(saved.category, next.category); assert.equal(saved.face, next.face)
      t.mock.timers.tick(24); t.mock.timers.tick(440)
      assert.equal(h.page.cubePosition.value, next.face)
      assert.equal(h.page.cubeBusy.value, false)
      assert.match(h.page.cubeFaces.value[next.face].style, /transform:none.*pointer-events:auto/)
      h.respondCategory(); await new Promise(resolve => setImmediate(resolve)); expand(h)
      index = (index + direction + sequence.length) % sequence.length
    }
    globalThis.__benchHooks.unload()
  }
})

test('short or cancelled boundary drags leave the category and its flat board unchanged', t => {
  t.mock.timers.enable({ apis: ['setTimeout', 'Date'] })
  const touch = x => ({ touches: [{ clientX: x, clientY: 200 }] })
  for (const item of categories) for (const direction of [-1, 1]) for (const cancel of [false, true]) {
    const face = direction > 0 ? item.kinds.length - 1 : 0
    const h = setup({ category: item.id, face })
    h.page.cubeStart(touch(180))
    t.mock.timers.tick(200)
    h.page.cubeMove(touch(180 - direction * (cancel ? 240 : 40)))
    t.mock.timers.tick(200)
    if (cancel) h.page.cubeCancel()
    else h.page.cubeEnd()
    t.mock.timers.tick(1000)
    assert.equal(h.page.category.value, item.id)
    assert.equal(h.page.face.value, face)
    assert.equal(h.page.cubePosition.value, face)
    assert.equal(h.page.cubeBusy.value, false)
    assert.equal(h.page.cubeDragging.value, false)
    globalThis.__benchHooks.unload()
  }
})

test('settings visibility survives reload, hides the single-source tab space and navigates categories using visible counts', t => {
  t.mock.timers.enable({ apis: ['setTimeout'] })
  const boardSelections = Object.fromEntries(categories.map(item => [item.id, [item.kinds.at(-1)]]))
  const touch = x => ({ touches: [{ clientX: x, clientY: 200 }] })
  for (const direction of [-1, 1]) {
    let index = 1
    const h = setup({ category: 'general', face: 2, boardSelections })
    for (let turn = 0; turn < categories.length * 2; turn++) {
      assert.equal(h.page.cards.value.length, 1)
      assert.equal(h.page.cards.value[0].kind, categories[index].kinds.at(-1))
      assert.equal(h.page.face.value, 0)
      assert.equal(h.page.sourceTabsExtent.value, 0)
      assert.match(h.page.cubeViewportStyle.value, /--cube-top:0px/)
      h.page.cubeStart(touch(180)); h.page.cubeMove(touch(180 - direction * 240)); h.page.cubeEnd()
      index = (index + direction + categories.length) % categories.length
      assert.equal(h.page.category.value, categories[index].id)
      assert.equal(h.page.entranceHintVisible.value, false)
    }
    globalThis.__benchHooks.unload()
  }
  const template = readFileSync(new URL('../src/pages/leaderboard/index.wxml', import.meta.url), 'utf8')
  assert.match(template, /class="source-tabs \{\{tabs.length < 2 \? 'is-hidden' : ''\}\}"/)
  assert.match(template, /aria-hidden="\{\{tabs.length < 2\}\}"/)
  assert.doesNotMatch(template, /wx:if="[^"]*" class="source-tabs /, 'Keep the indicator mounted to animate count changes')
  assert.match(template, /bindtap="openSettings"/)
})

test('source tabs keep valid geometry and source identities through category, count and palette changes', () => {
  const preferences = { category: 'general', face: 2 }
  const h = setup(preferences)
  try {
    for (const dark of [false, true]) {
      h.theme(dark ? 'dark' : 'light')
      for (const category of categories) {
        h.page.selectCategory(event({ id: category.id }))
        for (const count of [...new Set([1, 2, category.kinds.length])].filter(count => count <= category.kinds.length)) {
          preferences.boardSelections = { [category.id]: category.kinds.slice(0, count) }
          globalThis.__benchHooks.show()
          const selectedKind = h.page.cards.value[h.page.sourceTabIndex.value].kind
          assert.equal(h.page.sourceTabItems.value.length, count)
          assert.deepEqual(h.page.sourceTabItems.value.map(item => item.content[0].kind), category.kinds.slice(0, count))
          assert.deepEqual(h.page.sourceTabItems.value.map(item => item.index), Array.from({ length: count }, (_, i) => i))
          assert.ok(h.page.sourceTabItems.value.every(item => item.content[0].label && item.content[0].icon))
          assert.equal(h.page.sourceTabWidth.value, `calc((100% - ${(count - 1) * 12}rpx) / ${count})`)
          assert.ok(h.page.sourceSelection.value.includes(`width:${h.page.sourceTabWidth.value};`))
          assert.ok(h.page.sourceSelection.value.includes(`background-color:${sourceTabTheme(selectedKind, dark).background};`))
          assert.equal(h.page.sourceTabsExtent.value, count === 1 ? 0 : 50)
          assert.equal(/pointer-events:none/.test(h.page.sourceTabsStyle.value), count === 1)
        }
      }
    }
  } finally { globalThis.__benchHooks.unload() }
})

test('source tab styling interpolates geometry with color and disables every added animation for reduced motion', () => {
  const styles = readFileSync(new URL('../src/pages/leaderboard/index.css', import.meta.url), 'utf8')
  assert.match(styles, /\.source-selection\s*\{[^}]*transition-property:\s*width, transform, background-color;/)
  assert.match(styles, /\.source-tab\s*\{[^}]*transition:\s*width 420ms ease-in-out, color 420ms ease-in-out;/)
  assert.match(styles, /prefers-reduced-motion:\s*reduce[^\n]*\.source-tab-logo[^\n]*transition-delay:\s*0ms[^\n]*\.source-tab-content\s*\{\s*animation:\s*none;/)
  const template = readFileSync(new URL('../src/pages/leaderboard/index.wxml', import.meta.url), 'utf8')
  assert.match(template, /wx:for="\{\{sourceTabItems\}\}" wx:key="index"/)
  assert.match(template, /wx:for-item="content" wx:key="kind"/)
})

test('returning from settings preserves the active source when hiding siblings or resetting', () => {
  const preferences = { category: 'general', face: 2 }
  const h = setup(preferences)
  const show = () => globalThis.__benchHooks.show()
  assert.equal(h.page.cards.value[h.page.face.value].kind, 'epochECI')
  preferences.boardSelections = { general: ['epochECI'] }
  show()
  assert.equal(h.page.face.value, 0)
  assert.equal(h.page.cards.value.length, 1)
  assert.equal(h.page.cards.value[0].kind, 'epochECI')
  delete preferences.boardSelections
  show()
  assert.equal(h.page.face.value, 2)
  assert.equal(h.page.cards.value.length, 3)
  assert.equal(h.page.sourceTabsExtent.value, 50)
  preferences.boardSelections = { general: ['arenaText'] }
  show()
  assert.equal(h.page.face.value, 0)
  assert.equal(h.page.cards.value[0].kind, 'arenaText')
  globalThis.__benchHooks.unload()
})

test('cancelled and reversed boundary drags cannot switch categories or let an old timer overwrite navigation', t => {
  t.mock.timers.enable({ apis: ['setTimeout'] })
  const h = setup(), touch = x => ({ touches: [{ clientX: x, clientY: 200 }] })
  h.page.cubeStart(touch(180)); h.page.cubeMove(touch(300)); h.page.cubeCancel()
  t.mock.timers.tick(24); t.mock.timers.tick(440)
  assert.equal(h.page.face.value, 0); assert.equal(h.page.cubePosition.value, 0)
  assert.equal(h.page.category.value, 'general')
  h.page.cubeStart(touch(180)); h.page.cubeMove(touch(300)); h.page.cubeMove(touch(-60)); h.page.cubeEnd()
  assert.equal(h.page.face.value, 1, 'Reversing before release uses the final direction')
  t.mock.timers.tick(24)
  h.page.cubeStart(touch(180)); h.page.cubeMove(touch(420)); h.page.cubeEnd()
  assert.equal(h.page.face.value, 0)
  t.mock.timers.tick(24); t.mock.timers.tick(440)
  assert.equal(h.page.cubePosition.value, 0)
  h.page.cubeStart(touch(180)); h.page.cubeMove(touch(420)); h.page.cubeEnd()
  assert.equal(h.page.category.value, 'usage'); assert.equal(h.page.face.value, 2)
  globalThis.__benchHooks.hide()
  t.mock.timers.tick(400)
  assert.equal(h.page.cubePosition.value, 2); assert.equal(h.page.cubeBusy.value, false)
  h.page.selectCategory(event({ id: 'coding' }))
  assert.equal(h.page.face.value, 1); assert.equal(h.page.cubePosition.value, 1)
  globalThis.__benchHooks.unload()
})

test('native vertical scroll before direction lock keeps ownership until touch end and the next horizontal swipe still works', async () => {
  const h = setup({}, 1000), loading = h.loadCategory()
  h.respondCategory(); await loading
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
    const h = setup({ face }, 1000), loading = h.loadCategory()
    h.respondCategory(); await loading
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
  const h = setup({ face }), loading = h.loadCategory()
  globalThis.__benchHooks.show()
  h.respondCategory(); await loading
  t.mock.timers.tick(1000)
  assert.equal(h.page.cubeBusy.value, false, 'wait until the native page is ready')
  globalThis.__benchHooks.ready()
  t.mock.timers.tick(220)
  assert.equal(h.page.cubePosition.value, face ? 1 - 0.06 : 0.06)
  assert.match(h.page.entranceStyle.value, /opacity:0.65/)
  assert.equal(h.page.entranceHintVisible.value, true)
  t.mock.timers.tick(24)
  assert.equal(h.page.face.value, face); assert.equal(h.page.cubeBusy.value, true)
  assert.equal(h.page.cubePosition.value, face ? 0.90 : 0.10); assert.equal(h.page.cubeDuration.value, 420)
  assert.match(h.page.entranceStyle.value, /transform:none/)
  t.mock.timers.tick(550)
  assert.equal(h.page.cubePosition.value, face); assert.equal(h.page.cubeDuration.value, 700)
  assert.match(h.page.cubeFaces.value[face ? 0 : 1].style, face
    ? /rotateY\(-90deg\).*transform-origin:right center/
    : /rotateY\(90deg\).*transform-origin:left center/)
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
  const h = setup(), loading = h.loadCategory()
  t.after(() => globalThis.__benchHooks.unload())
  globalThis.__benchHooks.show(); globalThis.__benchHooks.ready()
  h.respondCategory(); await loading
  const initialSelection = h.page.sourceSelection.value
  t.mock.timers.tick(220); t.mock.timers.tick(24)
  assert.equal(h.page.cubePosition.value, 0.10)
  assert.equal(h.page.sourceSelection.value, initialSelection)
  h.page.selectFace(event({ index: 1 }))
  assert.equal(h.page.sourceSelection.value, initialSelection, 'Mounting the target cube face must not move the tab early')
  t.mock.timers.tick(24)
  const votedSelection = h.page.sourceSelection.value
  assert.match(votedSelection, /translateX\(100%\)/)
  assert.equal(h.page.entranceHintVisible.value, false)
  t.mock.timers.tick(440)
  h.page.cubeStart({ touches: [{ clientX: 60, clientY: 200 }] })
  h.page.cubeMove({ touches: [{ clientX: 280, clientY: 200 }] })
  assert.ok(h.page.cubePosition.value < 0.5)
  assert.equal(h.page.face.value, 1)
  assert.equal(h.page.sourceSelection.value, votedSelection)
  h.page.cubeEnd()
  assert.equal(h.page.face.value, 0)
  assert.equal(h.page.sourceSelection.value, votedSelection)
  t.mock.timers.tick(24)
  assert.equal(h.page.sourceSelection.value, initialSelection)
})

test('source tab motion starts with the cube and uses its complete settle duration', async t => {
  t.mock.timers.enable({ apis: ['setTimeout', 'Date'] })
  const h = setup(), loaded = h.loadCategory()
  t.after(() => globalThis.__benchHooks.unload())
  h.respondCategory(); await loaded
  h.page.selectFace(event({ index: 1 }))
  assert.equal(h.page.face.value, 1, 'The destination may load before visual motion starts')
  assert.equal(h.page.sourceTabIndex.value, 0)
  assert.equal(h.page.cubePosition.value, 0)
  assert.doesNotMatch(h.page.sourceTabsStyle.value, /--source-transition-duration:/, 'No 0ms tab style crosses the native bridge during preparation')
  t.mock.timers.tick(23)
  assert.equal(h.page.sourceTabIndex.value, 0)
  t.mock.timers.tick(1)
  assert.equal(h.page.cubePosition.value, 1)
  assert.equal(h.page.sourceTabIndex.value, 1)
  const duration = h.page.cubeDuration.value
  assert.equal(duration, 420)
  assert.doesNotMatch(h.page.sourceTabsStyle.value, /--source-transition-duration:/, 'Tab motion remains armed independently of cube preparation')
  t.mock.timers.tick(320)
  assert.equal(h.page.cubeBusy.value, true, 'The old tab duration must not define the end of the shared transition')
  assert.doesNotMatch(h.page.sourceTabsStyle.value, /--source-transition-duration:/, 'Tab motion remains armed independently of cube preparation')
  t.mock.timers.tick(duration - 320 + 20)
  assert.equal(h.page.cubeBusy.value, false)
  assert.equal(h.page.sourceTabIndex.value, 1)
  assert.equal(h.page.cubePosition.value, 1)
})

test('source tabs scroll out with the active board and return on back-to-top or grouping reset', async t => {
  const h = setup({}, 100), loading = h.loadCategory()
  t.after(() => globalThis.__benchHooks.unload())
  h.respondCategory(); await loading
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
  const h = setup({}, 1000), loaded = h.loadCategory()
  h.respondCategory(); await loaded
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
  const h = setup({}, 1000), loaded = h.loadCategory()
  h.respondCategory(); await loaded
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
  const cache = Object.fromEntries(['artificialAnalysis', 'arenaText', 'epochECI'].map(kind => [kind, {
    kind, fetchedAt: '2026-10-13T12:00:00Z', entries: [{ rank: 1, name: 'Cached model', score: 99 }],
  }]))
  const h = setup({ face: 1 }, 0, {}, 'light', 'zh_CN', cache)
  const loading = h.loadCategory()
  globalThis.__benchHooks.show(); globalThis.__benchHooks.ready()
  t.mock.timers.tick(220); t.mock.timers.tick(24)
  assert.equal(h.requests.length, 3)
  assert.equal(h.page.cubePosition.value, 0.90)
  assert.equal(h.page.entranceHintVisible.value, true)
  globalThis.__benchHooks.unload(); await loading
  t.mock.timers.tick(5000)
  assert.equal(h.page.cubeBusy.value, false); assert.equal(h.page.entranceHintVisible.value, false)
})

test('background data cannot start the reveal; touching it cancels all delayed steps', async t => {
  t.mock.timers.enable({ apis: ['setTimeout'] })
  const h = setup(), loading = h.loadCategory()
  globalThis.__benchHooks.show(); globalThis.__benchHooks.ready(); globalThis.__benchHooks.hide()
  h.respondCategory(); await loading; t.mock.timers.tick(1000)
  assert.equal(h.page.cubeBusy.value, false)
  globalThis.__benchHooks.show(); t.mock.timers.tick(220); t.mock.timers.tick(24)
  assert.equal(h.page.cubePosition.value, 0.10)
  h.page.cubeStart({ touches: [{ clientX: 200, clientY: 300 }] })
  assert.equal(h.page.cubePosition.value, 0); assert.equal(h.page.entranceHintVisible.value, false)
  t.mock.timers.tick(5000)
  assert.equal(h.page.cubeBusy.value, false); assert.equal(h.page.cubePosition.value, 0)
  globalThis.__benchHooks.unload()
})

test('all controls and global filters survive a local cold start, including manual language', async () => {
  const h = setup({}, 0, {}, 'light', 'en_US')
  assert.equal(h.page.labels.value.name, 'AI BenchGauge')
  const loading = h.loadCategory(); h.respondCategory(); await loading
  const expectedFilters = {}
  for (const category of ['general', 'coding', 'image', 'video']) {
    const start = h.requests.length
    const changed = category !== h.page.category.value
    h.page.selectCategory(event({ id: category }))
    assert.equal(h.requests.length, start + (changed ? 1 : 0))
    if (changed) { h.respondCategory() }
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


function tabTouch(kind, x, y = 740, ended = false) {
  const point = { identifier: 1, clientX: x, clientY: y }
  return { currentTarget: { dataset: { tabs: kind } }, touches: ended ? [] : [point], changedTouches: [point] }
}
function mockTabBounds() {
  wx.createSelectorQuery = () => {
    const q = { select: () => q, boundingClientRect: () => q, node: () => q, fields: () => q,
      exec: callback => callback([{ left: 20, width: 320 }]) }
    return q
  }
}
test('edge exit gestures on either tab bar never preview or commit another selection', () => {
  for (const kind of ['source', 'category']) for (const cancelled of [false, true]) {
    const h = setup(); mockTabBounds()
    const selection = h.page.sourceSelection.value
    h.page.tabStart(tabTouch(kind, 16))
    for (const x of [17, 170, 300, -60]) {
      h.page.tabMove(tabTouch(kind, x))
      assert.equal(h.page.categoryIndex.value, 1)
      assert.equal(h.page.sourceTabIndex.value, 0)
      assert.equal(h.page.sourceSelection.value, selection)
      assert.equal(h.page.cubeBusy.value, false)
    }
    if (cancelled) h.page.cancelTabDrag()
    h.page.tabEnd(tabTouch(kind, 300, 740, true))
    h.page.selectFace(event({ index: 1 }))
    h.page.selectCategory(event({ id: 'coding' }))
    assert.equal(h.page.face.value, 0)
    assert.equal(h.page.category.value, 'general')
    assert.equal(h.requests.length, 0)
    assert.equal(h.writes.length, 0)
    globalThis.__benchHooks.unload()
  }
})

test('bar drags preview under the finger and commit only the final category once', () => {
  const h = setup(); mockTabBounds()
  h.page.tabStart(tabTouch('category', 60))
  h.page.tabMove(tabTouch('category', 190))
  assert.equal(h.page.categoryIndex.value, 2)
  assert.equal(h.page.category.value, 'general')
  assert.equal(h.requests.length, 0)
  h.page.tabMove(tabTouch('category', 600))
  assert.equal(h.page.categoryIndex.value, 4)
  h.page.tabEnd(tabTouch('category', 600, 740, true))
  assert.equal(h.page.category.value, 'video')
  assert.equal(h.requests.length, 1, 'Only the active source in the released category is fetched')
  h.page.selectCategory(event({ id: 'coding' }))
  assert.equal(h.page.category.value, 'video', 'A synthesized tap cannot overwrite the drag result')
  h.page.tabStart(tabTouch('category', 300))
  h.page.tabMove(tabTouch('category', -100))
  h.page.tabEnd(tabTouch('category', -100, 740, true))
  assert.equal(h.page.category.value, 'usage')
  globalThis.__benchHooks.unload()
})
test('source bar drags do not rotate or copy while moving; release selects the pointed tab', () => {
  const h = setup(); mockTabBounds()
  h.page.tabStart(tabTouch('source', 60, 100))
  h.page.tabMove(tabTouch('source', 300, 102))
  assert.equal(h.page.sourceTabIndex.value, 2)
  assert.equal(h.page.face.value, 0)
  assert.equal(h.page.cubeDragging.value, false)
  h.page.tabEnd(tabTouch('source', 300, 102, true))
  assert.equal(h.page.face.value, 2)
  h.page.selectFace(event({ index: 0 }))
  assert.equal(h.page.face.value, 2)
  assert.deepEqual(h.clipboard, [])
  globalThis.__benchHooks.unload()
})
test('vertical, multitouch, cancelled and interrupted tab drags never change a selection', () => {
  const h = setup(); mockTabBounds()
  h.page.tabStart(tabTouch('category', 60))
  h.page.tabMove(tabTouch('category', 70, 780))
  h.page.tabMove(tabTouch('category', 300, 790))
  h.page.tabEnd(tabTouch('category', 300, 790, true))
  assert.equal(h.page.category.value, 'general')
  for (const cancel of [() => h.page.cancelTabDrag(), () => globalThis.__benchHooks.hide(),
    () => h.page.tabEnd(tabTouch('category', 300)),
    () => h.page.tabMove({ ...tabTouch('category', 300), touches: [{ clientX: 300 }, { clientX: 310 }] })]) {
    h.page.tabStart(tabTouch('category', 60)); h.page.tabMove(tabTouch('category', 300))
    cancel(); h.page.tabEnd(tabTouch('category', 300, 740, true))
    assert.equal(h.page.category.value, 'general')
    assert.equal(h.page.categoryIndex.value, 1)
  }
  assert.equal(h.requests.length, 0)
  globalThis.__benchHooks.unload()
})
test('a delayed bounds query cannot revive a released tab gesture', () => {
  const h = setup(); let measured
  const q = { select: () => q, boundingClientRect: () => q, exec: callback => { measured = callback } }
  wx.createSelectorQuery = () => q
  h.page.tabStart(tabTouch('category', 60)); h.page.tabMove(tabTouch('category', 300))
  h.page.tabEnd(tabTouch('category', 300, 740, true))
  measured([{ left: 20, width: 320 }])
  assert.equal(h.page.categoryIndex.value, 1)
  assert.equal(h.page.category.value, 'general')
  globalThis.__benchHooks.unload()
})

test('adding touch handlers preserves ordinary taps and double-tap return to top', () => {
  const h = setup(); mockTabBounds()
  const touch = tabTouch('category', 60)
  h.page.tabStart(touch); h.page.tabEnd(tabTouch('category', 60, 740, true))
  h.page.selectCategory(event({ id: 'general' }))
  const before = h.scrolls.length
  h.page.tabStart(touch); h.page.tabEnd(tabTouch('category', 60, 740, true))
  // Restore the ordinary native scroll query to observe the second tap.
  wx.createSelectorQuery = () => {
    const q = { select: () => q, node: () => q,
      exec: cb => cb([{ node: { scrollTo: value => h.scrolls.push(value) } }]) }
    return q
  }
  h.page.selectCategory(event({ id: 'general' }))
  assert.equal(h.scrolls.length, before + 1)
  globalThis.__benchHooks.unload()
})

test('Epoch is a third live source with original score precision, persistent sharing and safe category switches', async () => {
  const h = setup({ face: 2 });
  const loaded = h.loadCategory(); h.respondCategory(); await loaded;
  assert.equal(h.requests.length, 3);
  assert.equal(h.page.cubeFaces.value.length, 3);
  assert.equal(h.page.cards.value[2].kind, 'epochECI');
  assert.equal(h.page.cards.value[2].rows[1].scoreText, '98.00');
  assert.equal(h.page.cards.value[2].rows[1].scoreShare, '99%');
  assert.equal(h.page.cards.value[2].rows[1].fillPercent, 98.98989898989899);
  assert.match(h.page.sourceSelection.value, /\/ 3/);
  const shared = pagePreferences(Object.fromEntries(new URL('https://shared.example' + globalThis.__benchHooks.share().path).searchParams));
  assert.equal(shared.face, 2);
  h.page.selectCategory(event({ id: 'coding' })); h.respondCategory();
  assert.equal(h.page.face.value, 1);
  assert.equal(h.page.cubePosition.value, 1);
  assert.equal(h.page.cubeFaces.value.length, 2);
  globalThis.__benchHooks.unload();
});


test('source header accents follow full identities across category changes and live theme updates', async () => {
  const h = setup()
  const loaded = h.loadCategory(); h.respondCategory(); await loaded
  for (const dark of [false, true]) {
    h.theme(dark ? 'dark' : 'light')
    for (const category of categories) {
      h.page.selectCategory(event({ id: category.id })); h.respondCategory()
      for (const card of h.page.cards.value) {
        assert.equal(card.themeStyle, `--source-accent:${sourceTabTheme(card.kind, dark).accent};`)
      }
    }
  }
  globalThis.__benchHooks.unload()
})


test('bottom category icons and selected label follow the active source and live appearance', async () => {
  const h = setup()
  const loaded = h.loadCategory(); h.respondCategory(); await loaded
  for (const dark of [false, true]) {
    h.theme(dark ? 'dark' : 'light')
    for (const category of categories) {
      h.page.selectCategory(event({ id: category.id })); h.respondCategory()
      for (const [index, kind] of category.kinds.entries()) {
        // Exercise the reactive face state used by taps, drags and cube swipes.
        h.page.face.value = index
        const { accent } = sourceTabTheme(kind, dark)
        assert.equal(h.page.categoryThemeStyle.value, `--category-accent:${accent};`)
        assert.deepEqual(h.page.categoryItems.value.map(item => item.icon),
          categories.map(item => `/assets/categories/${item.id}-${accent.slice(1)}.png`))
        assert.equal(h.page.category.value, category.id)
      }
    }
  }
  globalThis.__benchHooks.unload()
})


test('recent header dates remain localized through loading and source help', async t => {
  t.mock.timers.enable({ apis: ['Date'], now: Date.parse('2026-10-25T06:00:00Z') })
  const originalZone = process.env.TZ
  process.env.TZ = 'Asia/Shanghai'
  try {
    const h = setup({ language: 'zh-CN' }), loading = h.loadCategory()
    h.respond(0, { sourceUpdatedAt: '2026-10-25T01:00:00Z' })
    h.respond(1, { sourceUpdatedAt: '2026-10-22T00:00:00Z', sourceNote: 'https://huggingface.co/datasets/lmarena-ai/leaderboard-dataset' })
    h.respond(2, { sourceUpdatedAt: '2026-10-21T01:00:00Z' })
    await loading
    assert.deepEqual(h.page.cards.value.map(card => card.time), ['今天 09:00', '大前天', '10/21 09:00'])
    for (const card of h.page.cards.value) {
      assert.ok(card.timeAccessibility.startsWith(card.time))
      h.page.sourceHelp(event({ kind: card.kind }))
      assert.ok(h.modals.at(-1).content.includes(card.time))
    }
    globalThis.__benchHooks.unload()
  } finally {
    if (originalZone === undefined) delete process.env.TZ
    else process.env.TZ = originalZone
  }
})
