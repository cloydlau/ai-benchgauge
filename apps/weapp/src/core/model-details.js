import labels from '../../../../Sources/LeaderboardKit/Resources/ModelDetailLabels.json' with { type: 'json' }

export const detailText = (key, language = 'en') => labels[key]?.[language === 'en' ? 0 : ['zh-Hant', 'zh-TW'].includes(language) ? 2 : 1] ?? key.replaceAll('_', ' ')
export const safeDetailURL = value => typeof value === 'string' && /^https:\/\/[^\s/?#@]+(?:[/?#]|$)/i.test(value) ? value : null
const number = value => value.toLocaleString('en-US', { maximumFractionDigits: 12 })
export function modelDetailSections(entry, language = 'en') {
  const model = entry?.modelMetadata
  if (model?.source !== 'models.dev') return []
  const tr = key => detailText(key, language)
  function scalar(value, money) {
    if (typeof value === 'boolean') return tr(String(value))
    if (typeof value === 'number') return `${money ? '$' : ''}${number(value)}`
    if (typeof value === 'string' && value) return labels[value] ? tr(value) : value
    return null
  }
  function rows(value, prefix = [], money = false) {
    const formatted = scalar(value, money)
    if (formatted !== null) return [{ label: prefix.join(' · '), value: formatted, url: safeDetailURL(formatted) }]
    if (Array.isArray(value)) {
      const values = value.map(item => scalar(item, money))
      if (values.length && values.every(v => v !== null)) return [{ label: prefix.join(' · '), value: values.join(' · '), url: null }]
      return value.flatMap((item, i) => rows(item, [...prefix, String(i + 1)], money))
    }
    return value && typeof value === 'object' ? Object.keys(value).sort().flatMap(key => rows(value[key], [...prefix, tr(key)], money && key !== 'tier')) : []
  }
  const result = [], attributes = { ...model.attributes }
  const add = (id, title, values, summary = null) => { if (values.length) result.push({ id, title, summary, rows: values }) }
  const general = Object.fromEntries(['id', 'name', 'license', 'releaseDate', 'lastUpdated', 'openWeights'].filter(k => model[k] != null).map(k => [k, model[k]]))
  general.license ??= tr('unknown')
  for (const key of ['description', 'family', 'type', 'knowledge']) { if (attributes[key] != null) general[key] = attributes[key]; delete attributes[key] }
  add('general', tr('general'), rows(general))
  add('limits', tr('limit'), rows(model.limit))
  const capabilities = {}
  for (const key of ['attachment', 'reasoning', 'tool_call', 'structured_output', 'temperature']) { if (attributes[key] != null) capabilities[key] = attributes[key]; delete attributes[key] }
  add('capabilities', tr('capabilities'), rows(capabilities))
  for (const key of ['modalities', 'links', 'weights']) { add(key, tr(key), rows(attributes[key])); delete attributes[key] }
  for (const [i, benchmark] of (attributes.benchmarks || []).entries()) {
    const { name, ...values } = benchmark
    add(`benchmark-${i}`, `${tr('benchmark')} · ${name || i + 1}`, rows(values))
  }
  delete attributes.benchmarks
  add('additional', tr('additional'), rows(attributes))
  for (const [i, offer] of (model.offers || []).entries()) {
    let values = rows(offer.modelID, [tr('modelID')])
    values.push(...rows(offer.status, [tr('status')]), ...rows(offer.limit, [tr('limit')]))
    let summary = tr('unknown')
    if (offer.cost) {
      values.push(...rows(offer.cost, [tr('cost')], true))
      summary = `${tr('input')} $${number(offer.cost.input)} · ${tr('output')} $${number(offer.cost.output)} · ${tr('pricing')}`
    } else values.push({ label: tr('cost'), value: tr('unknown'), url: null })
    values.push(...rows(offer.attributes))
    add(`provider-${i}`, offer.providerName, values, summary)
  }
  add('source', tr('provenance'), [{ label: tr('source'), value: 'models.dev · MIT', url: 'https://models.dev' },
    { label: tr('fetchedAt'), value: model.fetchedAt, url: null }, { label: '', value: tr('licenseNote'), url: null }])
  return result
}
