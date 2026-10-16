import catalog from './brand-catalog.json' with { type: 'json' }
import policy from './leaderboard-policy.json' with { type: 'json' }
// Pure leaderboard rules shared by the FC service and WeChat client.
// Platform adapters own network/storage and UI formatting; this module owns identity and selection.
const hasOwn = (object, key) => Object.prototype.hasOwnProperty.call(object, key)
export function replacementFailure(next, previous) {
  if (!previous) return null
  if (next.kind !== previous.kind) return 'kind'
  if (previous.sourceUpdatedAt && (!next.sourceUpdatedAt || Date.parse(next.sourceUpdatedAt) < Date.parse(previous.sourceUpdatedAt))) return 'source'
  if (Date.parse(next.fetchedAt) < Date.parse(previous.fetchedAt)) return 'snapshot'
  return null
}
export const canReplace = (next, previous) => replacementFailure(next, previous) === null
export function latestTimestamp(board) {
  const dates = [board?.sourceUpdatedAt, board?.fetchedAt].filter(value => value && Number.isFinite(Date.parse(value)))
  return dates.reduce((latest, value) => !latest || Date.parse(value) > Date.parse(latest) ? value : latest, null)
}
export function createBrandRules(catalog) {
  const normalizedBrandKey = value => { const key = String(value ?? '').toLowerCase().replace(/[^\p{L}\p{N}]/gu, ''); return hasOwn(catalog.aliases, key) ? catalog.aliases[key] : key }
  function brandKey(entry) {
    const organization = normalizedBrandKey(entry.organization)
    const model = entry.name?.split(' - ')[1]?.split(' + ')[0]
    let hosted
    if (model) for (const token of model.toLowerCase().split(/[^\p{L}\p{N}]+/u)) {
      for (const [family,key] of catalog.families) {
        if (token === family || token.startsWith(family) && /^\d/.test(token.slice(family.length))) { hosted = key; break }
      }
      if (hosted) break
    }
    if (!organization || ['unknown','other','na','none'].includes(organization)) {
      const name = String(entry.name ?? '').trim().toLowerCase()
      const verified = hasOwn(catalog.modelDevelopers ?? {}, name) ? catalog.modelDevelopers[name] : null
      return normalizedBrandKey(entry.name).startsWith('devin') ? 'devin' : hosted ?? verified
    }
    return hosted ?? organization
  }
  function knownModelBrand(entry) {
    const name = String(entry.name ?? '').toLowerCase().replace(/[-_]+/g, ' ')
    const organization = normalizedBrandKey(entry.organization)
    const model = catalog.modelLogos.find(model => model.organizations.includes(organization) && model.prefixes.some(raw => {
      const prefix = raw.replace(/[-_]+/g, ' ')
      return name.startsWith(prefix) && (name.length === prefix.length || /[\d\s._-]/.test(name[prefix.length]))
    }))
    return model ? { key: `model-${model.key}`, sourceURL: model.sourceURL, colorHex: model.colorHex, pngData: model.pngData, status: 'ready' } : null
  }
  function bundledProductKey(entry) {
    const tokens = String(entry.name ?? '').toLowerCase().split(/[^\p{L}\p{N}]+/u)
    const organization = brandKey(entry)
    for (const token of tokens) for (const [family,key] of catalog.families) {
      if (catalog.bundledModelMarks.includes(key) && key === organization && (token === family || token.startsWith(family) && /^\d/.test(token.slice(family.length)))) return key
    }
    return null
  }
  const sharedProviderMark = entry => policy.sharedModelProviderMarks.includes(brandKey(entry))
  return { normalizedBrandKey, brandKey, knownModelBrand, bundledProductKey, sharedProviderMark }
}
export function normalizedCountryCode(value) {
  const code = typeof value === 'string' ? value.trim().toUpperCase() : ''
  if (hasOwn(policy.countryOverrides, code)) return policy.countryOverrides[code]
  return /^[A-Z]{2}$/.test(code) ? code : null
}
export function countryCode(entry) {
  return normalizedCountryCode(entry.developerCountry?.countryCode) ?? 'unknown'
}
const rules = createBrandRules(catalog)
function companyIdentity(entry) {
  const key = rules.brandKey(entry)
  if (!key) return null
  const raw = typeof entry.organization === 'string' ? entry.organization.trim() : ''
  const name = hasOwn(policy.companyNames, key) ? policy.companyNames[key] : rules.normalizedBrandKey(raw) === key ? raw : key
  return { key, name }
}
export function companyRows(entries) {
  const groups = new Map()
  for (const entry of entries) {
    const identity = companyIdentity(entry)
    if (!identity) continue
    if (!groups.has(identity.key)) groups.set(identity.key, { ...identity, members: [] })
    groups.get(identity.key).members.push(entry)
  }
  const strongest = (a, b) => b.score - a.score || a.rank - b.rank || a.name.localeCompare(b.name)
  return [...groups.values()].map(group => {
    const members = group.members.sort(strongest)
    const best = members[0]
    const matchedCountry = members.map(member => member.developerCountry).find(country => {
      if (!country?.key || countryCode({ developerCountry: country }) === 'unknown') return false
      return rules.normalizedBrandKey(country.key) === group.key
    })
    const developerCountry = matchedCountry ? { ...matchedCountry, countryCode: countryCode({ developerCountry: matchedCountry }) } : undefined
    const brands = members.flatMap(member => [member.organizationBrand, member.brand])
      .filter(brand => brand && rules.normalizedBrandKey(brand.key) === group.key)
    // The strongest model may still be waiting for its company image. Reuse a
    // verified provider mark from any sibling, without borrowing a model/harness mark.
    const organizationBrand = brands.find(brand => typeof brand.pngData === 'string'
      && /^[A-Za-z0-9+/=]+$/.test(brand.pngData) && brand.pngData.length < 160000)
      ?? brands[0] ?? { key: group.key }
    return { ...best, name: group.name, bestRank: best.rank, openness: null,
      brand: organizationBrand, organizationBrand, developerCountry, components: members }
  }).sort((a, b) => b.score - a.score || a.bestRank - b.bestRank || a.name.localeCompare(b.name))
    .map((entry, index) => ({ ...entry, rank: index + 1 }))
}

