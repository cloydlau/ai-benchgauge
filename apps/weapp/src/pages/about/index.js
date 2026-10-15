import { definePage, ref, onShareAppMessage } from '@vue-mini/core'
import { leaderboardSources, desktopDownloadURL, copy, text } from '../../core/catalog.js'
import { createBrandMeasurer } from '../../core/brand-title.js'
import { pagePreferences, sharePath } from '../../core/share-state.js'

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
  onShareAppMessage(() => ({ title: `${labels.name} · ${labels.about}`,
    path: sharePath(preferences, dark ? 'dark' : 'light', '/pages/about/index') }))
  const statusBar = wx.getWindowInfo().statusBarHeight || 24
  const brandTitle = createBrandMeasurer(wx)(labels.name, (wx.getWindowInfo().windowWidth || 375) / 750 * 35)
  const notice = ref('')
  const notices = __THIRD_PARTY_NOTICES__.map(item => ({ ...item,
    title: text([`Third-party notice ${item.number}`, `第三方软件声明 ${item.number}`, `第三方軟體聲明 ${item.number}`], language) }))
  const items = leaderboardSources
  const back = () => {
    if (!preferences.fromShare && getCurrentPages().length > 1) wx.navigateBack()
    else wx.reLaunch({ url: sharePath(preferences, dark ? 'dark' : 'light') })
  }
  const copyLink = event => wx.setClipboardData({ data: event.currentTarget.dataset.url })
  const toggleNotice = event => {
    const id = event.currentTarget.dataset.id
    if (notices.some(item => item.id === id)) notice.value = notice.value === id ? '' : id
  }
  return { labels, brandTitle, dark, statusBar, items, version: __APP_VERSION__,
    back, copyLink, notices, notice, toggleNotice, desktopDownloadURL,
    description: text(['Compare task benchmarks and blind user votes across different AI model capabilities.',
      '对照任务测评与用户盲测，比较模型在不同场景下的表现。',
      '對照任務測評與使用者盲測，比較模型在不同情境下的表現。'], language),
    desktopTitle: text(['PC download', 'PC 端下载', 'PC 端下載'], language),
    desktopDownloadLabel: text(['Download the latest desktop version', '下载最新电脑端版本', '下載最新電腦版'], language),
    sourcesTitle: text(['Leaderboard sources', '榜单来源', '榜單來源'], language),
    noticesIntro: text(['Third-party software follows its original licenses. Tap to read the full copyright and license text.',
      '第三方软件分别遵循其原始许可证。点按查看完整版权与许可文本。', '第三方軟體分別遵循其原始授權條款。點按查看完整版權與授權文字。'], language),
    noticesTitle: text(['Open-source notices', '开源声明', '開源聲明'], language),
  }
}, { canShareToOthers: true })
