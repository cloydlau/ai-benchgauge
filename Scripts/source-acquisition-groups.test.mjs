import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { createServer } from 'node:http';
import { once } from 'node:events';
import { SharedLeaderboards, refreshInterval, grantLifetime } from '../fc/service.mjs';
import { acquisitionKinds, acquisitionKey, acquisitionPlan, legacyAcquisitionKey, parseAcquisition, loadPublicSource } from '../fc/client-acquisition.mjs';
import { arenaCategory, parseArenaAcquisitionRows } from '../fc/arena-dataset.mjs';
import { collectorHandler, loadConfiguredArenaDataset } from '../fc/arena-collector.mjs';
import { epochDomainPresets, loadEpochDomain } from '../fc/epoch-domain-loader.mjs';

const now = Date.parse('2026-10-31T12:00:00Z'), revision = 'a'.repeat(40);
class Store {
  boards = new Map(); states = new Map();
  async readBoard(k) { return this.boards.get(k) ?? null; }
  async writeBoard(k, board) { this.boards.set(k, board); }
  async readState(k) { return this.states.get(k) ?? { position: 0, state: null }; }
  async appendState(k, position, state) {
    if ((this.states.get(k)?.position ?? 0) !== position) return false;
    this.states.set(k, { position: position + 1, state }); return true;
  }
}
const groups = [['codeArenaWebDev', 'codeArenaImageToWebDev'], ['arenaImageEditing', 'arenaMultiImageEditing'], ['epochMathECI', 'epochSoftwareECI']];
function arenaRows(kinds) {
  return kinds.flatMap((kind, categoryIndex) => Array.from({ length: 22 }, (_, i) => ({
    model_name: `${kind}-${i}`, organization: 'OpenAI', rating: 2000 - categoryIndex * 100 - i,
    rank: i + 1, vote_count: 100 + i, category: arenaCategory(kind),
    leaderboard_publish_date: categoryIndex ? '2026-10-29' : '2026-10-30',
  })));
}
function arenaBundle(kind, rows = arenaRows(acquisitionKinds(kind))) {
  return parseArenaAcquisitionRows(kind, rows, { now, revision });
}
function epochFiles({ software = true } = {}) {
  const names = [...new Set([...epochDomainPresets.epochMathECI, ...(software ? epochDomainPresets.epochSoftwareECI : [])])];
  const scores = 'Model,Display name,eci,Organization,Country (of organization),Accessibility group\n'
    + Array.from({ length: 22 }, (_, i) => `m${i},Model ${i},175,Maker,US,Closed weights`).join('\n');
  const parameters = 'benchmark_name,edi,estimated_slope_scaled\n' + names.map(n => `${n},130,0.1`).join('\n');
  const results = 'model,benchmark,performance\n' + Array.from({ length: 22 }, (_, i) => names.map(n => {
    const score = epochDomainPresets.epochMathECI.includes(n) ? 140 + i : 180 - i;
    return `m${i},${n},${1 / (1 + Math.exp(-0.1 * (score - 130)))}`;
  }).join('\n')).join('\n');
  return [scores, results, parameters];
}
const epochPayload = files => ({ resources: acquisitionPlan('epochMathECI').resources.map((r, i) => ({ url: r.url, data: Buffer.from(files[i]).toString('base64') })) });

test('acquisition groups follow identical complete resources, not provider names or navigation', () => {
  for (const kinds of groups) {
    assert.deepEqual(acquisitionKinds(kinds[1]), kinds);
    assert.equal(acquisitionKey(kinds[0]), acquisitionKey(kinds[1]));
    assert.deepEqual(acquisitionPlan(kinds[0]), acquisitionPlan(kinds[1]));
  }
  for (const [a, b] of [['arenaText', 'arenaTextUncontrolled'], ['epochCyberECI', 'epochMathECI'],
    ['artificialAnalysis', 'artificialAnalysisTextToImage'], ['artificialAnalysisTextToImage', 'artificialAnalysisImageEditing'],
    ['artificialAnalysisTextToVideo', 'artificialAnalysisImageToVideo']]) assert.notEqual(acquisitionKey(a), acquisitionKey(b));
});

test('100 cold instances refreshing different subboards receive one source-group lease, also shared by legacy entries', async () => {
  for (const kinds of groups) {
    const store = new Store(); let calls = 0;
    const options = { clock: () => now, arenaDataset: async () => { calls++; throw Error('unexpected'); }, epochDomain: async () => { calls++; throw Error('unexpected'); } };
    const replies = await Promise.all(Array.from({ length: 100 }, (_, i) => new SharedLeaderboards(store, options).refresh(kinds[i % 2], { clientFirst: true })));
    assert.equal(replies.filter(r => r.grant).length, 1);
    const position = (await store.readState(acquisitionKey(kinds[0]))).position;
    await Promise.all(kinds.map(k => new SharedLeaderboards(store, options).refresh(k)));
    assert.equal(calls, 0);
    assert.equal((await store.readState(acquisitionKey(kinds[0]))).position, position);
    const winner = replies.find(r => r.grant);
    await assert.rejects(new SharedLeaderboards(store, options).fallback(kinds[1], winner.grant.token), e => e.status === 403);
  }
});

test('pre-grouping sibling cooldowns and unexpired route-bound leases survive migration', async () => {
  for (const kinds of groups) {
    const store = new Store(); let time = now, calls = 0;
    const token = 'T'.repeat(43), nextAttemptAt = now + grantLifetime + refreshInterval;
    await store.appendState(legacyAcquisitionKey(kinds[1]), 0, { hash: createHash('sha256').update(token).digest('hex'),
      issuedAt: now, expiresAt: now + grantLifetime, nextAttemptAt, consumed: false, clientFirst: true });
    const options = { clock: () => time, arenaDataset: async () => { calls++; throw Error('unexpected'); }, epochDomain: async () => { calls++; throw Error('unexpected'); } };
    const service = new SharedLeaderboards(store, options);
    for (const k of kinds) {
      assert.equal((await service.refresh(k, { clientFirst: true })).retryAt, nextAttemptAt);
      assert.equal((await service.refresh(k)).retryAt, nextAttemptAt);
    }
    assert.equal(calls, 0);
    assert.equal((await service.acquisitionGrant(kinds[1], token)).key, legacyAcquisitionKey(kinds[1]));
    await assert.rejects(service.acquisitionGrant(kinds[0], token), e => e.status === 403);
    time = nextAttemptAt;
    assert.ok((await service.refresh(kinds[1], { clientFirst: true })).grant);
  }
});

test('one Arena file updates both categories with separate ranks, scores and publication dates, in either direction', async () => {
  for (const kinds of groups.slice(0, 2)) for (const requested of kinds) {
    const store = new Store(); let calls = 0;
    const service = new SharedLeaderboards(store, { clock: () => now, arenaDataset: async (k, o) => {
      assert.equal(o.includeRelated, true); calls++; return arenaBundle(k);
    } });
    const { grant } = await service.refresh(requested, { clientFirst: true });
    const result = await service.fallback(requested, grant.token);
    assert.equal(result.board.kind, requested); assert.equal(result.board.relatedBoards, undefined);
    for (const [i, k] of kinds.entries()) {
      const board = (await service.read(k)).board;
      assert.equal(board.entries[0].name, `${k}-0`); assert.equal(board.entries[0].score, 2000 - i * 100);
      assert.equal(board.sourceUpdatedAt, i ? '2026-10-29T00:00:00.000Z' : '2026-10-30T00:00:00.000Z');
      assert.equal(board.sourceDatasetRevision, revision); assert.equal(board.relatedBoards, undefined);
      assert.equal((await service.refresh(k)).grant, undefined);
    }
    assert.equal(calls, 1);
  }
});

test('three Epoch CSV downloads fit and publish both domains; raw upload and fallback race publishes once', async () => {
  const files = epochFiles(), seen = [];
  const fetcher = async url => { seen.push(url); const i = ['eci_scores.csv', 'processed_data_for_eci.csv', 'edi_scores.csv'].indexOf(url.split('/').at(-1)); return new Response(files[i]); };
  const bundle = await loadEpochDomain('epochMathECI', { now, fetcher, includeRelated: true });
  assert.equal(seen.length, 3); assert.equal(new Set(seen).size, 3);
  assert.equal(bundle.relatedBoards[0].kind, 'epochSoftwareECI');
  assert.equal(bundle.entries[0].modelID, 'm21'); assert.equal(bundle.relatedBoards[0].entries[0].modelID, 'm0');
  const raw = await parseAcquisition('epochSoftwareECI', epochPayload(files), now);
  assert.equal(raw.relatedBoards[0].kind, 'epochMathECI');
  assert.equal(raw.relatedBoards[1].kind, 'epochECI');
  assert.equal(raw.relatedBoards[1].entries[0].score, 175);
  for (const fallbackWins of [false, true]) {
    const store = new Store(); let calls = 0;
    const options = { clock: () => now, epochDomain: async (k, o) => { calls++; return loadEpochDomain(k, { ...o, fetcher }); } };
    const service = new SharedLeaderboards(store, options);
    const { grant } = await service.refresh('epochMathECI', { clientFirst: true });
    const upload = () => service.acquire('epochMathECI', grant.token, epochPayload(files));
    const fallback = () => service.fallback('epochMathECI', grant.token);
    const first = await Promise.allSettled(fallbackWins ? [fallback(), upload()] : [upload(), fallback()]);
    assert.equal(first.filter(r => r.status === 'fulfilled').length, 1);
    const repeated = await Promise.allSettled(Array.from({ length: 30 }, (_, i) => i % 2
      ? new SharedLeaderboards(store, options).fallback('epochMathECI', grant.token)
      : new SharedLeaderboards(store, options).acquire('epochMathECI', grant.token, epochPayload(files))));
    assert.ok(repeated.every(r => r.status === 'rejected'));
    assert.ok(calls <= 1); assert.equal(store.boards.size, 3);
    assert.equal((await service.refresh('epochECI', { clientFirst: true })).grant, undefined);
    assert.equal((await service.refresh('epochECI')).grant, undefined);
    assert.equal((await service.read('epochMathECI')).board.entries[0].modelID, 'm21');
    assert.equal((await service.read('epochSoftwareECI')).board.entries[0].modelID, 'm0');
  }
});

test('legacy backend refresh also publishes related boards without another origin acquisition', async () => {
  for (const kinds of groups) {
    const store = new Store(); let calls = 0;
    const options = { clock: () => now, arenaDataset: async k => { calls++; return arenaBundle(k); },
      epochDomain: async (k, o) => { calls++; return parseAcquisition(k, epochPayload(epochFiles()), o.now); } };
    const first = await new SharedLeaderboards(store, options).refresh(kinds[1]);
    assert.equal(first.board.kind, kinds[1]); assert.equal(store.boards.size, kinds[0] === 'epochMathECI' ? 3 : 2);
    await new SharedLeaderboards(store, options).refresh(kinds[0]);
    assert.equal(calls, 1);
  }
});

test('invalid or older companion retains its own cache while the valid requested board updates', async () => {
  const kinds = groups[0], old = arenaBundle(kinds[1]); delete old.relatedBoards;
  const incomplete = arenaBundle(kinds[0], arenaRows([kinds[0]]));
  assert.deepEqual(incomplete.relatedBoards, []);
  const files = epochFiles({ software: false });
  assert.deepEqual((await parseAcquisition('epochMathECI', epochPayload(files), now)).relatedBoards.map(b => b.kind), ['epochECI']);
  for (const mode of ['missing', 'older', 'write-failed']) {
    const store = new Store(); await store.writeBoard(kinds[1], old);
    const next = arenaBundle(kinds[0]);
    if (mode === 'missing') next.relatedBoards = [];
    if (mode === 'older') next.relatedBoards[0].sourceUpdatedAt = '2026-10-28T00:00:00.000Z';
    if (mode === 'write-failed') {
      const write = store.writeBoard.bind(store);
      store.writeBoard = async (k, b) => { if (k === kinds[1]) throw Error('write failed'); return write(k, b); };
    }
    const service = new SharedLeaderboards(store, { clock: () => now, arenaDataset: async () => next });
    await service.refresh(kinds[0]);
    assert.equal((await service.read(kinds[0])).board.entries.length, 22);
    assert.deepEqual((await service.read(kinds[1])).board, old);
  }
});

test('collector shares a file acquisition across routes and revalidates each related category/revision', async t => {
  let calls = 0; const token = 'T'.repeat(43), kinds = groups[0];
  const server = createServer(collectorHandler({ token, clock: () => now, load: async k => { calls++; return arenaBundle(k); } }));
  server.listen(0, '127.0.0.1'); await once(server, 'listening');
  t.after(() => { server.closeAllConnections(); server.close(); });
  const base = `http://127.0.0.1:${server.address().port}`;
  const boards = await Promise.all(Array.from({ length: 20 }, (_, i) => fetch(`${base}/v1/arena/${kinds[i % 2]}`, { headers: { 'x-benchgauge-collector-key': token } }).then(r => r.json())));
  assert.equal(calls, 1); assert.ok(boards.every((b, i) => b.kind === kinds[i % 2] && b.relatedBoards.length === 1));
  const environment = { ARENA_COLLECTOR_ENDPOINT: 'https://collector.ap-southeast-1.fcapp.run', ARENA_COLLECTOR_TOKEN: token };
  const bundle = boards[0];
  const load = () => loadConfiguredArenaDataset(kinds[0], { now, environment, includeRelated: true, fetcher: async () => new Response(JSON.stringify(bundle)) });
  assert.equal((await load()).relatedBoards[0].kind, kinds[1]);
  bundle.relatedBoards[0].sourceDatasetRevision = 'b'.repeat(40);
  assert.deepEqual((await load()).relatedBoards, []);
  bundle.relatedBoards[0].sourceDatasetRevision = revision; bundle.relatedBoards[0].entries[0].rank = 2;
  assert.deepEqual((await load()).relatedBoards, []);
});


test('general Epoch only inherits a domain cooldown when the downloaded general snapshot was saved', async () => {
  for (const mode of ['pending', 'write-failed', 'published']) {
    const store = new Store();
    const prior = await parseAcquisition('epochMathECI', epochPayload(epochFiles()), now - 1000);
    await store.writeBoard('epochECI', prior.relatedBoards.find(b => b.kind === 'epochECI'));
    const service = new SharedLeaderboards(store, { clock: () => now, epochDomain: async () => { throw Error('offline'); } });
    if (mode === 'pending') await service.refresh('epochMathECI', { clientFirst: true });
    else {
      if (mode === 'write-failed') {
        const write = store.writeBoard.bind(store);
        store.writeBoard = async (k, b) => { if (k === 'epochECI') throw Error('write failed'); return write(k, b); };
      }
      service.epochDomain = (k, o) => parseAcquisition(k, epochPayload(epochFiles()), o.now);
      await service.refresh('epochMathECI');
    }
    assert.equal(Boolean((await service.refresh('epochECI', { clientFirst: true })).grant), mode !== 'published');
  }
});

test('a group coordination failure never authorizes any sibling to acquire the origin', async () => {
  const store = new Store(); let calls = 0;
  const read = store.readState.bind(store);
  store.readState = async k => { if (k === legacyAcquisitionKey('arenaMultiImageEditing')) throw Error('OSS unavailable'); return read(k); };
  const service = new SharedLeaderboards(store, { clock: () => now, arenaDataset: async () => { calls++; throw Error('unexpected origin'); } });
  for (const k of groups[1]) {
    await assert.rejects(service.refresh(k, { clientFirst: true }), e => e.status === 503);
    await assert.rejects(service.refresh(k), e => e.status === 503);
  }
  assert.equal(calls, 0); assert.equal(store.states.size, 0);
});


test('AA general uses one model-page response for scores, cost and speed without a second supplemental fetch', async () => {
  const kind = 'artificialAnalysis', url = 'https://artificialanalysis.ai/models/';
  const rows = Array.from({ length: 22 }, (_, i) => ({ name: `Model ${i}`, slug: `m${i}`, intelligenceIndex: 100 - i,
    ...(i !== 1 && { intelligenceIndexCostPerTask: { cost: { total: i } } }), timescaleData: { medianOutputSpeed: 50 + i } }));
  const html = `<script>self.__next_f.push([1,${JSON.stringify(JSON.stringify({ rows }))}])</script>`;
  assert.deepEqual(acquisitionPlan(kind).resources.map(r => r.url), [url]);
  for (const fallback of [false, true]) {
    const store = new Store(); let originCalls = 0, supplementalCalls = 0;
    const previous = await parseAcquisition(kind, { resources: [{ url, data: Buffer.from(html).toString('base64') }] }, now - 1000);
    previous.entries[0].taskCostUSD = 999; previous.entries[1].taskCostUSD = 2;
    await store.writeBoard(kind, previous);
    const service = new SharedLeaderboards(store, { clock: () => now,
      publicSource: (k, o) => loadPublicSource(k, { ...o, fetcher: async requested => { assert.equal(requested, url); originCalls++; return new Response(html); } }),
      generalCosts: async () => { supplementalCalls++; throw Error('duplicate origin fetch'); } });
    const { grant } = await service.refresh(kind, { clientFirst: true });
    const result = fallback ? await service.fallback(kind, grant.token)
      : await service.acquire(kind, grant.token, { resources: [{ url, data: Buffer.from(html).toString('base64') }] });
    assert.equal(originCalls, Number(fallback)); assert.equal(supplementalCalls, 0);
    assert.equal(result.board.entries[0].taskCostUSD, 0); assert.equal(result.board.entries[0].speed, 50);
    assert.equal(result.board.entries[1].taskCostUSD, 2);
  }
});
