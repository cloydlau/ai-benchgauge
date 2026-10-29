import { createServer } from 'node:http';
import { timingSafeEqual } from 'node:crypto';
import { OSSStore } from './oss-store.mjs';
import { RequestError, SharedLeaderboards } from './service.mjs';
import { BrandRegistry } from './brands.mjs';
import { CountryRegistry } from './countries.mjs';
import { loadConfiguredArenaDataset } from './arena-collector.mjs';
import { loadConfiguredVercelUsage } from './vercel-usage.mjs';
import { loadCloudBaseUsage } from './cloudbase-usage.mjs';
import { loadConfiguredOpenRouterUsage, openRouterConfigured } from './openrouter-usage.mjs';
import { ModelsDevRegistry, loadConfiguredModelsDev, modelsDevInterval } from './models-dev.mjs';
import { loadConfiguredOpenRouterPrices, priceBoard } from './price-catalog.mjs';
import { loadConfiguredAAGeneralCosts } from './aa-general-cost.mjs';

const maxHTMLBytes = 24 * 1024 * 1024;
export function handler(makeService, { syncToken = process.env.MODELS_DEV_SYNC_TOKEN, priceLoader = loadConfiguredOpenRouterPrices } = {}) {
  let openRouterPrices, priceExpires = 0;
  return async (request, response) => {
    response.setHeader('Content-Type', 'application/json; charset=utf-8');
    response.setHeader('Cache-Control', 'no-store');
    response.setHeader('X-Content-Type-Options', 'nosniff');
    try {
      const path = new URL(request.url, 'http://localhost').pathname;
      if (['/v1/prices/openRouter', '/v1/boards/openRouterPrice', '/v1/boards/openRouterPrice/refresh'].includes(path)) {
        const refreshing = path.endsWith('/refresh');
        if (request.method !== (refreshing ? 'POST' : 'GET')) throw new RequestError(405, 'Method not allowed');
        let catalog;
        if (!openRouterPrices || Date.now() >= priceExpires) {
          openRouterPrices = Promise.resolve().then(() => priceLoader()); priceExpires = Date.now() + 600000;
        }
        try { catalog = await openRouterPrices; }
        catch { openRouterPrices = undefined; priceExpires = 0; throw new RequestError(503, 'Price catalog unavailable'); }
        response.end(JSON.stringify(path.startsWith('/v1/boards/') ? { board: priceBoard('openRouterPrice', catalog) } : catalog));
        return;
      }
      if (path === '/invoke') {
        if (request.method !== 'POST') throw new RequestError(405, 'Method not allowed');
        let size = 0; const chunks = [];
        for await (const chunk of request) { size += chunk.length; if (size > 4096) throw new RequestError(413, 'Event too large'); chunks.push(chunk); }
        let payload;
        try { const event = JSON.parse(Buffer.concat(chunks).toString('utf8')); payload = event.payload ? JSON.parse(event.payload) : event; } catch { throw new RequestError(403, 'Invalid sync request'); }
        const supplied = Buffer.from(String(payload?.token ?? ''));
        if (!/^[A-Za-z0-9_-]{43}$/.test(syncToken ?? '') || !['models-dev-sync', 'models-dev-fill'].includes(payload?.type)
          || supplied.length !== syncToken.length || !timingSafeEqual(supplied, Buffer.from(syncToken))) throw new RequestError(403, 'Invalid sync request');
        const models = (await makeService(request)).models, pendingOnly = payload.type === 'models-dev-fill';
        const snapshot = await models?.sync({ pendingOnly });
        if (!models || models.syncFailed || !pendingOnly && (!snapshot || Date.now() - (models.checkedAt ?? Date.parse(snapshot.fetchedAt)) >= modelsDevInterval)) throw new RequestError(503, 'Metadata sync unavailable');
        response.end(JSON.stringify({ source: 'models.dev', models: snapshot?.models.length ?? 0, revision: snapshot?.revision,
          fetchedAt: snapshot?.fetchedAt, checkedAt: Number.isFinite(models.checkedAt) ? new Date(models.checkedAt).toISOString() : snapshot?.fetchedAt })); return;
      }
      const match = /^\/v1\/boards\/([A-Za-z]+)(?:\/(refresh|contribute))?$/.exec(path);
      if (!match) throw new RequestError(404, 'Unknown route');
      const [, kind, action] = match;
      if (action ? request.method !== 'POST' : request.method !== 'GET') throw new RequestError(405, 'Method not allowed');
      const service = await makeService(request);
      let result;
      if (!action) result = ['openRouterUsage', 'vercelUsage', 'cloudbaseUsage'].includes(kind) ? await service.refresh(kind) : await service.read(kind);
      else if (action === 'refresh') result = await service.refresh(kind);
      else {
        const contentType = kind === 'epochECI' ? 'text/csv' : 'text/html';
        if (!String(request.headers['content-type'] ?? '').startsWith(contentType)) throw new RequestError(415, 'Expected official source data');
        if (Number(request.headers['content-length']) > maxHTMLBytes) throw new RequestError(413, 'Source HTML too large');
        let size = 0; const chunks = [];
        for await (const chunk of request) {
          size += chunk.length;
          if (size > maxHTMLBytes) throw new RequestError(413, 'Source HTML too large');
          chunks.push(chunk);
        }
        result = await service.contribute(kind, request.headers['x-benchgauge-grant'], Buffer.concat(chunks).toString('utf8'));
      }
      response.end(JSON.stringify(result));
    } catch (error) {
      // Never expose SDK errors, role credentials, object names, or raw HTML.
      response.statusCode = error instanceof RequestError ? error.status : 503;
      response.end(JSON.stringify({ error: error instanceof RequestError ? error.message : 'Shared service unavailable' }));
    }
  };
}

export function storageConfiguration(headers, environment) {
  const fromEnvironment = environment.STORAGE_CREDENTIAL_SOURCE === 'environment';
  const accessKeyId = fromEnvironment ? environment.ALIBABA_CLOUD_ACCESS_KEY_ID : headers['x-fc-access-key-id'];
  const accessKeySecret = fromEnvironment ? environment.ALIBABA_CLOUD_ACCESS_KEY_SECRET : headers['x-fc-access-key-secret'];
  const stsToken = fromEnvironment ? environment.ALIBABA_CLOUD_SECURITY_TOKEN : headers['x-fc-security-token'];
  if (!accessKeyId || !accessKeySecret || (!fromEnvironment && !stsToken) || !environment.OSS_BUCKET || !environment.OSS_REGION) {
    throw new RequestError(503, 'Shared storage not configured');
  }
  return { accessKeyId, accessKeySecret, ...(stsToken && { stsToken }), bucket: environment.OSS_BUCKET,
    region: environment.OSS_REGION, secure: true, internal: true, timeout: 8000 };
}

const modelsCache = {};
async function serviceFor(request) {
  const configuration = storageConfiguration(request.headers, process.env);
  const { default: OSS } = await import('ali-oss');
  const client = new OSS(configuration);
  const store = new OSSStore(client);
  return new SharedLeaderboards(store, { brands: new BrandRegistry(store), countries: new CountryRegistry(store), arenaDataset: loadConfiguredArenaDataset,
    generalCosts: loadConfiguredAAGeneralCosts,
    cloudbaseUsage: loadCloudBaseUsage, vercelUsage: loadConfiguredVercelUsage, openRouterUsage: loadConfiguredOpenRouterUsage, openRouterConfigured,
    models: new ModelsDevRegistry(store, { load: loadConfiguredModelsDev, cache: modelsCache }) });
}

if (process.argv[1]?.endsWith('/server.mjs')) {
  const server = createServer(handler(serviceFor));
  server.requestTimeout = 30000;
  server.headersTimeout = 10000;
  server.listen(Number(process.env.FC_SERVER_PORT ?? 9000), '0.0.0.0');
}
