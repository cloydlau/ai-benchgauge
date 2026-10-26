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

test('About lists the requested seven platforms and moves contribution into their module', () => {
  const template = readFileSync(new URL('../src/pages/about/index.wxml', import.meta.url), 'utf8')
  const hero = template.slice(template.indexOf('<view class="about-hero">'), template.indexOf('<view class="about-card platforms-card">'))
  const module = template.slice(template.indexOf('<view class="about-card platforms-card">'), template.indexOf('<view class="about-card investment-card">'))
  assert.ok(!template.includes('quota-card'))
  assert.ok(!hero.includes('contribute-link'))
  assert.match(module, /wx:for="\{\{platforms.items\}\}"/)
  assert.match(module, /wx:if="\{\{item.prWelcome\}\}"/)
  assert.match(module, /class="contribute-link platform-contribute"/)
  const expected = [
    ['weapp', 'live', 1, false], ['ios', 'development', 1, true], ['ipad', 'development', 1, true],
    ['android', 'unavailable', 0, true], ['harmony', 'unavailable', 0, true],
    ['macos', 'live', 2, false], ['windows', 'development', 2, true],
  ]
  for (const language of ['en', 'zh-CN', 'zh-TW']) {
    const copies = []
    globalThis.wx = {
      getStorageSync: () => ({ language }), getWindowInfo: () => ({ statusBarHeight: 24 }),
      getAppBaseInfo: () => ({ theme: 'light' }),
      setClipboardData: ({ data }) => copies.push(data),
    }
    const about = globalThis.aboutFactory({})
    assert.deepEqual(about.platforms.items.map(item => [item.id, item.status, item.features.length, item.prWelcome]), expected)
    assert.equal(about.platforms.prWelcomeLabel, 'PR welcome')
    for (const platform of about.platforms.items) {
      assert.ok(platform.name && platform.statusLabel)
      assert.equal(platform.featureText, platform.features.join(' · '))
      if (platform.prWelcome) assert.equal(platform.url, about.repositoryURL)
      if (platform.id === 'macos') assert.equal(platform.url, about.desktopDownloadURL)
      if (platform.id === 'weapp') assert.equal(platform.url, null)
      if (platform.url) {
        about.copyLink({ currentTarget: { dataset: { url: platform.url } } })
        assert.equal(copies.at(-1), platform.url)
      }
    }
    about.copyLink({ currentTarget: { dataset: { url: about.platforms.repositoryURL } } })
    assert.equal(copies.at(-1), about.repositoryURL)
    assert.equal(copies.length, 7)
    if (language === 'zh-CN') {
      assert.deepEqual(about.platforms.items.map(item => [item.name, item.statusLabel, item.featureText]), [
        ['微信小程序', '已上线', '榜单'], ['iOS', '开发中', '榜单'], ['iPad', '开发中', '榜单'],
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
