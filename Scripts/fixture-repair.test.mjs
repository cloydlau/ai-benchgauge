import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import { copyFileSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import test from 'node:test'
import { ci } from './calmmit.mjs'
import { runTestGate } from './test-repair.mjs'
import { testInputSignature } from './test.mjs'

const scripts = dirname(fileURLToPath(import.meta.url))
const { repairContextCommand } = await ci.load('repair-context')

test('the real BenchGauge gate repairs a stale language fixture and reruns every original integration assertion', async t => {
  const root = realpathSync(mkdtempSync(join(tmpdir(), 'benchgauge fixture recovery ')))
  t.after(() => rmSync(root, { recursive: true, force: true }))
  mkdirSync(join(root, 'Scripts'))
  mkdirSync(join(root, 'work/test-results'), { recursive: true })
  for (const file of ['calmmit.mjs', 'ci-checks.mjs', 'commit.mjs'])
    copyFileSync(join(scripts, file), join(root, 'Scripts', file))
  const config = JSON.parse(readFileSync(join(scripts, '../calmmit.config.json'), 'utf8'))
  const library = resolve(scripts, '..', process.env.CALMMIT_PATH || config.library)
  writeFileSync(join(root, 'calmmit.config.json'), JSON.stringify({ ...config, library }))
  const original = readFileSync(join(scripts, 'calmmit-integration.test.mjs'), 'utf8')
  // Keep the two actual adapter tests and all their assertions. Workflow file
  // inspections are separate cases and need no part in this isolated checkout.
  const fixture = original.slice(0, original.indexOf('\nfor (const [filename'))
    // This regression adds an outer test runner and executes the adapter twice.
    // Give its nested CLI a bounded budget without changing any assertions.
    .replace('timeout: 15000', 'timeout: 60000')
    .replace(/run\(\['Scripts\/commit\.mjs', '-m', '[^'\n]+'\]\)/,
      "run(['Scripts/commit.mjs', '-m', 'feat: 添加接入测试'])")
  assert.ok(fixture.includes("'-m', 'feat: 添加接入测试'"))
  const path = join(root, 'Scripts', 'integration.test.mjs')
  writeFileSync(path, fixture)
  const env = { ...process.env, CALMMIT_PATH: library, TEST_AUTO_REPAIR: '1' }
  delete env.GIT_INDEX_FILE
  delete env.BENCHGAUGE_TEST_PASS
  delete env.NODE_TEST_CONTEXT
  // The outer runner measures the real adapter files separately. This copy is
  // a standalone CLI regression and must not inherit its parent's test worker
  // or coverage preload (which would measure a second copy of those files).
  delete env.NODE_OPTIONS
  delete env.NODE_V8_COVERAGE
  delete env.BENCHGAUGE_COVERAGE_DIRECTORY
  assert.equal(spawnSync('git', ['init', '-q', root], { env }).status, 0)
  let runs = 0
  const outputs = []
  const result = await runTestGate({ root, env,
    test: async () => {
      runs++
      const run = spawnSync(process.execPath, ['--test', '--test-reporter=spec', path], {
        cwd: root, env, encoding: 'utf8', timeout: 120000, maxBuffer: 8 * 1024 * 1024,
      })
      assert.ifError(run.error)
      const output = run.stdout + run.stderr
      outputs.push(output)
      const logPath = join(root, 'work/test-results', `failure-${runs}.log`)
      writeFileSync(logPath, output)
      return { status: run.status, logPath,
        signature: run.status === 0 ? testInputSignature(root, env) : null }
    },
    repairWithAi: () => assert.fail('the known policy mismatch must recover without an AI call'),
  })
  assert.equal(runs, 2, JSON.stringify({ result, outputs }))
  assert.match(outputs[0], /提交信息语言不符合 commit.language="en"/)
  assert.match(outputs[1], /pass 2/)
  assert.match(outputs[1], /fail 0/)
  assert.equal(result.status, 0)
  assert.equal(result.signature, testInputSignature(root, env))
  assert.equal(result.attemptedAi, false)
  assert.equal(readFileSync(path, 'utf8'), fixture.replace("'feat: 添加接入测试'",
    '"feat: update commit and deployment scripts"'))
  const [record] = repairContextCommand(root, ['history'])
  assert.equal(record.status, 'verified')
  assert.equal(record.ai.changes[0].file, 'Scripts/integration.test.mjs')
  assert.equal(record.verifications.at(-1).signature, result.signature)
})
