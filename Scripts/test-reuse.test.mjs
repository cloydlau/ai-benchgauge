import assert from 'node:assert/strict'
import childProcess from 'node:child_process'
import { copyFileSync, mkdirSync, mkdtempSync, rmSync, symlinkSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { syncBuiltinESMExports } from 'node:module'
import test from 'node:test'
import { coverageSummaryDigest, testIndexMatchesWorkspace, testReuseSignature } from './test-reuse.mjs'

const { execFileSync } = childProcess

test('cross-process proof changes with source, configuration, environment, dependencies and toolchain', t => {
  const root = mkdtempSync(join(tmpdir(), 'benchgauge-proof-'))
  t.after(() => rmSync(root, { recursive: true, force: true }))
  execFileSync('git', ['init', '-q', root])
  for (const path of ['node_modules/pkg', 'library/src', 'library/bin', 'library/node_modules']) mkdirSync(join(root, path), { recursive: true })
  writeFileSync(join(root, 'source'), 'one')
  writeFileSync(join(root, 'node_modules/pkg/index.js'), 'dependency')
  writeFileSync(join(root, 'library/src/shared.js'), 'shared')
  const options = { native: { available: true }, library: join(root, 'library'), versions: ['fixture'] }
  const env = { ...process.env, TEST_PROOF_FIXTURE: 'one' }
  const signature = () => testReuseSignature(root, env, options)
  let before = signature()
  assert.match(before, /^[a-f0-9]{64}$/)
  for (const [path, value] of [['source', 'two'], ['node_modules/pkg/index.js', 'changed'],
    ['library/src/shared.js', 'changed'], ['.benchgauge-cloud.local.json', 'config']]) {
    writeFileSync(join(root, path), value)
    const after = signature()
    assert.notEqual(after, before, path)
    before = after
  }
  env.TEST_PROOF_FIXTURE = 'two'
  assert.notEqual(signature(), before)
  before = signature()
  env.BENCHGAUGE_TEST_PASS = 'parent-only'
  assert.equal(signature(), before)
  env.GIT_INDEX_FILE = join(root, 'wrong-index')
  assert.equal(signature(), before)
  assert.notEqual(testReuseSignature(root, env, { ...options, native: { available: false } }), before)
  assert.notEqual(testReuseSignature(root, env, { ...options, versions: ['different'] }), before)
  symlinkSync(tmpdir(), join(root, 'node_modules/pkg/external'))
  assert.equal(signature(), null)
})

test('missing repository or unavailable library fails closed', t => {
  const root = mkdtempSync(join(tmpdir(), 'benchgauge-no-proof-'))
  t.after(() => rmSync(root, { recursive: true, force: true }))
  assert.equal(testReuseSignature(root, process.env, { versions: [] }), null)
  execFileSync('git', ['init', '-q', root])
  assert.equal(testReuseSignature(root, process.env, { library: join(root, 'missing'), versions: [] }), null)
})

test('proof records the actual runtime and installed tools when no fixture versions are supplied', t => {
  const root = mkdtempSync(join(tmpdir(), 'benchgauge-tool-proof-'))
  t.after(() => rmSync(root, { recursive: true, force: true }))
  execFileSync('git', ['init', '-q', root])
  writeFileSync(join(root, 'source'), 'source')
  const proof = testReuseSignature(root, process.env, { native: { available: false }, node: process.execPath })
  assert.match(proof, /^[a-f0-9]{64}$/)
})

test('commit reuse requires the real private index to match the working tree', t => {
  const root = mkdtempSync(join(tmpdir(), 'benchgauge-index-proof-'))
  t.after(() => rmSync(root, { recursive: true, force: true }))
  execFileSync('git', ['init', '-q', root])
  writeFileSync(join(root, 'source'), 'one')
  execFileSync('git', ['-C', root, 'add', 'source'])
  const index = join(root, '.git/commit-index-123')
  copyFileSync(join(root, '.git/index'), index)
  assert.equal(testIndexMatchesWorkspace(root, index), true)
  assert.equal(testIndexMatchesWorkspace(root, index, { ...process.env, GIT_INDEX_FILE: join(root, 'wrong-index') }), true)
  assert.equal(testIndexMatchesWorkspace(root, null), false)
  assert.equal(testIndexMatchesWorkspace(root, join(root, '.git/commit-index-999')), false)
  assert.equal(testIndexMatchesWorkspace(root, join(root, '.git/index')), false)
  writeFileSync(join(root, 'source'), 'two')
  assert.equal(testIndexMatchesWorkspace(root, index), false)
  writeFileSync(join(root, 'source'), 'one')
  writeFileSync(join(root, 'new'), 'new')
  assert.equal(testIndexMatchesWorkspace(root, index), false)
  rmSync(join(root, 'new'))
  assert.equal(testIndexMatchesWorkspace(root, index), true)
})

test('deleted inputs, duplicate links and unusual files cannot be mistaken for unchanged data', t => {
  const root = mkdtempSync(join(tmpdir(), 'benchgauge-input-proof-'))
  t.after(() => rmSync(root, { recursive: true, force: true }))
  execFileSync('git', ['init', '-q', root])
  mkdirSync(join(root, 'node_modules/pkg'), { recursive: true })
  writeFileSync(join(root, 'node_modules/pkg/index.js'), 'module')
  symlinkSync('pkg', join(root, 'node_modules/z-link'))
  writeFileSync(join(root, 'source'), 'source')
  execFileSync('git', ['-C', root, 'add', 'source'])
  const options = { library: root, versions: ['fixture'] }
  const before = testReuseSignature(root, process.env, options)
  assert.match(before, /^[a-f0-9]{64}$/)
  rmSync(join(root, 'source'))
  const after = testReuseSignature(root, process.env, options)
  assert.match(after, /^[a-f0-9]{64}$/)
  assert.notEqual(after, before)
  execFileSync('mkfifo', [join(root, 'node_modules/pkg/pipe')])
  assert.equal(testReuseSignature(root, process.env, options), null)
})

test('Git, toolchain and tool discovery failures never authorize cross-process reuse', t => {
  const root = mkdtempSync(join(tmpdir(), 'benchgauge-proof-errors-'))
  t.after(() => rmSync(root, { recursive: true, force: true }))
  execFileSync('git', ['init', '-q', root])
  writeFileSync(join(root, 'source'), 'source')
  const original = childProcess.spawnSync
  let mode = ''
  t.mock.method(childProcess, 'spawnSync', (command, args, options) => {
    if (mode === 'git-directory' && args.includes('--absolute-git-dir')) return { status: 1 }
    if (mode === 'git-config' && args.includes('--show-origin')) return { status: 1 }
    if (mode === 'missing-tool' && command === 'swift') return { error: { code: 'ENOENT' }, status: null }
    if (mode === 'missing-tool' && command === '/usr/bin/which' && args[0] === 'swift') return { status: 1, stdout: '' }
    if (mode === 'which-error' && command === '/usr/bin/which') return { error: { code: 'ENOENT' }, status: null }
    return original(command, args, options)
  })
  syncBuiltinESMExports()
  t.after(() => { t.mock.restoreAll(); syncBuiltinESMExports() })
  mode = 'git-directory'
  assert.equal(testIndexMatchesWorkspace(root, join(root, 'anything')), false)
  mode = 'git-config'
  assert.equal(testReuseSignature(root, process.env, { versions: ['fixture'] }), null)
  mode = 'missing-tool'
  assert.match(testReuseSignature(root, process.env), /^[a-f0-9]{64}$/)
  mode = 'which-error'
  assert.equal(testReuseSignature(root, process.env), null)
})

test('coverage evidence must be a local regular summary and its digest changes with its contents', t => {
  const root = mkdtempSync(join(tmpdir(), 'benchgauge-summary-proof-'))
  t.after(() => rmSync(root, { recursive: true, force: true }))
  const directory = join(root, 'work/test-results/coverage-123-456')
  mkdirSync(directory, { recursive: true })
  assert.equal(coverageSummaryDigest(root, undefined), null)
  assert.equal(coverageSummaryDigest(root, tmpdir()), null)
  assert.equal(coverageSummaryDigest(root, directory), null)
  const summary = join(directory, 'summary.json')
  writeFileSync(summary, '{}')
  const before = coverageSummaryDigest(root, directory)
  assert.match(before, /^[a-f0-9]{64}$/)
  writeFileSync(summary, '{"changed":true}')
  assert.notEqual(coverageSummaryDigest(root, directory), before)
  rmSync(summary)
  symlinkSync('/etc/hosts', summary)
  assert.equal(coverageSummaryDigest(root, directory), null)
})
