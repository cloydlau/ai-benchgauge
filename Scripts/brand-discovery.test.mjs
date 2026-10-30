import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
const sharp = createRequire(new URL('../fc/package.json', import.meta.url))('sharp');
import { BrandRegistry, brandKey, normalizedBrandKey, fallbackColor, normalizeLogo, validPNG, safeLogoURL, downloadLogo, brandRetryInterval } from '../fc/brands.mjs';
import { SharedLeaderboards } from '../fc/service.mjs';
import { parseBoard } from '../fc/parser.mjs';
import { arenaRowLogos, maximumInlineLogoBytes } from '../fc/source-logos.mjs';
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
test('cached coding and image rows recover verified marks without downloading', async () => {
  const catalog = JSON.parse(readFileSync(new URL('../fc/brand-catalog.json', import.meta.url)));
  const registry = new BrandRegistry(new Store(), { download: async () => { throw Error('offline'); } });
  for (const [kind, name, organization, key] of [
    ['arenaTextToImage', 'FLUX.2 [max]', 'bfl', 'blackforestlabs'],
    ['arenaTextToImage', 'Stable Diffusion 3.5 Large', undefined, 'stabilityai'],
    ['artificialAnalysisCodingAgent', 'Mistral Vibe - Mistral Large 4 (High)', undefined, 'mistral'],
    ['artificialAnalysisCodingAgent', 'Mistral Vibe - Mistral Large 4 (Medium)', undefined, 'mistral'],
    ['artificialAnalysisCodingAgent', 'GitHub Copilot - Copilot Fusion (max)', undefined, 'github'],
    ['artificialAnalysisCodingAgent', 'Mirror - Beam 1.0', undefined, 'reflection'],
  ]) {
    const result = await registry.enrich({ kind, entries: [{ name, organization, brand: { key: '', status: 'unknown' } }] });
    assert.equal(result.entries[0].brand.key, key);
    assert.equal(result.entries[0].brand.pngData, catalog.providerLogos[key].pngData);
  }
  assert.equal(brandKey({ name: 'Mistral Vibe - Mistral Large 4 (High)', organization: 'Another Developer' }), 'anotherdeveloper');
});
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
  const verifiedQwen = JSON.parse(readFileSync(new URL('../fc/brand-catalog.json', import.meta.url))).providerLogos.qwen;
  assert.equal(result.entries[2].brand.pngData, verifiedQwen.pngData);
  assert.deepEqual(result.entries[2].organizationBrand, provider);
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

const sourceRow = (name, mark) => `<tr><td><svg><path d="M0 0"/></svg></td><td><div><div>${mark}</div><div><a><span title="${name}">${name}</span><svg><path d="M0 0"/></svg></a></div></div></td></tr>`;
function arenaHTML(kind, marks) {
  const entries = Array.from({ length: 22 }, (_, i) => ({ modelDisplayName: `Model ${i}`, modelKey: `model-${i}`,
    rating: 1500 - i, modelOrganization: i === 2 ? null : 'New Maker' }));
  return `<table><tbody>${marks.map((mark, i) => sourceRow(`Model ${i}`, mark)).join('')}</tbody></table>`
    + `<script>self.__next_f.push([1,${JSON.stringify(JSON.stringify({ entries }))}])</script>`;
}
test('all Arena boards acquire row SVGs and source images without a hand-maintained vendor list', async () => {
  for (const kind of ['arenaText', 'codeArenaWebDev', 'arenaTextToImage', 'arenaTextToVideo']) {
    const html = arenaHTML(kind, [svg.toString(), '<img src="/images/models/newmaker_light.png"/>', svg.toString()]);
    const input = parseBoard(kind, html, Date.now());
    assert.ok(input.organizationLogoSVGs['New Maker']);
    assert.equal(input.entries[1].logoURL, 'https://arena.ai/images/models/newmaker_light.png');
    assert.ok(input.entries[2].modelLogoSVG);
    const store = new Store(); let downloads = 0;
    const registry = new BrandRegistry(store, { download: async () => { downloads++; throw Error('inline marks need no download'); } });
    const result = await registry.enrich(input, { acquire: true });
    assert.equal(result.entries.length, 22);
    assert.equal(result.entries[0].brand.status, 'ready');
    assert.equal(result.entries[2].brand.status, 'ready');
    assert.match(result.entries[2].brand.key, /^model-/);
    assert.equal(downloads, 0);
    const cached = await new BrandRegistry(store).enrich(JSON.parse(JSON.stringify(input)));
    assert.equal(cached.entries[0].brand.pngData, result.entries[0].brand.pngData);
    assert.equal(cached.entries[2].brand.pngData, result.entries[2].brand.pngData);
    const older = { ...input, entries: input.entries.map(({ modelLogoSVG, ...entry }) => entry) };
    assert.equal((await new BrandRegistry(store).enrich(older)).entries[2].brand.pngData, result.entries[2].brand.pngData);
    assert.equal((await new BrandRegistry(store).enrich(older, { acquire: true })).entries[2].brand.pngData, result.entries[2].brand.pngData);
  }
});
test('row matching excludes controls, ambiguous names, oversized assets and unrelated remote images', async () => {
  const noMark = '<table><tr><td><svg/></td><td><a><span title="Model 0">Model 0</span><svg/></a></td></tr></table>';
  assert.equal(arenaRowLogos(noMark, new Set(['Model 0'])).size, 0);
  const duplicates = `<table>${sourceRow('A &amp; B', svg)}${sourceRow('A &amp; B', '<svg><circle r="1"/></svg>')}</table>`;
  assert.equal(arenaRowLogos(duplicates, new Set(['A & B'])).size, 0);
  const large = `<svg xmlns="http://www.w3.org/2000/svg"><!--${'x'.repeat(maximumInlineLogoBytes)}--></svg>`;
  assert.equal(arenaRowLogos(`<table>${sourceRow('Model 0', large)}</table>`, new Set(['Model 0'])).size, 0);
  const input = parseBoard('arenaText', arenaHTML('arenaText', ['<img src="https://evil.example/tracker.svg"/>']), Date.now());
  assert.equal(input.entries[0].logoURL, undefined);
  assert.equal(safeLogoURL('https://arena.ai/images/models/new.png'), 'https://arena.ai/images/models/new.png');
  assert.equal(safeLogoURL('https://arena.ai/other/new.png'), null);
  await assert.rejects(downloadLogo('https://arena.ai/images/models/new.png', AbortSignal.timeout(1000),
    async () => new Response(null, { status: 302, headers: { location: 'https://evil.example/new.png' } })));
});
test('page CSS ink survives standalone rendering and active inline SVG never becomes a cached image', async () => {
  const css = '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" fill="none" class="fill-black dark:fill-white"><circle cx="32" cy="32" r="28"/></svg>';
  const extracted = arenaRowLogos(`<table>${sourceRow('Model 0', css)}</table>`, new Set(['Model 0'])).get('Model 0');
  assert.ok(validPNG((await normalizeLogo(Buffer.from(extracted.svg))).png));
  for (const mark of ['<svg onload="alert(1)"><circle r="20"/></svg>', '<svg><image href="https://evil.example/a.png"/></svg>', '<svg><foreignObject/></svg>']) {
    const store = new Store();
    const result = await new BrandRegistry(store).enrich(parseBoard('arenaText', arenaHTML('arenaText', [mark]), Date.now()), { acquire: true });
    assert.equal(result.entries[0].brand.pngData, undefined);
    assert.equal(store.assets.size, 0);
  }
});
test('a newly available source SVG repairs an earlier missing provider immediately and survives a cold read', async () => {
  const store = new Store();
  const registry = new BrandRegistry(store);
  const input = { ...board('New Maker', null), kind: 'arenaText' };
  await registry.enrich(input, { acquire: true });
  assert.equal(store.records.get('newmaker').status, 'missing');
  const refreshed = await registry.enrich({ ...input, organizationLogoSVGs: { 'New Maker': svg.toString() } }, { acquire: true });
  assert.equal(refreshed.entries[0].brand.status, 'ready');
  // Other boards can use the acquired provider even before their next origin fetch.
  const read = await new BrandRegistry(store).enrich(input);
  assert.equal(read.entries[0].brand.pngData, refreshed.entries[0].brand.pngData);
});
test('source provider marks do not override verified model marks or inherit a harness identity', async () => {
  const input = { kind: 'arenaTextToVideo', organizationLogoSVGs: { Alibaba: svg.toString(), Anthropic: svg.toString() }, entries: [
    { name: 'Wan 3.0', organization: 'Alibaba' }, { name: 'HappyHorse-1.1', organization: 'Alibaba' },
    { name: 'Claude Code - Qwen3.8 Max', organization: 'Anthropic' },
  ] };
  const result = await new BrandRegistry(new Store(), { download: async () => { throw Error('offline'); } }).enrich(input, { acquire: true });
  assert.equal(result.entries[0].brand.key, 'model-wan');
  assert.equal(result.entries[0].organizationBrand.key, 'qwen');
  assert.equal(result.entries[1].brand.key, 'qwen');
  // Hosted Qwen uses its own verified product mark, not Alibaba or Anthropic.
  assert.notDeepEqual(result.entries[2].brand, result.entries[1].brand);
  const alone = await new BrandRegistry(new Store()).enrich({ ...input, entries: input.entries.slice(2) }, { acquire: true });
  // The verified bundled Qwen mark remains available without any source SVG.
  const catalog = JSON.parse(readFileSync(new URL('../fc/brand-catalog.json', import.meta.url)));
  assert.equal(alone.entries[0].brand.pngData, catalog.providerLogos.qwen.pngData);
  assert.equal(alone.entries[0].brand.key, 'model-product-qwen');
});
test('known models repair company artwork in saved snapshots while keeping company and distinct model artwork', async () => {
  const catalog = JSON.parse(readFileSync(new URL('../fc/brand-catalog.json', import.meta.url)));
  const companyPNG = (await normalizeLogo(svg)).png.toString('base64');
  const stale = key => ({ key, pngData: companyPNG, colorHex: '#319FA8', status: 'ready' });
  const input = { kind: 'arenaText', entries: [
    { name: 'Qwen3.5', organization: 'Alibaba', brand: stale('qwen'), organizationBrand: stale('qwen') },
    { name: 'Claude Opus 4.6', organization: 'Anthropic', brand: stale('anthropic'), organizationBrand: stale('anthropic') },
    { name: 'Gemini 3 Pro', organization: 'Google', brand: stale('google'), organizationBrand: stale('google') },
    { name: 'Unrelated', organization: 'New Maker', brand: stale('newmaker') },
    { name: 'Wan 3.0', organization: 'Alibaba', brand: stale('qwen') },
  ] };
  const registry = new BrandRegistry(new Store(), { download: async () => { throw Error('offline'); } });
  for (const acquire of [false, true]) {
    const result = await registry.enrich(input, { acquire });
    for (const [index, key] of [[0, 'qwen'], [1, 'anthropic']]) {
      assert.equal(result.entries[index].brand.pngData, catalog.providerLogos[key].pngData);
      assert.equal(result.entries[index].organizationBrand.pngData, companyPNG);
    }
    assert.equal(result.entries[2].brand.key, 'model-gemini');
    assert.equal(result.entries[2].organizationBrand.pngData, companyPNG);
    assert.equal(result.entries[3].brand.pngData, companyPNG);
    assert.equal(result.entries[4].brand.key, 'model-wan');
  }
});

test('old cached product images never become company marks and a real sibling company mark wins', async () => {
  const catalog = JSON.parse(readFileSync(new URL('../fc/brand-catalog.json', import.meta.url)));
  const productPNG = catalog.providerLogos.qwen.pngData;
  const model = { rank: 1, score: 99, name: 'Qwen3.5', organization: 'Alibaba', brand: { key: 'qwen', pngData: productPNG }, organizationBrand: { key: 'qwen', pngData: productPNG } };
  const result = await new BrandRegistry(new Store()).enrich({ kind: 'arenaText', entries: [model] });
  assert.equal(result.entries[0].brand.key, 'model-product-qwen');
  assert.equal(result.entries[0].brand.pngData, productPNG);
  assert.equal(result.entries[0].organizationBrand.pngData, undefined);
  const { companyRows } = await import('../fc/domain.mjs');
  assert.equal(companyRows([model])[0].brand.pngData, undefined);
  const wan = { ...model, name: 'Wan 3.0', brand: { key: 'model-wan', pngData: catalog.modelLogos.find(item => item.key === 'wan').pngData } };
  assert.equal(companyRows([wan])[0].brand.pngData, undefined);
  const companyPNG = (await normalizeLogo(svg)).png.toString('base64');
  const sibling = { rank: 2, score: 90, name: 'Other', organization: 'Alibaba', organizationBrand: { key: 'qwen', pngData: companyPNG } };
  assert.equal(companyRows([model, sibling])[0].brand.pngData, companyPNG);
});

test('a cached product mark is replaced when a verified company source becomes available', async () => {
  const catalog = JSON.parse(readFileSync(new URL('../fc/brand-catalog.json', import.meta.url)));
  const store = new Store();
  store.assets.set('old', Buffer.from(catalog.providerLogos.qwen.pngData, 'base64'));
  store.records.set('qwen', { assetHash: 'old', sourceURL: 'https://qwen.ai/favicon.ico', status: 'ready' });
  const registry = new BrandRegistry(store, { download: async () => svg });
  const entry = { rank: 1, score: 99, name: 'Qwen3.5', organization: 'Alibaba', logoURL: 'https://artificialanalysis.ai/img/logos/alibaba.svg' };
  const stale = await registry.enrich({ entries: [entry] });
  assert.equal(stale.entries[0].organizationBrand.pngData, undefined);
  const fixed = await registry.enrich({ entries: [entry] }, { acquire: true });
  assert.equal(fixed.entries[0].brand.key, 'model-product-qwen');
  assert.equal(fixed.entries[0].organizationBrand.pngData, (await normalizeLogo(svg)).png.toString('base64'));
});
