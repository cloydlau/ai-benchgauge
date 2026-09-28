import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import { copyFileSync, existsSync, mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import test from 'node:test'

function fixture(t) {
  const root = mkdtempSync(join(tmpdir(), 'benchgauge-gates-'))
  mkdirSync(join(root, 'Scripts'))
  const original = dirname(fileURLToPath(import.meta.url))
  t.after(() => rmSync(root, { recursive: true, force: true }))
  return { root, original, env: { ...process.env, DESKTOP_NOTIFY: '0', COMMIT_PUSH: '0', COMMIT_CODEX_MESSAGE: '0' } }
}

test('standalone packaging stops before Swift build when the test gate fails', (t) => {
  const { root, original, env } = fixture(t)
  copyFileSync(join(original, 'make-app.sh'), join(root, 'Scripts', 'make-app.sh'))
  writeFileSync(join(root, 'Scripts', 'test.mjs'), "process.exitCode = 1")
  mkdirSync(join(root, 'bin'))
  writeFileSync(join(root, 'bin', 'swift'), '#!/bin/sh\ntouch unexpected-build\n', { mode: 0o755 })
  const result = spawnSync('zsh', [join(root, 'Scripts', 'make-app.sh')], { cwd: root, env: { ...env, PATH: join(root, 'bin') + ':' + env.PATH }, encoding: 'utf8' })
  assert.equal(result.status, 1)
  assert.equal(existsSync(join(root, 'unexpected-build')), false)
  assert.equal(existsSync(join(root, 'outputs')), false)
})

test('standalone commit stops before staging or changing history when tests fail', (t) => {
  const { root, original, env } = fixture(t)
  for (const file of ['commit.mjs', 'commit-lock.mjs', 'commit-message.mjs', 'commit-split.mjs', 'desktop-notify.mjs', 'git-network.mjs']) {
    copyFileSync(join(original, file), join(root, 'Scripts', file))
  }
  writeFileSync(join(root, 'Scripts', 'test.mjs'), "export function testInputSignature() { return 'same' }")
  writeFileSync(join(root, 'Scripts', 'test-repair.mjs'), "export async function runTestGate() { return { status: 1, logPath: 'fixture-failure.log' } }")
  writeFileSync(join(root, 'Scripts', 'commit-identity.mjs'), `
export function resolveCommitIdentity() { return { model: 'fixture', author: { name: 'fixture', email: 'fixture@example.com' }, committer: { name: 'fixture', email: 'fixture@example.com' } } }
export async function resolveModelAvatar() { return { url: '', candidates: [] } }
export function formatCommitIdentity() { return 'fixture' }
export function commitIdentityEnv() { return {} }
export function commitArgs() { return [] }
`)
  const git = (args) => {
    const result = spawnSync('git', args, { cwd: root, env, encoding: 'utf8' })
    assert.equal(result.status, 0, result.stderr)
    return result.stdout
  }
  git(['init', '-q']); git(['config', 'user.name', 'fixture']); git(['config', 'user.email', 'fixture@example.com'])
  writeFileSync(join(root, 'example.txt'), 'initial')
  git(['add', 'example.txt']); git(['commit', '-qm', 'initial fixture'])
  const head = git(['rev-parse', 'HEAD'])
  const index = readFileSync(join(root, '.git', 'index'))
  writeFileSync(join(root, 'example.txt'), 'changed')
  const result = spawnSync(process.execPath, [join(root, 'Scripts', 'commit.mjs'), '-m', 'fix(core): fixture'], { cwd: root, env, encoding: 'utf8' })
  assert.equal(result.status, 1)
  assert.match(result.stderr, /测试未通过，提交已停止/)
  assert.equal(git(['rev-parse', 'HEAD']), head)
  assert.deepEqual(readFileSync(join(root, '.git', 'index')), index)
})
