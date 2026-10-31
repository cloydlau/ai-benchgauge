import { readFileSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { normalizeLogo } from '../fc/brands.mjs';

// Offline only: source artwork is canonical; catalog PNGs are derived exports.
export async function syncProviderLogos({ root = fileURLToPath(new URL('../', import.meta.url)), check = false } = {}) {
  const directory = resolve(root, 'assets/brand/partners/leaderboard-providers');
  const manifest = JSON.parse(readFileSync(resolve(directory, 'sources.json')));
  const catalogPath = resolve(root, 'fc/brand-catalog.json');
  const catalog = JSON.parse(readFileSync(catalogPath));
  const sha = bytes => createHash('sha256').update(bytes).digest('hex');
  for (const record of manifest.records) {
    const file = resolve(directory, record.file);
    if (!file.startsWith(directory + '/')) throw Error(`Artwork outside source directory: ${record.key}`);
    const bytes = readFileSync(file);
    if (sha(bytes) !== record.sourceSHA256) throw Error(`Artwork hash changed: ${record.key}; update provenance after verifying the source`);
    const { png, colorHex } = await normalizeLogo(bytes);
    const target = record.scope === 'company' ? 'companyLogos' : 'providerLogos';
    const value = { sourceURL: record.sourceURL, referenceURL: record.referenceURL, colorHex, pngData: png.toString('base64'),
      provenance: { sourceSHA256: record.sourceSHA256, downloadSHA256: record.downloadSHA256,
        pngSHA256: sha(png), retrievedAt: manifest.retrievedAt, normalization: manifest.normalization,
        permissionStatus: record.permissionStatus, ...(record.conversion && { conversion: record.conversion }) } };
    if (check && JSON.stringify(catalog[target]?.[record.key]) !== JSON.stringify(value)) {
      throw Error(`Shared logo is stale: ${record.key}; run node Scripts/sync-provider-logos.mjs`);
    }
    catalog[target] ??= {};
    catalog[target][record.key] = value;
    if (target === 'providerLogos') {
      if (check && catalog.colors[record.key] !== colorHex) throw Error(`Shared logo color is stale: ${record.key}`);
      catalog.colors[record.key] = colorHex;
    }
  }
  if (!check) writeFileSync(catalogPath, JSON.stringify(catalog, null, 2) + '\n');
  return manifest.records.length;
}

if (process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url) {
  const rootOption = process.argv.indexOf('--root');
  const root = rootOption < 0 ? undefined : process.argv[rootOption + 1];
  console.log(`${await syncProviderLogos({ root, check: process.argv.includes('--check') })} shared provider marks ${process.argv.includes('--check') ? 'verified' : 'synchronized'}`);
}
