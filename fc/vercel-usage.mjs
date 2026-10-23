import { readBounded } from './arena-dataset.mjs';

export const vercelKind = 'vercelUsage';
export const vercelInterval = 24 * 60 * 60 * 1000;
export const vercelExportURL = 'https://vercel.com/api/ai/leaderboard-export?dataset=models&modality=text';
export const vercelModelsURL = 'https://ai-gateway.vercel.sh/v1/models';
export const vercelSource = 'https://vercel.com/ai-gateway/leaderboards/models';
const licenseURL = 'https://creativecommons.org/licenses/by/4.0/';
const validDay = value => typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value)
  && Number.isFinite(Date.parse(`${value}T00:00:00Z`))
  && new Date(`${value}T00:00:00Z`).toISOString().slice(0, 10) === value;

// These are daily percentages, never absolute token totals or multi-day sums.
export function parseVercelUsage(payload, { now = Date.now() } = {}) {
  if (payload?.dataset !== 'models' || payload.modality !== 'text'
    || payload.license !== 'CC-BY-4.0' || payload.license_url !== licenseURL
    || !Array.isArray(payload.rows) || !payload.rows.length || payload.rows.length > 50000) throw new Error('Invalid Vercel export');
  const today = new Date(now).toISOString().slice(0, 10);
  const rows = payload.rows.filter(row => row.metric === 'tokens' && row.modality === 'text');
  if (rows.some(row => !validDay(row.date))) throw new Error('Invalid Vercel date');
  const day = rows.filter(row => row.date < today).map(row => row.date).sort().at(-1);
  if (!day) throw new Error('No completed Vercel day');
  const selected = rows.filter(row => row.date === day), seen = new Set();
  for (const row of selected) {
    if (row.group !== 'model' || typeof row.name !== 'string' || !row.name.trim() || row.name.length > 256
      || /[\x00-\x1f<>]/.test(row.name) || row.name !== row.name.trim() || seen.has(row.name)
      || typeof row.share_percent !== 'number' || !Number.isFinite(row.share_percent)
      || row.share_percent < 0 || row.share_percent > 100) throw new Error('Invalid Vercel row');
    seen.add(row.name);
  }
  // Published buckets include Other and round to four decimal places.
  if (Math.abs(selected.reduce((sum, row) => sum + row.share_percent, 0) - 100) > selected.length * 0.0001 + 0.001) throw new Error('Incomplete Vercel shares');
  const models = selected.filter(row => row.name !== 'Other' && row.share_percent > 0)
    .sort((a, b) => b.share_percent - a.share_percent || a.name.localeCompare(b.name, 'en'));
  if (!models.length || models.length > 500) throw new Error('Empty Vercel ranking');
  const attribution = `© ${day.slice(0, 4)} Vercel. "AI Gateway Leaderboard Data" is licensed under CC BY 4.0. To view a copy of this license, visit ${licenseURL}`;
  return { kind: vercelKind, title: 'Vercel AI Gateway', fetchedAt: new Date(now).toISOString(),
    sourceUpdatedAt: `${day}T00:00:00Z`, sourceDataset: { dataset: 'models', modality: 'text', license: payload.license, license_url: licenseURL, rows: selected },
    sourceNote: `${attribution}\nSource: ${vercelSource}\nUTC ${day} · text token volume share (input, output, reasoning and cached tokens).\nFiltered and rounded for display; Other is excluded. Company shares sum listed models only. No absolute volumes are published.`,
    otherSharePercent: selected.find(row => row.name === 'Other')?.share_percent ?? 0,
    entries: models.map((row, index) => ({ rank: index + 1, name: row.name, modelID: `vercel-name:${row.name}`, score: row.share_percent })) };
}

// Only a unique, exact official display-name → full provider/model ID pair.
// Do not strip dates, versions, or match substrings such as K3.
export function withVercelModels(board, payload) {
  if (!Array.isArray(payload?.data) || payload.data.length > 10000) throw new Error('Invalid Vercel models');
  const names = new Map();
  for (const row of payload.data) {
    if (typeof row.name !== 'string' || !/^[a-z0-9][a-z0-9._-]*\/[a-zA-Z0-9][a-zA-Z0-9._:+/-]{0,240}$/.test(row.id ?? '')
      || row.owned_by !== row.id.split('/')[0]) throw new Error('Invalid Vercel identity');
    const ids = names.get(row.name) ?? new Map(); ids.set(row.id, row); names.set(row.name, ids);
  }
  return { ...board, entries: board.entries.map(entry => {
    const ids = names.get(entry.name);
    if (ids?.size !== 1) return entry;
    const model = [...ids.values()][0];
    return { ...entry, modelID: model.id, organization: model.owned_by, vercelModelID: model.id };
  }) };
}
export async function loadVercelUsage({ now = Date.now(), fetcher = fetch, signal = AbortSignal.timeout(18000) } = {}) {
  const options = { signal, redirect: 'error', headers: { Accept: 'application/json' } };
  const board = parseVercelUsage(JSON.parse((await readBounded(await fetcher(vercelExportURL, options), 8 * 1024 * 1024)).toString('utf8')), { now });
  try { return withVercelModels(board, JSON.parse((await readBounded(await fetcher(vercelModelsURL, options), 8 * 1024 * 1024)).toString('utf8'))); }
  catch { return board; } // Optional metadata must not discard valid shares.
}
export async function loadConfiguredVercelUsage({ now = Date.now(), fetcher = fetch, environment = process.env } = {}) {
  if (!environment.ARENA_COLLECTOR_ENDPOINT) return loadVercelUsage({ now, fetcher });
  const endpoint = new URL(environment.ARENA_COLLECTOR_ENDPOINT);
  if (endpoint.protocol !== 'https:' || endpoint.username || endpoint.password || endpoint.pathname !== '/' || endpoint.search || endpoint.hash || endpoint.port
    || !endpoint.hostname.endsWith('.ap-southeast-1.fcapp.run') || !/^[A-Za-z0-9_-]{43}$/.test(environment.ARENA_COLLECTOR_TOKEN ?? '')) throw new Error('Invalid collector configuration');
  const response = await fetcher(new URL('/v1/vercel-usage', endpoint), { headers: { 'x-benchgauge-collector-key': environment.ARENA_COLLECTOR_TOKEN }, signal: AbortSignal.timeout(22000), redirect: 'error' });
  const collected = JSON.parse((await readBounded(response, 512000)).toString('utf8'));
  const fetched = Date.parse(collected.fetchedAt);
  if (collected.kind !== vercelKind || !Array.isArray(collected.entries) || !Number.isFinite(fetched) || fetched > now + 300000 || fetched < now - 3600000) throw new Error('Invalid collected Vercel data');
  const board = parseVercelUsage(collected.sourceDataset, { now });
  return withVercelModels(board, { data: collected.entries.filter(entry => entry.vercelModelID).map(entry => ({ name: entry.name, id: entry.vercelModelID, owned_by: entry.organization })) });
}
