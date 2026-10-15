import { createServer } from 'node:http';
import { OSSStore } from './oss-store.mjs';
import { RequestError, SharedLeaderboards } from './service.mjs';
import { BrandRegistry } from './brands.mjs';
import { CountryRegistry } from './countries.mjs';

const maxHTMLBytes = 24 * 1024 * 1024;
export function handler(makeService) {
  return async (request, response) => {
    response.setHeader('Content-Type', 'application/json; charset=utf-8');
    response.setHeader('Cache-Control', 'no-store');
    response.setHeader('X-Content-Type-Options', 'nosniff');
    try {
      const path = new URL(request.url, 'http://localhost').pathname;
      const match = /^\/v1\/boards\/([A-Za-z]+)(?:\/(refresh|contribute))?$/.exec(path);
      if (!match) throw new RequestError(404, 'Unknown route');
      const [, kind, action] = match;
      if (action ? request.method !== 'POST' : request.method !== 'GET') throw new RequestError(405, 'Method not allowed');
      const service = await makeService(request);
      let result;
      if (!action) result = await service.read(kind);
      else if (action === 'refresh') result = await service.refresh(kind);
      else {
        if (!String(request.headers['content-type'] ?? '').startsWith('text/html')) throw new RequestError(415, 'Expected source HTML');
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

async function serviceFor(request) {
  const configuration = storageConfiguration(request.headers, process.env);
  const { default: OSS } = await import('ali-oss');
  const client = new OSS(configuration);
  const store = new OSSStore(client);
  return new SharedLeaderboards(store, { brands: new BrandRegistry(store), countries: new CountryRegistry(store) });
}

if (process.argv[1]?.endsWith('/server.mjs')) {
  const server = createServer(handler(serviceFor));
  server.requestTimeout = 30000;
  server.headersTimeout = 10000;
  server.listen(Number(process.env.FC_SERVER_PORT ?? 9000), '0.0.0.0');
}
