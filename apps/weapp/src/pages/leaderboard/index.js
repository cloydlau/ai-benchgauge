import { definePage, ref, computed, onLoad, onReady, onShow, onHide, onUnload, onShareAppMessage, onResize } from '@vue-mini/core'
import { boards, categories, categoryFor, copy, text, languages, boardTitle, hasOwn, desktopDownloadURL } from '../../core/catalog.js'
import { rankedEntries, rowView, countryCode, countryName, countryOptions, formatTime, latestTimestamp } from '../../core/leaderboard.js'
import { createBoardStore } from '../../services/boards.js'
import { rowGeometry, resolveRowWindow, createRowRenderer } from '../../core/row-window.js'
import { exportScreenshot, removeScreenshot, saveScreenshotImage } from '../../services/screenshot.js'
import { cubeIndex, cubeTarget, cubeRenderedFace, cubeFaceStyle, cubeGesture, moveCubeGesture, cubeDestination, matchingScroll } from '../../core/cube.js'
import { createBrandMeasurer } from '../../core/brand-title.js'
import { pagePreferences, sharePath, systemLanguage } from '../../core/share-state.js'
import { purchaseLinks, preferredPurchaseLink } from '../../core/purchase-links.js'

definePage(query => {
  const saved = (() => { try { return wx.getStorageSync('benchgauge.preferences') || {} } catch { return {} } })()
  const initial = pagePreferences(query, saved, wx.getAppBaseInfo?.().language)
  const language = ref(initial.language)
  const languageMode = ref(initial.languageMode)
  const category = ref(initial.category)
  const grouping = ref(initial.grouping)
  const modelSearchQuery = ref('')
  const modelSearchOpen = ref(false)
  const modelSearchFocused = ref(false)
  const modelSearchVisible = computed(() => grouping.value === 'model' && modelSearchOpen.value)
  const searchOrigins = ref({})
  let searchFocusTimer, searchExpandTimer, searchBlurTimer, searchSerial = 0
  let clearingModelSearch = false
  const face = ref(initial.face)
  const sourceTabsHeight = ref(42)
  const sourceTabsOffset = ref(0)
  const sourceTabsExtent = computed(() => sourceTabsHeight.value + 8)
  const cubeViewportStyle = computed(() => `--cube-top:${Math.max(0, sourceTabsExtent.value - sourceTabsOffset.value)}px;`)
  const sourceTabsStyle = computed(() => `transform:translateY(-${sourceTabsOffset.value}px);pointer-events:${sourceTabsOffset.value >= sourceTabsExtent.value ? 'none' : 'auto'};`)
  function updateSourceTabs(top) {
    sourceTabsOffset.value = Math.min(sourceTabsExtent.value, Math.max(0, top))
  }
  let sourceTabsSyncTimer, sourceTabsSyncSerial = 0
  function cancelSourceTabsSync() {
    clearTimeout(sourceTabsSyncTimer)
    sourceTabsSyncSerial++
  }
  function syncSourceTabsAfterScroll(kind) {
    cancelSourceTabsSync()
    const serial = sourceTabsSyncSerial
    sourceTabsSyncTimer = setTimeout(() => {
      if (!alive || serial !== sourceTabsSyncSerial || kind !== current.value.kinds[face.value] || !wx.createSelectorQuery) return
      const query = wx.createSelectorQuery()
      query.select(`#board-scroll-${kind}`).fields({ scrollOffset: true })
      query.exec(results => {
        if (!alive || serial !== sourceTabsSyncSerial || kind !== current.value.kinds[face.value]) return
        const top = results[0]?.scrollTop
        if (!Number.isFinite(top)) return
        // The native offset is authoritative once scrolling settles. Bridge
        // events queued before a reset can otherwise leave the tabs clipped.
        const request = scrollRequests.get(kind)
        if (request) request.pending = false
        scrollPositions[kind] = Math.max(0, top)
        updateSourceTabs(scrollPositions[kind])
        backTopBoards.value = { ...backTopBoards.value, [kind]: top > 400 }
        syncWindow(kind)
      })
    }, 96)
  }
  const cubePosition = ref(initial.face)
  const cubeOrigin = ref(initial.face)
  const cubeDirection = ref(1)
  const cubeDuration = ref(0)
  const cubeBusy = ref(false)
  const cubeDragging = ref(false)
  const entranceProgress = ref(1)
  const entranceHintVisible = ref(false)
  const entranceStyle = computed(() => entranceProgress.value === 1 ? 'transition-duration:420ms;opacity:1;transform:none;'
    : 'transition-duration:0ms;opacity:0.65;transform:translateY(6px) scale(0.9925);')
  const cubeFaces = computed(() => current.value.kinds.map((_, index) => {
    const position = cubeRenderedFace(index, cubeOrigin.value, cubeDirection.value, current.value.kinds.length)
    return { style: cubeFaceStyle(position, cubePosition.value, cubeDuration.value, cubeBusy.value),
      shade: Math.abs(position - cubePosition.value) * 0.18 }
  }))
  const sourceSelection = computed(() => {
    const position = face.value
    const from = dark.value ? [29, 55, 82] : [228, 240, 255]
    const to = dark.value ? [59, 42, 78] : [238, 229, 248]
    const color = position === 2 ? (dark.value ? [30, 65, 60] : [220, 244, 236]) : from.map((channel, index) => Math.round(channel + (to[index] - channel) * position))
    return `width:calc((100% - ${(current.value.kinds.length - 1) * 12}rpx) / ${current.value.kinds.length});transform:translateX(${position * 100}%) translateX(${position * 12}rpx);background-color:rgb(${color.join(',')});`
  })
  let gesture, cubeTimer, entranceTimer, entrancePlayed = false
  let pageReady = false, pageVisible = false
  let cubeWidth = 375
  let suppressTapUntil = 0
  let lastCategoryTap = null
  function stopCube() {
    lastCategoryTap = null
    cubeDragging.value = false
    clearTimeout(cubeTimer); clearTimeout(entranceTimer)
    gesture = null; cubeDuration.value = 0; cubeBusy.value = false; cubePosition.value = face.value; cubeOrigin.value = face.value; cubeDirection.value = 1
    entranceProgress.value = 1; entranceHintVisible.value = false
  }
  function alignFace(destination) {
    if (destination === face.value) return
    const from = current.value.kinds[face.value], to = current.value.kinds[destination]
    const count = rankedCards.value[destination].entries.length
    const target = matchingScroll({ scrollTop: scrollPositions[from] || 0,
      origin: origins[from] || 0, nextOrigin: origins[to] || 0, rowHeight: geometry.value.rowHeight, count })
    scrollPositions[to] = target
    requestScroll(to, target)
    backTopBoards.value = { ...backTopBoards.value, [to]: target > 400 }
    syncWindow(to, true)
  }
  function turnCube(destination, position = cubeTarget(face.value, destination, current.value.kinds.length)) {
    destination = cubeIndex(destination, current.value.kinds.length)
    blurModelSearch()
    cubeDragging.value = false
    entranceProgress.value = 1; entranceHintVisible.value = false
    clearTimeout(cubeTimer); clearTimeout(entranceTimer)
    if (!cubeBusy.value && destination === face.value && cubePosition.value === destination) { gesture = null; return }
    const direction = position === face.value ? cubeDirection.value : Math.sign(position - face.value)
    if (gesture?.axis !== 'horizontal') cubePosition.value = face.value
    if (gesture?.axis !== 'horizontal' || direction !== cubeDirection.value) alignFace(destination)
    cubeOrigin.value = face.value; cubeDirection.value = direction
    face.value = destination; gesture = null
    updateSourceTabs(scrollPositions[current.value.kinds[destination]] || 0)
    cubeBusy.value = true; cubeDuration.value = 0
    persist()
    // Mount both hinged faces before changing the target. Separate render
    // frames give a tab tap the same geometry as an interactive drag.
    cubeTimer = setTimeout(() => {
      if (!alive) return
      cubeDuration.value = 320; cubePosition.value = position
      cubeTimer = setTimeout(() => {
        if (!alive) return
        cubeBusy.value = false; cubeDuration.value = 0
        cubePosition.value = face.value; cubeOrigin.value = face.value; cubeDirection.value = 1
        measureLists()
      }, 340)
    }, 24)
  }
  function touchPoint(event) { return event.touches?.[0] || event.changedTouches?.[0] }
  function cubeStart(event) {
    const point = touchPoint(event)
    if (!point || event.touches?.length > 1 || backgroundLocked.value || modelSearchFocused.value) return
    stopCube(); entrancePlayed = true
    // A new touch takes ownership from any queued programmatic navigation.
    scrollRequests.clear(); cancelSourceTabsSync()
    gesture = cubeGesture(face.value, point.clientX, point.clientY, Date.now(), current.value.kinds.length)
    gesture.scrollTop = scrollPositions[current.value.kinds[face.value]] || 0
  }
  function cubeMove(event) {
    const point = touchPoint(event)
    if (!gesture || !point) return
    if (event.touches?.length > 1) { stopCube(); return }
    moveCubeGesture(gesture, point.clientX, point.clientY, Date.now(), cubeWidth)
    if (gesture.axis !== 'horizontal') return
    cubeDragging.value = true
    suppressTapUntil = Date.now() + 400
    const direction = gesture.position < gesture.face ? -1 : 1
    if (!cubeBusy.value || direction !== cubeDirection.value) alignFace(cubeIndex(gesture.face + direction, current.value.kinds.length))
    cubeOrigin.value = gesture.face; cubeDirection.value = direction
    cubeBusy.value = true; cubePosition.value = gesture.position
  }
  function cubeEnd() {
    if (gesture?.axis === 'horizontal') {
      const position = cubeDestination(gesture, cubeWidth, Date.now())
      turnCube(position, position)
    }
    else gesture = null
  }
  function cubeCancel() {
    if (gesture?.axis === 'horizontal') turnCube(face.value)
    else gesture = null
  }
  function playEntrance() {
    if (entrancePlayed || !alive || !pageReady || !pageVisible
      || !current.value.kinds.every(kind => snapshots.value[kind]?.entries.length)) return
    entrancePlayed = true
    entranceTimer = setTimeout(() => {
      if (!alive || !pageVisible || gesture) return
      cubeOrigin.value = face.value; cubeDirection.value = face.value ? -1 : 1
      alignFace(face.value === 0 ? 1 : face.value - 1)
      cubeBusy.value = true; cubeDuration.value = 0
      cubePosition.value = face.value + (face.value ? -0.09 : 0.09)
      entranceProgress.value = 0; entranceHintVisible.value = true
      entranceTimer = setTimeout(() => {
        if (!alive) return
        entranceProgress.value = 1
        cubeDuration.value = 420; cubePosition.value = face.value + (face.value ? -0.14 : 0.14)
        entranceTimer = setTimeout(() => {
          if (!alive) return
          // An introduction returns to the saved face without persisting a turn.
          cubeDuration.value = 700; cubePosition.value = face.value
          entranceTimer = setTimeout(() => {
            if (!alive) return
            cubeBusy.value = false; cubeDuration.value = 0
            cubePosition.value = face.value; cubeOrigin.value = face.value; cubeDirection.value = 1
            measureLists()
            entranceTimer = setTimeout(() => { entranceHintVisible.value = false }, 1600)
          }, 750)
        }, 550)
      }, 24)
    }, 220)
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
  const capsuleHeight = ref(32)
  const store = createBoardStore({ platform: wx, endpoint: __SHARED_ENDPOINT__ })
  const snapshots = ref(Object.fromEntries(Object.keys(boards).map(kind => [kind, store.read(kind)])))
  const filters = ref(initial.filters)
  const refreshing = ref({})
  const pullRefreshing = ref(false)
  const scrollPositions = {}
  const scrollWindows = ref({})
  const geometry = ref(rowGeometry(wx.getWindowInfo()))
  // Cover a full window before header measurements arrive, plus one partial
  // row. Window resizing recomputes both row height and placeholder count.
  const skeletonRows = computed(() => Array.from({ length: Math.ceil(geometry.value.viewportHeight / geometry.value.rowHeight) + 1 }, (_, index) => index))
  const origins = {}
  const headerOffsets = {}
  const pinnedHeaders = ref({})
  const viewports = {}
  const backTopBoards = ref({})
  const rowRenderers = new Map()
  let measureSerial = 0
  const scrollRequests = new Map()
  const sheet = ref({ open: false, title: '', actions: [], kind: '', mode: '' })
  const capturing = ref(false)
  const emptyCapture = () => ({ open: false, path: '', saving: false, saved: false })
  const capture = ref(emptyCapture())
  const showingFeatureHelp = ref(false)
  const companyDetails = ref({ open: false, name: '', content: '', members: [] })
  // Vant locks its mask, but touches inside popup content can still reach a
  // native scroll-view underneath. Lock every board as well as the page root.
  const backgroundLocked = computed(() => sheet.value.open || companyDetails.value.open
    || showingFeatureHelp.value || capture.value.open || capturing.value)
  const lastAttempt = {}
  let alive = true

  const tr = key => text(copy[key], language.value)
  const labels = computed(() => Object.fromEntries(Object.keys(copy).map(key => [key, tr(key)])))
  const subtitleParts = computed(() => labels.value.subtitle.split(' & '))
  const groupingControl = computed(() => ({
    height: capsuleHeight.value,
    width: capsuleHeight.value * (language.value === 'en' ? 3.75 : 2.5) + 16,
    fontSize: capsuleHeight.value * (language.value === 'en' ? 0.34 : 0.4),
  }))
  const brandTitle = computed(() => {
    const sample = measureBrand(labels.value.name, 32)
    const height = capsuleHeight.value
    const english = language.value === 'en'
    const width = Math.max(1, headerWidth.value - capsuleWidth.value - groupingControl.value.width - headerWidth.value / 750 * (24 + 14))
    if (english) {
      const title = measureBrand(labels.value.name, 32 * Math.min(height * 0.8 / sample.height, width / (sample.width + sample.height * 5.25)))
      return { ...title, subtitleHeight: title.height * 1.25, subtitleFontSize: title.height * 0.5 }
    }
    // Shrink the one-line caption first, then the title if both cannot fit.
    // Reserve 10.88 em for Chinese text, separators, help mark and their gaps.
    const captionEm = 10.88, minimumFontSize = 6.5
    const scale = Math.min(height / sample.height, Math.max(1, width - captionEm * minimumFontSize) / sample.width)
    const title = measureBrand(labels.value.name, 32 * scale * 0.85)
    const subtitleFontSize = Math.max(0, Math.min(12, (width - title.width) / captionEm))
    return { ...title, subtitleHeight: title.height, subtitleFontSize }
  })
  const categoryItems = computed(() => categories.map((item, index) => ({ id: item.id, label: text(item.labels, language.value),
    icon: ['apps-o', 'code', 'photo-o', 'video-o'][index] })))
  const categoryIndex = computed(() => categories.findIndex(item => item.id === category.value))
  const current = computed(() => categoryFor(category.value))
  const tabs = computed(() => current.value.kinds.map(kind => kind === 'epochECI' ? tr('capabilityIndex') : kind.startsWith('artificial') ? tr('tasks') : tr('votes')))
  const filterFor = kind => ({ country: 'all', openness: 'all', ...filters.value[kind] })
  const countriesFor = kind => countryOptions({ entries: Object.values(snapshots.value).flatMap(board => board?.entries || []) }, language.value, filterFor(kind).country)
  function setFilters(filter) {
    filters.value = Object.fromEntries(Object.keys(boards).map(source => [source, { ...filter }]))
    resetScroll(Object.keys(boards))
  }
  // Keep full model data out of the Vue-to-WeChat bridge. Sorting/filtering
  // are cached independently of scroll positions; only window rows are mapped.
  const rankedCards = computed(() => current.value.kinds.map(kind => ({ kind,
    leaderScore: kind === 'epochECI' ? undefined : rankedEntries(snapshots.value[kind], { ...filterFor(kind), grouping: grouping.value })[0]?.score,
    entries: rankedEntries(snapshots.value[kind], { ...filterFor(kind), grouping: grouping.value, query: modelSearchQuery.value }) })))
  const cards = computed(() => rankedCards.value.map(({ kind, entries, leaderScore }, index) => {
    const board = snapshots.value[kind]
    const filter = filterFor(kind)
    const range = rangeFor(kind, entries.length)
    return { kind, title: boardTitle(kind, language.value), index, summary: text(boards[kind].summaries, language.value),
      updated: formatTime(board?.sourceUpdatedAt), fetched: formatTime(board?.fetchedAt), time: formatTime(latestTimestamp(board)),
      count: entries.length,
      // Keep the editing header pinned when a query reduces a long list to a
      // few rows; native scroll views otherwise clamp their offset to zero.
      height: Math.max(entries.length * geometry.value.rowHeight, (modelSearchVisible.value || grouping.value === 'model' && !!modelSearchQuery.value.trim())
        ? Math.max(0, (viewports[kind] || geometry.value.viewportHeight) - geometry.value.rowHeight - (entries.length ? 0 : 200)) : 0),
      rowHeight: geometry.value.rowHeight,
      rows: renderRows(kind, entries, range, leaderScore),
      searchStyle: modelSearchVisible.value ? 'left:0px;right:0px;' : searchOrigins.value[kind] || 'left:50%;right:50%;',
      hasBoard: !!board, filtered: filter.country !== 'all' || filter.openness !== 'all' || grouping.value === 'model' && !!modelSearchQuery.value.trim(),
      countryFiltered: filter.country !== 'all', sourceFiltered: filter.openness !== 'all',
      loading: !!refreshing.value[kind],
      headerPinned: !!pinnedHeaders.value[kind],
    }
  }))
  const backToTop = computed(() => !!backTopBoards.value[current.value.kinds[face.value]])

  function renderRows(kind, entries, range, leaderScore) {
    if (!rowRenderers.has(kind)) rowRenderers.set(kind, createRowRenderer((entry, entries) =>
      rowView(entry, { company: grouping.value === 'company', dark: dark.value, details: false,
        language: language.value, category: category.value, kind, leaderScore: rankedCards.value.find(card => card.kind === kind)?.leaderScore })))
    return rowRenderers.get(kind)({ entries, ...range, rowHeight: geometry.value.rowHeight,
      variant: `${grouping.value}:${dark.value}:${language.value}:${category.value}:${leaderScore}` })
  }

  function rangeFor(kind, count, force = false) {
    return resolveRowWindow({ count, scrollTop: scrollPositions[kind] || 0, origin: origins[kind] || 0,
      geometry: { ...geometry.value, viewportHeight: viewports[kind] || geometry.value.viewportHeight },
      ...scrollWindows.value[kind], force })
  }
  function syncWindow(kind, force = false) {
    const card = rankedCards.value.find(card => card.kind === kind)
    if (!card) return
    const pinned = Number.isFinite(headerOffsets[kind]) && (scrollPositions[kind] || 0) >= headerOffsets[kind]
    if (!!pinnedHeaders.value[kind] !== pinned) {
      pinnedHeaders.value = { ...pinnedHeaders.value, [kind]: pinned }
      // The compact sticky header changes the rows' natural origin.
      measureLists()
    }
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
      requestScroll(kind, 0)
      syncWindow(kind, true)
    }
    measureLists()
  }
  function requestScroll(kind, top) {
    if (kind === current.value.kinds[face.value]) { cancelSourceTabsSync(); updateSourceTabs(top) }
    // A scroll-top binding inside the changing cards loop can replay an old
    // target on each virtual-window render. Command only explicit navigation.
    const request = { top, pending: true }
    scrollRequests.set(kind, request)
    const run = () => {
      if (!alive || scrollRequests.get(kind) !== request || !wx.createSelectorQuery) return
      const query = wx.createSelectorQuery()
      query.select(`#board-scroll-${kind}`).node()
      query.exec(results => {
        if (!alive || scrollRequests.get(kind) !== request) return
        results[0]?.node?.scrollTo({ top, animated: false })
        if (kind === current.value.kinds[face.value]) syncSourceTabsAfterScroll(kind)
      })
    }
    if (wx.nextTick) wx.nextTick(run)
    else run()
  }
  function measureLists() {
    const serial = ++measureSerial
    const kinds = current.value.kinds
    const run = () => {
      if (!alive || cubeBusy.value || serial !== measureSerial || !wx.createSelectorQuery) return
      const query = wx.createSelectorQuery()
      for (const kind of kinds) {
        query.select(`#board-scroll-${kind}`).fields({ rect: true, size: true, scrollOffset: true })
        query.select(`#rows-${kind}`).boundingClientRect()
      }
      // A non-sticky marker keeps the threshold stable when header height changes.
      for (const kind of kinds) query.select(`#head-anchor-${kind}`).boundingClientRect()
      query.exec(results => {
        if (!alive || cubeBusy.value || serial !== measureSerial) return
        kinds.forEach((kind, index) => {
          const viewport = results[index * 2], rows = results[index * 2 + 1]
          if (!viewport?.height || !rows || !Number.isFinite(rows.top) || !Number.isFinite(viewport.top)
            || !Number.isFinite(viewport.scrollTop)) return
          // Rectangles and native scroll offset belong to the same query snapshot.
          // The latest scroll event may already be far ahead when this callback runs.
          origins[kind] = rows.top - viewport.top + viewport.scrollTop
          viewports[kind] = viewport.height
          const anchor = results[kinds.length * 2 + index]
          if (Number.isFinite(anchor?.top)) headerOffsets[kind] = anchor.top - viewport.top + viewport.scrollTop
          syncWindow(kind, true)
        })
      })
    }
    if (wx.nextTick) wx.nextTick(run)
    else run()
  }

  function measureSourceTabs() {
    if (!wx.createSelectorQuery) return
    const query = wx.createSelectorQuery()
    query.select('.source-tabs').fields({ size: true })
    query.exec(results => {
      if (!alive || !results[0]?.height) return
      sourceTabsHeight.value = results[0].height
      updateSourceTabs(scrollPositions[current.value.kinds[face.value]] || 0)
      measureLists()
    })
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
    capsuleHeight.value = menu.height || menu.bottom - menu.top
    navHeight.value = menu.bottom + 8
    capsuleWidth.value = window.windowWidth - menu.left + 8
    geometry.value = rowGeometry(window)
    measureSourceTabs()
    for (const kind of current.value.kinds) syncWindow(kind, true)
    measureLists()
  }
  measure()
  onResize(measure)
  function updateTheme() {
    wx.setNavigationBarColor({ frontColor: dark.value ? '#ffffff' : '#000000', backgroundColor: dark.value ? '#101216' : '#f4f5f7' })
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
        playEntrance()
      }
    }
  }
  const refreshCategory = () => Promise.all(current.value.kinds.map(refreshKind))
  async function pullRefresh() {
    if (backgroundLocked.value || pullRefreshing.value) return
    pullRefreshing.value = true
    try { await refreshCategory() } finally { pullRefreshing.value = false }
  }
  onLoad(async () => { await refreshCategory(); playEntrance() })
  onReady(() => { pageReady = true; measureSourceTabs(); playEntrance() })
  onShow(() => {
    pageVisible = true
    syncSourceTabsAfterScroll(current.value.kinds[face.value])
    if (languageMode.value === 'system') {
      const next = systemLanguage(wx.getAppBaseInfo?.().language)
      if (next !== language.value) { language.value = next; measureLists() }
    }
    for (const kind of current.value.kinds) if (!lastAttempt[kind] || Date.now() - lastAttempt[kind] > 600000) refreshKind(kind)
    playEntrance()
  })
  onHide(() => { pageVisible = false; blurModelSearch(); clearTimeout(searchExpandTimer); stopCube(); cancelSourceTabsSync() })
  onUnload(() => { blurModelSearch(); clearTimeout(searchExpandTimer); stopCube(); cancelSourceTabsSync(); alive = false; measureSerial++; scrollRequests.clear(); rowRenderers.clear(); store.dispose(); wx.offThemeChange?.(themeListener)
    if (!capture.value.saving) removeScreenshot(wx, capture.value.path)
    if (capturing.value || capture.value.saving) wx.hideLoading() })
  onShareAppMessage(() => ({ title: `${tabs.value[face.value]}｜${tr('tagline')}`,
    path: sharePath(preferencesSnapshot(), dark.value ? 'dark' : 'light') }))

  function selectCategory(event) {
    const id = event.currentTarget.dataset.id
    if (!categories.some(item => item.id === id)) return
    if (id === category.value) {
      const now = Date.now()
      if (lastCategoryTap?.id === id && lastCategoryTap.face === face.value && now - lastCategoryTap.time <= 300) {
        stopCube(); entrancePlayed = true; top()
      } else {
        lastCategoryTap = { id, face: face.value, time: now }
      }
      return
    }
    blurModelSearch(); stopCube(); entrancePlayed = true
    category.value = id; face.value = Math.min(face.value, current.value.kinds.length - 1); cubePosition.value = face.value; cubeOrigin.value = face.value; cubeDirection.value = 1; rowRenderers.clear(); resetScroll(); persist(); refreshCategory()
  }
  function selectGrouping(event) { blurModelSearch(); stopCube(); entrancePlayed = true; grouping.value = event.currentTarget.dataset.id; resetScroll(); persist() }
  function selectFace(event) {
    if (Date.now() < suppressTapUntil) return
    const destination = Number(event.currentTarget.dataset.index)
    if (Number.isInteger(destination) && destination >= 0 && destination < current.value.kinds.length) { entrancePlayed = true; turnCube(destination) }
  }
  function changeFace(event) { turnCube(Math.max(0, Math.min(current.value.kinds.length - 1, Number(event.detail.current) || 0))) }
  function scroll(event) {
    const kind = event.currentTarget.dataset.kind
    if (!hasOwn(boards, kind)) return
    const top = Math.max(0, Number(event.detail.scrollTop) || 0)
    const request = scrollRequests.get(kind)
    if (request?.pending && Math.abs(top - request.top) > 1) {
      if (kind === current.value.kinds[face.value]) syncSourceTabsAfterScroll(kind)
      return
    }
    if (gesture && gesture.axis !== 'horizontal' && kind === current.value.kinds[face.value] && Math.abs(top - gesture.scrollTop) >= 12) {
      // Native scrolling wins before horizontal intent is locked. Small native
      // offsets already queued by a slanted swipe must not cancel a cube drag.
      gesture.axis = 'vertical'; gesture.position = face.value
      cubeBusy.value = false; cubeDuration.value = 0; cubePosition.value = face.value; cubeOrigin.value = face.value; cubeDirection.value = 1
    }
    scrollPositions[kind] = top
    if (kind === current.value.kinds[face.value]) { updateSourceTabs(top); syncSourceTabsAfterScroll(kind) }
    const show = top > 400
    if (!!backTopBoards.value[kind] !== show) backTopBoards.value = { ...backTopBoards.value, [kind]: show }
    // Native events, not delayed rAF: fast flicks must never outrun the window.
    syncWindow(kind)
  }
  function top() {
    const kind = current.value.kinds[face.value]
    requestScroll(kind, 0)
  }
  function showSheet(mode, kind, actions, title) { stopCube(); entrancePlayed = true; sheet.value = { open: true, mode, kind, actions, title } }
  function selectedActions(actions, selected) {
    return actions.map(action => ({ ...action, color: action.value === selected ? (dark.value ? '#d1dce8' : '#414d5c') : '' }))
  }
  function filterMenu(event) {
    const { kind, mode } = event.currentTarget.dataset
    const filter = filterFor(kind)
    const actions = mode === 'country' ? countriesFor(kind)
      : ['all', 'open', 'closed', 'unknown'].map(value => ({ value, label: tr(value) }))
    showSheet(mode, kind, selectedActions(actions.map(action => ({ name: action.label, value: action.value })), filter[mode]),
      tr(mode === 'country' ? 'country' : 'source'))
  }
  function clearFilters() {
    modelSearchQuery.value = ''
    setFilters({ country: 'all', openness: 'all' }); persist()
  }
  function blurModelSearch() {
    clearingModelSearch = false
    searchSerial++
    clearTimeout(searchFocusTimer)
    clearTimeout(searchExpandTimer)
    clearTimeout(searchBlurTimer)
    modelSearchFocused.value = false
    modelSearchOpen.value = false
  }
  function deferModelSearchBlur() {
    modelSearchFocused.value = false
    clearTimeout(searchFocusTimer)
    clearTimeout(searchBlurTimer)
    // Native blur may arrive before or after the Clear tap. Keep this gesture
    // separate from leaving search, until the input confirms its focus again.
    if (clearingModelSearch) { restoreModelSearchFocus(); return }
    // Let Clear/Cancel receive their tap before removing the native input.
    searchBlurTimer = setTimeout(() => {
      // Keep the query and results visible after dismissing the keyboard.
      if (!modelSearchQuery.value.trim()) blurModelSearch()
    }, 80)
  }
  function focusModelSearch() {
    if (!modelSearchVisible.value) return
    clearingModelSearch = false
    clearTimeout(searchBlurTimer)
    modelSearchFocused.value = true
  }
  function restoreModelSearchFocus() {
    clearTimeout(searchFocusTimer)
    modelSearchFocused.value = false
    const serial = searchSerial
    searchFocusTimer = setTimeout(() => {
      if (alive && serial === searchSerial && modelSearchVisible.value) modelSearchFocused.value = true
    }, 0)
  }
  function beginModelSearchClear() {
    if (!modelSearchVisible.value) return
    clearingModelSearch = true
    clearTimeout(searchBlurTimer)
  }
  function cancelModelSearchClear() {
    clearingModelSearch = false
    clearTimeout(searchFocusTimer)
    if (!modelSearchFocused.value) deferModelSearchBlur()
  }
  function openModelSearch() {
    if (grouping.value !== 'model' || cubeBusy.value || backgroundLocked.value) return
    stopCube(); entrancePlayed = true
    clearTimeout(searchBlurTimer)
    const serial = ++searchSerial
    const expand = () => {
      if (!alive || serial !== searchSerial || grouping.value !== 'model') return
      modelSearchOpen.value = true
      clearTimeout(searchFocusTimer)
      searchFocusTimer = setTimeout(() => {
        if (alive && serial === searchSerial && modelSearchVisible.value) modelSearchFocused.value = true
      }, 320)
    }
    if (modelSearchOpen.value) { expand(); return }
    const query = wx.createSelectorQuery()
    for (const kind of current.value.kinds) {
      query.select(`#table-head-${kind}`).boundingClientRect()
      query.select(`#model-filter-${kind}`).boundingClientRect()
    }
    query.exec(rects => {
      if (!alive || serial !== searchSerial) return
      searchOrigins.value = Object.fromEntries(current.value.kinds.flatMap((kind, index) => {
        const head = rects[index * 2], icon = rects[index * 2 + 1]
        if (!head?.width || !icon?.width) return []
        return [[kind, `left:${Math.max(0, icon.left - head.left)}px;right:${Math.max(0, head.right - icon.right)}px;`]]
      }))
      // Paint the icon-sized starting bounds before expanding both edges.
      clearTimeout(searchExpandTimer)
      searchExpandTimer = setTimeout(expand, 24)
    })
  }
  function inputModelSearch(event) {
    const value = String(event.detail.value || '')
    if (value === modelSearchQuery.value) return
    modelSearchQuery.value = value
    for (const kind of current.value.kinds) {
      const top = pinnedHeaders.value[kind] ? headerOffsets[kind] || 0 : 0
      scrollPositions[kind] = top
      backTopBoards.value = { ...backTopBoards.value, [kind]: false }
      requestScroll(kind, top)
      syncWindow(kind, true)
    }
    measureLists()
  }
  function clearModelSearch() {
    if (!modelSearchVisible.value) return
    beginModelSearchClear()
    inputModelSearch({ detail: { value: '' } })
    restoreModelSearchFocus()
  }
  function closeModelSearch() {
    blurModelSearch(); clearTimeout(searchExpandTimer)
    modelSearchOpen.value = false
    inputModelSearch({ detail: { value: '' } })
    wx.hideKeyboard?.()
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
      setFilters({ ...filterFor(sheet.value.kind), [sheet.value.mode]: action.value })
      // Keep the retained popup current while it closes, so reopening never
      // starts with the previous selection's highlight.
      sheet.value = { ...sheet.value, actions: selectedActions(sheet.value.actions, action.value) }
    }
    if (sheet.value.mode === 'settings') measureLists()
    sheet.value = { ...sheet.value, open: false }; persist()
  }
  function closeSheet() { sheet.value = { ...sheet.value, open: false } }
  function countryHelp() {
    wx.showModal({ title: tr('unknownCountryTitle'), content: tr('unknownCountryExplanation'), showCancel: false, confirmText: 'OK' })
  }
  function sourceHelp(event) {
    const kind = event.currentTarget.dataset.kind
    const board = snapshots.value[kind]
    wx.showModal({ title: boardTitle(kind, language.value),
      content: `${text(boards[kind].summaries, language.value)}\n\n${tr('updated')}: ${formatTime(latestTimestamp(board))}\n\n${boards[kind].url}`,
      showCancel: false })
  }
  function copyText(data) {
    wx.setClipboardData({ data, success: () => wx.showToast({ title: tr('copied'), icon: 'success' }) })
  }
  function copyPurchaseLink(event) {
    if (grouping.value !== 'company' || cubeBusy.value || Date.now() < suppressTapUntil) return
    const { kind, rank, purchase } = event.currentTarget.dataset
    if (!['codingPlan', 'payAsYouGo'].includes(purchase)) return
    const entry = rankedCards.value.find(card => card.kind === kind)?.entries.find(row => row.rank === Number(rank))
    if (!entry) return
    // Resolve locally rather than accepting an arbitrary URL from page data.
    const links = purchaseLinks(entry.organization, { modelName: entry.name, category: category.value })
    const link = preferredPurchaseLink(links[purchase], language.value)
    if (!link) return
    // WeChat has no API for opening arbitrary URLs in the system browser.
    wx.setClipboardData({ data: link.url,
      success: () => wx.showToast({ title: tr('copied'), icon: 'none' }),
      fail: () => wx.showToast({ title: tr('copyLinkFailed'), icon: 'none' }) })
  }
  function copyBoardTitle(event) {
    if (cubeBusy.value || Date.now() < suppressTapUntil) return
    const card = cards.value.find(card => card.kind === event.currentTarget.dataset.kind)
    if (card) copyText(card.title)
  }
  function rowDetails(event) {
    if (cubeBusy.value || Date.now() < suppressTapUntil) return
    const { kind, rank } = event.currentTarget.dataset
    const entry = rankedCards.value.find(card => card.kind === kind)?.entries.find(row => row.rank === Number(rank))
    if (!entry) return
    if (grouping.value === 'model') {
      copyText(entry.name)
      return
    }
    const row = rowView(entry, { company: grouping.value === 'company', dark: dark.value, kind })
    const content = row.components.length ? tr('strongest') : row.name
    stopCube(); entrancePlayed = true
    companyDetails.value = { open: true, name: row.name, content, members: row.components }
  }
  function attributeHint(event) {
    if (cubeBusy.value || backgroundLocked.value || Date.now() < suppressTapUntil) return
    const { kind, rank, attribute } = event.currentTarget.dataset
    if (kind !== current.value.kinds[face.value] || !['country', 'openness'].includes(attribute)) return
    if (attribute === 'openness' && grouping.value === 'company') return
    const entry = rankedCards.value.find(card => card.kind === kind)?.entries.find(row => row.rank === Number(rank))
    if (!entry) return
    const title = attribute === 'country' ? countryName(countryCode(entry), language.value)
      : tr(entry.openness === 'open' ? 'open' : entry.openness === 'closed' ? 'closed' : 'unknown')
    wx.showToast({ title, icon: 'none', duration: 1800 })
  }
  function closeCompanyDetails() {
    companyDetails.value = { ...companyDetails.value, open: false }
  }
  function copyCompanyName() {
    const name = companyDetails.value.name
    closeCompanyDetails()
    copyText(name)
  }
  async function screenshot() {
    if (capturing.value || capture.value.saving) return
    if (!current.value.kinds.some(kind => snapshots.value[kind])) {
      wx.showToast({ title: tr('noBoard'), icon: 'none' }); return
    }
    stopCube(); entrancePlayed = true
    capturing.value = true
    wx.showLoading({ title: tr('generating'), mask: true })
    let failed = false
    try {
      // Freeze the current filters/theme and export complete lists rather than
      // the rows currently mounted in the scroll window.
      const model = { labels: { ...labels.value }, dark: dark.value, grouping: grouping.value,
        groupingLabel: tr(grouping.value === 'company' ? 'companies' : 'models'),
        categoryLabel: text(current.value.labels, language.value),
        boards: current.value.kinds.map((kind, index) => {
          const board = snapshots.value[kind], filter = filterFor(kind)
          const country = filter.country === 'all' ? tr('all') : countryName(filter.country, language.value)
          return { title: boardTitle(kind, language.value), tab: tabs.value[index],
            summary: text(boards[kind].summaries, language.value), time: formatTime(latestTimestamp(board)),
            filterLabel: `${tr('country')}: ${country} · ${tr('source')}: ${tr(filter.openness)}`,
            empty: tr(board ? 'empty' : 'noBoard'),
            rows: rankedCards.value[index].entries.map(entry =>
              rowView(entry, { company: grouping.value === 'company', dark: dark.value, details: false, kind: rankedCards.value[index].kind, leaderScore: rankedCards.value[index].leaderScore })) }
        }) }
      const canvas = await new Promise((resolve, reject) => {
        wx.createSelectorQuery().select('#leaderboard-export').fields({ node: true }).exec(result => {
          if (result?.[0]?.node) resolve(result[0].node)
          else reject(new Error('Canvas unavailable'))
        })
      })
      const path = await exportScreenshot({ platform: wx, canvas, model, isActive: () => alive,
        progress: percent => wx.showLoading({ title: `${tr('generating')} ${percent}%`, mask: true }) })
      if (alive) capture.value = { ...emptyCapture(), open: true, path }
      else removeScreenshot(wx, path)
    } catch (error) {
      console.warn('Leaderboard screenshot failed', error)
      failed = true
    } finally { capturing.value = false; if (alive) wx.hideLoading() }
    if (alive && failed) wx.showToast({ title: tr('screenshotFailed'), icon: 'none' })
  }
  function closeCapture() {
    if (capture.value.saving) return
    removeScreenshot(wx, capture.value.path)
    capture.value = emptyCapture()
  }
  function previewScreenshot() {
    const path = capture.value.path
    if (path) wx.previewImage({ urls: [path], current: path })
  }
  async function saveScreenshot() {
    if (capture.value.saving || capture.value.saved || !capture.value.path) return
    capture.value = { ...capture.value, saving: true }
    let failed
    try {
      wx.showLoading({ title: tr('savingImages'), mask: true })
      await saveScreenshotImage(wx, capture.value.path)
      capture.value = { ...capture.value, saved: true }
    } catch (error) {
      failed = error
    } finally {
      capture.value = { ...capture.value, saving: false }
      if (alive) wx.hideLoading()
      else removeScreenshot(wx, capture.value.path)
    }
    if (!alive) return
    if (failed) {
      if (/auth.*(?:deny|denied)|permission/i.test(failed?.errMsg || '')) {
        wx.showModal({ title: tr('screenshot'), content: tr('photoPermission'), confirmText: tr('settings'),
          success: result => { if (result.confirm) wx.openSetting({}) } })
      } else wx.showToast({ title: tr('saveFailed'), icon: 'none' })
    } else wx.showToast({ title: tr('savedImages'), icon: 'success' })
  }
  const about = () => wx.navigateTo({ url: sharePath(preferencesSnapshot(), dark.value ? 'dark' : 'light', '/pages/about/index') })
  const quotaHelpContent = computed(() => tr('quotaHelp'))
  const quotaHelp = () => { stopCube(); entrancePlayed = true; showingFeatureHelp.value = true }
  const closeFeatureHelp = () => { showingFeatureHelp.value = false }
  const copyDesktopLink = () => { closeFeatureHelp(); copyText(desktopDownloadURL) }
  const refreshTap = event => refreshKind(event.currentTarget.dataset.kind)
  return { labels, subtitleParts, brandTitle, groupingControl, categoryItems, categoryIndex, category, grouping, face, dark, cards, tabs, backToTop, skeletonRows,
    modelSearchQuery, modelSearchVisible, modelSearchFocused, openModelSearch, inputModelSearch, beginModelSearchClear, cancelModelSearchClear, clearModelSearch, closeModelSearch, blurModelSearch, deferModelSearchBlur, focusModelSearch,
    statusBar, navHeight, headerTop, capsuleWidth, sheet, backgroundLocked,
    cubeFaces, sourceSelection, sourceTabsStyle, sourceTabsExtent, cubeViewportStyle,
    cubePosition, cubeDuration, cubeBusy, cubeDragging, entranceStyle, entranceHintVisible,
    cubeStart, cubeMove, cubeEnd, cubeCancel, attributeHint,
    selectCategory, selectGrouping, selectFace, changeFace, scroll, top, filterMenu,
    clearFilters, preferences, sheetSelect, closeSheet, sourceHelp, countryHelp, copyBoardTitle, copyPurchaseLink, rowDetails, companyDetails, closeCompanyDetails, copyCompanyName, about,
    quotaHelp, quotaHelpContent, showingFeatureHelp, closeFeatureHelp, copyDesktopLink, refreshTap, refreshCategory, pullRefresh, pullRefreshing,
    capturing, capture, screenshot, closeCapture, previewScreenshot, saveScreenshot }
}, { canShareToOthers: true })
