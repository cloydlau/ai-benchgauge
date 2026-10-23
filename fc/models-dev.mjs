import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { readBounded } from './arena-dataset.mjs';
import { createBrandRules } from './domain.mjs';
import brands from './brand-catalog.json' with { type: 'json' };
import { sources } from './parser.mjs';

export const modelsDevURL = 'https://models.dev/catalog.json?type=all';
export const modelsDevInterval = 24 * 60 * 60 * 1000;
const gapRetryInterval = 6 * 60 * 60 * 1000;
const retryInterval = 15 * 60 * 1000;
const requestsKey = 'models-dev/requests';
const license = readFileSync(new URL('./models-dev-license.txt', import.meta.url), 'utf8');
const { normalizedBrandKey } = createBrandRules(brands);
const object = value => value && typeof value === 'object' && !Array.isArray(value);
const string = value => typeof value === 'string' && value.length > 0 && value.length <= 256 && !/[\x00-\x1f\x7f]/.test(value);
const number = value => Number.isFinite(value) && value >= 0 && value <= 1e9;
const validLimits = value => object(value) && Object.entries(value).every(([key, n]) => ['context', 'input', 'output'].includes(key) && number(n) && Number.isSafeInteger(n) && n > 0);
function attributes(value, excluded = []) {
  const result = Object.fromEntries(Object.entries(value).filter(([key]) => !excluded.includes(key)));
  let nodes = 0;
  const visit = (v, depth = 0) => {
    if (++nodes > 10000 || depth > 10) throw Error('Model details too large');
    if (v === null || typeof v === 'boolean') return;
    if (typeof v === 'number' && Number.isFinite(v) && Math.abs(v) <= 1e15) return;
    if (typeof v === 'string' && v.length <= 16384 && !/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/.test(v)) return;
    if (Array.isArray(v) && v.length <= 500) { v.forEach(item => visit(item, depth + 1)); return; }
    if (object(v)) {
      for (const [key, item] of Object.entries(v)) {
        if (!string(key) || ['__proto__', 'prototype', 'constructor'].includes(key)) throw Error('Invalid detail key');
        visit(item, depth + 1);
      }
      return;
    }
    throw Error('Invalid model details');
  };
  visit(result);
  if (Buffer.byteLength(JSON.stringify(result)) > 128 * 1024) throw Error('Model details too large');
  return result;
}
const validAttributes = value => value == null || object(value) && Boolean(attributes(value));
const limits = value => {
  if (value == null) return {};
  if (!object(value) || Object.values(value).some(n => !number(n) || !Number.isSafeInteger(n))) throw Error('Invalid token limits');
  return Object.fromEntries(['context', 'input', 'output'].filter(k => value[k] > 0).map(k => [k, value[k]]));
};
function cost(value) {
  if (value == null) return undefined;
  if (!object(value) || !number(value.input) || !number(value.output)) throw Error('Invalid token price');
  const result = {};
  for (const key of ['input', 'output', 'reasoning', 'cache_read', 'cache_write', 'input_audio', 'output_audio']) {
    if (value[key] != null) { if (!number(value[key])) throw Error('Invalid price'); result[key] = value[key]; }
  }
  if (value.context_over_200k != null) result.context_over_200k = cost(value.context_over_200k);
  if (value.tiers != null) {
    if (!Array.isArray(value.tiers) || value.tiers.length > 50) throw Error('Invalid price tiers');
    result.tiers = value.tiers.map(t => {
      if (t.tier?.type !== 'context' || !Number.isSafeInteger(t.tier.size) || !number(t.tier.size)) throw Error('Invalid context price tier');
      return { ...cost({ ...t, tiers: undefined }), tier: { type: 'context', size: t.tier.size } };
    });
  }
  return result;
}
export function parseModelsDev(value, { now = Date.now(), revision } = {}) {
  if (!object(value?.models) || !object(value?.providers) || !/^[a-f0-9]{64}$/.test(revision ?? '')) throw Error('Invalid catalog');
  const models = Object.entries(value.models);
  if (models.length < 100 || models.length > 10000 || Object.keys(value.providers).length < 5 || Object.keys(value.providers).length > 2000) throw Error('Incomplete catalog');
  const records = new Map();
  for (const [id, model] of models) {
    if (!string(id) || model.id !== id || !string(model.name) || !id.includes('/')) throw Error('Invalid canonical identity');
    if (model.open_weights != null && typeof model.open_weights !== 'boolean') throw Error('Invalid weight classification');
    if (model.license != null && !string(model.license)) throw Error('Invalid model license');
    records.set(id, { id, name: model.name, limit: limits(model.limit),
      ...(typeof model.open_weights === 'boolean' && { openWeights: model.open_weights }),
      ...(model.license && { license: model.license }),
      ...(string(model.release_date) && { releaseDate: model.release_date }),
      ...(string(model.last_updated) && { lastUpdated: model.last_updated }),
      attributes: attributes(model, ['id', 'name', 'limit', 'open_weights', 'license', 'release_date', 'last_updated']), offers: [] });
  }
  let total = 0;
  for (const [provider, data] of Object.entries(value.providers)) {
    if (!string(provider) || !string(data.name) || !object(data.models)) throw Error('Invalid provider');
    for (const [id, model] of Object.entries(data.models)) {
      if (++total > 50000 || !string(id) || model.id !== id) throw Error('Invalid provider model');
      const canonical = model.canonical_model_id != null
        ? records.get(model.canonical_model_id) : records.get(`${provider}/${id}`);
      if (!canonical) continue; // A provider wrapper alone does not establish canonical identity.
      canonical.offers.push({ provider, providerName: data.name, modelID: id, name: string(model.name) ? model.name : id,
        limit: limits(model.limit), currency: 'USD', unit: 'per-million-tokens',
        ...(model.cost != null && { cost: cost(model.cost) }),
        ...(string(model.status) && { status: model.status }),
        attributes: attributes(model, ['id', 'name', 'canonical_model_id', 'limit', 'cost', 'status']) });
    }
  }
  if (total < 100) throw Error('Incomplete provider catalog');
  return { schemaVersion: 2, source: 'models.dev', sourceURL: modelsDevURL, license,
    fetchedAt: new Date(now).toISOString(), revision, providerCount: Object.keys(value.providers).length,
    models: [...records.values()] };
}
export async function loadModelsDev({ now = Date.now(), fetcher = fetch, signal = AbortSignal.timeout(18000) } = {}) {
  const bytes = await readBounded(await fetcher(modelsDevURL, { signal, redirect: 'error', headers: { Accept: 'application/json' } }), 12 * 1024 * 1024);
  return parseModelsDev(JSON.parse(bytes.toString('utf8')), { now, revision: createHash('sha256').update(bytes).digest('hex') });
}
export function validModelsDev(snapshot, now = Date.now()) {
  try { return [1, 2].includes(snapshot?.schemaVersion) && snapshot.source === 'models.dev' && snapshot.sourceURL === modelsDevURL
    && snapshot.license === license && /^[a-f0-9]{64}$/.test(snapshot.revision ?? '')
    && Number.isSafeInteger(snapshot.providerCount) && snapshot.providerCount >= 5 && snapshot.providerCount <= 2000
    && Number.isFinite(Date.parse(snapshot.fetchedAt)) && Date.parse(snapshot.fetchedAt) <= now + 300000
    && Array.isArray(snapshot.models) && snapshot.models.length >= 100 && snapshot.models.length <= 10000
    && new Set(snapshot.models.map(m => m.id)).size === snapshot.models.length
    && snapshot.models.every(m => string(m.id) && m.id.includes('/') && string(m.name) && validLimits(m.limit)
      && (m.openWeights == null || typeof m.openWeights === 'boolean')
      && validAttributes(m.attributes) && (m.license == null || string(m.license)) && Array.isArray(m.offers) && m.offers.length < 2000
      && m.offers.every(o => string(o.provider) && string(o.providerName) && string(o.modelID) && string(o.name)
        && o.currency === 'USD' && o.unit === 'per-million-tokens' && validLimits(o.limit)
        && validAttributes(o.attributes) && (o.cost == null || Boolean(cost(o.cost)))));
  } catch { return false; }
}
const fold = value => String(value ?? '').normalize('NFKC').toLowerCase().replace(/(\p{L})(\d)/gu, '$1-$2').replace(/(\d)(\p{L})/gu, '$1-$2').match(/[\p{L}\p{N}]+/gu)?.join('-') ?? '';
const inferenceSettings = /\((?:\s*(?:high|xhigh|medium|low|minimal|max|effort|reasoning|default|standard)[\s,/-]*)+\)/gi;
export function modelMatcher(snapshot) {
  const ids = new Map(), names = new Map(), openRouterIDs = new Map(), vercelIDs = new Map();
  const add = (index, key, record) => { if (!key) return; const values = index.get(key) ?? new Set(); values.add(record); index.set(key, values); };
  for (const record of snapshot.models) {
    add(ids, record.id.toLowerCase(), record); add(names, fold(record.name), record);
    add(names, fold(record.id.split('/').slice(1).join('/')), record);
    for (const offer of record.offers) {
      add(ids, `${offer.provider}/${offer.modelID}`.toLowerCase(), record);
      add(names, fold(offer.name), record);
      if (offer.provider === 'vercel') add(vercelIDs, offer.modelID.toLowerCase(), record);
      if (offer.provider === 'openrouter') add(openRouterIDs, offer.modelID.toLowerCase(), record);
    }
  }
  return (entry, kind) => {
    const supplied = String(entry.modelID ?? '').replace(/#arena-rank-\d+$/, '').toLowerCase();
    if (kind === 'cloudbaseUsage') {
      // Older CloudBase snapshots used the documented Z.ai brand alias.
      // Normalize only that complete developer segment, retaining the exact model ID.
      const identity = String(entry.cloudbaseCanonicalID ?? '').toLowerCase().replace(/^zai\//, 'zhipuai/');
      const matches = snapshot.models.filter(record => record.id.toLowerCase() === identity);
      return matches.length === 1 ? matches[0] : null;
    }
    if (kind === 'vercelUsage') {
      const candidates = entry.vercelModelID ? vercelIDs.get(String(entry.vercelModelID).toLowerCase()) : null;
      return candidates?.size === 1 ? [...candidates][0] : null;
    }
    if (kind === 'openRouterUsage') {
      // No name/date/version guessing for permanent OpenRouter build slugs.
      // The optional routable ID comes from OpenRouter's explicit catalog pair.
      const candidates = openRouterIDs.get(supplied)
        ?? openRouterIDs.get(String(entry.openRouterModelID ?? '').toLowerCase());
      return candidates?.size === 1 ? [...candidates][0] : null;
    }
    let candidates = ids.get(supplied);
    if (!candidates) {
      let name = kind === 'artificialAnalysisCodingAgent' ? entry.name.split(' - ').at(-1) : entry.name;
      if (kind === 'artificialAnalysisCodingAgent' && entry.name.startsWith('Claude Code - ') && /^(Sonnet|Opus|Haiku)\s+\d/.test(name)) name = 'Claude ' + name;
      name = name.replace(/\s*\((?:Codex Harness|Claude Code|OpenCode Harness)\)\s*$/i, '');
      candidates = names.get(fold(name)) ?? names.get(fold(name.replace(inferenceSettings, '')));
    }
    if (!candidates) return null;
    // Explicit developer identity may disambiguate, but never override an
    // unambiguous exact canonical ID with a provider/agent organization.
    let matches = [...candidates];
    if (matches.length > 1 && entry.organization) matches = matches.filter(m => normalizedBrandKey(m.id.split('/')[0]) === normalizedBrandKey(entry.organization));
    return matches.length === 1 ? matches[0] : null;
  };
}
// Compare facts rather than download timestamps, raw JSON key order or origin
// hashes. Offers and canonical records have identities; other arrays retain order.
const ordered = value => Array.isArray(value) ? value.map(ordered)
  : object(value) ? Object.fromEntries(Object.keys(value).sort().map(key => [key, ordered(value[key])])) : value;
const recordFacts = record => JSON.stringify(ordered({ ...record,
  offers: [...record.offers].sort((a, b) => `${a.provider}/${a.modelID}`.localeCompare(`${b.provider}/${b.modelID}`)) }));
function sameCatalog(previous, next) {
  if (!previous || previous.schemaVersion !== next.schemaVersion) return false;
  const records = new Map(previous.models.map(record => [record.id, record]));
  let unchanged = previous.sourceURL === next.sourceURL && previous.license === next.license
    && previous.providerCount === next.providerCount && previous.models.length === next.models.length;
  next.models = next.models.map(record => {
    const old = records.get(record.id);
    if (old && recordFacts(old) === recordFacts(record)) return old;
    unchanged = false; return record;
  });
  return unchanged;
}
function gapFingerprint(board, snapshot) {
  const match = snapshot ? modelMatcher(snapshot) : () => null;
  const tokenModel = !/TextTo(?:Image|Video)$/.test(board.kind);
  const gaps = new Set();
  for (const entry of board.entries) {
    const record = match(entry, board.kind);
    if (!record) { gaps.add(`identity:${String(entry.modelID ?? '').replace(/#arena-rank-\d+$/, '').toLowerCase()}:${fold(entry.name)}`); continue; }
    const missing = [];
    if (typeof record.openWeights !== 'boolean') missing.push('weights');
    if (!record.license) missing.push('license');
    if (tokenModel) {
      if (!record.limit.context && !record.offers.some(offer => offer.limit.context)) missing.push('context');
      if (!record.offers.some(offer => number(offer.cost?.input) && number(offer.cost?.output))) missing.push('prices');
    }
    if (missing.length) gaps.add(`${record.id}:${missing.join(',')}`);
  }
  return gaps.size ? createHash('sha256').update([...gaps].sort().join('\n')).digest('hex') : null;
}
export class ModelsDevRegistry {
  constructor(store, { clock = Date.now, load = loadModelsDev, cache = {} } = {}) { this.store = store; this.clock = clock; this.load = load; this.cache = cache; }
  async read() {
    if (this.cache.expires > this.clock()) return this.cache.snapshot;
    try {
      const value = await this.store.readModelsDev();
      if (validModelsDev(value, this.clock())) this.cache.snapshot = value;
    } catch { /* Use the last valid in-memory copy if storage is temporarily unavailable. */ }
    this.cache.expires = this.clock() + 30000;
    return this.cache.snapshot ?? null;
  }
  async queue(board) {
    // Only validated, successfully saved leaderboard updates call this method.
    // The journal contains at most nine compact fingerprints, never model data.
    if (!board || !Object.hasOwn(sources, board.kind)) return;
    try {
      const fingerprint = gapFingerprint(board, await this.read()), now = this.clock();
      for (let attempt = 0; attempt <= Object.keys(sources).length; attempt++) {
        const { position, state } = await this.store.readState(requestsKey, 1000);
        const boards = { ...state?.boards }, old = boards[board.kind];
        if ((!fingerprint && !old) || (fingerprint && old?.fingerprint === fingerprint && (old.pending || old.retryAfter > now))) return;
        if (fingerprint) boards[board.kind] = { fingerprint, queuedAt: now, pending: true };
        else delete boards[board.kind];
        if (await this.store.appendState(requestsKey, position, { boards }, 1000)) return;
      }
    } catch { /* Metadata scheduling must not turn a saved ranking into a failure. */ }
  }
  async acknowledge(requests, now) {
    if (!requests || !Object.keys(requests).length) return;
    for (let attempt = 0; attempt <= Object.keys(sources).length; attempt++) {
      const { position, state } = await this.store.readState(requestsKey, 1000);
      const boards = { ...state?.boards }; let changed = false;
      for (const [kind, request] of Object.entries(requests)) {
        const current = boards[kind];
        // A board that gained a different gap while downloading stays queued.
        if (request.pending && current?.pending && current.fingerprint === request.fingerprint && current.queuedAt === request.queuedAt) {
          boards[kind] = { ...current, pending: false, retryAfter: now + gapRetryInterval }; changed = true;
        }
      }
      if (!changed || await this.store.appendState(requestsKey, position, { boards }, 1000)) return;
    }
  }
  async sync({ pendingOnly = false } = {}) {
    const now = this.clock(); let previous = this.cache.snapshot ?? null;
    this.syncFailed = false;
    try {
      const requests = (await this.store.readState(requestsKey, 1000)).state?.boards ?? {};
      const pending = Object.values(requests).some(request => request.pending);
      if (pendingOnly && !pending) return previous;
      previous = await this.read();
      this.checkedAt = Date.parse(previous?.fetchedAt);
      const { position, state } = await this.store.readState('models-dev');
      this.checkedAt = Math.max(this.checkedAt || 0, state?.checkedAt ?? 0);
      if (!pending && previous?.schemaVersion === 2 && now - this.checkedAt < modelsDevInterval) return previous;
      if (state?.nextAttemptAt > now) return previous;
      if (!await this.store.appendState('models-dev', position, { ...state, nextAttemptAt: now + retryInterval })) return previous;
      const next = await this.load({ now });
      if (!validModelsDev(next, now) || previous && Date.parse(next.fetchedAt) < Date.parse(previous.fetchedAt)
        || previous && next.models.length < previous.models.length * 0.8) throw Error('Invalid or truncated metadata snapshot');
      const unchanged = sameCatalog(previous, next);
      if (!unchanged) await this.store.writeModelsDev(next);
      this.cache.snapshot = unchanged ? previous : next; this.cache.expires = now + 30000;
      const completion = await this.store.readState('models-dev');
      if (!await this.store.appendState('models-dev', completion.position, { nextAttemptAt: now + retryInterval, checkedAt: now })) throw Error('Cannot save metadata check');
      this.checkedAt = now;
      await this.acknowledge(requests, now);
      return this.cache.snapshot;
    } catch { this.syncFailed = true; return this.cache.snapshot ?? previous; }
  }
  async enrich(board) {
    if (!board) return board;
    // Ranking requests only join the saved catalog. The authenticated timer
    // owns upstream acquisition so a slow metadata source cannot delay a grant
    // or exhaust an Arena refresh's function execution budget.
    const snapshot = await this.read();
    if (!snapshot) return board;
    const match = modelMatcher(snapshot);
    return { ...board, modelMetadataSource: { source: 'models.dev', sourceURL: snapshot.sourceURL, license: snapshot.license, revision: snapshot.revision, fetchedAt: snapshot.fetchedAt },
      entries: board.entries.map(entry => {
        const record = match(entry, board.kind);
        const { modelMetadata: old, ...rest } = entry;
        return record ? { ...rest, modelMetadata: { ...record, source: 'models.dev', sourceURL: snapshot.sourceURL,
          revision: snapshot.revision, fetchedAt: snapshot.fetchedAt } }
          : old?.source === 'models.dev' ? rest : entry;
      }) };
  }
}

export async function loadConfiguredModelsDev({ now = Date.now(), fetcher = fetch, environment = process.env } = {}) {
  if (!environment.ARENA_COLLECTOR_ENDPOINT) return loadModelsDev({ now, fetcher });
  const endpoint = new URL(environment.ARENA_COLLECTOR_ENDPOINT);
  if (endpoint.protocol !== 'https:' || endpoint.pathname !== '/' || endpoint.port || endpoint.username || endpoint.password
    || endpoint.search || endpoint.hash || !endpoint.hostname.endsWith('.ap-southeast-1.fcapp.run')
    || !/^[A-Za-z0-9_-]{43}$/.test(environment.ARENA_COLLECTOR_TOKEN ?? '')) throw Error('Invalid collector destination');
  const response = await fetcher(new URL('/v1/models-dev', endpoint), { redirect: 'error', signal: AbortSignal.timeout(22000),
    headers: { 'x-benchgauge-collector-key': environment.ARENA_COLLECTOR_TOKEN } });
  const snapshot = JSON.parse((await readBounded(response, 8 * 1024 * 1024)).toString('utf8'));
  if (!validModelsDev(snapshot, now) || Date.parse(snapshot.fetchedAt) < now - 3600000) throw Error('Invalid collected catalog');
  return snapshot;
}
