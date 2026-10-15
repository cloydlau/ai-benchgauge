import assert from 'node:assert/strict'
import test from 'node:test'
import cp from 'node:child_process'
import { syncBuiltinESMExports } from 'node:module'
import { existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { runTestGate } from './test-repair.mjs'
import { acquireCommitLock } from './commit-lock.mjs'

function fixture(t) {
  const root = mkdtempSync(join(tmpdir(), 'benchgauge-repair-boundary-'))
  mkdirSync(join(root, 'work/test-results'), { recursive: true })
  t.after(() => rmSync(root, { recursive: true, force: true }))
  const logPath = join(root, 'work/test-results/failure.log')
  writeFileSync(logPath, 'deterministic assertion failure')
  return { root, logPath }
}
const passed = { verdict: 'pass', summary: 'fixed', fixes: ['source corrected'], decisions: [], issues: [] }

test('repair gate handles environment failures, busy lock and unattempted repair without recording a retry', async t => {
  const { root, logPath } = fixture(t)
  let repairs = 0
  const options = { root, env: {}, test: async () => ({ status: 1, logPath }), repairWithAi: async () => { repairs++; return { completed: false, attempted: false, summary: 'not available' } } }
  writeFileSync(logPath, 'SDK is not supported')
  assert.equal((await runTestGate(options)).status, 1)
  assert.equal(repairs, 0)
  writeFileSync(logPath, 'deterministic assertion failure')
  const lock = acquireCommitLock({ lockPath: join(root, 'work/test-results/repair.lock') })
  assert.ok(lock.acquired)
  try { assert.equal((await runTestGate(options)).status, 1); assert.equal(repairs, 0) }
  finally { lock.release() }
  for (let i = 0; i < 2; i++) {
    assert.equal((await runTestGate(options)).status, 1)
    assert.equal(existsSync(join(root, 'work/test-results/repair-attempt.json')), false)
  }
  assert.equal(repairs, 2)
})

test('Codex repair command validates deadlines and reports, redacts inherited state, then requires real retesting', async t => {
  let mode = 'pass', invocations = 0
  t.mock.method(cp, 'spawnSync', (_command, args, options) => {
    if (_command === 'git') {
      assert.equal(args[0], 'rev-parse')
      return { status: 0, stdout: args.includes('--absolute-git-dir') ? join(options.cwd, '.git') + '\n' : 'fixture-head\n' }
    }
    if (args[0] === '--version') return { status: mode === 'missing' ? 1 : 0 }
    assert.equal(args[0], 'exec')
    invocations++
    assert.equal(options.env.GIT_INDEX_FILE, undefined)
    assert.equal(options.env.BENCHGAUGE_TEST_PASS, undefined)
    assert.ok(options.input.includes('外围流程会重新运行完整测试'))
    assert.ok(options.input.includes('不要在修复子进程运行测试、lint 或构建'))
    assert.ok(options.input.includes('本次用户需求依据：'))
    if (mode === 'pass') assert.ok(options.input.includes('fixture user requirement'))
    const output = args[args.indexOf('-o') + 1]
    writeFileSync(output, mode === 'bad-json' ? 'broken' : JSON.stringify(mode === 'bad-report' ? { ...passed, fixes: [1] } : passed))
    if (mode === 'error') return { error: Error('launch failed') }
    if (mode === 'status') return { status: 9 }
    return { status: 0, stdout: 'fixture output', stderr: 'fixture diagnostic' }
  })
  syncBuiltinESMExports()
  t.after(() => { t.mock.restoreAll(); syncBuiltinESMExports() })
  for (mode of ['pass', 'missing', 'error', 'status', 'bad-json', 'bad-report', 'invalid-timeout', 'negative-timeout']) {
    const { root, logPath } = fixture(t)
    if (mode === 'pass') {
      mkdirSync(join(root, '.git/calmmit'), { recursive: true })
      writeFileSync(join(root, '.git/calmmit/repair-context.json'), JSON.stringify({
        version: 1, root: realpathSync(root), baseCommit: 'fixture-head', request: 'fixture user requirement',
        paths: ['Sources/Fixture.swift'], testUpdates: [],
      }))
    }
    let tests = 0
    const env = { TEST_REPAIR_CODEX: 'fixture-codex', GIT_INDEX_FILE: '/fixture/index', BENCHGAUGE_TEST_PASS: 'must-not-inherit',
      ...(mode === 'invalid-timeout' ? { TEST_REPAIR_TIMEOUT_MS: 'invalid' } : mode === 'negative-timeout' ? { TEST_REPAIR_TIMEOUT_MS: '-1' } : {}) }
    const result = await runTestGate({ root, env, test: async () => ({ status: ++tests === 1 ? 1 : 0, logPath }) })
    assert.equal(result.status, mode === 'pass' ? 0 : 1, mode)
    assert.equal(tests, mode === 'pass' ? 2 : 1, mode)
    if (['missing', 'invalid-timeout', 'negative-timeout'].includes(mode)) assert.equal(existsSync(join(root, 'work/test-results/repair-attempt.json')), false)
    if (mode === 'pass') {
      const report = JSON.parse(readFileSync(join(root, 'work/test-results/repair-report.json'), 'utf8'))
      assert.deepEqual(report, passed)
      assert.equal(readFileSync(join(root, 'work/test-results/repair.log'), 'utf8'), 'fixture outputfixture diagnostic')
    }
  }
  assert.equal(invocations, 5)
})
