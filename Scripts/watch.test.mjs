import assert from 'node:assert/strict'
import { test } from 'node:test'
import { dirtyStatusSignature } from './watch.mjs'

test('saving the same dirty file changes the commit retry signature', () => {
  const status = ' M Sources/example.swift\0'
  const before = dirtyStatusSignature(status, (path) => path === '.git/index' ? 'index-1' : 'file-1')
  const after = dirtyStatusSignature(status, (path) => path === '.git/index' ? 'index-1' : 'file-2')
  assert.notEqual(before, after)
})

test('staging a new version changes the commit retry signature', () => {
  const status = 'M  Sources/example.swift\0'
  const before = dirtyStatusSignature(status, (path) => path === '.git/index' ? 'index-1' : 'file-1')
  const after = dirtyStatusSignature(status, (path) => path === '.git/index' ? 'index-2' : 'file-1')
  assert.notEqual(before, after)
})
