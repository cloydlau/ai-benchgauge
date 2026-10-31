import test from 'node:test';
import { createServer } from 'node:http';
import { once } from 'node:events';
import { handler } from '../fc/server.mjs';
import { epochDomainPresets } from '../fc/epoch-domain-loader.mjs';
import { parseArenaRows } from '../fc/arena-dataset.mjs';
import assert from 'node:assert/strict';
import { SharedLeaderboards, grantLifetime, refreshInterval } from '../fc/service.mjs';
import { acquisitionPlan, parseAcquisition, acquisitionKey } from '../fc/client-acquisition.mjs';
class Store {
  boards = new Map(); states = new Map();
  async readBoard(k) { return this.boards.get(k) ?? null; }
  async writeBoard(k, b) { this.boards.set(k, b); }
  async readState(k) { return this.states.get(k) ?? { position: 0, state: null }; }
  async appendState(k, p, state) {
    if ((this.states.get(k)?.position ?? 0) !== p) return false;
    this.states.set(k, { position: p + 1, state }); return true;
  }
}
const kind = 'epochECI', now = Date.parse('2026-10-31T00:00:00Z');
const csv = 'Model,Display name,eci,Organization,Country (of organization),Accessibility group\n'
  + Array.from({ length: 22 }, (_, i) => `model-${i},Model ${i},${170-i},Maker,US,Closed weights`).join('\n');
const payload = { resources: [{ url: 'https://epoch.ai/data/eci_scores.csv', data: Buffer.from(csv).toString('base64') }] };
test('client raw bytes are parsed server-side, committed once and shared with legacy cooldown', async () => {
  const store = new Store(); let calls = 0;
  const service = new SharedLeaderboards(store, { clock: () => now, publicSource: async () => { calls++; throw Error('must not fetch'); } });
  const responses = await Promise.all(Array.from({ length: 30 }, () => service.refresh(kind, { clientFirst: true })));
  const grants = responses.filter(r => r.grant); assert.equal(grants.length, 1); assert.equal(calls, 0);
  const token = grants[0].grant.token;
  const accepted = await service.acquire(kind, token, payload);
  assert.equal(accepted.board.entries.length, 22); assert.equal(accepted.board.entries[0].score, 170);
  await assert.rejects(service.acquire(kind, token, payload), e => e.status === 403);
  await assert.rejects(service.fallback(kind, token), e => e.status === 403);
  assert.equal((await service.refresh(kind)).grant, undefined);
});
test('invalid upload permits one grant-bound fallback; concurrent fallback cannot duplicate origin calls', async () => {
  const store = new Store(); let calls = 0;
  const service = new SharedLeaderboards(store, { clock: () => now, publicSource: async (k, options) => {
    calls++; return parseAcquisition(k, payload, options.now);
  } });
  const { grant } = await service.refresh(kind, { clientFirst: true });
  await assert.rejects(service.acquire(kind, grant.token, { resources: [{ url: 'https://attacker.invalid', data: payload.resources[0].data }] }), e => e.status === 422);
  const results = await Promise.allSettled([service.fallback(kind, grant.token), service.fallback(kind, grant.token)]);
  assert.equal(results.filter(r => r.status === 'fulfilled').length, 1); assert.equal(calls, 1);
  assert.equal((await service.read(kind)).board.entries.length, 22);
});
test('backend failure preserves cache, consumes grant and does not reset cooldown', async () => {
  const store = new Store(), cached = await parseAcquisition(kind, payload, now - 1000); await store.writeBoard(kind, cached);
  let time = now, calls = 0;
  const service = new SharedLeaderboards(store, { clock: () => time, publicSource: async () => { calls++; throw Error('blocked'); } });
  const { grant, retryAt } = await service.refresh(kind, { clientFirst: true });
  assert.deepEqual((await service.fallback(kind, grant.token)).board, cached);
  assert.equal((await service.refresh(kind, { clientFirst: true })).retryAt, retryAt); assert.equal(calls, 1);
  time += grantLifetime + refreshInterval;
  const next = await service.refresh(kind, { clientFirst: true }); assert.ok(next.grant);
  time += grantLifetime;
  await assert.rejects(service.fallback(kind, next.grant.token), e => e.status === 403); assert.equal(calls, 1);
});
test('plans keep domain CSVs, licensed Arena revision and secret sources distinct', () => {
  assert.equal(acquisitionPlan('openRouterUsage'), null);
  assert.equal(acquisitionPlan('unknown'), null);
  assert.equal(acquisitionPlan('epochMathECI').resources.length, 3);
  assert.ok(acquisitionPlan('epochCyberECI').resources.every(r => r.url.includes('/cyber/')));
  assert.match(acquisitionPlan('arenaText').resources[1].url, /\{revision\}.*text_style_control/);
  assert.equal(acquisitionKey('arenaText'), 'arena-dataset/arenaText');
  assert.equal(acquisitionKey('epochMathECI'), 'epoch-domain/epochMathECI');
  assert.equal(acquisitionKey('epochSoftwareECI'), acquisitionKey('epochMathECI'));
  assert.equal(acquisitionKey('codeArenaImageToWebDev'), acquisitionKey('codeArenaWebDev'));
  assert.equal(acquisitionKey('arenaMultiImageEditing'), acquisitionKey('arenaImageEditing'));
});

test('domain contributions re-fit official raw CSVs rather than accepting general ECI scores', async () => {
  for (const k of ['epochMathECI', 'epochCyberECI']) {
    const names = k === 'epochCyberECI' ? ['a', 'b'] : epochDomainPresets[k];
    const scores = 'Model,Display name,eci,Organization,Country (of organization),Accessibility group\n'
      + Array.from({ length: 22 }, (_, i) => `m${i},Model ${i},${k === 'epochCyberECI' ? 140 : 175},Maker,US,Closed weights`).join('\n');
    const parameters = 'benchmark_name,edi,estimated_slope_scaled\n' + names.map((n, i) => `${n},${130+i*10},0.1`).join('\n');
    const results = `${k === 'epochCyberECI' ? 'model_group' : 'model'},benchmark,performance\n`
      + Array.from({ length: 22 }, (_, i) => names.map((n, j) => `m${i},${n},${1/(1+Math.exp(-0.1*(140-(130+j*10))))}`).join('\n')).join('\n');
    const p = { resources: acquisitionPlan(k).resources.map((r, i) => ({ url: r.url, data: Buffer.from([scores, results, parameters][i]).toString('base64') })) };
    const service = new SharedLeaderboards(new Store(), { clock: () => now });
    const { grant } = await service.refresh(k, { clientFirst: true });
    const { board } = await service.acquire(k, grant.token, p);
    assert.equal(board.entries.length, 22); assert.ok(Math.abs(board.entries[0].score - 140) < 1e-4);
  }
});
test('Arena client grant avoids backend access until fallback and preserves licensed dataset metadata', async () => {
  let calls = 0;
  const service = new SharedLeaderboards(new Store(), { clock: () => now, arenaDataset: async k => {
    calls++; return parseArenaRows(k, Array.from({ length: 22 }, (_, i) => ({ model_name: `M${i}`, organization: 'OpenAI', rating: 2000-i,
      rank: i+1, vote_count: 100, category: 'overall', leaderboard_publish_date: '2026-10-30' })), { now, revision: 'a'.repeat(40) });
  } });
  const { grant } = await service.refresh('arenaText', { clientFirst: true }); assert.equal(calls, 0);
  const { board } = await service.fallback('arenaText', grant.token); assert.equal(calls, 1);
  assert.match(board.sourceNote, /creativecommons.org/); assert.equal(board.sourceDatasetRevision, 'a'.repeat(40));
});
test('HTTP client-first refresh, raw JSON upload and token-bound fallback preserve legacy routes', async t => {
  const service = new SharedLeaderboards(new Store(), { clock: () => now, publicSource: (k, o) => parseAcquisition(k, payload, o.now) });
  const server = createServer(handler(() => service)); server.listen(0, '127.0.0.1'); await once(server, 'listening');
  t.after(() => { server.closeAllConnections(); server.close(); });
  const base = `http://127.0.0.1:${server.address().port}/v1/boards/${kind}`;
  const { grant } = await fetch(base + '/refresh', { method: 'POST', headers: { 'X-BenchGauge-Acquisition': 'client-first' } }).then(r => r.json());
  assert.ok(grant.acquisition);
  const headers = { 'Content-Type': 'application/json', 'X-BenchGauge-Grant': grant.token };
  assert.equal((await fetch(base + '/acquire', { method: 'POST', headers, body: 'invalid JSON' })).status, 422);
  const accepted = await fetch(base + '/acquire', { method: 'POST', headers, body: JSON.stringify(payload) });
  assert.equal(accepted.status, 200); assert.equal((await accepted.json()).board.entries.length, 22);
  assert.equal((await fetch(base + '/fallback', { method: 'POST', headers })).status, 403);
  assert.equal((await fetch(base + '/fallback')).status, 405);
});
test('public prices use client raw models without exposing OpenRouter usage credentials', async t => {
  const raw = { data: Array.from({ length: 22 }, (_, i) => ({ id: `maker/m${i}`, name: `Model ${i}`, architecture: { input_modalities: ['text'], output_modalities: ['text'] }, pricing: { prompt: '0.000001', completion: '0.000002' } })) };
  const p = { resources: [{ url: 'https://openrouter.ai/api/v1/models', data: Buffer.from(JSON.stringify(raw)).toString('base64') }] };
  const service = new SharedLeaderboards(new Store(), { clock: () => now });
  const server = createServer(handler(() => service)); server.listen(0, '127.0.0.1'); await once(server, 'listening');
  t.after(() => { server.closeAllConnections(); server.close(); });
  const base = `http://127.0.0.1:${server.address().port}/v1/boards/openRouterPrice`;
  const headers = { 'X-BenchGauge-Acquisition': 'client-first' };
  const { grant } = await fetch(base + '/refresh', { method: 'POST', headers }).then(r => r.json());
  assert.equal(grant.sourceURL, p.resources[0].url);
  const { board } = await service.acquire('openRouterPrice', grant.token, p);
  assert.equal(board.entries.length, 22); assert.equal(board.entries[0].score, 1); assert.equal(board.entries[0].outputPriceUSD, 2);
});

test('client-first cache reads never initiate backend acquisition, including usage and public prices', async t => {
  let calls = 0;
  const load = async () => { calls++; throw Error('must not acquire'); };
  const service = new SharedLeaderboards(new Store(), { clock: () => now, vercelUsage: load, cloudbaseUsage: load, openRouterUsage: load, openRouterConfigured: () => true });
  const server = createServer(handler(() => service)); server.listen(0, '127.0.0.1'); await once(server, 'listening');
  t.after(() => { server.closeAllConnections(); server.close(); });
  for (const k of ['openRouterPrice', 'vercelUsage', 'cloudbaseUsage', 'openRouterUsage']) {
    const response = await fetch(`http://127.0.0.1:${server.address().port}/v1/boards/${k}`, { headers: { 'X-BenchGauge-Acquisition': 'client-first' } });
    assert.equal(response.status, 200); assert.equal((await response.json()).board, null);
  }
  assert.equal(calls, 0);
});

test('daily public usage preserves ten-minute recovery after a lost client or failed backend', async () => {
  const store = new Store(); let time = now, calls = 0;
  const service = new SharedLeaderboards(store, { clock: () => time, vercelUsage: async () => { calls++; throw Error('offline'); } });
  const first = await service.refresh('vercelUsage', { clientFirst: true });
  assert.equal(first.retryAt, now + grantLifetime + 600000);
  assert.equal((await service.refresh('vercelUsage', { clientFirst: true })).grant, undefined);
  time = first.retryAt;
  const second = await service.refresh('vercelUsage', { clientFirst: true }); assert.ok(second.grant);
  await assert.rejects(service.fallback('vercelUsage', second.grant.token), e => e.status === 503);
  assert.equal(calls, 1);
  time += 600000;
  assert.ok((await service.refresh('vercelUsage', { clientFirst: true })).grant);
});

test('100 cold instances share one client lease per board, including legacy refresh competition', async () => {
  for (const k of ['artificialAnalysis', 'epochECI', 'arenaText', 'epochMathECI', 'openRouterPrice']) {
    const store = new Store(); let calls = 0
    const options = { clock: () => now, arenaDataset: async () => { calls++; throw Error('unexpected origin') },
      epochDomain: async () => { calls++; throw Error('unexpected origin') },
      priceLoader: async () => { calls++; throw Error('unexpected origin') } }
    const replies = await Promise.all(Array.from({ length: 100 }, () => new SharedLeaderboards(store, options).refresh(k, { clientFirst: true })))
    assert.equal(replies.filter(r => r.grant).length, 1, k)
    const position = (await store.readState(acquisitionKey(k))).position
    await Promise.all(Array.from({ length: 100 }, (_, i) => new SharedLeaderboards(store, options).refresh(k, { clientFirst: i % 2 === 0 })))
    assert.equal(calls, 0, k)
    assert.equal((await store.readState(acquisitionKey(k))).position, position, 'Denied requests must not extend the cooldown')
  }
})

test('concurrent upload and fallback across cold instances consume one lease and publish once', async () => {
  const store = new Store(); let calls = 0, writes = 0
  const write = store.writeBoard.bind(store); store.writeBoard = async (...args) => { writes++; return write(...args) }
  const options = { clock: () => now, publicSource: async (k, o) => { calls++; return parseAcquisition(k, payload, o.now) } }
  const { grant } = await new SharedLeaderboards(store, options).refresh(kind, { clientFirst: true })
  const results = await Promise.allSettled(Array.from({ length: 100 }, (_, i) => {
    const service = new SharedLeaderboards(store, options)
    return i % 2 ? service.acquire(kind, grant.token, payload) : service.fallback(kind, grant.token)
  }))
  assert.equal(results.filter(r => r.status === 'fulfilled').length, 1)
  assert.ok(results.filter(r => r.status === 'rejected').every(r => [403, 409].includes(r.reason.status)))
  assert.ok(calls <= 1); assert.equal(writes, 1)
})

test('slow storage cannot make a backend fallback start beyond the reserved lease window', async () => {
  const store = new Store(); let time = now, expireReads = false, calls = 0
  const read = store.readBoard.bind(store)
  store.readBoard = async k => { if (expireReads) time = now + grantLifetime; return read(k) }
  const service = new SharedLeaderboards(store, { clock: () => time, publicSource: async () => { calls++; throw Error('must not fetch') } })
  const { grant, retryAt } = await service.refresh(kind, { clientFirst: true }); expireReads = true
  await assert.rejects(service.fallback(kind, grant.token), e => e.status === 503)
  assert.equal(calls, 0)
  assert.equal((await service.refresh(kind, { clientFirst: true })).retryAt, retryAt)
})

test('legacy price HTTP routes and client-first share durable coordination across fresh handlers', async t => {
  const store = new Store(); let time = now, calls = 0
  const catalog = { source: 'OpenRouter', fetchedAt: new Date(now).toISOString(), rows: Array.from({ length: 22 }, (_, i) => ({
    id: `maker/m${i}`, name: `Model ${i}`, provider: 'OpenRouter', currency: 'USD', unit: 'per-million-tokens', input: i, output: i + 1 })) }
  const options = { clock: () => time, priceLoader: async () => { calls++; return catalog } }
  // Each request has a fresh handler and service, sharing only durable storage.
  const server = createServer((req, res) => handler(() => new SharedLeaderboards(store, options))(req, res))
  server.listen(0, '127.0.0.1'); await once(server, 'listening')
  t.after(() => { server.closeAllConnections(); server.close() })
  const base = `http://127.0.0.1:${server.address().port}`, path = '/v1/boards/openRouterPrice'
  const { grant, retryAt } = await fetch(base + path + '/refresh', { method: 'POST', headers: { 'X-BenchGauge-Acquisition': 'client-first' } }).then(r => r.json())
  const busy = await Promise.all(Array.from({ length: 30 }, () => fetch(base + '/v1/prices/openRouter')))
  assert.ok(busy.every(r => r.status === 503)); assert.equal(calls, 0)
  assert.equal((await fetch(base + path + '/fallback', { method: 'POST', headers: { 'X-BenchGauge-Grant': grant.token } })).status, 200)
  time = retryAt - 1
  const replies = await Promise.all(Array.from({ length: 30 }, (_, i) => fetch(base + (i % 2 ? '/v1/prices/openRouter' : path)).then(r => r.json())))
  assert.equal(calls, 1)
  assert.ok(replies.every(r => r.board?.entries.length === 22 || r.rows?.length === 22))
  assert.equal((await new SharedLeaderboards(store, options).refresh('openRouterPrice', { clientFirst: true })).grant, undefined)
  time = retryAt
  assert.ok((await new SharedLeaderboards(store, options).refresh('openRouterPrice', { clientFirst: true })).grant)
})

test('failed persistent coordination never authorizes origin access', async () => {
  for (const operation of ['readState', 'appendState']) {
    const store = new Store(); let calls = 0
    store[operation] = async () => { throw Error('OSS unavailable') }
    const service = new SharedLeaderboards(store, { clock: () => now, priceLoader: async () => { calls++; throw Error('must not fetch') } })
    await assert.rejects(service.refresh('openRouterPrice'), e => e.status === 503)
    assert.equal(calls, 0)
  }
})
