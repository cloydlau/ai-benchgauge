import assert from 'node:assert/strict'
import test from 'node:test'
import { registerHooks } from 'node:module'
import { canvasHarness } from './helpers/canvas.mjs'
import { pagePreferences } from '../src/core/share-state.js'

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
      export const onShow = fn => { globalThis.__benchHooks.show = fn }
      export const onUnload = fn => { globalThis.__benchHooks.unload = fn }
      export const onResize = fn => { globalThis.__benchHooks.resize = fn }
      export const onShareAppMessage = fn => { globalThis.__benchHooks.share = fn }
    ` }
  },
})
await import('../src/pages/leaderboard/index.js')
registration.deregister()

function setup(preferences = {}, count = 0, query = {}, systemTheme = 'light', systemLocale = 'zh_CN') {
  const requests = []; const writes = []; const modals = []; const clipboard = []
  globalThis.__SHARED_ENDPOINT__ = 'https://shared.example'
  globalThis.__benchHooks = {}
  let themeListener
  globalThis.wx = {
    getStorageSync: key => key === 'benchgauge.preferences' ? preferences : {},
    setStorageSync: (key, value) => writes.push({ key, value }),
    getWindowInfo: () => ({ statusBarHeight: 24, windowWidth: 375 }),
    getMenuButtonBoundingClientRect: () => ({ top: 28, bottom: 60, left: 270 }),
    getAppBaseInfo: () => ({ theme: systemTheme, language: systemLocale }),
    onThemeChange: fn => { themeListener = fn }, offThemeChange: () => { themeListener = null },
    setNavigationBarColor() {}, showModal: options => modals.push(options),
    setClipboardData: options => clipboard.push(options.data), navigateTo() {},
    request(options) { const task = { abort() { options.fail(); options.complete() } }; requests.push({ options, task }); return task },
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
  return { page, requests, writes, modals, clipboard, respond, theme: theme => themeListener?.({ theme }) }
}
const event = dataset => ({ currentTarget: { dataset } })

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
  assert.equal(h.page.capsuleWidth.value, 117)
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
  assert.match(message.title, /使用者盲測/)
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
  h.page.top()
  h.page.scroll({ ...event({ kind: card.kind }), detail: { scrollTop: 0 } })
  assert.equal(h.page.cards.value[0].rows[0].rank, 1)
  h.page.rowDetails(event({ kind: card.kind, rank: 10000 }))
  assert.equal(h.modals.at(-1).content, 'Model 10000')
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

test('measured header origin follows the scroll container and stale layout callbacks are ignored', async () => {
  const h = setup({}, 10000)
  const callbacks = []
  wx.nextTick = action => action()
  wx.createSelectorQuery = () => ({
    select() { return { boundingClientRect() {} } },
    exec: callback => callbacks.push(callback),
  })
  const pending = globalThis.__benchHooks.load(); h.respond(0); h.respond(1); await pending
  const rects = [{ top: 50, height: 480 }, { top: 250 }, { top: 50, height: 0 }, null]
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
test('actual filter/settings handlers retain independent source filters, react to theme, copy full names and repeat back-to-top', async () => {
  const h = setup(); const loading = globalThis.__benchHooks.load(); h.respond(0); h.respond(1); await loading
  h.page.filterMenu(event({ kind: 'artificialAnalysis', mode: 'openness' }))
  h.page.sheetSelect({ detail: h.page.sheet.value.actions.find(action => action.value === 'open') })
  assert.deepEqual(h.page.cards.value.map(card => card.rows.length), [1, 2])
  h.page.selectGrouping(event({ id: 'company' }))
  assert.equal(h.page.cards.value[0].rows[0].name, 'DeepSeek')
  h.page.rowDetails(event({ kind: 'artificialAnalysis', rank: 1 }))
  h.modals.at(-1).success({ confirm: true }); assert.equal(h.clipboard.at(-1), 'DeepSeek')
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
  h.page.scroll({ currentTarget: { dataset: { kind: 'artificialAnalysis' } }, detail: { scrollTop: 600 } })
  assert.equal(h.page.backToTop.value, true)
  h.page.top(); const first = h.page.scrollTargets.value.artificialAnalysis
  h.page.top(); assert.notEqual(h.page.scrollTargets.value.artificialAnalysis, first)
  assert.ok(h.writes.some(write => write.key === 'benchgauge.preferences' && write.value.language === 'en'))
  globalThis.__benchHooks.unload()
})

test('the screenshot button exports full filtered comparisons and album retries resume after the last saved page', async () => {
  const h = setup({}, 140), canvas = canvasHarness(), toasts = []
  Object.assign(wx, canvas.platform, { showLoading() {}, hideLoading() {},
    showToast: options => toasts.push(options), previewImage: options => { h.preview = options }, openSetting: () => { h.settings = true },
    createSelectorQuery: () => { const query = { select() { return { fields: () => query, boundingClientRect: () => query } }, exec: callback => callback([{ node: canvas.canvas }]) }; return query },
  })
  const loaded = globalThis.__benchHooks.load(); h.respond(0); h.respond(1); await loaded
  for (const [kind, value] of [['artificialAnalysis', 'open'], ['arenaText', 'closed']]) {
    h.page.filterMenu(event({ kind, mode: 'openness' }))
    h.page.sheetSelect({ detail: h.page.sheet.value.actions.find(action => action.value === value) })
  }
  await h.page.screenshot()
  assert.ok(h.page.capture.value.paths.length > 1)
  assert.equal(h.page.capture.value.open, true)
  assert.equal(h.page.capturing.value, false)
  const names = column => canvas.commands.filter(([command, value, x]) => command === 'fillText' && /^Model \d+$/.test(value) && (x < 500) === (column === 0)).map(command => command[1])
  assert.deepEqual(names(0), Array.from({ length: 70 }, (_, index) => `Model ${(index + 1) * 2}`))
  assert.deepEqual(names(1), Array.from({ length: 70 }, (_, index) => `Model ${index * 2 + 1}`))
  h.page.previewScreenshot(event({ index: 1 }))
  assert.equal(h.preview.current, h.page.capture.value.paths[1])
  h.page.capturePage(event({ step: 1 })); assert.equal(h.page.capture.value.index, 1)
  h.page.previewScreenshot(event({ index: 0 })); assert.equal(h.preview.current, h.page.capture.value.paths[0])
  let attempts = 0
  wx.saveImageToPhotosAlbum = options => {
    if (++attempts === 2) options.fail({ errMsg: 'saveImageToPhotosAlbum:fail auth deny' })
    else { canvas.saved.push(options.filePath); options.success({}) }
  }
  await h.page.saveScreenshot()
  assert.equal(h.page.capture.value.saved, 1)
  assert.equal(h.page.capture.value.saving, false)
  assert.match(h.modals.at(-1).content, /允许保存/)
  h.modals.at(-1).success({ confirm: true }); assert.equal(h.settings, true)
  await h.page.saveScreenshot()
  assert.equal(h.page.capture.value.saved, h.page.capture.value.paths.length)
  assert.deepEqual(canvas.saved, h.page.capture.value.paths)
  assert.equal(toasts.at(-1).icon, 'success')
  h.page.closeCapture(); assert.equal(h.page.capture.value.open, false)
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
  globalThis.__benchHooks.unload()
})

test('cube drag preserves virtual windows and scroll rank, cancels safely and never turns a vertical gesture', async () => {
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
  assert.equal(h.page.scrollTargets.value[to], 2400)
  assert.deepEqual(h.page.cards.value[0].rows, rows)
  assert.ok(h.page.cards.value[1].rows.some(row => row.rank === 51))
  h.page.rowDetails(event({ kind: from, rank: 51 })); assert.equal(h.modals.length, 0)
  h.page.cubeEnd(); assert.equal(h.page.face.value, 1)
  await new Promise(resolve => setTimeout(resolve, 390))
  assert.equal(h.page.cubeBusy.value, false); assert.equal(h.page.cubePosition.value, 1)
  h.page.cubeStart(touch(40, 200)); h.page.cubeMove(touch(250, 200)); h.page.cubeCancel()
  assert.equal(h.page.face.value, 1)
  globalThis.__benchHooks.resize()
  assert.equal(h.page.cubeBusy.value, false); assert.equal(h.page.cubePosition.value, 1)
  h.page.selectCategory(event({ id: 'coding' }))
  globalThis.__benchHooks.unload()
  await new Promise(resolve => setTimeout(resolve, 390))
  assert.equal(h.page.cubeBusy.value, false); assert.equal(h.page.category.value, 'coding')
})

test('first entrance gently reveals the other cube face without changing the saved source', async () => {
  const h = setup({ face: 1 }), loading = globalThis.__benchHooks.load()
  h.respond(0); h.respond(1); await loading
  await new Promise(resolve => setTimeout(resolve, 360))
  assert.equal(h.page.face.value, 1); assert.equal(h.page.cubeBusy.value, true)
  assert.equal(h.page.cubePosition.value, 0.86); assert.equal(h.page.cubeDuration.value, 220)
  await new Promise(resolve => setTimeout(resolve, 750))
  assert.equal(h.page.face.value, 1); assert.equal(h.page.cubePosition.value, 1)
  assert.equal(h.page.cubeBusy.value, false)
  globalThis.__benchHooks.unload()
})

test('all controls and independent board filters survive a local cold start, including manual language', async () => {
  const h = setup({}, 0, {}, 'light', 'en_US')
  assert.equal(h.page.labels.value.name, 'AI BenchGauge')
  const expectedFilters = {}
  for (const category of ['general', 'coding', 'image', 'video']) {
    const start = h.requests.length
    h.page.selectCategory(event({ id: category })); h.respond(start); h.respond(start + 1)
    await new Promise(resolve => setImmediate(resolve))
    for (const [index, card] of h.page.cards.value.entries()) {
      const filter = { country: index ? 'CN' : 'US', openness: index ? 'open' : 'closed' }
      h.page.filterMenu(event({ kind: card.kind, mode: 'country' })); h.page.sheetSelect({ detail: { value: filter.country } })
      h.page.filterMenu(event({ kind: card.kind, mode: 'openness' })); h.page.sheetSelect({ detail: { value: filter.openness } })
      expectedFilters[card.kind] = filter
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
