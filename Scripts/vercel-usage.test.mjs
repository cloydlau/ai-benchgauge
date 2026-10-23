import assert from 'node:assert/strict';
import test from 'node:test';
import { createServer } from 'node:http';
import { once } from 'node:events';
import { parseVercelUsage, withVercelModels, loadVercelUsage, loadConfiguredVercelUsage, vercelExportURL, vercelModelsURL, vercelInterval } from '../fc/vercel-usage.mjs';
import { modelMatcher } from '../fc/models-dev.mjs';
import { companyRows } from '../fc/domain.mjs';
import { collectorHandler } from '../fc/arena-collector.mjs';
import { SharedLeaderboards } from '../fc/service.mjs';
import { visibleRows, normalizeBoard } from '../apps/weapp/src/core/leaderboard.js';
import { vercelLicense } from '../apps/weapp/src/core/cc-by-4.0.js';
const now = Date.parse('2026-10-23T10:00:00Z');
const row = (name, share_percent, date = '2026-10-22', metric = 'tokens') => ({ name, share_percent, date, group: 'model', metric, modality: 'text' });
const fixture = () => ({ dataset: 'models', modality: 'text', license: 'CC-BY-4.0', license_url: 'https://creativecommons.org/licenses/by/4.0/', rows: [
  row('Kimi K3', 30), row('Kimi K3 1017', 20), row('Other', 50),
  row('Kimi K3', 70, '2026-10-21'), row('Other', 30, '2026-10-21'),
  row('Other', 100, '2026-10-23'), row('Wrong metric', 100, '2026-10-22', 'requests'),
] });
const catalog = { data: [{ name: 'Kimi K3', id: 'moonshotai/kimi-k3', owned_by: 'moonshotai' }, { name: 'Kimi K3 1017', id: 'moonshotai/kimi-k3-1017', owned_by: 'moonshotai' }] };
const board = () => withVercelModels(parseVercelUsage(fixture(), { now }), catalog);
test('single completed UTC day uses original platform shares, excluding Other without renormalizing or summing days', () => {
  const b = board();
  assert.equal(b.sourceUpdatedAt, '2026-10-22T00:00:00Z');
  assert.equal(b.entries.length, 2); assert.deepEqual(b.entries.map(e => e.score), [30, 20]);
  assert.equal(b.otherSharePercent, 50); assert.equal(b.entries[0].totalTokens, undefined);
  assert.match(b.sourceNote, /© 2026 Vercel/); assert.match(b.sourceNote, /CC BY 4.0/);
  const normalized = normalizeBoard(b, 'vercelUsage');
  const rows = visibleRows(normalized); assert.equal(rows[0].scoreText, '30.00%'); assert.equal(rows[1].scoreShare, '');
  const companies = companyRows(b.entries, { summingUsage: true });
  assert.equal(companies[0].score, 50); assert.equal(companies[0].totalTokens, undefined);
  const displayed = visibleRows(normalized, { grouping: 'company' }); assert.equal(displayed[0].scoreText, '50.00%');
  assert.equal(displayed[0].components[0].score, '30.00%');
  const tiny = normalizeBoard({ ...b, entries: [{ ...b.entries[0], score: 0.00001 }] }, 'vercelUsage');
  assert.equal(visibleRows(tiny)[0].scoreText, '<0.01%');
});
test('invalid license, incomplete/duplicate buckets, nonfinite shares and invalid dates cannot replace a snapshot', () => {
  for (const change of [p => p.license = 'unknown', p => p.license_url = 'https://evil.invalid', p => p.dataset = 'labs',
    p => p.rows[0].share_percent = '30', p => p.rows[0].share_percent = NaN, p => p.rows[0].share_percent = -1,
    p => p.rows[0].share_percent = 101, p => p.rows[0].share_percent = 25, p => p.rows[0].group = 'lab',
    p => p.rows.push(p.rows[0]), p => p.rows[0].date = '2026-02-30', p => p.rows = [row('Other', 100)],
    p => p.rows = [row('Other', 100, '2026-10-23')], p => p.rows[0].name = '<script>', p => p.rows = []]) {
    const data = fixture(); change(data); assert.throws(() => parseVercelUsage(data, { now }));
  }
  const lagged = fixture(); lagged.rows = lagged.rows.filter(r => r.date === '2026-10-21');
  assert.equal(parseVercelUsage(lagged, { now }).entries[0].score, 70, 'A lagged export retains its true source date');
});
test('identity requires exact unique official names and a full Vercel offer; K3 substrings/versions/providers never infer a match', () => {
  const b = parseVercelUsage(fixture(), { now });
  assert.equal(withVercelModels(b, { data: [catalog.data[0]] }).entries[1].vercelModelID, undefined);
  assert.equal(withVercelModels(b, { data: [...catalog.data, { name: 'Kimi K3', id: 'other/k3', owned_by: 'other' }] }).entries[0].vercelModelID, undefined);
  assert.throws(() => withVercelModels(b, { data: [{ name: 'Kimi K3', id: 'other/k3', owned_by: 'moonshotai' }] }));
  const model = { id: 'moonshotai/kimi-k3', name: 'Kimi K3', offers: [{ provider: 'vercel', modelID: 'moonshotai/kimi-k3', name: 'Kimi K3' }] };
  const match = modelMatcher({ models: [model] });
  assert.equal(match(board().entries[0], 'vercelUsage'), model);
  assert.equal(match(board().entries[1], 'vercelUsage'), null);
  assert.equal(match({ name: 'Kimi K3', modelID: 'moonshotai/kimi-k3' }, 'vercelUsage'), null);
  assert.equal(modelMatcher({ models: [{ ...model, offers: [{ ...model.offers[0], provider: 'other' }] }] })(board().entries[0], 'vercelUsage'), null);
});
test('public acquisition needs no credential or inference API; optional catalog failure preserves valid shares', async () => {
  const calls = [];
  const b = await loadVercelUsage({ now, fetcher: async (url, options) => {
    calls.push(url); assert.equal(options.redirect, 'error'); assert.equal(options.headers.Authorization, undefined);
    return new Response(JSON.stringify(url === vercelExportURL ? fixture() : catalog));
  } });
  assert.deepEqual(calls, [vercelExportURL, vercelModelsURL]); assert.equal(b.entries[0].vercelModelID, 'moonshotai/kimi-k3');
  const partial = await loadVercelUsage({ now, fetcher: async url => new Response(url === vercelExportURL ? JSON.stringify(fixture()) : 'bad') });
  assert.equal(partial.entries.length, 2); assert.equal(partial.entries[0].vercelModelID, undefined);
  for (const response of [new Response('{}', { status: 503 }), new Response('invalid')]) await assert.rejects(loadVercelUsage({ now, fetcher: async () => response }));
});
test('authenticated fixed collector route rejects arbitrary URLs and revalidates source buckets on return', async t => {
  const token = 'v'.repeat(43); let calls = 0;
  const server = createServer(collectorHandler({ token, vercel: async () => { calls++; return board(); }, clock: () => now }));
  server.listen(0, '127.0.0.1'); await once(server, 'listening'); t.after(() => { server.closeAllConnections(); server.close(); });
  const url = `http://127.0.0.1:${server.address().port}/v1/vercel-usage`, headers = { 'x-benchgauge-collector-key': token };
  assert.equal((await fetch(url)).status, 403);
  assert.equal((await fetch(url + '?url=https://evil.invalid', { headers })).status, 404);
  assert.equal((await fetch(url, { headers, method: 'POST' })).status, 404);
  await Promise.all([fetch(url, { headers }), fetch(url, { headers })]); assert.equal(calls, 1);
  const environment = { ARENA_COLLECTOR_ENDPOINT: 'https://fixture.ap-southeast-1.fcapp.run', ARENA_COLLECTOR_TOKEN: token };
  const collected = await loadConfiguredVercelUsage({ now, environment, fetcher: async (target, options) => {
    assert.equal(target.pathname, '/v1/vercel-usage'); assert.equal(options.headers.Authorization, undefined);
    assert.equal(options.headers['x-benchgauge-collector-key'], token); return new Response(JSON.stringify(board()));
  } });
  assert.equal(collected.entries[0].score, 30);
  for (const mutate of [b => b.sourceDataset.license = 'bad', b => b.sourceDataset.rows[0].share_percent = 1, b => b.fetchedAt = '2020-01-01']) {
    const b = board(); mutate(b); await assert.rejects(loadConfiguredVercelUsage({ now, environment, fetcher: async () => new Response(JSON.stringify(b)) }));
  }
});
class Store {
  boards = new Map(); states = new Map();
  async readBoard(kind) { return this.boards.get(kind) ?? null; }
  async writeBoard(kind, board) { this.boards.set(kind, board); }
  async readState(key) { return this.states.get(key) ?? { position: 0, state: null }; }
  async appendState(key, position, state) { if ((this.states.get(key)?.position ?? 0) !== position) return false; this.states.set(key, { position: position + 1, state }); return true; }
}
test('daily durable acquisition works without OpenRouter key, isolates sources, retains cache and retries a failed empty acquisition after ten minutes', async () => {
  let time = now, calls = 0, fail = false;
  const store = new Store(), service = new SharedLeaderboards(store, { clock: () => time, vercelUsage: async () => { calls++; if (fail) throw Error('upstream detail'); return board(); } });
  const results = await Promise.all([service.refresh('vercelUsage'), service.refresh('vercelUsage')]); assert.equal(calls, 1);
  assert.ok(results.some(r => r.board)); assert.ok(results.every(r => !r.grant && !r.configurationRequired));
  await assert.rejects(service.contribute('vercelUsage', 'x'.repeat(43), '<html/>'), { status: 403 });
  assert.equal((await service.read('openRouterUsage')).configurationRequired, true);
  await service.refresh('vercelUsage'); assert.equal(calls, 1);
  time += vercelInterval; fail = true;
  assert.equal((await service.refresh('vercelUsage')).board.entries[0].score, 30);
  store.boards.clear(); time += 600001;
  await assert.rejects(service.refresh('vercelUsage'), { status: 503, message: 'Vercel usage temporarily unavailable' });
  time += 600001; fail = false; assert.ok((await service.refresh('vercelUsage')).board);
});
test('about license provides offline fallback credit and cached source provenance in all languages', () => {
  for (const language of ['en', 'zh-CN', 'zh-TW']) {
    const fallback = vercelLicense(null, language); assert.match(fallback, /© 2026 Vercel/); assert.match(fallback, /creativecommons.org\/licenses\/by\/4.0/);
    assert.ok(vercelLicense('cached day and transformations', language).startsWith('cached day and transformations\n\n'));
    assert.ok(fallback.length > 1000);
  }
});

test('a first public GET initializes Vercel without an OpenRouter key and never offers an HTML grant', async t => {
  const { handler } = await import('../fc/server.mjs');
  let calls = 0;
  const service = new SharedLeaderboards(new Store(), { clock: () => now, vercelUsage: async () => { calls++; return board(); } });
  const server = createServer(handler(() => service)); server.listen(0, '127.0.0.1'); await once(server, 'listening');
  t.after(() => { server.closeAllConnections(); server.close(); });
  const url = `http://127.0.0.1:${server.address().port}/v1/boards/vercelUsage`;
  const first = await fetch(url); assert.equal(first.status, 200); const payload = await first.json();
  assert.equal(payload.board.entries[0].score, 30); assert.equal(payload.configurationRequired, undefined); assert.equal(payload.grant, undefined);
  const again = await (await fetch(url)).json(); assert.equal(again.board.fetchedAt, payload.board.fetchedAt); assert.equal(calls, 1);
});
