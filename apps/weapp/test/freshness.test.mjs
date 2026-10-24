import assert from 'node:assert/strict'
import test from 'node:test'
import { shouldAutoRefresh, automaticRetryInterval, boardFreshnessInterval } from '../src/core/freshness.js'

test('entering a board uses its displayed publication time or fetch fallback at the 24-hour boundary', () => {
  const now = Date.parse('2026-10-24T12:00:00Z')
  for (const age of [boardFreshnessInterval - 1, boardFreshnessInterval, boardFreshnessInterval + 1, -1000]) {
    const timestamp = new Date(now - age).toISOString()
    assert.equal(shouldAutoRefresh({ sourceUpdatedAt: timestamp, fetchedAt: new Date(now).toISOString() }, undefined, now), age >= boardFreshnessInterval)
    assert.equal(shouldAutoRefresh({ fetchedAt: timestamp }, undefined, now), age >= boardFreshnessInterval)
  }
  assert.equal(shouldAutoRefresh({ sourceUpdatedAt: new Date(now).toISOString(), fetchedAt: '2020-01-01T00:00:00Z' }, undefined, now), false)
  assert.equal(shouldAutoRefresh(null, undefined, now), true)
  assert.equal(shouldAutoRefresh({ fetchedAt: 'invalid' }, undefined, now), true)
})

test('an unchanged or failed automatic result backs off without scheduling a retry timer', () => {
  const now = Date.parse('2026-10-24T12:00:00Z')
  for (const board of [null, { fetchedAt: '2020-01-01T00:00:00Z' }]) {
    assert.equal(shouldAutoRefresh(board, now, now), false)
    assert.equal(shouldAutoRefresh(board, now - automaticRetryInterval + 1, now), false)
    assert.equal(shouldAutoRefresh(board, now - automaticRetryInterval, now), true)
    assert.equal(shouldAutoRefresh(board, now + 1, now), true, 'A corrected clock cannot lock out a board')
  }
})
