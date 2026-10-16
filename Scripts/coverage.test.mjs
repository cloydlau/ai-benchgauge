import { test } from 'node:test'
import assert from 'node:assert/strict'
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, readdirSync, realpathSync, rmSync } from 'node:fs'
import { spawnSync } from 'node:child_process'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { pathToFileURL } from 'node:url'
import { createHash } from 'node:crypto'
import { normalizeProfiles, validateCoverage } from './coverage-report.cjs'

function instrumentationFixture(t) {
  const root = realpathSync(mkdtempSync(join(tmpdir(), 'coverage-write-')))
  t.after(() => rmSync(root, { recursive: true, force: true }))
  const directory = join(root, 'coverage')
  mkdirSync(join(root, 'Scripts')); mkdirSync(directory)
  const bytes = 'export const value = 1\n'
  writeFileSync(join(root, 'Scripts/example.mjs'), bytes)
  const copy = join(root, 'copy.mjs'); writeFileSync(copy, bytes)
  return { root, directory, copy, loader: new URL('./coverage-preload.cjs', import.meta.url).pathname,
    env: { ...process.env, NODE_OPTIONS: '', NODE_V8_COVERAGE: '', BENCHGAUGE_COVERAGE_ROOT: root, BENCHGAUGE_COVERAGE_DIRECTORY: directory } }
}

test('termination during a manifest update preserves the last complete source evidence', t => {
  const f = instrumentationFixture(t)
  const fault = join(f.root, 'terminate.cjs')
  writeFileSync(fault, `const fs = require('node:fs'); const path = require('node:path');
    const write = fs.writeFileSync; let count = 0;
    fs.writeFileSync = function(file, ...args) {
      if (path.basename(String(file)).startsWith('.sources-') && ++count === 2) {
        write.call(this, file, ''); process.exit(77);
      }
      return write.call(this, file, ...args);
    };`)
  const result = spawnSync(process.execPath, ['--require', fault, '--require', f.loader, '--input-type=module', '--eval',
    `await import(${JSON.stringify(pathToFileURL(f.copy).href)})`], { env: f.env, encoding: 'utf8' })
  assert.equal(result.status, 77, result.stderr)
  const manifests = readdirSync(f.directory).filter(name => name.startsWith('sources-'))
  assert.equal(manifests.length, 1)
  const manifest = JSON.parse(readFileSync(join(f.directory, manifests[0]), 'utf8'))
  assert.equal(Object.keys(manifest.originals).length, 1)
  assert.deepEqual(manifest.aliases, [])
  // Incomplete temporary data must never be consumed as source evidence.
  writeFileSync(join(f.directory, 'coverage-1-1791800000000-0.json'), JSON.stringify({ result: [] }))
  assert.doesNotThrow(() => normalizeProfiles(f.directory, f.root))
})

test('workers sharing a process publish separate complete source manifests', t => {
  const f = instrumentationFixture(t)
  const worker = `require(${JSON.stringify(f.loader)}); require(${JSON.stringify(f.copy)});`
  const code = `const {Worker} = require('node:worker_threads');
    Promise.all([1,2].map(() => new Promise((resolve, reject) => {
      const worker = new Worker(${JSON.stringify(worker)}, {eval: true, execArgv: []});
      worker.once('error', reject); worker.once('exit', code => code ? reject(Error('worker '+code)) : resolve());
    }))).catch(error => { console.error(error); process.exitCode = 1; });`
  const result = spawnSync(process.execPath, ['--require', f.loader, '--eval', code], { env: f.env, encoding: 'utf8' })
  assert.equal(result.status, 0, result.stderr)
  const manifests = readdirSync(f.directory).filter(name => name.startsWith('sources-'))
  assert.equal(manifests.length, 3)
  assert.equal(manifests.map(name => JSON.parse(readFileSync(join(f.directory, name), 'utf8')))
    .filter(manifest => manifest.aliases.some(alias => alias.target === pathToFileURL(f.copy).href)).length, 2)
})

test('merges only byte-verified executed copies and rejects stale source reports', t => {
  const root = mkdtempSync(join(tmpdir(), 'coverage-contract-'))
  t.after(() => rmSync(root, { recursive: true, force: true }))
  const directory = join(root, 'coverage'), scripts = join(root, 'Scripts')
  mkdirSync(directory); mkdirSync(scripts)
  const original = join(scripts, 'example.mjs')
  const bytes = 'export const value = 1\n'; writeFileSync(original, bytes)
  const source = pathToFileURL(original).href, target = 'file:///deleted-fixture/example.mjs'
  const sha256 = createHash('sha256').update(bytes).digest('hex')
  const manifest = { originals: { [source]: sha256 }, aliases: [{ source, target, sha256 }] }
  writeFileSync(join(directory, 'sources-1.json'), JSON.stringify(manifest))
  writeFileSync(join(directory, 'coverage-1-1791800000000-0.json'), JSON.stringify({ result: [{ url: target, functions: [] }, { url: 'file:///unrelated/stub.mjs', functions: [] }] }))
  const normalized = normalizeProfiles(directory, root)
  const report = JSON.parse(readFileSync(join(normalized, 'coverage-1-1791800000000-0.json')))
  assert.deepEqual(report.result, [{ url: source, functions: [] }])
  manifest.aliases[0].sha256 = 'unverified'
  writeFileSync(join(directory, 'sources-1.json'), JSON.stringify(manifest))
  assert.throws(() => normalizeProfiles(directory, root), /Unverified/)
  writeFileSync(original, 'changed')
  assert.throws(() => normalizeProfiles(directory, root), /Source changed/)
})


test('100% means exact counts for every measured metric in every file', () => {
  const complete = { path: 'Scripts/example.mjs', coveredLineCount: 2, totalLineCount: 2, coveredBranchCount: 1, totalBranchCount: 1, coveredFunctionCount: 1, totalFunctionCount: 1 }
  assert.doesNotThrow(() => validateCoverage({ files: [complete] }))
  assert.throws(() => validateCoverage({ files: [] }), /empty/)
  for (const metric of ['Line', 'Branch', 'Function']) {
    assert.throws(() => validateCoverage({ files: [complete, { ...complete, [`covered${metric}Count`]: 0 }] }), /must be 100%/)
    assert.throws(() => validateCoverage({ files: [{ ...complete, [`covered${metric}Count`]: 9999, [`total${metric}Count`]: 10000, [`${metric.toLowerCase()}Percent`]: 100 }] }), /must be 100%/)
    for (const value of [null, -1, 1.5, 100]) assert.throws(() => validateCoverage({ files: [{ ...complete, [`covered${metric}Count`]: value }] }), /Invalid/)
  }
})


test('Swift gate rejects missing files and every partial native metric without rounding', async () => {
  const { validateSwiftCoverage } = await import('./swift-coverage.cjs')
  const source = '/fixture/Sources/LeaderboardCore/Test.swift'
  const full = { filename: source, summary: Object.fromEntries(['lines', 'functions', 'regions'].map(metric => [metric, { count: 10000, covered: 10000, percent: 100 }])) }
  const report = file => ({ type: 'llvm.coverage.json.export', data: [{ files: [file] }] })
  assert.equal(validateSwiftCoverage(report(full), [source]).files, 1)
  assert.throws(() => validateSwiftCoverage({}, [source]), /Invalid/)
  assert.throws(() => validateSwiftCoverage(report(full), []), /Empty/)
  assert.throws(() => validateSwiftCoverage(report(full), [source, '/missing.swift']), /Missing/)
  assert.throws(() => validateSwiftCoverage({ type: 'llvm.coverage.json.export', data: [{ files: [full, full] }] }, [source]), /duplicate/)
  for (const metric of ['lines', 'functions', 'regions']) {
    const summary = { ...full.summary, [metric]: { count: 10000, covered: 9999, percent: 100 } }
    assert.throws(() => validateSwiftCoverage(report({ ...full, summary }), [source]), /must be 100%/)
    assert.throws(() => validateSwiftCoverage(report({ ...full, summary: { ...summary, [metric]: { count: 1, covered: -1 } } }), [source]), /Invalid/)
  }
})

test('Swift report discovery clears old artifacts and never silently shrinks executable scope', async t => {
  const { reportPaths, sourcePaths } = await import('./swift-coverage.cjs')
  const root = mkdtempSync(join(tmpdir(), 'swift-coverage-contract-'))
  t.after(() => rmSync(root, { recursive: true, force: true }))
  for (const library of ['LeaderboardCore', 'LeaderboardKit']) mkdirSync(join(root, 'Sources', library), { recursive: true })
  writeFileSync(join(root, 'Sources/LeaderboardCore/Exports.swift'), '// Compatibility export\n@_exported import LeaderboardKit\n')
  writeFileSync(join(root, 'Sources/LeaderboardCore/Core.swift'), 'public func core() {}')
  writeFileSync(join(root, 'Sources/LeaderboardKit/Kit.swift'), 'public func kit() {}')
  assert.equal(sourcePaths(root).length, 2)
  writeFileSync(join(root, 'Sources/LeaderboardCore/Exports.swift'), '@_exported import LeaderboardKit\npublic func newCode() {}')
  assert.equal(sourcePaths(root).length, 3)
  assert.deepEqual(reportPaths(root), [])
  for (const directory of ['out/Products/Debug/codecov', 'aarch64-unknown-linux-gnu/debug/codecov']) {
    const folder = join(root, 'work/unit-test-build', directory); mkdirSync(folder, { recursive: true }); writeFileSync(join(folder, 'AI-BenchGauge.json'), '{}')
  }
  assert.equal(reportPaths(root).length, 2)
  const { spawnSync } = await import('node:child_process')
  const script = new URL('./swift-coverage.cjs', import.meta.url).pathname
  assert.equal(spawnSync(process.execPath, [script, root]).status, 1)
  assert.equal(spawnSync(process.execPath, [script, root, '--clear']).status, 0)
  assert.deepEqual(reportPaths(root), [])
  assert.equal(spawnSync(process.execPath, [script, root]).status, 1)
})
