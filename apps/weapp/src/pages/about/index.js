import { computed, definePage, ref, onShareAppMessage } from '@vue-mini/core'
import { leaderboardSources, desktopDownloadURL, copy, text } from '../../core/catalog.js'
import { createBrandMeasurer } from '../../core/brand-title.js'
import { pagePreferences, sharePath } from '../../core/share-state.js'
import { epochAttribution } from '../../core/epoch-attribution.js'
import { arenaAttribution } from '../../core/arena-attribution.js'
import { ccByLicense } from '../../core/cc-by-4.0.js'
import { investmentContent } from '../../core/investment.js'

definePage(query => {
  const saved = (() => { try { return wx.getStorageSync('benchgauge.preferences') || {} } catch { return {} } })()
  const preferences = pagePreferences(query, saved, wx.getAppBaseInfo?.().language)
  const language = preferences.language
  const labels = Object.fromEntries(Object.keys(copy).map(key => [key, text(copy[key], language)]))
  const dark = preferences.theme === 'dark' || (preferences.theme === 'system'
    && (preferences.appearance || wx.getAppBaseInfo?.().theme) === 'dark')
  if (preferences.fromShare) {
    try { wx.setStorageSync('benchgauge.preferences', preferences) } catch { /* Sharing does not require local storage. */ }
  }
  onShareAppMessage(() => ({ title: `${labels.about}｜${labels.rankingSummary}`,
    path: sharePath(preferences, dark ? 'dark' : 'light', '/pages/about/index') }))
  const statusBar = wx.getWindowInfo().statusBarHeight || 24
  const brandTitle = createBrandMeasurer(wx)(labels.name, (wx.getWindowInfo().windowWidth || 375) / 750 * 48)
  const notice = ref('')
  const investment = investmentContent(__ENGINEERING_INVESTMENT__, language)
  const collapsedCostGroups = ref(Object.fromEntries(investment.groups.map(group => [group.id, true])))
  const costGroups = computed(() => investment.groups.map(group => {
    const collapsed = Boolean(collapsedCostGroups.value[group.id])
    const action = collapsed ? ['Expand', '展开', '展開'] : ['Collapse', '收起', '收起']
    return { ...group, collapsed, toggleLabel: `${text(action, language)} ${group.title}` }
  }))
  const toggleCostGroup = event => {
    const id = event.currentTarget.dataset.id
    if (!investment.groups.some(group => group.id === id)) return
    collapsedCostGroups.value = { ...collapsedCostGroups.value, [id]: !collapsedCostGroups.value[id] }
  }
  const notices = __THIRD_PARTY_NOTICES__.map(item => ({ ...item,
    title: item.name || text([`Third-party notice ${item.number}`, `第三方软件声明 ${item.number}`, `第三方軟體聲明 ${item.number}`], language) }))
  const attributions = { arena: arenaAttribution(language), epoch: epochAttribution(language) }
  const licenseText = ccByLicense(language).text
  const items = leaderboardSources.map(item => ({ ...item,
    domain: item.url.split('/')[2], mark: { artificialAnalysis: 'AA', arena: 'A', epoch: 'E' }[item.id],
    license: Boolean(attributions[item.id]) }))
  const licenseNotice = ref({ open: false, text: '' })
  const openLicense = event => {
    if (!attributions[event.currentTarget.dataset.id]) return
    licenseNotice.value = { open: true, text: licenseText }
  }
  const closeLicense = () => { licenseNotice.value = { ...licenseNotice.value, open: false } }
  const back = () => {
    if (!preferences.fromShare && getCurrentPages().length > 1) wx.navigateBack()
    else wx.reLaunch({ url: sharePath(preferences, dark ? 'dark' : 'light') })
  }
  const copyLink = event => wx.setClipboardData({ data: event.currentTarget.dataset.url,
    success: () => wx.showToast({ title: labels.copied, icon: 'success' }) })
  const toggleNotice = event => {
    const id = event.currentTarget.dataset.id
    if (notices.some(item => item.id === id)) notice.value = notice.value === id ? '' : id
  }
  return { labels, brandTitle, dark, statusBar, items, version: __APP_VERSION__,
    back, copyLink, notices, notice, toggleNotice, desktopDownloadURL, investment, costGroups, toggleCostGroup,
    licenseNotice, openLicense, closeLicense,
    viewLicenseLabel: text(['View license', '查看协议', '查看協議'], language),
    description: labels.description,
    descriptionLines: labels.description.match(/[^。.]+[。.]?/g).map(line => line.trim()),
    desktopTitle: text(['Quota lookup', '余量查询', '餘量查詢'], language),
    desktopDownloadLabel: text(['PC', 'PC 端', 'PC 端'], language),
    contributeLabel: text(['Contribute code', '贡献代码', '貢獻程式碼'], language),
    sourcesTitle: text(['Data sources', '数据来源', '資料來源'], language),
    noticesIntro: text(['Third-party software and data follow their original licenses. Tap to read the full copyright and license text.',
      '第三方软件及数据分别遵循其原始许可证。点按查看完整版权与许可文本。', '第三方軟體及資料分別遵循其原始授權條款。點按查看完整版權與授權文字。'], language),
    noticesTitle: text(['Third-party licenses', '第三方许可', '第三方授權'], language),
  }
}, { canShareToOthers: true })
