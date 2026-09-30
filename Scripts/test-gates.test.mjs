import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import { copyFileSync, existsSync, mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import test from 'node:test'

const HUMAN_EMAIL = '31238760+cloydlau@users.noreply.github.com'
const COMMIT_SCRIPTS = ['commit.mjs', 'commit-lock.mjs', 'commit-message.mjs', 'commit-split.mjs', 'desktop-notify.mjs', 'git-network.mjs', 'media-gate.mjs', 'node-executable.mjs']
// 与真实的 commit-identity.mjs 行为一致，但不读配置、不联网、不取头像。
const IDENTITY_STUB = `
export const HUMAN = Object.freeze({ name: 'Cloyd Lau', email: '${HUMAN_EMAIL}' })
const MODEL = { name: 'gpt-5-codex', email: 'noreply@openai.com' }
export function resolveCommitIdentity() {
  const coauthor = process.env.COMMIT_COAUTHOR === '1'
  return { model: MODEL.name, avatar: { url: '', candidates: [] }, author: { ...MODEL }, committer: coauthor ? { ...HUMAN } : { ...MODEL }, coauthor: coauthor ? { ...HUMAN } : null }
}
export async function resolveModelAvatar() { return { url: '', candidates: [], source: 'fixture', probed: true } }
export function formatCommitIdentity(identity) { return identity.author.name + ' <' + identity.author.email + '>' }
export function commitIdentityEnv(identity) { return { GIT_AUTHOR_NAME: identity.author.name, GIT_AUTHOR_EMAIL: identity.author.email, GIT_COMMITTER_NAME: identity.committer.name, GIT_COMMITTER_EMAIL: identity.committer.email } }
export function commitArgs(message, identity) { return ['-c', 'gc.auto=0', '-c', 'user.name=' + identity.committer.name, '-c', 'user.email=' + identity.committer.email, 'commit', '-m', message, '--author', identity.author.name + ' <' + identity.author.email + '>'] }
`

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
  writeFileSync(join(root, 'Scripts', 'validate-app-config.mjs'), '')
  writeFileSync(join(root, 'Scripts', 'test.mjs'), "process.exitCode = 1")
  mkdirSync(join(root, 'bin'))
  writeFileSync(join(root, 'bin', 'swift'), '#!/bin/sh\ntouch unexpected-build\n', { mode: 0o755 })
  const result = spawnSync('zsh', [join(root, 'Scripts', 'make-app.sh')], { cwd: root, env: { ...env, PATH: join(root, 'bin') + ':' + env.PATH }, encoding: 'utf8' })
  assert.equal(result.status, 1)
  assert.equal(existsSync(join(root, 'unexpected-build')), false)
  assert.equal(existsSync(join(root, 'outputs')), false)
})

function commitFixture(t, { testGateStatus = 0 } = {}) {
  const { root, original, env } = fixture(t)
  for (const file of COMMIT_SCRIPTS) {
    copyFileSync(join(original, file), join(root, 'Scripts', file))
  }
  writeFileSync(join(root, 'Scripts', 'test.mjs'), "export function testInputSignature() { return 'same' }")
  writeFileSync(join(root, 'Scripts', 'test-repair.mjs'), `export async function runTestGate() { return { status: ${testGateStatus}, logPath: 'fixture-failure.log', signature: 'same' } }`)
  writeFileSync(join(root, 'Scripts', 'commit-identity.mjs'), IDENTITY_STUB)
  const git = (args) => {
    const result = spawnSync('git', args, { cwd: root, env, encoding: 'utf8' })
    assert.equal(result.status, 0, result.stderr)
    return result.stdout
  }
  git(['init', '-q']); git(['config', 'user.name', 'fixture']); git(['config', 'user.email', 'fixture@example.com'])
  writeFileSync(join(root, 'example.txt'), 'initial')
  git(['add', 'example.txt']); git(['commit', '-qm', 'initial fixture'])
  const commit = (args, extraEnv = {}) => spawnSync(process.execPath, [join(root, 'Scripts', 'commit.mjs'), ...args], { cwd: root, env: { ...env, ...extraEnv }, encoding: 'utf8' })
  return { root, env, git, commit }
}

test('standalone commit stops before staging or changing history when tests fail', (t) => {
  const { root, git, commit } = commitFixture(t, { testGateStatus: 1 })
  const head = git(['rev-parse', 'HEAD'])
  const index = readFileSync(join(root, '.git', 'index'))
  writeFileSync(join(root, 'example.txt'), 'changed')
  const result = commit(['-m', 'fix(core): fixture'])
  assert.equal(result.status, 1)
  assert.match(result.stderr, /测试未通过，提交已停止/)
  assert.equal(git(['rev-parse', 'HEAD']), head)
  assert.deepEqual(readFileSync(join(root, '.git', 'index')), index)
})

test('commit stops before staging screenshots or recordings a human has not reviewed', (t) => {
  const { root, git, commit } = commitFixture(t)
  const head = git(['rev-parse', 'HEAD'])
  const index = readFileSync(join(root, '.git', 'index'))
  mkdirSync(join(root, 'docs', 'screenshots'), { recursive: true })
  writeFileSync(join(root, 'docs', 'demo.gif'), 'GIF89a fixture recording')
  writeFileSync(join(root, 'docs', 'screenshots', 'menu.png'), Buffer.from([0x89, 0x50, 0x4e, 0x47]))
  writeFileSync(join(root, 'example.txt'), 'changed')
  const result = commit(['-m', 'docs(menu): add demo recording'])
  assert.equal(result.status, 1)
  assert.match(result.stderr, /涉及截图\/录屏，禁止直接提交，需要人工审核/)
  assert.match(result.stderr, /docs\/demo\.gif（GIF 动图）/)
  assert.match(result.stderr, /docs\/screenshots\/menu\.png（截图目录）/)
  assert.equal(git(['rev-parse', 'HEAD']), head)
  assert.deepEqual(readFileSync(join(root, '.git', 'index')), index)
  assert.equal(git(['status', '--porcelain', 'docs']).trim().startsWith('??'), true)
})

test('COMMIT_MEDIA_REVIEWED records the human review and keeps the model as author', (t) => {
  const { root, git, commit } = commitFixture(t)
  mkdirSync(join(root, 'docs'), { recursive: true })
  writeFileSync(join(root, 'docs', 'demo.gif'), 'GIF89a reviewed recording')
  const result = commit(['-m', 'docs(menu): add demo recording'], { COMMIT_MEDIA_REVIEWED: '1' })
  assert.equal(result.status, 0, result.stderr)
  assert.match(result.stdout, /截图\/录屏已人工审核：docs\/demo\.gif（GIF 动图）/)
  assert.equal(git(['log', '-1', '--format=%ae']).trim(), 'noreply@openai.com')
  assert.equal(git(['log', '-1', '--format=%ce']).trim(), 'noreply@openai.com')
  assert.equal(git(['log', '-1', '--format=%B']).trim(), `docs(menu): add demo recording\n\nMedia-Reviewed-By: Cloyd Lau <${HUMAN_EMAIL}>`)
})

test('COMMIT_COAUTHOR counts as the human review and commits under the user', (t) => {
  const { root, git, commit } = commitFixture(t)
  mkdirSync(join(root, 'docs', 'screenshots'), { recursive: true })
  writeFileSync(join(root, 'docs', 'screenshots', 'menu.png'), Buffer.from([0x89, 0x50, 0x4e, 0x47]))
  const result = commit(['-m', 'docs(menu): add leaderboard screenshot'], { COMMIT_COAUTHOR: '1' })
  assert.equal(result.status, 0, result.stderr)
  assert.match(result.stdout, /截图\/录屏已人工审核/)
  assert.equal(git(['log', '-1', '--format=%ce']).trim(), HUMAN_EMAIL)
  assert.match(git(['log', '-1', '--format=%B']), /Media-Reviewed-By: Cloyd Lau/)
})

test('split commits record the human review only on the commit carrying the media', (t) => {
  const { root, git, commit } = commitFixture(t)
  const base = git(['rev-parse', 'HEAD']).trim()
  mkdirSync(join(root, 'docs'), { recursive: true })
  writeFileSync(join(root, 'Scripts', 'fixture-note.mjs'), 'export const fixtureNote = 1\n')
  writeFileSync(join(root, 'README.md'), '# fixture\n')
  writeFileSync(join(root, 'docs', 'demo.gif'), 'GIF89a fixture recording')
  const result = commit([], { COMMIT_MEDIA_REVIEWED: '1' })
  assert.equal(result.status, 0, result.stderr)
  assert.match(result.stdout, /将拆成 \d+ 个提交/)
  const created = git(['rev-list', '--reverse', `${base}..HEAD`]).trim().split('\n')
  assert.ok(created.length > 1, '按用途拆分后应产生多个提交')
  const carrying = created.filter((sha) => git(['show', '--no-renames', '--name-only', '--pretty=format:', sha]).includes('docs/demo.gif'))
  assert.equal(carrying.length, 1)
  for (const sha of created) {
    const message = git(['show', '-s', '--format=%B', sha])
    if (sha === carrying[0]) assert.match(message, /Media-Reviewed-By: Cloyd Lau <31238760\+cloydlau@users\.noreply\.github\.com>/)
    else assert.doesNotMatch(message, /Media-Reviewed-By/)
  }
})

test('deleting a recording stays allowed and passthrough mode still requires the user', (t) => {
  const { root, git, commit } = commitFixture(t)
  mkdirSync(join(root, 'docs'), { recursive: true })
  writeFileSync(join(root, 'docs', 'demo.gif'), 'GIF89a leaked recording')
  assert.equal(commit(['-m', 'docs(menu): add demo recording'], { COMMIT_MEDIA_REVIEWED: '1' }).status, 0)
  assert.equal(git(['log', '-1', '--format=%ce']).trim(), 'noreply@openai.com')
  // 透传 git 参数时补不了审核记录，被修改的提交带画面就要本人署名。
  const amend = commit(['--amend', '--no-edit'])
  assert.equal(amend.status, 1)
  assert.match(amend.stderr, /docs\/demo\.gif（GIF 动图）/)
  assert.match(amend.stderr, /透传 git 参数时补不了审核记录/)
  assert.equal(git(['log', '-1', '--format=%ce']).trim(), 'noreply@openai.com')
  const amended = commit(['--amend', '--no-edit'], { COMMIT_COAUTHOR: '1' })
  assert.equal(amended.status, 0, amended.stderr)
  assert.equal(git(['log', '-1', '--format=%ce']).trim(), HUMAN_EMAIL)
  // 把画面从版本库里删掉不需要审核。
  git(['rm', '-q', 'docs/demo.gif'])
  const removed = commit(['-m', 'docs(menu): remove demo recording'])
  assert.equal(removed.status, 0, removed.stderr)
  assert.doesNotMatch(git(['log', '-1', '--format=%B']), /Media-Reviewed-By/)
  // 透传模式下暂存的新录屏同样拦下。
  mkdirSync(join(root, 'docs'), { recursive: true })
  writeFileSync(join(root, 'docs', 'menu.mov'), 'fixture recording')
  git(['add', 'docs/menu.mov'])
  const staged = commit(['--amend', '--no-edit'])
  assert.equal(staged.status, 1)
  assert.match(staged.stderr, /docs\/menu\.mov（录屏视频）/)
})
