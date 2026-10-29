import assert from 'node:assert/strict'
import test from 'node:test'
import { registerHooks } from 'node:module'
import { readFileSync } from 'node:fs'
import { categories } from '../src/core/catalog.js'
import { boardFaceStyle } from '../src/core/board-transition.js'

const registration = registerHooks({
  resolve(specifier, context, next) {
    return specifier === '@vue-mini/core' ? { url: 'benchgauge:settings-vue', shortCircuit: true } : next(specifier, context)
  },
  load(url, context, next) {
    if (url !== 'benchgauge:settings-vue') return next(url, context)
    return { format: 'module', shortCircuit: true, source: `
      export const definePage = factory => { globalThis.__settingsFactory = factory }
      export const ref = value => ({ value })
      export const computed = getter => ({ get value() { return getter() } })
      export const onReady = hook => { globalThis.__settingsHooks.ready = hook }
      export const onShow = hook => { globalThis.__settingsHooks.show = hook }
      export const onHide = hook => { globalThis.__settingsHooks.hide = hook }
      export const onUnload = hook => { globalThis.__settingsHooks.unload = hook }
    ` }
  },
})
await import('../src/pages/settings/index.js')
registration.deregister()

function setup(saved = {}) {
  let stored = saved, backs = 0, launched
  const colors = []
  globalThis.wx = {
    getStorageSync: () => stored, setStorageSync: (_, value) => { stored = value },
    getAppBaseInfo: () => ({ language: 'zh_CN', theme: 'light' }),
    getWindowInfo: () => ({ statusBarHeight: 24 }),
    setNavigationBarColor: options => colors.push(options),
    navigateBack: () => { backs++ }, reLaunch: options => { launched = options.url },
  }
  globalThis.getCurrentPages = () => [1, 2]
  const hooks = globalThis.__settingsHooks = {}
  const page = globalThis.__settingsFactory({})
  const toggle = (category, kind) => page.toggleBoard({ currentTarget: { dataset: { category, kind } } })
  return { page, hooks, toggle, colors, stored: () => stored, backs: () => backs, launched: () => launched }
}

test('motion preview waits for the first render, stops when hidden and restarts on return', t => {
  t.mock.timers.enable({ apis: ['setTimeout'] })
  const { page, hooks } = setup()
  assert.equal(page.previewRunning.value, false)
  hooks.show()
  assert.equal(page.previewRunning.value, false, 'The initial onShow precedes the first completed render')
  hooks.ready()
  assert.equal(page.previewRunning.value, true)
  const start = page.previewFaces.value
  t.mock.timers.tick(299)
  assert.deepEqual(page.previewFaces.value, start)
  t.mock.timers.tick(1)
  const end = page.previewFaces.value
  for (const style of ['cube', 'slide', 'fade']) assert.notDeepEqual(end[style], start[style])
  t.mock.timers.tick(2699)
  assert.deepEqual(page.previewFaces.value, end)
  t.mock.timers.tick(1)
  assert.deepEqual(page.previewFaces.value, start, 'All previews restart after exactly three seconds')
  t.mock.timers.tick(300)
  hooks.hide()
  assert.equal(page.previewRunning.value, false)
  assert.deepEqual(page.previewFaces.value, start)
  t.mock.timers.tick(6000)
  assert.deepEqual(page.previewFaces.value, start, 'Hidden pages cancel all pending motion')
  hooks.show()
  assert.equal(page.previewRunning.value, true)
  assert.deepEqual(page.previewFaces.value, start)
  t.mock.timers.tick(300)
  assert.deepEqual(page.previewFaces.value, end)
  hooks.unload()
  assert.equal(page.previewRunning.value, false)
  t.mock.timers.tick(6000)
  assert.deepEqual(page.previewFaces.value, start)
})

test('all previews animate with live board transforms without selection, and choosing a style preserves their cycle', t => {
  t.mock.timers.enable({ apis: ['setTimeout'] })
  const { page, hooks, stored } = setup()
  hooks.ready()
  assert.equal(stored().boardTransition, undefined, 'Autoplay does not write an animation preference')
  for (const [elapsed, position, duration] of [[0, 0, 0], [300, 1, 1050]]) {
    t.mock.timers.tick(elapsed)
    for (const style of ['cube', 'slide', 'fade']) for (const face of [0, 1]) {
      assert.equal(page.previewFaces.value[style][face].style, boardFaceStyle(style, face, position, duration, true))
      assert.equal(page.previewFaces.value[style][face].shade,
        `opacity:${style === 'cube' ? Math.abs(face - position) * 0.18 : 0};transition-duration:${duration}ms;`)
    }
  }
  const end = page.previewFaces.value
  for (const id of ['slide', 'fade', 'cube']) {
    page.selectTransition({ currentTarget: { dataset: { id } } })
    assert.equal(page.boardTransition.value, id)
    assert.equal(stored().boardTransition ?? 'cube', id)
    assert.deepEqual(page.previewFaces.value, end, 'Choosing an animation must not restart the demonstrations')
  }
  t.mock.timers.tick(2699)
  assert.deepEqual(page.previewFaces.value, end)
  t.mock.timers.tick(1)
  for (const style of ['cube', 'slide', 'fade']) for (const face of [0, 1]) {
    assert.equal(page.previewFaces.value[style][face].style, boardFaceStyle(style, face, 0, 0, true))
  }
  hooks.unload()
})

test('settings immediately persists independent category selections, protects the last board and resets all', () => {
  const h = setup({ category: 'general', face: 2, theme: 'dark', language: 'zh-TW', grouping: 'company' })
  for (const category of categories) {
    if (category.defaultKinds && !category.defaultKinds.includes(category.kinds.at(-1))) h.toggle(category.id, category.kinds.at(-1))
    for (const kind of category.kinds.slice(0, -1)) h.toggle(category.id, kind)
    const group = h.page.groups.value.find(group => group.id === category.id)
    assert.equal(group.boards.filter(board => board.selected).length, 1)
    assert.equal(group.boards.at(-1).disabled, true)
    h.toggle(category.id, category.kinds.at(-1))
    assert.deepEqual(h.stored().boardSelections[category.id], category.kinds.length === 1 ? undefined : [category.kinds.at(-1)])
  }
  assert.equal(h.stored().face, 0)
  assert.equal(h.stored().theme, 'dark')
  assert.equal(h.stored().language, 'zh-TW')
  assert.equal(h.stored().grouping, 'company')
  assert.equal(h.page.dark, true)
  assert.equal(h.colors.at(-1).frontColor, '#ffffff')
  const before = h.stored()
  h.toggle('invalid', 'epochECI'); h.toggle('general', 'retired')
  assert.equal(h.stored(), before)
  h.page.reset()
  assert.equal(h.stored().boardSelections, undefined)
  assert.equal(h.stored().face, 2, 'Reset restores the selected board at its catalog position')
  assert.ok(h.page.groups.value.every(group => {
    const category = categories.find(item => item.id === group.id)
    const defaults = category.defaultKinds || category.kinds
    return group.boards.every(board => board.selected === defaults.includes(board.kind) && board.disabled === (defaults.length === 1 && board.selected))
  }))
})

test('settings supports both back navigation and a directly opened page', () => {
  const h = setup()
  assert.equal(h.colors.at(-1).frontColor, '#000000')
  h.page.back(); assert.equal(h.backs(), 1)
  globalThis.getCurrentPages = () => [1]
  h.page.back(); assert.equal(h.launched(), '/pages/leaderboard/index')
  const template = readFileSync(new URL('../src/pages/settings/index.wxml', import.meta.url), 'utf8')
  assert.match(template, /disabled="\{\{item.disabled\}\}"/)
  assert.match(template, /bindtap="reset"/)
  assert.match(template, /aria-checked="\{\{item.selected\}\}"/)
})

test('motion cards default to cube, persist immediately and stay independent of board visibility and its reset', () => {
  const h = setup({ category: 'general', face: 2, language: 'en', grouping: 'company', theme: 'dark' })
  assert.equal(h.page.boardTransition.value, 'cube')
  assert.deepEqual(h.page.transitionOptions.map(option => option.id), ['cube', 'slide', 'fade'])
  assert.ok(h.page.transitionOptions.every(option => option.title && option.hint))
  for (const style of ['slide', 'fade', 'cube']) {
    h.page.selectTransition({ currentTarget: { dataset: { id: style } } })
    assert.equal(h.page.boardTransition.value, style)
    assert.equal(h.stored().boardTransition ?? 'cube', style)
    assert.equal(h.stored().face, 2)
    assert.equal(h.stored().grouping, 'company')
    assert.equal(h.stored().theme, 'dark')
  }
  h.page.selectTransition({ currentTarget: { dataset: { id: 'fade' } } })
  h.toggle('general', 'artificialAnalysis')
  assert.equal(h.stored().boardTransition, 'fade')
  h.page.reset()
  assert.equal(h.stored().boardTransition, 'fade', 'The board visibility reset only resets visibility')
  const saved = h.stored()
  h.page.selectTransition({ currentTarget: { dataset: { id: 'invalid' } } })
  assert.equal(h.stored(), saved)
  for (const style of ['cube', 'slide', 'fade']) assert.equal(setup({ boardTransition: style }).page.boardTransition.value, style)
  assert.equal(setup({ boardTransition: 'retired' }).page.boardTransition.value, 'cube')
})
