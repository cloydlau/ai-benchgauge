import assert from 'node:assert/strict';
import test from 'node:test';
import { createServer } from 'node:http';
import { once } from 'node:events';
import { completedUsageDay, parseOpenRouterUsage, loadOpenRouterUsage, loadConfiguredOpenRouterUsage, openRouterInterval, openRouterModelsURL, withOpenRouterModels } from '../fc/openrouter-usage.mjs';
import { collectorHandler } from '../fc/arena-collector.mjs';
import { SharedLeaderboards } from '../fc/service.mjs';
import { companyRows, resolvedOpenness } from '../fc/domain.mjs';
import { CountryRegistry } from '../fc/countries.mjs';
import { categories, boards } from '../apps/weapp/src/core/catalog.js';
import { visibleRows, normalizeBoard } from '../apps/weapp/src/core/leaderboard.js';
const now = Date.parse('2026-10-23T00:01:00Z');
const fixture = () => ({ meta: { as_of: '2026-10-23T00:00:30Z', version: 'v1', start_date: '2026-10-22', end_date: '2026-10-22' },
  data: [{ date: '2026-10-22', model_permaslug: 'openai/model-one', total_tokens: '9007199254740993' },
    { date: '2026-10-22', model_permaslug: 'openai/model-two:free', total_tokens: '20000000000' },
    { date: '2026-10-22', model_permaslug: 'anthropic/model-three', total_tokens: '30000000000' },
    { date: '2026-10-22', model_permaslug: 'other', total_tokens: '10000000000000000000' }] });
test('audited OpenRouter gaps repair saved and refreshed rows without guessing other builds or changing usage', async () => {
  const cases = [
    ['minimax/minimax-m3.1-flash-20261019:free', 'CN', 'closed'],
    ['meta/muse-spark-1.3-contributor-20260902', 'US', 'closed'],
    ['typesafe/jev-1.13-20260917', 'US', 'closed'],
    ['typesafe/jev-1.14-20261014', 'US', 'closed'],
    ['dots-studio/dots-3-note-preview-20260813:free', 'CN', 'open'],
    ['openai/gpt-6-luna-pro-20260922', 'US', 'closed'],
  ];
  const payload = fixture();
  payload.data = cases.map(([id], index) => ({ date: '2026-10-22', model_permaslug: id, total_tokens: String(9007199254740993n - BigInt(index)) }));
  const raw = parseOpenRouterUsage(payload, { now }), original = structuredClone(raw);
  let cached = { ...raw, entries: raw.entries.map(entry => ({ ...entry,
    developerCountry: { key: entry.organization.replace(/[^a-z]/g, ''), status: 'failed', nextAttemptAt: now + openRouterInterval },
  })) };
  const store = { readBoard: async () => cached, writeBoard: async (_, board) => { cached = board; },
    readState: async () => ({ position: 0 }), appendState: async () => true,
    readCountry: async () => { assert.fail('verified countries must resolve without discovery or cache retries'); } };
  const service = new SharedLeaderboards(store, { clock: () => now, countries: new CountryRegistry(store),
    openRouterConfigured: () => true, openRouterUsage: async () => structuredClone(raw) });
  for (const result of [await service.read('openRouterUsage'), await service.refresh('openRouterUsage'), await service.read('openRouterUsage')]) {
    const board = result.board;
    for (const [index, entry] of board.entries.entries()) {
      assert.equal(entry.developerCountry.countryCode, cases[index][1], entry.modelID);
      assert.equal(entry.developerCountry.status, 'ready');
      assert.equal(entry.openness, cases[index][2], entry.modelID);
      assert.equal(entry.totalTokens, raw.entries[index].totalTokens);
      assert.equal(entry.rank, raw.entries[index].rank);
    }
    const normalized = normalizeBoard(board, board.kind);
    assert.equal(visibleRows(normalized, { openness: 'open' }).length, 1);
    assert.equal(visibleRows(normalized, { openness: 'closed' }).length, 5);
    assert.equal(board.sourceNote, raw.sourceNote);
    assert.deepEqual(board.sourceMeta, raw.sourceMeta);
  }
  assert.deepEqual(raw, original);
  for (const [modelID] of cases) {
    assert.equal(resolvedOpenness({ modelID: modelID + '-unverified' }), null);
    assert.equal(resolvedOpenness({ modelID, openness: 'open' }), 'open');
  }
  assert.equal(resolvedOpenness({ modelID: 'minimax/minimax-m3-20260531', modelMetadata: { source: 'models.dev', openWeights: true } }), 'open');
});
test('one completed UTC day preserves exact tokens, variants, original meta and CC attribution; other is not a model', () => {
  assert.equal(completedUsageDay(now), '2026-10-22');
  const payload = fixture(), board = parseOpenRouterUsage(payload, { now });
  assert.deepEqual(board.sourceMeta, payload.meta);
  assert.equal(board.entries.length, 3);
  assert.equal(board.entries[0].totalTokens, '9007199254740993');
  assert.equal(board.entries[2].modelID, 'openai/model-two:free');
  assert.equal(board.otherTokens, '10000000000000000000');
  assert.match(board.sourceNote, /Source: OpenRouter \(openrouter.ai\/rankings\), as of 2026-10-23T00:00:30Z\./);
  assert.match(board.sourceNote, /Licensed under CC BY 4.0/);
  assert.match(board.sourceNote, /UTC 2026-10-22/);
  assert.deepEqual(categories.map(category => category.id), ['usage', 'general', 'coding', 'image', 'video']);
  assert.deepEqual(categories[0].kinds, ['openRouterUsage', 'vercelUsage', 'cloudbaseUsage']);
  assert.equal(boards.openRouterUsage.title, 'OpenRouter');
  const normalized = normalizeBoard(board, board.kind);
  assert.equal(normalized.entries[0].totalTokens, payload.data[0].total_tokens);
  assert.equal(visibleRows(normalized)[1].scoreText, '30.00B');
  const company = companyRows(board.entries, { summingUsage: true });
  assert.equal(company[0].totalTokens, '9007219254740993');
  assert.equal(company[0].score, board.entries[0].score + board.entries[2].score);
  assert.equal(companyRows(board.entries)[0].score, board.entries[0].score);
});
test('rejects mixed dates, duplicate models, invalid/overflow tokens and unverified snapshots', () => {
  const changes = [p => p.data[0].date = '2026-10-21', p => p.data.push(p.data[0]),
    p => p.data[0].total_tokens = 123, p => p.data[0].total_tokens = '-1', p => p.data[0].total_tokens = '18446744073709551616',
    p => p.data[0].total_tokens = '1e12', p => p.data[0].model_permaslug = '<script>',
    p => p.meta.as_of = '2026-10-24T00:00:00Z', p => p.meta.as_of = '2026-10-22T00:00:00Z',
    p => p.meta.start_date = '2026-02-30', p => p.meta.end_date = '2026-10-23', p => p.meta.version = 'v2',
    p => p.data = [], p => p.data = [p.data.at(-1)], p => p.data = Array(52).fill(p.data[0])];
  for (const change of changes) { const data = fixture(); change(data); assert.throws(() => parseOpenRouterUsage(data, { now })); }
  assert.throws(() => parseOpenRouterUsage(fixture(), { now, day: '2026-02-30' }));
  assert.throws(() => parseOpenRouterUsage(fixture(), { now, day: '2026-10-23' }));
});
test('official acquisition uses only server key, a bounded JSON response, no redirects, and no scraping', async () => {
  let calls = 0;
  const fetcher = async (url, options) => {
    calls++;
    if (url === openRouterModelsURL) {
      assert.equal(options.headers.Authorization, undefined);
      assert.equal(options.redirect, 'error');
      return new Response(JSON.stringify({ data: [{ id: 'openai/model-one', canonical_slug: 'openai/model-one' }] }));
    }
    assert.equal(url, 'https://openrouter.ai/api/v1/datasets/rankings-daily?start_date=2026-10-22&end_date=2026-10-22');
    assert.equal(options.headers.Authorization, 'Bearer test-only-key');
    assert.equal(options.redirect, 'error');
    return new Response(JSON.stringify(fixture()));
  };
  await assert.rejects(loadOpenRouterUsage({ now, apiKey: '', fetcher })); assert.equal(calls, 0);
  const board = await loadOpenRouterUsage({ now, apiKey: 'test-only-key', fetcher, includeSpeeds: false });
  assert.equal(board.entries.length, 3); assert.equal(board.entries[0].openRouterModelID, 'openai/model-one');
  assert.equal(calls, 2);
  for (const response of [new Response('', { status: 429 }), new Response('bad'), new Response('x'.repeat(256001))]) {
    await assert.rejects(loadOpenRouterUsage({ now, apiKey: 'test-only-key', fetcher: async () => response }));
  }
});
test('official model pairs preserve dated builds and variants, reject conflicts, and never infer missing identities', async () => {
  const entries = ['lab/k3-20261017', 'lab/k3-20261017:free', 'lab/k3-20260910', 'other/k3-20261017',
    'lab/k3-20261017:unknown', 'lab/k3-20260801'].map(modelID => ({ modelID, name: 'K3' }));
  const board = { kind: 'openRouterUsage', entries };
  const payload = { data: [
    { id: 'lab/k3-1017', canonical_slug: 'lab/k3-20261017' },
    { id: 'lab/k3-1017:free', canonical_slug: 'lab/k3-20261017' },
    { id: 'lab/k3', canonical_slug: 'lab/k3-20260910' },
    { id: 'lab/k3:batch', canonical_slug: 'lab/k3-20260910' },
    { id: 'other/explicit-route', canonical_slug: 'lab/k3-20260801' },
    { id: '~lab/k3-latest', canonical_slug: 'lab/k3-20261017' },
  ] };
  const enriched = withOpenRouterModels(board, payload);
  assert.deepEqual(enriched.entries.map(e => e.openRouterModelID), ['lab/k3-1017', 'lab/k3-1017:free', 'lab/k3', undefined, undefined, 'other/explicit-route']);
  assert.deepEqual(enriched.entries.map(e => e.modelID), entries.map(e => e.modelID));
  assert.equal(withOpenRouterModels(board, { data: [...payload.data,
    { id: 'lab/conflicting', canonical_slug: 'lab/k3-20261017' }] }).entries[0].openRouterModelID, undefined);
  assert.deepEqual(withOpenRouterModels(enriched, { data: [] }), board, 'A missing explicit pair removes stale identity hints');
  for (const data of [[{ id: 'lab/k3', canonical_slug: 'lab/k3-20261017:free' }],
    [{ id: 'lab/k3:batch', canonical_slug: 'lab/k3-20261017:free' }],
    [{ id: 'bad', canonical_slug: 'lab/k3-20261017' }], [{ id: 'lab/k3' }], Array(10001).fill(payload.data[0]), null]) {
    assert.throws(() => withOpenRouterModels(board, { data }));
  }
  for (const response of [new Response('{}', { status: 503 }), new Response('invalid JSON'),
    new Response(JSON.stringify({ data: [{ id: 'invalid', canonical_slug: 'lab/k3' }] }))]) {
    const loaded = await loadOpenRouterUsage({ now, apiKey: 'test-only-key', fetcher: async url =>
      url === openRouterModelsURL ? response : new Response(JSON.stringify(fixture())) });
    assert.deepEqual(loaded, parseOpenRouterUsage(fixture(), { now }), 'Metadata failure retains independently validated usage');
  }
});
test('durable hourly coordination, no-key state, disabled contributions, and last good cache after failures', async () => {
  let cached = null, state = null, position = 0, calls = 0, time = now, configured = false, fail = false;
  const store = { readBoard: async () => cached, writeBoard: async (_, board) => { cached = board; },
    readState: async () => ({ state, position }), appendState: async (_, expected, value) => {
      if (expected !== position) return false; state = value; position++; return true;
    } };
  const service = new SharedLeaderboards(store, { clock: () => time, openRouterConfigured: () => configured,
    openRouterUsage: async () => { calls++; if (fail) throw Error('private upstream error'); return parseOpenRouterUsage(fixture(), { now }); } });
  assert.deepEqual(await service.read('openRouterUsage'), { board: null, configurationRequired: true });
  assert.deepEqual(await service.refresh('openRouterUsage'), { board: null, configurationRequired: true });
  assert.equal(calls, 0); assert.equal(state, null);
  await assert.rejects(service.contribute('openRouterUsage', 'x'.repeat(43), '<html/>'), { status: 403 });
  configured = true;
  const results = await Promise.all([service.refresh('openRouterUsage'), service.refresh('openRouterUsage')]);
  assert.equal(calls, 1); assert.ok(results.some(result => result.board));
  assert.ok(results.every(result => !result.grant));
  await service.refresh('openRouterUsage'); assert.equal(calls, 1);
  time += openRouterInterval; fail = true;
  assert.deepEqual((await service.refresh('openRouterUsage')).board, cached);
  assert.equal(calls, 2);
  configured = false;
  assert.deepEqual((await service.refresh('openRouterUsage')).board, cached);
  cached = null; configured = true; time += openRouterInterval;
  await assert.rejects(service.refresh('openRouterUsage'), { status: 503, message: 'OpenRouter usage temporarily unavailable' });
});

test('configured usage uses the authenticated Singapore route and independently validates original tokens and metadata', async () => {
  const environment = { OPENROUTER_API_KEY: 'test-only-key', ARENA_COLLECTOR_ENDPOINT: 'https://fixture.ap-southeast-1.fcapp.run',
    ARENA_COLLECTOR_TOKEN: 'T'.repeat(43) };
  const board = withOpenRouterModels(parseOpenRouterUsage(fixture(), { now }), {
    data: [{ id: 'openai/model-one', canonical_slug: 'openai/model-one' }],
  }); let calls = 0;
  const fetcher = async (url, options) => {
    calls++;
    assert.equal(url.href, 'https://fixture.ap-southeast-1.fcapp.run/v1/openrouter-usage');
    assert.equal(options.headers.Authorization, 'Bearer test-only-key');
    assert.equal(options.headers['x-benchgauge-collector-key'], environment.ARENA_COLLECTOR_TOKEN);
    assert.equal(options.redirect, 'error');
    return new Response(JSON.stringify({ ...board, title: 'Untrusted display text', sourceNote: 'No attribution',
      entries: board.entries.map(entry => ({ ...entry, name: 'Untrusted name' })) }));
  };
  assert.deepEqual(await loadConfiguredOpenRouterUsage({ now, environment, fetcher }), board);
  assert.equal(calls, 1);
  for (const endpoint of ['http://fixture.ap-southeast-1.fcapp.run', 'https://evil.example',
    'https://fixture.ap-southeast-1.fcapp.run/path', 'https://fixture.ap-southeast-1.fcapp.run?x=1',
    'https://user:password@fixture.ap-southeast-1.fcapp.run', 'https://fixture.ap-southeast-1.fcapp.run:8443']) {
    await assert.rejects(loadConfiguredOpenRouterUsage({ now, environment: { ...environment, ARENA_COLLECTOR_ENDPOINT: endpoint }, fetcher }));
  }
  await assert.rejects(loadConfiguredOpenRouterUsage({ now, environment: { ...environment, ARENA_COLLECTOR_TOKEN: '' }, fetcher }));
  await assert.rejects(loadConfiguredOpenRouterUsage({ now, environment: { ...environment, OPENROUTER_API_KEY: '' }, fetcher }));
  assert.equal(calls, 1, 'Invalid destinations never receive the API key');
  for (const corrupt of [{ kind: 'arenaText' }, { entries: [] }, { entries: null },
    { fetchedAt: 'invalid' }, { fetchedAt: new Date(now - 3600001).toISOString() },
    { fetchedAt: new Date(now + 300001).toISOString() }, { sourceMeta: { ...board.sourceMeta, version: 'v2' } },
    { otherTokens: '-1' }, { entries: [{ ...board.entries[0], modelID: 'other' }] },
    { entries: [{ ...board.entries[0], totalTokens: '18446744073709551616' }] },
    { entries: [{ ...board.entries[0], openRouterModelID: 'invalid' }] },
    { entries: [{ ...board.entries[2], openRouterModelID: 'openai/model-two' }] },
    { entries: Array(51).fill(board.entries[0]) }]) {
    await assert.rejects(loadConfiguredOpenRouterUsage({ now, environment,
      fetcher: async () => new Response(JSON.stringify({ ...board, ...corrupt })) }));
  }
  await assert.rejects(loadConfiguredOpenRouterUsage({ now, environment,
    fetcher: async () => new Response('{}', { status: 503 }) }));
  const direct = await loadConfiguredOpenRouterUsage({ now, environment: { OPENROUTER_API_KEY: 'test-only-key' },
    fetcher: async (url, options) => {
      if (url === openRouterModelsURL) return new Response(JSON.stringify({ data: [{ id: 'openai/model-one', canonical_slug: 'openai/model-one' }] }));
      assert.ok(url.startsWith('https://openrouter.ai/api/v1/datasets/rankings-daily?'));
      assert.equal(options.headers.Authorization, 'Bearer test-only-key');
      return new Response(JSON.stringify(fixture()));
    } });
  assert.deepEqual(direct, board);
});

test('collector authenticates usage requests before loading, separates keys and UTC days, and redacts failures', async t => {
  const token = 'T'.repeat(43); let time = now, calls = 0;
  const server = createServer(collectorHandler({ token, clock: () => time, usage: async options => {
    calls++; assert.equal(options.now, time);
    if (options.apiKey === 'invalid-key') throw Error('private upstream error containing invalid-key');
    return parseOpenRouterUsage(fixture(), { now });
  } }));
  server.listen(0, '127.0.0.1'); await once(server, 'listening');
  t.after(() => { server.closeAllConnections(); server.close(); });
  const url = `http://127.0.0.1:${server.address().port}/v1/openrouter-usage`;
  const headers = { 'x-benchgauge-collector-key': token, Authorization: 'Bearer first-key' };
  assert.equal((await fetch(url)).status, 403);
  assert.equal((await fetch(url, { headers: { 'x-benchgauge-collector-key': token } })).status, 403);
  assert.equal((await fetch(url, { headers: { ...headers, Authorization: 'Basic first-key' } })).status, 403);
  assert.equal((await fetch(url + '?url=https://evil.example', { headers })).status, 404);
  assert.equal((await fetch(url, { method: 'POST', headers })).status, 404);
  assert.equal(calls, 0);
  const results = await Promise.all(Array.from({ length: 8 }, () => fetch(url, { headers }).then(r => r.json())));
  assert.equal(calls, 1); assert.ok(results.every(result => result.entries.length === 3));
  await fetch(url, { headers: { ...headers, Authorization: 'Bearer second-key' } }); assert.equal(calls, 2);
  time += 86400000;
  await fetch(url, { headers }); assert.equal(calls, 3, 'UTC rollover cannot reuse yesterday\'s dataset');
  for (let i = 0; i < 2; i++) {
    const response = await fetch(url, { headers: { ...headers, Authorization: 'Bearer invalid-key' } });
    assert.equal(response.status, 503); assert.equal(await response.text(), '{}');
  }
  assert.equal(calls, 5, 'A failed key never receives cached success from another key or poisons later retries');
});
