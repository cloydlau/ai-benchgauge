import assert from 'node:assert/strict'
import test from 'node:test'
import { registerHooks } from 'node:module'
import { pagePreferences, sharePath } from '../src/core/share-state.js'
import { leaderboardSources, copy, text } from '../src/core/catalog.js'
import { arenaAttribution } from '../src/core/arena-attribution.js'
import { epochAttribution } from '../src/core/epoch-attribution.js'
import { ccByLicense } from '../src/core/cc-by-4.0.js'
import { sourceAgreement } from '../src/core/source-agreement.js'
import { readCachedBoard } from '../src/services/boards.js'
import { readFileSync } from 'node:fs'

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
        export const onReady = fn => { globalThis.aboutReady = fn }
        export const onResize = fn => { globalThis.aboutResize = fn }
        export const onUnload = fn => { globalThis.aboutUnload = fn }
      `,
    }
  },
})
await import('../src/pages/about/index.js')
registration.deregister()
globalThis.__CONTRIBUTOR_CIRCLES__ = { nodes: [] }
const queryFor = path => Object.fromEntries(new URL('https://shared.example' + path).searchParams)

test('contributor cloud sits beside engineering counters, expands and selects without writing the clipboard', () => {
  globalThis.__APP_VERSION__ = '0.0.0'; globalThis.__THIRD_PARTY_NOTICES__ = []
  globalThis.__ENGINEERING_INVESTMENT__ = { commitCount: 3, codeLineCount: 100 }
  globalThis.__CONTRIBUTOR_CIRCLES__ = { nodes: [{ id: 'owner', name: 'Cloyd Lau', count: 2,
    avatar: '', initial: 'C', monochrome: false, url: 'https://github.com/owner/repo/commit/abc', x: 0.5, y: 0.5, r: 0.2 }] }
  const copies = []
  globalThis.wx = {
    getStorageSync: () => ({ language: 'zh-CN' }), getWindowInfo: () => ({ statusBarHeight: 24 }),
    getAppBaseInfo: () => ({ theme: 'light' }), setClipboardData: ({ data }) => copies.push(data),
  }
  try {
    const about = globalThis.aboutFactory({})
    assert.equal(about.contributors.nodes[0].initial, 'C')
    assert.equal(about.contributorsExpanded.value, false)
    assert.equal(about.selectedContributor.value, null)
    about.openContributors()
    assert.equal(about.contributorsExpanded.value, true)
    about.selectContributor({ currentTarget: { dataset: { id: 'owner' } } })
    assert.equal(about.selectedContributor.value.name, 'Cloyd Lau')
    assert.equal(about.selectedContributor.value.countLabel, '2 次提交')
    about.selectContributor({ currentTarget: { dataset: { id: 'missing' } } })
    assert.equal(about.selectedContributorID.value, 'owner')
    about.closeContributors()
    assert.equal(about.contributorsExpanded.value, false)
    assert.deepEqual(copies, [])
    const template = readFileSync(new URL('../src/pages/about/index.wxml', import.meta.url), 'utf8')
    const engineering = template.slice(template.indexOf('class="investment-engineering'), template.indexOf('{{investment.note}}'))
    assert.ok(engineering.indexOf('class="contributor-mini"') > engineering.indexOf('class="investment-metrics"'))
    assert.ok(!template.includes('contributors-card'))
    assert.match(template, /bind:close="closeContributors"/)
    assert.doesNotMatch(template, /class="contributor-link"|selectedContributor\.url/)
  } finally { globalThis.__CONTRIBUTOR_CIRCLES__ = { nodes: [] } }
})

test('About artwork title fits measured space and recovers on resize without accepting stale measurements', () => {
  globalThis.__APP_VERSION__ = '0.0.0'; globalThis.__THIRD_PARTY_NOTICES__ = []
  globalThis.__ENGINEERING_INVESTMENT__ = { commitCount: 0, codeLineCount: 0 }
  const ticks = [], measurements = [], selectors = []
  globalThis.wx = {
    getStorageSync: () => ({ language: 'en' }), getWindowInfo: () => ({ statusBarHeight: 24 }),
    getAppBaseInfo: () => ({ theme: 'light' }), nextTick: callback => ticks.push(callback),
    createSelectorQuery: () => {
      const query = {
        select: selector => { selectors.push(selector); return query },
        boundingClientRect: () => query,
        exec: callback => measurements.push(callback),
      }
      return query
    },
  }
  const about = globalThis.aboutFactory({})
  globalThis.aboutResize()
  assert.equal(ticks.length, 0, 'Wait for the initial page layout')
  globalThis.aboutReady(); ticks.shift()()
  assert.deepEqual(selectors, ['.artwork-heading', '.artwork-title-measure'])
  measurements.shift()([{ width: 150 }, { width: 200 }])
  assert.equal(about.artworkTitleScale.value, 0.75)
  globalThis.aboutResize(); ticks.shift()()
  measurements.shift()([{ width: 300 }, { width: 200 }])
  assert.equal(about.artworkTitleScale.value, 1, 'Restore natural size without enlarging above it')
  globalThis.aboutResize(); ticks.shift()()
  const stale = measurements.shift()
  globalThis.aboutResize(); ticks.shift()()
  measurements.shift()([{ width: 160 }, { width: 200 }])
  stale([{ width: 20 }, { width: 200 }])
  assert.equal(about.artworkTitleScale.value, 0.8, 'An older resize must not overwrite the latest size')
  globalThis.aboutResize(); ticks.shift()()
  const afterUnload = measurements.shift()
  globalThis.aboutUnload()
  afterUnload([{ width: 20 }, { width: 200 }])
  globalThis.aboutResize()
  assert.equal(ticks.length, 0)
  assert.equal(about.artworkTitleScale.value, 0.8)
})

test('About allows rotation with native artwork preview and restores chrome when returning to portrait', () => {
  const config = JSON.parse(readFileSync(new URL('../src/pages/about/index.json', import.meta.url), 'utf8'))
  assert.equal(config.pageOrientation, 'auto')
  globalThis.__APP_VERSION__ = '0.0.0'; globalThis.__THIRD_PARTY_NOTICES__ = []
  globalThis.__ENGINEERING_INVESTMENT__ = { commitCount: 0, codeLineCount: 0 }
  for (const language of ['en', 'zh-CN', 'zh-TW']) {
    let window = { statusBarHeight: 47, windowWidth: 375 }
    const previews = []
    globalThis.wx = {
      getStorageSync: () => ({ language }), getWindowInfo: () => window,
      getAppBaseInfo: () => ({ theme: 'light' }), previewImage: options => previews.push(options),
    }
    const about = globalThis.aboutFactory({})
    const portraitTitle = about.brandTitle.value
    about.previewArtwork()
    assert.deepEqual(previews, [{ current: about.artwork.image, urls: [about.artwork.image] }])
    window = { statusBarHeight: 0, windowWidth: 812 }
    globalThis.aboutResize()
    assert.equal(about.statusBar.value, 0, 'Landscape can legitimately have no status bar')
    assert.notDeepEqual(about.brandTitle.value, portraitTitle)
    window = { statusBarHeight: 47, windowWidth: 375 }
    globalThis.aboutResize()
    assert.equal(about.statusBar.value, 47)
    assert.deepEqual(about.brandTitle.value, portraitTitle)
  }
})

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
  assert.equal(about.repositoryURL, 'https://github.com/cloydlau/ai-benchgauge')
  assert.equal(about.desktopDownloadURL, about.repositoryURL + '/releases/latest')
  assert.equal(about.items, undefined)
  assert.equal(about.openLicense, undefined)
  const template = readFileSync(new URL('../src/pages/about/index.wxml', import.meta.url), 'utf8')
  assert.ok(!template.includes('sources-section'))
  assert.ok(!template.includes('licenseNotice'))
  assert.equal(sourceAgreement('unknown'), '')
  assert.equal(sourceAgreement('artificialAnalysis'), '')
  assert.equal(sourceAgreement('arenaText'), '', 'Legacy Arena data must not inherit the dataset license')
  const arena = { kind: 'arenaText', sourceNote: arenaAttribution('en').sourceURL }
  for (const [kind, board, credit] of [['epochECI', null, epochAttribution('en')], ['arenaText', arena, arenaAttribution('en')]]) {
    const agreement = sourceAgreement(kind, board, 'en')
    assert.equal(agreement, `${credit.fullText}\n\n${ccByLicense('en').text}`)
    assert.notEqual(agreement, credit.fullText)
  }
  assert.ok(sourceAgreement('openRouterUsage').includes('Source: OpenRouter (openrouter.ai/rankings).'))
  assert.ok(sourceAgreement('openRouterUsage').endsWith(ccByLicense('en').text))
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

test('OpenRouter agreement reads current offline attribution on demand with localized full license', () => {
  globalThis.__APP_VERSION__ = '0.0.0'; globalThis.__THIRD_PARTY_NOTICES__ = []
  globalThis.__ENGINEERING_INVESTMENT__ = { commitCount: 1234, codeLineCount: 56789 }
  const note = 'Source: OpenRouter (openrouter.ai/rankings), as of 2026-10-23T06:00:00Z.\nLicensed under CC BY 4.0.\nUTC 2026-10-22\nSnapshot meta: {"version":"v1"}'
  let cachedNote = note
  for (const language of ['en', 'zh-CN', 'zh-TW']) {
    globalThis.wx = {
      getStorageSync: key => key === 'benchgauge.preferences' ? { language } : {},
      env: { USER_DATA_PATH: '/offline' },
      getFileSystemManager: () => ({ readFileSync: () => JSON.stringify({ openRouterUsage: {
        kind: 'openRouterUsage', title: 'OpenRouter', fetchedAt: '2026-10-23T06:00:00Z', sourceNote: cachedNote,
        entries: [{ rank: 1, name: 'vendor/model', score: 123, totalTokens: '123000000000' }],
      } }) }),
      getWindowInfo: () => ({ statusBarHeight: 24 }),
      getAppBaseInfo: () => ({ theme: 'light' }),
      request: () => assert.fail('Opening an agreement must work offline'),
    }
    const agreement = () => sourceAgreement('openRouterUsage', readCachedBoard(wx, 'openRouterUsage'), language)
    cachedNote = note
    assert.equal(agreement(), `${note}\n\n${ccByLicense(language).text}`)
    cachedNote = note.replace('06:00:00Z', '07:00:00Z')
    assert.ok(agreement().startsWith(cachedNote))
  }
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

test('About lists seven icon rows with a single contribution footer and no platform links', () => {
  const template = readFileSync(new URL('../src/pages/about/index.wxml', import.meta.url), 'utf8')
  const hero = template.slice(template.indexOf('<view class="about-hero">'), template.indexOf('<view class="about-card platforms-card">'))
  const module = template.slice(template.indexOf('<view class="about-card platforms-card">'), template.indexOf('<view class="about-card investment-card">'))
  assert.ok(!template.includes('quota-card'))
  assert.ok(!hero.includes('contribute-link'))
  assert.match(module, /wx:for="\{\{platforms.items\}\}"/)
  assert.match(module, /class="platform-icon platform-icon-\{\{item.id\}\}"/)
  assert.equal((module.match(/class="platform-contribute"/g) || []).length, 1)
  assert.ok(module.indexOf('class="platform-contribute"') > module.indexOf('wx:for="{{platforms.items}}"'))
  assert.ok(!module.includes('item.url'))
  assert.ok(!module.includes('platform-download'))
  assert.ok(!module.includes('platform-pr'))
  const expected = [
    ['weapp', 'live', 1], ['ios', 'development', 1], ['ipad', 'development', 1],
    ['android', 'unavailable', 0], ['harmony', 'unavailable', 0],
    ['macos', 'live', 2], ['windows', 'development', 2],
  ]
  for (const language of ['en', 'zh-CN', 'zh-TW']) {
    const copies = []
    globalThis.wx = {
      getStorageSync: () => ({ language }), getWindowInfo: () => ({ statusBarHeight: 24 }),
      getAppBaseInfo: () => ({ theme: 'light' }),
      setClipboardData: ({ data }) => copies.push(data),
    }
    const about = globalThis.aboutFactory({})
    assert.deepEqual(about.platforms.items.map(item => [item.id, item.status, item.features.length]), expected)
    assert.equal(about.platforms.contributeLabel, { en: 'PR welcome', 'zh-CN': '欢迎贡献代码', 'zh-TW': '歡迎貢獻程式碼' }[language])
    assert.equal(about.platforms.items.find(item => item.id === 'ios').note, language === 'en' ? '(incl. iPhone Duo)' : '（含 iPhone Duo）')
    for (const platform of about.platforms.items) {
      assert.ok(platform.name && platform.statusLabel)
      assert.equal(platform.featureText, platform.features.join(' · '))
      assert.equal(platform.url, undefined)
      assert.equal(platform.prWelcome, undefined)
    }
    assert.equal(about.platforms.repositoryURL, about.repositoryURL)
    about.copyLink({ currentTarget: { dataset: { url: about.platforms.repositoryURL } } })
    assert.deepEqual(copies, [about.repositoryURL])
    if (language === 'zh-CN') {
      assert.deepEqual(about.platforms.items.map(item => [item.name, item.statusLabel, item.featureText]), [
        ['微信小程序', '已上线', '榜单'], ['iOS', '开发中', '榜单'], ['iPadOS', '开发中', '榜单'],
        ['安卓', '暂无', ''], ['鸿蒙', '暂无', ''], ['macOS', '已上线', '榜单 · 余量'], ['Windows', '开发中', '榜单 · 余量'],
      ])
    }
  }
})

test('Vercel agreement opens the current cached credit offline and never borrows OpenRouter attribution', () => {
  globalThis.__APP_VERSION__ = '0.0.0'; globalThis.__THIRD_PARTY_NOTICES__ = []
  globalThis.__ENGINEERING_INVESTMENT__ = { commitCount: 0, codeLineCount: 0 }
  for (const language of ['en', 'zh-CN', 'zh-TW']) {
    let note = '© 2026 Vercel · UTC 2026-10-22 · transformed shares'
    globalThis.wx = {
      getStorageSync: key => key === 'benchgauge.preferences' ? { language } : {},
      env: { USER_DATA_PATH: '/offline' },
      getFileSystemManager: () => ({ readFileSync: () => JSON.stringify({
        openRouterUsage: { kind: 'openRouterUsage', fetchedAt: '2026-10-23T06:00:00Z', sourceNote: 'Wrong source credit', entries: [{ rank: 1, name: 'OR model', score: 9 }] },
        vercelUsage: { kind: 'vercelUsage', fetchedAt: '2026-10-23T06:00:00Z', sourceNote: note, entries: [{ rank: 1, name: 'Vercel model', score: 16.3389 }] },
      }) }),
      getWindowInfo: () => ({ statusBarHeight: 24 }), getAppBaseInfo: () => ({ theme: 'light' }),
      request: () => assert.fail('License opens offline'),
    }
    const agreement = () => sourceAgreement('vercelUsage', readCachedBoard(wx, 'vercelUsage'), language)
    assert.equal(agreement(), `${note}\n\n${ccByLicense(language).text}`)
    note = 'Updated Vercel credit'
    assert.ok(agreement().startsWith(note)); assert.ok(!agreement().includes('Wrong source credit'))
    note = ''; assert.ok(agreement().includes('© 2026 Vercel'))
  }
})


test('Tencent keeps its source link without an invented license or separate notice entry', () => {
  globalThis.__APP_VERSION__ = '0.0.0'; globalThis.__THIRD_PARTY_NOTICES__ = []
  globalThis.__ENGINEERING_INVESTMENT__ = { commitCount: 0, codeLineCount: 0 }
  for (const language of ['en', 'zh-CN', 'zh-TW']) {
    globalThis.wx = {
      getStorageSync: key => key === 'benchgauge.preferences' ? { language } : {},
      env: { USER_DATA_PATH: '/offline' },
      getFileSystemManager: () => ({ readFileSync: () => JSON.stringify({
        cloudbaseUsage: { kind: 'cloudbaseUsage', fetchedAt: '2026-10-23T06:00:00Z', sourceNote: 'Tencent sampled period', entries: [{ rank: 1, name: 'Kimi K3', score: 1.1 }] },
        vercelUsage: { kind: 'vercelUsage', fetchedAt: '2026-10-23T06:00:00Z', sourceNote: 'Other platform credit', entries: [{ rank: 1, name: 'Vercel', score: 20 }] },
      }) }),
      getWindowInfo: () => ({ statusBarHeight: 24 }), getAppBaseInfo: () => ({ theme: 'light' }),
      request: () => assert.fail('Source metadata must remain offline'),
    }
    const source = leaderboardSources.find(item => item.id === 'cloudbase')
    assert.equal(source.title, 'Tencent Cloud')
    assert.equal(source.url, 'https://docs.cloudbase.net/ai/announcement/model-token-volume')
    const notice = sourceAgreement('cloudbaseUsage', readCachedBoard(wx, 'cloudbaseUsage'), language)
    assert.ok(notice.includes('Tencent sampled period'))
    assert.ok(!notice.includes(ccByLicense(language).text))
    assert.ok(!notice.includes('creativecommons.org/licenses/'))
    const vercel = sourceAgreement('vercelUsage', readCachedBoard(wx, 'vercelUsage'), language)
    assert.ok(vercel.includes('Other platform credit'))
    assert.ok(!vercel.includes('Tencent sampled period'))
    const about = globalThis.aboutFactory({})
    assert.equal(about.openLicense, undefined)
  }
})
