import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { createRequire } from 'node:module';
import { BrandRegistry, validPNG } from '../fc/brands.mjs';
const sharp = createRequire(new URL('../fc/package.json', import.meta.url))('sharp');
const catalog = JSON.parse(readFileSync(new URL('../fc/brand-catalog.json', import.meta.url)));

// The supplier keys removed from client asset bundles on 2026-10-28. Keep this
// acceptance inventory independent of the server catalog so omissions fail.
const consolidatedProviders = [
  "01ai",
  "ai21labs",
  "anthropic",
  "arceeai",
  "blackforestlabs",
  "bytedance",
  "databricks",
  "deepseek",
  "devin",
  "fal",
  "google",
  "huggingface",
  "ideogram",
  "kimi",
  "klingai",
  "krea",
  "kuaishou",
  "laion",
  "lmsys",
  "luma",
  "meta",
  "microsoftai",
  "minimax",
  "mistral",
  "mosaicml",
  "nexusflow",
  "nomicai",
  "nousresearch",
  "nvidia",
  "openai",
  "opencode",
  "pixverse",
  "primeintellect",
  "princetonnlp",
  "qwen",
  "reka",
  "reve",
  "runway",
  "shanghaiailaboratory",
  "snowflake",
  "spacexai",
  "stabilityai",
  "stanford",
  "stepfun",
  "technologyinnovationinstitute",
  "tencent",
  "thinkingmachines",
  "togetherai",
  "ucberkeley",
  "universityofwashington",
  "videorebirth",
  "xiaomi",
  "zai"
];

for (const storageUnavailable of [false, true]) {
  test(`all 53 former client brands have shared images with ${storageUnavailable ? 'unavailable' : 'cold'} storage`, async () => {
    const store = { async readBrand() { if (storageUnavailable) throw Error('offline'); return null; } };
    let downloads = 0;
    const registry = new BrandRegistry(store, { download: async () => { downloads++; throw Error('unexpected network request'); } });
    const input = { kind: 'artificialAnalysis', fetchedAt: '2026-10-28T00:00:00Z', entries: consolidatedProviders.map((key, i) => ({
      rank: i + 1, name: `Synthetic provider fixture ${i}`, organization: key, score: 100 - i,
    })) };
    const output = await registry.enrich(input);
    assert.equal(output.entries.length, 53);
    for (const [i, key] of consolidatedProviders.entries()) {
      const record = catalog.providerLogos[key];
      assert.ok(record?.pngData, `Missing backend image: ${key}`);
      assert.equal(new URL(record.sourceURL).protocol, 'https:', key);
      assert.equal(new URL(record.referenceURL).protocol, 'https:', key);
      const image = Buffer.from(output.entries[i].brand.pngData, 'base64');
      assert.equal(validPNG(image), true, key);
      const decoded = await sharp(image).metadata();
      assert.deepEqual([decoded.format, decoded.width, decoded.height], ['png', 64, 64], key);
      assert.equal(output.entries[i].brand.key, key);
      assert.equal(output.entries[i].brand.pngData, (catalog.companyLogos?.[key] ?? record).pngData, key);
      assert.equal(output.entries[i].rank, input.entries[i].rank);
      assert.equal(output.entries[i].score, input.entries[i].score);
    }
    assert.equal(downloads, 0);
    // Cached snapshots retain the same images even when a subsequent read has
    // neither registry storage nor access to the original image website.
    const saved = JSON.parse(JSON.stringify(output));
    assert.deepEqual((await registry.enrich(saved)).entries, output.entries);
    assert.equal(input.entries[0].brand, undefined);
  });
}

test('Video Rebirth records its official source and hashes without asserting artwork permission', () => {
  const record = catalog.providerLogos.videorebirth;
  assert.equal(record.sourceURL, 'https://www.videorebirth.com/fav-icon.svg');
  assert.equal(record.referenceURL, 'https://www.videorebirth.com/');
  assert.match(record.provenance.sourceSHA256, /^[a-f0-9]{64}$/);
  assert.equal(createHash('sha256').update(Buffer.from(record.pngData, 'base64')).digest('hex'), record.provenance.pngSHA256);
  assert.equal(record.provenance.permissionStatus, 'not-confirmed');
  assert.equal(record.provenance.normalization, 'fc/brands.mjs normalizeLogo');
  assert.ok(Number.isFinite(Date.parse(record.provenance.retrievedAt)));
});
