import { opennessIcon } from './openness-icon.js'
import { bundledFlags } from './flag-catalog.js'
import { boards, text, copy, hasOwn } from './catalog.js'
import brandCatalog from '../../../../fc/brand-catalog.json' with { type: 'json' }
import companyCatalog from '../../../../assets/logos/company-catalog.json' with { type: 'json' }
import { purchaseLinks, preferredPurchaseLink } from './purchase-links.js'
import { canReplace, countryCode, companyRows, latestTimestamp, createBrandRules, normalizedCountryCode, resolvedOpenness } from '../../../../fc/domain.mjs'
export { canReplace, countryCode, companyRows, latestTimestamp } from '../../../../fc/domain.mjs'
const brandRules = createBrandRules(brandCatalog)
const bundledBrands = new Set(Object.keys(brandCatalog.colors))
const bundledCompanies = new Set([...bundledBrands, ...Object.keys(companyCatalog)])

export function normalizeBoard(value, kind) {
  if (!hasOwn(boards, kind) || !value || value.kind !== kind
    || !Number.isFinite(Date.parse(value.fetchedAt)) || !Array.isArray(value.entries)
    || !value.entries.length) throw new Error('Invalid shared snapshot')
  if (value.sourceUpdatedAt && !Number.isFinite(Date.parse(value.sourceUpdatedAt))) throw new Error('Invalid publication time')
  const seen = new Set()
  const entries = value.entries.map(entry => {
    if (!Number.isInteger(entry.rank) || entry.rank <= 0 || seen.has(entry.rank)
      || typeof entry.name !== 'string' || !entry.name.trim() || !Number.isFinite(entry.score) || entry.score < 0) throw new Error('Invalid ranking entry')
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

export function formatTime(value) {
  const date = new Date(value)
  if (!value || !Number.isFinite(date.getTime())) return '—'
  return `${date.getMonth() + 1}/${date.getDate()} ${String(date.getHours()).padStart(2, '0')}:${String(date.getMinutes()).padStart(2, '0')}`
}
export function scoreShareText(score, leaderScore) {
  if (!Number.isFinite(score) || score < 0 || !Number.isFinite(leaderScore) || leaderScore <= 0) return ''
  const percent = Math.round(score / leaderScore * 100)
  return percent < 100 ? `${percent}%` : ''
}
export function rowView(entry, { company = false, dark = false, details = true, language = 'en', category = 'general', kind, leaderScore } = {}) {
  const productKey = !company ? brandRules.bundledProductKey(entry) : null
  const modelBrand = !company ? brandRules.knownModelBrand(entry) : null
  const brand = company ? entry.organizationBrand || entry.brand : entry.brand?.key?.startsWith('model-') ? entry.brand : modelBrand || entry.brand
  let image = typeof brand?.pngData === 'string' && /^[A-Za-z0-9+/=]+$/.test(brand.pngData) && brand.pngData.length < 160000
    ? `data:image/png;base64,${brand.pngData}` : ''
  // A missing dedicated model mark must not hide its verified provider's bundled
  // icon. Use the complete shared catalog, including image/video providers.
  const key = company
    ? [brand?.key, entry.developerCountry?.key, brandRules.normalizedBrandKey(entry.organization)].find(key => bundledCompanies.has(key))
    : productKey || [brandRules.brandKey(entry)].find(key => bundledBrands.has(key))
  if (!company && !brand?.key?.startsWith('model-') && (productKey || key && !brandRules.sharedProviderMark(entry))) image = ''
  if (!image && key) image = `/assets/logos/${key}.png`
  const color = /^#[0-9a-f]{6}$/i.test(brand?.colorHex || '') ? brand.colorHex : '#62748b'
  const rgb = [1, 3, 5].map(i => parseInt(color.slice(i, i + 2), 16)).join(',')
  const links = company ? purchaseLinks(entry.organization, { modelName: entry.name, category }) : null
  const actions = links ? [['codingPlan', 'plan'], ['payAsYouGo', 'payAsYouGo']].flatMap(([kind, label]) => {
    const link = preferredPurchaseLink(links[kind], language)
    return link ? [{ kind, title: text(copy[label], language), url: link.url }] : []
  }) : []
  const code = countryCode(entry)
  return { rank: entry.rank, name: entry.name, score: entry.score, logo: image,
    purchaseActions: actions,
    initial: [...entry.name][0], countryUnknown: countryCode(entry) === 'unknown', countryName: countryName(countryCode(entry), language),
    flag: countryCode(entry) === 'unknown' ? '?' : countryFlag(countryCode(entry)),
    countryCode: code, flagImage: bundledFlags.has(code) ? `/assets/flags/${code.toLowerCase()}.png` : '',
    components: details ? entry.components?.map(member => ({ name: member.name, rank: member.rank, score: member.score.toFixed(kind === 'epochECI' ? 2 : 1) })) || [] : [],
    scoreText: entry.score.toFixed(kind === 'epochECI' ? 2 : 1), scoreShare: scoreShareText(entry.score, leaderScore), openness: company ? null : resolvedOpenness(entry),
    opennessIcon: opennessIcon(company ? null : resolvedOpenness(entry), dark),
    fill: `background-color:rgba(${rgb},${dark ? '0.26' : '0.18'});`,
    fillPercent: Number.isFinite(entry.score) && entry.score >= 0 && Number.isFinite(leaderScore) && leaderScore > 0
      ? Math.min(100, entry.score / leaderScore * 100) : 100,
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
export function rankedEntries(board, { grouping = 'model', country = 'all', openness = 'all', query = '' } = {}) {
  country = normalizedCountryCode(country) ?? country
  const entries = (board?.entries || []).filter(entry => (country === 'all' || countryCode(entry) === country)
    && (openness === 'all' || (resolvedOpenness(entry) || 'unknown') === openness))
  return grouping === 'company' ? companyRows(entries) : entries.filter(entry => modelNameMatches(entry.name, query))
}
export function visibleRows(board, { grouping = 'model', country = 'all', openness = 'all', query = '', dark = false, language = 'en', category = 'general' } = {}) {
  const leaderScore = rankedEntries(board, { grouping, country, openness })[0]?.score
  const rows = rankedEntries(board, { grouping, country, openness, query })
  return rows.map(entry => rowView(entry, { company: grouping === 'company', dark, language, category, kind: board?.kind, leaderScore }))
}
