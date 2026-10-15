import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
const sharp = createRequire(new URL('../fc/package.json', import.meta.url))('sharp');
import { BrandRegistry, brandKey, normalizedBrandKey, fallbackColor, normalizeLogo, validPNG, safeLogoURL, downloadLogo, brandRetryInterval } from '../fc/brands.mjs';
import { SharedLeaderboards } from '../fc/service.mjs';
const svg = Buffer.from('<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64"><circle cx="32" cy="32" r="28" fill="#319FA8"/></svg>');
const url = 'https://artificialanalysis.ai/img/logos/newmaker.svg';
class Store {
  records = new Map(); assets = new Map(); states = new Map(); reads = 0;
  async readBrand(k) { this.reads++; return this.records.get(k); }
  async writeBrand(k, v) { this.records.set(k, v); }
  async readBrandPNG(k) { return this.assets.get(k); }
  async writeBrandPNG(k, v) { this.assets.set(k, v); }
  async readState(k) { return this.states.get(k) ?? { position: 0 }; }
  async appendState(k, position, state) {
    if ((this.states.get(k)?.position ?? 0) !== position) return false;
    this.states.set(k, { position: position + 1, state }); return true;
  }
}
const board = (organization = 'New Maker', logoURL = url) => ({ kind: 'arenaText', fetchedAt: '2026-10-12T00:00:00Z', entries: [1, 2].map(rank => ({ rank, name: `New Model ${rank}`, score: 100 - rank, organization, logoURL })) });
test('SVG becomes a visible bounded PNG and useful color; blank/malformed/external SVG cannot become cached logos', async () => {
  const result = await normalizeLogo(svg);
  assert.equal(validPNG(result.png), true); assert.equal(result.colorHex, '#319FA8');
  const white = await normalizeLogo(Buffer.from('<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64"><circle cx="32" cy="32" r="28" fill="white"/></svg>'));
  assert.equal(validPNG(white.png), true);
  const pixels = await sharp(white.png).ensureAlpha().raw().toBuffer();
  assert.ok(pixels[(32 * 64 + 32) * 4] < 100 && pixels[(32 * 64 + 32) * 4 + 3] > 240);
  for (const data of [Buffer.from('bad bytes'), Buffer.from('<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64"/>'),
    Buffer.from('<svg><image href="https://example.com/a.png"/></svg>'), Buffer.from('<!DOCTYPE svg><svg/>')]) await assert.rejects(normalizeLogo(data));
});
test('new models and cold FC instances share one manufacturer PNG; cached reads never download', async () => {
  const store = new Store(); let downloads = 0;
  const registry = () => new BrandRegistry(store, { download: async () => { downloads++; return svg; } });
  const results = await Promise.all(Array.from({ length: 8 }, () => registry().enrich(board(), { acquire: true })));
  assert.equal(downloads, 1); assert.equal(store.records.size, 1);
  const enriched = await registry().enrich(board());
  assert.ok(enriched.entries[0].brand.pngData);
  assert.deepEqual(enriched.entries[0].brand, enriched.entries[1].brand);
  assert.deepEqual(enriched.entries.map(({brand, ...row}) => row), board().entries);
  assert.equal(enriched.fetchedAt, board().fetchedAt);
  await registry().enrich(board('New-Maker', undefined), { acquire: true });
  assert.equal(downloads, 1);
  store.readBrand = async () => { throw Error('storage unavailable'); };
  assert.deepEqual((await registry().enrich(enriched)).entries, enriched.entries);
  assert.equal(results.length, 8);
});
test('failed acquisition preserves rankings and stable washes, waits then retries; missing asset is repairable', async () => {
  const store = new Store(); let now = 1000, attempts = 0;
  const registry = new BrandRegistry(store, { clock: () => now, download: async () => { if (++attempts === 1) throw Error('offline'); return svg; } });
  const failure = await registry.enrich(board(), { acquire: true });
  assert.equal(failure.entries[0].brand.colorHex, fallbackColor('New Maker'));
  assert.equal(failure.entries[0].brand.pngData, undefined);
  await registry.enrich(board(), { acquire: true }); assert.equal(attempts, 1);
  now += brandRetryInterval;
  const success = await registry.enrich(board(), { acquire: true }); assert.ok(success.entries[0].brand.pngData);
  store.assets.clear(); now += brandRetryInterval;
  assert.ok((await registry.enrich(board(), { acquire: true })).entries[0].brand.pngData);
  assert.equal(attempts, 3);
});
test('missing source is retried when a source appears; known hue wins, ambiguous owner stays ungrouped', async () => {
  const store = new Store(); let calls = 0;
  const registry = new BrandRegistry(store, { download: async () => { calls++; return svg; } });
  const missing = board('New Maker', null);
  assert.equal((await registry.enrich(missing, { acquire: true })).entries[0].brand.pngData, undefined);
  assert.equal(store.records.get('newmaker').status, 'missing');
  assert.ok((await registry.enrich(board(), { acquire: true })).entries[0].brand.pngData);
  const known = await registry.enrich(board('Moonshot AI'), { acquire: true });
  assert.equal(known.entries[0].brand.key, 'kimi'); assert.equal(known.entries[0].brand.colorHex, '#007CFF');
  const unknown = await registry.enrich(board('Unknown'), { acquire: true });
  assert.equal(unknown.entries[0].brand.key, ''); assert.equal(store.records.has('unknown'), false);
  assert.equal(brandKey({organization:'Anthropic', name:'Claude Code - Qwen3.8 Max + GPT'}), 'qwen');
  assert.equal(brandKey({name:'Devin Fusion - GPT-6'}), 'devin');
  assert.equal(brandKey({name:'Claude Code - Sonnet 5.5 (max)'}), 'anthropic');
  const hostedStore = new Store();
  await new BrandRegistry(hostedStore, {download: async()=>{throw Error('must not fetch harness logo');}}).enrich({entries:[{organization:'Anthropic',name:'Claude Code - Qwen3.8 Max',logoURL:url}]},{acquire:true});
  assert.equal(hostedStore.records.get('qwen').sourceURL,null);
  assert.equal(calls, 2);
});
test('source logo requests reject unrelated hosts, redirect escapes and oversized content', async () => {
  for (const address of ['https://evil.example/img/logos/a.svg','http://artificialanalysis.ai/img/logos/a.svg','https://artificialanalysis.ai/other.svg','https://artificialanalysis.ai:8443/img/logos/a.svg']) assert.equal(safeLogoURL(address),null);
  const signal = AbortSignal.timeout(1000);
  await assert.rejects(downloadLogo(url, signal, async()=>new Response(null,{status:302,headers:{location:'https://evil.example/a.svg'}})));
  await assert.rejects(downloadLogo(url, signal, async()=>new Response(svg,{headers:{'content-length':1048577}})));
  assert.deepEqual(await downloadLogo(url, signal, async()=>new Response(svg)), svg);
});
test('branding failures do not suppress refresh grants or rankings and budgets stop queued acquisitions', async () => {
  const store = new Store(); store.readBrand = async () => {throw Error('registry outage');}; store.readBoard = async()=>board();
  const service = new SharedLeaderboards(store,{brands:new BrandRegistry(store)});
  assert.ok((await service.refresh('arenaText')).grant); assert.equal((await service.read('arenaText')).board.entries.length,2);
  let attempts=0;
  const slow = new BrandRegistry(new Store(),{budget:20,download:async(_, signal)=>{attempts++;await new Promise((resolve,reject)=>signal.addEventListener('abort',()=>reject(Error('timeout')),{once:true}));}});
  const result = await slow.enrich({entries:Array.from({length:20},(_,i)=>({organization:`Maker ${i}`,name:`Model ${i}`,logoURL:url}))},{acquire:true});
  assert.equal(result.entries.length,20); assert.equal(attempts,4);
});
test('shared catalog retains Swift established colors/families and stable alias fallback vectors', () => {
  const catalog=JSON.parse(readFileSync(new URL('../fc/brand-catalog.json',import.meta.url)));
  const swift=readFileSync(new URL('../Sources/LeaderboardKit/OrganizationLogoCatalog.swift',import.meta.url),'utf8');
  const colors=Object.fromEntries([...swift.matchAll(/"([a-z]+)": "(#[0-9A-F]{6})"/g)].map(m=>[m[1],m[2]]));
  assert.deepEqual(catalog.colors,colors);
  const generated=readFileSync(new URL('../Sources/LeaderboardKit/LeaderboardBrandPolicy.generated.swift',import.meta.url),'utf8');
  for (const [family,key] of catalog.families) assert.ok(generated.includes(`("${family}", "${key}")`));
  for (const [alias,key] of Object.entries(catalog.aliases)) assert.equal(normalizedBrandKey(alias),key);
  assert.equal(fallbackColor('New Maker'),fallbackColor('new-maker'));
  assert.equal(fallbackColor('Skywork AI'),'#B55C7B');
});
test('Wan family owns a separate mark; old Alibaba PNG cannot hide it or leak into Qwen', async () => {
  const store = new Store(); const requests = [];
  const registry = new BrandRegistry(store, { download: async address => { requests.push(address); return svg; } });
  const provider = (await registry.enrich(board('Alibaba', 'https://artificialanalysis.ai/img/logos/alibaba.svg'), { acquire: true })).entries[0].brand;
  const input = { entries: [
    { name: 'Wan 3.0', organization: 'Alibaba', logoURL: 'https://artificialanalysis.ai/img/logos/alibaba.svg', brand: provider },
    { name: 'Wan2.7-260612', organization: 'Alibaba', logoURL: 'https://artificialanalysis.ai/img/logos/alibaba.svg', brand: provider },
    { name: 'Qwen 4', organization: 'Alibaba', brand: provider },
    { name: 'HappyHorse-1.1', organization: 'Alibaba-ATH', brand: provider },
  ] };
  const result = await registry.enrich(input, { acquire: true });
  assert.equal(result.entries[0].brand.key, 'model-wan');
  assert.deepEqual(result.entries[0].brand, result.entries[1].brand);
  assert.deepEqual(result.entries[0].organizationBrand, provider);
  assert.deepEqual(result.entries[2].brand, provider);
  assert.deepEqual(result.entries[3].brand, provider);
  assert.equal(requests.length, 2);
  assert.equal(store.records.size, 2);
  await registry.enrich(result, { acquire: true });
  assert.equal(requests.length, 2);
  store.readBrand = async () => { throw Error('outage'); };
  assert.equal((await registry.enrich(result)).entries[0].brand.key, 'model-wan');
});
test('failed model mark uses provider temporarily and retries without losing its separate identity', async () => {
  const store = new Store(); let now = 1000, attempts = 0;
  const registry = new BrandRegistry(store, { clock: () => now, download: async address => {
    if (address.includes('new-family') && ++attempts === 1) throw Error('offline');
    return svg;
  } });
  const input = { entries: [{ name: 'New Family 1', organization: 'Alibaba', logoURL: 'https://artificialanalysis.ai/img/logos/alibaba.svg', modelLogoURL: 'https://artificialanalysis.ai/img/logos/new-family.svg' }] };
  const { modelLogo } = await import('../fc/brands.mjs'); const key = modelLogo(input.entries[0]).key;
  const failed = await registry.enrich(input, { acquire: true });
  assert.equal(failed.entries[0].brand.key, 'qwen');
  assert.equal(store.records.get(key).status, 'failed');
  await registry.enrich(failed, { acquire: true }); assert.equal(attempts, 1);
  now += brandRetryInterval;
  assert.equal((await registry.enrich(failed, { acquire: true })).entries[0].brand.key, key);
});
test('explicit source model assets are shared by image, never by provider; unrecognized names do not guess', async () => {
  const store = new Store(); let downloads = 0;
  const registry = new BrandRegistry(store, { download: async () => { downloads++; return svg; } });
  const input = { entries: [
    { name: 'New family 1', organization: 'New Maker', logoURL: url, modelLogoURL: 'https://artificialanalysis.ai/img/logos/new-family.svg' },
    { name: 'New family 2', organization: 'New Maker', logoURL: url, modelLogoURL: 'https://artificialanalysis.ai/img/logos/new-family.svg' },
    { name: 'Other family', organization: 'New Maker', logoURL: url },
  ] };
  const result = await registry.enrich(input, { acquire: true });
  assert.match(result.entries[0].brand.key, /^model-/);
  assert.deepEqual(result.entries[0].brand, result.entries[1].brand);
  assert.equal(result.entries[2].brand.key, 'newmaker');
  assert.equal(downloads, 2);
  assert.equal((await registry.enrich({ entries: [{name:'New ownerless model', modelLogoURL:url}] }, { acquire:true })).entries[0].brand.status, 'ready');
  const catalog=JSON.parse(readFileSync(new URL('../fc/brand-catalog.json',import.meta.url)));
  for (const model of catalog.modelLogos) assert.equal(safeLogoURL(model.sourceURL),model.sourceURL);
  assert.equal(safeLogoURL('https://g.alicdn.com/other/icon.png'),null);
  assert.equal(safeLogoURL('https://www.skyreels.ai/arbitrary.png'),null);
  const {modelLogo} = await import('../fc/brands.mjs');
  assert.equal(modelLogo({ name: 'Wanderer', organization: 'Alibaba' }),null);
  assert.equal(modelLogo({ name: 'Wan 3.0', organization: 'Other Maker' }),null);
  for (const [name,organization,key] of [['Dreamina Seedance 2.5','ByteDance Seed','dreamina'],['dreamina-seedance-2.0-720p','ByteDance','dreamina'],['gemini-omni-1.1-flash','Google','geminiomni'],['Veo 3.1','Google','veo'],['SkyReels V4','Skywork AI','skyreels'],['Grok Imagine Video 1.5','SpaceXAI','grok']]) assert.equal(modelLogo({name,organization}).key,`model-${key}`);
});
test('verified official marks remain visible during regional download or registry failure', async () => {
  const store = new Store();
  const registry = new BrandRegistry(store, { download: async () => { throw Error('regional outage'); } });
  const input = { entries: [{ name:'Wan 3.0', organization:'Alibaba', logoURL:'https://artificialanalysis.ai/img/logos/alibaba.svg' }] };
  assert.equal((await registry.enrich(input)).entries[0].brand.key,'model-wan');
  const result = await registry.enrich(input,{acquire:true});
  assert.equal(result.entries[0].brand.key,'model-wan');
  assert.ok(validPNG(Buffer.from(result.entries[0].brand.pngData,'base64')));
  assert.equal(store.records.get('model-wan').status,'ready');
  store.readBrand = async()=>{throw Error('registry offline');};
  assert.equal((await registry.enrich(input)).entries[0].brand.key,'model-wan');
});
