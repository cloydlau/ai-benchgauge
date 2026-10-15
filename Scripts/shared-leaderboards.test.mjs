import assert from 'node:assert/strict';
import test from 'node:test';
import { createServer } from 'node:http';
import { once } from 'node:events';
import { readFileSync } from 'node:fs';
import { SharedLeaderboards, refreshInterval, grantLifetime } from '../fc/service.mjs';
import { parseBoard, sources, modelOpenness } from '../fc/parser.mjs';
import { OSSStore } from '../fc/oss-store.mjs';
import { handler, storageConfiguration } from '../fc/server.mjs';
import { deploymentConfiguration, existingRuntimeCredentials, checkExistingBucket } from './deploy-shared-leaderboards.mjs';

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
const time = Date.parse('2026-10-12T00:00:00Z');
function html(kind = 'arenaText', date = '2026-10-10T00:00:00Z', count = 22, modelLogoURL = undefined) {
  const rows = Array.from({ length: count }, (_, i) => {
    if (kind.startsWith('arena') || kind === 'codeArenaWebDev') return { modelDisplayName: `Model ${i}`, rating: 2000 - i, modelKey: `model-${i}`, modelOrganization: 'Maker' };
    if (kind === 'artificialAnalysisCodingAgent') return { displayLabel: `Model ${i}`, indexScore: (100 - i) / 100, display: { creator: { agent: 'Maker' } }, hostModelSlug: `model-${i}`, materializedAt: date };
    const value = { ...(modelLogoURL && { modelLogoURL }), name: `Model ${i}`, intelligenceIndex: 100 - i, elo: 1200 - i, slug: `model-${i}`, id: `model-${i}`, creator: { name: 'Maker', logo: '/img/logos/maker.svg' } };
    return kind === 'artificialAnalysis' ? value : { formatted: { rank: i + 1 }, values: value };
  });
  return `<title>Artificial Analysis Intelligence Index v4.3.2</title><script>self.__next_f.push([1,${JSON.stringify(JSON.stringify({ entries: rows, voteCutoffISOString: date }))}])</script>`;
}

test('one grant across 100 concurrent cold FC instances; denied requests do not extend cooldown', async () => {
  const store = new MemoryStore();
  let now = time;
  const responses = await Promise.all(Array.from({ length: 100 }, () => new SharedLeaderboards(store, { clock: () => now }).refresh('arenaText')));
  assert.equal(responses.filter(r => r.grant).length, 1);
  now += refreshInterval;
  assert.equal((await new SharedLeaderboards(store, { clock: () => now }).refresh('arenaText')).grant, undefined);
  now += grantLifetime;
  assert.ok((await new SharedLeaderboards(store, { clock: () => now }).refresh('arenaText')).grant);
});

test('snapshots remain readable after months and cold restart; cache reads preserve timestamps', async () => {
  const store = new MemoryStore(), board = parseBoard('arenaText', html(), time);
  await store.writeBoard('arenaText', board);
  const service = new SharedLeaderboards(store, { clock: () => time + 90 * 86400000 });
  assert.deepEqual((await service.read('arenaText')).board, board);
  assert.deepEqual((await service.refresh('arenaText')).board, board);
});

test('failed coordination serves stale data and never authorizes an origin request', async () => {
  const store = new MemoryStore(), board = parseBoard('arenaText', html(), time);
  await store.writeBoard('arenaText', board);
  store.readState = async () => { throw new Error('OSS unavailable'); };
  const service = new SharedLeaderboards(store);
  assert.deepEqual(await service.refresh('arenaText'), { board });
  await assert.rejects(service.refresh('artificialAnalysis'), e => e.status === 503);
});

test('source failure consumes the update window but preserves the existing snapshot', async () => {
  const store = new MemoryStore(), service = new SharedLeaderboards(store, { clock: () => time });
  const board = parseBoard('arenaText', html(), time - 86400000);
  await store.writeBoard('arenaText', board);
  const { grant } = await service.refresh('arenaText');
  await assert.rejects(service.contribute('arenaText', grant.token, '<html>Blocked</html>'), e => e.status === 422);
  assert.deepEqual((await service.refresh('arenaText')).board, board);
  assert.equal((await service.refresh('arenaText')).grant, undefined);
});

test('only one concurrent contribution can publish and the token cannot be replayed', async () => {
  const store = new MemoryStore(), service = new SharedLeaderboards(store, { clock: () => time });
  const { grant } = await service.refresh('arenaText');
  const results = await Promise.allSettled(Array.from({ length: 25 }, () => service.contribute('arenaText', grant.token, html())));
  assert.equal(results.filter(r => r.status === 'fulfilled').length, 1);
  assert.equal((await service.read('arenaText')).board.entries.length, 22);
  await assert.rejects(service.contribute('arenaText', grant.token, html()), e => e.status === 403);
});

test('tokens are source-bound, expire, and remain unusable for arbitrary tables', async () => {
  const store = new MemoryStore(); let now = time;
  const service = new SharedLeaderboards(store, { clock: () => now });
  const { grant } = await service.refresh('arenaText');
  await assert.rejects(service.contribute('arenaTextToImage', grant.token, html('arenaTextToImage')), e => e.status === 403);
  await assert.rejects(service.contribute('arenaText', 'A'.repeat(43), html()), e => e.status === 403);
  now += grantLifetime;
  await assert.rejects(service.contribute('arenaText', grant.token, html()), e => e.status === 403);
  await assert.rejects(service.read('__proto__'), e => e.status === 404);
});

test('older or future source dates and failed writes cannot erase a good snapshot', async () => {
  const store = new MemoryStore(), service = new SharedLeaderboards(store, { clock: () => time });
  const previous = parseBoard('arenaText', html(), time - 1000);
  await store.writeBoard('arenaText', previous);
  const { grant } = await service.refresh('arenaText');
  await assert.rejects(service.contribute('arenaText', grant.token, html('arenaText', '2026-10-09T00:00:00Z')), e => e.status === 409);
  await assert.rejects(service.contribute('arenaText', grant.token, html('arenaText', '2026-11-01T00:00:00Z')), e => e.status === 422);
  store.writeBoard = async () => { throw new Error('write interrupted'); };
  await assert.rejects(service.contribute('arenaText', grant.token, html()));
  assert.deepEqual((await service.read('arenaText')).board, previous);
});

test('all eight sources retain ranking, IDs, organizations and correct source date semantics', () => {
  for (const kind of Object.keys(sources)) {
    const board = parseBoard(kind, html(kind), time);
    assert.equal(board.kind, kind);
    assert.equal(board.entries.length, 22);
    assert.equal(board.entries.at(-1).rank, 22);
    assert.equal(board.entries.at(-1).modelID, 'model-21');
    assert.equal(board.entries[0].rank, 1);
    assert.equal(board.entries[0].name, 'Model 0');
    assert.equal(board.entries[0].modelID, 'model-0');
    assert.equal(board.entries[0].organization, 'Maker');
    assert.equal(board.fetchedAt, new Date(time).toISOString());
    if (kind.startsWith('arena') || kind === 'codeArenaWebDev' || kind === 'artificialAnalysisCodingAgent') {
      assert.equal(board.sourceUpdatedAt, '2026-10-10T00:00:00.000Z');
    } else assert.equal(board.sourceUpdatedAt, undefined);
  }
});

test('incomplete boards and arbitrary logo URL injection are rejected or sanitized', () => {
  assert.throws(() => parseBoard('arenaText', html('arenaText', undefined, 19), time));
  assert.throws(() => parseBoard('artificialAnalysisCodingAgent', html('artificialAnalysisCodingAgent', undefined, 9), time));
  const source = html('artificialAnalysis').replaceAll('/img/logos/maker.svg', 'https://attacker.invalid/tracking.svg');
  assert.equal(parseBoard('artificialAnalysis', source, time).entries[0].logoURL, undefined);
});

test('OSS tail reads and append position handle real multi-instance conflicts without process locks', async () => {
  const objects = new Map(); const ranges = [];
  const client = {
    async head(key) { if (!objects.has(key)) throw { code: 'NoSuchKey' }; return { res: { headers: { 'content-length': objects.get(key).length } } }; },
    async get(key, options) {
      const data = objects.get(key); if (!data) throw { code: 'NoSuchKey' };
      if (!options) return { content: data };
      ranges.push(options.headers.Range);
      const [, start, end] = options.headers.Range.match(/bytes=(\d+)-(\d+)/);
      return { content: data.subarray(Number(start), Number(end) + 1) };
    },
    async append(key, data, options) {
      const previous = objects.get(key) ?? Buffer.alloc(0);
      if (previous.length !== options.position) throw { code: 'PositionNotEqualToLength' };
      objects.set(key, Buffer.concat([previous, data]));
    },
    async put(key, data) { objects.set(key, data); },
  };
  const store = new OSSStore(client);
  for (let i = 0; i < 100; i++) {
    const state = await store.readState('arenaText');
    assert.ok(await store.appendState('arenaText', state.position, { hash: 'abc', issuedAt: i }));
  }
  const prior = await store.readState('arenaText');
  assert.equal(prior.state.issuedAt, 99);
  assert.ok(prior.position > 2048);
  assert.ok(await store.appendState('arenaText', prior.position, { hash: 'next' }));
  assert.equal(await store.appendState('arenaText', prior.position, { hash: 'race' }), false);
  assert.ok(ranges.at(-1).startsWith(`bytes=${prior.position - 2048}-`));
});

test('HTTP read, grant and HTML contribution round trip; wrong routes and raw JSON are blocked', async t => {
  const service = new SharedLeaderboards(new MemoryStore(), { clock: () => time });
  const server = createServer(handler(() => service));
  server.listen(0, '127.0.0.1'); await once(server, 'listening');
  t.after(() => { server.closeAllConnections(); server.close(); });
  const base = `http://127.0.0.1:${server.address().port}/v1/boards/arenaText`;
  assert.deepEqual(await (await fetch(base)).json(), { board: null });
  const { grant } = await (await fetch(base + '/refresh', { method: 'POST' })).json();
  assert.ok(grant);
  const json = await fetch(base + '/contribute', { method: 'POST', headers: { 'content-type': 'application/json', 'x-benchgauge-grant': grant.token }, body: '{}' });
  assert.equal(json.status, 415);
  const upload = await fetch(base + '/contribute', { method: 'POST', headers: { 'content-type': 'text/html', 'x-benchgauge-grant': grant.token }, body: html() });
  assert.equal(upload.status, 200);
  const board = (await upload.json()).board;
  const read = await fetch(base); assert.equal(read.headers.get('cache-control'), 'no-store');
  assert.deepEqual((await read.json()).board, board);
  assert.equal((await fetch(base + '/refresh')).status, 405);
  assert.equal((await fetch(base + '/unknown')).status, 404);
});

test('HTTP storage failures are redacted and cannot accidentally grant source access', async t => {
  const server = createServer(handler(() => { throw new Error('private credential or object path'); }));
  server.listen(0, '127.0.0.1'); await once(server, 'listening');
  t.after(() => { server.closeAllConnections(); server.close(); });
  const response = await fetch(`http://127.0.0.1:${server.address().port}/v1/boards/arenaText/refresh`, { method: 'POST' });
  assert.equal(response.status, 503);
  assert.deepEqual(await response.json(), { error: 'Shared service unavailable' });
});

test('runtime storage uses configured credentials and ignores public request credential headers', () => {
  const headers = { 'x-fc-access-key-id': 'untrusted-id', 'x-fc-access-key-secret': 'untrusted-secret', 'x-fc-security-token': 'untrusted-token' };
  const environment = { STORAGE_CREDENTIAL_SOURCE: 'environment', OSS_BUCKET: 'ai-benchgauge', OSS_REGION: 'oss-cn-shenzhen',
    ALIBABA_CLOUD_ACCESS_KEY_ID: 'runtime-id', ALIBABA_CLOUD_ACCESS_KEY_SECRET: 'runtime-secret' };
  const configuration = storageConfiguration(headers, environment);
  assert.equal(configuration.accessKeyId, 'runtime-id');
  assert.equal(configuration.accessKeySecret, 'runtime-secret');
  assert.equal(configuration.stsToken, undefined);
  assert.equal(configuration.internal, true);
  assert.throws(() => storageConfiguration(headers, { ...environment, ALIBABA_CLOUD_ACCESS_KEY_SECRET: '' }), e => e.status === 503);
  const role = storageConfiguration(headers, { OSS_BUCKET: 'ai-benchgauge', OSS_REGION: 'oss-cn-shenzhen', STORAGE_CREDENTIAL_SOURCE: 'role' });
  assert.equal(role.stsToken, 'untrusted-token');
  assert.throws(() => storageConfiguration({}, { OSS_BUCKET: 'ai-benchgauge', OSS_REGION: 'oss-cn-shenzhen', STORAGE_CREDENTIAL_SOURCE: 'role' }), e => e.status === 503);
});

test('deployment verifies the existing runtime identity and transfers only cloud credentials', async () => {
  class Request {}
  const config = deploymentConfiguration({ runtimeCredentialsFunction: 'weaveo', runtimeIdentityName: 'limphase-runtime' });
  const identity = { accountId: '123456789', arn: 'acs:ram::123456789:user/limphase-runtime' };
  const client = { async getFunction(name) {
    assert.equal(name, 'weaveo');
    return { body: { environmentVariables: { ALIBABA_CLOUD_ACCESS_KEY_ID: 'runtime-id', ALIBABA_CLOUD_ACCESS_KEY_SECRET: 'runtime-secret',
      ALIBABA_CLOUD_SECURITY_TOKEN: 'runtime-token', OTHER_PROVIDER_SECRET: 'never-copy' } } };
  } };
  const runtime = await existingRuntimeCredentials(client, { GetFunctionRequest: Request }, config, identity.accountId, async auth => {
    assert.deepEqual(auth, { accessKeyId: 'runtime-id', accessKeySecret: 'runtime-secret', securityToken: 'runtime-token' }); return identity;
  });
  assert.deepEqual(runtime.environmentVariables, { STORAGE_CREDENTIAL_SOURCE: 'environment', ALIBABA_CLOUD_ACCESS_KEY_ID: 'runtime-id',
    ALIBABA_CLOUD_ACCESS_KEY_SECRET: 'runtime-secret', ALIBABA_CLOUD_SECURITY_TOKEN: 'runtime-token' });
  await assert.rejects(existingRuntimeCredentials(client, { GetFunctionRequest: Request }, config, identity.accountId, async () => ({ ...identity, accountId: 'another-account' })));
  await assert.rejects(existingRuntimeCredentials(client, { GetFunctionRequest: Request }, config, identity.accountId, async () => ({ ...identity, arn: 'acs:ram::123456789:user/another-user' })));
  assert.equal(deploymentConfiguration({}).region, 'cn-shenzhen');
  assert.equal(deploymentConfiguration({}).functionName, 'ai-benchgauge');
  assert.throws(() => deploymentConfiguration({ functionName: '../another-service' }));
  assert.throws(() => deploymentConfiguration({ bucket: 'bad/bucket' }));
  assert.throws(() => deploymentConfiguration({ runtimeCredentialsFunction: 'weaveo' }));
  assert.equal(deploymentConfiguration({ roleArn: 'acs:ram::123456789:role/benchgauge' }).roleArn, 'acs:ram::123456789:role/benchgauge');
  assert.throws(() => deploymentConfiguration({ roleArn: 'not-a-role' }));
  assert.throws(() => deploymentConfiguration({ ...config, roleArn: 'acs:ram::123456789:role/benchgauge' }));
});

test('deployment checks existing private storage and never creates a bucket or alters permissions', async () => {
  const info = { Location: 'oss-cn-shenzhen', Owner: { ID: '123456789' }, AccessControlList: { Grant: 'private' }, StorageClass: 'Standard' };
  const oss = {
    async getBucketInfo() { return { bucket: info }; }, async getBucketVersioning() { return {}; },
    async getBucketLifecycle() { throw { code: 'NoSuchLifecycle' }; },
    async putBucket() { assert.fail('Bucket creation must remain with the user'); },
  };
  await checkExistingBucket(oss, 'ai-benchgauge', 'cn-shenzhen', '123456789');
  await assert.rejects(checkExistingBucket({ ...oss, getBucketInfo: async () => { throw { code: 'NoSuchBucket' }; } }, 'ai-benchgauge', 'cn-shenzhen', '123456789'), e => e.code === 'NoSuchBucket');
  await assert.rejects(checkExistingBucket(oss, 'ai-benchgauge', 'cn-beijing', '123456789'));
  await assert.rejects(checkExistingBucket({ ...oss, getBucketVersioning: async () => ({ versionStatus: 'Suspended' }) }, 'ai-benchgauge', 'cn-shenzhen', '123456789'));
  await assert.rejects(checkExistingBucket({ ...oss, getBucketLifecycle: async () => ({ rules: [{ prefix: 'benchgauge/' }] }) }, 'ai-benchgauge', 'cn-shenzhen', '123456789'));
});


test('openness uses explicit public-weight/license metadata and keeps unavailable values absent', () => {
  assert.equal(modelOpenness({ isOpenWeights: true }), 'open');
  assert.equal(modelOpenness({ isOpenWeights: false }), 'closed');
  assert.equal(modelOpenness({ openWeightsUrl: 'https://huggingface.co/maker/model' }), 'open');
  assert.equal(modelOpenness({ openWeightsUrl: null }), 'closed');
  assert.equal(modelOpenness({ license: 'Proprietary' }), 'closed');
  for (const license of ['MIT', 'Apache-2.0', 'MiniMax Community License']) assert.equal(modelOpenness({ license }), 'open');
  for (const value of [{}, { license: 'Other' }, { license: 'Unknown' }, { openWeightsUrl: '' }, { openWeightsUrl: 'invalid' }, { isOpenWeights: 'false' }]) assert.equal(modelOpenness(value), undefined);
  const swift = readFileSync(new URL('../Sources/LeaderboardKit/ModelOpenness.swift', import.meta.url), 'utf8');
  const keys = [...swift.split('public static let openLicenses: Set<String> = [')[1].split(']')[0].matchAll(/"([^"\n]+)"/g)].map(m => m[1]);
  const js = readFileSync(new URL('../fc/parser.mjs', import.meta.url), 'utf8');
  const sharedKeys = JSON.parse(js.match(/const openLicenses = new Set\((\[[^;]+\])\);/)[1]);
  assert.deepEqual([...keys].sort(), [...sharedKeys].sort());
  for (const kind of ['artificialAnalysis', 'artificialAnalysisTextToImage', 'artificialAnalysisTextToVideo', 'arenaText', 'codeArenaWebDev', 'arenaTextToImage', 'arenaTextToVideo']) {
    // The RSC stream contains an escaped JSON string; mutate decoded records and reframe it.
    const original = html(kind).match(/self\.__next_f\.push\(\[1,(.*)\]\)/)[1];
    const payload = JSON.parse(JSON.parse(original));
    for (const entry of payload.entries) Object.assign(entry.values ?? entry, { isOpenWeights: true });
    const framed = `<script>self.__next_f.push([1,${JSON.stringify(JSON.stringify(payload))}])</script>`;
    assert.equal(parseBoard(kind, framed, time).entries[0].openness, 'open');
    assert.equal(parseBoard(kind, html(kind), time).entries[0].openness, undefined);
  }
});
test('explicit model logo metadata remains separate from creator logo during parsing', () => {
  const source = html('artificialAnalysis', '2026-10-10T00:00:00Z', 22, '/img/logos/model-family.svg');
  const board = parseBoard('artificialAnalysis', source, time);
  assert.equal(board.entries[0].modelLogoURL,'https://artificialanalysis.ai/img/logos/model-family.svg');
  assert.equal(board.entries[0].logoURL,'https://artificialanalysis.ai/img/logos/maker.svg');
});
