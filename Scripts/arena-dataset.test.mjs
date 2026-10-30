import assert from 'node:assert/strict';
import test from 'node:test';
import { createServer } from 'node:http';
import { once } from 'node:events';
import { readFileSync } from 'node:fs';
import { parseArenaRows, loadArenaDataset, arenaSubsets, arenaDataURL, isArenaDataset } from '../fc/arena-dataset.mjs';
import { SharedLeaderboards, refreshInterval } from '../fc/service.mjs';
import { handler } from '../fc/server.mjs';
import { modelOpenness } from '../fc/parser.mjs';
import { canReplace } from '../fc/domain.mjs';

const now = Date.parse('2026-10-19T00:00:00Z'), revision = 'a'.repeat(40);
const rows = () => Array.from({ length: 22 }, (_, i) => ({ model_name: `model-${i}`, organization: 'openai', license: 'Proprietary',
  rating: 1523.9035861299108 - i, vote_count: BigInt(1000 + i), rank: BigInt(i + 1), category: 'overall', leaderboard_publish_date: '2026-10-15' }));
const parsed = (kind = 'arenaText', source = rows(), time = now) => parseArenaRows(kind, source, { now: time, revision, classifyLicense: modelOpenness });
class Store {
  boards = new Map(); states = new Map(); writes = 0;
  async readBoard(kind) { return this.boards.get(kind) ?? null; }
  async writeBoard(kind, board) { this.writes++; this.boards.set(kind, board); }
  async readState(key) { return this.states.get(key) ?? { position: 0, state: null }; }
  async appendState(key, position, state) {
    if ((this.states.get(key)?.position ?? 0) !== position) return false;
    this.states.set(key, { position: position + 1, state }); return true;
  }
}

test('all four subsets preserve published scores, ranks, counts, license and date; never mix categories', () => {
  assert.equal(arenaSubsets.arenaText, 'text_style_control');
  assert.equal(arenaSubsets.arenaTextUncontrolled, 'text');
  for (const kind of Object.keys(arenaSubsets)) {
    const source = rows(); if (kind === 'arenaMultiImageEditing') source.forEach(row => { row.category = 'multi_image_edit'; });
    if (kind === 'codeArenaImageToWebDev') source.forEach(row => { row.category = 'image_to_webdev'; });
    source[0].license = 'MIT'; source[1].organization = ''; source[2].license = 'Unrecognized new license';
    const board = parsed(kind, [...source, { category: 'coding', rating: 9999 }]);
    assert.equal(board.entries.length, 22); assert.equal(board.entries[0].score, source[0].rating);
    assert.equal(board.entries[0].rank, 1); assert.equal(board.entries[0].voteCount, 1000);
    assert.equal(board.entries[0].openness, 'open'); assert.equal(board.entries[0].organization, 'OpenAI');
    assert.equal(board.entries[1].organization, undefined); assert.equal(board.entries[2].openness, undefined);
    assert.equal(board.sourceUpdatedAt, '2026-10-15T00:00:00.000Z'); assert.equal(board.sourceDatasetRevision, revision);
    assert.ok(board.sourceNote.includes('/tree/' + revision)); assert.ok(board.sourceNote.includes('creativecommons.org/licenses/by/4.0/'));
    assert.ok(isArenaDataset(board)); assert.ok(arenaDataURL(kind, revision).includes('/resolve/' + revision + '/'));
  }
  const duplicate = rows(); duplicate[1].model_name = duplicate[0].model_name;
  const board = parsed('codeArenaWebDev', duplicate);
  assert.equal(board.entries.length, 22); assert.equal(board.entries[0].name, board.entries[1].name);
  assert.notEqual(board.entries[0].modelID, board.entries[1].modelID); assert.equal(board.entries[1].rank, 2);
});

test('partial snapshots, mixed dates, invalid counts/ranks and future dates cannot publish', () => {
  assert.throws(() => parsed('arenaText', rows().slice(0, 19)));
  for (const change of [{ rank: 2 }, { rank: null }, { vote_count: null }, { vote_count: -1 }, { rating: NaN },
    { model_name: '' }, { model_name: 'bad\nname' }, { leaderboard_publish_date: '2099-01-01' },
    { leaderboard_publish_date: '2026-02-30' }, { leaderboard_publish_date: '2026-10-14' }]) {
    const source = rows(); source[0] = { ...source[0], ...change }; assert.throws(() => parsed('arenaText', source));
  }
  assert.throws(() => arenaDataURL('arenaText', '../../attacker')); assert.throws(() => arenaDataURL('__proto__'));
});

test('migration replaces website timestamps once, retains anti-rollback checks and never reverts to website data', () => {
  const next = parsed(), old = { ...next, sourceNote: undefined, sourceUpdatedAt: '2026-10-18T18:00:00Z', fetchedAt: new Date(now - 1).toISOString() };
  assert.ok(canReplace(next, old)); assert.equal(canReplace(old, next), false);
  assert.equal(canReplace({ ...next, sourceUpdatedAt: '2026-10-14T00:00:00Z' }, next), false);
  assert.equal(canReplace({ ...next, fetchedAt: new Date(now - 1).toISOString() }, next), false);
});

test('100 FC instances acquire only one dataset fetch, publish once and return no client grants', async () => {
  const store = new Store(); let calls = 0, time = now;
  const options = { clock: () => time, arenaDataset: async kind => { calls++; return parsed(kind, rows(), time); } };
  const result = await Promise.all(Array.from({ length: 100 }, () => new SharedLeaderboards(store, options).refresh('arenaText')));
  assert.equal(calls, 1); assert.equal(store.writes, 1); assert.ok(result.every(value => !value.grant));
  const service = new SharedLeaderboards(store, options), board = (await service.read('arenaText')).board;
  await service.refresh('arenaText'); assert.equal(calls, 1); assert.equal(board.fetchedAt, new Date(now).toISOString());
  time += refreshInterval; await service.refresh('arenaText'); assert.equal(calls, 2);
  await assert.rejects(service.contribute('arenaText', 'A'.repeat(43), '<html>website</html>'), error => error.status === 403);
});

test('failed or older dataset updates retain the last licensed snapshot; website-only caches are withheld', async () => {
  const store = new Store(), good = parsed(); store.boards.set('arenaText', good);
  const broken = new SharedLeaderboards(store, { clock: () => now, arenaDataset: async () => { throw new Error('timeout'); } });
  assert.deepEqual((await broken.refresh('arenaText')).board, good); assert.equal(store.writes, 0);
  store.states.clear();
  const older = new SharedLeaderboards(store, { clock: () => now, arenaDataset: async () => ({ ...good, sourceUpdatedAt: '2026-10-14T00:00:00Z' }) });
  assert.deepEqual((await older.refresh('arenaText')).board, good); assert.equal(store.writes, 0);
  store.boards.set('arenaText', { ...good, sourceNote: undefined }); store.states.clear();
  assert.equal((await broken.read('arenaText')).board, null);
  await assert.rejects(broken.refresh('arenaText'), error => error.status === 503);
  assert.equal(store.writes, 0);
});

test('Arena schedules missing metadata only after a valid dataset is committed', async () => {
  const store = new Store(), queued = [];
  const models = { enrich: async board => board, queue: async board => {
    assert.equal(store.boards.get(board.kind), board); queued.push(board.kind);
  } };
  const service = new SharedLeaderboards(store, { clock: () => now, models, arenaDataset: async () => parsed() });
  await service.read('arenaText'); assert.deepEqual(queued, []);
  await service.refresh('arenaText'); assert.deepEqual(queued, ['arenaText']);
  await service.refresh('arenaText'); assert.deepEqual(queued, ['arenaText']);
  store.states.clear(); store.writeBoard = async () => { throw Error('Write failed'); };
  await service.refresh('arenaText'); assert.deepEqual(queued, ['arenaText']);
});

test('HTTP refresh serves a dataset and rejects website contributions; read never initiates acquisition', async t => {
  const store = new Store(); let calls = 0;
  const service = new SharedLeaderboards(store, { clock: () => now, arenaDataset: async kind => { calls++; return parsed(kind); } });
  const server = createServer(handler(() => service)); server.listen(0, '127.0.0.1'); await once(server, 'listening');
  t.after(() => { server.closeAllConnections(); server.close(); });
  const url = `http://127.0.0.1:${server.address().port}/v1/boards/arenaText`;
  assert.deepEqual(await (await fetch(url)).json(), { board: null }); assert.equal(calls, 0);
  const response = await (await fetch(url + '/refresh', { method: 'POST' })).json();
  assert.equal(response.board.entries.length, 22); assert.equal(response.grant, undefined);
  assert.equal((await fetch(url + '/contribute', { method: 'POST', headers: { 'Content-Type': 'text/html' }, body: '<html/>' })).status, 403);
  assert.equal(calls, 1);
});

test('dataset loader verifies the license/revision before acquiring any Parquet file', async () => {
  for (const info of [{ sha: revision, cardData: { license: 'other' } }, { sha: '../bad', cardData: { license: 'cc-by-4.0' } }]) {
    const requests = [];
    await assert.rejects(loadArenaDataset('arenaText', { fetcher: async url => { requests.push(url); return new Response(JSON.stringify(info)); } }));
    assert.equal(requests.length, 1);
  }
  const runtime = readFileSync(new URL('../Scripts/deploy-shared-leaderboards.mjs', import.meta.url), 'utf8');
  assert.ok(runtime.includes("'arena-dataset.mjs'")); assert.ok(runtime.includes("'arena-attribution.json'"));
  assert.match(readFileSync(new URL('../fc/server.mjs', import.meta.url), 'utf8'), /arenaDataset: loadConfiguredArenaDataset/);
});

test('collector authenticates before acquisition and shares in-flight work without accepting arbitrary sources', async t => {
  const { collectorHandler } = await import('../fc/arena-collector.mjs');
  const token = 'T'.repeat(43); let calls = 0;
  const server = createServer(collectorHandler({ token, clock: () => now, load: async kind => { calls++; return parsed(kind); } }));
  server.listen(0, '127.0.0.1'); await once(server, 'listening');
  t.after(() => { server.closeAllConnections(); server.close(); });
  const url = `http://127.0.0.1:${server.address().port}/v1/arena/arenaText`;
  assert.equal((await fetch(url)).status, 403); assert.equal(calls, 0);
  const headers = { 'x-benchgauge-collector-key': token };
  assert.equal((await fetch(url + '?url=https://example.com', { headers })).status, 404); assert.equal(calls, 0);
  const responses = await Promise.all(Array.from({ length: 10 }, () => fetch(url, { headers }).then(r => r.json())));
  assert.equal(calls, 1); assert.ok(responses.every(board => board.entries.length === 22));
});

test('configured collector preserves official scores and validates the returned snapshot and fixed destination', async () => {
  const { loadConfiguredArenaDataset } = await import('../fc/arena-collector.mjs');
  const environment = { ARENA_COLLECTOR_ENDPOINT: 'https://fixture.ap-southeast-1.fcapp.run', ARENA_COLLECTOR_TOKEN: 'T'.repeat(43) };
  const requests = [];
  const fetcher = async (url, options) => { requests.push({ url, options }); return new Response(JSON.stringify(parsed())); };
  const board = await loadConfiguredArenaDataset('arenaText', { now, environment, fetcher });
  assert.equal(board.entries[0].score, parsed().entries[0].score); assert.equal(board.sourceDatasetRevision, revision);
  assert.equal(requests[0].url.pathname, '/v1/arena/arenaText'); assert.equal(requests[0].options.redirect, 'error');
  for (const endpoint of ['https://evil.example', 'http://fixture.ap-southeast-1.fcapp.run', 'https://fixture.ap-southeast-1.fcapp.run/path']) {
    await assert.rejects(loadConfiguredArenaDataset('arenaText', { now, environment: { ...environment, ARENA_COLLECTOR_ENDPOINT: endpoint }, fetcher }));
  }
  for (const corrupt of [{ kind: 'artificialAnalysis' }, { sourceNote: '' }, { sourceDatasetRevision: '../bad' }, { fetchedAt: new Date(now + 600000).toISOString() }, { entries: parsed().entries.slice(0, 3) }]) {
    await assert.rejects(loadConfiguredArenaDataset('arenaText', { now, environment,
      fetcher: async () => new Response(JSON.stringify({ ...parsed(), ...corrupt })) }));
  }
});

test('image-to-WebDev round trip selects only its own category and publication date', async () => {
  const { loadConfiguredArenaDataset } = await import('../fc/arena-collector.mjs');
  const source = rows().map(row => ({ ...row, category: 'image_to_webdev', leaderboard_publish_date: '2026-10-14' }));
  const board = parsed('codeArenaImageToWebDev', [...rows(), ...source]);
  assert.equal(board.sourceUpdatedAt, '2026-10-14T00:00:00.000Z');
  assert.match(board.sourceNote, /webdev\/latest\/image_to_webdev/);
  const restored = await loadConfiguredArenaDataset('codeArenaImageToWebDev', { now,
    environment: { ARENA_COLLECTOR_ENDPOINT: 'https://fixture.ap-southeast-1.fcapp.run', ARENA_COLLECTOR_TOKEN: 'T'.repeat(43) },
    fetcher: async () => new Response(JSON.stringify(board)) });
  assert.deepEqual(restored.entries, board.entries);
});
