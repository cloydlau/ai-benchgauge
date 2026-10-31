import { loadConfiguredOpenRouterPrices, priceBoard } from './price-catalog.mjs';
import { acquisitionPlan, acquisitionKey, acquisitionKinds, acquisitionOutputs, legacyAcquisitionKey, parseAcquisition, loadPublicSource } from './client-acquisition.mjs';
import { createHash, randomBytes, timingSafeEqual } from 'node:crypto';
import { replacementFailure, resolvedOpenness, withRankChanges, withContentTimestamp } from './domain.mjs';
import { parseBoard, sources } from './parser.mjs';
import { attachGeneralTaskCosts } from './aa-general-cost.mjs';
import { codingKinds, withCodingOpenness } from './model-openness.mjs';
import { isArena, isArenaDataset } from './arena-dataset.mjs';
import { isEpochDomain } from './epoch-domain-loader.mjs';
import { vercelKind, vercelInterval } from './vercel-usage.mjs';
import { cloudbaseKind, cloudbaseInterval } from './cloudbase-usage.mjs';
import { openRouterKind, openRouterInterval } from './openrouter-usage.mjs';

export const refreshInterval = 30 * 60 * 1000;
export const grantLifetime = 90 * 1000;
const digest = token => createHash('sha256').update(token).digest('hex');
export class RequestError extends Error {
  constructor(status, message) { super(message); this.status = status; }
}

// All durable decisions live in OSS, not a process-local lock. AppendObject's
// position precondition makes simultaneous FC instances compete atomically.
export class SharedLeaderboards {
  constructor(store, { clock = Date.now, token = () => randomBytes(32).toString('base64url'), brands = null, countries = null, arenaDataset = null, models = null, openRouterUsage = null, vercelUsage = null, cloudbaseUsage = null, generalCosts = null, epochDomain = null, publicSource = loadPublicSource, priceLoader = loadConfiguredOpenRouterPrices, openRouterConfigured = () => false } = {}) {
    this.store = store; this.clock = clock; this.token = token; this.brands = brands; this.countries = countries; this.arenaDataset = arenaDataset; this.models = models;
    this.cloudbaseUsage = cloudbaseUsage; this.vercelUsage = vercelUsage; this.openRouterUsage = openRouterUsage; this.openRouterConfigured = openRouterConfigured;
    this.priceLoader = priceLoader; this.publicSource = publicSource; this.generalCosts = generalCosts; this.epochDomain = epochDomain;
  }
  async enrich(board, options) {
    if (this.models) board = await this.models.enrich(board, options);
    if (this.brands) board = await this.brands.enrich(board, options);
    if (this.countries) board = await this.countries.enrich(board, options);
    return board;
  }
  async withModelOpenness(board) {
    if (board?.entries) board = { ...board, entries: board.entries.map(entry => {
      const openness = resolvedOpenness(entry);
      return !['open', 'closed'].includes(entry.openness) && openness ? { ...entry, openness } : entry;
    }) };
    if (!codingKinds.has(board?.kind) || board.entries.every(entry => ['open', 'closed'].includes(entry.openness))) return board;
    const kinds = ['artificialAnalysis', 'arenaText', 'codeArenaWebDev'].filter(kind => kind !== board.kind);
    const results = await Promise.allSettled(kinds.map(kind => this.store.readBoard(kind)));
    return withCodingOpenness(board, results.filter(result => result.status === 'fulfilled').map(result => result.value));
  }
  checkKind(kind) {
    if (kind !== 'openRouterPrice' && !Object.hasOwn(sources, kind)) throw new RequestError(404, 'Unknown leaderboard');
  }
  async read(kind) {
    this.checkKind(kind);
    let board = await this.store.readBoard(kind);
    if (this.arenaDataset && isArena(kind) && !isArenaDataset(board)) board = null;
    return { board: await this.withModelOpenness(await this.enrich(board)),
      ...(kind === openRouterKind && !this.openRouterConfigured() && { configurationRequired: true }) };
  }
  async refresh(kind, { clientFirst = false } = {}) {
    this.checkKind(kind);
    if (clientFirst && acquisitionPlan(kind)) return this.claimAcquisition(kind);
    if (kind === 'openRouterPrice') {
      const result = await this.claimAcquisition(kind);
      return result.grant ? this.fallback(kind, result.grant.token) : result;
    }
    if (kind === vercelKind || kind === cloudbaseKind) return this.refreshShareUsage(kind);
    if (kind === openRouterKind) return this.refreshOpenRouter();
    if (this.arenaDataset && isArena(kind)) return this.refreshArena(kind);
    if (isEpochDomain(kind)) return this.refreshEpochDomain(kind);
    const cached = await this.store.readBoard(kind);
    const board = await this.withModelOpenness(await this.enrich(cached, { acquire: true }));
    // Failure to coordinate must NOT give permission to contact the source.
    try {
      if (kind === 'epochECI') {
        const { nextAttemptAt } = await this.acquisitionState(kind);
        if (this.clock() < nextAttemptAt) return { board, retryAt: nextAttemptAt };
      }
      const { position, state } = await this.store.readState(kind);
      const now = this.clock();
      if (state && now < state.nextAttemptAt) return { board, retryAt: state.nextAttemptAt };
      const token = this.token();
      const grant = { hash: digest(token), issuedAt: now, expiresAt: now + grantLifetime,
        // Include the entire request-start window to guarantee a minimum
        // thirty-minute separation even when the winning client starts late.
        nextAttemptAt: now + grantLifetime + refreshInterval, consumed: false };
      if (!await this.store.appendState(kind, position, grant)) return { board };
      if (this.clock() >= grant.expiresAt) return { board, retryAt: grant.nextAttemptAt };
      return { board, grant: { token, expiresAt: grant.expiresAt, sourceURL: sources[kind][0] }, retryAt: grant.nextAttemptAt };
    } catch {
      if (board) return { board };
      throw new RequestError(503, 'Shared refresh temporarily unavailable');
    }
  }
  async acquisitionState(kind) {
    const key = acquisitionKey(kind);
    const records = await Promise.all(acquisitionKinds(kind).map(async member => {
      const memberKey = legacyAcquisitionKey(member);
      return { key: memberKey, ...await this.store.readState(memberKey) };
    }));
    const current = records.find(record => record.key === key);
    // Honour every pre-grouping cooldown/lease during migration. New decisions
    // always append to the canonical member's existing CAS log.
    let nextAttemptAt = Math.max(0, ...records.map(record => record.state?.nextAttemptAt ?? 0));
    if (kind === 'epochECI') {
      const { state } = await this.store.readState(acquisitionKey('epochMathECI'));
      const cached = await this.store.readBoard(kind);
      // Only inherit the domain cooldown after its already-downloaded general
      // score CSV was published. A pending/failed domain must not block general.
      if (state && Date.parse(cached?.fetchedAt) >= state.issuedAt) nextAttemptAt = Math.max(nextAttemptAt, state.nextAttemptAt);
    }
    return { ...current, nextAttemptAt };
  }
  async claimAcquisition(kind) {
    const { board } = await this.read(kind);
    try {
      const { key, position, nextAttemptAt } = await this.acquisitionState(kind), now = this.clock();
      if (now < nextAttemptAt) return { board, retryAt: nextAttemptAt };
      const token = this.token(), daily = [vercelKind, cloudbaseKind].includes(kind), interval = daily ? 600000 : refreshInterval;
      const next = { hash: digest(token), issuedAt: now, expiresAt: now + grantLifetime,
        nextAttemptAt: now + grantLifetime + interval, ...(daily && { successNextAttemptAt: now + grantLifetime + vercelInterval }), consumed: false, clientFirst: true, kind };
      if (!await this.store.appendState(key, position, next)) return { board };
      if (this.clock() >= next.expiresAt) return { board, retryAt: next.nextAttemptAt };
      return { board, retryAt: next.nextAttemptAt, grant: { token, expiresAt: next.expiresAt,
        sourceURL: acquisitionPlan(kind).resources[0].url, acquisition: acquisitionPlan(kind) } };
    } catch {
      if (board) return { board };
      throw new RequestError(503, 'Shared refresh temporarily unavailable');
    }
  }
  async acquisitionGrant(kind, token) {
    this.checkKind(kind);
    if (!acquisitionPlan(kind) || !/^[A-Za-z0-9_-]{43}$/.test(token ?? '')) throw new RequestError(403, 'Invalid grant');
    // Bind the lease to its requesting route, even though siblings share a log.
    // Still accept an unexpired client-first lease from a pre-grouping log.
    for (const key of new Set([acquisitionKey(kind), legacyAcquisitionKey(kind)])) {
      const { position, state } = await this.store.readState(key);
      if (state?.clientFirst && !state.consumed && this.clock() < state.expiresAt
        && (state.kind ? state.kind === kind : key === legacyAcquisitionKey(kind))
        && timingSafeEqual(Buffer.from(digest(token)), Buffer.from(state.hash))) return { key, position, state };
    }
    throw new RequestError(403, 'Expired or consumed grant');
  }
  async commitAcquisition(kind, board, previous, { completeGeneralMetrics = false } = {}) {
    const { relatedBoards = [], ...primary } = board ?? {};
    board = primary;
    if (board?.kind !== kind || !board.entries?.length || replacementFailure(board, previous)) throw new RequestError(409, 'Invalid or older snapshot');
    if (kind === 'artificialAnalysis') {
      let costs = previous;
      try { if (this.generalCosts && !completeGeneralMetrics) costs = await this.generalCosts({ now: this.clock() }); } catch { /* Preserve matching cached costs. */ }
      const supplemented = attachGeneralTaskCosts(board, costs);
      // The models page already includes scores, costs and speed. Preserve
      // matching cached gaps without replacing fresh metrics or fetching it twice.
      board = completeGeneralMetrics ? { ...board, entries: board.entries.map((entry, i) => ({ ...supplemented.entries[i], ...entry })) } : supplemented;
    }
    board = withContentTimestamp(withRankChanges(await this.enrich(board, { acquire: true }), previous), previous);
    await this.store.writeBoard(kind, board);
    await this.models?.queue?.(board);
    const allowed = new Set(acquisitionOutputs(kind).filter(candidate => candidate !== kind));
    for (const related of relatedBoards) {
      if (!allowed.delete(related?.kind)) continue;
      try {
        const { relatedBoards: ignored, ...snapshot } = related;
        await this.commitAcquisition(snapshot.kind, snapshot, await this.store.readBoard(snapshot.kind));
      } catch { /* Each category retains its own valid snapshot on parse/write/rollback failure. */ }
    }
    return { board: await this.withModelOpenness(board) };
  }
  async acquire(kind, token, payload) {
    const { key, position, state } = await this.acquisitionGrant(kind, token);
    let board;
    try { board = await parseAcquisition(kind, payload, this.clock()); }
    catch { throw new RequestError(422, 'Invalid official source bundle'); }
    const previous = (await this.read(kind)).board;
    if (replacementFailure(board, previous)) throw new RequestError(409, 'Older snapshot');
    if (this.clock() >= state.expiresAt || !await this.store.appendState(key, position, { ...state, consumed: true, nextAttemptAt: state.successNextAttemptAt ?? state.nextAttemptAt })) throw new RequestError(409, 'Contribution already submitted');
    return this.commitAcquisition(kind, board, previous, { completeGeneralMetrics: kind === 'artificialAnalysis' });
  }
  async fallback(kind, token) {
    const { key, position, state } = await this.acquisitionGrant(kind, token);
    // Consume before contacting the origin: concurrent fallbacks or uploads
    // cannot trigger a second acquisition or reset the source cooldown.
    if (!await this.store.appendState(key, position, { ...state, consumed: true, nextAttemptAt: state.successNextAttemptAt ?? state.nextAttemptAt })) throw new RequestError(409, 'Acquisition already started');
    const previous = (await this.read(kind)).board;
    try {
      const now = this.clock();
      // Slow coordination/cache reads must never start an origin request after
      // the lease window used to reserve the following cooldown.
      if (now >= state.expiresAt) throw new Error('Acquisition lease expired');
      let board;
      if (kind === 'openRouterPrice') board = priceBoard(kind, await this.priceLoader({ now }));
      else if (isArena(kind)) board = await this.arenaDataset(kind, { now, includeRelated: true });
      else if (isEpochDomain(kind)) board = await this.epochDomain(kind, { now, includeRelated: true });
      else if (kind === vercelKind) board = await this.vercelUsage({ now });
      else if (kind === cloudbaseKind) board = await this.cloudbaseUsage({ now });
      else board = await this.publicSource(kind, { now });
      if (isArena(kind) && !isArenaDataset(board)) throw new Error('Invalid dataset');
      return await this.commitAcquisition(kind, board, previous, { completeGeneralMetrics: kind === 'artificialAnalysis' });
    } catch {
      // Preserve public-usage failure backoff. An abandoned client lease must
      // not prevent every other user from refreshing for an entire day.
      if (state.successNextAttemptAt) {
        try {
          const latest = await this.store.readState(key);
          if (latest.state?.hash === state.hash && latest.state.consumed) {
            await this.store.appendState(key, latest.position, { ...latest.state, nextAttemptAt: this.clock() + 600000 });
          }
        } catch { /* A storage failure never authorizes another origin request. */ }
      }
      if (previous) return { board: previous };
      throw new RequestError(503, 'Source temporarily unavailable');
    }
  }
  async contribute(kind, token, html) {
    this.checkKind(kind);
    if (isEpochDomain(kind)) throw new RequestError(403, 'Epoch domain uses official data');
    if (kind === openRouterKind || kind === vercelKind || kind === cloudbaseKind) throw new RequestError(403, 'Usage uses the official API; contributions disabled');
    if (this.arenaDataset && isArena(kind)) throw new RequestError(403, 'Arena uses the official dataset; contributions disabled');
    if (typeof token !== 'string' || !/^[A-Za-z0-9_-]{43}$/.test(token)) throw new RequestError(403, 'Invalid grant');
    const { position, state } = await this.store.readState(kind);
    const now = this.clock();
    if (!state || state.consumed || now >= state.expiresAt
      || !timingSafeEqual(Buffer.from(digest(token)), Buffer.from(state.hash))) throw new RequestError(403, 'Expired or consumed grant');
    let board;
    try { board = parseBoard(kind, html, now); }
    catch { throw new RequestError(422, 'Incomplete or invalid source HTML'); }
    const previous = await this.store.readBoard(kind);
    const stale = replacementFailure(board, previous);
    if (stale === 'source') throw new RequestError(409, 'Older source data');
    if (stale) throw new RequestError(409, 'Older snapshot');
    // Consume the grant before writing: concurrent/replayed contributions can
    // never both publish. A failed write preserves the previous snapshot.
    if (this.clock() >= state.expiresAt || !await this.store.appendState(kind, position, { ...state, consumed: true })) {
      throw new RequestError(409, 'Contribution already submitted');
    }
    if (kind === 'artificialAnalysis') {
      // Preserve known prices only for identical scores if the supplemental source is temporarily unavailable.
      let costs = previous;
      if (this.generalCosts) {
        try { costs = await this.generalCosts({ now: this.clock() }); } catch { /* Keep the matching cached value. */ }
      }
      board = attachGeneralTaskCosts(board, costs);
    }
    board = await this.enrich(board, { acquire: true });
    board = withContentTimestamp(withRankChanges(board, previous), previous);
    await this.store.writeBoard(kind, board);
    await this.models?.queue?.(board);
    return { board: await this.withModelOpenness(board) };
  }

  async refreshEpochDomain(kind) {
    const cached = (await this.read(kind)).board;
    try {
      const { key, position, nextAttemptAt: retryAt } = await this.acquisitionState(kind);
      const now = this.clock();
      if (now < retryAt) return { board: cached, retryAt };
      const nextAttemptAt = now + refreshInterval;
      if (!await this.store.appendState(key, position, { issuedAt: now, nextAttemptAt })) return { board: cached };
      if (!this.epochDomain) throw new Error('Epoch domain loader unavailable');
      let board = await this.epochDomain(kind, { now, includeRelated: true });
      if (board?.kind !== kind || !board.entries?.length || replacementFailure(board, cached)) throw new Error('Invalid Epoch snapshot');
      return { ...await this.commitAcquisition(kind, board, cached), retryAt: nextAttemptAt };
    } catch {
      if (cached) return { board: cached };
      throw new RequestError(503, 'Epoch domain temporarily unavailable');
    }
  }

  async refreshArena(kind) {
    const cached = (await this.read(kind)).board;
    // A separate coordination namespace lets migration replace a website cache
    // without inheriting its client grant or mislabelling it as CC-licensed data.
    try {
      const { key, position, nextAttemptAt: retryAt } = await this.acquisitionState(kind);
      const now = this.clock();
      if (now < retryAt) return { board: await this.enrich(cached, { acquire: true }), retryAt };
      const nextAttemptAt = now + refreshInterval;
      if (!await this.store.appendState(key, position, { issuedAt: now, nextAttemptAt })) return { board: cached };
      let board = await this.arenaDataset(kind, { now, includeRelated: true });
      if (!isArenaDataset(board) || board.kind !== kind || replacementFailure(board, cached)) throw new Error('Invalid or older dataset');
      return { ...await this.commitAcquisition(kind, board, cached), retryAt: nextAttemptAt };
    } catch {
      if (cached) return { board: cached };
      throw new RequestError(503, 'Arena dataset temporarily unavailable');
    }
  }

  async refreshOpenRouter() {
    const { board: cached } = await this.read(openRouterKind);
    if (!this.openRouterConfigured()) return { board: cached, configurationRequired: true };
    try {
      const key = 'openrouter-api/usage';
      const { position, state } = await this.store.readState(key);
      const now = this.clock();
      if (state && now < state.nextAttemptAt) return { board: cached, retryAt: state.nextAttemptAt };
      const nextAttemptAt = now + openRouterInterval;
      // Durable coordination limits the entire application to 24 calls/day.
      if (!await this.store.appendState(key, position, { issuedAt: now, nextAttemptAt })) return { board: cached };
      let board = await this.openRouterUsage({ now });
      if (board?.kind !== openRouterKind || !board.entries?.length || replacementFailure(board, cached)) throw new Error('Invalid or older usage snapshot');
      board = await this.withModelOpenness(await this.enrich(board, { acquire: true }));
      board = withContentTimestamp(withRankChanges(board, cached), cached);
      await this.store.writeBoard(openRouterKind, board);
      await this.models?.queue?.(board);
      return { board, retryAt: nextAttemptAt };
    } catch {
      if (cached) return { board: cached };
      throw new RequestError(503, 'OpenRouter usage temporarily unavailable');
    }
  }
  async refreshShareUsage(kind) {
    const tencent = kind === cloudbaseKind;
    const load = tencent ? this.cloudbaseUsage : this.vercelUsage;
    const interval = tencent ? cloudbaseInterval : vercelInterval;
    const { board: cached } = await this.read(kind);
    const key = tencent ? 'cloudbase-document/usage' : 'vercel-export/usage';
    let issuedAt;
    try {
      const { position, state } = await this.store.readState(key);
      const now = this.clock();
      if (state && now < state.nextAttemptAt) return { board: cached, retryAt: state.nextAttemptAt };
      const nextAttemptAt = now + interval;
      // Durable coordination limits the entire application to one acquisition/source/day.
      if (!await this.store.appendState(key, position, { issuedAt: now, nextAttemptAt })) return { board: cached };
      issuedAt = now;
      let board = await load({ now });
      if (board?.kind !== kind || !board.entries?.length || replacementFailure(board, cached)) throw new Error('Invalid or older usage snapshot');
      board = await this.enrich(board, { acquire: true });
      board = withContentTimestamp(withRankChanges(board, cached), cached);
      await this.store.writeBoard(kind, board);
      await this.models?.queue?.(board);
      return { board, retryAt: nextAttemptAt };
    } catch {
      if (issuedAt != null) {
        try {
          const { position, state } = await this.store.readState(key);
          if (state?.issuedAt === issuedAt) await this.store.appendState(key, position, { ...state, nextAttemptAt: this.clock() + 600000 });
        } catch { /* Storage failure must not trigger an uncoordinated source call. */ }
      }
      if (cached) return { board: cached };
      throw new RequestError(503, `${tencent ? 'Tencent' : 'Vercel'} usage temporarily unavailable`);
    }
  }
}
