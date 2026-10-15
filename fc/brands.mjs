import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import sharp from 'sharp';
import { createBrandRules } from './domain.mjs';

const catalog = JSON.parse(readFileSync(new URL('./brand-catalog.json', import.meta.url)));
const palette = ['#607D8B', '#4F6DCD', '#8C6BB1', '#318F7A', '#A5683A', '#B55C7B', '#5A87A1', '#737D3C'];
export const brandRetryInterval = 30 * 60 * 1000;
const maximumPNG = 16 * 1024;
export function validPNG(bytes) {
  return Buffer.isBuffer(bytes) && bytes.length >= 33 && bytes.length <= maximumPNG
    && bytes.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]))
    && bytes.readUInt32BE(16) === 64 && bytes.readUInt32BE(20) === 64;
}
sharp.concurrency(1);
sharp.cache({ memory: 16, files: 0, items: 16 });

export const { normalizedBrandKey, brandKey, knownModelBrand } = createBrandRules(catalog);
export function fallbackColor(key) {
  let hash = 2166136261;
  for (const byte of Buffer.from(normalizedBrandKey(key))) hash = Math.imul(hash ^ byte, 16777619) >>> 0;
  return palette[hash % palette.length];
}
export function safeLogoURL(value) {
  try {
    const url = new URL(value);
    // Only source-owned logo assets. Validate again after every redirect.
    const verified = catalog.modelLogos.some(model => model.sourceURL === url.href);
    const source = url.hostname === 'artificialanalysis.ai' && url.pathname.startsWith('/img/logos/')
      && /\.(svg|png|jpe?g|webp)$/i.test(url.pathname);
    if (url.protocol !== 'https:' || url.username || url.password || url.port || !verified && !source) return null;
    return url.href;
  } catch { return null; }
}
// Model marks are independent of provider marks. Never infer a model mark
// from creator.logo: the current source explicitly supplies Alibaba for Wan.
export function modelLogo(entry) {
  const explicit = safeLogoURL(entry.modelLogoURL);
  if (explicit) return { key: `model-${createHash('sha256').update(explicit).digest('hex').slice(0, 24)}`, sourceURL: explicit };
  const verified = knownModelBrand(entry);
  return verified ? { key: verified.key, sourceURL: verified.sourceURL, verified } : null;
}
export async function downloadLogo(value, signal, fetcher = fetch) {
  let url = safeLogoURL(value);
  if (!url) throw new Error('Unsupported source logo');
  for (let hop = 0; hop < 3; hop++) {
    const response = await fetcher(url, { redirect: 'manual', signal,
      headers: { Accept: 'image/svg+xml,image/png,image/webp,image/jpeg', 'User-Agent': 'BenchGauge brand cache' } });
    if (response.status >= 300 && response.status < 400) {
      const next = safeLogoURL(new URL(response.headers.get('location') ?? '', url).href);
      await response.body?.cancel();
      if (!next) throw new Error('Unsupported logo redirect');
      url = next; continue;
    }
    if (!response.ok || Number(response.headers.get('content-length')) > 1024 * 1024) {
      await response.body?.cancel(); throw new Error('Logo unavailable');
    }
    const chunks = []; let length = 0;
    for await (const chunk of response.body ?? []) {
      signal.throwIfAborted(); length += chunk.length;
      if (length > 1024 * 1024) throw new Error('Logo too large');
      chunks.push(chunk);
    }
    return Buffer.concat(chunks);
  }
  throw new Error('Too many logo redirects');
}

export async function normalizeLogo(bytes) {
  // Logos need no external images, fonts, entities or active SVG content.
  const text = bytes.toString('utf8');
  if (/<svg[\s>]/i.test(text)) {
    if (/<!DOCTYPE|<!ENTITY|<\s*(?:script|foreignObject|iframe)\b|@import/i.test(text)) throw new Error('Unsupported SVG');
    const refs = [...text.matchAll(/(?:\b|:)href\s*=\s*(['"])(.*?)\1/gi)];
    if (refs.some(ref => !ref[2].startsWith('#'))
      || (text.match(/(?:\b|:)href\s*=/gi)?.length ?? 0) !== refs.length) throw new Error('External SVG reference');
    for (const match of text.matchAll(/url\s*\(([^)]*)\)/gi)) {
      if (!match[1].trim().replace(/^['"]|['"]$/g, '').startsWith('#')) throw new Error('External SVG style');
    }
  }
  let png = await sharp(bytes, { limitInputPixels: 4_000_000, failOn: 'warning', pages: 1 })
    .timeout({ seconds: 2 }).rotate().resize(64, 64, { fit: 'contain', background: '#00000000' })
    .ensureAlpha().png({ palette: true, colours: 64, compressionLevel: 9 }).toBuffer();
  if (png.length > maximumPNG) throw new Error('Normalized logo too large');
  const { data } = await sharp(png).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  const bins = new Map(); let visible = 0, white = 0;
  for (let i = 0; i < data.length; i += 4) {
    const [r, g, b, a] = data.subarray(i, i + 4);
    if (a >= 160) { visible++; if (r > 240 && g > 240 && b > 240) white++; }
    const high = Math.max(r, g, b), low = Math.min(r, g, b);
    if (a < 160 || high > 240 && low > 225 || high < 35 || high - low < 30) continue;
    const key = `${r >> 5},${g >> 5},${b >> 5}`;
    const bin = bins.get(key) ?? { count: 0, sum: [0, 0, 0] };
    bin.count++; bin.sum[0] += r; bin.sum[1] += g; bin.sum[2] += b; bins.set(key, bin);
  }
  if (visible < 4) throw new Error('Empty logo');
  if (white === visible) {
    if (visible > 64 * 64 * 0.95) throw new Error('Empty white tile');
    // Source wordmarks sometimes contain only white ink for a dark page.
    // Our cross-platform icon tile is white, so preserve alpha and darken ink.
    for (let i = 0; i < data.length; i += 4) data[i] = data[i + 1] = data[i + 2] = 48;
    png = await sharp(data, { raw: { width: 64, height: 64, channels: 4 } })
      .png({ palette: true, colours: 64, compressionLevel: 9 }).toBuffer();
  }
  const best = [...bins.values()].sort((a, b) => b.count - a.count)[0];
  // Preserve colored ink but avoid nearly-white fills. Monochrome uses a neutral wash.
  const channels = best ? best.sum.map(v => Math.min(210, Math.max(45, Math.round(v / best.count)))) : [96, 96, 96];
  const colorHex = '#' + channels.map(v => v.toString(16).padStart(2, '0')).join('').toUpperCase();
  return { png, colorHex };
}

export class BrandRegistry {
  constructor(store, { clock = Date.now, download = downloadLogo, normalize = normalizeLogo, budget = 4500 } = {}) {
    this.store = store; this.clock = clock; this.download = download; this.normalize = normalize; this.budget = budget;
  }
  async enrich(board, { acquire = false } = {}) {
    if (!board) return board;
    const groups = new Map();
    for (const entry of board.entries) {
      const model = modelLogo(entry);
      if (model) groups.set(model.key, { ...model, name: entry.name, scope: 'model',
        saved: entry.brand?.key === model.key && entry.brand.sourceURL === model.sourceURL ? entry.brand : null });
      const key = brandKey(entry); if (!key) continue;
      const candidate = safeLogoURL(entry.logoURL ?? board.organizationLogoURLs?.[entry.organization]);
      const previous = groups.get(key);
      // A hosted-model override must never inherit the harness's source logo.
      const sourceURL = normalizedBrandKey(entry.organization) === key ? candidate : null;
      const organizationBrand = entry.organizationBrand ?? entry.brand;
      const saved = organizationBrand?.key === key && validPNG(Buffer.from(organizationBrand.pngData ?? '', 'base64')) ? organizationBrand : previous?.saved;
      groups.set(key, { key, name: entry.organization ?? entry.name, sourceURL: previous?.sourceURL ?? sourceURL, saved });
    }
    const resolved = new Map();
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.budget);
    const queue = [...groups.values()];
    try {
      await Promise.all(Array.from({ length: Math.min(4, queue.length) }, async () => {
        while (queue.length && !controller.signal.aborted) {
          const brand = queue.shift();
          try { resolved.set(brand.key, await this.resolve(brand, acquire, controller.signal)); }
          catch { /* Registry/asset failure cannot erase a valid ranking. */ }
        }
      }));
    } finally { clearTimeout(timer); }
    return { ...board, entries: board.entries.map(entry => {
      const key = brandKey(entry);
      const cached = resolved.get(key);
      // Retain saved PNGs if the registry temporarily cannot be read.
      const saved = [entry.organizationBrand, entry.brand].find(brand => brand?.key === key);
      const organizationBrand = cached ?? saved ?? { key: key ?? '', colorHex: catalog.colors[key] ?? fallbackColor(key ?? entry.name), status: key ? 'pending' : 'unknown' };
      const model = modelLogo(entry);
      const savedModel = model && entry.brand?.key === model.key
        && validPNG(Buffer.from(entry.brand.pngData ?? '', 'base64')) ? entry.brand : null;
      const modelBrand = model && (resolved.get(model.key)?.pngData ? resolved.get(model.key) : savedModel ?? model.verified);
      return { ...entry, brand: modelBrand?.pngData ? modelBrand : organizationBrand,
        ...(model && { organizationBrand }) };
    }) };
  }
  async resolve(brand, acquire, signal) {
    if (brand.saved && validPNG(Buffer.from(brand.saved.pngData ?? '', 'base64'))) return brand.saved;
    const previous = await this.store.readBrand(brand.key);
    const publicValue = async record => {
      const colorHex = catalog.colors[brand.key] ?? record?.colorHex ?? fallbackColor(brand.key);
      if (record?.assetHash) {
        const png = await this.store.readBrandPNG(record.assetHash);
        if (validPNG(png)) return { key: brand.key, colorHex, pngData: png.toString('base64'), status: 'ready', sourceURL: record.sourceURL };
      }
      return { key: brand.key, colorHex, status: record?.status === 'ready' ? 'failed' : record?.status ?? 'pending' };
    };
    const cached = await publicValue(previous);
    // A ready provider asset cannot satisfy a model request. A changed model
    // source must also be retried instead of returning its old image forever.
    if (cached.pngData && (brand.scope !== 'model' || previous.sourceURL === brand.sourceURL)
      || !acquire || signal.aborted) return cached;
    const { position, state } = await this.store.readState(`brand-state/${encodeURIComponent(brand.key)}`, 2500);
    const now = this.clock();
    if (state && now < state.nextAttemptAt && state.sourceURL === brand.sourceURL) return publicValue(previous);
    const claim = { sourceURL: brand.sourceURL, attemptedAt: now, nextAttemptAt: now + brandRetryInterval };
    if (signal.aborted || !await this.store.appendState(`brand-state/${encodeURIComponent(brand.key)}`, position, claim, 2500)) return publicValue(previous);
    const record = { key: brand.key, name: brand.name, sourceURL: brand.sourceURL,
      colorHex: catalog.colors[brand.key] ?? fallbackColor(brand.key), status: brand.sourceURL ? 'failed' : 'missing',
      attemptedAt: now, nextRetryAt: claim.nextAttemptAt };
    if (brand.sourceURL) {
      try {
        const timeout = AbortSignal.any([signal, AbortSignal.timeout(2200)]);
        const bytes = await this.download(brand.sourceURL, timeout);
        timeout.throwIfAborted();
        const { png, colorHex } = await this.normalize(bytes);
        timeout.throwIfAborted();
        if (!validPNG(png)) throw new Error('Invalid normalized PNG');
        const assetHash = createHash('sha256').update(png).digest('hex');
        await this.store.writeBrandPNG(assetHash, png);
        Object.assign(record, { assetHash, colorHex: catalog.colors[brand.key] ?? colorHex, status: 'ready' });
      } catch { /* Persist retry state, never a raw upstream error or body. */ }
    }
    // Verified official marks travel with the service too: a regional network
    // failure must not turn a known Wan logo back into Alibaba's logo.
    if (record.status !== 'ready' && brand.verified) {
      const png = Buffer.from(brand.verified.pngData ?? '', 'base64');
      if (validPNG(png)) {
        const assetHash = createHash('sha256').update(png).digest('hex');
        await this.store.writeBrandPNG(assetHash, png);
        Object.assign(record, { assetHash, colorHex: brand.verified.colorHex, status: 'ready' });
      }
    }
    // Keep a previously verified model mark while a replacement URL is offline.
    if (record.status !== 'ready' && cached.pngData) return cached;
    await this.store.writeBrand(brand.key, record);
    return publicValue(record);
  }
}
