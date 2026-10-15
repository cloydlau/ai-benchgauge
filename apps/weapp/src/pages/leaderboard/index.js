import { definePage, ref, computed, onLoad, onShow, onUnload, onShareAppMessage, onResize } from '@vue-mini/core'
import { boards, categories, categoryFor, copy, text, languages, boardTitle, hasOwn } from '../../core/catalog.js'
import { rankedEntries, rowView, countryOptions, formatTime, latestTimestamp } from '../../core/leaderboard.js'
import { createBoardStore } from '../../services/boards.js'
import { rowGeometry, resolveRowWindow, createRowRenderer } from '../../core/row-window.js'
import { exportScreenshots, saveScreenshotImage } from '../../services/screenshot.js'
import { cubeFaceStyle, cubeGesture, moveCubeGesture, cubeDestination, matchingScroll } from '../../core/cube.js'
import { createBrandMeasurer } from '../../core/brand-title.js'
import { pagePreferences, sharePath, systemLanguage } from '../../core/share-state.js'

definePage(query => {
  const saved = (() => { try { return wx.getStorageSync('benchgauge.preferences') || {} } catch { return {} } })()
  const initial = pagePreferences(query, saved, wx.getAppBaseInfo?.().language)
  const language = ref(initial.language)
  const languageMode = ref(initial.languageMode)
  const category = ref(initial.category)
  const grouping = ref(initial.grouping)
  const face = ref(initial.face)
  const cubePosition = ref(initial.face)
  const cubeDuration = ref(0)
  const cubeBusy = ref(false)
  const cubeFaces = computed(() => [0, 1].map(index => ({
    style: cubeFaceStyle(index, cubePosition.value, cubeDuration.value, cubeBusy.value),
    shade: Math.abs(index - cubePosition.value) * 0.18,
  })))
  const sourceSelection = computed(() => {
    const position = cubePosition.value
    const from = dark.value ? [29, 55, 82] : [228, 240, 255]
    const to = dark.value ? [59, 42, 78] : [238, 229, 248]
    const color = from.map((channel, index) => Math.round(channel + (to[index] - channel) * position))
    return `transform:translateX(${position * 100}%) translateX(${position * 12}rpx);background-color:rgb(${color.join(',')});transition-duration:${cubeDuration.value}ms;`
  })
  let gesture, cubeTimer, entranceTimer, entrancePlayed = false
  let cubeWidth = 375
  let suppressTapUntil = 0
  function stopCube() {
    clearTimeout(cubeTimer); clearTimeout(entranceTimer)
    gesture = null; cubeDuration.value = 0; cubeBusy.value = false; cubePosition.value = face.value
  }
  function alignFace(destination) {
    if (destination === face.value) return
    const from = current.value.kinds[face.value], to = current.value.kinds[destination]
    const count = rankedCards.value[destination].entries.length
    const target = matchingScroll({ scrollTop: scrollPositions[from] || 0,
      origin: origins[from] || 0, nextOrigin: origins[to] || 0, rowHeight: geometry.value.rowHeight, count })
    scrollPositions[to] = target
    scrollTargets.value = { ...scrollTargets.value, [to]: target === scrollTargets.value[to] ? target + 0.01 : target }
    backTopBoards.value = { ...backTopBoards.value, [to]: target > 400 }
    syncWindow(to, true)
  }
  function turnCube(destination) {
    if (!cubeBusy.value && destination === face.value && cubePosition.value === destination) return
    clearTimeout(cubeTimer); clearTimeout(entranceTimer)
    if (gesture?.axis !== 'horizontal') alignFace(destination)
    face.value = destination; gesture = null
    cubeBusy.value = true; cubeDuration.value = 0
    persist()
    // Mount both hinged faces before changing the target. Separate render
    // frames give a tab tap the same geometry as an interactive drag.
    cubeTimer = setTimeout(() => {
      if (!alive) return
      cubeDuration.value = 320; cubePosition.value = destination
      cubeTimer = setTimeout(() => {
        if (!alive) return
        cubeBusy.value = false; cubeDuration.value = 0; measureLists()
      }, 340)
    }, 24)
  }
  function touchPoint(event) { return event.touches?.[0] || event.changedTouches?.[0] }
  function cubeStart(event) {
    const point = touchPoint(event)
    if (!point || event.touches?.length > 1 || sheet.value.open || capture.value.open) return
    stopCube(); entrancePlayed = true
    gesture = cubeGesture(face.value, point.clientX, point.clientY, Date.now())
  }
  function cubeMove(event) {
    const point = touchPoint(event)
    if (!gesture || !point) return
    if (event.touches?.length > 1) { stopCube(); return }
    const previousAxis = gesture.axis
    moveCubeGesture(gesture, point.clientX, point.clientY, Date.now(), cubeWidth)
    if (gesture.axis !== 'horizontal') return
    if (previousAxis !== 'horizontal') alignFace(1 - face.value)
    cubeBusy.value = true; cubePosition.value = gesture.position
    suppressTapUntil = Date.now() + 400
  }
  function cubeEnd() {
    if (gesture?.axis === 'horizontal') turnCube(cubeDestination(gesture, cubeWidth, Date.now()))
    else gesture = null
  }
  function cubeCancel() {
    if (gesture?.axis === 'horizontal') turnCube(face.value)
    else gesture = null
  }
  function playEntrance() {
    if (entrancePlayed || !alive) return
    entrancePlayed = true
    entranceTimer = setTimeout(() => {
      if (!alive || gesture) return
      alignFace(1 - face.value)
      cubeBusy.value = true; cubeDuration.value = 0
      entranceTimer = setTimeout(() => {
        if (!alive) return
        cubeDuration.value = 220; cubePosition.value = face.value ? 0.86 : 0.14
        entranceTimer = setTimeout(() => turnCube(face.value), 360)
      }, 24)
    }, 300)
  }
  const theme = ref(initial.theme)
  const sharedAppearance = ref(initial.appearance)
  const systemTheme = ref(wx.getAppBaseInfo?.().theme || 'light')
  const dark = computed(() => theme.value === 'dark' || (theme.value === 'system' && (sharedAppearance.value || systemTheme.value) === 'dark'))
  const headerWidth = ref(wx.getWindowInfo().windowWidth || 375)
  const measureBrand = createBrandMeasurer(wx)
  const statusBar = ref(24)
  const navHeight = ref(68)
  const headerTop = ref(28)
  const capsuleWidth = ref(100)
  const store = createBoardStore({ platform: wx, endpoint: __SHARED_ENDPOINT__ })
  const snapshots = ref(Object.fromEntries(Object.keys(boards).map(kind => [kind, store.read(kind)])))
  const filters = ref(initial.filters)
  const refreshing = ref({})
  const pullRefreshing = ref(false)
  const scrollPositions = {}
  const scrollWindows = ref({})
  const geometry = ref(rowGeometry(wx.getWindowInfo()))
  const origins = {}
  const viewports = {}
  const backTopBoards = ref({})
  const rowRenderers = new Map()
  let measureSerial = 0
  const scrollTargets = ref({})
  const sheet = ref({ open: false, title: '', actions: [], kind: '', mode: '' })
  const capturing = ref(false)
  const capture = ref({ open: false, paths: [], index: 0, saving: false, saved: 0 })
  const lastAttempt = {}
  let alive = true

  const tr = key => text(copy[key], language.value)
  const labels = computed(() => Object.fromEntries(Object.keys(copy).map(key => [key, tr(key)])))
  const brandTitle = computed(() => measureBrand(labels.value.name, headerWidth.value / 750
    * (language.value === 'en' ? headerWidth.value <= 350 ? 21 : 26 : 24)))
  const categoryItems = computed(() => categories.map((item, index) => ({ id: item.id, label: text(item.labels, language.value),
    icon: ['bar-chart-o', 'cluster-o', 'photo-o', 'video-o'][index] })))
  const categoryIndex = computed(() => categories.findIndex(item => item.id === category.value))
  const current = computed(() => categoryFor(category.value))
  const tabs = computed(() => [tr('tasks'), tr('votes')])
  const filterFor = kind => ({ country: 'all', openness: 'all', ...filters.value[kind] })
  // Keep full model data out of the Vue-to-WeChat bridge. Sorting/filtering
  // are cached independently of scroll positions; only window rows are mapped.
  const rankedCards = computed(() => current.value.kinds.map(kind => ({ kind,
    entries: rankedEntries(snapshots.value[kind], { ...filterFor(kind), grouping: grouping.value }) })))
  const cards = computed(() => rankedCards.value.map(({ kind, entries }, index) => {
    const board = snapshots.value[kind]
    const filter = filterFor(kind)
    const range = rangeFor(kind, entries.length)
    return { kind, title: boardTitle(kind, language.value), index, summary: text(boards[kind].summaries, language.value),
      updated: formatTime(board?.sourceUpdatedAt), fetched: formatTime(board?.fetchedAt), time: formatTime(latestTimestamp(board)),
      count: entries.length, height: entries.length * geometry.value.rowHeight, rowHeight: geometry.value.rowHeight,
      rows: renderRows(kind, entries, range),
      hasBoard: !!board, filtered: filter.country !== 'all' || filter.openness !== 'all',
      countryFiltered: filter.country !== 'all', sourceFiltered: filter.openness !== 'all',
      loading: !!refreshing.value[kind],
    }
  }))
  const backToTop = computed(() => !!backTopBoards.value[current.value.kinds[face.value]])

  function renderRows(kind, entries, range) {
    if (!rowRenderers.has(kind)) rowRenderers.set(kind, createRowRenderer(entry =>
      rowView(entry, { company: grouping.value === 'company', dark: dark.value, details: false })))
    return rowRenderers.get(kind)({ entries, ...range, rowHeight: geometry.value.rowHeight,
      variant: `${grouping.value}:${dark.value}` })
  }

  function rangeFor(kind, count, force = false) {
    return resolveRowWindow({ count, scrollTop: scrollPositions[kind] || 0, origin: origins[kind] || 0,
      geometry: { ...geometry.value, viewportHeight: viewports[kind] || geometry.value.viewportHeight },
      ...scrollWindows.value[kind], force })
  }
  function syncWindow(kind, force = false) {
    const card = rankedCards.value.find(card => card.kind === kind)
    if (!card) return
    const next = rangeFor(kind, card.entries.length, force)
    const previous = scrollWindows.value[kind]
    if (!previous || next.start !== previous.start || next.end !== previous.end) {
      scrollWindows.value = { ...scrollWindows.value, [kind]: next }
    }
  }
  function resetScroll(kinds = current.value.kinds) {
    for (const kind of kinds) {
      scrollPositions[kind] = 0
      backTopBoards.value = { ...backTopBoards.value, [kind]: false }
      scrollTargets.value = { ...scrollTargets.value, [kind]: (scrollTargets.value[kind] || 0) === 0 ? 0.01 : 0 }
      syncWindow(kind, true)
    }
    measureLists()
  }
  function measureLists() {
    const serial = ++measureSerial
    const kinds = current.value.kinds
    const run = () => {
      if (!alive || cubeBusy.value || serial !== measureSerial || !wx.createSelectorQuery) return
      const query = wx.createSelectorQuery()
      for (const kind of kinds) {
        query.select(`#board-scroll-${kind}`).boundingClientRect()
        query.select(`#rows-${kind}`).boundingClientRect()
      }
      query.exec(results => {
        if (!alive || serial !== measureSerial) return
        kinds.forEach((kind, index) => {
          const viewport = results[index * 2], rows = results[index * 2 + 1]
          if (!viewport?.height || !rows || !Number.isFinite(rows.top) || !Number.isFinite(viewport.top)) return
          origins[kind] = rows.top - viewport.top + (scrollPositions[kind] || 0)
          viewports[kind] = viewport.height
          syncWindow(kind, true)
        })
      })
    }
    if (wx.nextTick) wx.nextTick(run)
    else run()
  }

  function preferencesSnapshot() {
    return { language: language.value, languageMode: languageMode.value, category: category.value, grouping: grouping.value,
      face: face.value, theme: theme.value, appearance: sharedAppearance.value, filters: filters.value }
  }
  function persist() {
    try { wx.setStorageSync('benchgauge.preferences', preferencesSnapshot()) } catch { /* Preferences are optional. */ }
  }
  if (initial.fromShare) persist()
  function measure() {
    stopCube()
    const window = wx.getWindowInfo()
    cubeWidth = window.windowWidth || 375
    headerWidth.value = cubeWidth
    const menu = wx.getMenuButtonBoundingClientRect()
    statusBar.value = window.statusBarHeight || 24
    headerTop.value = menu.top
    navHeight.value = menu.bottom + 8
    capsuleWidth.value = window.windowWidth - menu.left + 12
    geometry.value = rowGeometry(window)
    for (const kind of current.value.kinds) syncWindow(kind, true)
    measureLists()
  }
  measure()
  onResize(measure)
  function updateTheme() {
    wx.setNavigationBarColor({ frontColor: dark.value ? '#ffffff' : '#000000', backgroundColor: dark.value ? '#10151c' : '#f5f7fa' })
  }
  const themeListener = event => { systemTheme.value = event.theme; sharedAppearance.value = null; updateTheme(); persist() }
  wx.onThemeChange?.(themeListener)
  updateTheme()

  async function refreshKind(kind) {
    if (refreshing.value[kind]) return
    lastAttempt[kind] = Date.now()
    refreshing.value = { ...refreshing.value, [kind]: true }
    try {
      const board = await store.fetch(kind)
      if (!alive) return
      snapshots.value = { ...snapshots.value, [kind]: board }
    } catch {
      // Background failures keep the last shared snapshot and its timestamps.
    } finally {
      if (alive) {
        refreshing.value = { ...refreshing.value, [kind]: false }
        syncWindow(kind, true)
        measureLists()
      }
    }
  }
  const refreshCategory = () => Promise.all(current.value.kinds.map(refreshKind))
  async function pullRefresh() {
    if (pullRefreshing.value) return
    pullRefreshing.value = true
    try { await refreshCategory() } finally { pullRefreshing.value = false }
  }
  onLoad(async () => { await refreshCategory(); playEntrance() })
  onShow(() => {
    if (languageMode.value === 'system') {
      const next = systemLanguage(wx.getAppBaseInfo?.().language)
      if (next !== language.value) { language.value = next; measureLists() }
    }
    for (const kind of current.value.kinds) if (!lastAttempt[kind] || Date.now() - lastAttempt[kind] > 600000) refreshKind(kind)
  })
  onUnload(() => { stopCube(); alive = false; measureSerial++; rowRenderers.clear(); store.dispose(); wx.offThemeChange?.(themeListener)
    if (capturing.value || capture.value.saving) wx.hideLoading() })
  onShareAppMessage(() => ({ title: `${tr('name')} · ${tabs.value[face.value]}`,
    path: sharePath(preferencesSnapshot(), dark.value ? 'dark' : 'light') }))

  function selectCategory(event) {
    const id = event.currentTarget.dataset.id
    if (!categories.some(item => item.id === id)) return
    stopCube(); entrancePlayed = true
    category.value = id; rowRenderers.clear(); resetScroll(); persist(); refreshCategory()
  }
  function selectGrouping(event) { stopCube(); entrancePlayed = true; grouping.value = event.currentTarget.dataset.id; resetScroll(); persist() }
  function selectFace(event) {
    if (Date.now() < suppressTapUntil) return
    const destination = Number(event.currentTarget.dataset.index)
    if (destination === 0 || destination === 1) { entrancePlayed = true; turnCube(destination) }
  }
  function changeFace(event) { turnCube(event.detail.current === 1 ? 1 : 0) }
  function scroll(event) {
    const kind = event.currentTarget.dataset.kind
    if (!hasOwn(boards, kind)) return
    const top = Math.max(0, Number(event.detail.scrollTop) || 0)
    scrollPositions[kind] = top
    const show = top > 400
    if (!!backTopBoards.value[kind] !== show) backTopBoards.value = { ...backTopBoards.value, [kind]: show }
    // Native events, not delayed rAF: fast flicks must never outrun the window.
    syncWindow(kind)
  }
  function top() {
    const kind = current.value.kinds[face.value]
    // Change the target each time, including repeated returns after another scroll.
    scrollTargets.value = { ...scrollTargets.value, [kind]: (scrollTargets.value[kind] || 0) === 0 ? 0.01 : 0 }
  }
  function showSheet(mode, kind, actions, title) { sheet.value = { open: true, mode, kind, actions, title } }
  function filterMenu(event) {
    const { kind, mode } = event.currentTarget.dataset
    const filter = filterFor(kind)
    const actions = mode === 'country' ? countryOptions(snapshots.value[kind], language.value)
      : ['all', 'open', 'closed', 'unknown'].map(value => ({ value, label: tr(value) }))
    showSheet(mode, kind, actions.map(action => ({ name: action.label, value: action.value,
      ...(filter[mode] === action.value ? { color: '#1675dc' } : {}) })), tr(mode === 'country' ? 'country' : 'source'))
  }
  function clearFilters(event) {
    filters.value = { ...filters.value, [event.currentTarget.dataset.kind]: { country: 'all', openness: 'all' } }; resetScroll([event.currentTarget.dataset.kind]); persist()
  }
  function preferences(event) {
    const mode = event?.currentTarget?.dataset?.mode || 'language'
    const actions = mode === 'language'
      ? languages.map(value => ({ name: value === 'en' ? 'English' : value === 'zh-CN' ? '简体中文' : '繁體中文', value, mode }))
      : ['system', 'light', 'dark'].map(value => ({ name: tr(value === 'system' ? 'automatic' : value), value, mode }))
    showSheet('settings', '', actions, tr(mode === 'language' ? 'language' : 'theme'))
  }
  function sheetSelect(event) {
    const action = event.detail
    if (sheet.value.mode === 'settings') {
      if (action.mode === 'language') { language.value = action.value; languageMode.value = 'manual' }
      else { theme.value = action.value; sharedAppearance.value = null; updateTheme() }
    } else {
      filters.value = { ...filters.value, [sheet.value.kind]: { ...filterFor(sheet.value.kind), [sheet.value.mode]: action.value } }
    }
    if (sheet.value.mode !== 'settings') resetScroll([sheet.value.kind])
    else measureLists()
    sheet.value = { ...sheet.value, open: false }; persist()
  }
  function closeSheet() { sheet.value = { ...sheet.value, open: false } }
  function sourceHelp(event) {
    const kind = event.currentTarget.dataset.kind
    const board = snapshots.value[kind]
    wx.showModal({ title: boardTitle(kind, language.value),
      content: `${text(boards[kind].summaries, language.value)}\n\n${tr('updated')}: ${formatTime(latestTimestamp(board))}\n\n${boards[kind].url}`,
      showCancel: false })
  }
  function rowDetails(event) {
    if (cubeBusy.value || Date.now() < suppressTapUntil) return
    const { kind, rank } = event.currentTarget.dataset
    const entry = rankedCards.value.find(card => card.kind === kind)?.entries.find(row => row.rank === Number(rank))
    if (!entry) return
    const row = rowView(entry, { company: grouping.value === 'company', dark: dark.value })
    const content = row.components.length ? `${tr('strongest')}\n\n${row.components.map(member => `#${member.rank} ${member.name} · ${member.score}`).join('\n')}` : row.name
    wx.showModal({ title: grouping.value === 'company' ? row.name : tr('details'), content,
      confirmText: tr('copyName'), success: result => { if (result.confirm) wx.setClipboardData({ data: row.name }) } })
  }
  async function screenshot() {
    if (capturing.value || capture.value.saving) return
    if (!current.value.kinds.some(kind => snapshots.value[kind])) {
      wx.showToast({ title: tr('noBoard'), icon: 'none' }); return
    }
    capturing.value = true
    wx.showLoading({ title: tr('generating'), mask: true })
    let failed = false
    try {
      // Freeze the current filters/theme and export complete lists rather than
      // the rows currently mounted in the scroll window.
      const model = { labels: { ...labels.value }, dark: dark.value,
        groupingLabel: tr(grouping.value === 'company' ? 'companies' : 'models'),
        categoryLabel: text(current.value.labels, language.value),
        boards: current.value.kinds.map((kind, index) => {
          const board = snapshots.value[kind], filter = filterFor(kind)
          const country = countryOptions(board, language.value).find(option => option.value === filter.country)?.label || tr('unknown')
          return { title: boardTitle(kind, language.value), tab: tabs.value[index],
            summary: text(boards[kind].summaries, language.value), time: formatTime(latestTimestamp(board)),
            filterLabel: `${tr('country')}: ${country} · ${tr('source')}: ${tr(filter.openness)}`,
            empty: tr(board ? 'empty' : 'noBoard'),
            rows: rankedEntries(board, { ...filter, grouping: grouping.value }).map(entry =>
              rowView(entry, { company: grouping.value === 'company', dark: dark.value, details: false })) }
        }) }
      const canvas = await new Promise((resolve, reject) => {
        wx.createSelectorQuery().select('#leaderboard-export').fields({ node: true }).exec(result => {
          if (result?.[0]?.node) resolve(result[0].node)
          else reject(new Error('Canvas unavailable'))
        })
      })
      const paths = await exportScreenshots({ platform: wx, canvas, model, isActive: () => alive,
        progress: (index, count) => wx.showLoading({ title: `${tr('generating')} ${index}/${count}`, mask: true }) })
      if (alive) capture.value = { open: true, paths, index: 0, saving: false, saved: 0 }
    } catch {
      failed = true
    } finally { capturing.value = false; if (alive) wx.hideLoading() }
    if (alive && failed) wx.showToast({ title: tr('screenshotFailed'), icon: 'none' })
  }
  function closeCapture() { if (!capture.value.saving) capture.value = { ...capture.value, open: false } }
  function capturePage(event) {
    const index = capture.value.index + Number(event.currentTarget.dataset.step)
    if (index >= 0 && index < capture.value.paths.length) capture.value = { ...capture.value, index }
  }
  function previewScreenshot(event) {
    const paths = capture.value.paths
    if (paths.length) wx.previewImage({ urls: paths, current: paths[Number(event?.currentTarget?.dataset?.index ?? capture.value.index)] })
  }
  async function saveScreenshot() {
    if (capture.value.saving || !capture.value.paths.length) return
    capture.value = { ...capture.value, saving: true }
    let failed
    try {
      while (capture.value.saved < capture.value.paths.length) {
        if (!alive) return
        wx.showLoading({ title: `${tr('savingImages')} ${capture.value.saved + 1}/${capture.value.paths.length}`, mask: true })
        await saveScreenshotImage(wx, capture.value.paths[capture.value.saved])
        capture.value = { ...capture.value, saved: capture.value.saved + 1 }
      }
    } catch (error) {
      failed = error
    } finally { capture.value = { ...capture.value, saving: false }; if (alive) wx.hideLoading() }
    if (!alive) return
    if (failed) {
      if (/auth.*(?:deny|denied)|permission/i.test(failed?.errMsg || '')) {
        wx.showModal({ title: tr('screenshot'), content: tr('photoPermission'), confirmText: tr('settings'),
          success: result => { if (result.confirm) wx.openSetting({}) } })
      } else wx.showToast({ title: tr('saveFailed'), icon: 'none' })
    } else wx.showToast({ title: tr('savedImages'), icon: 'success' })
  }
  const about = () => wx.navigateTo({ url: sharePath(preferencesSnapshot(), dark.value ? 'dark' : 'light', '/pages/about/index') })
  const quotaHelp = () => wx.showModal({ title: tr('subtitle'), content: tr('quotaHelp'), showCancel: false })
  const refreshTap = event => refreshKind(event.currentTarget.dataset.kind)
  return { labels, brandTitle, categoryItems, categoryIndex, category, grouping, face, dark, cards, tabs, backToTop,
    statusBar, navHeight, headerTop, capsuleWidth, sheet, scrollTargets,
    cubeFaces, sourceSelection, cubePosition, cubeDuration, cubeBusy, cubeStart, cubeMove, cubeEnd, cubeCancel,
    selectCategory, selectGrouping, selectFace, changeFace, scroll, top, filterMenu,
    clearFilters, preferences, sheetSelect, closeSheet, sourceHelp, rowDetails, about,
    quotaHelp, refreshTap, refreshCategory, pullRefresh, pullRefreshing,
    capturing, capture, screenshot, closeCapture, capturePage, previewScreenshot, saveScreenshot }
}, { canShareToOthers: true })
