import { createServer } from 'node:http';
import { createHash, timingSafeEqual } from 'node:crypto';
import { isArena, isArenaDataset, arenaAcquisitionKinds, arenaCategory, arenaSubsets, loadArenaDataset, parseArenaRows, readBounded } from './arena-dataset.mjs';
import { loadModelsDev } from './models-dev.mjs';
import { loadVercelUsage } from './vercel-usage.mjs';
import { completedUsageDay, loadOpenRouterUsage } from './openrouter-usage.mjs';
import { loadOpenRouterPrices } from './price-catalog.mjs';
import { loadAAGeneralCosts } from './aa-general-cost.mjs';

export function collectorHandler({ token, load = loadArenaDataset, models = loadModelsDev, usage = loadOpenRouterUsage, vercel = loadVercelUsage, prices = loadOpenRouterPrices, aaCosts = loadAAGeneralCosts, clock = Date.now } = {}) {
  if (!/^[A-Za-z0-9_-]{43}$/.test(token ?? '')) throw new Error('Collector token required');
  const cache = new Map();
  return async (request, response) => {
    response.setHeader('Content-Type', 'application/json');
    response.setHeader('Cache-Control', 'no-store');
    const supplied = Buffer.from(String(request.headers['x-benchgauge-collector-key'] ?? ''));
    if (supplied.length !== token.length || !timingSafeEqual(supplied, Buffer.from(token))) {
      response.statusCode = 403; response.end('{}'); return;
    }
    const match = /^\/v1\/arena\/([A-Za-z]+)$/.exec(request.url);
    const metadata = request.url === '/v1/models-dev';
    const vercelUsage = request.url === '/v1/vercel-usage';
    const openRouter = request.url === '/v1/openrouter-usage';
    const openRouterPrices = request.url === '/v1/openrouter-prices';
    const aaGeneralCosts = request.url === '/v1/aa-general-costs';
    if (request.method !== 'GET' || !metadata && !openRouter && !openRouterPrices && !aaGeneralCosts && !vercelUsage && (!match || !isArena(match[1]))) {
      response.statusCode = 404; response.end('{}'); return;
    }
    const apiKey = openRouter ? /^Bearer ([\x21-\x7e]{1,1024})$/.exec(String(request.headers.authorization ?? ''))?.[1] : null;
    if (openRouter && !apiKey) { response.statusCode = 403; response.end('{}'); return; }
    const now = clock();
    // Credentials stay in request memory. A different key or UTC day must not
    // inherit another acquisition's cache (including its authentication).
    const kind = openRouter ? `openrouter-usage:${completedUsageDay(now)}:${createHash('sha256').update(apiKey).digest('hex')}`
      : aaGeneralCosts ? 'aa-general-costs' : openRouterPrices ? 'openrouter-prices' : vercelUsage ? 'vercel-usage' : metadata ? 'models-dev' : arenaSubsets[match[1]];
    try {
      let item = cache.get(kind);
      if (!item || now >= item.expires) {
        // Reuse an in-flight acquisition on this instance. The main service's
        // OSS coordination controls the global 30-minute refresh interval.
        const options = { now, signal: AbortSignal.timeout(18000), includeRelated: true };
        item = { expires: now + 600000, value: aaGeneralCosts ? aaCosts(options) : openRouterPrices ? prices(options) : openRouter ? usage({ ...options, apiKey })
          : vercelUsage ? vercel(options) : metadata ? models(options) : load(match[1], options) };
        cache.set(kind, item);
      }
      let value = await item.value;
      if (match) {
        const { relatedBoards = [], ...primary } = value;
        const boards = [primary, ...relatedBoards];
        const selected = boards.find(board => board.kind === match[1]);
        if (!selected) throw new Error('Category unavailable');
        value = { ...selected, relatedBoards: boards.filter(board => board.kind !== selected.kind) };
      }
      response.end(JSON.stringify(value));
    } catch {
      cache.delete(kind); response.statusCode = 503; response.end('{}');
    }
  };
}

export async function loadConfiguredArenaDataset(kind, { now = Date.now(), fetcher = fetch, environment = process.env, includeRelated = false } = {}) {
  if (!environment.ARENA_COLLECTOR_ENDPOINT) return loadArenaDataset(kind, { now, fetcher, includeRelated });
  const endpoint = new URL(environment.ARENA_COLLECTOR_ENDPOINT);
  if (!isArena(kind) || endpoint.protocol !== 'https:' || endpoint.username || endpoint.password
    || endpoint.pathname !== '/' || endpoint.search || endpoint.hash || endpoint.port
    || !endpoint.hostname.endsWith('.ap-southeast-1.fcapp.run')
    || !/^[A-Za-z0-9_-]{43}$/.test(environment.ARENA_COLLECTOR_TOKEN ?? '')) throw new Error('Invalid collector configuration');
  const response = await fetcher(new URL(`/v1/arena/${kind}`, endpoint), {
    headers: { 'x-benchgauge-collector-key': environment.ARENA_COLLECTOR_TOKEN },
    signal: AbortSignal.timeout(22000), redirect: 'error',
  });
  const bundle = JSON.parse((await readBounded(response, 4 * 1024 * 1024)).toString('utf8'));
  const { modelOpenness } = await import('./parser.mjs');
  const validate = (kind, board) => {
    const fetched = Date.parse(board.fetchedAt);
    if (!isArenaDataset(board) || board.kind !== kind || !board.sourceNote?.includes(`${arenaSubsets[kind]}/latest/${arenaCategory(kind)}`) || !Array.isArray(board.entries)
      || !Number.isFinite(fetched) || fetched > now + 300000 || fetched < now - 3600000) throw new Error('Invalid collected dataset');
    return parseArenaRows(kind, board.entries.map(entry => ({ model_name: entry.name, organization: entry.organization,
      license: entry.modelLicense, rating: entry.score, rank: entry.rank, vote_count: entry.voteCount,
      category: arenaCategory(kind), leaderboard_publish_date: board.sourceUpdatedAt?.slice(0, 10) })),
    { now: fetched, revision: board.sourceDatasetRevision, classifyLicense: modelOpenness });
  };
  const board = validate(kind, bundle);
  if (!includeRelated) return board;
  const allowed = new Set(arenaAcquisitionKinds(kind).filter(candidate => candidate !== kind)), relatedBoards = [];
  for (const related of bundle.relatedBoards ?? []) {
    if (!allowed.delete(related?.kind) || related.sourceDatasetRevision !== board.sourceDatasetRevision) continue;
    try { relatedBoards.push(validate(related.kind, related)); } catch { /* Retain the last complete category. */ }
  }
  return { ...board, relatedBoards };
}

if (process.argv[1]?.endsWith('/arena-collector.mjs')) {
  createServer(collectorHandler({ token: process.env.ARENA_COLLECTOR_TOKEN }))
    .listen(Number(process.env.FC_SERVER_PORT ?? 9000), '0.0.0.0');
}
