import { ci } from './calmmit.mjs'
export const { DEFAULT_LOCK_STALE_MS, pidState, acquireCommitLock } = await ci.load('commit-lock')
