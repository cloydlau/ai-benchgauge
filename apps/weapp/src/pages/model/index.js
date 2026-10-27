import { definePage, ref, computed, onPageScroll } from '@vue-mini/core'
import { detailText, modelDetailSections, safeDetailURL } from '../../core/model-details.js'
import { pagePreferences } from '../../core/share-state.js'

definePage((query, context) => {
  const saved = (() => { try { return wx.getStorageSync('benchgauge.preferences') || {} } catch { return {} } })()
  const preferences = pagePreferences(query, saved, wx.getAppBaseInfo?.().language)
  const language = preferences.language, tr = key => detailText(key, language)
  const dark = preferences.theme === 'dark' || preferences.theme === 'system' && (preferences.appearance || wx.getAppBaseInfo?.().theme) === 'dark'
  const entry = ref(null), expanded = ref({}), copied = ref(false), backToTop = ref(false)
  const sections = computed(() => modelDetailSections(entry.value, language).map(section => ({ ...section,
    summary: section.summary || `${section.rows.length} ${tr('facts')}`,
    layout: section.id === 'limits' || section.id === 'capabilities' ? 'tiles' : 'list',
    icon: section.id === 'limits' ? 'chart-trending-o' : section.id === 'capabilities' ? 'apps-o' : section.id.startsWith('provider-') ? 'cluster-o' : section.id === 'source' ? 'info-o' : 'description',
    expanded: expanded.value[section.id] ?? ['limits', 'capabilities', 'modalities'].includes(section.id),
  })).sort((a, b) => {
    const order = id => ({limits: 0, capabilities: 1, modalities: 2, general: 3, source: 9}[id] ?? 4)
    return order(a.id) - order(b.id)
  }))
  const description = computed(() => typeof entry.value?.modelMetadata?.attributes?.description === 'string' ? entry.value.modelMetadata.attributes.description : '')
  onPageScroll(({ scrollTop }) => { backToTop.value = scrollTop > 400 })
  const top = () => wx.pageScrollTo({ scrollTop: 0, duration: 250 })
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
    const section = sections.value.find(section => section.id === id)
    if (section) expanded.value = { ...expanded.value, [id]: !section.expanded }
  }
  return { entry, sections, description, copied, backToTop, top, dark, statusBar: wx.getWindowInfo().statusBarHeight || 24,
    labels: Object.fromEntries(['details', 'copy', 'copied', 'close', 'missing', 'backToTop'].map(k => [k, tr(k)])),
    back: () => wx.navigateBack(), copyName, copyLink, toggle }
})
