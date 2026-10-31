import { loadOpenRouterPrices, priceBoard } from './price-catalog.mjs';
import { sources, parseBoard } from './parser.mjs';
import { isArena, arenaAcquisitionKinds, arenaDataURL, loadArenaDataset, readBounded } from './arena-dataset.mjs';
import { isEpochDomain, epochAcquisitionKinds, loadEpochDomain } from './epoch-domain-loader.mjs';
import { vercelExportURL, vercelModelsURL, loadVercelUsage } from './vercel-usage.mjs';
import { cloudbaseSource, loadCloudBaseUsage } from './cloudbase-usage.mjs';

const arenaMetadata = 'https://huggingface.co/api/datasets/lmarena-ai/leaderboard-dataset';
const resource = (url, maxBytes, accept, extra = {}) => ({ url, maxBytes, accept, ...extra });
// The service chooses fixed public resources; clients never select backend URLs.
export function acquisitionPlan(kind) {
  if (kind === 'artificialAnalysis') return { resources: [resource('https://artificialanalysis.ai/models/', 16 * 1024 * 1024, 'text/html')] };
  if (kind === 'openRouterPrice') return { resources: [resource('https://openrouter.ai/api/v1/models', 8 * 1024 * 1024, 'application/json')] };
  if (kind === 'openRouterUsage' || !Object.hasOwn(sources, kind)) return null;
  if (isArena(kind)) return { resources: [resource(arenaMetadata, 250000, 'application/json'),
    resource(arenaDataURL(kind).replace('/main/', '/{revision}/'), 4 * 1024 * 1024, 'application/octet-stream', { revisionFrom: 0 })] };
  if (isEpochDomain(kind)) return { resources: ['eci_scores.csv', 'processed_data_for_eci.csv', 'edi_scores.csv']
    .map(name => resource(`https://epoch.ai/data/${kind === 'epochCyberECI' ? 'cyber/' : ''}${name}`, 8000000, 'text/csv')) };
  if (kind === 'vercelUsage') return { resources: [resource(vercelExportURL, 8 * 1024 * 1024, 'application/json'),
    resource(vercelModelsURL, 8 * 1024 * 1024, 'application/json', { optional: true })] };
  if (kind === 'cloudbaseUsage') return { resources: [resource(cloudbaseSource, 2 * 1024 * 1024, 'text/html')] };
  return { resources: [resource(sources[kind][0], 16 * 1024 * 1024, kind === 'epochECI' ? 'text/csv' : 'text/html')] };
}
export function legacyAcquisitionKey(kind) {
  if (isArena(kind)) return `arena-dataset/${kind}`;
  if (isEpochDomain(kind)) return `epoch-domain/${kind}`;
  if (kind === 'vercelUsage') return 'vercel-export/usage';
  if (kind === 'cloudbaseUsage') return 'cloudbase-document/usage';
  return kind;
}
export function acquisitionKinds(kind) {
  return isArena(kind) ? arenaAcquisitionKinds(kind) : isEpochDomain(kind) ? epochAcquisitionKinds(kind) : [kind];
}
// A domain bundle also contains the complete general score CSV, at no extra request cost.
export const acquisitionOutputs = kind => isEpochDomain(kind) && kind !== 'epochCyberECI'
  ? [...acquisitionKinds(kind), 'epochECI'] : acquisitionKinds(kind);
export const acquisitionKey = kind => legacyAcquisitionKey(acquisitionKinds(kind)[0]);
export function resourceURL(spec, parts) {
  if (spec.revisionFrom == null) return spec.url;
  const revision = JSON.parse(parts[spec.revisionFrom].toString('utf8')).sha;
  if (!/^[a-f0-9]{40}$/.test(revision ?? '')) throw new Error('Invalid dataset revision');
  return spec.url.replace('{revision}', revision);
}
// Replay raw bytes through the same official loaders as backend acquisition.
// Domain fitting, dataset attribution and completeness checks stay on the server.
export async function parseAcquisition(kind, payload, now) {
  const plan = acquisitionPlan(kind), parts = [], responses = new Map();
  if (!plan || !Array.isArray(payload?.resources) || payload.resources.length !== plan.resources.length) throw new Error('Invalid source bundle');
  for (let i = 0; i < plan.resources.length; i++) {
    const spec = plan.resources[i], entry = payload.resources[i];
    if (entry == null && spec.optional) { parts.push(null); continue; }
    if (typeof entry?.data !== 'string' || entry.data.length > Math.ceil(spec.maxBytes / 3) * 4) throw new Error('Invalid source bytes');
    const bytes = Buffer.from(entry.data, 'base64');
    if (bytes.length > spec.maxBytes || bytes.toString('base64') !== entry.data || entry.url !== resourceURL(spec, parts)) throw new Error('Invalid source resource');
    parts.push(bytes); responses.set(entry.url, bytes);
  }
  const fetcher = async url => {
    if (!responses.has(String(url))) throw new Error('Missing source resource');
    return new Response(responses.get(String(url)));
  };
  if (kind === 'openRouterPrice') return priceBoard(kind, await loadOpenRouterPrices({ now, fetcher }));
  if (isArena(kind)) return loadArenaDataset(kind, { now, fetcher, includeRelated: true });
  if (isEpochDomain(kind)) return loadEpochDomain(kind, { now, fetcher, includeRelated: true });
  if (kind === 'vercelUsage') return loadVercelUsage({ now, fetcher });
  if (kind === 'cloudbaseUsage') return loadCloudBaseUsage({ now, fetcher });
  return parseBoard(kind, parts[0].toString('utf8'), now);
}
export async function loadPublicSource(kind, { now, fetcher = fetch }) {
  const spec = acquisitionPlan(kind).resources[0];
  const response = await fetcher(spec.url, { signal: AbortSignal.timeout(15000), redirect: 'error',
    headers: { Accept: spec.accept, 'User-Agent': 'Mozilla/5.0' } });
  return parseBoard(kind, (await readBounded(response, spec.maxBytes)).toString('utf8'), now);
}
