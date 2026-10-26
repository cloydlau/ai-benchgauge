import { computed, definePage, ref } from '@vue-mini/core'
import { categories, copy, text, boardTitle } from '../../core/catalog.js'
import { pagePreferences, normalizePreferences } from '../../core/share-state.js'
import { visibleBoardKinds, toggleBoardSelection, selectedBoardFace } from '../../core/board-selection.js'
import { sourceTabLogo } from '../../core/source-tab-theme.js'
import { boardTransitions, normalizeBoardTransition } from '../../core/board-transition.js'

definePage(query => {
  const saved = (() => { try { return wx.getStorageSync('benchgauge.preferences') || {} } catch { return {} } })()
  const preferences = pagePreferences(query, saved, wx.getAppBaseInfo?.().language)
  const selections = ref(preferences.boardSelections || {})
  const boardTransition = ref(normalizeBoardTransition(preferences.boardTransition))
  const transitionOptions = boardTransitions.map(id => {
    const key = `transition${id[0].toUpperCase()}${id.slice(1)}`
    return { id, title: text(copy[key], preferences.language), hint: text(copy[`${key}Hint`], preferences.language) }
  })
  const labels = Object.fromEntries(Object.entries(copy).map(([key, values]) => [key, text(values, preferences.language)]))
  const dark = preferences.theme === 'dark' || (preferences.theme === 'system'
    && (preferences.appearance || wx.getAppBaseInfo?.().theme) === 'dark')
  wx.setNavigationBarColor?.({ frontColor: dark ? '#ffffff' : '#000000', backgroundColor: dark ? '#101216' : '#f4f5f7' })
  const groups = computed(() => categories.map(category => {
    const visible = visibleBoardKinds(category.id, selections.value)
    return { id: category.id, title: text(category.labels, preferences.language),
      boards: category.kinds.map(kind => ({ kind, title: boardTitle(kind, preferences.language),
        icon: sourceTabLogo(kind, dark), selected: visible.includes(kind), disabled: visible.length === 1 && visible.includes(kind) })) }
  }))
  function save(next) {
    preferences.face = selectedBoardFace(preferences.category, preferences.face, selections.value, next)
    selections.value = next
    preferences.boardSelections = next
    try { wx.setStorageSync('benchgauge.preferences', normalizePreferences(preferences, wx.getAppBaseInfo?.().language)) } catch { /* Local preferences are optional. */ }
  }
  function toggleBoard(event) {
    const { category, kind } = event.currentTarget.dataset
    if (!categories.some(item => item.id === category)) return
    const next = toggleBoardSelection(category, kind, selections.value)
    if (next !== selections.value) save(next)
  }
  const reset = () => save({})
  function selectTransition(event) {
    const id = event.currentTarget.dataset.id
    if (!boardTransitions.includes(id)) return
    boardTransition.value = id
    preferences.boardTransition = id
    try { wx.setStorageSync('benchgauge.preferences', normalizePreferences(preferences, wx.getAppBaseInfo?.().language)) } catch { /* Local preferences are optional. */ }
  }
  const back = () => {
    if (getCurrentPages().length > 1) wx.navigateBack()
    else wx.reLaunch({ url: '/pages/leaderboard/index' })
  }
  return { labels, groups, dark, boardTransition, transitionOptions, selectTransition, statusBar: wx.getWindowInfo().statusBarHeight || 24, toggleBoard, reset, back }
})
