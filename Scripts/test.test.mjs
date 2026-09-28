import assert from 'node:assert/strict'
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import test from 'node:test'
import { runTests, testCommands, testInputSignature } from './test.mjs'

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

test('full test entry selects both script and Swift suites; filters select just one', (t) => {
  const root = fixture(t)
  const commands = testCommands(root, { swiftcPath: '/missing/swiftc' })
  assert.equal(commands.length, 2)
  assert.ok(commands[0][1].includes(join(root, 'Scripts', 'example.test.mjs')))
  assert.equal(commands[1][0], 'swift')
  assert.ok(commands[1][1].includes('--disable-xctest'))
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
