import assert from 'node:assert/strict';
import test from 'node:test';
import { CountryRegistry, countryCode, countryRetryInterval, discoverCountry } from '../fc/countries.mjs';
import { SharedLeaderboards } from '../fc/service.mjs';
import { parseBoard } from '../fc/parser.mjs';
import { OSSStore } from '../fc/oss-store.mjs';
class Store {
  records = new Map(); states = new Map(); board;
  async readCountry(key) { return this.records.get(key); }
  async writeCountry(key, record) { this.records.set(key, record); }
  async readBoard() { return this.board; }
  async writeBoard(_, board) { this.board = board; }
  async readState(key) { return this.states.get(key) ?? { position: 0 }; }
  async appendState(key, position, state) {
    if ((this.states.get(key)?.position ?? 0) !== position) return false;
    this.states.set(key, { position: position + 1, state }); return true;
  }
}
const board = (organization = 'New Maker') => ({ kind: 'arenaTextToVideo', fetchedAt: '2026-10-13T00:00:00Z', entries: [1, 2].map(rank => ({ rank, score: 100 - rank, name: `Future Video ${rank}`, organization })) });
test('verified currently missing video developers and aliases work on cached reads without network', async () => {
  let calls = 0; const registry = new CountryRegistry(new Store(), { discover: async () => { calls++; } });
  for (const [name, code] of [['Utopai Studios','US'],['Skywork AI','SG'],['Sapiens AI','SG'],['Alibaba','CN'],['Moonshot AI','CN']]) {
    const result = await registry.enrich(board(name));
    assert.equal(result.entries[0].developerCountry.countryCode, code);
    assert.equal(result.fetchedAt, board(name).fetchedAt);
  }
  assert.equal(calls, 0);
});
test('MAGI developer country corrects failed discovery on cached reads without changing leaderboard data', async () => {
  const store = new Store(); let calls = 0;
  store.records.set('sandai', { key: 'sandai', status: 'failed', nextAttemptAt: Date.now() + countryRetryInterval });
  const registry = new CountryRegistry(store, { discover: async () => { calls++; throw Error('must not discover'); } });
  for (const organization of ['Sand.ai', 'Sand AI', 'SANDAI']) {
    const value = board(organization);
    value.entries[0].name = 'MAGI-2 Preview (0912)';
    value.entries.forEach(entry => { entry.developerCountry = store.records.get('sandai'); });
    const result = await registry.enrich(value);
    assert.equal(result.entries[0].developerCountry.key, 'sandai');
    assert.equal(result.entries[0].developerCountry.countryCode, 'CN');
    assert.equal(result.entries[0].developerCountry.status, 'ready');
    assert.equal(result.fetchedAt, value.fetchedAt);
    assert.deepEqual(result.entries.map(({ developerCountry, ...entry }) => entry),
      value.entries.map(({ developerCountry, ...entry }) => entry));
  }
  assert.equal(calls, 0);
});
test('concurrent cold workers acquire once per developer, new models reuse shared countries, reads never discover', async () => {
  const store = new Store(); let calls = 0;
  const registry = () => new CountryRegistry(store, { discover: async () => { calls++; return { countryCode: 'JP', sourceURL: 'https://www.wikidata.org/wiki/Q123' }; } });
  await Promise.all(Array.from({ length: 8 }, () => registry().enrich(board(), { acquire: true })));
  assert.equal(calls, 1); assert.equal(store.records.size, 1);
  const result = await registry().enrich(board('New-Maker'), { acquire: true });
  assert.equal(result.entries[1].developerCountry.countryCode, 'JP'); assert.equal(calls, 1);
  await registry().enrich(board('Other Maker')); assert.equal(calls, 1);
  store.readCountry = async () => { throw Error('offline'); };
  assert.deepEqual((await registry().enrich(result)).entries, result.entries);
});
test('failed or ambiguous discovery leaves country unknown, preserves scores, retries after thirty minutes', async () => {
  const store = new Store(); let now = 0, calls = 0;
  const registry = new CountryRegistry(store, { clock: () => now, discover: async () => { if (++calls === 1) throw Error('offline'); return { countryCode: 'GB' }; } });
  const result = await registry.enrich(board(), { acquire: true });
  assert.equal(result.entries[0].developerCountry.status, 'failed');
  assert.equal(result.entries[0].developerCountry.countryCode, undefined);
  assert.deepEqual(result.entries.map(({ developerCountry, ...entry }) => entry), board().entries);
  await registry.enrich(board(), { acquire: true }); assert.equal(calls, 1);
  now += countryRetryInterval;
  assert.equal((await registry.enrich(board(), { acquire: true })).entries[0].developerCountry.countryCode, 'GB');
  assert.equal(calls, 2);
});
test('source country metadata is validated, shared, and cannot assign a coding harness country to its lead model', async () => {
  const store = new Store(); let calls = 0;
  const registry = new CountryRegistry(store, { discover: async () => { calls++; return { countryCode: 'ZZ' }; } });
  const value = board(); value.entries.forEach(entry => { entry.countryHint = { key: 'newmaker', countryCode: 'KR' }; });
  assert.equal((await registry.enrich(value, { acquire: true })).entries[0].developerCountry.countryCode, 'KR');
  assert.equal((await registry.enrich(board())).entries[0].developerCountry.countryCode, 'KR'); assert.equal(calls, 0);
  const harness = board('Opencode'); harness.entries.forEach(entry => { entry.name = 'Opencode - GPT-9'; entry.countryHint = { key: 'opencode', countryCode: 'CN' }; });
  assert.equal((await registry.enrich(harness, { acquire: true })).entries[0].developerCountry.countryCode, 'US');
  for (const value of ['ZZ','EU','UN','AAA','',null,'China']) assert.equal(countryCode(value), null);
});
const claim = (value, other = {}) => ({ rank: 'normal', mainsnak: { snaktype: 'value', datavalue: { value } }, ...other });
const entity = (id, label, claims = {}) => ({ id, labels: { en: { value: label } }, claims });
const jsonFetcher = data => async url => new Response(JSON.stringify(url.includes('wbsearchentities') ? { search: data.hits ?? [{ id: 'Q1' }] }
  : { entities: { [url.match(/(Q\d+)\.json/)[1]]: data[url.match(/(Q\d+)\.json/)[1]] } }), { status: 200, headers: { 'Content-Type': 'application/json' } });
const data = () => ({ Q1: entity('Q1','New Maker',{ P856: [claim('https://newmaker.example')], P159: [claim({ id: 'Q2' })] }),
  Q2: entity('Q2','Tokyo',{ P17: [claim({ id: 'Q3' })] }), Q3: entity('Q3','Japan',{ P297: [claim('JP')] }) });
test('automatic discovery follows exact entity identity to current headquarters, country, and ISO code', async () => {
  const records = data(); records.Q1.claims.P159.push(claim({ id: 'Q4' }, { qualifiers: { P582: [{}] } }));
  const result = await discoverCountry({ organization: 'New Maker', organizationWebsite: 'https://www.newmaker.example/about' }, { fetcher: jsonFetcher(records) });
  assert.deepEqual(result, { status: 'ready', countryCode: 'JP', source: 'wikidata', sourceURL: 'https://www.wikidata.org/wiki/Q1' });
  assert.equal((await discoverCountry({ organization: 'New Maker', organizationWebsite: 'https://unrelated.example' }, { fetcher: jsonFetcher(records) })).status, 'missing');
});
test('same-named developers and conflicting current HQ countries are ambiguous, never guessed', async () => {
  const records = data(); records.hits = [{ id: 'Q1' }, { id: 'Q4' }]; records.Q4 = entity('Q4','New Maker',{ P856: [claim('https://other.example')], P159: [claim({ id: 'Q2' })] });
  assert.equal((await discoverCountry({ organization: 'New Maker' }, { fetcher: jsonFetcher(records) })).status, 'ambiguous');
  records.hits = [{ id: 'Q1' }]; records.Q1.claims.P159.push(claim({ id: 'Q5' }));
  records.Q5 = entity('Q5','Other HQ',{ P17: [claim({ id: 'Q6' })] }); records.Q6 = entity('Q6','Britain',{ P297: [claim('GB')] });
  assert.equal((await discoverCountry({ organization: 'New Maker' }, { fetcher: jsonFetcher(records) })).status, 'ambiguous');
  records.Q1.claims.P31 = [claim({ id: 'Q5' })];
  assert.equal((await discoverCountry({ organization: 'New Maker' }, { fetcher: jsonFetcher(records) })).status, 'missing');
});
test('missing HQ, arbitrary source websites and failed endpoints cannot fabricate countries or access source homepages', async () => {
  const records = data(); delete records.Q1.claims.P159; const urls = [];
  const result = await discoverCountry({ organization: 'New Maker', organizationWebsite: 'https://127.0.0.1/private' }, { fetcher: async (url, options) => { urls.push(url); return jsonFetcher(records)(url, options); } });
  assert.equal(result.status, 'missing'); assert.ok(urls.every(url => new URL(url).hostname === 'www.wikidata.org'));
  await assert.rejects(discoverCountry({ organization: 'New Maker' }, { fetcher: async () => new Response('offline', { status: 429 }) }));
  await assert.rejects(discoverCountry({ organization: 'New Maker' }, { fetcher: async () => new Response('x'.repeat(1024 * 1024 + 1)) }));
});
test('source parser reads developer ISO metadata separately from logos and scores', () => {
  const values = Array.from({ length: 20 }, (_, index) => ({ formatted: {}, values: { id: `v${index}`, name: `Video ${index}`, elo: 100 - index,
    creator: { name: 'New Maker', countryCode: 'GB', website: 'https://newmaker.example' } } }));
  const html = `self.__next_f.push([1,${JSON.stringify(JSON.stringify(values))}])`;
  const result = parseBoard('artificialAnalysisTextToVideo', html, 0);
  assert.equal(result.entries[0].countryHint.countryCode, 'GB'); assert.equal(result.entries[0].countryHint.key, 'newmaker');
});
test('shared refresh discovers countries even when the source refresh grant is throttled', async () => {
  const store = new Store(); store.board = board(); let calls = 0;
  store.states.set('arenaTextToVideo', { position: 1, state: { nextAttemptAt: Date.now() + 100000 } });
  const countries = new CountryRegistry(store, { discover: async () => { calls++; return { countryCode: 'JP' }; } });
  const service = new SharedLeaderboards(store, { countries });
  assert.equal((await service.read('arenaTextToVideo')).board.entries[0].developerCountry.status, 'pending'); assert.equal(calls, 0);
  assert.equal((await service.refresh('arenaTextToVideo')).board.entries[0].developerCountry.countryCode, 'JP'); assert.equal(calls, 1);
  assert.equal((await service.read('arenaTextToVideo')).board.entries[0].developerCountry.countryCode, 'JP');
});
test('OSS country records are private shared JSON, missing objects are harmless and real errors propagate', async () => {
  const calls = []; const store = new OSSStore({ get: async key => { calls.push(key); return { content: Buffer.from('{"countryCode":"JP"}') }; }, put: async (...args) => calls.push(args) });
  assert.equal((await store.readCountry('new maker')).countryCode, 'JP'); await store.writeCountry('new maker', { countryCode: 'JP' });
  assert.equal(calls[0], 'benchgauge/countries/new%20maker.json'); assert.equal(calls[1][2].headers['Content-Type'], 'application/json');
  store.client.get = async () => { throw { code: 'NoSuchKey' }; }; assert.equal(await store.readCountry('missing'), null);
  store.client.get = async () => { throw Error('denied'); }; await assert.rejects(store.readCountry('missing'));
});

test('partial sibling metadata is reused and a discovery time budget preserves remaining saved countries', async () => {
  const store = new Store(); let calls = 0;
  const registry = new CountryRegistry(store, { budget: 5, discover: async (_, { signal }) => { calls++; await new Promise(resolve => { const timer = setTimeout(resolve, 10); signal.addEventListener('abort', () => { clearTimeout(timer); resolve(); }, { once: true }); }); throw Error('timeout'); } });
  const partial = board(); partial.entries[0].countryHint = { key: 'newmaker', countryCode: 'JP' };
  assert.equal((await registry.enrich(partial, { acquire: true })).entries[1].developerCountry.countryCode, 'JP');
  const slow = board('Timeout Maker');
  slow.entries.push({ rank: 3, score: 90, name: 'Future', organization: 'Saved Maker', developerCountry: { key: 'savedmaker', countryCode: 'GB' } });
  const result = await registry.enrich(slow, { acquire: true });
  assert.equal(calls, 1); assert.equal(result.entries[2].developerCountry.countryCode, 'GB');
});
