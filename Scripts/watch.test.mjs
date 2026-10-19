import assert from 'node:assert/strict'
import { test } from 'node:test'
import { spawn } from 'node:child_process'
import { Writable } from 'node:stream'
import { ci } from './calmmit.mjs'
import { copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, utimesSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { deploymentNotification, dirtyStatusSignature } from './watch.mjs'

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

test('restart attribution stays with the deployed commit when the current model or HEAD changes', () => {
  const authors = new Map([['deployed-grok', 'grok-4.7'], ['newer-gpt', 'gpt-6.1-sol']])
  const notification = deploymentNotification('deployed-grok', { readAuthor: (revision) => authors.get(revision) })
  assert.equal(notification.model, 'grok-4.7')
  assert.match(notification.message, /^提交署名：grok-4\.7\n/)
  assert.doesNotMatch(notification.message, /gpt/)
})

test('an uncommitted build or unreadable deployment never borrows the current model', () => {
  const unknown = deploymentNotification(null, { readAuthor: () => { throw Error('must not read HEAD') } })
  assert.equal(unknown.model, '')
  assert.equal(unknown.message, '菜单栏应用已使用最新代码重新打开。')
  for (const readAuthor of [() => null, () => { throw Error('missing commit') }, () => 'grok\nother']) {
    assert.deepEqual(deploymentNotification('missing', { readAuthor }), unknown)
  }
})

// Run the real watcher in an isolated project. The build/restart scripts only
// record calls; these tests never launch the user's app or use its accounts.
function watcherFixture(t, { binary = 'fresh', restartFails = false, testsFail = false, commitFails = false, initiallyBusy = false, gitWork = false, receiptCommit = null, receiptAuthor = undefined, notificationAuthor = null, dirtyBuild = false, phone = false, phoneFails = false, env = {}, setup } = {}) {
  const root = realpathSync(mkdtempSync(join(tmpdir(), 'benchgauge-watch-test-')))
  const scripts = join(root, 'Scripts')
  const app = join(root, 'outputs', 'AI-BenchGauge.app')
  mkdirSync(scripts)
  mkdirSync(join(root, '.git'))
  mkdirSync(join(root, 'Sources'))
  mkdirSync(join(root, 'Tests'))
  mkdirSync(join(app, 'Contents', 'MacOS'), { recursive: true })
  const original = dirname(fileURLToPath(import.meta.url))
  // The real test runner is imported for its IPC execution context even though
  // runTestGate is mocked, so its module dependencies must exist in the fixture.
  for (const name of ['calmmit.mjs', 'watch.mjs', 'test.mjs', 'build-cache.mjs', 'prepare-swift-workspace.mjs', 'commit-identity.mjs', 'commit-lock.mjs', 'desktop-notify.mjs', 'git-network.mjs', 'node-executable.mjs']) {
    copyFileSync(join(original, name), join(scripts, name))
  }
  // These desktop watcher fixtures never construct or upload a mini-program.
  writeFileSync(join(scripts, 'weapp-deploy.mjs'), 'export async function startWeappUploadWatch() { return () => {} }')
  const config = JSON.parse(readFileSync(join(original, '../calmmit.config.json'), 'utf8'))
  config.library = resolve(original, '..', config.library)
  writeFileSync(join(root, 'calmmit.config.json'), JSON.stringify(config))
  if (phone) {
    writeFileSync(join(root, '.benchgauge-ios.local.json'), '{"enabled":true}')
    writeFileSync(join(scripts, 'ios-deploy.mjs'), `import { appendFileSync, readFileSync } from 'node:fs'
if (process.argv[2] !== 'checked' || process.env.BENCHGAUGE_TEST_PASS !== 'mock-pass') process.exit(2)
appendFileSync('events', 'phone-check\\n')
process.exit(${phoneFails} && readFileSync('Tests/example.swift', 'utf8') === 'phone-fail' ? 1 : 0)
`)
  }
  const source = join(root, 'Sources', 'example.swift')
  const testFile = join(root, 'Tests', 'example.swift')
  writeFileSync(testFile, testsFail ? 'fail' : 'pass')
  writeFileSync(join(scripts, 'test-repair.mjs'), `import { appendFileSync, readFileSync, existsSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
const root = fileURLToPath(new URL('../', import.meta.url))
export async function runTestGate() {
  const first = !existsSync(root + 'events')
  appendFileSync(root + 'events', 'test\\n')
  if (${initiallyBusy} && first) return { status: 75, signature: null }
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
  if (notificationAuthor != null) {
    // Isolate system notifications and Git from the user's desktop and checkout.
    writeFileSync(join(scripts, 'desktop-notify.mjs'), `import { appendFileSync } from 'node:fs'
export const materializeAvatar = (avatar) => avatar.provider
export function notifyDesktop(root, title, message, options) {
  appendFileSync(root + '/notifications.jsonl', JSON.stringify({ title, message, image: options.image }) + '\\n')
}
`)
    mkdirSync(join(root, 'bin'), { recursive: true })
    writeFileSync(join(root, 'bin', 'git'), `#!/bin/sh
case "$1" in
  status) if ${dirtyBuild}; then printf ' M Sources/example.swift\\0'; fi;;
  show) printf '%s\\n' '${notificationAuthor}';;
  rev-parse) echo newer-gpt;;
  cat-file) exit 0;;
  rev-list) echo '0 0';;
esac
`, { mode: 0o755 })
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
    writeFileSync(join(root, 'work', '.last-app-deploy'), `${JSON.stringify({ commit: receiptCommit, author: receiptAuthor })}\n`)
  }
  const fixtureEnv = setup?.(root) || {}
  const child = spawn(process.execPath, [join(scripts, 'watch.mjs')], {
    cwd: root,
    env: { ...process.env, WATCH_AUTOCOMMIT: gitWork ? '1' : '0', DESKTOP_NOTIFY: '0', ...env, ...fixtureEnv,
      ...((gitWork || notificationAuthor != null) ? { PATH: join(root, 'bin') + ':' + process.env.PATH } : {}) },
    stdio: ['ignore', 'pipe', 'pipe'],
    detached: process.platform !== 'win32',
  })
  let output = ''
  child.stdout.setEncoding('utf8')
  child.stderr.setEncoding('utf8')
  child.stdout.on('data', (data) => { output += data })
  child.stderr.on('data', (data) => { output += data })
  const exited = new Promise((resolve) => child.once('close', (code) => resolve(code)))
  let cleaned = false
  const cleanup = async () => {
    if (cleaned) return
    cleaned = true
    const signalGroup = signal => {
      if (process.platform === 'win32') return
      try { process.kill(-child.pid, signal) } catch (error) { if (error.code !== 'ESRCH') throw error }
    }
    // Let Node flush coverage while stopping every writer in the fixture.
    // A bounded fallback also stops descendants that ignore termination.
    if (child.exitCode == null) child.kill('SIGTERM')
    signalGroup('SIGTERM')
    const force = setTimeout(() => signalGroup('SIGKILL'), 1000)
    // close also waits for inherited pipes; the fallback handles descendants
    // that keep them open. Do not signal the exited group again on macOS.
    try { await exited } finally { clearTimeout(force) }
    rmSync(root, { recursive: true, force: true, maxRetries: 5, retryDelay: 20 })
  }
  t.after(cleanup)
  return {
    source, testFile, root, child, exited, cleanup,
    notifications: () => existsSync(join(root, 'notifications.jsonl'))
      ? readFileSync(join(root, 'notifications.jsonl'), 'utf8').trim().split('\n').map((line) => JSON.parse(line)) : [],
    output: () => output,
    events: () => existsSync(join(root, 'events')) ? readFileSync(join(root, 'events'), 'utf8').trim().split('\n') : [],
  }
}

test('fixture cleanup terminates descendant writers before deleting its directory', async t => {
  const fixture = watcherFixture(t, { setup(root) {
    writeFileSync(join(root, 'Scripts/test-repair.mjs'), `import {spawn} from 'node:child_process'
export async function runTestGate() {
  spawn(process.execPath, ['-e', "const fs=require('node:fs'); fs.appendFileSync('events','writer-ready\\\\n'); setInterval(()=>fs.writeFileSync('late-write','fixture'),5)"], {stdio:'inherit'})
  return new Promise(()=>{})
}`)
  } })
  await waitUntil(fixture, () => fixture.events().includes('writer-ready'))
  await fixture.cleanup()
  assert.equal(existsSync(fixture.root), false)
  await new Promise(resolve => setTimeout(resolve, 50))
  assert.equal(existsSync(fixture.root), false)
})

async function waitUntil(fixture, predicate) {
  // Process fixtures may queue behind native builds on the same CI machine.
  const deadline = Date.now() + 30_000
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

test('the real restart uses one deployed author for both the notification text and avatar', async (t) => {
  const fixture = watcherFixture(t, {
    receiptCommit: 'deployed-grok', notificationAuthor: 'grok-4.7',
    env: { DESKTOP_NOTIFY: '1', MODEL_NAME: 'gpt-6.1-sol' },
  })
  await waitUntil(fixture, () => fixture.output().includes('等待源码变更'))
  assert.deepEqual(fixture.notifications(), [{
    title: '已重启',
    message: '提交署名：grok-4.7\n菜单栏应用已使用最新代码重新打开。',
    image: 'grok',
  }])
})

test('restarting an uncommitted deployed build keeps its missing author and avatar', async (t) => {
  const fixture = watcherFixture(t, {
    receiptCommit: 'deployed-dirty', receiptAuthor: '', notificationAuthor: 'grok-4.7',
    env: { DESKTOP_NOTIFY: '1', MODEL_NAME: 'gpt-6.1-sol' },
  })
  await waitUntil(fixture, () => fixture.output().includes('等待源码变更'))
  assert.deepEqual(fixture.notifications(), [{
    title: '已重启',
    message: '菜单栏应用已使用最新代码重新打开。',
    image: '',
  }])
  const receipt = JSON.parse(readFileSync(join(fixture.root, 'work', '.last-app-deploy'), 'utf8'))
  assert.equal(receipt.author, '')
  assert.equal(receipt.commit, 'deployed-dirty')
})

test('building dirty source omits the old author and persists that decision for the next restart', async (t) => {
  const fixture = watcherFixture(t, {
    binary: 'stale', dirtyBuild: true, notificationAuthor: 'grok-4.7',
    env: { DESKTOP_NOTIFY: '1', MODEL_NAME: 'gpt-6.1-sol' },
  })
  await waitUntil(fixture, () => fixture.output().includes('等待源码变更'))
  assert.deepEqual(fixture.events(), ['test', 'build', 'restart'])
  assert.deepEqual(fixture.notifications(), [{
    title: '已重启',
    message: '菜单栏应用已使用最新代码重新打开。',
    image: '',
  }])
  const receipt = JSON.parse(readFileSync(join(fixture.root, 'work', '.last-app-deploy'), 'utf8'))
  assert.equal(receipt.author, '')
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
  await waitUntil(fixture, () => fixture.output().includes('Mac 构建或启动失败，监听继续'))
  assert.equal(fixture.child.exitCode, null)
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

test('a running watcher reloads test dependencies and forwards the new phone receipt', async t => {
  const fixture = watcherFixture(t, { phone: true,
    env: { WATCH_DEBOUNCE_MS: '0', WATCH_THROTTLE_MS: '0', WATCH_POLL_MS: '200' },
    setup(root) {
      writeFileSync(join(root, 'Scripts/gate-version.mjs'), "export const version = 'v1'\n")
      writeFileSync(join(root, 'Scripts/test-repair.mjs'), `import {appendFileSync} from 'node:fs'
import {version} from './gate-version.mjs'
export async function runTestGate() {
  appendFileSync('events','test-'+version+'\\n')
  return {status:0,signature:version==='v1'?'mock-pass':'updated-pass'}
}`)
    },
  })
  await waitUntil(fixture, () => fixture.output().includes('等待源码变更'))
  assert.deepEqual(fixture.events(), ['test-v1', 'restart', 'phone-check'])
  writeFileSync(join(fixture.root, 'Scripts/ios-deploy.mjs'), `import {appendFileSync} from 'node:fs'
if(process.argv[2]!=='checked'||process.env.BENCHGAUGE_TEST_PASS!=='updated-pass')process.exit(2)
appendFileSync('events','phone-check-v2\\n')`)
  writeFileSync(join(fixture.root, 'Scripts/gate-version.mjs'), "export const version = 'v2'\n")
  writeFileSync(fixture.source, '// latest source\n')
  await waitUntil(fixture, () => fixture.events().length >= 7)
  assert.deepEqual(fixture.events(), ['test-v1', 'restart', 'phone-check', 'test-v2', 'build', 'restart', 'phone-check-v2'])
})

test('a crashed test worker cannot authorize deployment with a passing message', async t => {
  const fixture = watcherFixture(t, { setup(root) {
    writeFileSync(join(root, 'Scripts/test-repair.mjs'), `export async function runTestGate(){
      const send=process.send.bind(process)
      process.send=message=>{send(message);setImmediate(()=>process.exit(2))}
      return {status:0,signature:'mock-pass'}
    }`)
  } })
  assert.equal(await fixture.exited, 1)
  assert.match(fixture.output(), /测试进程异常退出（2）/)
  assert.deepEqual(fixture.events(), [])
})

test('phone validation preserves the tested runtime, locale and absent environment settings', async t => {
  const fixture = watcherFixture(t, { phone: true, env: { TZ: 'Asia/Shanghai' }, setup(root) {
    writeFileSync(join(root, 'Scripts/test-repair.mjs'), `import{appendFileSync}from'node:fs'
export async function runTestGate(){
  process.env.LANG='en_GB.UTF-8';delete process.env.TZ
  appendFileSync('events','test\\n')
  return {status:0,signature:'mock-pass'}
}`)
    writeFileSync(join(root, 'Scripts/ios-deploy.mjs'), `import{appendFileSync}from'node:fs'
if(process.env.LANG!=='en_GB.UTF-8'||process.env.TZ!==undefined||process.execPath!==process.env.BENCHGAUGE_NODE)process.exit(2)
if(process.env.BENCHGAUGE_TEST_PASS!=='mock-pass')process.exit(2)
appendFileSync('events','phone-check\\n')`)
  } })
  await waitUntil(fixture, () => fixture.output().includes('等待源码变更'))
  assert.deepEqual(fixture.events(), ['test', 'restart', 'phone-check'])
})

test('a missing test runtime stops startup before deployment', async t => {
  const fixture = watcherFixture(t, { setup(root) {
    writeFileSync(join(root, 'Scripts/node-executable.mjs'), "export const nodeExecutable=()=>'/missing/gate-runtime'\n")
  } })
  assert.equal(await fixture.exited, 1)
  assert.match(fixture.output(), /ENOENT/)
  assert.deepEqual(fixture.events(), [])
})

test('a transient test lock after startup retries without another source save', async t => {
  const fixture = watcherFixture(t, {
    env: { WATCH_DEBOUNCE_MS: '0', WATCH_THROTTLE_MS: '0', WATCH_POLL_MS: '200' },
    setup(root) {
      writeFileSync(join(root, 'Scripts/test-repair.mjs'), `import {appendFileSync,readFileSync,existsSync,writeFileSync} from 'node:fs'
export async function runTestGate() {
  appendFileSync('events', 'test\\n')
  if (readFileSync('Tests/example.swift','utf8') === 'retry' && !existsSync('retried')) {
    writeFileSync('retried','done')
    return {status:75,signature:null}
  }
  return {status:0,signature:'mock-pass'}
}`)
    },
  })
  await waitUntil(fixture, () => fixture.output().includes('等待源码变更'))
  writeFileSync(fixture.testFile, 'retry')
  writeFileSync(fixture.source, '// changed while a test lock is temporarily busy\n')
  await waitUntil(fixture, () => fixture.events().length >= 6)
  assert.deepEqual(fixture.events(), ['test', 'restart', 'test', 'test', 'build', 'restart'])
  assert.match(fixture.output(), /测试期间有新变更，重新验证/)
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

for (const failingRun of [1, 2]) test(`edits during failing test ${failingRun} are not swallowed as a failed version`, async t => {
  const f = watcherFixture(t, { binary: 'missing',
    env: { WATCH_DEBOUNCE_MS: '0', WATCH_THROTTLE_MS: '0', WATCH_POLL_MS: '200' },
    setup(root) {
      writeFileSync(join(root, 'Scripts/test-repair.mjs'), `import{appendFileSync,readFileSync,writeFileSync}from'node:fs'
export async function runTestGate(){
  appendFileSync('events','test\\n')
  const count=readFileSync('events','utf8').split('\\n').filter(v=>v==='test').length
  if(count===${failingRun}) {writeFileSync('Sources/example.swift','// fixed while the old test failed');return {status:1,logPath:'old-failure.log'}}
  return {status:0,signature:'mock-pass'}
}`)
    } })
  if (failingRun === 2) {
    await waitUntil(f, () => f.output().includes('等待源码变更'))
    writeFileSync(f.source, '// start second check')
  }
  await waitUntil(f, () => f.events().filter(v => v === 'test').length === failingRun + 1 && f.events().at(-1) === 'restart')
  assert.equal(f.child.exitCode, null)
  assert.doesNotMatch(f.output(), /这一版测试已失败|测试失败，已停止/)
})

test('an external full test pass wakes a blocked watcher without another source edit', async t => {
  const f = watcherFixture(t, { binary: 'missing',
    env: { WATCH_DEBOUNCE_MS: '0', WATCH_THROTTLE_MS: '0', WATCH_POLL_MS: '200' },
    setup(root) {
      writeFileSync(join(root, 'Scripts/test-repair.mjs'), `import{appendFileSync,existsSync}from'node:fs'
export async function runTestGate(){appendFileSync('events','test\\n');return {status:existsSync('gate-fixed')?0:1,signature:'mock-pass',logPath:'mock.log'}}`)
    } })
  await waitUntil(f, () => f.output().includes('等待测试相关文件变更'))
  mkdirSync(join(f.root, 'work/test-results'), { recursive: true })
  const receipt = join(f.root, 'work/test-results/latest.json')
  for (const result of [{status:1,scope:'all',signature:'bad'}, {status:0,scope:'scripts',signature:'partial'}]) {
    writeFileSync(receipt, JSON.stringify(result))
    await new Promise(resolve => setTimeout(resolve, 250))
    assert.equal(f.events().length, 1)
  }
  writeFileSync(join(f.root, 'gate-fixed'), '')
  writeFileSync(receipt, JSON.stringify({status:0,scope:'all',signature:'external-pass'}))
  await waitUntil(f, () => f.events().at(-1) === 'restart')
  assert.deepEqual(f.events(), ['test', 'test', 'build', 'restart'])
  assert.match(f.output(), /新的完整测试通过结果/)
})

test('an external full pass retries a failed startup launch while retaining the watcher', async t => {
  const f = watcherFixture(t, { env: { WATCH_DEBOUNCE_MS:'0', WATCH_THROTTLE_MS:'0', WATCH_POLL_MS:'200' }, setup(root) {
    writeFileSync(join(root,'Scripts/restart.sh'), '#!/bin/sh\necho restart >> events\ntest -f restart-ready\n', {mode:0o755})
  } })
  await waitUntil(f, () => f.output().includes('Mac 构建或启动失败，监听继续'))
  writeFileSync(join(f.root,'restart-ready'),'')
  mkdirSync(join(f.root,'work/test-results'),{recursive:true})
  writeFileSync(join(f.root,'work/test-results/latest.json'),JSON.stringify({status:0,scope:'all',signature:'new-pass'}))
  await waitUntil(f, () => f.events().filter(v=>v==='restart').length===2)
  assert.equal(f.child.exitCode,null)
})

test('the running watcher loads corrected resident dependencies without a new terminal command', async t => {
  const f = watcherFixture(t, { env: { WATCH_DEBOUNCE_MS:'1000', WATCH_THROTTLE_MS:'0', WATCH_POLL_MS:'200' } })
  await waitUntil(f, () => f.output().includes('等待源码变更'))
  const path = join(f.root,'Scripts/desktop-notify.mjs')
  const source = readFileSync(path,'utf8')
  writeFileSync(path,source+'\ninvalid syntax !\n')
  await waitUntil(f, () => f.output().includes('监听脚本暂不能重新加载'))
  assert.equal(f.child.exitCode,null)
  writeFileSync(path,source+"\nimport {writeFileSync} from 'node:fs'; writeFileSync('runtime-version','v2')\n")
  await waitUntil(f, () => existsSync(join(f.root,'runtime-version')) && f.events().filter(v=>v==='restart').length===2)
  assert.equal(readFileSync(join(f.root,'runtime-version'),'utf8'),'v2')
  assert.equal(Number(readFileSync(join(f.root,'.git/benchgauge-watch.lock'),'utf8').split('\n')[0]), f.child.pid)
  assert.match(f.output(),/监听逻辑已更新/)
})

test('saves observed while the gate is busy stay queued until the newest version is checked',async t=>{
  const f=watcherFixture(t,{env:{WATCH_DEBOUNCE_MS:'0',WATCH_THROTTLE_MS:'0',WATCH_POLL_MS:'200'},setup(root){
    writeFileSync(join(root,'Scripts/test-repair.mjs'),`import{appendFileSync,readFileSync,existsSync}from'node:fs'
export async function runTestGate(){appendFileSync('events','test\\n');
if(readFileSync('events','utf8').split('\\n').filter(v=>v==='test').length===2){
appendFileSync('events','gate-waiting\\n');while(!existsSync('gate-release'))await new Promise(r=>setTimeout(r,20))}
return{status:0,signature:'mock-pass'}}`)
  }})
  await waitUntil(f,()=>f.output().includes('等待源码变更'))
  writeFileSync(f.source,'// starts a check')
  await waitUntil(f,()=>f.events().includes('gate-waiting'))
  writeFileSync(f.source,'// newer edit while busy')
  await waitUntil(f,()=>f.output().includes('当前正在提交、推送或构建，结束后再调度'))
  writeFileSync(join(f.root,'gate-release'),'')
  await waitUntil(f,()=>f.events().filter(v=>v==='restart').length===2)
  assert.equal(f.events().filter(v=>v==='test').length,3)
})

test('a clean externally committed app change is deployed without a source timestamp change',async t=>{
  const f=watcherFixture(t,{gitWork:true,env:{WATCH_DEBOUNCE_MS:'0',WATCH_THROTTLE_MS:'0',WATCH_POLL_MS:'200'},setup(root){
    writeFileSync(join(root,'commit.done'),'');writeFileSync(join(root,'push.done'),'')
  }})
  await waitUntil(f,()=>f.output().includes('等待源码变更'))
  writeFileSync(join(f.root,'head'),'external-head')
  await waitUntil(f,()=>f.events().filter(v=>v==='restart').length===2)
  assert.match(f.output(),/检测到已提交的应用变更/)
  assert.deepEqual(f.events(),['test','restart','test','build','restart'])
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
  await waitUntil(fixture, () => fixture.events().includes('push'))
  assert.deepEqual(fixture.events(), ['test', 'test', 'build', 'restart', 'commit', 'push'])
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

test('phone updates are checked at startup and after edits even with Mac deployment disabled', async (t) => {
  const fixture = watcherFixture(t, { phone: true, env: { APP_AUTODEPLOY: '0', WATCH_DEBOUNCE_MS: '0', WATCH_THROTTLE_MS: '0', WATCH_POLL_MS: '200' } })
  await waitUntil(fixture, () => fixture.output().includes('等待源码变更'))
  assert.deepEqual(fixture.events(), ['test', 'phone-check'])
  writeFileSync(fixture.source, '// phone update\n')
  await waitUntil(fixture, () => fixture.events().length === 4)
  assert.deepEqual(fixture.events(), ['test', 'phone-check', 'test', 'phone-check'])
})
test('a phone build failure leaves Mac delivery independent and a new edit recovers the phone', async (t) => {
  const fixture = watcherFixture(t, { phone: true, phoneFails: true, env: { WATCH_DEBOUNCE_MS: '0', WATCH_THROTTLE_MS: '0', WATCH_POLL_MS: '200' } })
  await waitUntil(fixture, () => fixture.output().includes('等待源码变更'))
  writeFileSync(fixture.testFile, 'phone-fail')
  await waitUntil(fixture, () => fixture.output().includes('iPhone 构建检查失败'))
  assert.deepEqual(fixture.events(), ['test', 'restart', 'phone-check', 'test', 'build', 'restart', 'phone-check'])
  await new Promise(resolve => setTimeout(resolve, 200))
  assert.equal(fixture.events().length, 7)
  writeFileSync(fixture.testFile, 'pass')
  await waitUntil(fixture, () => fixture.events().length === 11)
  assert.deepEqual(fixture.events().slice(-4), ['test', 'build', 'restart', 'phone-check'])
})

test('startup phone failure does not stop the Mac watcher or authorize Git actions', async t => {
  const f=watcherFixture(t,{phone:true,phoneFails:true,gitWork:true,
    env:{WATCH_DEBOUNCE_MS:'0',WATCH_THROTTLE_MS:'0',WATCH_POLL_MS:'200'},
    setup(root){writeFileSync(join(root,'Tests/example.swift'),'phone-fail')},
  })
  await waitUntil(f,()=>f.output().includes('Mac 已独立更新'))
  await new Promise(resolve=>setTimeout(resolve,250))
  assert.deepEqual(f.events(),['test','restart','phone-check'])
  assert.equal(f.child.exitCode,null)
})

test('invalid watch durations fail before any test, commit or restart', async t => {
  const f = watcherFixture(t, { env: { WATCH_DEBOUNCE_MS: 'invalid' } })
  assert.equal(await f.exited, 1)
  assert.match(f.output(), /WATCH_DEBOUNCE_MS 无效/)
  assert.deepEqual(f.events(), [])
})

test('source scan distinguishes permission denials, vanished files, directories and unexpected errors', async t => {
  for (const mode of ['denied-stat', 'denied-read', 'vanished', 'special', 'unexpected']) {
    const f = watcherFixture(t, { setup(root) {
      const hook = join(root, 'scan-hook.cjs')
      mkdirSync(join(root, 'Sources/denied'))
      writeFileSync(join(root, 'Sources/deny.swift'), 'fixture')
      writeFileSync(hook, `const fs=require('node:fs');const stat=fs.statSync,read=fs.readdirSync;
fs.statSync=(path,...args)=>{if(String(path).endsWith('/deny.swift')){if('${mode}'==='denied-stat'||'${mode}'==='unexpected')throw Object.assign(new Error('fixture scan failure'),{code:'${mode}'==='denied-stat'?'EPERM':'EIO'});if('${mode}'==='vanished')return undefined;if('${mode}'==='special')return {isFile:()=>false,isDirectory:()=>false}}return stat(path,...args)};
fs.readdirSync=(path,...args)=>{if(String(path).endsWith('/Sources/denied')&&'${mode}'==='denied-read')throw Object.assign(new Error('fixture denied'),{code:'EACCES'});return read(path,...args)};
require('node:module').syncBuiltinESMExports()`)
      return { NODE_OPTIONS: `${process.env.NODE_OPTIONS || ''} --require=${hook}`.trim() }
    } })
    if (mode === 'unexpected') { assert.equal(await f.exited, 1); assert.match(f.output(), /fixture scan failure/) }
    else {
      await waitUntil(f, () => f.output().includes('等待源码变更'))
      assert.deepEqual(f.events(), ['test', 'restart'])
      if (mode.startsWith('denied')) assert.match(f.output(), /无法读取/)
    }
  }
})

test('missing upstream and failed Git probes stay visible without an automatic push', async t => {
  for (const mode of ['no-upstream', 'denied', 'error', 'unknown', 'head-error']) {
    const f = watcherFixture(t, { gitWork: true, env: { WATCH_DEBOUNCE_MS: '0', WATCH_THROTTLE_MS: '0', WATCH_POLL_MS: '200' }, setup(root) {
      const hook = join(root, 'git-hook.cjs')
      writeFileSync(hook, `const cp=require('node:child_process');const original=cp.spawnSync;
cp.spawnSync=(command,args,options)=>{if(command==='git'&&args[0]==='rev-list'){
if('${mode}'==='no-upstream')return {status:1,stdout:''};
if('${mode}'==='denied'||'${mode}'==='error')return {error:Object.assign(new Error('fixture upstream error'),{code:'${mode}'==='denied'?'EACCES':'ENOENT'})};
if('${mode}'==='unknown')return {status:0,stdout:'invalid'};
return {status:0,stdout:'0 1'}};
if(command==='git'&&args[0]==='rev-parse'&&'${mode}'==='head-error')return {status:1,stdout:''};return original(command,args,options)};
require('node:module').syncBuiltinESMExports()`)
      return { NODE_OPTIONS: `${process.env.NODE_OPTIONS || ''} --require=${hook}`.trim() }
    } })
    await waitUntil(f, () => f.events().includes('commit'))
    await new Promise(accept => setTimeout(accept, 300))
    assert.equal(f.events().includes('push'), false)
    if (mode === 'no-upstream') assert.match(f.output(), /没有上游/)
    if (mode === 'error') assert.match(f.output(), /上游检查失败/)
    if (mode === 'denied') assert.doesNotMatch(f.output(), /上游检查失败/)
  }
})

test('a build failure stays blocked until a newer save arrives', async t => {
  const f = watcherFixture(t, { env: { WATCH_DEBOUNCE_MS: '0', WATCH_THROTTLE_MS: '0', WATCH_POLL_MS: '200' }, setup(root) {
    writeFileSync(join(root, 'Scripts/make-app.sh'), '#!/bin/sh\ncd "$(dirname "$0")/.."\necho build >> events\nexit 2\n', { mode: 0o755 })
  } })
  await waitUntil(f, () => f.output().includes('等待源码变更'))
  writeFileSync(f.source, '// changed to fail build\n')
  await waitUntil(f, () => f.output().includes('构建失败'))
  const count = f.events().filter(event => event === 'build').length
  await new Promise(accept => setTimeout(accept, 350))
  assert.equal(f.events().filter(event => event === 'build').length, count)
  assert.equal(f.events().filter(event => event === 'restart').length, 1)
})

test('temporary commit lock contention is retried, while an unchanged successful commit is blocked', async t => {
  for (const mode of ['busy', 'unchanged']) {
    const f = watcherFixture(t, { gitWork: true, env: { COMMIT_PUSH: '0', WATCH_DEBOUNCE_MS: '0', WATCH_THROTTLE_MS: '0', WATCH_POLL_MS: '200' }, setup(root) {
      writeFileSync(join(root, 'Scripts/commit.mjs'), `import{appendFileSync,existsSync,readFileSync,writeFileSync}from'node:fs';appendFileSync('events','commit\\n');const n=existsSync('attempt')?Number(readFileSync('attempt')):0;writeFileSync('attempt',String(n+1));if('${mode}'==='busy'&&n===0)process.exit(75);if('${mode}'==='busy'){writeFileSync('commit.done','done');writeFileSync('head','fixture-head-2')}`)
    } })
    if (mode === 'busy') {
      await waitUntil(f, () => f.output().includes('本轮流程完成'))
      assert.ok(f.events().filter(event => event === 'commit').length >= 2)
      assert.match(f.output(), /提交锁被占用/)
    } else {
      await waitUntil(f, () => f.output().includes('改动仍在'))
      const count = f.events().filter(event => event === 'commit').length
      writeFileSync(f.testFile, '// new test with the same dirty source fingerprint\n')
      await waitUntil(f, () => f.output().includes('这一版提交已失败'))
      assert.equal(f.events().filter(event => event === 'commit').length, count)
    }
  }
})

test('a failed push and a falsely successful push remain failed until a source change', async t => {
  for (const mode of ['failed', 'unchanged']) {
    const f = watcherFixture(t, { gitWork: true, env: { WATCH_DEBOUNCE_MS: '0', WATCH_THROTTLE_MS: '0', WATCH_POLL_MS: '200' }, setup(root) {
      writeFileSync(join(root, 'bin/git'), `#!/bin/sh
case "$1" in
status) test -f commit.done || printf ' M Sources/example.swift\\0';;
rev-list) echo '0 1';;
rev-parse) echo fixture-head;;
cat-file) exit 0;;
diff) echo Sources/example.swift;;
*) for arg in "$@"; do if test "$arg" = push; then echo push >> events; exit ${mode === 'failed' ? 2 : 0}; fi; done;;
esac
exit 0
`, { mode: 0o755 })
    } })
    await waitUntil(f, () => f.output().includes('推送失败'))
    const count = f.events().filter(event => event === 'push').length
    await new Promise(accept => setTimeout(accept, 350))
    assert.equal(f.events().filter(event => event === 'push').length, count)
    if (mode === 'unchanged') assert.match(f.output(), /上游仍落后/)
    else assert.match(f.output(), /git push 退出码 2/)
  }
})


test('another save resets a pending debounce timer before any commit',async t=>{
 const f=watcherFixture(t,{env:{WATCH_DEBOUNCE_MS:'700',WATCH_THROTTLE_MS:'0',WATCH_POLL_MS:'200'}})
 await waitUntil(f,()=>f.output().includes('等待源码变更'))
 writeFileSync(f.source,'// first save')
 await waitUntil(f,()=>f.output().includes('检测到源码变更'))
 const length=f.output().length
 writeFileSync(f.source,'// second save')
 await waitUntil(f,()=>f.output().slice(length).includes('检测到源码变更'))
 await waitUntil(f,()=>f.events().filter(v=>v==='restart').length===2)
 assert.equal(f.events().filter(v=>v==='build').length,1)
})

test('a failed test signature is not rerun solely because the upstream head changes',async t=>{
 const f=watcherFixture(t,{gitWork:true,testsFail:true,env:{APP_AUTODEPLOY:'0',WATCH_DEBOUNCE_MS:'0',WATCH_THROTTLE_MS:'0',WATCH_POLL_MS:'200'}})
 await waitUntil(f,()=>f.output().includes('启动测试失败'))
 writeFileSync(f.source,'// edited failing source')
 await waitUntil(f,()=>f.events().filter(v=>v==='test').length===2)
 await waitUntil(f,()=>f.output().includes('测试失败，已停止提交、推送和重建'))
 writeFileSync(join(f.root,'head'),'new-upstream-signature')
 await waitUntil(f,()=>f.output().includes('这一版测试已失败，等待下次保存'))
 assert.equal(f.events().filter(v=>v==='test').length,2)
})

test('edits arriving during a test are rechecked before the commit',async t=>{
 const f=watcherFixture(t,{gitWork:true,env:{APP_AUTODEPLOY:'0',WATCH_DEBOUNCE_MS:'0',WATCH_THROTTLE_MS:'0',WATCH_POLL_MS:'200'},setup(root){
  writeFileSync(join(root,'Scripts/test-repair.mjs'),`import{appendFileSync,writeFileSync,readFileSync}from'node:fs';export async function runTestGate(){appendFileSync('events','test\\n');if(readFileSync('events','utf8').split('\\n').filter(v=>v==='test').length===2)writeFileSync('Sources/example.swift','// newer save');return {status:0,signature:'mock-pass'}}`)
 }})
 await waitUntil(f,()=>f.output().includes('检查期间有新变更，重新验证'))
 await waitUntil(f,()=>f.events().includes('commit'))
 assert.ok(f.events().filter(v=>v==='test').length>=3)
})

test('watcher lock reporting covers an orphan launcher and an unverifiable owner',async t=>{
 const f=watcherFixture(t,{setup(root){
  writeFileSync(join(root,'Scripts/commit-lock.mjs'),`export function acquireCommitLock(options){if(options.launcherPid!==0)throw Error('wrong orphan marker');options.warn('fixture lock warning');return {acquired:false,owner:null}}`)
  writeFileSync(join(root,'hook.cjs'),`Object.defineProperty(process,'ppid',{value:1})`)
  return {NODE_OPTIONS:(process.env.NODE_OPTIONS||'')+` --require=${join(root,'hook.cjs')}`}
 }})
 assert.equal(await f.exited,75)
 assert.match(f.output(),/pid 未知/)
})


test('renamed paths fingerprint the destination and skip the old pathname', () => {
 const seen=[]
 const value=dirtyStatusSignature('R  new.swift\0old.swift\0',path=>{seen.push(path);return 'fixture'})
 assert.ok(value.includes('new.swift'));assert.ok(!seen.includes('old.swift'))
})

const quickWatch={WATCH_DEBOUNCE_MS:'0',WATCH_THROTTLE_MS:'0',WATCH_POLL_MS:'200',APP_AUTODEPLOY:'0'}

test('mini-program output and private settings do not schedule checks, dependency inputs do', async t => {
 const f=watcherFixture(t,{env:quickWatch,setup(root){
  mkdirSync(join(root,'apps/weapp/dist'),{recursive:true})
  writeFileSync(join(root,'apps/weapp/dist/app.js'),'generated')
  writeFileSync(join(root,'apps/weapp/project.private.config.json'),'{}')
  writeFileSync(join(root,'package.json'),'{}')
  writeFileSync(join(root,'pnpm-workspace.yaml'),'packages: []')
  writeFileSync(join(root,'pnpm-lock.yaml'),'initial')
 }})
 await waitUntil(f,()=>f.output().includes('等待源码变更'))
 const count=f.events().filter(event=>event==='test').length
 writeFileSync(join(f.root,'apps/weapp/dist/app.js'),'new generated output')
 writeFileSync(join(f.root,'apps/weapp/project.private.config.json'),'private setting')
 await new Promise(resolve=>setTimeout(resolve,500))
 assert.equal(f.events().filter(event=>event==='test').length,count)
 writeFileSync(join(f.root,'pnpm-lock.yaml'),'changed dependency')
 await waitUntil(f,()=>f.events().filter(event=>event==='test').length>count)
})

test('startup with clean source and unpushed commits only pushes',async t=>{
 const fixture=watcherFixture(t,{gitWork:true,env:quickWatch,setup(root){
  writeFileSync(join(root,'commit.done'),'done')
 }})
 await waitUntil(fixture,()=>fixture.output().includes('本轮流程完成'))
 assert.ok(fixture.output().includes('启动时检测到未推送提交'))
 assert.ok(fixture.events().includes('push'));assert.ok(!fixture.events().includes('commit'))
})

test('a Git-only edit is detected independently of source files',async t=>{
 const fixture=watcherFixture(t,{gitWork:true,env:quickWatch,setup(root){
  writeFileSync(join(root,'commit.done'),'done');writeFileSync(join(root,'push.done'),'done')
 }})
 await waitUntil(fixture,()=>fixture.output().includes('等待源码变更'))
 rmSync(join(fixture.root,'commit.done'))
 await waitUntil(fixture,()=>fixture.output().includes('本轮流程完成'))
 assert.ok(fixture.output().includes('检测到未提交改动'))
 assert.ok(fixture.events().includes('commit'))
})

test('unpushed commits appearing after startup schedule a push',async t=>{
 const fixture=watcherFixture(t,{gitWork:true,env:quickWatch,setup(root){
  writeFileSync(join(root,'commit.done'),'done');writeFileSync(join(root,'push.done'),'done')
 }})
 await waitUntil(fixture,()=>fixture.output().includes('等待源码变更'))
 rmSync(join(fixture.root,'push.done'))
 await waitUntil(fixture,()=>fixture.events().includes('push'))
 assert.ok(fixture.output().includes('检测到未推送提交'))
})

test('newly missing upstream is reported once during a scheduled run',async t=>{
 const fixture=watcherFixture(t,{gitWork:true,env:quickWatch,setup(root){
  writeFileSync(join(root,'commit.done'),'done');writeFileSync(join(root,'push.done'),'done')
  writeFileSync(join(root,'bin/git'),`#!/bin/sh
case "$1" in
status) ;; rev-list) if test -f no-upstream; then exit 1; else echo '0 0'; fi;;
rev-parse) echo fixture-head;; cat-file) exit 0;; esac
`,{mode:0o755})
 }})
 await waitUntil(fixture,()=>fixture.output().includes('等待源码变更'))
 writeFileSync(join(fixture.root,'no-upstream'),'fixture');writeFileSync(fixture.source,'// changed')
 await waitUntil(fixture,()=>fixture.output().includes('本轮流程完成'))
 assert.ok(fixture.output().includes('当前分支没有上游'))
})

test('a scheduled push reports a nonzero exit and waits for a new change before retrying',async t=>{
 const fixture=watcherFixture(t,{gitWork:true,env:{...quickWatch,COMMIT_PUSH:'1',WATCH_AUTOPUSH:'1'},setup(root){
  writeFileSync(join(root,'commit.done'),'done');writeFileSync(join(root,'push.done'),'done')
  writeFileSync(join(root,'bin/git'),`#!/bin/sh
case "$1" in
status) ;;
rev-list) if test -f push.done; then echo '0 0'; else echo '0 1'; fi;;
rev-parse) echo fixture-head;;
cat-file) exit 0;;
*) for arg in "$@"; do if test "$arg" = push; then echo push >> events; exit 2; fi; done;;
esac
`,{mode:0o755})
 }})
 await waitUntil(fixture,()=>fixture.output().includes('等待源码变更'))
 rmSync(join(fixture.root,'push.done'))
 await waitUntil(fixture,()=>fixture.output().includes('git push 退出码 2'))
 await new Promise(accept=>setTimeout(accept,500))
 assert.equal(fixture.events().filter(event=>event==='push').length,1)
 assert.equal(fixture.child.exitCode,null)
})

test('unexpected scheduled test errors are reported and leave the watcher running',async t=>{
 const fixture=watcherFixture(t,{env:quickWatch,setup(root){
  writeFileSync(join(root,'Scripts/test-repair.mjs'),`import{existsSync,writeFileSync}from'node:fs';export async function runTestGate(){if(existsSync('gate-called'))throw Error('fixture gate failure');writeFileSync('gate-called','done');return {status:0,signature:'mock-pass'}}`)
 }})
 await waitUntil(fixture,()=>fixture.output().includes('等待源码变更'))
 writeFileSync(fixture.source,'// changed')
 await waitUntil(fixture,()=>fixture.output().includes('本轮已停止自动重试'))
 assert.ok(fixture.output().includes('fixture gate failure'));assert.equal(fixture.child.exitCode,null)
})

test('a push spawn failure is reported without touching real Git',async t=>{
 const fixture=watcherFixture(t,{gitWork:true,env:quickWatch,setup(root){
  writeFileSync(join(root,'commit.done'),'done')
  const hook=join(root,'unit-preload.cjs')
  writeFileSync(hook,`const cp=require('node:child_process'),{EventEmitter}=require('node:events'),{syncBuiltinESMExports}=require('node:module');const original=cp.spawn;cp.spawn=(command,args,options)=>{if(command==='git'&&args.includes('push')){const child=new EventEmitter();queueMicrotask(()=>child.emit('error',Error('fixture push spawn')));return child}return original(command,args,options)};syncBuiltinESMExports()`)
  return {NODE_OPTIONS:(process.env.NODE_OPTIONS||'')+' --require '+hook}
 }})
 await waitUntil(fixture,()=>fixture.output().includes('本轮已停止自动重试'))
 assert.ok(fixture.output().includes('fixture push spawn'))
})

test('polling filesystem failures are reported without stopping the watcher',async t=>{
 const fixture=watcherFixture(t,{env:quickWatch,setup(root){
  const hook=join(root,'unit-preload.cjs')
  writeFileSync(hook,`const fs=require('node:fs'),{syncBuiltinESMExports}=require('node:module');const original=fs.statSync;fs.statSync=(file,...args)=>{if(String(file).endsWith('example.swift')&&fs.existsSync('poll-fail'))throw Error('fixture stat failure');return original(file,...args)};syncBuiltinESMExports()`)
  return {NODE_OPTIONS:(process.env.NODE_OPTIONS||'')+' --require '+hook}
 }})
 await waitUntil(fixture,()=>fixture.output().includes('等待源码变更'))
 writeFileSync(join(fixture.root,'poll-fail'),'fixture')
 await waitUntil(fixture,()=>fixture.output().includes('扫描源码失败'))
 assert.equal(fixture.child.exitCode,null)
})

test('edits made during the build schedule a new test and rebuild before settling',async t=>{
 const f=watcherFixture(t,{env:{WATCH_DEBOUNCE_MS:'0',WATCH_THROTTLE_MS:'0',WATCH_POLL_MS:'200'},setup(root){
  writeFileSync(join(root,'Scripts/make-app.sh'),`#!/bin/sh
cd "$(dirname "$0")/.."
echo build >> events
if ! test -f build.edited; then touch build.edited; echo '// newer edit during build' > Sources/example.swift; fi
touch outputs/AI-BenchGauge.app/Contents/MacOS/leaderboard-menu
`,{mode:0o755})
 }})
 await waitUntil(f,()=>f.output().includes('等待源码变更'))
 writeFileSync(f.source,'// first edit')
 await waitUntil(f,()=>f.events().filter(event=>event==='build').length===2 && f.output().includes('本轮流程完成'))
 assert.ok(f.output().includes('运行期间有新变更'))
 assert.equal(f.events().filter(event=>event==='test').length,3)
})

// A child may finish with progress output instead of a trailing newline. The
// persistent footer must receive the failure as its own status record even
// when the parent launcher was loaded before its embedded-status parser fix.
test('manual failure starts a separate status record after unterminated child output', async t => {
  const fixture = watcherFixture(t, { setup(root) {
    writeFileSync(join(root, 'Scripts/test-repair.mjs'), `export async function runTestGate() {
      process.stdout.write('last child progress without newline')
      return { status: 1, signature: 'failed', logPath: 'mock.log' }
    }`)
  } })
  await waitUntil(fixture, () => fixture.output().includes('需人工介入'))
  const records = fixture.output().split(/\r?\n/)
  assert.ok(records.some(line => /^\[watch\] ⚠【需人工介入】 (?:启动)?测试失败/.test(line)), fixture.output())
  assert.ok(records.some(line => line.startsWith('last child progress without newline') && !line.includes('需人工介入')), fixture.output())
  assert.deepEqual(fixture.events(), [])
  const { createDevStatus } = await ci.load('dev-status')
  const { createDevFormatter } = await ci.load('dev-output')
  const tty = new Writable({ write(_chunk, _encoding, done) { done() } })
  tty.isTTY = true; tty.rows = 24; tty.columns = 179
  const dashboard = createDevStatus({ stdout: tty, stderr: tty,
    readRepoStatus: async () => ({ known: true, clean: true, staged: 0, unstaged: 0, untracked: 0, conflicts: 0, ahead: 0, behind: 0 }),
    readActivities: async () => new Map() })
  t.after(() => dashboard.close())
  const project = { name: 'ai-benchgauge', root: fixture.root }
  const stream = dashboard.forProject(project), format = createDevFormatter(project)
  for (const line of records) stream.log(format(line))
  for (let i = 0; i < 40; i++) stream.log(format('[desktop-notify] 系统已接受通知'))
  await stream.flush()
  assert.equal(dashboard.snapshot()[0].manual, true)
  assert.match(dashboard.snapshot()[0].message, /需人工介入.*测试失败/)
})
