import { computed, definePage, ref, onReady, onResize, onUnload, onShareAppMessage } from '@vue-mini/core'
import { desktopDownloadURL, repositoryURL, copy, text } from '../../core/catalog.js'
import { createBrandMeasurer } from '../../core/brand-title.js'
import { pagePreferences, sharePath } from '../../core/share-state.js'
import { investmentContent } from '../../core/investment.js'
import { contributorsContent } from '../../core/contributors.js'
import { aboutPlatforms } from '../../core/about-platforms.js'
import { aboutArtwork } from '../../core/about-artwork.js'

definePage(query => {
  const saved = (() => { try { return wx.getStorageSync('benchgauge.preferences') || {} } catch { return {} } })()
  const preferences = pagePreferences(query, saved, wx.getAppBaseInfo?.().language)
  const language = preferences.language
  const artwork = aboutArtwork(language)
  const previewArtwork = () => wx.previewImage({ current: artwork.image, urls: [artwork.image] })
  const artworkTitleScale = ref(wx.createSelectorQuery ? 0 : 1)
  let ready = false, alive = true, titleMeasureSerial = 0
  const measureArtworkTitle = () => {
    if (!ready || !alive || !wx.createSelectorQuery) return
    const serial = ++titleMeasureSerial
    const measure = () => {
      if (!alive || serial !== titleMeasureSerial) return
      const query = wx.createSelectorQuery()
      query.select('.artwork-heading').boundingClientRect()
      // This hidden copy always keeps its natural size, including after a resize.
      query.select('.artwork-title-measure').boundingClientRect()
      query.exec(([heading, title]) => {
        if (!alive || serial !== titleMeasureSerial || !Number.isFinite(heading?.width)
          || !Number.isFinite(title?.width) || title.width <= 0) return
        artworkTitleScale.value = Math.min(1, Math.max(0, heading.width) / title.width)
      })
    }
    if (wx.nextTick) wx.nextTick(measure)
    else measure()
  }
  onReady(() => { ready = true; measureArtworkTitle() })
  onResize(() => {
    const window = wx.getWindowInfo()
    statusBar.value = window.statusBarHeight ?? 24
    brandTitle.value = measureBrand(labels.name, (window.windowWidth || 375) / 750 * 48)
    measureArtworkTitle()
  })
  onUnload(() => { alive = false; titleMeasureSerial++ })
  const labels = Object.fromEntries(Object.keys(copy).map(key => [key, text(copy[key], language)]))
  const dark = preferences.theme === 'dark' || (preferences.theme === 'system'
    && (preferences.appearance || wx.getAppBaseInfo?.().theme) === 'dark')
  if (preferences.fromShare) {
    try { wx.setStorageSync('benchgauge.preferences', preferences) } catch { /* Sharing does not require local storage. */ }
  }
  onShareAppMessage(() => ({ title: `${labels.about}｜${labels.rankingSummary}`,
    path: sharePath(preferences, dark ? 'dark' : 'light', '/pages/about/index') }))
  const statusBar = ref(wx.getWindowInfo().statusBarHeight ?? 24)
  const measureBrand = createBrandMeasurer(wx)
  const brandTitle = ref(measureBrand(labels.name, (wx.getWindowInfo().windowWidth || 375) / 750 * 48))
  const notice = ref('')
  const investment = investmentContent(__ENGINEERING_INVESTMENT__, language)
  const contributors = contributorsContent(__CONTRIBUTOR_CIRCLES__, language)
  const contributorsExpanded = ref(false)
  const openContributors = () => { contributorsExpanded.value = true }
  const closeContributors = () => { contributorsExpanded.value = false }
  const selectedContributorID = ref('')
  const selectedContributor = computed(() => contributors.nodes.find(node => node.id === selectedContributorID.value) || null)
  const selectContributor = event => {
    const id = event.currentTarget.dataset.id
    if (contributors.nodes.some(node => node.id === id)) selectedContributorID.value = id
  }
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
  return { labels, brandTitle, dark, statusBar, version: __APP_VERSION__, artwork, previewArtwork, artworkTitleScale,
    back, copyLink, notices, notice, toggleNotice, desktopDownloadURL, repositoryURL, investment, costGroups, toggleCostGroup,
    platforms: aboutPlatforms(language),
    contributors, contributorsExpanded, openContributors, closeContributors,
    selectedContributorID, selectedContributor, selectContributor,
    description: labels.description,
    descriptionLines: labels.description.match(/[^。.]+[。.]?/g).map(line => line.trim()),
    noticesIntro: text(['Third-party software and data follow their original licenses. Tap to read the full copyright and license text.',
      '第三方软件及数据分别遵循其原始许可证。点按查看完整版权与许可文本。', '第三方軟體及資料分別遵循其原始授權條款。點按查看完整版權與授權文字。'], language),
    noticesTitle: text(['Third-party licenses', '第三方许可', '第三方授權'], language),
  }
}, { canShareToOthers: true })
