import assert from 'node:assert/strict'
import test from 'node:test'
import { createAutoVersion } from '../scripts/version.mjs'

test('date versions use Shanghai midnight and remain the same throughout a calendar day', () => {
  for (const [instant, expected] of [
    ['2026-10-17T16:00:00.000Z', '20261018'],
    ['2026-10-18T15:59:59.999Z', '20261018'],
    ['2026-10-18T16:00:00.000Z', '20261019'],
    ['2026-12-31T16:00:00.000Z', '20270101'],
    ['2028-02-28T16:00:00.000Z', '20280229'],
    ['2028-02-29T16:00:00.000Z', '20280301'],
  ]) assert.equal(createAutoVersion(new Date(instant)), expected, instant)
  assert.match(createAutoVersion(), /^\d{8}$/)
})
