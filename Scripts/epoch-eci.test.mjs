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
