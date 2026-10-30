import { opennessIcon } from './openness-icon.js'
import { bundledFlags } from './flag-catalog.js'
import { boards, text, copy, hasOwn } from './catalog.js'
import { purchaseLinks, preferredPurchaseLink } from './purchase-links.js'
import { canReplace, countryCode, companyRows, latestTimestamp, normalizedCountryCode, resolvedOpenness, taskCostText, validTaskCost } from '../../../../fc/domain.mjs'
export { canReplace, countryCode, companyRows, latestTimestamp, contentTimestamp, withContentTimestamp } from '../../../../fc/domain.mjs'
export function normalizeBoard(value, kind) {
  if (!hasOwn(boards, kind) || !value || value.kind !== kind
    || !Number.isFinite(Date.parse(value.fetchedAt)) || !Array.isArray(value.entries)
    || !value.entries.length) throw new Error('Invalid shared snapshot')
  if (value.sourceUpdatedAt && !Number.isFinite(Date.parse(value.sourceUpdatedAt))) throw new Error('Invalid publication time')
  if (value.contentUpdatedAt && (!Number.isFinite(Date.parse(value.contentUpdatedAt))
    || Date.parse(value.contentUpdatedAt) > Date.parse(value.fetchedAt))) throw new Error('Invalid content update time')
  const seen = new Set()
  const entries = value.entries.map(entry => {
    if (!Number.isInteger(entry.rank) || entry.rank <= 0 || seen.has(entry.rank)
      || typeof entry.name !== 'string' || !entry.name.trim() || !Number.isFinite(entry.score) || entry.score < 0) throw new Error('Invalid ranking entry')
    if (entry.speed != null && !(typeof entry.speed === 'number' && Number.isFinite(entry.speed) && entry.speed > 0)) throw new Error('Invalid speed')
    if (entry.taskCostUSD != null && !validTaskCost(entry.taskCostUSD)) throw new Error('Invalid task cost')
    if (isPriceBoard(kind) && !validTaskCost(entry.outputPriceUSD)) throw new Error('Invalid output price')
    seen.add(entry.rank)
    return { ...entry, name: entry.name.trim(), openness: resolvedOpenness(entry),
      ...(entry.developerCountry && { developerCountry: { ...entry.developerCountry, countryCode: normalizedCountryCode(entry.developerCountry.countryCode) } }) }
  }).sort((a, b) => a.rank - b.rank)
  return { ...value, entries }
}

export const countryFlag = value => {
  const code = normalizedCountryCode(value)
  return code ? String.fromCodePoint(...[...code].map(letter => letter.charCodeAt(0) + 127397)) : '—'
}
export const countryFlagImage = value => {
  const code = normalizedCountryCode(value)
  return bundledFlags.has(code) ? `/assets/flags/${code.toLowerCase()}.png` : ''
}
const countryNames = {
  US: ['United States', '美国', '美國'], CN: ['China', '中国', '中國'], FR: ['France', '法国', '法國'],
  CA: ['Canada', '加拿大', '加拿大'], IL: ['Israel', '以色列', '以色列'], DE: ['Germany', '德国', '德國'],
  GB: ['United Kingdom', '英国', '英國'], SG: ['Singapore', '新加坡', '新加坡'], JP: ['Japan', '日本', '日本'],
  KR: ['South Korea', '韩国', '韓國'], AE: ['United Arab Emirates', '阿联酋', '阿聯酋'], CH: ['Switzerland', '瑞士', '瑞士'],
  AU: ['Australia', '澳大利亚', '澳大利亞'], RU: ['Russia', '俄罗斯', '俄羅斯'],
}
export function countryName(value, language = 'en') {
  const code = normalizedCountryCode(value)
  return code ? (countryNames[code] ? text(countryNames[code], language) : code) : text(copy.unknown, language)
}
export function countryOptions(board, language, selected = 'all') {
  const codes = [...new Set([...(board?.entries || []).map(countryCode),
    ...(/^(unknown|[A-Z]{2})$/.test(selected) ? [normalizedCountryCode(selected) ?? selected] : [])])].sort()
  return [{ value: 'all', label: text(copy.all, language) }, ...codes.map(code => ({ value: code,
    label: code === 'unknown' ? text(copy.unknown, language) : `${countryFlag(code)} ${countryName(code, language)}` }))]
}

export function formatTime(value, language = 'en', now = new Date(), { dateOnly = false, utc = false } = {}) {
  const date = new Date(value)
  if (!value || !Number.isFinite(date.getTime())) return '—'
  const part = (date, name) => date[`get${utc ? 'UTC' : ''}${name}`]()
  const dayNumber = date => Date.UTC(part(date, 'FullYear'), part(date, 'Month'), part(date, 'Date')) / 86400000
  const days = dayNumber(new Date(now)) - dayNumber(date)
  const label = days >= 0 && days <= 3
    ? (language === 'en' ? ['Today', 'Yesterday', '2 days ago', '3 days ago'] : ['今天', '昨天', '前天', '大前天'])[days]
    : `${part(date, 'Month') + 1}/${part(date, 'Date')}`
  return dateOnly ? label : `${label} ${String(part(date, 'Hours')).padStart(2, '0')}:${String(part(date, 'Minutes')).padStart(2, '0')}`
}
export function scoreShareText(score, leaderScore) {
  if (!Number.isFinite(score) || score < 0 || !Number.isFinite(leaderScore) || leaderScore <= 0) return ''
  const percent = Math.round(score / leaderScore * 100)
  return percent < 100 ? `${percent}%` : ''
}
export const usageScoreText = score => score > 0 && score < 0.01 ? '<0.01B' : `${score.toFixed(2)}B`
export const shareScoreText = score => score > 0 && score < 0.01 ? '<0.01%' : `${score.toFixed(2)}%`
export const isAAImageCost = kind => ['artificialAnalysisTextToImage', 'artificialAnalysisImageEditing'].includes(kind)
export const isAAVideoCost = kind => ['artificialAnalysisTextToVideo', 'artificialAnalysisImageToVideo', 'artificialAnalysisVideoEditing'].includes(kind)
export const isErrorRate = kind => ['artificialAnalysisSpeechToText', 'artificialAnalysisSpeechToTextStreaming'].includes(kind)
export const supportsAACost = kind => ['openRouterUsage', 'artificialAnalysis', 'artificialAnalysisCodingAgent', 'valsSWEbench'].includes(kind) || isAAImageCost(kind) || isAAVideoCost(kind)
export const supportsAASpeed = kind => ['openRouterUsage', 'artificialAnalysis', 'artificialAnalysisCodingAgent', 'valsSWEbench'].includes(kind)
export const speedText = value => Number.isFinite(value) && value > 0 ? value.toFixed(value < 10 ? 1 : 0) : '—'
export const isPriceBoard = kind => kind === 'openRouterPrice'
export function dollarParts(value) {
  const index = value.indexOf('$')
  return index < 0 ? null : { before: value.slice(0, index), after: value.slice(index + 1) }
}
export function rowView(entry, { company = false, dark = false, details = true, language = 'en', category = 'general', kind, leaderScore, costMode = false, speedMode = false } = {}) {
  const brand = company ? entry.organizationBrand || entry.brand : entry.brand
  const image = typeof brand?.pngData === 'string' && /^[A-Za-z0-9+/=]+$/.test(brand.pngData) && brand.pngData.length < 160000
    ? `data:image/png;base64,${brand.pngData}` : ''
  const color = /^#[0-9a-f]{6}$/i.test(brand?.colorHex || '') ? brand.colorHex : '#62748b'
  const rgb = [1, 3, 5].map(i => parseInt(color.slice(i, i + 2), 16)).join(',')
  const links = company ? purchaseLinks(entry.organization, { modelName: entry.name, category }) : null
  const actions = links ? [['codingPlan', 'plan'], ['payAsYouGo', 'payAsYouGo']].flatMap(([kind, label]) => {
    const link = preferredPurchaseLink(links[kind], language)
    return link ? [{ kind, title: text(copy[label], language), url: link.url }] : []
  }) : []
  const code = countryCode(entry)
  const rankChangeText = entry.rankChange?.isNew ? (language === 'en' ? 'New' : '新')
    : Number.isSafeInteger(entry.rankChange?.delta) && entry.rankChange.delta !== 0 ? `${entry.rankChange.delta > 0 ? '↑' : '↓'}${Math.abs(entry.rankChange.delta)}` : ''
  const value = speedMode && supportsAASpeed(kind) ? entry.speed : costMode && supportsAACost(kind) ? entry.taskCostUSD : entry.score
  const scoreText = isErrorRate(kind) ? `${value.toFixed(2)}%` : speedMode && supportsAASpeed(kind) ? speedText(value) : costMode && supportsAACost(kind) || isPriceBoard(kind) ? taskCostText(value) : ['vercelUsage', 'cloudbaseUsage'].includes(kind) ? shareScoreText(value) : kind === 'openRouterUsage' ? usageScoreText(value) : value.toFixed(kind === 'epochECI' ? 2 : 1)
  const outputPriceText = isPriceBoard(kind) || (kind === 'openRouterUsage' && costMode) ? taskCostText(entry.outputPriceUSD) : null
  const scoreDollar = dollarParts(scoreText), outputDollar = outputPriceText && dollarParts(outputPriceText)
  return { rank: entry.rank, name: entry.name, score: entry.score, logo: image,
    ...(outputPriceText && { outputPriceText }), ...(scoreDollar && { scoreDollar }), ...(outputDollar && { outputDollar }),
    rankChangeText,
    rankChangeTone: rankChangeText ? (entry.rankChange?.isNew ? 'new' : entry.rankChange.delta > 0 ? 'up' : 'down') : undefined,
    purchaseActions: actions,
    initial: [...entry.name][0], countryUnknown: countryCode(entry) === 'unknown', countryName: countryName(countryCode(entry), language),
    flag: countryCode(entry) === 'unknown' ? '?' : countryFlag(countryCode(entry)),
    countryCode: code, flagImage: countryFlagImage(code),
    components: details ? entry.components?.map(member => ({ name: member.name, rank: member.rank, score: isErrorRate(kind) ? `${member.score.toFixed(2)}%` : ['vercelUsage', 'cloudbaseUsage'].includes(kind) ? shareScoreText(member.score) : kind === 'openRouterUsage' ? usageScoreText(member.score) : member.score.toFixed(kind === 'epochECI' ? 2 : 1) })) || [] : undefined,
    scoreText, scoreShare: isErrorRate(kind) || ['vercelUsage', 'cloudbaseUsage'].includes(kind) || isPriceBoard(kind) ? '' : scoreShareText(value, leaderScore), openness: company ? null : resolvedOpenness(entry),
    opennessIcon: opennessIcon(company ? null : resolvedOpenness(entry), dark),
    fill: `background-color:rgba(${rgb},${dark ? '0.26' : '0.18'});`,
    fillPercent: isErrorRate(kind) ? 0 : Number.isFinite(value) && value >= 0 && Number.isFinite(leaderScore) && leaderScore > 0
      ? Math.min(100, value / leaderScore * 100) : costMode || speedMode || isPriceBoard(kind) ? 0 : 100,
    medal: ['🥇', '🥈', '🥉'][entry.rank - 1] || String(entry.rank),
  }
}
export function modelNameMatches(name, query) {
  if (!String(query || '').trim()) return true
  const fold = value => String(value || '').normalize('NFKD').replace(/[\u0300-\u036f]/g, '').toLowerCase()
  const tokens = fold(query).trim().split(/\s+/).filter(Boolean)
  const value = fold(name)
  return tokens.every(token => value.includes(token))
}
export function rankedEntries(board, { grouping = 'model', country = 'all', openness = 'all', query = '', sort = 'score', priceAscending = false } = {}) {
  country = normalizedCountryCode(country) ?? country
  const entries = (board?.entries || []).filter(entry => (country === 'all' || countryCode(entry) === country)
    && (openness === 'all' || (resolvedOpenness(entry) || 'unknown') === openness))
  const ranked = grouping === 'company' && !isPriceBoard(board?.kind)
    ? companyRows(entries, { summingUsage: ['openRouterUsage', 'vercelUsage', 'cloudbaseUsage'].includes(board?.kind), lowerIsBetter: isErrorRate(board?.kind) }) : entries
  const ordered = isPriceBoard(board?.kind) ? [...ranked].sort((a, b) => {
    const direction = priceAscending ? 1 : -1
    return direction * (a.score - b.score || (a.outputPriceUSD ?? 0) - (b.outputPriceUSD ?? 0)) || (a.name < b.name ? -1 : a.name > b.name ? 1 : 0) || ((a.modelID ?? '') < (b.modelID ?? '') ? -1 : (a.modelID ?? '') > (b.modelID ?? '') ? 1 : 0)
  }).map((entry, index) => ({ ...entry, rank: index + 1, rankChange: undefined })) : ranked
  return ordered.filter(entry => modelNameMatches(entry.name, query))
}
export function visibleRows(board, { grouping = 'model', country = 'all', openness = 'all', query = '', dark = false, language = 'en', category = 'general', sort = 'score', priceAscending = false } = {}) {
  const costMode = supportsAACost(board?.kind) && sort === 'cost'
  const speedMode = supportsAASpeed(board?.kind) && sort === 'speed'
  const unsearched = rankedEntries(board, { grouping, country, openness, priceAscending })
  const prices = unsearched.map(row => row.taskCostUSD).filter(validTaskCost)
  const speeds = unsearched.map(row => row.speed).filter(value => Number.isFinite(value) && value > 0)
  const leaderScore = speedMode ? (speeds.length ? Math.max(...speeds) : undefined) : costMode ? (prices.length ? Math.max(...prices) : undefined) : isPriceBoard(board?.kind) ? Math.max(...unsearched.map(row => row.score), 0) : unsearched[0]?.score
  const rows = rankedEntries(board, { grouping, country, openness, query, sort, priceAscending })
  return rows.map(entry => rowView(entry, { company: grouping === 'company', dark, language, category, kind: board?.kind, leaderScore, costMode, speedMode }))
}
