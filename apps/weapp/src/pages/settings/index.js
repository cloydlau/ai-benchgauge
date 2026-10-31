import { computed, definePage, ref, onReady, onShow, onHide, onUnload } from '@vue-mini/core'
import { categories, copy, text } from '../../core/catalog.js'
import { pagePreferences, normalizePreferences } from '../../core/share-state.js'
import { visibleBoardKinds, toggleBoardSelection, selectedBoardFace, selectedBoardCategory, selectedBoardCount, boardSelectionTitle } from '../../core/board-selection.js'
import { sourceTabLogo } from '../../core/source-tab-theme.js'
import { boardTransitions, normalizeBoardTransition, boardFaceStyle } from '../../core/board-transition.js'

definePage(query => {
  const saved = (() => { try { return wx.getStorageSync('benchgauge.preferences') || {} } catch { return {} } })()
  const preferences = pagePreferences(query, saved, wx.getAppBaseInfo?.().language)
  const selections = ref(preferences.boardSelections || {})
  const boardTransition = ref(normalizeBoardTransition(preferences.boardTransition))
  const previewRunning = ref(false)
  const previewPosition = ref(0)
  const previewDuration = ref(0)
  let previewTimer
  function stopPreview() {
    clearTimeout(previewTimer)
    previewRunning.value = false
    previewDuration.value = 0
    previewPosition.value = 0
  }
  function startPreview() {
    stopPreview()
    previewRunning.value = true
    function cycle() {
      previewDuration.value = 0
      previewPosition.value = 0
      previewTimer = setTimeout(() => {
        previewDuration.value = 1050
        previewPosition.value = 1
        previewTimer = setTimeout(cycle, 2700)
      }, 300)
    }
    cycle()
  }
  let ready = false
  onReady(() => { ready = true; startPreview() })
  onShow(() => { if (ready) startPreview() })
  onHide(stopPreview)
  onUnload(() => { ready = false; stopPreview() })
  const previewFaces = computed(() => Object.fromEntries(boardTransitions.map(id => {
    const position = previewPosition.value
    const duration = previewDuration.value
    return [id, [0, 1].map(face => ({
      style: boardFaceStyle(id, face, position, duration, true),
      shade: `opacity:${id === 'cube' ? Math.abs(face - position) * 0.18 : 0};transition-duration:${duration}ms;`,
    }))]
  })))
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
      boards: category.kinds.map(kind => ({ kind, title: boardSelectionTitle(kind, preferences.language),
        icon: sourceTabLogo(kind, dark), selected: visible.includes(kind), disabled: selectedBoardCount(selections.value) === 1 && visible.includes(kind) })) }
  }))
  function save(next) {
    const category = selectedBoardCategory(preferences.category, next)
    preferences.face = category === preferences.category ? selectedBoardFace(category, preferences.face, selections.value, next) : 0
    preferences.category = category
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
    if (boardTransition.value === id) return
    boardTransition.value = id
    preferences.boardTransition = id
    try { wx.setStorageSync('benchgauge.preferences', normalizePreferences(preferences, wx.getAppBaseInfo?.().language)) } catch { /* Local preferences are optional. */ }
  }
  const back = () => {
    if (getCurrentPages().length > 1) wx.navigateBack()
    else wx.reLaunch({ url: '/pages/leaderboard/index' })
  }
  return { labels, groups, dark, boardTransition, previewRunning, previewFaces, transitionOptions, selectTransition, statusBar: wx.getWindowInfo().statusBarHeight || 24, toggleBoard, reset, back }
})
