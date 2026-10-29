import { createHash, randomBytes, timingSafeEqual } from 'node:crypto';
import { replacementFailure, resolvedOpenness, withRankChanges, withContentTimestamp } from './domain.mjs';
import { parseBoard, sources } from './parser.mjs';
import { attachGeneralTaskCosts } from './aa-general-cost.mjs';
import { codingKinds, withCodingOpenness } from './model-openness.mjs';
import { isArena, isArenaDataset } from './arena-dataset.mjs';
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
  constructor(store, { clock = Date.now, token = () => randomBytes(32).toString('base64url'), brands = null, countries = null, arenaDataset = null, models = null, openRouterUsage = null, vercelUsage = null, cloudbaseUsage = null, generalCosts = null, openRouterConfigured = () => false } = {}) {
    this.store = store; this.clock = clock; this.token = token; this.brands = brands; this.countries = countries; this.arenaDataset = arenaDataset; this.models = models;
    this.cloudbaseUsage = cloudbaseUsage; this.vercelUsage = vercelUsage; this.openRouterUsage = openRouterUsage; this.openRouterConfigured = openRouterConfigured;
    this.generalCosts = generalCosts;
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
    if (!Object.hasOwn(sources, kind)) throw new RequestError(404, 'Unknown leaderboard');
  }
  async read(kind) {
    this.checkKind(kind);
    let board = await this.store.readBoard(kind);
    if (this.arenaDataset && isArena(kind) && !isArenaDataset(board)) board = null;
    return { board: await this.withModelOpenness(await this.enrich(board)),
      ...(kind === openRouterKind && !this.openRouterConfigured() && { configurationRequired: true }) };
  }
  async refresh(kind) {
    this.checkKind(kind);
    if (kind === vercelKind || kind === cloudbaseKind) return this.refreshShareUsage(kind);
    if (kind === openRouterKind) return this.refreshOpenRouter();
    if (this.arenaDataset && isArena(kind)) return this.refreshArena(kind);
    const cached = await this.store.readBoard(kind);
    const board = await this.withModelOpenness(await this.enrich(cached, { acquire: true }));
    // Failure to coordinate must NOT give permission to contact the source.
    try {
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
  async contribute(kind, token, html) {
    this.checkKind(kind);
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

  async refreshArena(kind) {
    const cached = (await this.read(kind)).board;
    // A separate coordination namespace lets migration replace a website cache
    // without inheriting its client grant or mislabelling it as CC-licensed data.
    const key = `arena-dataset/${kind}`;
    try {
      const { position, state } = await this.store.readState(key);
      const now = this.clock();
      if (state && now < state.nextAttemptAt) return { board: await this.enrich(cached, { acquire: true }), retryAt: state.nextAttemptAt };
      const nextAttemptAt = now + refreshInterval;
      if (!await this.store.appendState(key, position, { issuedAt: now, nextAttemptAt })) return { board: cached };
      let board = await this.arenaDataset(kind, { now });
      if (!isArenaDataset(board) || board.kind !== kind || replacementFailure(board, cached)) throw new Error('Invalid or older dataset');
      // Complete acquisition is committed atomically; failures retain the old dataset.
      board = await this.enrich(board, { acquire: true });
      board = withContentTimestamp(withRankChanges(board, cached), cached);
      await this.store.writeBoard(kind, board);
      await this.models?.queue?.(board);
      return { board: await this.withModelOpenness(board), retryAt: nextAttemptAt };
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
