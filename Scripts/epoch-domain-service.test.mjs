import test from 'node:test';
import assert from 'node:assert/strict';
import { SharedLeaderboards, refreshInterval } from '../fc/service.mjs';
import { loadEpochDomain } from '../fc/epoch-domain-loader.mjs';

class MemoryStore {
  boards = new Map(); states = new Map();
  async readBoard(kind) { return this.boards.get(kind) ?? null; }
  async writeBoard(kind, board) { this.boards.set(kind, board); }
  async readState(kind) { return this.states.get(kind) ?? { position: 0, state: null }; }
  async appendState(kind, position, state) {
    if ((this.states.get(kind)?.position ?? 0) !== position) return false;
    this.states.set(kind, { position: position + 1, state }); return true;
  }
}
const now = Date.parse('2026-10-31T00:00:00Z');
test('Epoch domain refresh persists once, shares cooldown and retains cache on failure', async () => {
  const store = new MemoryStore(); let time = now, calls = 0, fail = false;
  const service = new SharedLeaderboards(store, { clock: () => time, epochDomain: async kind => {
    calls++; if (fail) throw Error('offline');
    return { kind, title: 'Test', fetchedAt: new Date(time).toISOString(), entries: [{ rank: 1, name: 'Model', score: 150 }] };
  } });
  const first = await service.refresh('epochMathECI');
  assert.equal(first.board.entries[0].score, 150);
  assert.equal((await service.read('epochMathECI')).board.entries[0].score, 150);
  await service.refresh('epochMathECI'); assert.equal(calls, 1);
  await assert.rejects(service.contribute('epochMathECI', '', ''), e => e.status === 403);
  time += refreshInterval; fail = true;
  assert.equal((await service.refresh('epochMathECI')).board.entries[0].score, 150);
  assert.equal(calls, 2);
});

test('loader requests only fixed official sources and refuses invalid input', async () => {
  const seen = [];
  const fetcher = async url => { seen.push(url); return new Response('not a csv', { status: 200 }); };
  await assert.rejects(loadEpochDomain('epochCyberECI', { fetcher }), /header/);
  assert.deepEqual(seen.sort(), ['https://epoch.ai/data/cyber/eci_scores.csv', 'https://epoch.ai/data/cyber/edi_scores.csv', 'https://epoch.ai/data/cyber/processed_data_for_eci.csv'].sort());
  await assert.rejects(loadEpochDomain('epochOther', { fetcher }), /Unknown/);
});


test('loader recovers transient transport and origin failures within one acquisition', async () => {
  const count = new Map();
  const a = 1 / (1 + Math.exp(-1)), b = 1 / (1 + Math.exp(1));
  const files = {
    'eci_scores.csv': 'Model,Display name,eci,Organization\n' + Array.from({ length: 20 }, (_, i) => `m${i},Model ${i},140,Maker`).join('\n'),
    'processed_data_for_eci.csv': 'model_group,benchmark,performance\n' + Array.from({ length: 20 }, (_, i) => `m${i},a,${a}\nm${i},b,${b}`).join('\n'),
    'edi_scores.csv': 'benchmark_name,edi,estimated_slope_scaled\na,130,0.1\nb,150,0.1',
  };
  const board = await loadEpochDomain('epochCyberECI', { fetcher: async url => {
    const name = url.split('/').at(-1), attempt = (count.get(name) ?? 0) + 1;
    count.set(name, attempt);
    if (attempt === 1 && name === 'eci_scores.csv') throw new TypeError('fetch failed');
    if (attempt === 1 && name === 'edi_scores.csv') return new Response('', { status: 503 });
    return new Response(files[name]);
  } });
  assert.equal(board.entries.length, 20);
  assert.equal(board.entries[0].score, 140);
  assert.deepEqual(Object.fromEntries(count), { 'eci_scores.csv': 2, 'processed_data_for_eci.csv': 1, 'edi_scores.csv': 2 });
  const permanent = [];
  await assert.rejects(loadEpochDomain('epochCyberECI', { fetcher: async url => { permanent.push(url); return new Response('', { status: 403 }); } }), /unavailable/);
  assert.equal(permanent.length, 3, 'Permanent failures must not retry any source file');
});

test('loader bounds rate-limit, server and transport retries without publishing invalid data', { timeout: 10_000 }, async () => {
  for (const status of [408, 429, 502, null]) {
    let calls = 0, releaseFinalAttempts;
    const attempts = new Map();
    const finalAttempts = new Set();
    const allFinalAttempts = new Promise(resolve => { releaseFinalAttempts = resolve; });
    await assert.rejects(loadEpochDomain('epochCyberECI', { fetcher: async url => {
      calls++;
      const name = url.split('/').at(-1), attempt = (attempts.get(name) ?? 0) + 1;
      attempts.set(name, attempt);
      if (attempt === 3) {
        finalAttempts.add(name);
        if (finalAttempts.size === 3) releaseFinalAttempts();
        // Promise.all rejects on the first failure, without waiting for siblings.
        // Hold final failures until every file has reached its last attempt.
        await allFinalAttempts;
      }
      if (status === null) throw new TypeError('offline');
      return new Response('', { status });
    } }));
    assert.equal(calls, 9, 'Each of the three fixed files has at most three attempts');
    assert.deepEqual(Object.fromEntries(attempts), { 'eci_scores.csv': 3, 'processed_data_for_eci.csv': 3, 'edi_scores.csv': 3 });
  }
});
