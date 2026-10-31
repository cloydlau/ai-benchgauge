import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, mkdtempSync, mkdirSync, cpSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createRequire } from 'node:module';
import { execFileSync } from 'node:child_process';
import { CountryRegistry, countryRetryInterval } from '../fc/countries.mjs';
import { BrandRegistry, brandKey, validPNG } from '../fc/brands.mjs';
import { companyRows } from '../fc/domain.mjs';
import { auditCountryCoverage } from './audit-country-coverage.mjs';
import { syncProviderLogos } from './sync-provider-logos.mjs';
const sharp = createRequire(new URL('../fc/package.json', import.meta.url))('sharp');
const fixtures = JSON.parse(readFileSync(new URL('../Tests/fixtures/new-board-metadata.json', import.meta.url)));
const catalog = JSON.parse(readFileSync(new URL('../fc/brand-catalog.json', import.meta.url)));
const countries = JSON.parse(readFileSync(new URL('../fc/country-catalog.json', import.meta.url)));

for (const unavailable of [false, true]) {
  test(`new board omissions enrich offline with ${unavailable ? 'unavailable' : 'failed'} registry storage`, async () => {
    let network = 0;
    const failed = key => ({ key, status: 'failed', nextAttemptAt: 1793453000000 + countryRetryInterval });
    const store = {
      async readCountry(key) { if (unavailable) throw Error('offline'); return failed(key); },
      async readBrand(key) { if (unavailable) throw Error('offline'); return failed(key); },
    };
    const input = { kind: 'artificialAnalysisSpeechProviderVoice', fetchedAt: '2026-10-31T09:00:00Z',
      sourceUpdatedAt: '2026-10-30T09:00:00Z', contentUpdatedAt: '2026-10-30T09:00:00Z',
      entries: fixtures.map((entry, i) => ({ name: entry.name, organization: entry.organization,
        modelID: entry.name, rank: i + 1, score: 100 - i, voteCount: 200 + i, rankChange: { delta: 2 },
        developerCountry: failed(String(entry.organization ?? '').toLowerCase().replace(/[^\p{L}\p{N}]/gu, '')) })) };
    const original = structuredClone(input);
    const countryRegistry = new CountryRegistry(store, { discover: async () => { network++; throw Error('unexpected network'); } });
    const brands = new BrandRegistry(store, { download: async () => { network++; throw Error('unexpected network'); } });
    const output = await brands.enrich(await countryRegistry.enrich(input));
    for (const [i, expected] of fixtures.entries()) {
      const entry = output.entries[i];
      assert.equal(brandKey(entry), expected.key, expected.name);
      assert.equal(entry.developerCountry.countryCode ?? null, expected.countryCode, expected.name);
      if (expected.countryCode) {
        assert.equal(entry.developerCountry.status, 'ready', expected.name);
        assert.equal(entry.developerCountry.sourceURL, countries[expected.key].sourceURL, expected.key);
      }
      if (expected.expectLogo) {
        assert.equal(validPNG(Buffer.from(entry.brand.pngData ?? '', 'base64')), true, expected.name);
        const metadata = await sharp(Buffer.from(entry.brand.pngData, 'base64')).metadata();
        assert.deepEqual([metadata.format, metadata.width, metadata.height], ['png', 64, 64]);
      }
      for (const key of ['name', 'modelID', 'rank', 'score', 'voteCount', 'rankChange']) assert.deepEqual(entry[key], input.entries[i][key], `${expected.name}: ${key}`);
    }
    for (const key of ['fetchedAt','sourceUpdatedAt','contentUpdatedAt']) assert.equal(output[key], input[key]);
    assert.equal(auditCountryCoverage([output]).missingCount, fixtures.filter(e => !e.countryCode).length);
    assert.deepEqual(input, original);
    assert.equal(network, 0);
    assert.deepEqual((await brands.enrich(await countryRegistry.enrich(output))).entries, output.entries);
  });
}

test('new artwork exports are reproducible from canonical sources without network', async () => {
  assert.ok(await syncProviderLogos({ check: true }) >= 19);
  const output = execFileSync(process.execPath, [new URL('./sync-provider-logos.mjs', import.meta.url).pathname, '--check'], { encoding: 'utf8' });
  assert.match(output, /^\d+ shared provider marks verified\n$/);
});

test('Alibaba company mark stays distinct from Qwen product artwork in models, company rows and export data', async () => {
  const store = { async readCountry() { return null; }, async readBrand() { return null; } };
  const input = { kind: 'artificialAnalysisSpeechAgent', fetchedAt: '2026-10-31T00:00:00Z', entries: [
    { name: 'Qwen Audio 3.0 Realtime Flash', organization: 'Alibaba Cloud', rank: 1, score: 100 },
  ] };
  const output = await new BrandRegistry(store).enrich(await new CountryRegistry(store).enrich(input));
  const entry = output.entries[0];
  assert.equal(entry.organization, 'Alibaba');
  assert.equal(entry.brand.key, 'model-product-qwen');
  assert.equal(entry.brand.pngData, catalog.providerLogos.qwen.pngData);
  assert.equal(entry.organizationBrand.key, 'qwen');
  assert.equal(entry.organizationBrand.pngData, catalog.companyLogos.qwen.pngData);
  assert.notEqual(entry.brand.pngData, entry.organizationBrand.pngData);
  const [company] = companyRows(JSON.parse(JSON.stringify(output)).entries);
  assert.equal(company.name, 'Alibaba');
  assert.equal(company.brand.pngData, entry.organizationBrand.pngData);
});

test('new display labels do not claim unrelated fine-tunes or overwrite an explicit source developer', async () => {
  const input = { kind: 'arenaText', entries: [
    { name: 'Yi Lightning', organization: 'Other Maker' },
    { name: 'Yi Lightning', modelID: 'yi-lightning-finetune' },
    { name: 'Trinity Large Thinking Community Fine-tune' },
    { name: 'P-Image-Edit Unverified Fork' },
    { name: 'Kokoro 82M v1.0', organization: 'Kokoro' },
    { name: 'Breeze TTS 2', organization: 'BreezeBlue' },
    { name: 'open_llama_7b', organization: 'OpenLM Research' },
    { name: 'OpenVoice v2', organization: 'OpenVoice' },
  ] };
  const result = await new CountryRegistry({ async readCountry() { return null; } }).enrich(input);
  assert.equal(result.entries[0].organization, 'Other Maker');
  for (const entry of result.entries) assert.equal(entry.developerCountry.countryCode, undefined, entry.name);
  assert.equal(brandKey(result.entries[1]), null);
  assert.equal(brandKey(result.entries[2]), null);
  assert.equal(brandKey(result.entries[3]), null);
});

// Older ownerless snapshots contain failed company marks under an empty key.
test('discovering an exact developer also repairs its stale company image', async () => {
  const input = { kind: 'arenaText', entries: [{ name: 'Yi Lightning', modelID: 'Yi Lightning', rank: 1, score: 99,
    organizationBrand: { key: '', status: 'missing' }, brand: { key: '', status: 'missing' } }] };
  const store = { async readCountry() { return null; }, async readBrand() { throw Error('offline'); } };
  const output = await new BrandRegistry(store).enrich(await new CountryRegistry(store).enrich(input));
  assert.equal(output.entries[0].organization, '01.AI');
  assert.equal(output.entries[0].organizationBrand.key, '01ai');
  assert.equal(output.entries[0].organizationBrand.pngData, catalog.providerLogos['01ai'].pngData);
  const company = companyRows(output.entries)[0];
  assert.equal(company.name, '01.AI');
  assert.equal(company.brand.pngData, catalog.providerLogos['01ai'].pngData);
});

test('stale catalog exports repair offline while unreviewed source changes remain rejected', async () => {
  const root = mkdtempSync(join(tmpdir(), 'benchgauge-provider-sync-'));
  try {
    mkdirSync(join(root, 'fc'));
    mkdirSync(join(root, 'assets/brand/partners'), { recursive: true });
    cpSync(new URL('../assets/brand/partners/leaderboard-providers', import.meta.url), join(root, 'assets/brand/partners/leaderboard-providers'), { recursive: true });
    const path = join(root, 'fc/brand-catalog.json');
    const stale = structuredClone(catalog); stale.providerLogos.cartesia.pngData = '';
    writeFileSync(path, JSON.stringify(stale));
    await assert.rejects(syncProviderLogos({ root, check: true }), /Shared logo is stale: cartesia/);
    await syncProviderLogos({ root });
    const fixed = JSON.parse(readFileSync(path));
    assert.deepEqual(fixed.providerLogos.cartesia, catalog.providerLogos.cartesia);
    assert.deepEqual(fixed.modelDevelopers, catalog.modelDevelopers);
    assert.deepEqual(fixed.providerLogos.openai, catalog.providerLogos.openai);
    await syncProviderLogos({ root, check: true });
    writeFileSync(join(root, 'assets/brand/partners/leaderboard-providers/cartesia/logo.svg'), '<svg/>');
    await assert.rejects(syncProviderLogos({ root }), /Artwork hash changed: cartesia/);
    assert.equal(readFileSync(path, 'utf8'), JSON.stringify(fixed, null, 2) + '\n');
  } finally { rmSync(root, { recursive: true, force: true }); }
});

test('artwork path escapes and independent color drift fail without rewriting the catalog', async () => {
  const root = mkdtempSync(join(tmpdir(), 'benchgauge-provider-boundaries-'));
  try {
    mkdirSync(join(root, 'fc'));
    const directory = join(root, 'assets/brand/partners/leaderboard-providers');
    cpSync(new URL('../assets/brand/partners/leaderboard-providers', import.meta.url), directory, { recursive: true });
    const manifestPath = join(directory, 'sources.json');
    const manifest = JSON.parse(readFileSync(manifestPath));
    const record = manifest.records.find(record => record.key === 'cartesia');
    manifest.records = [record];
    const catalogPath = join(root, 'fc/brand-catalog.json');
    const stale = structuredClone(catalog);
    stale.colors.cartesia = '#000000';
    const original = JSON.stringify(stale);
    writeFileSync(catalogPath, original);
    writeFileSync(manifestPath, JSON.stringify(manifest));
    await assert.rejects(syncProviderLogos({ root, check: true }), /Shared logo color is stale: cartesia/);
    assert.equal(readFileSync(catalogPath, 'utf8'), original);

    writeFileSync(manifestPath, JSON.stringify({ ...manifest, records: [{ ...record, file: '../outside.svg' }] }));
    await assert.rejects(syncProviderLogos({ root }), /Artwork outside source directory: cartesia/);
    assert.equal(readFileSync(catalogPath, 'utf8'), original);

    writeFileSync(manifestPath, JSON.stringify(manifest));
    const script = new URL('./sync-provider-logos.mjs', import.meta.url).pathname;
    assert.equal(execFileSync(process.execPath, [script, '--root', root], { encoding: 'utf8' }), '1 shared provider marks synchronized\n');
    const fixed = JSON.parse(readFileSync(catalogPath));
    assert.equal(fixed.colors.cartesia, catalog.colors.cartesia);
    assert.deepEqual(fixed.providerLogos.cartesia, catalog.providerLogos.cartesia);
    assert.deepEqual(fixed.modelDisplayAliases, catalog.modelDisplayAliases);
    const synchronized = readFileSync(catalogPath, 'utf8');
    assert.equal(execFileSync(process.execPath, [script, '--root', root, '--check'], { encoding: 'utf8' }), '1 shared provider marks verified\n');
    assert.equal(readFileSync(catalogPath, 'utf8'), synchronized);
  } finally { rmSync(root, { recursive: true, force: true }); }
});
