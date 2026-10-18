import assert from 'node:assert/strict';
import test from 'node:test';
import { parseBoard, sources } from '../fc/parser.mjs';

const header = 'Model,Display name,eci,Organization,Country (of organization),Accessibility group,date,model_versions';
const record = (i, changes = {}) => ({ Model: `model-${i}`, 'Display name': `Model ${i}`, eci: String(170 - i / 3),
  Organization: 'Maker', 'Country (of organization)': 'United States of America', 'Accessibility group': 'Closed weights',
  date: '2099-01-01', model_versions: '["a","b"]', ...changes });
const quote = value => /[",\r\n]/.test(value) ? `"${value.replaceAll('"', '""')}"` : value;
const csv = (changes = {}, count = 22) => header + '\r\n' + Array.from({ length: count }, (_, i) =>
  Object.values(record(i, i === 0 ? changes : {})).map(quote).join(',')).join('\r\n') + '\r\n';
const now = Date.parse('2026-10-18T00:00:00Z');

test('official CSV preserves unbounded ECI scores, attribution, CSV quoting, country and openness', () => {
  const source = '\uFEFF' + csv({ 'Display name': '模型, "Alpha"', eci: '166.82', 'Accessibility group': 'Open weights',
    'Country (of organization)': 'Hong Kong', model_versions: 'a\nb' });
  const board = parseBoard('epochECI', source, now);
  assert.equal(sources.epochECI[0], 'https://epoch.ai/data/eci_scores.csv');
  assert.equal(board.sourceUpdatedAt, undefined); // release date is not the source update
  assert.equal(board.fetchedAt, new Date(now).toISOString());
  assert.equal(board.entries.length, 22);
  const entry = board.entries.find(row => row.modelID === 'model-0');
  assert.equal(entry.name, '模型, "Alpha"'); assert.equal(entry.score, 166.82);
  assert.equal(entry.countryHint.countryCode, 'CN'); assert.equal(entry.openness, 'open');
  assert.ok(board.entries.every((row, i) => row.rank === i + 1));
  assert.match(board.sourceNote, /Epoch AI/);
  const unknown = parseBoard('epochECI', csv({ 'Display name': '', 'Accessibility group': 'Other', 'Country (of organization)': 'Unknown' }), now);
  assert.equal(unknown.entries[0].name, 'model-0'); assert.equal(unknown.entries[0].openness, undefined);
  assert.equal(unknown.entries[0].countryHint, undefined);
  assert.equal(parseBoard('epochECI', csv({ 'Country (of organization)': 'GB' }), now).entries[0].countryHint.countryCode, 'GB');
});

test('malformed, duplicate, invalid-score and partial CSV cannot replace a shared snapshot', () => {
  for (const source of ['<html>Blocked</html>', '', csv({}, 19), csv({ eci: '' }), csv({ eci: 'NaN' }),
    csv({ eci: 'Infinity' }), csv({ eci: '100001' }), csv({ Model: 'model-1' }), csv({ Model: '' }),
    csv({ Organization: 'Bad\nOrganization' }), csv().replace('Model,Display name', 'Model,Model'),
    csv() + '"unclosed', csv() + 'a,b', csv().replace('model-0', 'model-"0'),
    csv().replace('model-0', '"model-0"bad')]) assert.throws(() => parseBoard('epochECI', source, now));
});

test('Epoch contributions use the same source-bound shared grant and persist an independently parsed snapshot', async () => {
  const { SharedLeaderboards } = await import('../fc/service.mjs');
  const { handler } = await import('../fc/server.mjs');
  const { createServer } = await import('node:http');
  const { once } = await import('node:events');
  let state = { position: 0, state: null }, board;
  const store = {
    async readState() { return state; },
    async appendState(kind, position, value) {
      if (position !== state.position) return false;
      state = { position: position + 1, state: value }; return true;
    },
    async readBoard() { return board ?? null; },
    async writeBoard(kind, value) { board = value; },
  };
  const service = new SharedLeaderboards(store, { clock: () => now });
  const server = createServer(handler(() => service)); server.listen(0, '127.0.0.1'); await once(server, 'listening');
  try {
    const url = `http://127.0.0.1:${server.address().port}/v1/boards/epochECI`;
    const { grant } = await (await fetch(url + '/refresh', { method: 'POST' })).json();
    assert.equal(grant.sourceURL, sources.epochECI[0]);
    const headers = { 'Content-Type': 'text/csv; charset=utf-8', 'X-BenchGauge-Grant': grant.token };
    const response = await fetch(url + '/contribute', { method: 'POST', headers, body: csv() });
    assert.equal(response.status, 200);
    assert.equal((await response.json()).board.entries.length, 22);
    assert.equal((await (await fetch(url)).json()).board.sourceUpdatedAt, undefined);
    assert.equal((await fetch(url + '/contribute', { method: 'POST', headers, body: csv() })).status, 403);
    assert.equal((await fetch(url + '/contribute', { method: 'POST', headers: { ...headers, 'Content-Type': 'text/html' }, body: csv() })).status, 415);
  } finally { await new Promise(resolve => server.close(resolve)); }
});

test('ECI aliases, missing developers and exact openness repair existing shared snapshots without changing rankings', async () => {
  const { BrandRegistry, validPNG, brandKey } = await import('../fc/brands.mjs');
  const { CountryRegistry } = await import('../fc/countries.mjs');
  const { SharedLeaderboards } = await import('../fc/service.mjs');
  const { readFileSync } = await import('node:fs');
  const catalog = JSON.parse(readFileSync(new URL('../fc/brand-catalog.json', import.meta.url)));
  const cases = [
    ['Gemini example', 'Google DeepMind', 'google', 'US'],
    ['Gemini example', 'Google DeepMind,Google', 'google', 'US'],
    ['Muse example', 'Meta AI', 'meta', 'US'],
    ['Mistral example', 'Mistral AI', 'mistral', 'FR'],
    ['GLM example', 'Z.ai (Zhipu AI)', 'zai', 'CN'],
    ['Phi example', 'Microsoft Research', 'microsoftai', 'US'],
    ['Command R+', 'Cohere,Cohere Labs (formerly Cohere for AI)', 'cohere', 'CA'],
    ['Qwen2.5-Coder-14B', undefined, 'qwen', 'CN', 'open'],
    ['DeepSeek-Coder-V2-Lite-Base', undefined, 'deepseek', 'CN', 'open'],
    ['internlm-20b', undefined, 'shanghaiailaboratory', 'CN', 'open'],
    ['Yi-9B', undefined, '01ai', 'CN', 'open'],
    ['PaLM 2-L', undefined, 'google', 'US', 'closed'],
    ['RedPajama-INCITE-7B-Base', undefined, 'togetherai', 'US', 'open'],
    ['open_llama_7b', undefined, 'openlmresearch', undefined, 'open'],
    ['Baichuan2-13B', 'Baichuan', 'baichuan', 'CN', 'open'],
    ['StarCoder 2 15B', 'Hugging Face,ServiceNow,Nvidia,BigCode', 'huggingfaceservicenownvidiabigcode', 'US', 'open'],
  ];
  const entries = cases.map(([name, organization, key, code], i) => ({ rank: i + 1, name, modelID: name, organization,
    score: 171.234 - i, ...(organization && { countryHint: { key: organization.toLowerCase().replace(/[^\p{L}\p{N}]/gu, ''), countryCode: code } }),
    brand: { key, status: 'missing' }, ...(i >= 14 && { openness: 'open' }) }));
  const input = { kind: 'epochECI', fetchedAt: '2026-10-18T00:00:00Z', entries };
  let downloads = 0, writes = 0;
  const store = { async readBoard() { return input; }, async readBrand() { throw Error('OSS unavailable'); },
    async readCountry() { return null; }, async writeBoard() { writes++; } };
  const brands = new BrandRegistry(store, { download: async () => { downloads++; throw Error('offline'); } });
  const service = new SharedLeaderboards(store, { brands, countries: new CountryRegistry(store) });
  const { board } = await service.read('epochECI');
  assert.equal(downloads, 0); assert.equal(writes, 0);
  assert.equal(board.fetchedAt, input.fetchedAt);
  for (const [i, [, , key, country, openness]] of cases.entries()) {
    const entry = board.entries[i];
    assert.equal(brandKey(entry), key);
    assert.equal((entry.organizationBrand ?? entry.brand).key, key);
    assert.ok(validPNG(Buffer.from(entry.brand.pngData, 'base64')), entry.name);
    assert.equal(entry.developerCountry.countryCode, country, entry.name);
    assert.equal(entry.openness, openness, entry.name);
    assert.equal(entry.rank, entries[i].rank); assert.equal(entry.score, entries[i].score); assert.equal(entry.modelID, entries[i].modelID);
  }
  for (const [key, logo] of Object.entries(catalog.providerLogos)) {
    assert.ok(validPNG(Buffer.from(logo.pngData, 'base64')), key);
    assert.equal(new URL(logo.sourceURL).protocol, 'https:');
    assert.equal(new URL(logo.referenceURL).protocol, 'https:');
  }
});

test('ECI repairs never guess a neighboring variant, replace explicit openness, or claim a community country', async () => {
  const { SharedLeaderboards } = await import('../fc/service.mjs');
  const { brandKey } = await import('../fc/brands.mjs');
  const entries = [
    { modelID: 'Qwen2.5-Coder-14B', name: 'Qwen2.5-Coder-14B', openness: 'closed' },
    { modelID: 'Qwen2.5-Coder-14B-preview', name: 'Qwen2.5-Coder-14B-preview' },
    { modelID: 'unknown', name: 'Qwen mysterious model' },
    { modelID: 'Yi-9B', name: 'Yi-9B', organization: 'Another developer' },
    { modelID: 'Gemini 4 Argon', name: 'Gemini 4 Argon', organization: 'Google DeepMind' },
  ];
  const service = new SharedLeaderboards({ async readBoard() { return { kind: 'epochECI', entries }; } });
  const { board } = await service.read('epochECI');
  assert.equal(board.entries[0].openness, 'closed');
  assert.equal(board.entries[1].openness, undefined); assert.equal(brandKey(board.entries[1]), null);
  assert.equal(board.entries[2].openness, undefined); assert.equal(brandKey(board.entries[2]), null);
  assert.equal(brandKey(board.entries[3]), 'anotherdeveloper');
  assert.equal(board.entries[4].openness, undefined);
});
