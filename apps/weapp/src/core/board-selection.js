import { categories, categoryFor, boardTitle, variantBase, variantLabels, text } from './catalog.js'

// Settings name source families independently of the concise table headings.
export function boardSelectionTitle(kind, language) {
  const base = variantBase(kind) || kind
  if (base === 'artificialAnalysis') return text(['Artificial Analysis General', 'Artificial Analysis 综合', 'Artificial Analysis 綜合'], language)
  if (base === 'artificialAnalysisCodingAgent') return text(['Artificial Analysis Coding', 'Artificial Analysis 编程', 'Artificial Analysis 編程'], language)
  if (base === 'artificialAnalysisTextToImage') return text(['Artificial Analysis Image', 'Artificial Analysis 图片', 'Artificial Analysis 圖片'], language)
  if (base === 'artificialAnalysisTextToVideo') return text(['Artificial Analysis Video', 'Artificial Analysis 视频', 'Artificial Analysis 影片'], language)
  if (base === 'arenaText') return text(['Arena Text', 'Arena 文本', 'Arena 文本'], language)
  if (base === 'codeArenaWebDev') return text(['Arena Coding', 'Arena 编程', 'Arena 編程'], language)
  if (base === 'artificialAnalysisSpeechProviderVoice') return text(['Artificial Analysis Speech', 'Artificial Analysis 语音', 'Artificial Analysis 語音'], language)
  if (kind === 'epochSoftwareECI') return text(['Epoch ECI Software engineering', 'Epoch ECI 软件工程', 'Epoch ECI 軟體工程'], language)
  if (kind === 'epochECI' || kind === 'epochMathECI' || kind === 'epochCyberECI') return `Epoch ECI ${text(variantLabels[kind], language)}`
  return boardTitle(kind, language)
}

// Match DesktopBoardSelection: defaults exclude archived sources; explicit choices retain them.
export function visibleBoardKinds(category, selections = {}) {
  const item = categoryFor(category), kinds = item.kinds
  const defaults = item.defaultKinds || kinds
  const saved = selections?.[category]
  const selected = Array.isArray(saved) ? kinds.filter(kind => saved.includes(kind)) : defaults
  return Array.isArray(saved) && saved.length === 0 ? [] : selected.length ? selected : defaults
}

export function normalizeBoardSelections(value) {
  const normalized = Object.fromEntries(categories.flatMap(category => {
    const kinds = visibleBoardKinds(category.id, value)
    const defaults = category.defaultKinds || category.kinds
    return kinds.length === defaults.length && kinds.every((kind, index) => kind === defaults[index]) ? [] : [[category.id, kinds]]
  }))
  return categories.some(category => visibleBoardKinds(category.id, normalized).length) ? normalized : {}
}

export function visibleCategories(selections = {}) {
  return categories.filter(category => visibleBoardKinds(category.id, selections).length > 0)
}

export function selectedBoardCategory(category, selections = {}) {
  const enabled = visibleCategories(selections)
  return enabled.some(item => item.id === category) ? category : enabled[0].id
}

export function selectedBoardCount(selections = {}) {
  return categories.reduce((count, category) => count + visibleBoardKinds(category.id, selections).length, 0)
}

export function toggleBoardSelection(category, kind, selections = {}) {
  const current = visibleBoardKinds(category, selections)
  if (!categoryFor(category).kinds.includes(kind) || (selectedBoardCount(selections) === 1 && current.includes(kind))) return selections
  const next = current.includes(kind) ? current.filter(item => item !== kind) : [...current, kind]
  return normalizeBoardSelections({ ...selections, [category]: next })
}

export function selectedBoardFace(category, face, previous, next) {
  const kind = visibleBoardKinds(category, previous)[face]
  const kinds = visibleBoardKinds(category, next)
  const index = kinds.indexOf(kind)
  return index >= 0 ? index : Math.max(0, Math.min(face, kinds.length - 1))
}
