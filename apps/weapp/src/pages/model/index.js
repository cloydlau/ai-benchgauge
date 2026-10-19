import { definePage, ref, computed } from '@vue-mini/core'
import { detailText, modelDetailSections, safeDetailURL } from '../../core/model-details.js'
import { pagePreferences } from '../../core/share-state.js'

definePage((query, context) => {
  const saved = (() => { try { return wx.getStorageSync('benchgauge.preferences') || {} } catch { return {} } })()
  const preferences = pagePreferences(query, saved, wx.getAppBaseInfo?.().language)
  const language = preferences.language, tr = key => detailText(key, language)
  const dark = preferences.theme === 'dark' || preferences.theme === 'system' && (preferences.appearance || wx.getAppBaseInfo?.().theme) === 'dark'
  const entry = ref(null), expanded = ref({}), copied = ref(false)
  const sections = computed(() => modelDetailSections(entry.value, language).map(section => ({ ...section,
    expanded: !section.summary || Boolean(expanded.value[section.id]) })))
  context.getOpenerEventChannel().on('modelDetails', data => { entry.value = data.entry })
  const copyName = () => {
    if (!entry.value?.name) return
    wx.setClipboardData({ data: entry.value.name, success: () => { copied.value = true; wx.showToast({ title: tr('copied'), icon: 'success' }) } })
  }
  const copyLink = event => {
    const url = safeDetailURL(event.currentTarget.dataset.url)
    if (url) wx.setClipboardData({ data: url, success: () => wx.showToast({ title: tr('copied'), icon: 'success' }) })
  }
  const toggle = event => {
    const id = event.currentTarget.dataset.id
    expanded.value = { ...expanded.value, [id]: !expanded.value[id] }
  }
  return { entry, sections, copied, dark, statusBar: wx.getWindowInfo().statusBarHeight || 24,
    labels: Object.fromEntries(['details', 'copy', 'copied', 'close', 'missing'].map(k => [k, tr(k)])),
    back: () => wx.navigateBack(), copyName, copyLink, toggle }
})
