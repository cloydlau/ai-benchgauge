import assert from 'node:assert/strict'
import test from 'node:test'
import { boards, categories, languages } from '../src/core/catalog.js'
import { normalizePreferences, pagePreferences, readSharedPreferences, sharePath } from '../src/core/share-state.js'

const queryFor = path => Object.fromEntries(new URL('https://shared.example' + path).searchParams)
test('every category, grouping, source, language and appearance survives sharing', () => {
  const filters = Object.fromEntries(Object.keys(boards).map((kind, index) => [kind, {
    country: index % 2 ? 'unknown' : 'SG', openness: ['all', 'open', 'closed', 'unknown'][index % 4],
  }]))
  for (const category of categories.map(item => item.id)) for (const grouping of ['model', 'company']) {
    for (const face of categories.find(item => item.id === category).kinds.map((_, index) => index)) for (const language of languages) for (const theme of ['light', 'dark', 'system']) {
      const original = { category, grouping, face, language, theme, filters }
      const path = sharePath(original, 'dark')
      const expected = normalizePreferences({ ...original, appearance: 'dark' })
      assert.deepEqual(readSharedPreferences(queryFor(path)), expected)
      const encoded = path.split('?state=')[1]
      assert.deepEqual(readSharedPreferences({ state: encoded }), expected)
      assert.ok(path.length < 1024)
    }
  }
})
test('sharing unfiltered defaults clears every receiver filter instead of inheriting local choices', () => {
  const incoming = queryFor(sharePath({ category: 'general', grouping: 'model', face: 0, language: 'zh-CN', theme: 'light' }, 'light'))
  const saved = { category: 'video', grouping: 'company', face: 1, language: 'en', theme: 'dark',
    filters: Object.fromEntries(Object.keys(boards).map(kind => [kind, { country: 'CN', openness: 'closed' }])) }
  const restored = pagePreferences(incoming, saved)
  assert.deepEqual(restored.filters, {})
  assert.equal(restored.face, 0)
  assert.equal(restored.grouping, 'model')
  assert.equal(restored.theme, 'light')
  assert.equal(restored.fromShare, true)
  assert.equal(Object.keys(saved.filters).length, 9)
})
test('malformed and future-version links fall back safely, and legacy links remain supported', () => {
  const saved = { category: 'image', face: 1, language: 'en', theme: 'dark' }
  const good = JSON.parse(decodeURIComponent(sharePath(saved, 'dark').split('?state=')[1]))
  for (const state of [null, '', '%broken', '{}', 'null', '[]', 'x'.repeat(4097),
    ...[{ v: 2 }, { f: 2 }, { l: 'invalid' }, { t: 'invalid' }, { c: 'invalid' }, { g: 'invalid' }, { a: 'invalid' }, { x: [] }]
      .map(change => JSON.stringify({ ...good, ...change }))]) {
    assert.equal(readSharedPreferences({ state }), null)
    assert.equal(pagePreferences({ state }, saved).category, 'image')
  }
  assert.equal(pagePreferences({ category: 'coding', face: '0' }, saved).face, 0)
  assert.equal(pagePreferences({ category: 'coding', face: '0' }, saved).category, 'coding')
  assert.equal(pagePreferences({ language: 'zh-TW', theme: 'light' }, saved).language, 'zh-TW')
  assert.equal(pagePreferences({}, saved).face, 1)
})
test('only valid board filters are restored and arbitrary JSON fields cannot enter preferences', () => {
  const original = { category: 'general', theme: 'system', face: 0, language: 'en', filters: {
    artificialAnalysis: { country: 'JP', openness: 'open', unrelated: 'ignored' },
    arenaText: { country: '<script>', openness: 'invalid' },
    unknownBoard: { country: 'CN', openness: 'closed' },
  }, token: 'must not be shared' }
  const path = sharePath(original, 'light')
  assert.ok(!path.includes('token'))
  const expected = Object.fromEntries(Object.keys(boards).map(kind => [kind, { country: 'JP', openness: 'open' }]))
  assert.deepEqual(readSharedPreferences(queryFor(path)).filters, expected)
  const crafted = JSON.parse(decodeURIComponent(path.split('?state=')[1]))
  crafted.x.arenaText = ['unknown', 'closed']
  crafted.x.arenaTextToVideo = 'invalid'
  crafted.x.unknownBoard = ['CN', 'open']
  assert.deepEqual(readSharedPreferences({ state: JSON.stringify(crafted) }).filters, expected)
})

test('legacy per-board filters migrate from the visible source and remain shared in saved and forwarded preferences', () => {
  const filters = { artificialAnalysis: { country: 'US', openness: 'closed' }, arenaText: { country: 'CN', openness: 'open' } }
  for (const face of [0, 1]) {
    const expected = filters[face ? 'arenaText' : 'artificialAnalysis']
    const saved = normalizePreferences({ category: 'general', face, filters })
    assert.deepEqual(saved.filters, Object.fromEntries(Object.keys(boards).map(kind => [kind, expected])))
    assert.deepEqual(readSharedPreferences(queryFor(sharePath(saved, 'light'))).filters, saved.filters)
    assert.deepEqual(pagePreferences({ face: String(face) }, { face: 1 - face, filters }).filters, saved.filters)
  }
  assert.deepEqual(normalizePreferences({ face: 1, filters: { artificialAnalysis: filters.artificialAnalysis } }).filters, {})
})

test('system language follows supported locales until an explicit local choice overrides it', () => {
  for (const [locale, expected] of [['en_US', 'en'], ['en-GB', 'en'], ['zh_CN', 'zh-CN'],
    ['zh-Hans-SG', 'zh-CN'], ['zh_TW', 'zh-TW'], ['zh-Hant-HK', 'zh-TW'], ['zh_HK', 'zh-TW'], ['fr_FR', 'en']]) {
    const first = pagePreferences({}, {}, locale)
    assert.equal(first.language, expected); assert.equal(first.languageMode, 'system')
    const saved = { ...first, category: 'video', grouping: 'company', face: 1 }
    assert.equal(pagePreferences({}, saved, 'zh_TW').language, 'zh-TW')
    assert.equal(pagePreferences({}, saved, 'zh_TW').category, 'video')
    assert.equal(pagePreferences({}, { ...saved, language: 'en', languageMode: 'manual' }, 'zh_CN').language, 'en')
  }
  assert.equal(pagePreferences({}, { language: 'en' }, 'zh_CN').language, 'en')
  assert.equal(pagePreferences({ language: 'zh-TW' }, {}, 'en_US').languageMode, 'manual')
})
test('saved and incoming shared Hong Kong, Macao and Taiwan filters migrate to China', () => {
  for (const code of ['HK', 'MO', 'TW']) {
    const saved = { category: 'general', face: 0, filters: { artificialAnalysis: { country: code, openness: 'open' } } }
    assert.equal(normalizePreferences(saved).filters.artificialAnalysis.country, 'CN')
    assert.equal(pagePreferences({}, saved).filters.artificialAnalysis.country, 'CN')
    const path = sharePath(saved, 'light')
    const state = JSON.parse(decodeURIComponent(path.split('?state=')[1]))
    assert.ok(Object.values(state.x).every(pair => pair[0] === 'CN'))
    state.x.artificialAnalysis[0] = code
    assert.equal(readSharedPreferences({ state: JSON.stringify(state) }).filters.artificialAnalysis.country, 'CN')
  }
})
