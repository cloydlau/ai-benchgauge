import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import { copyFileSync, existsSync, readFileSync, mkdtempSync, mkdirSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import test from 'node:test'

function fixture(t) {
  const root = mkdtempSync(join(tmpdir(), 'benchgauge-gates-'))
  mkdirSync(join(root, 'Scripts'))
  // Packaging validates the release config before reaching this fixture's gate.
  // Config validation itself is covered in app-config.test.mjs.
  writeFileSync(join(root, 'Scripts', 'validate-app-config.mjs'), '')
  writeFileSync(join(root, 'Scripts', 'prepare-swift-workspace.mjs'), '')
  const original = dirname(fileURLToPath(import.meta.url))
  t.after(() => rmSync(root, { recursive: true, force: true }))
  return { root, original, env: { ...process.env, DESKTOP_NOTIFY: '0', COMMIT_PUSH: '0', COMMIT_CODEX_MESSAGE: '0' } }
}

test('standalone packaging stops before Swift build when the test gate fails', (t) => {
  const { root, original, env } = fixture(t)
  copyFileSync(join(original, 'make-app.sh'), join(root, 'Scripts', 'make-app.sh'))
  writeFileSync(join(root, 'Scripts', 'validate-app-config.mjs'), '')
  writeFileSync(join(root, 'Scripts', 'test.mjs'), "process.exitCode = 1")
  mkdirSync(join(root, 'bin'))
  writeFileSync(join(root, 'bin', 'swift'), '#!/bin/sh\ntouch unexpected-build\n', { mode: 0o755 })
  const result = spawnSync('zsh', [join(root, 'Scripts', 'make-app.sh')], { cwd: root, env: { ...env, PATH: join(root, 'bin') + ':' + env.PATH }, encoding: 'utf8' })
  assert.equal(result.status, 1)
  assert.equal(existsSync(join(root, 'unexpected-build')), false)
  assert.equal(existsSync(join(root, 'outputs')), false)
})


test('configured tests=false skips the packaging test gate and still reports build failures', (t) => {
  const { root, original, env } = fixture(t)
  for (const name of ['make-app.sh', 'ci-build.mjs', 'calmmit.mjs']) copyFileSync(join(original, name), join(root, 'Scripts', name))
  const current = JSON.parse(readFileSync(join(original, '../calmmit.config.json'), 'utf8'))
  const config = { preset: 'custom', library: resolve(original, '..', current.library), steps: { tests: false, build: true }, commands: { build: ['node', 'Scripts/ci-build.mjs'] } }
  writeFileSync(join(root, 'calmmit.config.json'), JSON.stringify(config))
  writeFileSync(join(root, 'Scripts/test.mjs'), `import {writeFileSync} from 'node:fs'; export function testInputSignature() { return 'fixture' }; if (process.argv[1]?.endsWith('/Scripts/test.mjs')) { writeFileSync('unexpected-tests', 'ran'); process.exit(44) }`)
  mkdirSync(join(root, 'bin'))
  writeFileSync(join(root, 'bin/swift'), '#!/bin/sh\ntouch attempted-build\nexit 23\n', { mode: 0o755 })
  const result = spawnSync(process.execPath, [join(root, 'Scripts/ci-build.mjs')], { cwd: root, env: { ...env, CALMMIT_CONFIG: join(root, 'calmmit.config.json'), PATH: join(root, 'bin') + ':' + env.PATH }, encoding: 'utf8' })
  assert.equal(result.status, 23, result.stderr)
  assert.equal(existsSync(join(root, 'unexpected-tests')), false)
  assert.equal(existsSync(join(root, 'attempted-build')), true)
})
