import assert from 'node:assert/strict'
import test from 'node:test'
import { registerHooks } from 'node:module'
import { readFileSync } from 'node:fs'
import { categories } from '../src/core/catalog.js'

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
  const page = globalThis.__settingsFactory({})
  const toggle = (category, kind) => page.toggleBoard({ currentTarget: { dataset: { category, kind } } })
  return { page, toggle, colors, stored: () => stored, backs: () => backs, launched: () => launched }
}

test('settings immediately persists independent category selections, protects the last board and resets all', () => {
  const h = setup({ category: 'general', face: 2, theme: 'dark', language: 'zh-TW', grouping: 'company' })
  for (const category of categories) {
    for (const kind of category.kinds.slice(0, -1)) h.toggle(category.id, kind)
    const group = h.page.groups.value.find(group => group.id === category.id)
    assert.equal(group.boards.filter(board => board.selected).length, 1)
    assert.equal(group.boards.at(-1).disabled, true)
    h.toggle(category.id, category.kinds.at(-1))
    assert.deepEqual(h.stored().boardSelections[category.id], [category.kinds.at(-1)])
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
  assert.ok(h.page.groups.value.every(group => group.boards.every(board => board.selected && !board.disabled)))
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
