import { spawnSync } from 'node:child_process'
import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import { ci } from './calmmit.mjs'
import { testInputSignature } from './test.mjs'

const { loadConfig } = await ci.load('config')
const config = loadConfig(ci.root)
const env = { ...process.env }
if (!config.steps.tests) env.BENCHGAUGE_SKIP_TESTS = '1'
else {
  delete env.BENCHGAUGE_SKIP_TESTS
  try {
    const passed = JSON.parse(readFileSync(join(ci.root, 'work/test-results/latest.json'), 'utf8'))
    if (passed.status === 0 && passed.signature === testInputSignature(ci.root)) env.BENCHGAUGE_TEST_PASS = passed.signature
  } catch { /* Packaging independently verifies when there is no current receipt. */ }
}
const result = spawnSync(join(ci.root, 'Scripts/make-app.sh'), [], { cwd: ci.root, env, stdio: 'inherit' })
if (result.error) throw result.error
process.exitCode = result.status ?? 1
