import { readFileSync } from 'node:fs';
import brandCatalog from './brand-catalog.json' with { type: 'json' };
import policy from './leaderboard-policy.json' with { type: 'json' };
import { brandKey, normalizedBrandKey } from './brands.mjs';
import { normalizedCountryCode } from './domain.mjs';

const catalog = JSON.parse(readFileSync(new URL('./country-catalog.json', import.meta.url)));
const names = new Intl.DisplayNames(['en'], { type: 'region', fallback: 'none' });
const excluded = new Set(['EU', 'UN', 'ZZ', 'XA', 'XB', 'QO']);
export const countryRetryInterval = 30 * 60 * 1000;
export function countryCode(value) {
  if (typeof value !== 'string') return null;
  const code = normalizedCountryCode(value);
  return code && !excluded.has(code) && names.of(code) ? code : null;
}
const canonicalCountry = record => {
  const code = countryCode(record?.countryCode);
  return code && code !== record.countryCode ? { ...record, countryCode: code } : record;
};
const identity = value => String(value ?? '').toLowerCase().replace(/[^\p{L}\p{N}]/gu, '');
function hostname(value) {
  try { const url = new URL(value); return url.protocol === 'https:' ? url.hostname.replace(/^www\./, '') : null; }
  catch { return null; }
}
// Ignore deprecated and ended statements; prefer an explicitly current HQ.
function values(entity, property) {
  const claims = (entity?.claims?.[property] ?? []).filter(claim => claim.rank !== 'deprecated'
    && !claim.qualifiers?.P582?.length && claim.mainsnak?.snaktype === 'value');
  const current = claims.some(claim => claim.rank === 'preferred') ? claims.filter(claim => claim.rank === 'preferred') : claims;
  return current.map(claim => claim.mainsnak.datavalue?.value).filter(value => value !== undefined);
}
const entityIDs = (entity, property) => values(entity, property).map(value => value.id).filter(id => /^Q\d+$/.test(id));
export async function discoverCountry(entry, { fetcher = fetch, signal } = {}) {
  const json = async url => {
    const response = await fetcher(url, { signal, redirect: 'error', headers: {
      Accept: 'application/json', 'User-Agent': 'BenchGauge/1.0 (developer headquarters lookup)',
    } });
    if (!response.ok || Number(response.headers.get('content-length')) > 1024 * 1024) throw new Error('Country source unavailable');
    const chunks = []; let size = 0;
    for await (const chunk of response.body ?? []) {
      signal?.throwIfAborted(); size += chunk.length;
      if (size > 1024 * 1024) throw new Error('Country source too large');
      chunks.push(chunk);
    }
    return JSON.parse(Buffer.concat(chunks).toString('utf8'));
  };
  const cache = new Map();
  const entity = id => {
    if (!/^Q\d+$/.test(id)) throw new Error('Invalid entity');
    if (!cache.has(id)) cache.set(id, json(`https://www.wikidata.org/wiki/Special:EntityData/${id}.json`).then(data => data.entities?.[id]));
    return cache.get(id);
  };
  // Fixed public endpoints only. Source-provided homepages are used for
  // identity matching, never fetched (no private-network or tracking URLs).
  const result = await json(`https://www.wikidata.org/w/api.php?action=wbsearchentities&search=${encodeURIComponent(entry.organization)}&language=en&format=json&limit=50&maxlag=5`);
  if (!Array.isArray(result.search)) throw new Error('Invalid entity search');
  const expected = identity(entry.organization), website = hostname(entry.organizationWebsite);
  const matches = [];
  const candidates = result.search.filter(hit => !hit.label || identity(hit.match?.text ?? hit.label) === expected);
  if (candidates.length > 5) return { status: 'ambiguous' };
  for (const hit of candidates) {
    if (!/^Q\d+$/.test(hit.id)) continue;
    const candidate = await entity(hit.id);
    const labels = [...Object.values(candidate?.labels ?? {}), ...Object.values(candidate?.aliases ?? {}).flat()].map(item => identity(item.value));
    if (!labels.includes(expected) || !values(candidate, 'P856').length) continue;
    if (entityIDs(candidate, 'P31').some(id => ['Q5', 'Q6256', 'Q515'].includes(id))) continue;
    if (website && !values(candidate, 'P856').some(value => hostname(value) === website)) continue;
    matches.push(candidate);
  }
  if (matches.length !== 1) return { status: matches.length ? 'ambiguous' : 'missing' };
  const company = matches[0], countries = new Set();
  const headquarters = entityIDs(company, 'P159');
  if (!headquarters.length) return { status: 'missing' };
  for (const locationID of headquarters) {
    const location = await entity(locationID);
    const locations = values(location, 'P297').length ? [location] : await Promise.all(entityIDs(location, 'P17').map(entity));
    for (const locationCountry of locations) for (const value of values(locationCountry, 'P297')) {
      const code = countryCode(value); if (code) countries.add(code);
    }
  }
  if (countries.size !== 1) return { status: countries.size ? 'ambiguous' : 'missing' };
  return { status: 'ready', countryCode: [...countries][0], source: 'wikidata', sourceURL: `https://www.wikidata.org/wiki/${company.id}` };
}

export class CountryRegistry {
  constructor(store, { clock = Date.now, discover = discoverCountry, budget = 6000 } = {}) {
    this.store = store; this.clock = clock; this.discover = discover; this.budget = budget;
  }
  async enrich(board, { acquire = false } = {}) {
    if (!board?.entries) return board;
    // Exact, verified model identities repair old source rows with no developer.
    // Do not infer ownership from a loose family prefix or override a source owner.
    board = { ...board, entries: board.entries.map(entry => {
      // Verified spelling aliases describe the same owner. Emit its canonical
      // name so older clients can validate the country key without new aliases.
      const canonicalName = brandCatalog.organizationNames?.[identity(entry.organization)];
      if (canonicalName && normalizedBrandKey(canonicalName) === normalizedBrandKey(entry.organization)) {
        return { ...entry, organization: canonicalName };
      }
      const name = String(entry.name ?? '').trim().toLowerCase();
      const key = Object.prototype.hasOwnProperty.call(brandCatalog.modelDevelopers, name)
        ? brandCatalog.modelDevelopers[name] : null;
      return !entry.organization?.trim() && key && policy.companyNames[key]
        ? { ...entry, organization: policy.companyNames[key] } : entry;
    }) };
    const signal = AbortSignal.timeout(this.budget), records = new Map();
    const grouped = new Map();
    for (const entry of board.entries) {
      const key = brandKey(entry);
      if (!key) continue;
      const previous = grouped.get(key);
      // A sibling can carry metadata that a newer row omits.
      if (!previous || entry.countryHint?.key === key && countryCode(entry.countryHint.countryCode)
          || !previous.countryHint && entry.developerCountry?.key === key && countryCode(entry.developerCountry.countryCode)) grouped.set(key, entry);
    }
    const jobs = [...grouped.entries()];
    let index = 0;
    const worker = async () => {
      while (index < jobs.length && !signal.aborted) {
        const [key, entry] = jobs[index++];
        try { records.set(key, await this.resolve(key, entry, acquire && !signal.aborted, signal)); }
        catch { records.set(key, { key, status: 'pending' }); }
      }
    };
    await Promise.all([worker(), worker()]);
    return { ...board, entries: board.entries.map(entry => {
      const key = brandKey(entry), known = catalog[key], saved = entry.developerCountry;
      const fallback = countryCode(known?.countryCode) ? { key, status: 'ready', ...known }
        : saved?.key === key && countryCode(saved.countryCode) ? saved : { key: key ?? '', status: key ? 'pending' : 'missing' };
      return { ...entry, ...(entry.countryHint && { countryHint: canonicalCountry(entry.countryHint) }),
        developerCountry: canonicalCountry(records.get(key) ?? fallback) };
    }) };
  }
  async resolve(key, entry, acquire, signal) {
    const known = catalog[key];
    // Fresh verified catalog values can correct older shared records at read.
    if (countryCode(known?.countryCode)) return canonicalCountry({ key, status: 'ready', ...known });
    const hint = entry.countryHint;
    if (hint?.key === key && countryCode(hint.countryCode)) {
      const record = { key, countryCode: countryCode(hint.countryCode), status: 'ready', source: 'upstream', retrievedAt: new Date(this.clock()).toISOString() };
      if (acquire) try { await this.store.writeCountry(key, record); } catch { /* Still show source metadata. */ }
      return record;
    }
    let cached;
    try { cached = await this.store.readCountry(key); } catch { /* Preserve snapshot country on an OSS outage. */ }
    const saved = entry.developerCountry;
    if (!cached && saved?.key === key && countryCode(saved.countryCode)) cached = saved;
    if (cached?.key !== key) cached = null;
    if (countryCode(cached?.countryCode)) return canonicalCountry(cached);
    if (!acquire || cached?.nextAttemptAt > this.clock()) return cached ?? { key, status: 'pending' };
    // A harness's developer is the lead model; never search the harness under
    // a hosted-model key. Known hosted developers are handled by the catalog.
    if (normalizedBrandKey(entry.organization) !== key) return cached ?? { key, status: 'missing' };
    try {
      const { position, state } = await this.store.readState(`countries/${key}`, 1500);
      if (state?.nextAttemptAt > this.clock()) return cached ?? { key, status: 'pending' };
      if (signal.aborted) return cached ?? { key, status: 'pending' };
      const now = this.clock(), nextAttemptAt = now + countryRetryInterval;
      if (!await this.store.appendState(`countries/${key}`, position, { nextAttemptAt }, 1500)) return cached ?? { key, status: 'pending' };
      let found;
      try { found = await this.discover(entry, { signal }); }
      catch { found = { status: 'failed' }; }
      const code = countryCode(found.countryCode);
      const record = { key, status: code ? 'ready' : ['missing', 'ambiguous', 'failed'].includes(found.status) ? found.status : 'missing',
        ...(code && { countryCode: code, source: found.source, sourceURL: found.sourceURL }), retrievedAt: new Date(now).toISOString(), nextAttemptAt };
      try { await this.store.writeCountry(key, record); } catch { /* Return resolved metadata even if caching failed. */ }
      return record;
    } catch { return cached ?? { key, status: 'pending' }; }
  }
}
