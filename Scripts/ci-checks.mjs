#!/usr/bin/env node
import { spawnSync } from 'node:child_process'
import { readdirSync } from 'node:fs'
import { join } from 'node:path'
import { runTests, testRoot } from './test.mjs'

// The same checks run manually and before packaging; no app or accounts are opened.
for (const name of readdirSync(join(testRoot, 'Scripts')).filter((name) => name.endsWith('.mjs')).sort()) {
  const result = spawnSync(process.execPath, ['--check', join(testRoot, 'Scripts', name)], { stdio: 'inherit' })
  if (result.status !== 0 || result.error) process.exit(result.status || 1)
}
const tested = await runTests()
if (tested.status !== 0) process.exit(tested.status)
const built = spawnSync(join(testRoot, 'Scripts', 'make-app.sh'), [], { cwd: testRoot, stdio: 'inherit',
  env: { ...process.env, BENCHGAUGE_TEST_PASS: tested.signature } })
process.exitCode = built.status ?? 1
