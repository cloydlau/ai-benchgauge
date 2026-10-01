import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import { copyFileSync, readFileSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import test from 'node:test'

import { HUMAN } from './commit-identity.mjs'
import {
  MEDIA_REVIEW_TRAILER, assertMediaReviewed, describeMedia, introducedPaths, isMediaPath,
  mediaApproved, mediaPaths, parseNameStatus, reviewedCommit, withMediaReview,
} from './media-gate.mjs'

const MODEL_EMAIL = 'noreply@openai.com'
const MODEL = Object.freeze({
  author: { name: 'gpt-5-codex', email: MODEL_EMAIL },
  committer: { name: 'gpt-5-codex', email: MODEL_EMAIL },
  coauthor: null,
})
const COAUTHORED = Object.freeze({ ...MODEL, committer: { ...HUMAN }, coauthor: { ...HUMAN } })
const original = dirname(fileURLToPath(import.meta.url))

function caughtError(call) {
  try { call() } catch (error) { return error }
  return null
}

test('录屏、GIF 和截图命中门禁，仓库里的设计稿不命中', () => {
  for (const path of [
    'docs/demo.gif', 'demo.mov', 'work/recording.mp4', 'docs/screenshots/leaderboard-model-dark.png',
    '截屏2026-09-29 下午4.42.40.png', 'Screenshot 2026-09-29.png', 'CleanShot 2026-01-01.png',
    'work/demo-gif-frames/frame-0001.png', 'work/candidate-0.png', 'docs/captures/menu.png',
  ]) assert.equal(isMediaPath(path), true, path)
  for (const path of [
    'assets/logos/kimi.png', 'docs/logo/social-preview.png', 'docs/logo/ai-benchgauge-menubar-22@2x.png',
    'docs/logo/AI-BenchGauge.icns', 'docs/overview.svg', 'docs/architecture.md', 'Scripts/commit.mjs',
    'apps/windows/BenchGauge/App.xaml', 'Sources/LeaderboardCore/Quota.swift',
  ]) assert.equal(isMediaPath(path), /\.(png|jpe?g|webp|avif|heic|heif|tiff?|bmp)$/i.test(path), path)
})

test('只有新增和修改会进历史，删除截图不需要审核', () => {
  const entries = parseNameStatus('D\0docs/demo.gif\0M\0README.md\0A\0docs/screenshots/menu.png\0R100\0a.png\0b.png\0')
  assert.deepEqual(entries.map((entry) => entry.status), ['D', 'M', 'A', 'R'])
  assert.deepEqual(introducedPaths(entries), ['README.md', 'docs/screenshots/menu.png', 'b.png'])
  assert.deepEqual(mediaPaths(introducedPaths(entries)), ['docs/screenshots/menu.png', 'b.png'])
})

test('模型提交截图必须人工审核，本人署名或显式确认后放行', () => {
  const paths = ['docs/demo.gif', 'docs/screenshots/menu.png']
  assert.equal(mediaApproved({ identity: MODEL, env: {} }), false)
  assert.equal(mediaApproved({ identity: MODEL, env: { COMMIT_MEDIA_REVIEWED: '1' } }), true)
  assert.equal(mediaApproved({ identity: COAUTHORED, env: {} }), true)
  // 透传 git 参数时补不了审核记录，只认本人署名。
  assert.equal(mediaApproved({ identity: MODEL, env: { COMMIT_MEDIA_REVIEWED: '1' }, identityOnly: true }), false)
  assert.equal(mediaApproved({ identity: COAUTHORED, env: {}, identityOnly: true }), true)
  assert.deepEqual(assertMediaReviewed({ paths: ['README.md'], identity: MODEL, env: {} }), [])
  assert.deepEqual(assertMediaReviewed({ paths, identity: MODEL, env: { COMMIT_MEDIA_REVIEWED: '1' } }), paths)
  const blocked = caughtError(() => assertMediaReviewed({ paths, identity: MODEL, env: {} }))
  assert.ok(blocked, '未经审核的截图提交必须被拦下')
  assert.match(blocked.message, /涉及截图\/录屏，禁止直接提交，需要人工审核/)
  assert.match(blocked.message, /docs\/demo\.gif（GIF 动图）、docs\/screenshots\/menu\.png（截图目录）/)
  assert.match(blocked.message, /COMMIT_MEDIA_REVIEWED=1/)
  assert.match(blocked.message, /COMMIT_COAUTHOR=1/)
  const passthrough = caughtError(() => assertMediaReviewed({
    paths, identity: MODEL, env: { COMMIT_MEDIA_REVIEWED: '1' }, identityOnly: true,
  }))
  assert.match(passthrough.message, /透传 git 参数时补不了审核记录/)
  assert.doesNotMatch(passthrough.message, /COMMIT_MEDIA_REVIEWED=1/)
})

test('审核过的提交带上审核记录，其它提交不动说明', () => {
  const reviewed = withMediaReview('docs(menu): add preview', ['README.md', 'docs/demo.gif'])
  assert.equal(reviewed, `docs(menu): add preview\n\n${MEDIA_REVIEW_TRAILER}: ${HUMAN.name} <${HUMAN.email}>`)
  assert.equal(withMediaReview('docs(menu): add preview', ['README.md']), 'docs(menu): add preview')
  assert.equal(withMediaReview(reviewed, ['docs/demo.gif']), reviewed)
  assert.deepEqual(describeMedia(['docs/demo.gif']), ['docs/demo.gif（GIF 动图）'])
})

test('CI 兜底只认本人署名或审核记录', () => {
  const trailer = `${MEDIA_REVIEW_TRAILER}: ${HUMAN.name} <${HUMAN.email}>`
  assert.equal(reviewedCommit({ authorEmail: MODEL_EMAIL, committerEmail: HUMAN.email, message: 'docs: x' }), true)
  assert.equal(reviewedCommit({ authorEmail: HUMAN.email, committerEmail: MODEL_EMAIL, message: 'docs: x' }), true)
  assert.equal(reviewedCommit({ authorEmail: MODEL_EMAIL, committerEmail: MODEL_EMAIL, message: `docs: x\n\n${trailer}` }), true)
  assert.equal(reviewedCommit({ authorEmail: MODEL_EMAIL, committerEmail: MODEL_EMAIL, message: 'docs: x' }), false)
  assert.equal(reviewedCommit({
    authorEmail: MODEL_EMAIL,
    committerEmail: MODEL_EMAIL,
    message: `docs: x\n\n${MEDIA_REVIEW_TRAILER}: Someone Else <other@example.com>`,
  }), false)
})

test('CI 脚本拒绝没有审核记录的截图提交，补上记录或删除后放行', (t) => {
  const root = mkdtempSync(join(tmpdir(), 'benchgauge-media-ci-'))
  t.after(() => rmSync(root, { recursive: true, force: true }))
  mkdirSync(join(root, 'Scripts'), { recursive: true })
  mkdirSync(join(root, 'docs', 'screenshots'), { recursive: true })
  for (const file of ['calmmit.mjs', 'media-gate.mjs', 'media-gate-ci.mjs', 'commit-identity.mjs']) {
    copyFileSync(join(original, file), join(root, 'Scripts', file))
  }
  const config = JSON.parse(readFileSync(join(original, '../calmmit.config.json'), 'utf8'))
  config.library = resolve(original, '..', config.library)
  writeFileSync(join(root, 'calmmit.config.json'), JSON.stringify(config))
  const gate = (...args) => spawnSync(process.execPath, [join(root, 'Scripts', 'media-gate-ci.mjs'), ...args], { cwd: root, encoding: 'utf8' })
  const git = (args) => {
    const result = spawnSync('git', args, {
      cwd: root, encoding: 'utf8',
      env: { ...process.env, GIT_AUTHOR_NAME: 'gpt-5-codex', GIT_AUTHOR_EMAIL: MODEL_EMAIL, GIT_COMMITTER_NAME: 'gpt-5-codex', GIT_COMMITTER_EMAIL: MODEL_EMAIL },
    })
    assert.equal(result.status, 0, result.stderr)
    return result.stdout
  }
  git(['init', '-q'])
  writeFileSync(join(root, 'README.md'), 'fixture')
  git(['add', '-A'])
  git(['commit', '-qm', 'docs: add fixture readme'])
  writeFileSync(join(root, 'docs', 'screenshots', 'menu.png'), Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a]))
  git(['add', '-A'])
  git(['commit', '-qm', 'docs(menu): add preview'])

  const blocked = gate()
  assert.equal(blocked.status, 1)
  assert.match(blocked.stderr, /没有匹配的审核记录/)
  assert.match(blocked.stderr, /docs\/screenshots\/menu\.png（截图目录）/)

  git(['commit', '-q', '--amend', '-m', `docs(menu): add preview\n\n${MEDIA_REVIEW_TRAILER}: ${HUMAN.name} <${HUMAN.email}>`])
  const allowed = gate()
  assert.equal(allowed.status, 0, allowed.stderr)
  assert.match(allowed.stdout, /已通过媒体审核/)

  git(['rm', '-q', 'docs/screenshots/menu.png'])
  git(['commit', '-qm', 'docs(menu): remove preview'])
  assert.equal(gate().status, 0)
  const ranged = gate('HEAD~2', 'HEAD')
  assert.equal(ranged.status, 0, ranged.stderr)
  assert.match(ranged.stdout, /1 个含媒体且已通过审核/)
})
