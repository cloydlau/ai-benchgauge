import assert from 'node:assert/strict'
import test from 'node:test'
import { chmodSync, mkdirSync, mkdtempSync, realpathSync, rmSync, symlinkSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { delimiter, join } from 'node:path'

import { nodeExecutable, nodeOnPath } from './node-executable.mjs'

test('keeps the running executable while it still exists', () => {
  assert.equal(nodeExecutable({ env: {}, execPath: process.execPath }), process.execPath)
})

test('an explicit override wins over both the runtime and PATH', () => {
  assert.equal(nodeExecutable({ env: { BENCHGAUGE_NODE: '/opt/node' }, execPath: process.execPath }), '/opt/node')
})

test('a deleted runtime falls back to the real node on PATH', (t) => {
  const root = mkdtempSync(join(tmpdir(), 'benchgauge-node-'))
  t.after(() => rmSync(root, { recursive: true, force: true }))
  const real = join(root, 'real-node')
  writeFileSync(real, '#!/bin/sh\n')
  chmodSync(real, 0o755)
  const bin = join(root, 'bin')
  mkdirSync(bin)
  symlinkSync(real, join(bin, 'node'))
  const env = { PATH: [bin, join(root, 'nowhere')].join(delimiter) }
  assert.equal(nodeOnPath(env), realpathSync(real))
  assert.equal(nodeExecutable({ env, execPath: join(root, 'deleted-runtime', 'node') }), realpathSync(real))
})

test('without any usable node the original path stays so the failure is explicit', () => {
  assert.equal(nodeExecutable({ env: { PATH: '' }, execPath: '/gone/node' }), '/gone/node')
  assert.equal(nodeExecutable({ env: {}, execPath: '' }), 'node')
})
