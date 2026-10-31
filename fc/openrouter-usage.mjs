import { readBounded } from './arena-dataset.mjs';
import { openRouterPriceRows } from './price-catalog.mjs';

export const openRouterKind = 'openRouterUsage';
export const openRouterSource = 'https://openrouter.ai/rankings';
export const openRouterInterval = 60 * 60 * 1000;
export const openRouterConfigured = () => Boolean(process.env.OPENROUTER_API_KEY?.trim());
export const openRouterModelsURL = 'https://openrouter.ai/api/v1/models';
const modelSlug = value => typeof value === 'string'
  && /^[a-zA-Z0-9][a-zA-Z0-9._-]*\/[a-zA-Z0-9][a-zA-Z0-9._+-]{0,240}(?::[a-zA-Z0-9._+-]+)?$/.test(value)
  && value.length <= 256;
const variant = value => value.includes(':') ? value.slice(value.indexOf(':')) : '';

// The usage dataset publishes permanent build slugs; models.dev lists the
// routable OpenRouter IDs. Join only the official catalog's explicit pair.
export function withOpenRouterModels(board, payload) {
  if (!Array.isArray(payload?.data) || payload.data.length > 10000) throw new Error('Invalid OpenRouter models');
  const identities = new Map();
  const prices = new Map(openRouterPriceRows(payload).map(row => [row.id, row]));
  for (const row of payload.data) {
    // Dynamic aliases are not pinned model identities.
    if (typeof row.id === 'string' && row.id.startsWith('~')) continue;
    if (!modelSlug(row.id) || !modelSlug(row.canonical_slug)
      || variant(row.canonical_slug) && variant(row.canonical_slug) !== variant(row.id)) throw new Error('Invalid OpenRouter identity');
    // canonical_slug may omit the route's variant; retain the variant from
    // this exact catalog row, never borrow the paid/default route's identity.
    const permaslug = row.canonical_slug + (variant(row.canonical_slug) ? '' : variant(row.id));
    const ids = identities.get(permaslug) ?? new Set();
    ids.add(row.id); identities.set(permaslug, ids);
  }
  return { ...board, entries: board.entries.map(entry => {
    const { openRouterModelID: ignored, ...original } = entry;
    const ids = identities.get(entry.modelID);
    if (ids?.size !== 1) return original;
    const id = [...ids][0], price = prices.get(id);
    return { ...original, openRouterModelID: id, ...(price && { taskCostUSD: price.input, outputPriceUSD: price.output }) };
  }) };
}

// The source exposes provider-specific p50 throughput; the best available
// provider is explicit, not an assumed default routing speed.
export function withOpenRouterSpeeds(board, responses) {
  return { ...board, entries: board.entries.map(entry => {
    const data = responses.get(entry.openRouterModelID)?.data;
    if (!data || data.id !== entry.openRouterModelID || !Array.isArray(data.endpoints)) return entry;
    const values = data.endpoints.map(endpoint => endpoint.throughput_last_30m?.p50)
      .filter(value => typeof value === 'number' && Number.isFinite(value) && value > 0);
    return values.length ? { ...entry, speed: Math.max(...values) } : entry;
  }) };
}

// Rank a single complete UTC day. Summing daily top-50 lists would silently
// undercount models that fell outside the top 50 on another day.
export function completedUsageDay(now) {
  return new Date(now - 86400000).toISOString().slice(0, 10);
}
export function parseOpenRouterUsage(payload, { now = Date.now(), day = completedUsageDay(now) } = {}) {
  const meta = payload?.meta;
  const validDay = value => /^\d{4}-\d{2}-\d{2}$/.test(value ?? '')
    && Number.isFinite(Date.parse(`${value}T00:00:00Z`))
    && new Date(`${value}T00:00:00Z`).toISOString().slice(0, 10) === value;
  const asOf = Date.parse(meta?.as_of);
  if (!validDay(day) || day >= new Date(now).toISOString().slice(0, 10)
    || meta?.start_date !== day || meta?.end_date !== day || meta?.version !== 'v1'
    || typeof meta?.as_of !== 'string' || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?Z$/.test(meta.as_of)
    || !Number.isFinite(asOf) || asOf > now + 300000
    || asOf < Date.parse(`${day}T00:00:00Z`) + 86400000
    || !Array.isArray(payload?.data) || !payload.data.length || payload.data.length > 51) throw new Error('Invalid OpenRouter dataset');
  const seen = new Set();
  const rows = payload.data.map(row => {
    if (row.date !== day || typeof row.model_permaslug !== 'string'
      || !(row.model_permaslug === 'other' || /^[a-zA-Z0-9][a-zA-Z0-9._-]*\/[a-zA-Z0-9][a-zA-Z0-9._:+-]{0,240}$/.test(row.model_permaslug))
      || seen.has(row.model_permaslug) || typeof row.total_tokens !== 'string'
      || !/^(0|[1-9]\d{0,19})$/.test(row.total_tokens)
      || BigInt(row.total_tokens) > 18446744073709551615n) throw new Error('Invalid OpenRouter row');
    seen.add(row.model_permaslug);
    return { ...row, tokens: BigInt(row.total_tokens) };
  });
  const models = rows.filter(row => row.model_permaslug !== 'other' && row.tokens > 0n)
    .sort((a, b) => a.tokens === b.tokens ? a.model_permaslug.localeCompare(b.model_permaslug, 'en') : a.tokens > b.tokens ? -1 : 1);
  if (!models.length || models.length > 50) throw new Error('Empty OpenRouter ranking');
  const citation = `Source: OpenRouter (openrouter.ai/rankings), as of ${meta.as_of}.\nLicensed under CC BY 4.0.\nhttps://creativecommons.org/licenses/by/4.0/`;
  return { kind: openRouterKind, title: 'OpenRouter', fetchedAt: new Date(now).toISOString(),
    sourceUpdatedAt: new Date(asOf).toISOString(), sourceMeta: { ...meta },
    sourceNote: `${citation}\nUTC ${day} · prompt + completion tokens · public traffic only.\nFiltered and rounded for display; company totals cover listed models only.\nSnapshot meta: ${JSON.stringify(meta)}`,
    otherTokens: rows.find(row => row.model_permaslug === 'other')?.total_tokens ?? '0',
    entries: models.map((row, index) => ({ rank: index + 1, modelID: row.model_permaslug,
      // Preserve the complete official identity, including :free/:variant.
      // Never guess a display name or developer from a partial model string.
      name: row.model_permaslug, organization: row.model_permaslug.split('/')[0],
      totalTokens: row.total_tokens, score: Number(row.tokens) / 1e9 })) };
}

export async function loadOpenRouterUsage({ now = Date.now(), apiKey = process.env.OPENROUTER_API_KEY,
  fetcher = fetch, signal = AbortSignal.timeout(10000), includeSpeeds = true } = {}) {
  if (!apiKey?.trim()) throw new Error('OpenRouter data source not configured');
  const day = completedUsageDay(now);
  const url = `https://openrouter.ai/api/v1/datasets/rankings-daily?start_date=${day}&end_date=${day}`;
  const response = await fetcher(url, { signal, redirect: 'error',
    headers: { Authorization: `Bearer ${apiKey.trim()}`, Accept: 'application/json' } });
  const data = await readBounded(response, 256000);
  const board = parseOpenRouterUsage(JSON.parse(data.toString('utf8')), { now, day });
  try {
    const models = await readBounded(await fetcher(openRouterModelsURL, {
      signal, redirect: 'error', headers: { Accept: 'application/json' },
    }), 8 * 1024 * 1024);
    const identified = withOpenRouterModels(board, JSON.parse(models.toString('utf8')));
    if (!includeSpeeds) return identified;
    const ids = [...new Set(identified.entries.map(entry => entry.openRouterModelID).filter(Boolean))];
    const responses = new Map(); let next = 0;
    await Promise.all(Array.from({ length: Math.min(6, ids.length) }, async () => {
      while (next < ids.length && !signal.aborted) {
        const id = ids[next++];
        try {
          const url = `https://openrouter.ai/api/v1/models/${id.split('/').map(encodeURIComponent).join('/')}/endpoints`;
          const response = await fetcher(url, { signal, redirect: 'error',
            headers: { Authorization: `Bearer ${apiKey.trim()}`, Accept: 'application/json' } });
          responses.set(id, JSON.parse((await readBounded(response, 512000)).toString('utf8')));
        } catch { /* Missing speed does not discard usage or prices. */ }
      }
    }));
    return withOpenRouterSpeeds(identified, responses);
  } catch { return board; } // Optional identity data must not discard valid usage.
}

export async function loadConfiguredOpenRouterUsage({ now = Date.now(), fetcher = fetch,
  environment = process.env } = {}) {
  const apiKey = environment.OPENROUTER_API_KEY?.trim();
  if (!apiKey) throw new Error('OpenRouter data source not configured');
  if (!environment.ARENA_COLLECTOR_ENDPOINT) return loadOpenRouterUsage({ now, apiKey, fetcher });
  const endpoint = new URL(environment.ARENA_COLLECTOR_ENDPOINT);
  if (endpoint.protocol !== 'https:' || endpoint.username || endpoint.password
    || endpoint.pathname !== '/' || endpoint.search || endpoint.hash || endpoint.port
    || !endpoint.hostname.endsWith('.ap-southeast-1.fcapp.run')
    || !/^[A-Za-z0-9_-]{43}$/.test(environment.ARENA_COLLECTOR_TOKEN ?? '')) throw new Error('Invalid collector configuration');
  const response = await fetcher(new URL('/v1/openrouter-usage', endpoint), {
    headers: { 'x-benchgauge-collector-key': environment.ARENA_COLLECTOR_TOKEN,
      Authorization: `Bearer ${apiKey}` }, signal: AbortSignal.timeout(22000), redirect: 'error',
  });
  const board = JSON.parse((await readBounded(response, 256000)).toString('utf8'));
  const fetched = Date.parse(board.fetchedAt), day = completedUsageDay(now);
  if (board.kind !== openRouterKind || !Array.isArray(board.entries) || !board.entries.length
    || board.entries.length > 50 || board.entries.some(entry => entry.modelID === 'other')
    || !Number.isFinite(fetched) || fetched > now + 300000 || fetched < now - 3600000) throw new Error('Invalid collected usage');
  // Revalidate original integer tokens and metadata, and regenerate attribution
  // instead of trusting collector-provided display fields.
  const parsed = parseOpenRouterUsage({ meta: board.sourceMeta, data: [
    ...board.entries.map(entry => ({ date: day, model_permaslug: entry.modelID, total_tokens: entry.totalTokens })),
    { date: day, model_permaslug: 'other', total_tokens: board.otherTokens },
  ] }, { now, day });
  const identified = withOpenRouterModels(parsed, { data: board.entries.filter(entry => entry.openRouterModelID != null)
    .map(entry => ({ id: entry.openRouterModelID, canonical_slug: entry.modelID })) });
  const collected = new Map(board.entries.map(entry => [entry.modelID, entry]));
  return { ...identified, entries: identified.entries.map(entry => {
    const item = collected.get(entry.modelID);
    if (!item || !entry.openRouterModelID || entry.openRouterModelID !== item.openRouterModelID) return entry;
    const validPrice = n => typeof n === 'number' && Number.isFinite(n) && n >= 0;
    return { ...entry, openRouterModelID: item.openRouterModelID,
      ...(validPrice(item.taskCostUSD) && validPrice(item.outputPriceUSD) && { taskCostUSD: item.taskCostUSD, outputPriceUSD: item.outputPriceUSD }),
      ...(typeof item.speed === 'number' && Number.isFinite(item.speed) && item.speed > 0 && { speed: item.speed }) };
  }) };
}
