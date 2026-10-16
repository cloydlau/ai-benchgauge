import { createHash, randomBytes, timingSafeEqual } from 'node:crypto';
import { replacementFailure } from './domain.mjs';
import { parseBoard, sources } from './parser.mjs';
import { codingKinds, withCodingOpenness } from './model-openness.mjs';

export const refreshInterval = 30 * 60 * 1000;
export const grantLifetime = 90 * 1000;
const digest = token => createHash('sha256').update(token).digest('hex');
export class RequestError extends Error {
  constructor(status, message) { super(message); this.status = status; }
}

// All durable decisions live in OSS, not a process-local lock. AppendObject's
// position precondition makes simultaneous FC instances compete atomically.
export class SharedLeaderboards {
  constructor(store, { clock = Date.now, token = () => randomBytes(32).toString('base64url'), brands = null, countries = null } = {}) {
    this.store = store; this.clock = clock; this.token = token; this.brands = brands; this.countries = countries;
  }
  async enrich(board, options) {
    if (this.brands) board = await this.brands.enrich(board, options);
    if (this.countries) board = await this.countries.enrich(board, options);
    return board;
  }
  async withModelOpenness(board) {
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
    const board = await this.store.readBoard(kind);
    return { board: await this.withModelOpenness(await this.enrich(board)) };
  }
  async refresh(kind) {
    this.checkKind(kind);
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
    board = await this.enrich(board, { acquire: true });
    await this.store.writeBoard(kind, board);
    return { board: await this.withModelOpenness(board) };
  }
}
