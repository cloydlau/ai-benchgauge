import test from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import cp from 'node:child_process'
import { syncBuiltinESMExports } from 'node:module'
import { EventEmitter } from 'node:events'
import { dirname, join, resolve } from 'node:path'
import { tmpdir } from 'node:os'
import { pathToFileURL } from 'node:url'
import { fullCoverageReuseSignature, nativeTestAvailability, runTests, testCommands, testInputSignature, testEnvironment } from './test.mjs'
import { runTestGate } from './test-repair.mjs'
import { cacheLock } from './build-cache.mjs'
import { acquireCommitLock } from './commit-lock.mjs'
import { coverageSummaryDigest } from './test-reuse.mjs'

function fixture(t) {
  const root = fs.realpathSync(fs.mkdtempSync(join(tmpdir(), 'benchgauge-runner-unit-')))
  for (const path of ['Sources', 'Tests', 'Scripts']) fs.mkdirSync(join(root, path))
  fs.writeFileSync(join(root, 'Scripts/fixture.test.mjs'), '')
  t.after(() => fs.rmSync(root, { recursive: true, force: true }))
  return root
}
const logger = { log() {}, error() {} }

test('coverage proof fails closed when the shared library is missing or unspecified', t => {
  const root = fixture(t)
  const env = { ...process.env, CALMMIT_PATH: '' }
  fs.writeFileSync(join(root, 'calmmit.config.json'), '{}')
  assert.equal(fullCoverageReuseSignature(root, env, { available: true }), null)
  env.CALMMIT_PATH = join(root, 'missing-library')
  assert.equal(fullCoverageReuseSignature(root, env, { available: true }), null)
})

test('explicit native availability stays consistent when host Xcode differs', async t => {
  const root = fixture(t)
  fs.mkdirSync(join(root, 'library/src'), { recursive: true })
  fs.writeFileSync(join(root, 'library/src/fixture.mjs'), 'shared')
  fs.writeFileSync(join(root, 'calmmit.config.json'), JSON.stringify({ library: 'library' }))
  fs.writeFileSync(join(root, 'README.md'), 'before')
  const originalExists = fs.existsSync
  t.mock.method(fs, 'existsSync', path => String(path) === '/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild' || originalExists(path))
  t.mock.method(cp, 'spawnSync', (command, args) => {
    if (command === 'xcode-select') return { status: 0, stdout: '/Library/Developer/CommandLineTools\n' }
    if (command === 'git' && args.includes('ls-files')) return { status: 0, stdout: Buffer.from('README.md\0calmmit.config.json\0Scripts/fixture.test.mjs\0') }
    if (command === 'git' && args.includes('--show-origin')) return { status: 0, stdout: Buffer.from('git-config') }
    if (command === '/usr/bin/which') return { status: 1, stdout: '' }
    if (args[0] === '--expose-internals') { fs.mkdirSync(args[2], { recursive: true }); fs.writeFileSync(join(args[2], 'summary.json'), '{}') }
    return { status: 0, stdout: '', stderr: '' }
  })
  t.mock.method(cp, 'spawn', () => {
    const child = new EventEmitter(); child.stdout = new EventEmitter(); child.stderr = new EventEmitter()
    queueMicrotask(() => child.emit('close', 0)); return child
  })
  syncBuiltinESMExports()
  t.after(() => { t.mock.restoreAll(); syncBuiltinESMExports() })
  const env = { ...process.env, CALMMIT_PATH: '' }
  for (const key of ['DEVELOPER_DIR', 'TOOLCHAINS', 'SDKROOT', 'SWIFT_EXEC', 'SWIFT_DRIVER_SWIFT_FRONTEND_EXEC']) delete env[key]
  const result = await runTests({ root, logger, nativeAvailable: false, coverage: true, env })
  assert.equal(result.status, 0)
  assert.match(result.reuseFingerprint, /^[a-f0-9]{64}$/)
  assert.match(result.coverageDigest, /^[a-f0-9]{64}$/)
})

for (const mode of ['stable', 'changed', 'missing-summary']) test(`coverage receipt attests only a stable complete run: ${mode}`, async t => {
  const root = fixture(t)
  fs.mkdirSync(join(root, 'library/src'), { recursive: true })
  fs.writeFileSync(join(root, 'library/src/fixture.mjs'), 'shared')
  fs.writeFileSync(join(root, 'calmmit.config.json'), JSON.stringify({ library: 'library' }))
  fs.writeFileSync(join(root, 'README.md'), 'before')
  t.mock.method(cp, 'spawnSync', (command, args) => {
    if (command === 'git' && args.includes('ls-files')) return { status: 0, stdout: Buffer.from('README.md\0calmmit.config.json\0Scripts/fixture.test.mjs\0') }
    if (command === 'git' && args.includes('--show-origin')) return { status: 0, stdout: Buffer.from('git-config') }
    if (command === '/usr/bin/which') return { status: 1, stdout: '' }
    if (args[0] === '--expose-internals') {
      fs.mkdirSync(args[2], { recursive: true })
      if (mode !== 'missing-summary') fs.writeFileSync(join(args[2], 'summary.json'), '{}')
      return { status: 0, stdout: '', stderr: '' }
    }
    return { status: 0, stdout: '', stderr: '' }
  })
  t.mock.method(cp, 'spawn', () => {
    const child = new EventEmitter(); child.stdout = new EventEmitter(); child.stderr = new EventEmitter()
    queueMicrotask(() => {
      if (mode === 'changed') fs.writeFileSync(join(root, 'README.md'), 'after')
      child.emit('close', 0)
    })
    return child
  })
  syncBuiltinESMExports()
  t.after(() => { t.mock.restoreAll(); syncBuiltinESMExports() })
  const result = await runTests({ root, logger, nativeAvailable: false, coverage: true, env: { ...process.env, CALMMIT_PATH: '' } })
  assert.equal(result.status, 0)
  assert.equal(Boolean(result.reuseFingerprint), mode === 'stable')
  assert.equal(Boolean(result.coverageDigest), mode === 'stable')
})
function mockCommands(t, { mode = '', collector = 0 } = {}) {
  const calls = []
  t.mock.method(cp, 'spawnSync', (command, args, options) => {
    calls.push([command, args, options])
    return args[0] === '--expose-internals'
      ? { status: collector, stdout: 'fixture coverage output\n', stderr: 'fixture collector diagnostic\n' }
      : { status: 0, stdout: undefined }
  })
  t.mock.method(cp, 'spawn', (command, args, options) => {
    calls.push([command, args, options])
    const child = new EventEmitter(); child.stdout = new EventEmitter(); child.stderr = new EventEmitter()
    queueMicrotask(() => {
      child.stdout.emit('data', Buffer.from('fixture output\n'))
      child.stderr.emit('data', Buffer.from('fixture error stream\n'))
      if (mode === 'error') child.emit('error', new Error('fixture child failed'))
      const native = args[0]?.endsWith('swift-coverage.cjs') && (mode === 'native-clear-failure' ? args.includes('--clear') : mode === 'native-report-failure' && !args.includes('--clear'))
      child.emit('close', mode === 'null' ? null : mode === 'failure' || native ? 2 : 0)
    })
    return child
  })
  syncBuiltinESMExports()
  t.after(() => { t.mock.restoreAll(); syncBuiltinESMExports() })
  return calls
}

for (const mode of ['', 'failure']) test(`shared scheduling preserves native job limits, timing output and child status: ${mode || 'success'}`, async t => {
  const root = fixture(t), calls = mockCommands(t, { mode }), messages = []
  const library = join(root, 'shared library')
  fs.mkdirSync(join(library, 'src'), { recursive: true })
  fs.writeFileSync(join(root, 'calmmit.config.json'), JSON.stringify({ library }))
  const modulePath = join(library, 'src/business-tests.mjs')
  fs.writeFileSync(modulePath, `
export const prepared = [], timings = []
export const selfTestConcurrency = () => 3
export function prepareNodeTestCommand(command, args, { root }) {
  prepared.push({ command, args, root })
  return args[0] === '--test' ? { command: 'fixture-scheduled-node', args: ['fixture-scheduler', ...args] } : null
}
export function recordCommandTiming(entry) {
  timings.push(entry)
  entry.output('fixture timing recorded')
}
`)
  const result = await runTests({ root, nativeAvailable: true, env: { ...process.env, CALMMIT_PATH: '' },
    logger: { log: message => messages.push(message), error() {} } })
  const runtime = await import(pathToFileURL(modulePath).href)
  const scheduled = calls.find(call => call[0] === 'fixture-scheduled-node')
  assert.ok(scheduled, 'Node suites must use the shared scheduler command')
  assert.equal(scheduled[1][0], 'fixture-scheduler')
  assert.equal(scheduled[1][1], '--test')
  assert.ok(scheduled[1].includes(join(root, 'Scripts/fixture.test.mjs')))
  assert.equal(result.status, mode === 'failure' ? 2 : 0)
  assert.equal(Boolean(result.signature), mode !== 'failure')
  assert.deepEqual(runtime.prepared.map(entry => entry.root), mode === 'failure' ? [root] : [root, root])
  assert.deepEqual(runtime.timings.map(entry => [entry.cwd, entry.command, entry.args, entry.status]),
    runtime.prepared.map(entry => [root, entry.command, entry.args, result.status]))
  assert.ok(runtime.timings.every(entry => Number.isFinite(entry.durationMs) && entry.durationMs >= 0))
  assert.equal(messages.filter(message => message === 'fixture timing recorded').length, runtime.timings.length)
  const swift = calls.find(call => call[0] === 'swift')
  if (mode === 'failure') assert.equal(swift, undefined, 'A failed Node suite must block native tests')
  else {
    assert.deepEqual(swift[1], runtime.prepared.find(entry => entry.command === 'swift').args,
      'Commands outside Node testing must retain their original arguments')
    assert.equal(swift[1][swift[1].indexOf('--jobs') + 1], '3')
  }
})

test('Xcode discovery reads the caller selection and safely retains it when discovery fails', t => {
  const root = fixture(t), xcodeDeveloperDir = join(root, 'Xcode.app/Contents/Developer')
  fs.mkdirSync(join(xcodeDeveloperDir, 'usr/bin'), { recursive: true })
  fs.writeFileSync(join(xcodeDeveloperDir, 'usr/bin/xcodebuild'), '')
  const env = { PATH: '/fixture/bin' }, options = { platform: 'darwin', xcodeDeveloperDir }
  let output = { status: 0, stdout: '/Library/Developer/CommandLineTools\n' }
  t.mock.method(cp, 'spawnSync', (command, args, config) => {
    assert.equal(command, 'xcode-select'); assert.deepEqual(args, ['-p']); assert.equal(config.env, env)
    return output
  })
  syncBuiltinESMExports()
  t.after(() => { t.mock.restoreAll(); syncBuiltinESMExports() })
  assert.equal(testEnvironment(env, options).DEVELOPER_DIR, xcodeDeveloperDir)
  output = { status: 1 }
  assert.equal(testEnvironment(env, options), env)
  assert.equal(nativeTestAvailability(env, { ...options, xcodeDeveloperDir: join(root, 'Missing Xcode') }).available, false)
  output = { status: 1, stdout: '' }
  assert.equal(nativeTestAvailability(env, { ...options, xcodeDeveloperDir: join(root, 'Missing Xcode') }).available, false)
})

test('real runner default command path streams output and isolates inherited private state', async t => {
  const root = fixture(t), calls = mockCommands(t)
  const result = await runTests({ root, logger, nativeAvailable: true,
    env: { ...process.env, GIT_INDEX_FILE: 'fixture-private-index', BENCHGAUGE_TEST_PASS: 'fixture-parent-pass' } })
  assert.equal(result.status, 0)
  assert.equal(calls.filter(call => call[0] === 'swift').length, 1)
  assert.ok(result.signature)
  const childEnv = calls.find(call => call[1][0] === '--test')[2].env
  assert.equal(childEnv.GIT_INDEX_FILE, undefined); assert.equal(childEnv.BENCHGAUGE_TEST_PASS, undefined)
  assert.equal(childEnv.TZ, 'Asia/Shanghai')
  assert.equal(calls.find(call => call[0] === 'xcrun')[2].env.DEVELOPER_DIR, childEnv.DEVELOPER_DIR,
    'Plugin discovery and the Swift child must use the same developer directory')
  assert.match(fs.readFileSync(result.logPath, 'utf8'), /fixture output/)
  assert.match(fs.readFileSync(result.logPath, 'utf8'), /fixture error stream/)
  const gated = await runTestGate({ root, env: { ...process.env, TEST_AUTO_REPAIR: '0' } })
  assert.equal(gated.status, 0, 'Default test gate must actually invoke the runner')
})

test('missing full Xcode warns, skips native coverage, and keeps other suites running', async t => {
  const root = fixture(t), calls = mockCommands(t), messages = []
  const result = await runTests({ root, coverage: true, nativeAvailable: false,
    logger: { log: message => messages.push(message), error() {} } })
  assert.equal(result.status, 0)
  assert.ok(result.signature)
  assert.equal(result.skipped[0].suite, 'swift')
  assert.ok(messages.some(message => message.includes('已跳过 Swift/iOS 原生测试')))
  assert.match(fs.readFileSync(result.logPath, 'utf8'), /已跳过 Swift\/iOS 原生测试/)
  assert.equal(calls.some(call => call[0] === 'swift'), false)
  assert.equal(calls.some(call => call[1].some(arg => String(arg).endsWith('swift-coverage.cjs'))), false)
  assert.ok(calls.some(call => call[1][0] === '--test'))
  assert.ok(calls.some(call => call[1][0] === '--expose-internals'))
})

test('coverage collector is mandatory after successful instrumented children', async t => {
  const root = fixture(t), calls = mockCommands(t, { collector: 1 })
  const result = await runTests({ root, logger, scriptsOnly: true, coverage: true, env: { ...process.env, NODE_OPTIONS: '' } })
  assert.equal(result.status, 1)
  assert.ok(result.coverageDirectory)
  const child = calls.find(call => call[1][0] === '--test')
  assert.equal(child[2].env.NODE_V8_COVERAGE, result.coverageDirectory)
  assert.equal(child[2].env.BENCHGAUGE_COVERAGE_ROOT, root)
  assert.match(child[2].env.NODE_OPTIONS, /coverage-preload.cjs/)
  assert.ok(calls.some(call => call[1][0] === '--expose-internals'))
  assert.match(fs.readFileSync(result.logPath, 'utf8'), /fixture collector diagnostic/)
})

for (const mode of ['error', 'null', 'failure']) test(`child ${mode} cannot produce a passing receipt`, async t => {
  const root = fixture(t); mockCommands(t, { mode })
  const result = await runTests({ root, logger, commands: [['fixture-command', []]] })
  assert.equal(result.status, mode === 'failure' ? 2 : 1)
  assert.equal(result.signature, null)
  if (mode === 'error') assert.match(fs.readFileSync(result.logPath, 'utf8'), /fixture child failed/)
})

test('runner waits for an owned lock and rehashes edits made during the wait', async t => {
  const root = fixture(t)
  let entered, finish
  const started = new Promise(accept => { entered = accept })
  const first = runTests({ root, logger, commands: [['fixture', []]], run: async () => { entered(); return new Promise(accept => { finish = accept }) } })
  await started
  const before = testInputSignature(root)
  const waiting = runTests({ root, logger, commands: [['fixture', []]], lockWaitMs: 100, run: async () => 0 })
  fs.writeFileSync(join(root, 'Sources/fixture.swift'), 'edited while waiting')
  finish(1)
  await first
  const result = await waiting
  assert.equal(result.status, 0); assert.notEqual(result.signature, before)
  let enteredAgain, finishAgain
  const startAgain = new Promise(accept => { enteredAgain = accept })
  const held = runTests({ root, logger, commands: [['fixture', []]], run: async () => { enteredAgain(); return new Promise(accept => { finishAgain = accept }) } })
  await startAgain
  const busy = await runTests({ root, logger, commands: [['fixture', []]], lockWaitMs: 100, run: async () => 0 })
  assert.equal(busy.status, 75); assert.match(busy.error, /等待超时/)
  finishAgain(0); await held
  await assert.rejects(runTests({ root, coreOnly: true, scriptsOnly: true }), /不能同时/)
})

for (const mode of ['busy', 'released', 'source-changed', 'failed', 'partial', 'summary-changed', 'environment-changed', 'index-mismatch', 'manual']) {
  test(`waiting coverage gates validate a concurrent complete proof: ${mode}`, async t => {
    const root = fixture(t)
    fs.mkdirSync(join(root, 'library/src'), { recursive: true })
    fs.writeFileSync(join(root, 'library/src/fixture.mjs'), 'shared')
    fs.writeFileSync(join(root, 'calmmit.config.json'), JSON.stringify({ library: 'library' }))
    fs.writeFileSync(join(root, 'Sources/fixture.swift'), 'before')
    t.mock.method(cp, 'spawnSync', (command, args) => {
      if (command === 'git' && args.includes('ls-files')) return { status: 0, stdout: Buffer.from('Sources/fixture.swift\0calmmit.config.json\0Scripts/fixture.test.mjs\0') }
      if (command === 'git' && args.includes('--show-origin')) return { status: 0, stdout: Buffer.from('git-config') }
      if (command === '/usr/bin/which') return { status: 1, stdout: '' }
      return { status: 0, stdout: '', stderr: '' }
    })
    let children = 0
    t.mock.method(cp, 'spawn', () => { children++; throw new Error('A verified concurrent proof must not spawn another suite') })
    syncBuiltinESMExports()
    t.after(() => { t.mock.restoreAll(); syncBuiltinESMExports() })
    const env = { ...process.env, CALMMIT_PATH: '' }
    for (const key of ['BENCHGAUGE_TEST_PASS', 'COMMIT_REQUIRE_LOCK', 'CALMMIT_TEST_INDEX']) delete env[key]
    if (mode === 'index-mismatch') env.CALMMIT_TEST_INDEX = join(root, 'missing-commit-index')
    const directory = join(root, 'work/test-results')
    const coverageDirectory = join(directory, 'coverage-123-456')
    fs.mkdirSync(coverageDirectory, { recursive: true })
    fs.writeFileSync(join(coverageDirectory, 'summary.json'), '{}')
    const receipt = { status: 0, scope: 'all', coverage: true,
      signature: testInputSignature(root, env), reuseFingerprint: fullCoverageReuseSignature(root, env),
      coverageDirectory, coverageDigest: coverageSummaryDigest(root, coverageDirectory) }
    assert.match(receipt.reuseFingerprint, /^[a-f0-9]{64}$/)
    fs.writeFileSync(join(directory, 'latest.log'), 'concurrent log')
    const held = acquireCommitLock({ lockPath: join(directory, 'test.lock') })
    assert.equal(held.acquired, true)
    t.after(() => held.release())
    const messages = []
    const waiting = runTests({ root, env, gate: mode !== 'manual', coverage: true, lockWaitMs: 30,
      logger: { log: message => messages.push(message), error() {} } })
    if (mode === 'source-changed') fs.writeFileSync(join(root, 'Sources/fixture.swift'), 'after')
    if (mode === 'failed') receipt.status = 1
    if (mode === 'partial') receipt.scope = 'scripts'
    if (mode === 'summary-changed') fs.writeFileSync(join(coverageDirectory, 'summary.json'), '{"changed":true}')
    if (mode === 'environment-changed') receipt.reuseFingerprint = '0'.repeat(64)
    const serialized = JSON.stringify(receipt)
    fs.writeFileSync(join(directory, 'latest.json'), serialized)
    if (mode === 'released') held.release()
    const result = await waiting
    const valid = mode === 'busy' || mode === 'released'
    assert.equal(result.status, valid ? 0 : 75)
    assert.equal(result.reused, valid ? true : undefined)
    assert.equal(children, 0)
    assert.equal(messages.filter(message => message.includes('等待正在运行')).length, 1)
    assert.equal(fs.readFileSync(join(directory, 'latest.log'), 'utf8'), 'concurrent log')
    assert.equal(fs.readFileSync(join(directory, 'latest.json'), 'utf8'), serialized)
    assert.equal(fs.existsSync(join(directory, 'test.lock')), mode !== 'released')
  })
}

for (const mode of ['missing', 'unchanged']) test(`waiting coverage gates reject ${mode} receipts across repeated polls`, async t => {
  const root = fixture(t), calls = mockCommands(t)
  const directory = join(root, 'work/test-results')
  fs.mkdirSync(directory, { recursive: true })
  const receiptPath = join(directory, 'latest.json')
  const receipt = JSON.stringify({ status: 1, scope: 'all', coverage: true })
  if (mode === 'unchanged') fs.writeFileSync(receiptPath, receipt)
  fs.writeFileSync(join(directory, 'latest.log'), 'previous failure')
  const lockPath = join(directory, 'test.lock')
  const held = acquireCommitLock({ lockPath })
  assert.equal(held.acquired, true)
  t.after(() => held.release())
  const lockContents = fs.readFileSync(lockPath, 'utf8')
  const read = fs.readFileSync
  let clock = Date.now(), receiptReads = 0
  t.mock.method(Date, 'now', () => clock)
  t.mock.method(fs, 'readFileSync', (path, ...args) => {
    if (path === receiptPath) {
      receiptReads++
      // Advance only on receipt reads so host scheduling cannot consume the
      // deadline before the missing/unchanged receipt has been polled again.
      clock++
    }
    return read(path, ...args)
  })
  syncBuiltinESMExports()
  const messages = []
  const result = await runTests({ root, nativeAvailable: true, gate: true, coverage: true, lockWaitMs: 3,
    logger: { log: message => messages.push(message), error() {} } })
  assert.equal(result.status, 75)
  assert.equal(result.signature, null)
  assert.equal(result.reused, undefined)
  assert.match(result.error, /等待超时/)
  // Missing: three failed reads. Unchanged: initial read plus validation,
  // then one repeat read; the unchanged failure must not be validated twice.
  assert.equal(receiptReads, 3)
  assert.equal(calls.some(call => call[2]?.stdio), false, 'Waiting must not spawn test children')
  assert.equal(messages.filter(message => message.includes('等待正在运行')).length, 1)
  assert.equal(read(join(directory, 'latest.log'), 'utf8'), 'previous failure')
  assert.equal(read(lockPath, 'utf8'), lockContents)
  if (mode === 'unchanged') assert.equal(read(receiptPath, 'utf8'), receipt)
  else assert.equal(fs.existsSync(receiptPath), false)
})

test('runner waits for the shared native-build lease before executing native tests', async t => {
  const root = fixture(t); mockCommands(t)
  const held = await cacheLock(root)
  const messages = []
  const running = runTests({ root, nativeAvailable: true, logger: { log: message => messages.push(message), error() {} } })
  setTimeout(() => held.release(), 10)
  const result = await running
  assert.equal(result.status, 0)
  assert.ok(messages.some(message => message.includes('等待当前构建结束')))
  assert.equal(fs.existsSync(join(root, 'work/build-cache/native.lock')), false)
})

test('relocated Swift workspaces recover under the cache lease before native tests', async t => {
  const root = fixture(t), backups = [], messages = [], rename = fs.renameSync
  for (const name of ['.build', 'work/unit-test-build']) {
    const cache = join(root, name)
    fs.mkdirSync(join(cache, 'artifacts/fixture/Kit.xcframework'), { recursive: true })
    fs.writeFileSync(join(cache, 'workspace-state.json'), JSON.stringify({ object: { artifacts: [{ source: { type: 'remote' },
      path: join('/previous/project', name, 'artifacts/fixture/Kit.xcframework') }] } }))
  }
  t.mock.method(fs, 'renameSync', (from, to) => {
    if ([join(root, '.build'), join(root, 'work/unit-test-build')].includes(from)) {
      assert.equal(fs.existsSync(join(root, 'work/build-cache/native.lock')), true)
      backups.push(dirname(to))
    }
    return rename(from, to)
  })
  mockCommands(t)
  t.after(() => { for (const path of backups) fs.rmSync(path, { recursive: true, force: true }) })
  const result = await runTests({ root, nativeAvailable: true, logger: { log: message => messages.push(message), error() {} } })
  assert.equal(result.status, 0)
  assert.equal(backups.length, 2)
  assert.ok(messages.some(message => message.includes('仓库搬迁')))
})

test('Windows test target is included and unsupported files do not affect signatures', t => {
  const root = fixture(t); mockCommands(t)
  fs.mkdirSync(join(root, 'apps/windows/BenchGauge.Tests'), { recursive: true })
  fs.writeFileSync(join(root, 'apps/windows/BenchGauge.Tests/BenchGauge.Tests.csproj'), 'fixture')
  assert.equal(testCommands(root, { scriptsOnly: true }).length, 2)
  fs.mkdirSync(join(root, 'Sources/bin')); fs.writeFileSync(join(root, 'Sources/bin/ignored'), '')
  fs.writeFileSync(join(root, 'Sources/.hidden'), '')
  const originalStat = fs.statSync
  t.mock.method(fs, 'statSync', (path, ...args) => String(path).endsWith('fixture.socket') ? { isDirectory: () => false, isFile: () => false } : originalStat(path, ...args))
  fs.writeFileSync(join(root, 'Sources/fixture.socket'), '')
  syncBuiltinESMExports()
  const before = testInputSignature(root)
  fs.writeFileSync(join(root, 'Sources/fixture.socket'), 'ignored')
  assert.equal(testInputSignature(root), before)
})


test('runner CLI validates flags, forwards lock errors and executes only isolated fixture commands', t => {
  const root=fixture(t)
  fs.copyFileSync(new URL('./test.mjs',import.meta.url),join(root,'Scripts/test.mjs'))
  fs.copyFileSync(new URL('./test-reuse.mjs',import.meta.url),join(root,'Scripts/test-reuse.mjs'))
  fs.copyFileSync(new URL('./build-cache.mjs',import.meta.url),join(root,'Scripts/build-cache.mjs'))
  fs.copyFileSync(new URL('./prepare-swift-workspace.mjs',import.meta.url),join(root,'Scripts/prepare-swift-workspace.mjs'))
  fs.writeFileSync(join(root,'Scripts/commit-lock.mjs'), `export const pidState=()=> 'gone'; export const acquireCommitLock=()=>process.env.UNIT_BUSY==='1'?{acquired:false,reason:'error'}:{acquired:true,release(){}}`)
  fs.writeFileSync(join(root,'Scripts/node-executable.mjs'), `export const nodeExecutable=()=>process.execPath`)
  fs.writeFileSync(join(root,'Scripts/test-repair.mjs'), `export const runTestGate=async()=>({status:0});export const readBoundCoveragePass=()=>process.env.UNIT_REUSE==='1'?{status:0,reused:true}:null;export const readSharedCoveragePass=({requireIndex}={})=>{if(process.env.UNIT_EXPECT_INDEX==='1'&&!requireIndex)throw Error('private index validation is required');return process.env.UNIT_SHARED==='1'?{status:0,reused:true}:null}`)
  fs.writeFileSync(join(root,'hook.cjs'), `const cp=require('node:child_process'),{EventEmitter}=require('node:events');cp.spawnSync=()=>({status:0});cp.spawn=()=>{const child=new EventEmitter();child.stdout=new EventEmitter();child.stderr=new EventEmitter();queueMicrotask(()=>child.emit('close',0));return child};require('node:module').syncBuiltinESMExports();`)
  const invoke=(args=[],env={})=>cp.spawnSync(process.execPath,['--require',join(root,'hook.cjs'),join(root,'Scripts/test.mjs'),...args],{encoding:'utf8',env:{...process.env,...env}})
  for(const args of [[],['--core'],['--scripts'],['--core','--coverage'],['--gate']]) assert.equal(invoke(args).status,0)
  assert.match(invoke(['--unknown']).stderr,/用法/)
  assert.match(invoke(['--gate','--core']).stderr,/必须运行完整测试/)
  assert.match(invoke(['--core','--scripts']).stderr,/不能同时/)
  assert.match(invoke([], {UNIT_BUSY:'1'}).stderr,/无法获取测试锁/)
  assert.equal(invoke(['--coverage'], {BENCHGAUGE_TEST_PASS:'bound',UNIT_REUSE:'1',UNIT_BUSY:'1'}).status,0)
  assert.match(invoke(['--coverage'], {BENCHGAUGE_TEST_PASS:'bound',UNIT_REUSE:'0',UNIT_BUSY:'1'}).stderr,/无法获取测试锁/)
  assert.match(invoke(['--core','--coverage'], {BENCHGAUGE_TEST_PASS:'bound',UNIT_REUSE:'1',UNIT_BUSY:'1'}).stderr,/无法获取测试锁/)
  assert.equal(invoke(['--coverage'], {COMMIT_REQUIRE_LOCK:'1',UNIT_SHARED:'1',UNIT_BUSY:'1'}).status,0)
  assert.match(invoke(['--coverage'], {COMMIT_REQUIRE_LOCK:'1',UNIT_SHARED:'0',UNIT_BUSY:'1'}).stderr,/无法获取测试锁/)
  assert.match(invoke(['--coverage'], {UNIT_SHARED:'1',UNIT_BUSY:'1'}).stderr,/无法获取测试锁/)
  assert.equal(invoke(['--coverage'], {CALMMIT_TEST_INDEX:'/fixture/commit-index-1',UNIT_EXPECT_INDEX:'1',UNIT_SHARED:'1',UNIT_BUSY:'1'}).status,0)
  assert.match(invoke(['--coverage'], {CALMMIT_TEST_INDEX:'/fixture/commit-index-1',UNIT_EXPECT_INDEX:'1',UNIT_SHARED:'0',UNIT_BUSY:'1'}).stderr,/无法获取测试锁/)
})


test('test command discovery rejects an empty suite instead of passing without tests', async t => {
 const { testCommands } = await import('./test.mjs')
 const root = fs.mkdtempSync(join(tmpdir(), 'benchgauge-empty-tests-'))
 t.after(() => fs.rmSync(root, { recursive: true, force: true }))
 fs.mkdirSync(join(root, 'Scripts'))
 assert.throws(() => testCommands(root, { scriptsOnly: true, node: process.execPath }), /未找到脚本测试/)
})


for (const mode of ['native-clear-failure', 'native-report-failure']) test(`${mode} blocks a passing native coverage receipt`, async t => {
 const root = fixture(t), calls = mockCommands(t, { mode })
 const result = await runTests({ root, logger, coreOnly: true, coverage: true, nativeAvailable: true })
 assert.equal(result.status, 2)
 assert.equal(result.signature, null)
 const commands = calls.filter(call => call[0] !== 'xcrun')
 assert.ok(commands.some(call => call[1].includes('--clear')))
 assert.equal(commands.some(call => call[0] === 'swift'), mode === 'native-report-failure')
})
