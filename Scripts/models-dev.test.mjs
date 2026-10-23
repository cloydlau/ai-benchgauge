import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { once } from 'node:events';
import { parseModelsDev, validModelsDev, modelMatcher, ModelsDevRegistry, modelsDevInterval, loadModelsDev, loadConfiguredModelsDev } from '../fc/models-dev.mjs';
import { resolvedOpenness } from '../fc/domain.mjs';
import { handler } from '../fc/server.mjs';
import { sources } from '../fc/parser.mjs';
import { withOpenRouterModels } from '../fc/openrouter-usage.mjs';
const now = Date.now(), revision = 'a'.repeat(64);
function raw() {
  const models = Object.fromEntries(Array.from({ length: 100 }, (_, i) => [`lab/model-${i}`, { id: `lab/model-${i}`, name: `Model ${i}`, limit: { context: 100000 }, open_weights: true, license: 'Apache-2.0' }]));
  const providers = Object.fromEntries(Array.from({ length: 5 }, (_, p) => [`provider-${p}`, { name: `Provider ${p}`, models: Object.fromEntries(Object.values(models).map((m, i) => [String(i), { id: String(i), name: m.name, canonical_model_id: m.id, limit: { context: 50000, output: 1000 }, cost: { input: p, output: p + 1, tiers: [{ input: p * 2, output: p * 3, tier: { type: 'context', size: 200000 } }] } }])) }]));
  return { models, providers };
}
const parsed = (time = now) => parseModelsDev(raw(), { now: time, revision });
class Store {
  value = null; states = new Map(); writes = 0;
  get state() { return this.states.get('models-dev'); }
  set state(value) { if (value) this.states.set('models-dev', value); else this.states.delete('models-dev'); }
  async readModelsDev() { return this.value; }
  async writeModelsDev(v) { this.value = v; this.writes++; }
  async readState(key) { return this.states.get(key) ?? { position: 0, state: null }; }
  async appendState(key, pos, state) { if ((this.states.get(key)?.position ?? 0) !== pos) return false; this.states.set(key, { position: pos + 1, state }); return true; }
}

test('catalog retains canonical facts separately from provider prices, units, zero prices and tiers', () => {
  const s = parsed(), m = s.models[0]; assert.ok(validModelsDev(s));
  assert.equal(m.limit.context, 100000); assert.equal(m.openWeights, true); assert.equal(m.license, 'Apache-2.0');
  assert.equal(m.offers.length, 5); assert.equal(m.offers[0].limit.context, 50000);
  assert.equal(m.offers[0].cost.input, 0); assert.equal(m.offers[1].cost.input, 1);
  assert.equal(m.offers[1].cost.tiers[0].tier.size, 200000); assert.equal(m.offers[0].unit, 'per-million-tokens');
  assert.match(s.license, /Copyright \(c\) 2025 models.dev/); assert.equal(m.sampleCount, undefined);
});
test('invalid or incomplete source and stored snapshots cannot publish', () => {
  for (const change of [r => { r.models = {}; }, r => { r.models['lab/model-0'].open_weights = 'false'; },
    r => { r.providers['provider-0'].models['0'].cost.input = -1; }, r => { r.models['lab/model-0'].limit.context = Infinity; }]) {
    const r = raw(); change(r); assert.throws(() => parseModelsDev(r, { now, revision }));
  }
  for (const change of [s => { s.models[0].offers[0].cost.output = -1; }, s => { s.models[0].openWeights = 'false'; },
    s => { s.models[0].offers[0].currency = 'CNY'; }, s => { s.license = 'MIT'; }]) {
    const s = parsed(); change(s); assert.equal(validModelsDev(s), false);
  }
});
test('provider wrappers without a confirmed canonical link cannot establish model identity', () => {
  const r = raw();
  r.providers.lab = { name: 'Lab', models: {
    'model-0': { id: 'model-0', name: 'Unconfirmed wrapper', canonical_model_id: 'missing/model', cost: { input: 1, output: 2 } },
    'model-1': { id: 'model-1', name: 'Exact native endpoint', cost: { input: 1, output: 2 } },
  } };
  const s = parseModelsDev(r, { now, revision });
  assert.equal(modelMatcher(s)({ name: 'Unconfirmed wrapper' }), null);
  assert.equal(modelMatcher(s)({ name: 'Exact native endpoint' }).id, 'lab/model-1');
});
test('identity matching preserves numeric versions, agents, ambiguous names and exact provider canonical links', () => {
  const s = parsed(); s.models[0].name = 'Variant 5.1'; s.models[0].id = 'lab/variant-5.1';
  s.models[1].name = 'Variant 51'; s.models[1].id = 'lab/variant-51';
  s.models[2].name = 'Ambiguous'; s.models[3].name = 'Ambiguous'; s.models[3].id = 'other/ambiguous';
  const match = modelMatcher(s);
  assert.equal(match({ name: 'Variant 5.1 (high)' }).id, 'lab/variant-5.1');
  assert.equal(match({ name: 'Variant 51' }).id, 'lab/variant-51');
  assert.equal(match({ name: 'Variant 5.2' }), null); assert.equal(match({ name: 'Ambiguous' }), null);
  assert.equal(match({ name: 'Agent - Variant 5.1 (high)' }, 'artificialAnalysisCodingAgent').id, 'lab/variant-5.1');
  assert.equal(match({ name: 'Unknown', modelID: 'provider-1/0' }).id, 'lab/variant-5.1');
  assert.equal(match({ name: 'Variant 5.1 + Variant 51' }), null);
});
test('OpenRouter usage joins only confirmed OpenRouter offers through official full-ID pairs, including closed weights', async () => {
  const r = raw();
  r.models['lab/model-1'].open_weights = false;
  r.providers.openrouter = { name: 'OpenRouter', models: {
    'vendor/k3-1017': { id: 'vendor/k3-1017', canonical_model_id: 'lab/model-0' },
    'vendor/k3': { id: 'vendor/k3', canonical_model_id: 'lab/model-1' },
    'vendor/k3-1017:free': { id: 'vendor/k3-1017:free', canonical_model_id: 'lab/model-0' },
  } };
  const store = new Store(); store.value = parseModelsDev(r, { now, revision });
  const original = { kind: 'openRouterUsage', fetchedAt: new Date(now).toISOString(), entries: [
    { modelID: 'vendor/k3-20261017', name: 'Model 1', rank: 1, totalTokens: '123456789123456789' },
    { modelID: 'vendor/k3-20260910', name: 'Model 0', rank: 2 },
    { modelID: 'vendor/k3-20261017:free', name: 'Model 0', rank: 3 },
    { modelID: 'other/k3-20261017', name: 'Model 0', rank: 4 },
    { modelID: 'vendor/k3-20260801', name: 'Model 0', rank: 5 },
    { modelID: 'provider-1/0', name: 'Model 0', rank: 6 },
    { modelID: 'vendor/k3-1017', name: 'Ignored name', rank: 7 },
  ] };
  const board = withOpenRouterModels(original, { data: [
    { id: 'vendor/k3-1017', canonical_slug: 'vendor/k3-20261017' },
    { id: 'vendor/k3', canonical_slug: 'vendor/k3-20260910' },
    { id: 'vendor/k3-1017:free', canonical_slug: 'vendor/k3-20261017' },
  ] });
  const enriched = await new ModelsDevRegistry(store).enrich(board);
  assert.deepEqual(enriched.entries.map(e => e.modelMetadata?.id), ['lab/model-0', 'lab/model-1', 'lab/model-0', undefined, undefined, undefined, 'lab/model-0']);
  assert.deepEqual(enriched.entries.map(resolvedOpenness), ['open', 'closed', 'open', null, null, null, 'open']);
  assert.equal(enriched.entries[0].totalTokens, original.entries[0].totalTokens);
  assert.equal(enriched.fetchedAt, original.fetchedAt); assert.equal(store.writes, 0);
  const s = store.value;
  s.models[2].offers.push({ ...s.models[0].offers.find(o => o.provider === 'openrouter') });
  assert.equal(modelMatcher(s)(board.entries[0], board.kind), null, 'Conflicting canonical links cannot be disambiguated by display name');
});
test('100 concurrent services sync once; 24-hour freshness and failed updates retain the last valid OSS snapshot', async () => {
  const store = new Store(); let calls = 0, time = now;
  const make = () => new ModelsDevRegistry(store, { clock: () => time, load: async () => { calls++; return parsed(time); } });
  await Promise.all(Array.from({ length: 100 }, () => make().sync())); assert.equal(calls, 1); assert.equal(store.writes, 1);
  assert.equal(modelsDevInterval, 24 * 60 * 60 * 1000);
  await make().sync(); assert.equal(calls, 1);
  time += 6 * 60 * 60 * 1000; await make().sync(); assert.equal(calls, 1);
  time = now + modelsDevInterval - 1; await make().sync(); assert.equal(calls, 1);
  time++; // Existing facts become due only after a full day.
  await make().sync(); assert.equal(calls, 2); const good = store.value;
  time += modelsDevInterval;
  const broken = new ModelsDevRegistry(store, { clock: () => time, load: async () => { throw Error('network'); } });
  assert.deepEqual(await broken.sync(), good); assert.equal(store.writes, 1);
});
test('truncated updates and failed atomic writes leave the previous valid catalog available', async () => {
  const store = new Store(); store.value = parsed(now - modelsDevInterval);
  store.value.models.push(...store.value.models.map(m => ({ ...m, id: m.id + '-extra' })));
  assert.ok(validModelsDev(store.value)); const previous = structuredClone(store.value);
  const truncated = new ModelsDevRegistry(store, { clock: () => now, load: async () => parsed() });
  assert.deepEqual(await truncated.sync(), previous); assert.equal(store.writes, 0);
  store.state = null;
  store.writeModelsDev = async () => { throw Error('Write failed'); };
  const next = structuredClone(previous); next.fetchedAt = new Date(now).toISOString(); next.models[0].limit.context++;
  const unavailable = new ModelsDevRegistry(store, { clock: () => now, load: async () => next });
  assert.deepEqual(await unavailable.sync(), previous); assert.deepEqual(await unavailable.read(), previous);
});
test('new ranking models match saved catalog on reads without contacting upstream or changing ranking times', async () => {
  const store = new Store(); store.value = parsed(); let calls = 0;
  const registry = new ModelsDevRegistry(store, { load: async () => { calls++; return parsed(); } });
  const board = { kind: 'arenaText', fetchedAt: '2026-10-01T00:00:00Z', sourceUpdatedAt: '2026-09-30T00:00:00Z', entries: [{ rank: 1, name: 'Model 4', score: 123, openness: 'closed' }, { rank: 2, name: 'No match', score: 100 }] };
  const enriched = await registry.enrich(board); assert.equal(calls, 0); assert.equal(store.writes, 0);
  await registry.enrich(board, { acquire: true }); assert.equal(calls, 0);
  assert.equal(enriched.fetchedAt, board.fetchedAt); assert.equal(enriched.sourceUpdatedAt, board.sourceUpdatedAt);
  assert.equal(enriched.entries[0].rank, 1); assert.equal(enriched.entries[0].score, 123);
  assert.equal(enriched.entries[0].modelMetadata.id, 'lab/model-4'); assert.equal(resolvedOpenness(enriched.entries[0]), 'closed');
  assert.equal(resolvedOpenness({ modelMetadata: enriched.entries[0].modelMetadata }), 'open');
  assert.equal(enriched.entries[1].modelMetadata, undefined); assert.match(enriched.modelMetadataSource.license, /MIT License/);
});
test('sync endpoint authenticates bounded native timer payloads and never returns tokens', async t => {
  let calls = 0; const token = 'T'.repeat(43);
  const server = createServer(handler(() => ({ models: { sync: async () => { calls++; return parsed(); } } }), { syncToken: token }));
  server.listen(0, '127.0.0.1'); await once(server, 'listening'); t.after(() => { server.closeAllConnections(); server.close(); });
  const url = `http://127.0.0.1:${server.address().port}/invoke`;
  assert.equal((await fetch(url, { method: 'POST', body: '{}' })).status, 403); assert.equal(calls, 0);
  assert.equal((await fetch(url, { method: 'POST', body: 'null' })).status, 403); assert.equal(calls, 0);
  const r = await fetch(url, { method: 'POST', body: JSON.stringify({ triggerName: 'models-dev-sync', payload: JSON.stringify({ type: 'models-dev-sync', token }) }) });
  assert.equal(r.status, 200); const text = await r.text(); assert.ok(!text.includes(token)); assert.equal(calls, 1);
});
test('source download is fixed and bounded; collector rejects a stale or malformed response', async () => {
  const s = await loadModelsDev({ now, fetcher: async url => { assert.equal(url, 'https://models.dev/catalog.json?type=all'); return new Response(JSON.stringify(raw())); } });
  assert.ok(validModelsDev(s));
  await assert.rejects(loadModelsDev({ fetcher: async () => new Response('{}', { headers: { 'content-length': '999999999' } }) }));
  await assert.rejects(loadConfiguredModelsDev({ environment: { ARENA_COLLECTOR_ENDPOINT: 'https://evil.example' } }));
  const environment = { ARENA_COLLECTOR_ENDPOINT: 'https://collector.ap-southeast-1.fcapp.run', ARENA_COLLECTOR_TOKEN: 'T'.repeat(43) };
  assert.ok(validModelsDev(await loadConfiguredModelsDev({ now, environment, fetcher: async () => new Response(JSON.stringify(parsed())) })));
  for (const snapshot of [parsed(now - 7200000), parsed(now + 600000), { ...parsed(), license: 'MIT' }]) {
    await assert.rejects(loadConfiguredModelsDev({ now, environment, fetcher: async () => new Response(JSON.stringify(snapshot)) }));
  }
});

test('expanded facts survive publication; malformed or excessive public attributes cannot poison a snapshot', async () => {
  const r = raw()
  r.models['lab/model-0'].modalities = { input: ['text', 'image'], output: ['text'] }
  r.models['lab/model-0'].reasoning = false
  r.models['lab/model-0'].future = { count: 0, note: 'New fact' }
  r.providers['provider-0'].models['0'].reasoning_options = { effort: ['low', 'high'] }
  const s = parseModelsDev(r, { now, revision })
  assert.equal(s.schemaVersion, 2)
  assert.equal(s.models[0].attributes.reasoning, false)
  assert.deepEqual(s.models[0].attributes.future, { count: 0, note: 'New fact' })
  assert.deepEqual(s.models[0].offers[0].attributes.reasoning_options, { effort: ['low', 'high'] })
  assert.ok(validModelsDev(JSON.parse(JSON.stringify(s))))
  for (const value of [{ value: Infinity }, { value: 'x'.repeat(20000) }, JSON.parse('{"__proto__":{}}')]) {
    const invalid = structuredClone(s); invalid.models[0].attributes = value
    assert.equal(validModelsDev(invalid), false)
  }
  const store = new Store(); store.value = { ...parsed(), schemaVersion: 1 }
  let calls = 0
  await new ModelsDevRegistry(store, { clock: () => now, load: async () => { calls++; return s } }).sync()
  assert.equal(calls, 1); assert.equal(store.value.schemaVersion, 2)
})

const boardWith = (...entries) => ({ kind: 'arenaText', entries: entries.map(name => ({ name })) });
const pending = store => store.states.get('models-dev/requests')?.state.boards ?? {};
test('only real gaps queue work; false weights, free prices, absent optional facts and image token limits are valid', async () => {
  const store = new Store(); store.value = parsed();
  store.value.models[0].openWeights = false;
  store.value.models[0].offers[0].cost = { input: 0, output: 0 };
  let calls = 0;
  const registry = new ModelsDevRegistry(store, { clock: () => now, load: async () => { calls++; return parsed(); } });
  await registry.queue(boardWith('Model 0'));
  assert.deepEqual(pending(store), {});
  // No catalog read or origin acquisition is needed on an idle minute tick.
  store.readModelsDev = async () => { throw Error('Idle worker read catalog'); };
  assert.equal(await new ModelsDevRegistry(store).sync({ pendingOnly: true }), null);
  assert.equal(calls, 0);
  store.value.models[0].limit = {}; store.value.models[0].offers = [];
  for (const kind of ['arenaTextToImage', 'arenaTextToVideo', 'artificialAnalysisTextToImage', 'artificialAnalysisTextToVideo']) {
    await registry.queue({ ...boardWith('Model 0'), kind });
  }
  assert.deepEqual(pending(store), {});
  await registry.queue(boardWith('Model 0'));
  assert.equal(pending(store).arenaText.pending, true);
  await registry.queue({ ...boardWith('Model 0'), kind: 'not-a-board' });
  assert.deepEqual(Object.keys(pending(store)), ['arenaText']);
});
test('new gaps bypass catalog freshness, unresolved gaps are negatively cached and new identities can queue independently', async () => {
  const store = new Store(); store.value = parsed(); let time = now, calls = 0;
  const make = () => new ModelsDevRegistry(store, { clock: () => time, load: async () => { calls++; return parsed(time); } });
  await make().queue(boardWith('Not yet indexed'));
  await make().sync({ pendingOnly: true });
  assert.equal(calls, 1); assert.equal(store.writes, 0);
  assert.equal(pending(store).arenaText.pending, false);
  const revision = pending(store).arenaText.fingerprint;
  time += 16 * 60 * 1000;
  // A new score, rank or ranking timestamp does not change the missing identity.
  await make().queue({ ...boardWith('Not yet indexed'), fetchedAt: new Date(time).toISOString() });
  await make().sync({ pendingOnly: true }); assert.equal(calls, 1);
  await make().queue(boardWith('Different new identity'));
  assert.notEqual(pending(store).arenaText.fingerprint, revision);
  await make().sync({ pendingOnly: true }); assert.equal(calls, 2);
  time += 6 * 60 * 60 * 1000;
  await make().queue(boardWith('Different new identity'));
  assert.equal(pending(store).arenaText.pending, true);
  await make().queue(boardWith('Model 0')); assert.deepEqual(pending(store), {});
});
test('a valid fill is visible on the next read without changing ranks or either ranking timestamp', async () => {
  const store = new Store(); store.value = parsed(); let time = now, calls = 0;
  const board = { ...boardWith('New arrival'), fetchedAt: '2026-10-01T00:00:00Z', sourceUpdatedAt: '2026-09-30T00:00:00Z' };
  board.entries[0] = { ...board.entries[0], score: 77, rank: 3 };
  const registry = new ModelsDevRegistry(store, { clock: () => time, load: async () => {
    calls++; const next = parsed(time); next.models[0].name = 'New arrival'; return next;
  } });
  assert.equal((await registry.enrich(board)).entries[0].modelMetadata, undefined);
  await registry.queue(board); await registry.sync({ pendingOnly: true });
  const result = await registry.enrich(board);
  assert.equal(result.entries[0].modelMetadata.id, 'lab/model-0');
  assert.equal(result.entries[0].score, 77); assert.equal(result.entries[0].rank, 3);
  assert.equal(result.fetchedAt, board.fetchedAt); assert.equal(result.sourceUpdatedAt, board.sourceUpdatedAt);
  assert.equal(calls, 1); assert.equal(store.writes, 1);
});
test('unchanged facts preserve OSS bytes and acquisition time while separate successful checks prevent repeated downloads', async () => {
  const store = new Store(); store.value = parsed(now - modelsDevInterval); const original = store.value;
  let time = now, calls = 0;
  const make = () => new ModelsDevRegistry(store, { clock: () => time, load: async () => {
    calls++; const next = parsed(time); next.revision = 'b'.repeat(64);
    next.models.reverse(); next.models.forEach(record => record.offers.reverse());
    next.models[0].limit = Object.fromEntries(Object.entries(next.models[0].limit).reverse());
    return next;
  } });
  assert.equal(await make().sync(), original);
  assert.equal(store.value, original); assert.equal(store.writes, 0);
  assert.equal(store.state.state.checkedAt, now);
  time += 16 * 60 * 1000; await make().sync(); assert.equal(calls, 1);
  time = now + modelsDevInterval; await make().sync(); assert.equal(calls, 2); assert.equal(store.writes, 0);
});
test('periodic checks update populated prices, limits, licenses and public fields, reusing records that did not change', async () => {
  const store = new Store(); store.value = parsed(now - modelsDevInterval); const original = store.value;
  const registry = new ModelsDevRegistry(store, { clock: () => now, load: async () => {
    const next = parsed(); next.models[0].offers[0].cost.input = 9;
    next.models[0].license = 'MIT'; next.models[0].limit.context = 200000;
    next.models[0].attributes.newFact = true; return next;
  } });
  const next = await registry.sync(); assert.equal(store.writes, 1);
  assert.equal(next.models[0].offers[0].cost.input, 9); assert.equal(next.models[0].license, 'MIT');
  assert.equal(next.models[0].limit.context, 200000); assert.equal(next.models[0].attributes.newFact, true);
  assert.equal(next.models[1], original.models[1]); assert.notEqual(next.models[0], original.models[0]);
});
test('failed fills keep valid data and pending work; cross-instance cooldown permits one retry after fifteen minutes', async () => {
  const store = new Store(); store.value = parsed(); const original = store.value;
  let time = now, calls = 0, fail = true;
  const make = () => new ModelsDevRegistry(store, { clock: () => time, load: async () => {
    calls++; if (fail) throw Error('upstream unavailable'); return parsed(time);
  } });
  await make().queue(boardWith('Missing'));
  const failure = make(); assert.equal(await failure.sync({ pendingOnly: true }), original);
  assert.equal(failure.syncFailed, true); assert.equal(pending(store).arenaText.pending, true);
  for (let tick = 1; tick < 15; tick++) { time = now + tick * 60000; await make().sync({ pendingOnly: true }); }
  assert.equal(calls, 1); assert.equal(store.writes, 0);
  time = now + 15 * 60000; fail = false;
  await Promise.all(Array.from({ length: 100 }, () => make().sync({ pendingOnly: true })));
  assert.equal(calls, 2); assert.equal(store.writes, 0); assert.equal(pending(store).arenaText.pending, false);
});
test('queue CAS preserves simultaneous boards and gaps added during acquisition; coordination failures fail closed', async () => {
  const store = new Store(); store.value = parsed();
  const registry = new ModelsDevRegistry(store, { clock: () => now, load: async () => {
    await registry.queue(boardWith('A later identity')); return parsed();
  } });
  await Promise.all(Object.keys(sources).map(kind => registry.queue({ ...boardWith('Initial gap'), kind })));
  assert.equal(Object.keys(pending(store)).length, Object.keys(sources).length);
  assert.ok(Buffer.byteLength(JSON.stringify({ boards: pending(store) })) < 2048);
  await registry.sync({ pendingOnly: true });
  assert.equal(pending(store).arenaText.pending, true);
  assert.equal(pending(store).artificialAnalysis.pending, false);
  assert.equal(pending(store).epochECI.pending, false);
  store.readState = async () => { throw Error('Storage failure'); };
  await registry.queue(boardWith('No scheduling storage'));
  assert.equal(await registry.sync({ pendingOnly: true }), store.value);
  assert.equal(registry.syncFailed, true); assert.equal(store.writes, 0);
});
test('failed snapshot publication retains pending gaps, and removed upstream facts are not silently kept', async () => {
  const store = new Store(); store.value = parsed(); const original = store.value;
  const registry = new ModelsDevRegistry(store, { clock: () => now, load: async () => {
    const next = parsed(); delete next.models[0].license; return next;
  } });
  await registry.queue(boardWith('Missing'));
  const write = store.writeModelsDev.bind(store);
  store.writeModelsDev = async () => { throw Error('Write failed'); };
  assert.equal(await registry.sync({ pendingOnly: true }), original);
  assert.equal(pending(store).arenaText.pending, true); assert.equal(registry.syncFailed, true);
  store.writeModelsDev = write; store.state = null;
  const next = await registry.sync({ pendingOnly: true });
  assert.equal(next.models[0].license, undefined); assert.equal(original.models[0].license, 'Apache-2.0');
  assert.equal(store.writes, 1); assert.equal(pending(store).arenaText.pending, false);
});
test('catalog additions and removals compare by identity and preserve unchanged model records', async () => {
  const store = new Store(); store.value = parsed(now - modelsDevInterval); const original = store.value;
  const next = parsed(); next.models.shift(); next.models.push({ ...next.models[0], id: 'lab/new-model' });
  next.models.push({ ...next.models[0], id: 'lab/second-model' });
  const registry = new ModelsDevRegistry(store, { clock: () => now, load: async () => next });
  const result = await registry.sync();
  assert.equal(store.writes, 1); assert.equal(result.models.length, 101);
  assert.equal(result.models.find(record => record.id === 'lab/model-0'), undefined);
  assert.ok(result.models.some(record => record.id === 'lab/new-model'));
  assert.equal(result.models[0], original.models[1]);
});
test('Arena synthetic rank suffixes and row ordering do not invalidate the same missing identity', async () => {
  const store = new Store(); store.value = parsed(); let calls = 0;
  const registry = new ModelsDevRegistry(store, { clock: () => now, load: async () => { calls++; return parsed(); } });
  await registry.queue({ ...boardWith('Missing'), entries: [{ name: 'Missing', modelID: 'unknown#arena-rank-1' }] });
  await registry.sync({ pendingOnly: true });
  await registry.queue({ ...boardWith('Missing'), entries: [{ name: 'Missing', modelID: 'unknown#arena-rank-7' }] });
  await registry.sync({ pendingOnly: true }); assert.equal(calls, 1);
  assert.equal(pending(store).arenaText.pending, false);
});
test('idle fill events are authenticated and succeed without a snapshot; old unchanged catalogs use the separate check timestamp', async t => {
  const store = new Store(); store.value = parsed(now - modelsDevInterval * 2);
  const registry = new ModelsDevRegistry(store, { clock: () => now, load: async () => parsed() });
  const token = 'T'.repeat(43);
  const server = createServer(handler(() => ({ models: registry }), { syncToken: token }));
  server.listen(0, '127.0.0.1'); await once(server, 'listening'); t.after(() => { server.closeAllConnections(); server.close(); });
  const invoke = type => fetch(`http://127.0.0.1:${server.address().port}/invoke`, { method: 'POST', body: JSON.stringify({ type, token }) });
  assert.equal((await invoke('models-dev-fill')).status, 200);
  const response = await invoke('models-dev-sync'); assert.equal(response.status, 200);
  const body = await response.json(); assert.equal(body.checkedAt, new Date(now).toISOString());
  assert.equal(body.fetchedAt, store.value.fetchedAt); assert.equal(store.writes, 0);
  assert.equal((await invoke('other-job')).status, 403);
});
