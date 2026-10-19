import test from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import cp from 'node:child_process'
import { syncBuiltinESMExports } from 'node:module'
import { EventEmitter } from 'node:events'
import { dirname, join, resolve } from 'node:path'
import { tmpdir } from 'node:os'
import { nativeTestAvailability, runTests, testCommands, testInputSignature, testEnvironment } from './test.mjs'
import { runTestGate } from './test-repair.mjs'
import { cacheLock } from './build-cache.mjs'

function fixture(t) {
  const root = fs.realpathSync(fs.mkdtempSync(join(tmpdir(), 'benchgauge-runner-unit-')))
  for (const path of ['Sources', 'Tests', 'Scripts']) fs.mkdirSync(join(root, path))
  fs.writeFileSync(join(root, 'Scripts/fixture.test.mjs'), '')
  t.after(() => fs.rmSync(root, { recursive: true, force: true }))
  return root
}
const logger = { log() {}, error() {} }
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
  fs.copyFileSync(new URL('./build-cache.mjs',import.meta.url),join(root,'Scripts/build-cache.mjs'))
  fs.copyFileSync(new URL('./prepare-swift-workspace.mjs',import.meta.url),join(root,'Scripts/prepare-swift-workspace.mjs'))
  fs.writeFileSync(join(root,'Scripts/commit-lock.mjs'), `export const pidState=()=> 'gone'; export const acquireCommitLock=()=>process.env.UNIT_BUSY==='1'?{acquired:false,reason:'error'}:{acquired:true,release(){}}`)
  fs.writeFileSync(join(root,'Scripts/node-executable.mjs'), `export const nodeExecutable=()=>process.execPath`)
  fs.writeFileSync(join(root,'Scripts/test-repair.mjs'), `export const runTestGate=async()=>({status:0})`)
  fs.writeFileSync(join(root,'hook.cjs'), `const cp=require('node:child_process'),{EventEmitter}=require('node:events');cp.spawnSync=()=>({status:0});cp.spawn=()=>{const child=new EventEmitter();child.stdout=new EventEmitter();child.stderr=new EventEmitter();queueMicrotask(()=>child.emit('close',0));return child};require('node:module').syncBuiltinESMExports();`)
  const invoke=(args=[],env={})=>cp.spawnSync(process.execPath,['--require',join(root,'hook.cjs'),join(root,'Scripts/test.mjs'),...args],{encoding:'utf8',env:{...process.env,...env}})
  for(const args of [[],['--core'],['--scripts'],['--core','--coverage'],['--gate']]) assert.equal(invoke(args).status,0)
  assert.match(invoke(['--unknown']).stderr,/用法/)
  assert.match(invoke(['--gate','--core']).stderr,/必须运行完整测试/)
  assert.match(invoke(['--core','--scripts']).stderr,/不能同时/)
  assert.match(invoke([], {UNIT_BUSY:'1'}).stderr,/无法获取测试锁/)
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
