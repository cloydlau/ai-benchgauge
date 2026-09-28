import assert from 'node:assert/strict'
import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import test from 'node:test'
import { repairTests, runTestGate } from './test-repair.mjs'

const passReport = { completed: true, verdict: 'pass', summary: 'fixed', fixes: [], decisions: [], issues: [] }
const protectedSignature = () => 'same'

test('passing tests never call an AI; input-change/lock status is retried without AI', async () => {
  for (const status of [0, 75]) {
    let calls = 0
    const result = await repairTests({ runTests: async () => ({ status }), repairWithAi: () => { calls++; return passReport }, protectedSignature })
    assert.equal(result.status, status); assert.equal(calls, 0)
  }
})

test('AI pass cannot override failing real tests and is attempted only once', async () => {
  let tests = 0; let repairs = 0
  const result = await repairTests({ runTests: async () => { tests++; return { status: 1 } }, repairWithAi: async () => { repairs++; return passReport }, protectedSignature })
  assert.equal(result.status, 1); assert.equal(tests, 2); assert.equal(repairs, 1)
})

test('a completed repair must pass a second full run', async () => {
  let tests = 0
  const result = await repairTests({ runTests: async () => ({ status: ++tests === 1 ? 1 : 0, signature: 'verified' }), repairWithAi: async () => passReport, protectedSignature })
  assert.equal(result.status, 0); assert.equal(result.signature, 'verified'); assert.equal(tests, 2)
})

test('unresolved decisions, issues and failing verdict block even green tests', async () => {
  for (const report of [{ ...passReport, decisions: ['business decision'] }, { ...passReport, issues: ['remaining bug'] }, { ...passReport, verdict: 'fail' }]) {
    let tests = 0
    const result = await repairTests({ runTests: async () => ({ status: ++tests === 1 ? 1 : 0 }), repairWithAi: async () => report, protectedSignature })
    assert.equal(result.status, 1)
  }
})

test('changed tests/config stop verification and incomplete/crashed repairs stop without looping', async () => {
  let key = 'before'; let tests = 0
  const result = await repairTests({ runTests: async () => { tests++; return { status: 1 } }, repairWithAi: async () => { key = 'changed'; return passReport }, protectedSignature: () => key })
  assert.equal(result.status, 1); assert.match(result.error, /改动了测试/); assert.equal(tests, 1)
  const crashed = await repairTests({ runTests: async () => ({ status: 1 }), repairWithAi: async () => { throw new Error('timeout') }, protectedSignature })
  assert.equal(crashed.status, 1); assert.match(crashed.error, /timeout/)
})

test('disabled/sandbox repair never invokes Codex and failed attempts persist across restarts', async (t) => {
  const root = mkdtempSync(join(tmpdir(), 'benchgauge-test-repair-'))
  mkdirSync(join(root, 'Sources')); writeFileSync(join(root, 'Sources', 'example.swift'), 'initial')
  t.after(() => rmSync(root, { recursive: true, force: true }))
  let calls = 0
  const options = { root, test: async () => ({ status: 1 }), repairWithAi: async () => { calls++; return passReport } }
  await runTestGate({ ...options, env: { TEST_AUTO_REPAIR: '0' } })
  await runTestGate({ ...options, env: { CODEX_SANDBOX_NETWORK_DISABLED: '1' } })
  assert.equal(calls, 0)
  await runTestGate({ ...options, env: {} }); assert.equal(calls, 1)
  await runTestGate({ ...options, env: {} }); assert.equal(calls, 1)
  writeFileSync(join(root, 'Sources', 'example.swift'), 'fixed inputs')
  await runTestGate({ ...options, env: {} }); assert.equal(calls, 2)
})
