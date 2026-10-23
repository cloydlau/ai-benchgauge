import { createServer } from 'node:http';
import { createHash, timingSafeEqual } from 'node:crypto';
import { isArena, isArenaDataset, loadArenaDataset, parseArenaRows, readBounded } from './arena-dataset.mjs';
import { loadModelsDev } from './models-dev.mjs';
import { completedUsageDay, loadOpenRouterUsage } from './openrouter-usage.mjs';

export function collectorHandler({ token, load = loadArenaDataset, models = loadModelsDev, usage = loadOpenRouterUsage, clock = Date.now } = {}) {
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
    const openRouter = request.url === '/v1/openrouter-usage';
    if (request.method !== 'GET' || !metadata && !openRouter && (!match || !isArena(match[1]))) {
      response.statusCode = 404; response.end('{}'); return;
    }
    const apiKey = openRouter ? /^Bearer ([\x21-\x7e]{1,1024})$/.exec(String(request.headers.authorization ?? ''))?.[1] : null;
    if (openRouter && !apiKey) { response.statusCode = 403; response.end('{}'); return; }
    const now = clock();
    // Credentials stay in request memory. A different key or UTC day must not
    // inherit another acquisition's cache (including its authentication).
    const kind = openRouter ? `openrouter-usage:${completedUsageDay(now)}:${createHash('sha256').update(apiKey).digest('hex')}`
      : metadata ? 'models-dev' : match[1];
    try {
      let item = cache.get(kind);
      if (!item || now >= item.expires) {
        // Reuse an in-flight acquisition on this instance. The main service's
        // OSS coordination controls the global 30-minute refresh interval.
        const options = { now, signal: AbortSignal.timeout(18000) };
        item = { expires: now + 600000, value: openRouter ? usage({ ...options, apiKey })
          : metadata ? models(options) : load(kind, options) };
        cache.set(kind, item);
      }
      response.end(JSON.stringify(await item.value));
    } catch {
      cache.delete(kind); response.statusCode = 503; response.end('{}');
    }
  };
}

export async function loadConfiguredArenaDataset(kind, { now = Date.now(), fetcher = fetch, environment = process.env } = {}) {
  if (!environment.ARENA_COLLECTOR_ENDPOINT) return loadArenaDataset(kind, { now, fetcher });
  const endpoint = new URL(environment.ARENA_COLLECTOR_ENDPOINT);
  if (!isArena(kind) || endpoint.protocol !== 'https:' || endpoint.username || endpoint.password
    || endpoint.pathname !== '/' || endpoint.search || endpoint.hash || endpoint.port
    || !endpoint.hostname.endsWith('.ap-southeast-1.fcapp.run')
    || !/^[A-Za-z0-9_-]{43}$/.test(environment.ARENA_COLLECTOR_TOKEN ?? '')) throw new Error('Invalid collector configuration');
  const response = await fetcher(new URL(`/v1/arena/${kind}`, endpoint), {
    headers: { 'x-benchgauge-collector-key': environment.ARENA_COLLECTOR_TOKEN },
    signal: AbortSignal.timeout(22000), redirect: 'error',
  });
  const board = JSON.parse((await readBounded(response, 4 * 1024 * 1024)).toString('utf8'));
  const fetched = Date.parse(board.fetchedAt);
  if (!isArenaDataset(board) || board.kind !== kind || !Array.isArray(board.entries)
    || !Number.isFinite(fetched) || fetched > now + 300000 || fetched < now - 3600000) throw new Error('Invalid collected dataset');
  const { modelOpenness } = await import('./parser.mjs');
  return parseArenaRows(kind, board.entries.map(entry => ({ model_name: entry.name, organization: entry.organization,
    license: entry.modelLicense, rating: entry.score, rank: entry.rank, vote_count: entry.voteCount,
    category: 'overall', leaderboard_publish_date: board.sourceUpdatedAt?.slice(0, 10) })),
  { now: fetched, revision: board.sourceDatasetRevision, classifyLicense: modelOpenness });
}

if (process.argv[1]?.endsWith('/arena-collector.mjs')) {
  createServer(collectorHandler({ token: process.env.ARENA_COLLECTOR_TOKEN }))
    .listen(Number(process.env.FC_SERVER_PORT ?? 9000), '0.0.0.0');
}
