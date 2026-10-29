import { readBounded } from './arena-dataset.mjs'

// OpenRouter quotes USD/token; display prices use USD/million tokens.
const finitePrice = value => typeof value === 'number' && Number.isFinite(value) && value >= 0
const validText = value => typeof value === 'string' && value.trim().length > 0 && value.length <= 512

function openRouterPrice(value) {
  if (typeof value !== 'string' || !/^(?:\d+(?:\.\d*)?|\.\d+)(?:e[+-]?\d+)?$/i.test(value)) return undefined
  const price = Number(value) * 1_000_000
  return finitePrice(price) ? price : undefined
}

export function openRouterPriceRows(catalog) {
  if (!Array.isArray(catalog?.data)) throw new Error('Invalid OpenRouter price catalog')
  return catalog.data.flatMap(model => {
    if (!validText(model?.id) || !validText(model?.name) || !Array.isArray(model.architecture?.input_modalities) || !model.architecture.input_modalities.includes('text')
      || !Array.isArray(model.architecture?.output_modalities) || !model.architecture.output_modalities.includes('text')) return []
    const input = openRouterPrice(model.pricing?.prompt), output = openRouterPrice(model.pricing?.completion)
    if (input === undefined || output === undefined) return []
    return [{ id: model.id, name: model.name, provider: 'OpenRouter', input, output, currency: 'USD', unit: 'per-million-tokens' }]
  })
}

export function priceBoard(kind, catalog) {
  if (kind !== 'openRouterPrice' || !Array.isArray(catalog?.rows)
    || !Number.isFinite(Date.parse(catalog.fetchedAt))) throw new Error('Invalid price catalog')
  const source = 'OpenRouter'
  if (catalog.source !== source) throw new Error('Invalid price source')
  const rows = catalog.rows.map(row => {
    if (!validText(row.id) || !validText(row.name) || !finitePrice(row.input) || !finitePrice(row.output)
      || row.currency !== 'USD' || row.unit !== 'per-million-tokens') throw new Error('Invalid price row')
    const provider = row.providerName ?? row.provider
    if (!validText(provider)) throw new Error('Invalid price provider')
    return { name: row.name,
      modelID: row.id, provider, organization: row.id.split('/')[0], score: row.input, outputPriceUSD: row.output }
  }).sort((a, b) => a.score - b.score || a.outputPriceUSD - b.outputPriceUSD || a.name.localeCompare(b.name) || a.modelID.localeCompare(b.modelID))
  if (!rows.length || rows.length > 50000) throw new Error('Empty price catalog')
  return { kind, title: source, fetchedAt: catalog.fetchedAt, entries: rows.map((row, i) => ({ rank: i + 1, ...row })) }
}

export async function loadOpenRouterPrices({ now = Date.now(), fetcher = fetch, signal = AbortSignal.timeout(18000) } = {}) {
  const response = await fetcher('https://openrouter.ai/api/v1/models', { signal, redirect: 'error', headers: { Accept: 'application/json' } })
  const data = JSON.parse((await readBounded(response, 8 * 1024 * 1024)).toString('utf8'))
  const rows = openRouterPriceRows(data)
  if (rows.length < 20 || rows.length > 10000) throw new Error('Incomplete OpenRouter price catalog')
  return { source: 'OpenRouter', fetchedAt: new Date(now).toISOString(), rows }
}

export async function loadConfiguredOpenRouterPrices({ now = Date.now(), fetcher = fetch, environment = process.env } = {}) {
  if (!environment.ARENA_COLLECTOR_ENDPOINT) return loadOpenRouterPrices({ now, fetcher })
  const endpoint = new URL(environment.ARENA_COLLECTOR_ENDPOINT)
  if (endpoint.protocol !== 'https:' || endpoint.username || endpoint.password || endpoint.pathname !== '/' || endpoint.search || endpoint.hash || endpoint.port
    || !endpoint.hostname.endsWith('.ap-southeast-1.fcapp.run') || !/^[A-Za-z0-9_-]{43}$/.test(environment.ARENA_COLLECTOR_TOKEN ?? '')) throw new Error('Invalid collector configuration')
  const response = await fetcher(new URL('/v1/openrouter-prices', endpoint), { redirect: 'error', signal: AbortSignal.timeout(22000), headers: { 'x-benchgauge-collector-key': environment.ARENA_COLLECTOR_TOKEN } })
  const data = JSON.parse((await readBounded(response, 4 * 1024 * 1024)).toString('utf8'))
  const fetched = Date.parse(data.fetchedAt)
  if (data.source !== 'OpenRouter' || !Number.isFinite(fetched) || fetched > now + 300000 || fetched < now - 3600000
    || !Array.isArray(data.rows) || data.rows.length < 20 || data.rows.length > 10000
    || !data.rows.every(row => validText(row.id) && validText(row.name) && row.provider === 'OpenRouter'
      && row.currency === 'USD' && row.unit === 'per-million-tokens' && finitePrice(row.input) && finitePrice(row.output))) throw new Error('Invalid collected prices')
  return data
}
