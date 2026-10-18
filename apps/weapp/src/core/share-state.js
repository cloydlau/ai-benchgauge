import { boards, categories, hasOwn, languages } from './catalog.js'
import { normalizedCountryCode } from '../../../../fc/domain.mjs'

const groupings = ['model', 'company']
const themes = ['system', 'light', 'dark']
const appearances = ['light', 'dark']
const opennessValues = ['all', 'open', 'closed', 'unknown']
const isObject = value => value !== null && typeof value === 'object' && !Array.isArray(value)
const validCategory = value => categories.some(category => category.id === value)
const validCountry = value => typeof value === 'string' && /^(all|unknown|[A-Z]{2})$/.test(value)

function normalizeFilters(value, category, face) {
  // Migrate older per-board/category preferences from the visible board.
  const kind = categories.find(group => group.id === category).kinds[face]
  const filter = isObject(value) && hasOwn(value, kind) && isObject(value[kind]) ? value[kind] : {}
  const country = validCountry(filter.country) ? normalizedCountryCode(filter.country) ?? filter.country : 'all'
  const openness = opennessValues.includes(filter.openness) ? filter.openness : 'all'
  // Preserve the existing storage/share format for older clients.
  return country === 'all' && openness === 'all' ? {}
    : Object.fromEntries(Object.keys(boards).map(source => [source, { country, openness }]))
}

export function systemLanguage(value) {
  if (typeof value !== 'string' || !value.trim()) return 'zh-CN'
  const locale = value.trim().replaceAll('_', '-').toLowerCase()
  if (/^zh(?:-|$)/.test(locale)) return /(?:hant|tw|hk|mo)(?:-|$)/.test(locale) ? 'zh-TW' : 'zh-CN'
  return 'en'
}

export function normalizePreferences(value, locale) {
  value = isObject(value) ? value : {}
  const theme = themes.includes(value.theme) ? value.theme : 'system'
  // Old saved language choices remain explicit. New automatic preferences
  // keep following the host language even when another setting is saved.
  const manualLanguage = languages.includes(value.language) && value.languageMode !== 'system'
  const category = validCategory(value.category) ? value.category : 'general'
  const face = Math.max(0, Math.min(categories.find(item => item.id === category).kinds.length - 1, Number.isInteger(Number(value.face)) ? Number(value.face) : 0))
  return {
    category,
    grouping: groupings.includes(value.grouping) ? value.grouping : 'model',
    face,
    language: manualLanguage ? value.language : systemLanguage(locale ?? value.language),
    languageMode: manualLanguage ? 'manual' : 'system',
    theme,
    // A system-theme share starts with the sender's appearance, until the
    // receiver changes their system appearance or chooses an appearance option.
    appearance: theme === 'system' && appearances.includes(value.appearance) ? value.appearance : null,
    filters: normalizeFilters(value.filters, category, face),
  }
}

export function readSharedPreferences(query = {}) {
  if (typeof query.state !== 'string' || query.state.length > 4096) return null
  try {
    const raw = query.state.trim()
    const state = JSON.parse(raw.startsWith('{') ? raw : decodeURIComponent(raw))
    if (!isObject(state) || state.v !== 1 || !validCategory(state.c)
      || !groupings.includes(state.g) || !Number.isInteger(state.f) || state.f < 0 || state.f >= categories.find(item => item.id === state.c).kinds.length
      || !languages.includes(state.l) || !themes.includes(state.t)
      || !appearances.includes(state.a) || !isObject(state.x)) return null
    const filters = {}
    for (const kind of Object.keys(boards)) {
      const pair = hasOwn(state.x, kind) ? state.x[kind] : null
      if (Array.isArray(pair) && pair.length === 2) filters[kind] = { country: pair[0], openness: pair[1] }
    }
    return normalizePreferences({ category: state.c, grouping: state.g, face: state.f,
      language: state.l, theme: state.t, appearance: state.a, filters })
  } catch { return null }
}

export function pagePreferences(query = {}, saved = {}, locale) {
  const shared = readSharedPreferences(query)
  if (shared) return { ...shared, fromShare: true }
  const preferences = normalizePreferences(saved, locale)
  // Retain older category/face links and the about page's language/theme links.
  if (validCategory(query.category)) preferences.category = query.category
  if (groupings.includes(query.grouping)) preferences.grouping = query.grouping
  if (/^[0-2]$/.test(query.face)) preferences.face = Number(query.face)
  preferences.face = Math.min(preferences.face, categories.find(item => item.id === preferences.category).kinds.length - 1)
  if (languages.includes(query.language)) { preferences.language = query.language; preferences.languageMode = 'manual' }
  if (themes.includes(query.theme)) { preferences.theme = query.theme; preferences.appearance = null }
  preferences.filters = normalizeFilters(saved.filters, preferences.category, preferences.face)
  return { ...preferences, fromShare: false }
}

export function sharePath(value, appearance, path = '/pages/leaderboard/index') {
  const preferences = normalizePreferences(value)
  const actualAppearance = appearances.includes(appearance) ? appearance : preferences.theme === 'dark' ? 'dark' : 'light'
  const state = { v: 1, c: preferences.category, g: preferences.grouping, f: preferences.face,
    l: preferences.language, t: preferences.theme, a: actualAppearance,
    // All-default filters are deliberately omitted. The complete snapshot
    // replaces receiver preferences, so omission resets that board's filters.
    x: Object.fromEntries(Object.entries(preferences.filters).map(([kind, filter]) => [kind, [filter.country, filter.openness]])) }
  return `${path}?state=${encodeURIComponent(JSON.stringify(state))}`
}
