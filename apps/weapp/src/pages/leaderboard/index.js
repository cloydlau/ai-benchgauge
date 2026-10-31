import { sourceAgreement } from '../../core/source-agreement.js'
import { isArenaDatasetBoard } from '../../core/arena-attribution.js'
import { definePage, ref, computed, onLoad, onReady, onShow, onHide, onUnload, onShareAppMessage, onResize } from '@vue-mini/core'
import { boards, categories, categoryFor, boardVariants, variantLabels, variantBase, normalizeVariants, copy, text, languages, boardTitle, mobileBoardHeading, hasOwn, desktopDownloadURL } from '../../core/catalog.js'
import { rankedEntries, rowView, supportsAACost, supportsAASpeed, isAAImageCost, isAAVideoCost, isErrorRate, isPriceBoard, countryCode, countryName, countryFlag, countryFlagImage, countryOptions, formatTime, contentTimestamp } from '../../core/leaderboard.js'
import { opennessIcon, opennessColor } from '../../core/openness-icon.js'
import { sourceTabTheme, sourceTabLogo } from '../../core/source-tab-theme.js'
import { leaderboardDistribution } from '../../../../../fc/distributions.mjs'
import { createBoardStore } from '../../services/boards.js'
import { shouldAutoRefresh } from '../../core/freshness.js'
import { createTimestampPolish } from '../../core/timestamp-polish.js'
import { createMetricGuide } from '../../core/metric-guide.js'
import { rowGeometry, resolveRowWindow, createRowRenderer } from '../../core/row-window.js'
import { exportScreenshot, removeScreenshot, saveScreenshotImage } from '../../services/screenshot.js'
import { cubeIndex, cubeTarget, cubeNavigation, cubeRenderedFace, cubeTabPosition, cubeGesture, moveCubeGesture, cubeDestination, matchingScroll, isBackSwipe } from '../../core/cube.js'
import { createBrandMeasurer, createSubtitleMeasurer } from '../../core/brand-title.js'
import { pagePreferences, sharePath, systemLanguage } from '../../core/share-state.js'
import { purchaseLinks, preferredPurchaseLink } from '../../core/purchase-links.js'
import { visibleBoardKinds, normalizeBoardSelections, selectedBoardFace } from '../../core/board-selection.js'
import { boardFaceStyle, normalizeBoardTransition } from '../../core/board-transition.js'

definePage(query => {
  const saved = (() => { try { return wx.getStorageSync('benchgauge.preferences') || {} } catch { return {} } })()
  const initial = pagePreferences(query, saved, wx.getAppBaseInfo?.().language)
  const language = ref(initial.language)
  const languageMode = ref(initial.languageMode)
  const category = ref(initial.category)
  const boardSelections = ref(initial.boardSelections || {})
  const variants = ref(normalizeVariants(initial.variants))
  const boardTransition = ref(normalizeBoardTransition(initial.boardTransition))
  const grouping = ref(initial.category === 'price' ? 'model' : initial.grouping)
  const expandedBoards = ref({})
  const configurationRequired = ref({})
  // Share the input interaction while retaining a separate query per grouping.
  const searchQueries = { model: '', company: '' }
  const modelSearchQuery = ref('')
  const modelSearchOpen = ref(false)
  const modelSearchFocused = ref(false)
  const modelSearchVisible = computed(() => modelSearchOpen.value)
  const searchOrigins = ref({})
  let searchFocusTimer, searchExpandTimer, searchBlurTimer, searchSerial = 0
  let clearingModelSearch = false
  const face = ref(initial.face)
  const sourceTabsHeight = ref(42)
  const sourceTabsOffset = ref(0)
  const cubeClipTop = ref(null)
  const sourceTabsExtent = computed(() => current.value.kinds.length > 1 ? sourceTabsHeight.value + 8 : 0)
  const cubeViewportStyle = computed(() => `--cube-top:${cubeClipTop.value ?? Math.max(0, sourceTabsExtent.value - sourceTabsOffset.value)}px;--cube-layout-duration:${cubeDuration.value}ms;`)
  // Keep the tab transition armed while cube faces are prepared at 0ms.
  // Separate native style updates must never move the highlight with a 0ms duration.
  const sourceTabsStyle = computed(() => `transform:translateY(-${sourceTabsOffset.value}px);pointer-events:${sourceTabsOffset.value >= sourceTabsExtent.value ? 'none' : 'auto'};--source-selected-foreground:${selectedSourceTheme.value.foreground};`)
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
        if (request?.preparing && !request.ready) return
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
  const cubeWaiting = ref(false)
  const entranceProgress = ref(1)
  const entranceHintVisible = ref(false)
  const entranceStyle = computed(() => entranceProgress.value === 1 ? 'transition-duration:420ms;opacity:1;transform:none;'
    : 'transition-duration:0ms;opacity:0.65;transform:translateY(4px) scale(0.995);')
  const cubeFaces = computed(() => current.value.kinds.map((_, index) => {
    const position = cubeRenderedFace(index, cubeOrigin.value, cubeDirection.value, current.value.kinds.length)
    const displayed = cubeWaiting.value ? cubeOrigin.value : cubePosition.value
    return { style: boardFaceStyle(boardTransition.value, position, displayed, cubeDuration.value, cubeBusy.value, cubeOrigin.value, cubeDirection.value),
      shade: boardTransition.value === 'cube' ? Math.abs(position - displayed) * 0.18 : 0 }
  }))
  const sourceDragIndex = ref(null)
  const categoryDragIndex = ref(null)
  // The logical destination starts loading immediately. Selected labels wait
  // for the visual turn; the background below follows its fractional progress.
  const sourceTabIndex = computed(() => sourceDragIndex.value ?? (cubeBusy.value && cubeDuration.value === 0 ? cubeOrigin.value : face.value))
  const selectedSourceTheme = computed(() => sourceTabTheme(current.value.kinds[sourceTabIndex.value], dark.value))
  const sourceTabWidth = computed(() => `calc((100% - ${(current.value.kinds.length - 1) * 12}rpx) / ${current.value.kinds.length})`)
  const sourceSelection = computed(() => {
    const tracking = sourceDragIndex.value == null && cubeBusy.value && !entranceHintVisible.value
    const position = tracking ? cubeTabPosition(cubeWaiting.value ? cubeOrigin.value : cubePosition.value,
      cubeOrigin.value, cubeDirection.value, current.value.kinds.length) : sourceTabIndex.value
    // Finger tracking has no easing; preparation, catch-up and release use the
    // very same duration as the visible faces, including a cancelled turn.
    const motion = tracking ? `--source-position-duration:${cubeDuration.value}ms;--source-position-easing:${boardTransition.value === 'slide' ? 'cubic-bezier(.22,.68,0,1)' : 'ease-in-out'};` : ''
    return `width:${sourceTabWidth.value};transform:translateX(${position * 100}%) translateX(${position * 12}rpx);background-color:${selectedSourceTheme.value.background};${motion}`
  })
  let tabGesture
  let tabSerial = 0
  let tabSuppressTapUntil = 0
  function cancelTabDrag() {
    tabSerial++; tabGesture = null
    sourceDragIndex.value = null; categoryDragIndex.value = null
  }
  function tabStart(event) {
    cancelTabDrag()
    const point = touchPoint(event), kind = event.currentTarget.dataset.tabs
    if (!point || event.touches?.length !== 1 || backgroundLocked.value || modelSearchFocused.value) return
    if (kind === 'source' && current.value.kinds.length < 2) return
    const started = { kind, x: point.clientX, y: point.clientY, lastX: point.clientX, axis: '', rect: null }
    tabGesture = started
    const serial = tabSerial
    wx.createSelectorQuery().select(kind === 'category' ? '.category-tabs' : '.source-tabs').boundingClientRect().exec(results => {
      if (serial !== tabSerial || tabGesture !== started) return
      const rect = results[0]
      if (rect?.width > 0) { started.rect = rect; previewTabDrag(started) }
    })
  }
  function previewTabDrag(drag) {
    if (drag.axis !== 'horizontal' || !drag.rect) return
    const count = drag.kind === 'category' ? categories.length : current.value.kinds.length
    const index = Math.max(0, Math.min(count - 1, Math.floor((drag.lastX - drag.rect.left) / drag.rect.width * count)))
    if (drag.kind === 'category') categoryDragIndex.value = index
    else sourceDragIndex.value = index
  }
  function tabMove(event) {
    const point = touchPoint(event), drag = tabGesture
    if (!drag || !point) return
    if (event.touches?.length !== 1) { cancelTabDrag(); return }
    const dx = point.clientX - drag.x, dy = point.clientY - drag.y
    if (!drag.axis) {
      if (isBackSwipe(drag.x, dx)) drag.axis = 'navigation'
      else if (Math.abs(dx) >= 8 && Math.abs(dx) > Math.abs(dy) * 1.25) {
        stopCube(true); entrancePlayed = true; drag.axis = 'horizontal'
      }
      else if (Math.abs(dy) >= 8) drag.axis = 'vertical'
    }
    drag.lastX = point.clientX
    if (drag.axis === 'navigation') {
      tabSuppressTapUntil = suppressTapUntil = Date.now() + 400
      return
    }
    if (drag.axis === 'horizontal') {
      tabSuppressTapUntil = suppressTapUntil = Date.now() + 400
      lastCategoryTap = null
      previewTabDrag(drag)
    }
  }
  function tabEnd(event) {
    if (event.touches?.length) { cancelTabDrag(); return }
    const drag = tabGesture, point = touchPoint(event)
    if (drag?.axis === 'horizontal' && point) { drag.lastX = point.clientX; previewTabDrag(drag) }
    const destination = drag?.kind === 'category' ? categoryDragIndex.value : sourceDragIndex.value
    cancelTabDrag()
    if (drag?.axis !== 'horizontal' || destination == null || backgroundLocked.value) return
    tabSuppressTapUntil = suppressTapUntil = Date.now() + 400
    if (drag.kind === 'category') {
      if (enabledCategories.value[destination].id !== category.value) changeCategory(enabledCategories.value[destination].id)
    } else { entrancePlayed = true; turnCube(destination) }
  }
  let gesture, cubeTimer, entranceTimer, entrancePlayed = false
  let preparedScroll, cubeTurnSerial = 0
  let pageReady = false, pageVisible = false
  const polishingKind = ref(null)
  const metricGuideKind = ref(null)
  const metricAvailable = kind => supportsAACost(kind)
  const costTitle = kind => kind === 'openRouterUsage' ? (language.value === 'en' ? 'Price' : language.value === 'zh-TW' ? '價格' : '价格') : (language.value === 'en' ? 'Cost' : '成本')
  const metricGuide = createMetricGuide({ supports: metricAvailable,
    read: () => { const value = wx.getStorageSync('benchgauge.metricGuideSeen'); return Array.isArray(value) ? value : [] },
    write: value => wx.setStorageSync('benchgauge.metricGuideSeen', value), show: value => { metricGuideKind.value = value },
    readyNow: kind => alive && pageReady && pageVisible && !cubeBusy.value && !modelSearchVisible.value
      && current.value.kinds[face.value] === kind && !refreshing.value[kind] && (!!snapshots.value[kind] || lastAttempt[kind] != null),
  })
  const timestampPolish = createTimestampPolish(kind => { polishingKind.value = kind })
  function syncTimestampPolish() {
    const kind = current.value.kinds[face.value], board = snapshots.value[kind]
    const hasDate = Number.isFinite(Date.parse(board?.sourceUpdatedAt)) || Number.isFinite(Date.parse(board?.fetchedAt))
    timestampPolish.update(kind, alive && pageReady && pageVisible && kind !== 'cloudbaseUsage' && hasDate && !refreshing.value[kind])
    metricGuide.update(kind, alive && pageReady && pageVisible && !cubeBusy.value && !modelSearchVisible.value && !refreshing.value[kind] && (!!board || lastAttempt[kind] != null))
  }
  let cubeWidth = 375
  let suppressTapUntil = 0
  let lastCategoryTap = null
  function stopCube(keepTabDrag = false) {
    if (!keepTabDrag) cancelTabDrag()
    lastCategoryTap = null
    cubeDragging.value = false
    cubeWaiting.value = false; preparedScroll = null; queuedCubeFace = null; cubeTurnSerial++
    cubeClipTop.value = null
    for (const [kind, request] of scrollRequests) if (request.preparing && !request.ready) {
      clearTimeout(request.timer)
      scrollRequests.delete(kind)
    }
    clearTimeout(cubeTimer); clearTimeout(entranceTimer)
    gesture = null; cubeDuration.value = 0; cubeBusy.value = false; cubePosition.value = face.value; cubeOrigin.value = face.value; cubeDirection.value = 1
    entranceProgress.value = 1; entranceHintVisible.value = false
  }
  function alignFace(destination) {
    if (destination === face.value) return
    const from = current.value.kinds[face.value], to = current.value.kinds[destination]
    const count = visibleCards.value[destination].entries.length
    const target = matchingScroll({ scrollTop: scrollPositions[from] || 0,
      origin: origins[from] || 0, nextOrigin: origins[to] || 0, rowHeight: geometry.value.rowHeight, count })
    scrollPositions[to] = target
    const request = requestScroll(to, target, true)
    backTopBoards.value = { ...backTopBoards.value, [to]: target > 400 }
    syncWindow(to, true)
    return request
  }
  function prepareCubeFace(destination) {
    preparedScroll = alignFace(destination)
    cubeWaiting.value = !!preparedScroll && !preparedScroll.ready
    const request = preparedScroll
    whenScrollReady(request, () => {
      if (!alive || preparedScroll !== request) return
      if (request?.failed) {
        face.value = cubeIndex(cubeOrigin.value, current.value.kinds.length)
        stopCube(); updateSourceTabs(scrollPositions[current.value.kinds[face.value]] || 0); persist()
        syncTimestampPolish()
        return
      }
      // A quick swipe can arrive before the hidden native scroll-view settles.
      // Catch up smoothly instead of exposing its old rows mid-turn.
      if (cubeWaiting.value && cubeDragging.value) cubeDuration.value = 120
      cubeWaiting.value = false
    })
  }
  function whenScrollReady(request, callback) {
    if (!request || request.ready) callback()
    else request.callbacks.push(callback)
  }
  function turnCube(destination, position) {
    destination = cubeIndex(destination, current.value.kinds.length)
    if (gesture?.axis !== 'horizontal' && cubeBusy.value && preparedScroll) {
      if (!cubeWaiting.value) { queuedCubeFace = destination; return }
      // A second tab tap during preparation still starts from the visible face.
      face.value = cubeIndex(cubeOrigin.value, current.value.kinds.length)
      stopCube(); updateSourceTabs(scrollPositions[current.value.kinds[face.value]] || 0); persist()
      syncTimestampPolish()
    }
    position ??= cubeTarget(face.value, destination, current.value.kinds.length)
    blurModelSearch()
    // Keep the post-swipe tap guard through the 420ms settle, even after a pause.
    if (gesture?.axis === 'horizontal') suppressTapUntil = Date.now() + 500
    cubeDragging.value = false
    entranceProgress.value = 1; entranceHintVisible.value = false
    clearTimeout(cubeTimer); clearTimeout(entranceTimer)
    if (!cubeBusy.value && destination === face.value && cubePosition.value === destination) { stopCube(); return }
    const direction = position === face.value ? cubeDirection.value : Math.sign(position - face.value)
    cubeClipTop.value ??= Math.max(0, sourceTabsExtent.value - sourceTabsOffset.value)
    if (cubeWaiting.value) cubePosition.value = cubeOrigin.value
    if (gesture?.axis !== 'horizontal') cubePosition.value = face.value
    if (gesture?.axis !== 'horizontal' || direction !== cubeDirection.value) prepareCubeFace(destination)
    cubeOrigin.value = face.value; cubeDirection.value = direction
    face.value = destination; gesture = null
    syncTimestampPolish()
    if (destination !== cubeOrigin.value) autoRefresh()
    updateSourceTabs(scrollPositions[current.value.kinds[destination]] || 0)
    cubeBusy.value = true; cubeDuration.value = 0
    persist()
    // Mount both hinged faces before changing the target. Separate render
    // frames give a tab tap the same geometry as an interactive drag.
    const serial = ++cubeTurnSerial
    whenScrollReady(preparedScroll, () => {
      if (!alive || serial !== cubeTurnSerial) return
      cubeWaiting.value = false
      cubeTimer = setTimeout(() => {
        if (!alive) return
        cubeDuration.value = 420; cubePosition.value = position; cubeClipTop.value = null
        cubeTimer = setTimeout(() => {
          if (!alive) return
          cubeBusy.value = false; cubeDuration.value = 0
          cubePosition.value = face.value; cubeOrigin.value = face.value; cubeDirection.value = 1
          measureLists(); syncTimestampPolish()
          const next = queuedCubeFace; queuedCubeFace = null
          if (next != null && next !== face.value) turnCube(next)
        }, 440)
      }, 24)
    })
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
    if (gesture.axis === 'navigation') {
      suppressTapUntil = Date.now() + 400
      return
    }
    if (gesture.axis !== 'horizontal') return
    cubeDragging.value = true
    cubeClipTop.value ??= Math.max(0, sourceTabsExtent.value - sourceTabsOffset.value)
    suppressTapUntil = Date.now() + 400
    const direction = gesture.position < gesture.face ? -1 : 1
    const destination = gesture.face + direction
    if (destination < 0 || destination >= current.value.kinds.length) {
      // Hold the last board flat: never preview the opposite end of this tab.
      cubePosition.value = gesture.face; cubeBusy.value = false; cubeDuration.value = 0
      cubeWaiting.value = false; preparedScroll = null
      cubeOrigin.value = gesture.face; cubeDirection.value = direction
      return
    }
    if (!cubeBusy.value || direction !== cubeDirection.value) prepareCubeFace(destination)
    else cubeDuration.value = 0
    cubeOrigin.value = gesture.face; cubeDirection.value = direction
    cubeBusy.value = true; cubePosition.value = gesture.position
  }
  function cubeEnd() {
    if (gesture?.axis === 'horizontal') {
      const position = cubeDestination(gesture, cubeWidth, Date.now())
      const next = cubeNavigation(categories.findIndex(item => item.id === category.value), position, categories.map(item => visibleBoardKinds(item.id, boardSelections.value).length))
      if (categories[next.category].id !== category.value) {
        suppressTapUntil = Date.now() + 500
        changeCategory(categories[next.category].id, next.face)
        return
      }
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
    if (current.value.kinds.length < 2) return
    entranceTimer = setTimeout(() => {
      if (!alive || !pageVisible || gesture) return
      cubeOrigin.value = face.value; cubeDirection.value = face.value ? -1 : 1
      alignFace(face.value === 0 ? 1 : face.value - 1)
      cubeBusy.value = true; cubeDuration.value = 0
      cubePosition.value = face.value + (face.value ? -0.06 : 0.06)
      entranceProgress.value = 0; entranceHintVisible.value = true
      entranceTimer = setTimeout(() => {
        if (!alive) return
        entranceProgress.value = 1
        cubeDuration.value = 420; cubePosition.value = face.value + (face.value ? -0.10 : 0.10)
        entranceTimer = setTimeout(() => {
          if (!alive) return
          // An introduction returns to the saved face without persisting a turn.
          cubeDuration.value = 700; cubePosition.value = face.value
          entranceTimer = setTimeout(() => {
            if (!alive) return
            cubeBusy.value = false; cubeDuration.value = 0
            cubePosition.value = face.value; cubeOrigin.value = face.value; cubeDirection.value = 1
            measureLists(); syncTimestampPolish()
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
  const measureSubtitle = createSubtitleMeasurer(wx)
  const statusBar = ref(24)
  const navHeight = ref(68)
  const headerTop = ref(28)
  const capsuleWidth = ref(100)
  const capsuleHeight = ref(32)
  const store = createBoardStore({ platform: wx, endpoint: __SHARED_ENDPOINT__ })
  const snapshots = ref(Object.fromEntries(Object.keys(boards).map(kind => [kind, store.read(kind)])))
  const filters = ref(initial.filters)
  const refreshing = ref({})
  const refreshTasks = new Map()
  const pullRefreshing = ref(false)
  const pullRefreshKind = ref('')
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
  const sourceNotice = ref({ open: false, title: '', content: '', url: '' })
  const companyDetails = ref({ open: false, name: '', content: '', members: [] })
  // Vant locks its mask, but touches inside popup content can still reach a
  // native scroll-view underneath. Lock every board as well as the page root.
  const backgroundLocked = computed(() => sheet.value.open || companyDetails.value.open
    || showingFeatureHelp.value || sourceNotice.value.open || capture.value.open || capturing.value)
  const lastAttempt = {}
  let alive = true

  const tr = key => text(copy[key], language.value)
  const labels = computed(() => Object.fromEntries(Object.keys(copy).map(key => [key, tr(key)])))
  const subtitleParts = computed(() => labels.value.subtitle.replace(/([;；])\s*/, '$1\n').split('\n'))
  const groupingControl = computed(() => ({
    height: capsuleHeight.value,
    width: capsuleHeight.value * (language.value === 'en' ? 3.75 : 2.5) + 16,
    fontSize: capsuleHeight.value * (language.value === 'en' ? 0.34 : 0.4),
  }))
  const brandTitle = computed(() => {
    const sample = measureBrand(labels.value.name, 32)
    const height = capsuleHeight.value
    const english = language.value === 'en'
    const width = Math.max(1, headerWidth.value - capsuleWidth.value - groupingControl.value.width - headerWidth.value / 750 * 30 - 8)
    const baseSize = 32 * height * (english ? 0.8 : 0.85) / sample.height
    const subtitleBaseSize = Math.min(11, (height * (english ? 0.8 : 0.85) - 4) / 2)
    const captionWidth = english ? 0 : measureSubtitle(subtitleParts.value) * subtitleBaseSize / 12
    // English shows only the title; Chinese shares space with its caption.
    // Only text contributes width. The floating help glyph uses the existing
    // 8px gap, matching the gap on the other side of the grouping control.
    const baseTitle = measureBrand(labels.value.name, baseSize)
    const headingScale = Math.min(1, width / (baseTitle.width + captionWidth))
    const title = measureBrand(labels.value.name, baseSize * headingScale)
    return { ...title, showSubtitle: !english, headingScale, baseTitleFontSize: baseSize,
      subtitleWidth: captionWidth * headingScale,
      subtitleHeight: title.height - 3 * headingScale,
      subtitleBaseFontSize: subtitleBaseSize, subtitleFontSize: subtitleBaseSize * headingScale,
      // A full-width Chinese stop has spare space to its right; tuck the icon
      // into that space rather than adding another gap after the glyph box.
      subtitleHelpOffset: /。$/.test(subtitleParts.value[1]) ? -0.55 : 0.08 }
  })
  const categoryItems = computed(() => categories.map(item => ({ id: item.id, label: text(item.labels, language.value),
    icon: `/assets/categories/${item.id}-${selectedSourceTheme.value.accent.slice(1)}.png` })))
  const categoryIndex = computed(() => categoryDragIndex.value ?? categories.findIndex(item => item.id === category.value))
  const categoryThemeStyle = computed(() => `--category-accent:${selectedSourceTheme.value.accent};`)
  const current = computed(() => ({ ...categoryFor(category.value), kinds: visibleBoardKinds(category.value, boardSelections.value).map(kind => variants.value[kind] || kind) }))
  const sourceTabIcons = computed(() => current.value.kinds.map(kind => sourceTabLogo(kind, dark.value)))
  const tabs = computed(() => current.value.kinds.map(kind => isPriceBoard(kind) ? 'API' : kind === 'openRouterUsage' ? tr('dailyUsage') : kind === 'cloudbaseUsage' ? tr('cumulativeShare') : kind === 'vercelUsage' ? tr('dailyShare') : kind === 'valsSWEbench' ? tr('archivedBenchmark') : kind === 'epochECI' ? tr('capabilityIndex') : kind.startsWith('artificial') ? tr('tasks') : tr('votes')))
  // Retain each slot's geometry while replacing its source identity and label.
  const sourceTabItems = computed(() => current.value.kinds.map((kind, index) => ({ index,
    content: [{ kind, label: tabs.value[index], icon: sourceTabIcons.value[index] }] })))
  const priceAscending = ref(false)
  const togglePriceOrder = () => {
    if (cubeBusy.value || backgroundLocked.value) return
    priceAscending.value = !priceAscending.value
    expandedBoards.value = {}
    resetScroll(["openRouterPrice"])
  }
  const costOrder = ref({})
  const speedOrder = ref({})
  const costUnit = kind => kind === 'openRouterUsage' ? (language.value === 'en' ? 'In/Out $/1M' : language.value === 'zh-TW' ? '輸入/輸出$/百萬' : '输入/输出$/百万') : tr(isAAImageCost(kind) ? 'imageCostUnit' : isAAVideoCost(kind) ? 'videoCostUnit' : 'taskCostUnit')
  const toggleCostOrder = event => {
    const kind = event.currentTarget.dataset.kind
    if (!metricAvailable(kind) || cubeBusy.value || backgroundLocked.value) return
    metricGuide.acknowledge(kind)
    const labels = kind === 'openRouterUsage' ? (language.value === 'en' ? ['Usage', 'Price', 'Speed'] : language.value === 'zh-TW' ? ['用量', '價格', '速度'] : ['用量', '价格', '速度']) : language.value === "en" ? ["Score", "Cost", "Speed"] : language.value === "zh-TW" ? ["分數", "成本", "速度"] : ["分数", "成本", "速度"]
    wx.showActionSheet({ itemList: labels.slice(0, supportsAASpeed(kind) ? 3 : 2), success: ({ tapIndex }) => {
      costOrder.value = { ...costOrder.value, [kind]: tapIndex === 1 }
      speedOrder.value = { ...speedOrder.value, [kind]: tapIndex === 2 }
      expandedBoards.value = {}
      resetScroll([kind])
    } })
  }
  const filterFor = kind => ({ country: 'all', openness: 'all', ...filters.value[kind] })
  const countriesFor = kind => countryOptions({ entries: Object.values(snapshots.value).flatMap(board => board?.entries || []) }, language.value, filterFor(kind).country)
  function setFilters(filter) {
    expandedBoards.value = {}
    filters.value = Object.fromEntries(Object.keys(boards).map(source => [source, { ...filter }]))
    resetScroll(Object.keys(boards))
  }
  // Keep full model data out of the Vue-to-WeChat bridge. Sorting/filtering
  // are cached independently of scroll positions; only window rows are mapped.
  const rankedCards = computed(() => current.value.kinds.map(kind => {
    const costMode = metricAvailable(kind) && !!costOrder.value[kind]
    const speedMode = metricAvailable(kind) && !!speedOrder.value[kind]
    const base = rankedEntries(snapshots.value[kind], { ...filterFor(kind), grouping: grouping.value })
    const prices = base.map(entry => entry.taskCostUSD).filter(value => Number.isFinite(value) && value >= 0)
    const speeds = base.map(entry => entry.speed).filter(value => Number.isFinite(value) && value > 0)
    return { kind, costMode, speedMode, leaderScore: speedMode ? (speeds.length ? Math.max(...speeds) : undefined) : costMode ? (prices.length ? Math.max(...prices) : undefined) : isPriceBoard(kind) ? Math.max(...base.map(entry => entry.score), 0) : base[0]?.score,
      entries: rankedEntries(snapshots.value[kind], { ...filterFor(kind), grouping: grouping.value, query: modelSearchQuery.value, priceAscending: priceAscending.value, sort: speedMode ? 'speed' : costMode ? 'cost' : 'score' }) }
  }))
  const visibleCards = computed(() => rankedCards.value.map(card => ({ ...card, totalCount: card.entries.length,
    entries: expandedBoards.value[card.kind] ? card.entries : card.entries.slice(0, 20) })))
  function toggleRanking(event) {
    const kind = event.currentTarget.dataset.kind
    const card = rankedCards.value.find(card => card.kind === kind)
    if (!card || card.entries.length <= 20 || cubeBusy.value || backgroundLocked.value) return
    const expanded = !expandedBoards.value[kind]
    expandedBoards.value = { ...expandedBoards.value, [kind]: expanded }
    if (expanded) { syncWindow(kind, true); measureLists() }
    else { syncWindow(kind, true); measureLists() }
  }
  const distributions = computed(() => Object.fromEntries(current.value.kinds.map(kind => {
    const distribution = leaderboardDistribution(snapshots.value[kind]?.entries || [])
    return [kind, { ...distribution,
      totalLabel: language.value === 'en' ? `${distribution.total} models` : `${distribution.total} ${language.value === 'zh-TW' ? '個' : '个'}模型`,
      countries: distribution.countries.map(slice => ({ ...slice, width: `${slice.fraction * 100}%`,
        flag: slice.id === 'unknown' ? '?' : slice.id === 'other' ? '🌐' : countryFlag(slice.id), flagImage: countryFlagImage(slice.id), name:
        ['unknown', 'other'].includes(slice.id) ? tr(slice.id) : countryName(slice.id, language.value) })),
      sources: distribution.sources.map(slice => ({ ...slice, width: `${slice.fraction * 100}%`, color: opennessColor(slice.id, dark.value), icon: opennessIcon(slice.id, dark.value), name: tr(slice.id) })),
    }]
  })))
  function boardTime(board, kind) {
    // Statistical dates describe coverage, not publication or retrieval.
    const isSourceTime = !['vercelUsage', 'cloudbaseUsage'].includes(kind) && Number.isFinite(Date.parse(board?.sourceUpdatedAt))
    const value = isSourceTime ? board.sourceUpdatedAt : contentTimestamp(board)
    const dataset = isSourceTime && isArenaDatasetBoard(board)
    return { time: formatTime(value, language.value, new Date(), { dateOnly: dataset, utc: dataset }),
      timeLabel: tr(isSourceTime ? 'published' : 'updated'), isSourceTime }
  }
  const cards = computed(() => visibleCards.value.map(({ kind, entries, leaderScore, totalCount }, index) => {
    const board = snapshots.value[kind]
    const base = variantBase(kind)
    const options = boardVariants[base] || []
    const filter = filterFor(kind)
    const range = rangeFor(kind, entries.length)
    const time = boardTime(board, kind)
    return { kind, themeStyle: `--source-accent:${sourceTabTheme(kind, dark.value).accent};`, title: boardTitle(kind, language.value), heading: mobileBoardHeading(kind, language.value), index, summary: text(boards[kind].summaries, language.value),
      ...(options.length > 1 && { variantBase: base, variantLabels: options.map(option => text(variantLabels[option], language.value)), variantIndex: options.indexOf(kind) }),
      ...time, timeAccessibility: `${time.time} ${time.timeLabel}`,
      count: totalCount, shownCount: entries.length, hasMore: totalCount > 20, expanded: !!expandedBoards.value[kind],
      expansionLabel: expandedBoards.value[kind] ? tr('showLess') : tr('showAll').replace('{count}', totalCount), distribution: distributions.value[kind],
      // Keep the editing header pinned when a query reduces a long list to a
      // few rows; native scroll views otherwise clamp their offset to zero.
      height: Math.max(entries.length * geometry.value.rowHeight, (modelSearchVisible.value || !!modelSearchQuery.value.trim())
        ? Math.max(0, (viewports[kind] || geometry.value.viewportHeight) - geometry.value.rowHeight - (entries.length ? 0 : 200)) : 0) + (totalCount > 20 ? 48 : 0),
      toggleTop: 20 * geometry.value.rowHeight,
      rowHeight: geometry.value.rowHeight,
      rows: renderRows(kind, entries, range, leaderScore).map(row => ({ ...row, top: row.top + (expandedBoards.value[kind] && row.top >= 20 * geometry.value.rowHeight ? 48 : 0) })),
      searchStyle: modelSearchVisible.value ? 'left:0px;right:0px;' : searchOrigins.value[kind] || 'left:50%;right:50%;',
      ...(isPriceBoard(kind) && { hasPrice: true, priceAscending: priceAscending.value }),
      ...(metricAvailable(kind) && { hasTaskCost: true, ...(metricGuideKind.value === kind && { showMetricGuide: true }), ...(kind in costOrder.value && { costOrder: !!costOrder.value[kind] }), ...(kind in speedOrder.value && { speedOrder: !!speedOrder.value[kind] }), ...((speedOrder.value[kind] || costOrder.value[kind]) && { metricTitle: speedOrder.value[kind] ? (language.value === 'en' ? 'Speed' : '速度') : (language.value === 'en' ? 'Cost' : '成本') }), ...(speedOrder.value[kind] && { speedUnit: (kind === "artificialAnalysisCodingAgent" || kind === "valsSWEbench") ? (language.value === "en" ? "s/task" : language.value === "zh-TW" ? "秒/任務" : "秒/任务") : "token/s" }), ...(costOrder.value[kind] && { costUnit: costUnit(kind) }),
        costSortLabel: speedOrder.value[kind] ? (language.value === "en" ? "Speed" : "速度") : kind === 'openRouterUsage' ? (costOrder.value[kind] ? (language.value === 'en' ? 'Price' : language.value === 'zh-TW' ? '價格' : '价格') : tr('tokens')) : costOrder.value[kind] ? tr('taskCostAscending') : tr('scoreDescending') }),
      scoreLabel: isErrorRate(kind) ? 'WER ↓' : ['vercelUsage', 'cloudbaseUsage'].includes(kind) ? tr('tokenShare') : kind === 'openRouterUsage' ? tr('tokens') : tr('score'),
      pendingConfiguration: !!configurationRequired.value[kind],
      hasBoard: !!board, filtered: filter.country !== 'all' || filter.openness !== 'all' || !!modelSearchQuery.value.trim(),
      countryFiltered: filter.country !== 'all', sourceFiltered: filter.openness !== 'all',
      // Lazy sources also need placeholders before their first lifecycle task
      // starts; only a completed attempt may reveal the no-board state.
      loading: !!refreshing.value[kind] || (!board && lastAttempt[kind] == null),
      polishing: polishingKind.value === kind,
      headerPinned: !!pinnedHeaders.value[kind],
    }
  }))
  const backToTop = computed(() => !!backTopBoards.value[current.value.kinds[face.value]])

  function renderRows(kind, entries, range, leaderScore) {
    if (!rowRenderers.has(kind)) rowRenderers.set(kind, createRowRenderer((entry, entries) =>
      rowView(entry, { company: grouping.value === 'company', dark: dark.value, details: false,
        language: language.value, category: category.value, kind, costMode: metricAvailable(kind) && !!costOrder.value[kind], speedMode: metricAvailable(kind) && !!speedOrder.value[kind], leaderScore: rankedCards.value.find(card => card.kind === kind)?.leaderScore })))
    return rowRenderers.get(kind)({ entries, ...range, rowHeight: geometry.value.rowHeight,
      variant: `${grouping.value}:${dark.value}:${language.value}:${category.value}:${leaderScore}:${!!costOrder.value[kind]}:${!!speedOrder.value[kind]}` })
  }

  function rangeFor(kind, count, force = false) {
    const scrollTop = scrollPositions[kind] || 0
    const toggleStart = (origins[kind] || 0) + 20 * geometry.value.rowHeight
    const adjustedScrollTop = expandedBoards.value[kind] ? scrollTop - Math.min(48, Math.max(0, scrollTop - toggleStart)) : scrollTop
    return resolveRowWindow({ count, scrollTop: adjustedScrollTop, origin: origins[kind] || 0,
      geometry: { ...geometry.value, viewportHeight: viewports[kind] || geometry.value.viewportHeight },
      ...scrollWindows.value[kind], force })
  }
  function syncWindow(kind, force = false) {
    const card = visibleCards.value.find(card => card.kind === kind)
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
  function requestScroll(kind, top, preparing = false) {
    if (kind === current.value.kinds[face.value]) { cancelSourceTabsSync(); updateSourceTabs(top) }
    // A scroll-top binding inside the changing cards loop can replay an old
    // target on each virtual-window render. Command only explicit navigation.
    clearTimeout(scrollRequests.get(kind)?.timer)
    const request = { top, pending: true, preparing, ready: false, callbacks: [], started: Date.now() }
    scrollRequests.set(kind, request)
    const run = () => {
      if (!alive || scrollRequests.get(kind) !== request || !wx.createSelectorQuery) return
      const query = wx.createSelectorQuery()
      query.select(`#board-scroll-${kind}`).node()
      query.exec(results => {
        if (!alive || scrollRequests.get(kind) !== request) return
        results[0]?.node?.scrollTo({ top, animated: false })
        if (preparing) settlePreparedScroll(kind, request)
        else if (kind === current.value.kinds[face.value]) syncSourceTabsAfterScroll(kind)
      })
    }
    if (wx.nextTick) wx.nextTick(run)
    else run()
    return request
  }
  function settlePreparedScroll(kind, request) {
    if (!alive || scrollRequests.get(kind) !== request) return
    const query = wx.createSelectorQuery()
    query.select(`#board-scroll-${kind}`).fields({ size: true, scrollOffset: true })
    query.exec(results => {
      if (!alive || scrollRequests.get(kind) !== request) return
      const native = results[0]
      const maximum = Number.isFinite(native?.scrollHeight) && native.height > 0
        ? Math.max(0, native.scrollHeight - native.height) : Infinity
      const target = Math.min(request.top, maximum)
      const misplaced = Number.isFinite(native?.scrollTop) && Math.abs(native.scrollTop - target) > 1
      // Read two native frames at the destination: pinning a compact header
      // can change its scroll range after the first scrollTo acknowledgement.
      const stable = !misplaced && request.settledTop === native?.scrollTop && request.settledMaximum === maximum
      if (native && (!stable || misplaced) && Date.now() - request.started < 600) {
        request.settledTop = misplaced ? null : native.scrollTop
        request.settledMaximum = maximum
        request.timer = setTimeout(() => settlePreparedScroll(kind, request), 32)
        return
      }
      const top = Number.isFinite(native?.scrollTop) ? Math.max(0, native.scrollTop) : request.top
      request.failed = misplaced
      request.pending = false; request.ready = true; request.top = top
      scrollPositions[kind] = top
      backTopBoards.value = { ...backTopBoards.value, [kind]: top > 400 }
      syncWindow(kind, true)
      if (kind === current.value.kinds[face.value]) updateSourceTabs(top)
      for (const callback of request.callbacks.splice(0)) callback()
    })
  }
  function measureHeaderText() {
    if (!pageReady || !alive || cubeBusy.value || !wx.createSelectorQuery) return
    const kinds = [...current.value.kinds]
    const key = `${headerWidth.value}:${language.value}:${grouping.value}:${face.value}:${kinds.join(',')}`
    if (key === headerFitKey) return
    headerFitKey = key
    const serial = ++headerMeasureSerial
    const run = () => {
      if (!alive || serial !== headerMeasureSerial) return
      const query = wx.createSelectorQuery()
      for (const kind of kinds) for (const selector of ['.source-heading-details', '.source-heading-measure', '.variant-measure', '.variant-chrome-measure', '.model-filter-toggle']) {
        query.select(`#table-head-${kind} ${selector}`).fields({ size: true, computedStyle: ['font-size'] })
      }
      query.exec(results => {
        if (!alive || serial !== headerMeasureSerial || key !== headerFitKey) return
        const next = { ...headerFits.value }
        kinds.forEach((kind, index) => {
          const [row, heading, variant, chrome, search] = results.slice(index * 5, index * 5 + 5)
          if (!row?.width || !heading?.width) return
          const hasVariant = (boardVariants[variantBase(kind)] || []).length > 1
          if (hasVariant && (!variant?.width || !chrome?.width)) return
          const pickerChrome = hasVariant ? chrome.width : 0
          const chromeWidth = (search?.width || 28) + pickerChrome
            + headerWidth.value / 750 * (hasVariant ? 24 : 2)
          const fit = fitSourceHeader({ width: row.width, headingWidth: heading.width,
            variantWidth: hasVariant ? variant.width : 0, chromeWidth })
          // rpx font sizes are rounded by WeChat. Fit from the rendered probe
          // fonts in px and reserve the resulting picker width explicitly: a
          // native picker must not shrink the fitted text a second time.
          next[kind] = { ...fit,
            headingPixels: (parseFloat(heading['font-size']) || (language.value === 'en' ? 18 : 21) * headerWidth.value / 750) * fit.headingScale,
            variantPixels: (parseFloat(variant?.['font-size']) || 18 * headerWidth.value / 750) * fit.variantScale,
            ...(hasVariant && { pickerWidth: variant.width * fit.variantScale + pickerChrome + 1 }) }
        })
        headerFits.value = next
      })
    }
    if (wx.nextTick) wx.nextTick(run)
    else run()
  }
  function measureLists() {
    measureHeaderText()
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
      face: face.value, theme: theme.value, appearance: sharedAppearance.value, filters: filters.value,
      ...(Object.keys(variants.value).length ? { variants: variants.value } : {}),
      ...(boardTransition.value !== 'cube' ? { boardTransition: boardTransition.value } : {}),
      ...(Object.keys(boardSelections.value).length ? { boardSelections: boardSelections.value } : {}) }
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

  function refreshKind(kind) {
    if (refreshTasks.has(kind)) return refreshTasks.get(kind)
    const task = loadKind(kind).finally(() => refreshTasks.delete(kind))
    refreshTasks.set(kind, task)
    return task
  }
  async function loadKind(kind) {
    lastAttempt[kind] = Date.now()
    refreshing.value = { ...refreshing.value, [kind]: true }
    syncTimestampPolish()
    try {
      const board = await store.fetch(kind)
      if (!alive) return
      configurationRequired.value = { ...configurationRequired.value, [kind]: false }
      snapshots.value = { ...snapshots.value, [kind]: board }
    } catch (error) {
      if (alive) configurationRequired.value = { ...configurationRequired.value, [kind]: error.code === 'configurationRequired' }
      // Background failures keep the last shared snapshot and its timestamps.
    } finally {
      if (alive) {
        refreshing.value = { ...refreshing.value, [kind]: false }
        syncTimestampPolish()
        syncWindow(kind, true)
        measureLists()
        playEntrance()
      }
    }
  }
  function autoRefresh() {
    const kind = current.value.kinds[face.value]
    if (refreshTasks.has(kind)) return refreshTasks.get(kind)
    return shouldAutoRefresh(snapshots.value[kind], lastAttempt[kind]) ? refreshKind(kind) : Promise.resolve()
  }
  async function pullRefresh(event) {
    if (backgroundLocked.value || pullRefreshing.value) return
    const kind = event?.currentTarget?.dataset?.kind || current.value.kinds[face.value]
    if (!current.value.kinds.includes(kind)) return
    pullRefreshKind.value = kind
    pullRefreshing.value = true
    const started = Date.now()
    try { await refreshKind(kind) } finally {
      // Even a cached response needs a painted loading frame before restoring
      // the native header; otherwise a quick release leaves only its blank gap.
      const remaining = 300 - (Date.now() - started)
      if (alive && remaining > 0) await new Promise(resolve => setTimeout(resolve, remaining))
      if (alive) pullRefreshing.value = false
    }
  }
  function finishPullRefresh(event) {
    if (!pullRefreshing.value && event.currentTarget.dataset.kind === pullRefreshKind.value) pullRefreshKind.value = ''
  }
  onLoad(async () => { await autoRefresh(); playEntrance() })
  onReady(() => { pageReady = true; measureSourceTabs(); measureHeaderText(); playEntrance(); syncTimestampPolish() })
  onShow(() => {
    pageVisible = true
    updateTheme()
    const latestSaved = (() => { try { return wx.getStorageSync('benchgauge.preferences') || {} } catch { return preferencesSnapshot() } })()
    const nextTransition = normalizeBoardTransition(latestSaved.boardTransition)
    if (nextTransition !== boardTransition.value) { stopCube(); boardTransition.value = nextTransition }
    const latest = normalizeBoardSelections(latestSaved.boardSelections)
    if (JSON.stringify(latest) !== JSON.stringify(boardSelections.value)) {
      const nextFace = selectedBoardFace(category.value, face.value, boardSelections.value, latest)
      stopCube(); boardSelections.value = latest; face.value = nextFace
      cubePosition.value = nextFace; cubeOrigin.value = nextFace
      expandedBoards.value = {}; rowRenderers.clear(); resetScroll(); measureSourceTabs(); measureLists()
      persist(); autoRefresh()
    }
    syncTimestampPolish()
    syncSourceTabsAfterScroll(current.value.kinds[face.value])
    if (languageMode.value === 'system') {
      const next = systemLanguage(wx.getAppBaseInfo?.().language)
      if (next !== language.value) { language.value = next; measureLists() }
    }
    playEntrance()
  })
  onHide(() => { pageVisible = false; metricGuide.stop(); timestampPolish.stop(); blurModelSearch(); clearTimeout(searchExpandTimer); stopCube(); cancelSourceTabsSync() })
  onUnload(() => { metricGuide.stop(); timestampPolish.stop(); blurModelSearch(); clearTimeout(searchExpandTimer); stopCube(); cancelSourceTabsSync(); alive = false; measureSerial++; scrollRequests.clear(); rowRenderers.clear(); store.dispose(); wx.offThemeChange?.(themeListener)
    if (!capture.value.saving) removeScreenshot(wx, capture.value.path)
    if (capturing.value || capture.value.saving) wx.hideLoading() })
  onShareAppMessage(() => ({ title: `${tabs.value[face.value]}｜${tr('rankingSummary')}`,
    path: sharePath(preferencesSnapshot(), dark.value ? 'dark' : 'light') }))

  function selectCategory(event) {
    if (Date.now() < tabSuppressTapUntil) return
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
    changeCategory(id)
  }
  function changeCategory(id, destination = face.value) {
    blurModelSearch(); stopCube(); entrancePlayed = true
    if (id === 'price') grouping.value = 'model'
    expandedBoards.value = {}; category.value = id; face.value = Math.min(destination, current.value.kinds.length - 1); cubePosition.value = face.value; cubeOrigin.value = face.value; cubeDirection.value = 1; rowRenderers.clear(); resetScroll(); persist(); autoRefresh()
    syncTimestampPolish()
  }
  function selectGrouping(event) {
    if (category.value === 'price') return
    blurModelSearch(); stopCube(); entrancePlayed = true
    searchQueries[grouping.value] = modelSearchQuery.value
    grouping.value = event.currentTarget.dataset.id
    modelSearchQuery.value = searchQueries[grouping.value] || ''
    expandedBoards.value = {}; resetScroll(); persist()
  }
  function selectFace(event) {
    if (Date.now() < suppressTapUntil) return
    const destination = Number(event.currentTarget.dataset.index)
    if (Number.isInteger(destination) && destination >= 0 && destination < current.value.kinds.length) { entrancePlayed = true; turnCube(destination) }
  }
  function selectVariant(event) {
    const base = event.currentTarget.dataset.base
    const options = boardVariants[base]
    const index = Number(event.detail.value)
    if (!options || !Number.isInteger(index) || index < 0 || index >= options.length || cubeBusy.value) return
    const previous = current.value.kinds[face.value]
    if (variantBase(previous) !== base || options[index] === previous) return
    blurModelSearch(); stopCube(); entrancePlayed = true
    variants.value = normalizeVariants({ ...variants.value, [base]: options[index] })
    expandedBoards.value = {}; rowRenderers.clear(); resetScroll(); persist(); autoRefresh(); syncTimestampPolish()
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
    searchQueries.model = searchQueries.company = ''
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
    if (cubeBusy.value || backgroundLocked.value) return
    stopCube(); entrancePlayed = true
    clearTimeout(searchBlurTimer)
    const serial = ++searchSerial
    const expand = () => {
      if (!alive || serial !== searchSerial) return
      modelSearchOpen.value = true; metricGuide.stop()
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
    expandedBoards.value = {}
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
    syncTimestampPolish()
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
    if (cubeBusy.value || backgroundLocked.value || Date.now() < suppressTapUntil) return
    const kind = event.currentTarget.dataset.kind
    if (!hasOwn(boards, kind)) return
    const board = snapshots.value[kind]
    const formerName = kind.startsWith('arena') || kind.startsWith('codeArena')
      ? `${text(['Formerly LMSYS Chatbot Arena / LMArena', '原 LMSYS Chatbot Arena / LMArena', '原 LMSYS Chatbot Arena / LMArena'], language.value)}\n\n` : ''
    const agreement = sourceAgreement(kind, board, language.value)
    const time = boardTime(board, kind)
    const times = `${time.time} ${time.timeLabel}`
    const refreshOnly = ['vercelUsage', 'cloudbaseUsage'].includes(kind)
    const day = kind === 'vercelUsage' && Number.isFinite(Date.parse(board?.sourceUpdatedAt))
      ? `${text(['Statistical day (UTC): ', '统计日期（UTC）：', '統計日期（UTC）：'], language.value)}${new Date(board.sourceUpdatedAt).toISOString().slice(0, 10)}\n\n` : ''
    const sampled = kind === 'cloudbaseUsage' ? `${text(boards[kind].summaries, language.value)}\n\n` : ''
    const refreshMeaning = refreshOnly ? `\n${tr('timeExplanation')}` : ''
    const textArenaSummary = ['arenaText', 'arenaTextUncontrolled'].includes(kind) ? `${text(boards[kind].summaries, language.value)}\n\n` : ''
    sourceNotice.value = { open: true, title: boardTitle(kind, language.value),
      content: `${formerName}${day}${sampled}${textArenaSummary}${text(boards[kind].methodology || boards[kind].summaries, language.value)}\n\n${times}${refreshMeaning}\n\n${boards[kind].url}${agreement ? `\n\n${agreement}` : ''}`,
      url: boards[kind].url }
  }
  function closeSourceNotice() { sourceNotice.value = { ...sourceNotice.value, open: false } }
  function copySourceLink() {
    if (!sourceNotice.value.open) return
    copyText(sourceNotice.value.url)
    closeSourceNotice()
  }

  function timeHelp() {
    if (cubeBusy.value || Date.now() < suppressTapUntil) return
    wx.showModal({ title: tr('timeExplanationTitle'), content: tr('timeExplanation'), showCancel: false, confirmText: 'OK' })
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
  function rowDetails(event) {
    if (cubeBusy.value || Date.now() < suppressTapUntil) return
    const { kind, rank } = event.currentTarget.dataset
    const entry = rankedCards.value.find(card => card.kind === kind)?.entries.find(row => row.rank === Number(rank))
    if (!entry) return
    if (grouping.value === 'model') {
      stopCube(); entrancePlayed = true
      wx.navigateTo({ url: sharePath(preferencesSnapshot(), dark.value ? 'dark' : 'light', '/pages/model/index'),
        success: result => result.eventChannel.emit('modelDetails', { entry }) })
      return
    }
    const row = rowView(entry, { company: grouping.value === 'company', dark: dark.value, kind })
    const content = row.components.length ? tr(['vercelUsage', 'cloudbaseUsage'].includes(kind) ? 'usageShareSum' : kind === 'openRouterUsage' ? 'usageSum' : 'strongest') : row.name
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
      const model = { language: language.value, labels: { ...labels.value }, dark: dark.value, grouping: grouping.value,
        groupingLabel: tr(grouping.value === 'company' ? 'companies' : 'models'),
        categoryLabel: text(current.value.labels, language.value),
        boards: current.value.kinds.map((kind, index) => {
          const board = snapshots.value[kind], filter = filterFor(kind)
          const country = filter.country === 'all' ? tr('all') : countryName(filter.country, language.value)
          const time = boardTime(board, kind)
          return { kind, sourceNote: board?.sourceNote, title: boardTitle(kind, language.value), heading: mobileBoardHeading(kind, language.value), tab: tabs.value[index],
            summary: text(boards[kind].summaries, language.value),
            variantLabel: variantBase(kind) ? text(variantLabels[kind], language.value) : '',
            time: `${time.time} ${time.timeLabel}`, isSourceTime: time.isSourceTime,
            taskCostLabel: isErrorRate(kind) ? 'WER ↓' : isPriceBoard(kind) ? tr('priceInput') + (priceAscending.value ? ' ↑' : ' ↓') : metricAvailable(kind) && speedOrder.value[kind] ? ((kind === 'artificialAnalysisCodingAgent' || kind === 'valsSWEbench') ? (language.value === 'en' ? 's/task' : language.value === 'zh-TW' ? '秒/任務' : '秒/任务') : 'token/s') : metricAvailable(kind) && costOrder.value[kind] ? costUnit(kind) : '',
            metricHeading: metricAvailable(kind) && speedOrder.value[kind] ? (language.value === 'en' ? 'Speed' : '速度') : metricAvailable(kind) && costOrder.value[kind] ? (language.value === 'en' ? 'Cost' : '成本') : '',
            filterLabel: `${metricAvailable(kind) ? (speedOrder.value[kind] ? (language.value === 'en' ? 'Speed' : '速度') : tr(costOrder.value[kind] ? 'taskCostAscending' : 'scoreDescending')) + ' · ' : ''}${tr('country')}: ${country} · ${tr('source')}: ${tr(filter.openness)}`,
            empty: tr(board ? 'empty' : 'noBoard'),
            rows: rankedCards.value[index].entries.map(entry =>
              rowView(entry, { company: grouping.value === 'company', dark: dark.value, language: language.value, details: false, kind: rankedCards.value[index].kind, costMode: metricAvailable(kind) && !!costOrder.value[kind], speedMode: metricAvailable(kind) && !!speedOrder.value[kind], leaderScore: rankedCards.value[index].leaderScore })) }
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
  const openSettings = () => { blurModelSearch(); stopCube(); persist(); wx.navigateTo({ url: '/pages/settings/index' }) }
  const quotaHelpContent = computed(() => tr('quotaHelp'))
  const quotaHelp = () => { stopCube(); entrancePlayed = true; showingFeatureHelp.value = true }
  const closeFeatureHelp = () => { showingFeatureHelp.value = false }
  const copyDesktopLink = () => { closeFeatureHelp(); copyText(desktopDownloadURL) }
  const refreshTap = event => refreshKind(event.currentTarget.dataset.kind)
  return { labels, subtitleParts, brandTitle, groupingControl, categoryItems, categoryIndex, categoryThemeStyle, category, grouping, face, dark, cards, tabs, sourceTabIcons, backToTop, skeletonRows,
    modelSearchQuery, modelSearchVisible, modelSearchFocused, openModelSearch, inputModelSearch, beginModelSearchClear, cancelModelSearchClear, clearModelSearch, closeModelSearch, blurModelSearch, deferModelSearchBlur, focusModelSearch,
    statusBar, navHeight, headerTop, capsuleWidth, sheet, backgroundLocked, sourceNotice, closeSourceNotice, copySourceLink,
    cubeFaces, sourceSelection, sourceTabIndex, sourceTabsStyle, sourceTabsExtent, sourceTabWidth, sourceTabItems, cubeViewportStyle,
    cubePosition, cubeDuration, cubeBusy, cubeDragging, entranceStyle, entranceHintVisible, boardTransition,
    cubeStart, cubeMove, cubeEnd, cubeCancel, tabStart, tabMove, tabEnd, cancelTabDrag, attributeHint,
    selectCategory, selectGrouping, selectFace, selectVariant, changeFace, scroll, top, filterMenu, toggleRanking, toggleCostOrder, togglePriceOrder,
    clearFilters, preferences, sheetSelect, closeSheet, sourceHelp, timeHelp, countryHelp, copyPurchaseLink, rowDetails, companyDetails, closeCompanyDetails, copyCompanyName, about, openSettings,
    quotaHelp, quotaHelpContent, showingFeatureHelp, closeFeatureHelp, copyDesktopLink, refreshTap, autoRefresh, pullRefresh, pullRefreshing, pullRefreshKind, finishPullRefresh,
    capturing, capture, screenshot, closeCapture, previewScreenshot, saveScreenshot }
}, { canShareToOthers: true })
