import assert from 'node:assert/strict'
import { test } from 'node:test'
import { spawn } from 'node:child_process'
import { copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, utimesSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
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

// Run the real watcher in an isolated project. The build/restart scripts only
// record calls; these tests never launch the user's app or use its accounts.
function watcherFixture(t, { binary = 'fresh', restartFails = false, testsFail = false, commitFails = false, initiallyBusy = false, gitWork = false, receiptCommit = null, env = {} } = {}) {
  const root = realpathSync(mkdtempSync(join(tmpdir(), 'benchgauge-watch-test-')))
  const scripts = join(root, 'Scripts')
  const app = join(root, 'outputs', 'AI-BenchGauge.app')
  mkdirSync(scripts)
  mkdirSync(join(root, '.git'))
  mkdirSync(join(root, 'Sources'))
  mkdirSync(join(root, 'Tests'))
  mkdirSync(join(app, 'Contents', 'MacOS'), { recursive: true })
  const original = dirname(fileURLToPath(import.meta.url))
  for (const name of ['calmmit.mjs', 'watch.mjs', 'commit-identity.mjs', 'commit-lock.mjs', 'desktop-notify.mjs', 'git-network.mjs', 'node-executable.mjs']) {
    copyFileSync(join(original, name), join(scripts, name))
  }
  const config = JSON.parse(readFileSync(join(original, '../calmmit.config.json'), 'utf8'))
  config.library = resolve(original, '..', config.library)
  writeFileSync(join(root, 'calmmit.config.json'), JSON.stringify(config))
  const source = join(root, 'Sources', 'example.swift')
  const testFile = join(root, 'Tests', 'example.swift')
  writeFileSync(testFile, testsFail ? 'fail' : 'pass')
  writeFileSync(join(scripts, 'test-repair.mjs'), `import { appendFileSync, readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
const root = fileURLToPath(new URL('../', import.meta.url))
let calls = 0
export async function runTestGate() {
  appendFileSync(root + 'events', 'test\\n')
  if (${initiallyBusy} && calls++ === 0) return { status: 75, signature: null }
  return { status: readFileSync(root + 'Tests/example.swift', 'utf8') === 'fail' ? 1 : 0, signature: 'mock-pass', logPath: 'mock.log' }
}
`)
  writeFileSync(source, '// initial\n')
  writeFileSync(join(scripts, 'make-app.sh'), `#!/bin/sh
cd "$(dirname "$0")/.."
echo build >> events
touch outputs/AI-BenchGauge.app/Contents/MacOS/leaderboard-menu
`, { mode: 0o755 })
  writeFileSync(join(scripts, 'restart.sh'), `#!/bin/sh
cd "$(dirname "$0")/.."
echo restart >> events
exit ${restartFails ? 1 : 0}
`, { mode: 0o755 })
  if (gitWork) {
    mkdirSync(join(root, 'bin'))
    writeFileSync(join(root, 'bin', 'git'), `#!/bin/sh
case "$1" in
  status) test -f commit.done || printf ' M Sources/example.swift\\0';;
  rev-list) if test -f push.done; then echo '0 0'; else echo '0 1'; fi;;
  rev-parse) if test -f head; then cat head; else echo fixture-head; fi;;
  cat-file) exit 0;;
  diff) echo Sources/example.swift;;
  *) for arg in "$@"; do if test "$arg" = push; then echo push >> events; touch push.done; fi; done;;
esac
exit 0
`, { mode: 0o755 })
    writeFileSync(join(scripts, 'commit.mjs'), `import { appendFileSync, writeFileSync } from 'node:fs'; appendFileSync('events', 'commit\\n'); if (${commitFails}) process.exit(2); writeFileSync('commit.done', 'done'); writeFileSync('head', 'fixture-head-2')`)
  }
  const executable = join(app, 'Contents', 'MacOS', 'leaderboard-menu')
  if (binary !== 'missing') {
    writeFileSync(executable, '')
    const date = new Date(Date.now() + (binary === 'fresh' ? 60_000 : -60_000))
    utimesSync(executable, date, date)
  }
  // Deliberately disagree with the executable's date to catch bundle-mtime bugs.
  const bundleDate = new Date(Date.now() + (binary === 'fresh' ? -120_000 : 120_000))
  utimesSync(app, bundleDate, bundleDate)
  if (receiptCommit) {
    mkdirSync(join(root, 'work'), { recursive: true })
    writeFileSync(join(root, 'work', '.last-app-deploy'), `${JSON.stringify({ commit: receiptCommit })}\n`)
  }
  const child = spawn(process.execPath, [join(scripts, 'watch.mjs')], {
    cwd: root,
    env: { ...process.env, WATCH_AUTOCOMMIT: gitWork ? '1' : '0', DESKTOP_NOTIFY: '0', ...env,
      ...(gitWork ? { PATH: join(root, 'bin') + ':' + process.env.PATH } : {}) },
    stdio: ['ignore', 'pipe', 'pipe'],
  })
  let output = ''
  child.stdout.setEncoding('utf8')
  child.stderr.setEncoding('utf8')
  child.stdout.on('data', (data) => { output += data })
  child.stderr.on('data', (data) => { output += data })
  const exited = new Promise((resolve) => child.once('exit', (code) => resolve(code)))
  t.after(async () => {
    if (child.exitCode == null) child.kill('SIGTERM')
    await exited
    rmSync(root, { recursive: true, force: true })
  })
  return {
    source, testFile, root, child, exited,
    output: () => output,
    events: () => existsSync(join(root, 'events')) ? readFileSync(join(root, 'events'), 'utf8').trim().split('\n') : [],
  }
}

async function waitUntil(fixture, predicate) {
  const deadline = Date.now() + 8_000
  while (!predicate()) {
    assert.ok(Date.now() < deadline, `watcher timed out:\n${fixture.output()}`)
    await new Promise((resolve) => setTimeout(resolve, 20))
  }
}

test('startup launches a current executable immediately despite an old bundle directory', async (t) => {
  const fixture = watcherFixture(t)
  await waitUntil(fixture, () => fixture.output().includes('等待源码变更'))
  assert.match(fixture.output(), /【自动处理中】 启动自检中；测试通过后将启动或更新菜单栏应用/)
  assert.deepEqual(fixture.events(), ['test', 'restart'])
})

test('a second watcher exits without testing or launching the app again', async (t) => {
  const fixture = watcherFixture(t)
  await waitUntil(fixture, () => fixture.output().includes('等待源码变更'))
  assert.equal(
    readFileSync(join(fixture.root, '.git', 'benchgauge-watch.lock'), 'utf8'),
    `${fixture.child.pid}\nlauncher ${process.pid}\n`,
  )
  const before = fixture.events().length

  const duplicate = spawn(process.execPath, [join(fixture.root, 'Scripts', 'watch.mjs')], {
    cwd: fixture.root,
    env: { ...process.env, WATCH_AUTOCOMMIT: '0', DESKTOP_NOTIFY: '0' },
    stdio: ['ignore', 'pipe', 'pipe'],
  })
  let output = ''
  duplicate.stdout.setEncoding('utf8')
  duplicate.stderr.setEncoding('utf8')
  duplicate.stdout.on('data', (data) => { output += data })
  duplicate.stderr.on('data', (data) => { output += data })
  const exited = new Promise((resolve) => duplicate.once('exit', resolve))
  t.after(async () => {
    if (duplicate.exitCode == null) duplicate.kill('SIGTERM')
    await exited
  })

  assert.equal(await exited, 75)
  assert.match(output, /⚠【需人工介入】 已有 BenchGauge watcher（pid \d+），本次不重复启动/)
  await new Promise((resolve) => setTimeout(resolve, 200))
  assert.equal(fixture.events().length, before)

  fixture.child.kill('SIGTERM')
  await fixture.exited
  assert.equal(existsSync(join(fixture.root, '.git', 'benchgauge-watch.lock')), false)
})

test('startup rebuilds a stale executable even when the bundle directory looks newer', async (t) => {
  const fixture = watcherFixture(t, { binary: 'stale' })
  await waitUntil(fixture, () => fixture.output().includes('等待源码变更'))
  assert.deepEqual(fixture.events(), ['test', 'build', 'restart'])
})

test('startup builds and launches when the executable is missing', async (t) => {
  const fixture = watcherFixture(t, { binary: 'missing' })
  await waitUntil(fixture, () => fixture.output().includes('等待源码变更'))
  assert.deepEqual(fixture.events(), ['test', 'build', 'restart'])
})

test('startup reports a restart failure instead of claiming the application is running', async (t) => {
  const fixture = watcherFixture(t, { restartFails: true })
  const code = await fixture.exited
  assert.equal(code, 1)
  assert.match(fixture.output(), /重启失败/)
  assert.doesNotMatch(fixture.output(), /应用已启动，等待源码变更/)
})

test('saving source after startup rebuilds and restarts through the running watcher', async (t) => {
  const fixture = watcherFixture(t, { env: { WATCH_DEBOUNCE_MS: '0', WATCH_THROTTLE_MS: '0', WATCH_POLL_MS: '200' } })
  await waitUntil(fixture, () => fixture.output().includes('等待源码变更'))
  writeFileSync(fixture.source, '// changed\n')
  await waitUntil(fixture, () => fixture.events().length === 5)
  assert.deepEqual(fixture.events(), ['test', 'restart', 'test', 'build', 'restart'])
})

test('failed tests stop startup and saving a test file recovers without restarting the watcher', async (t) => {
  const fixture = watcherFixture(t, { testsFail: true, binary: 'missing', env: { WATCH_DEBOUNCE_MS: '0', WATCH_THROTTLE_MS: '0', WATCH_POLL_MS: '200' } })
  await waitUntil(fixture, () => fixture.output().includes('等待测试相关文件变更'))
  assert.deepEqual(fixture.events(), ['test'])
  assert.match(fixture.output().trim().split('\n').at(-1), /⚠【需人工介入】.*启动测试失败.*mock.log/)
  await new Promise((resolve) => setTimeout(resolve, 500))
  assert.deepEqual(fixture.events(), ['test'])
  writeFileSync(fixture.testFile, 'pass')
  await waitUntil(fixture, () => fixture.events().length === 4)
  assert.deepEqual(fixture.events(), ['test', 'test', 'build', 'restart'])
})

test('a test failure after startup blocks rebuilding and does not loop on the same input', async (t) => {
  const fixture = watcherFixture(t, { env: { WATCH_DEBOUNCE_MS: '0', WATCH_THROTTLE_MS: '0', WATCH_POLL_MS: '200' } })
  await waitUntil(fixture, () => fixture.output().includes('等待源码变更'))
  writeFileSync(fixture.testFile, 'fail')
  await waitUntil(fixture, () => fixture.output().includes('测试失败，已停止提交、推送和重建'))
  await new Promise((resolve) => setTimeout(resolve, 500))
  assert.deepEqual(fixture.events(), ['test', 'restart', 'test'])
  writeFileSync(fixture.testFile, 'pass')
  await waitUntil(fixture, () => fixture.events().length === 6)
  assert.deepEqual(fixture.events(), ['test', 'restart', 'test', 'test', 'build', 'restart'])
})

test('saving a workflow script triggers tests before rebuild', async (t) => {
  const fixture = watcherFixture(t, { env: { WATCH_DEBOUNCE_MS: '0', WATCH_THROTTLE_MS: '0', WATCH_POLL_MS: '200' } })
  await waitUntil(fixture, () => fixture.output().includes('等待源码变更'))
  writeFileSync(join(fixture.root, 'Scripts', 'example.mjs'), '// changed')
  await waitUntil(fixture, () => fixture.events().length === 5)
  assert.deepEqual(fixture.events(), ['test', 'restart', 'test', 'build', 'restart'])
})

test('an older deploy receipt rebuilds committed app changes at startup', async (t) => {
  const fixture = watcherFixture(t, {
    gitWork: true,
    receiptCommit: 'fixture-old',
    env: { WATCH_DEBOUNCE_MS: '0', WATCH_THROTTLE_MS: '0', WATCH_POLL_MS: '200' },
  })
  await waitUntil(fixture, () => {
    try {
      return JSON.parse(readFileSync(join(fixture.root, 'work', '.last-app-deploy'), 'utf8')).commit === 'fixture-head-2'
    } catch {
      return false
    }
  })
  assert.match(fixture.output(), /上次已部署提交：fixture-old/)
  assert.match(fixture.output(), /未部署的已提交应用变更/)
  assert.deepEqual(fixture.events().slice(0, 3), ['test', 'build', 'restart'])
  assert.match(fixture.output(), /检测到已提交的应用变更|启动时检测到未提交改动/)
})

test('APP_AUTODEPLOY=0 keeps the watcher from rebuilding or restarting the app', async (t) => {
  const fixture = watcherFixture(t, {
    env: { APP_AUTODEPLOY: '0', WATCH_DEBOUNCE_MS: '0', WATCH_THROTTLE_MS: '0', WATCH_POLL_MS: '200' },
  })
  await waitUntil(fixture, () => fixture.output().includes('自动部署已关闭，等待源码变更'))
  assert.deepEqual(fixture.events(), ['test'])
  writeFileSync(fixture.source, '// changed\n')
  await waitUntil(fixture, () => fixture.events().length === 2)
  assert.deepEqual(fixture.events(), ['test', 'test'])
  assert.ok(!fixture.events().includes('build'))
  assert.ok(!fixture.events().includes('restart'))
})

test('failed tests prevent commits and pushes; recovery runs tests before every mutation', async (t) => {
  const fixture = watcherFixture(t, { testsFail: true, gitWork: true, env: { WATCH_DEBOUNCE_MS: '0', WATCH_THROTTLE_MS: '0', WATCH_POLL_MS: '200', WATCH_AUTOPUSH: '1', COMMIT_PUSH: '1' } })
  await waitUntil(fixture, () => fixture.output().includes('等待测试相关文件变更'))
  await new Promise((resolve) => setTimeout(resolve, 500))
  assert.deepEqual(fixture.events(), ['test'])
  writeFileSync(fixture.testFile, 'pass')
  await waitUntil(fixture, () => fixture.events().includes('restart'))
  assert.deepEqual(fixture.events(), ['test', 'test', 'commit', 'push', 'build', 'restart'])
})

test('startup commits and pushes existing changes even when deployment is disabled', async (t) => {
  const fixture = watcherFixture(t, {
    gitWork: true,
    env: { APP_AUTODEPLOY: '0', WATCH_DEBOUNCE_MS: '0', WATCH_THROTTLE_MS: '0', WATCH_POLL_MS: '200', COMMIT_PUSH: '1', WATCH_AUTOPUSH: '1' },
  })
  await waitUntil(fixture, () => fixture.output().includes('【已完成】'))
  assert.match(fixture.output(), /【等待自动处理】.*启动时检测到未提交改动/)
  assert.deepEqual(fixture.events(), ['test', 'test', 'commit', 'push'])
})

test('a failed commit stays visible after a successful rebuild without looping', async (t) => {
  const fixture = watcherFixture(t, {
    gitWork: true, commitFails: true,
    env: { WATCH_DEBOUNCE_MS: '0', WATCH_THROTTLE_MS: '0', WATCH_POLL_MS: '200', COMMIT_PUSH: '0' },
  })
  await waitUntil(fixture, () => fixture.output().includes('⚠【需人工介入】'))
  assert.match(fixture.output().trim().split('\n').at(-1), /⚠【需人工介入】.*提交失败.*commit-last.log/)
  await new Promise((resolve) => setTimeout(resolve, 500))
  assert.equal(fixture.events().filter((event) => event === 'commit').length, 1)
  assert.doesNotMatch(fixture.output(), /【已完成】/)
})

test('startup retries a transient test lock without waiting for another edit', async (t) => {
  const fixture = watcherFixture(t, {
    gitWork: true, initiallyBusy: true,
    env: { APP_AUTODEPLOY: '0', WATCH_DEBOUNCE_MS: '0', WATCH_THROTTLE_MS: '0', WATCH_POLL_MS: '200', COMMIT_PUSH: '0' },
  })
  await waitUntil(fixture, () => fixture.output().includes('【已完成】'))
  assert.deepEqual(fixture.events(), ['test', 'test', 'commit'])
  assert.doesNotMatch(fixture.output(), /⚠【需人工介入】/)
})
