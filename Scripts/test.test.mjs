import assert from 'node:assert/strict'
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import test from 'node:test'
import { runTests, testCommands, testInputSignature, testExecutionContext, testEnvironment } from './test.mjs'

function fixture(t) {
  const root = mkdtempSync(join(tmpdir(), 'benchgauge-tests-'))
  for (const name of ['Sources', 'Tests', 'Scripts']) mkdirSync(join(root, name))
  writeFileSync(join(root, 'Sources', 'example.swift'), 'initial')
  writeFileSync(join(root, 'Tests', 'example.swift'), 'assertion')
  writeFileSync(join(root, 'Scripts', 'example.test.mjs'), 'test')
  t.after(() => rmSync(root, { recursive: true, force: true }))
  return root
}
const logger = { log() {}, error() {} }

test('native tests select full Xcode only for an implicit Command Line Tools selection', t => {
  const root = fixture(t)
  const xcodeDeveloperDir = join(root, 'Xcode.app', 'Contents', 'Developer')
  const options = { platform: 'darwin', xcodeDeveloperDir, selectedDeveloperDir: '/Library/Developer/CommandLineTools' }
  const env = { PATH: '/fixture/bin' }
  assert.equal(testEnvironment(env, options), env, 'Missing Xcode must not change the environment')
  mkdirSync(join(xcodeDeveloperDir, 'usr/bin'), { recursive: true })
  writeFileSync(join(xcodeDeveloperDir, 'usr/bin/xcodebuild'), '')
  assert.deepEqual(testEnvironment(env, options), { ...env, DEVELOPER_DIR: xcodeDeveloperDir })
  assert.equal(env.DEVELOPER_DIR, undefined, 'The caller environment remains unchanged')
  for (const key of ['DEVELOPER_DIR', 'TOOLCHAINS', 'SDKROOT', 'SWIFT_EXEC', 'SWIFT_DRIVER_SWIFT_FRONTEND_EXEC']) {
    const explicit = { ...env, [key]: '/custom/toolchain' }
    assert.equal(testEnvironment(explicit, options), explicit, key)
  }
  assert.equal(testEnvironment(env, { ...options, platform: 'linux' }), env)
  assert.equal(testEnvironment(env, { ...options, selectedDeveloperDir: '/Custom/Xcode.app/Contents/Developer' }), env)
  assert.equal(testEnvironment(env, { ...options, selectedDeveloperDir: '' }), env)
})

test('execution context carries only signature settings and explicitly preserves unset values', () => {
  const context = testExecutionContext({ ...process.env, LANG: 'en_GB.UTF-8', TZ: undefined, PRIVATE_TEST_VALUE: 'omit' })
  assert.equal(context.env.LANG, 'en_GB.UTF-8')
  assert.equal(context.env.TZ, null)
  assert.equal('PRIVATE_TEST_VALUE' in context.env, false)
  assert.equal(typeof context.node, 'string')
})

test('full test entry selects both script and Swift suites; filters select just one', (t) => {
  const root = fixture(t)
  const commands = testCommands(root, { swiftcPath: '/missing/swiftc' })
  assert.equal(commands.length, 2)
  assert.ok(commands[0][1].includes(join(root, 'Scripts', 'example.test.mjs')))
  assert.equal(commands[1][0], 'swift')
  assert.ok(commands[1][1].includes('--disable-xctest'))
  assert.ok(commands[1][1].includes('--no-parallel'))
  assert.equal(testCommands(root, { coreOnly: true })[0][0], 'swift')
  assert.equal(testCommands(root, { scriptsOnly: true }).length, 1)
})

test('first failed suite blocks subsequent suites and writes a failing report', async (t) => {
  const root = fixture(t); const calls = []
  const result = await runTests({ root, logger, commands: [['scripts', []], ['swift', []]], run: async (command) => { calls.push(command); return 1 } })
  assert.deepEqual(calls, ['scripts'])
  assert.equal(result.status, 1); assert.equal(result.signature, null)
  assert.equal(JSON.parse(readFileSync(join(root, 'work', 'test-results', 'latest.json'))).status, 1)
})

test('mini-program business tests join the full offline gate and an empty suite is rejected', (t) => {
  const root = fixture(t)
  const directory = join(root, 'apps/weapp/test')
  mkdirSync(directory, { recursive: true })
  assert.throws(() => testCommands(root, { swiftcPath: '/missing/swiftc' }), /小程序测试/)
  writeFileSync(join(directory, 'leaderboard.test.mjs'), 'test')
  writeFileSync(join(directory, 'fixture.json'), '{}')
  const commands = testCommands(root, { swiftcPath: '/missing/swiftc' })
  assert.equal(commands.length, 3)
  assert.ok(commands[1][1].includes(join(directory, 'leaderboard.test.mjs')))
  assert.equal(testCommands(root, { coreOnly: true }).length, 1)
})

test('mini-program sources and build inputs invalidate cached passes but dist does not', (t) => {
  const root = fixture(t)
  const env = { ...process.env, CALMMIT_PATH: '' }
  let before = testInputSignature(root, env)
  for (const path of ['apps/weapp/src/app.js', 'apps/weapp/test/example.test.mjs', 'apps/weapp/scripts/build.mjs',
    'apps/weapp/package.json', 'apps/weapp/vite.config.js', 'apps/weapp/project.config.json',
    'package.json', 'pnpm-workspace.yaml', 'pnpm-lock.yaml']) {
    mkdirSync(join(root, path, '..'), { recursive: true })
    writeFileSync(join(root, path), 'source')
    const next = testInputSignature(root, env)
    assert.notEqual(next, before, path)
    before = next
  }
  mkdirSync(join(root, 'apps/weapp/dist'), { recursive: true })
  writeFileSync(join(root, 'apps/weapp/dist/app.js'), 'generated')
  assert.equal(testInputSignature(root, env), before)
})

test('passing suites yield a receipt which only the same full inputs can reuse', async (t) => {
  const root = fixture(t); let count = 0
  const options = { root, logger, commands: [['check', []]], run: async () => { count++; return 0 } }
  const passed = await runTests(options)
  const env = { ...process.env, BENCHGAUGE_TEST_PASS: passed.signature }
  const reused = await runTests({ ...options, env, gate: true })
  assert.equal(reused.reused, true); assert.equal(count, 1)
  writeFileSync(join(root, 'Tests', 'example.swift'), 'changed assertion')
  const rerun = await runTests({ ...options, env, gate: true })
  assert.equal(rerun.reused, undefined); assert.equal(count, 2)
  assert.notEqual(rerun.signature, passed.signature)
})

test('manual runs and partial/coverage runs cannot reuse a full-pass receipt', async (t) => {
  const root = fixture(t); let count = 0
  const options = { root, logger, commands: [['check', []]], run: async () => { count++; return 0 } }
  const env = { ...process.env, BENCHGAUGE_TEST_PASS: testInputSignature(root) }
  await runTests({ ...options, env })
  await runTests({ ...options, env, gate: true, coreOnly: true })
  await runTests({ ...options, env, gate: true, coverage: true })
  assert.equal(count, 3)
})

test('editing source during a successful run invalidates the result and releases the lock', async (t) => {
  const root = fixture(t)
  const result = await runTests({ root, logger, commands: [['check', []]], run: async () => { writeFileSync(join(root, 'Sources', 'example.swift'), 'new'); return 0 } })
  assert.equal(result.status, 75); assert.equal(result.signature, null)
  const next = await runTests({ root, logger, commands: [['check', []]], run: async () => 0 })
  assert.equal(next.status, 0)
})

test('empty suites are rejected and concurrent runs wait instead of overwriting logs', async (t) => {
  const root = fixture(t)
  await assert.rejects(runTests({ root, logger, commands: [] }), /测试列表为空/)
  let finish; let started
  const running = new Promise((resolve) => { started = resolve })
  const first = runTests({ root, logger, commands: [['check', []]], run: async () => { started(); return new Promise((resolve) => { finish = resolve }) } })
  await running
  const second = await runTests({ root, logger, commands: [['check', []]], run: async () => 0 })
  assert.equal(second.status, 75)
  finish(0); assert.equal((await first).status, 0)
})

test('coverage enables reporting for both languages and toolchain plugins are discovered', (t) => {
  const root = fixture(t)
  const plugins = join(root, 'toolchain', 'lib', 'swift', 'host', 'plugins', 'testing')
  mkdirSync(plugins, { recursive: true })
  const commands = testCommands(root, { coverage: true, swiftcPath: join(root, 'toolchain', 'bin', 'swiftc') })
  assert.ok(commands[0][1].includes('--experimental-test-coverage'))
  assert.ok(commands[1][1].includes('--enable-code-coverage'))
  assert.ok(commands[1][1].includes(plugins))
})

test('Calmmit configuration and live shared source invalidate passing receipts', (t) => {
  const root = fixture(t)
  const library = join(root, 'shared-ci')
  mkdirSync(join(library, 'src'), { recursive: true })
  mkdirSync(join(library, 'bin'))
  const config = { library: './shared-ci', steps: { tests: true } }
  writeFileSync(join(root, 'calmmit.config.json'), JSON.stringify(config))
  writeFileSync(join(library, 'src/identity.mjs'), 'export const version = 1')
  const env = { ...process.env, CALMMIT_PATH: '' }
  const before = testInputSignature(root, env)
  writeFileSync(join(library, 'src/identity.mjs'), 'export const version = 2')
  const updated = testInputSignature(root, env)
  assert.notEqual(updated, before)
  config.steps.tests = false
  writeFileSync(join(root, 'calmmit.config.json'), JSON.stringify(config))
  assert.notEqual(testInputSignature(root, env), updated)
})

test('mobile source and UI test edits in apps/ios invalidate a cached full pass', (t) => {
  const root = fixture(t)
  let before = testInputSignature(root)
  for (const path of ['apps/ios/App/BenchGaugeApp.swift', 'apps/ios/UI/LeaderboardPadView.swift', 'apps/ios/UITests/LeaderboardPadTests.swift']) {
    const file = join(root, path)
    mkdirSync(join(file, '..'), { recursive: true })
    writeFileSync(file, 'initial')
    let after = testInputSignature(root)
    assert.notEqual(after, before, `Adding ${path} must invalidate the pass`)
    before = after
    writeFileSync(file, 'changed')
    after = testInputSignature(root)
    assert.notEqual(after, before, `Editing ${path} must invalidate the pass`)
    before = after
  }
})
