import { countryCode, resolvedOpenness } from './domain.mjs'

// The full source model list is the denominator, including unknown metadata.
export function leaderboardDistribution(entries = []) {
  const total = entries.length, countries = new Map(), sources = new Map()
  for (const entry of entries) {
    const country = countryCode(entry), source = resolvedOpenness(entry) ?? 'unknown'
    countries.set(country, (countries.get(country) ?? 0) + 1)
    sources.set(source, (sources.get(source) ?? 0) + 1)
  }
  const slice = (id, count) => ({ id, count, fraction: total ? count / total : 0,
    percent: !total ? '—' : count > 0 && count / total < 0.001 ? '<0.1%' : `${(count / total * 100).toFixed(1)}%` })
  const known = [...countries].filter(([key]) => key !== 'unknown').sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
  const compact = known.slice(0, 5).map(([id, count]) => slice(id, count))
  const other = known.slice(5).reduce((sum, [, count]) => sum + count, 0)
  if (other) compact.push(slice('other', other))
  if (countries.has('unknown')) compact.push(slice('unknown', countries.get('unknown')))
  return { total, countries: compact, sources: ['open', 'closed', 'unknown']
    .filter(id => id !== 'unknown' || sources.has(id)).map(id => slice(id, sources.get(id) ?? 0)) }
}
