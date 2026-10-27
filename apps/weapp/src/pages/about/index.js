import { computed, definePage, ref, onShareAppMessage } from '@vue-mini/core'
import { desktopDownloadURL, repositoryURL, copy, text } from '../../core/catalog.js'
import { createBrandMeasurer } from '../../core/brand-title.js'
import { pagePreferences, sharePath } from '../../core/share-state.js'
import { investmentContent } from '../../core/investment.js'
import { aboutPlatforms } from '../../core/about-platforms.js'
import { aboutArtwork } from '../../core/about-artwork.js'

definePage(query => {
  const saved = (() => { try { return wx.getStorageSync('benchgauge.preferences') || {} } catch { return {} } })()
  const preferences = pagePreferences(query, saved, wx.getAppBaseInfo?.().language)
  const language = preferences.language
  const artwork = aboutArtwork(language)
  const previewArtwork = () => wx.previewImage({ current: artwork.image, urls: [artwork.image] })
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
  return { labels, brandTitle, dark, statusBar, version: __APP_VERSION__, artwork, previewArtwork,
    back, copyLink, notices, notice, toggleNotice, desktopDownloadURL, repositoryURL, investment, costGroups, toggleCostGroup,
    platforms: aboutPlatforms(language),
    description: labels.description,
    descriptionLines: labels.description.match(/[^。.]+[。.]?/g).map(line => line.trim()),
    noticesIntro: text(['Third-party software and data follow their original licenses. Tap to read the full copyright and license text.',
      '第三方软件及数据分别遵循其原始许可证。点按查看完整版权与许可文本。', '第三方軟體及資料分別遵循其原始授權條款。點按查看完整版權與授權文字。'], language),
    noticesTitle: text(['Third-party licenses', '第三方许可', '第三方授權'], language),
  }
}, { canShareToOthers: true })
