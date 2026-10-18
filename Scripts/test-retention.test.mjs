import assert from 'node:assert/strict'
import { copyFileSync, existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, symlinkSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import test from 'node:test'
import { acquireCommitLock } from './commit-lock.mjs'
import { pruneTestResults, runTests } from './test.mjs'

function fixture(t) {
  const root = mkdtempSync(join(tmpdir(), 'benchgauge-retention-'))
  for (const name of ['Scripts', 'Sources', 'Tests', 'work/test-results']) mkdirSync(join(root, name), { recursive: true })
  t.after(() => rmSync(root, { recursive: true, force: true }))
  const directory = join(root, 'work/test-results')
  const coverage = (time, pid, summary = true) => {
    const path = join(directory, `coverage-${time}-${pid}`)
    mkdirSync(join(path, 'normalized'), { recursive: true })
    writeFileSync(join(path, 'coverage-10-100-0.json'), 'raw')
    writeFileSync(join(path, 'sources-10-0.json'), 'source evidence')
    writeFileSync(join(path, '.sources-10-0.tmp'), 'incomplete evidence')
    writeFileSync(join(path, 'normalized/coverage-10-100-0.json'), 'merged')
    if (summary) writeFileSync(join(path, 'summary.json'), '{"files":[]}\n')
    return path
  }
  return { root, directory, coverage }
}
const logger = { log() {}, error() {} }
const gone = () => 'gone'

test('retention keeps the newest available summary and failure, removing raw and interrupted data', t => {
  const f = fixture(t)
  const old = f.coverage(9, 1), latest = f.coverage(10, 2), interrupted = f.coverage(11, 3, false)
  for (const name of ['failure-9-1.log', 'failure-10-2.log', 'latest.json', 'latest.log', 'test.lock', 'repair.log', 'notes.txt']) {
    writeFileSync(join(f.directory, name), name)
  }
  const summary = readFileSync(join(latest, 'summary.json'), 'utf8')
  pruneTestResults(f.directory, { state: gone })
  assert.equal(existsSync(old), false); assert.equal(existsSync(interrupted), false)
  assert.deepEqual(readdirSync(latest), ['summary.json'])
  assert.equal(readFileSync(join(latest, 'summary.json'), 'utf8'), summary)
  assert.equal(existsSync(join(f.directory, 'failure-9-1.log')), false)
  for (const name of ['failure-10-2.log', 'latest.json', 'latest.log', 'test.lock', 'repair.log', 'notes.txt']) {
    assert.equal(readFileSync(join(f.directory, name), 'utf8'), name)
  }
  // Repeated cleanup is safe even when the newest run never produced a report.
  pruneTestResults(f.directory, { state: gone })
  assert.deepEqual(readdirSync(latest), ['summary.json'])
})

test('live and unverifiable owners are untouched; only the completed current run bypasses its owner', t => {
  const f = fixture(t)
  const old = f.coverage(1, 1), completed = f.coverage(2, process.pid)
  const live = f.coverage(3, 3), unknown = f.coverage(4, 4)
  const state = pid => pid === 1 ? 'gone' : pid === 4 ? 'unknown' : 'alive'
  pruneTestResults(f.directory, { completedCoverageDirectory: completed, state })
  assert.equal(existsSync(old), false)
  assert.deepEqual(readdirSync(completed), ['summary.json'])
  assert.equal(readdirSync(live).length, 5); assert.equal(readdirSync(unknown).length, 5)
})

test('cleanup ignores unrelated names and symlink targets, including nested links', t => {
  const f = fixture(t), outside = join(f.root, 'keep')
  mkdirSync(outside); writeFileSync(join(outside, 'private.txt'), 'keep')
  for (const name of ['coverage-1-1', 'failure-1-1.log']) symlinkSync(outside, join(f.directory, name), 'junction')
  for (const name of ['coverage-2-2.log', 'failure-2-2', 'coverage-invalid', 'coverage-3-0']) mkdirSync(join(f.directory, name))
  const old = f.coverage(4, 4), latest = f.coverage(5, 5)
  symlinkSync(outside, join(old, 'nested'), 'junction')
  symlinkSync(outside, join(latest, 'nested'), 'junction')
  const bad = f.coverage(6, 6, false)
  symlinkSync(join(outside, 'private.txt'), join(bad, 'summary.json'))
  pruneTestResults(f.directory, { state: gone })
  assert.equal(existsSync(bad), false, 'A linked summary is not a report to retain')
  assert.equal(readFileSync(join(outside, 'private.txt'), 'utf8'), 'keep')
  assert.deepEqual(readdirSync(latest), ['summary.json'])
  assert.equal(lstatSync(join(f.directory, 'coverage-1-1')).isSymbolicLink(), true)
  for (const name of ['coverage-2-2.log', 'failure-2-2', 'coverage-invalid', 'coverage-3-0']) assert.equal(existsSync(join(f.directory, name)), true)
  const link = join(f.root, 'linked-results'); symlinkSync(f.directory, link, 'junction')
  assert.throws(() => pruneTestResults(link), /非真实/)
})

test('equal timestamps are resolved consistently and cleanup handles a directory with no reports', t => {
  const f = fixture(t)
  pruneTestResults(f.directory)
  const first = f.coverage(1, 1), second = f.coverage(1, 2)
  for (const pid of [1, 2]) writeFileSync(join(f.directory, `failure-1-${pid}.log`), 'failure')
  pruneTestResults(f.directory, { state: gone })
  assert.equal(existsSync(first), false); assert.deepEqual(readdirSync(second), ['summary.json'])
  assert.equal(existsSync(join(f.directory, 'failure-1-1.log')), false)
  assert.equal(existsSync(join(f.directory, 'failure-1-2.log')), true)
})

for (const complete of [true, false]) test(`instrumented children finish and ${complete ? 'complete' : 'incomplete'} coverage is validated before profiles are removed`, async t => {
  const f = fixture(t)
  for (const name of ['coverage-preload.cjs', 'coverage-report.cjs']) copyFileSync(new URL(name, import.meta.url), join(f.root, 'Scripts', name))
  writeFileSync(join(f.root, 'Scripts/example.mjs'), complete ? 'export const answer = 42\n' : 'export function untested() { return 42 }\n')
  const result = await runTests({ root: f.root, scriptsOnly: true, coverage: true, logger,
    commands: [[process.execPath, ['--input-type=module', '--eval', "await import('./Scripts/example.mjs')"]]] })
  assert.equal(result.status, complete ? 0 : 1, readFileSync(result.logPath, 'utf8'))
  assert.deepEqual(readdirSync(result.coverageDirectory), ['summary.json'])
  const report = JSON.parse(readFileSync(join(result.coverageDirectory, 'summary.json'), 'utf8'))
  assert.equal(report.files.length, 1)
  if (complete) assert.equal(report.files[0].coveredLineCount, report.files[0].totalLineCount)
  else {
    assert.equal(result.signature, null)
    assert.match(readFileSync(result.logPath, 'utf8'), /Coverage must be 100%/)
    assert.equal(report.files[0].coveredFunctionCount, 0)
    assert.equal(report.files[0].totalFunctionCount, 1)
  }
  assert.equal(existsSync(join(f.directory, 'test.lock')), false)
})

test('failed coverage still blocks the run, keeping only its log and the previous available summary', async t => {
  const f = fixture(t)
  copyFileSync(new URL('coverage-preload.cjs', import.meta.url), join(f.root, 'Scripts/coverage-preload.cjs'))
  const previous = f.coverage(1, process.pid)
  writeFileSync(join(f.directory, 'failure-1-1.log'), 'old failure')
  const result = await runTests({ root: f.root, scriptsOnly: true, coverage: true, logger,
    commands: [[process.execPath, ['--eval', 'process.exit(2)']]] })
  assert.equal(result.status, 2); assert.equal(result.signature, null)
  assert.equal(existsSync(result.coverageDirectory), false)
  assert.equal(existsSync(previous), true, 'A live owner must be preserved')
  assert.equal(existsSync(result.logPath), true)
  assert.equal(existsSync(join(f.directory, 'failure-1-1.log')), false)
  assert.equal(JSON.parse(readFileSync(join(f.directory, 'latest.json'), 'utf8')).status, 2)
})

test('a busy test lock prevents both tests and cleanup', async t => {
  const f = fixture(t), old = f.coverage(1, 1)
  const lock = acquireCommitLock({ lockPath: join(f.directory, 'test.lock') })
  assert.equal(lock.acquired, true)
  try {
    const result = await runTests({ root: f.root, logger, commands: [['fixture', []]], run: async () => assert.fail('lock must block execution') })
    assert.equal(result.status, 75)
    assert.equal(readdirSync(old).length, 5)
  } finally { lock.release() }
})

for (const status of [0, 2]) test(`a cleanup error preserves status ${status}, the receipt and lock release`, async t => {
  const f = fixture(t), messages = []
  // The test-result root must not be traversed through a symlink.
  const actual = join(f.root, 'actual-results')
  rmSync(f.directory, { recursive: true }); mkdirSync(actual); symlinkSync(actual, f.directory, 'junction')
  const result = await runTests({ root: f.root, logger: { log() {}, error: text => messages.push(text) },
    commands: [['fixture', []]], run: async () => status })
  assert.equal(result.status, status)
  assert.equal(JSON.parse(readFileSync(join(actual, 'latest.json'), 'utf8')).status, status)
  assert.ok(messages.some(message => message.includes('清理未完成')))
  assert.equal(existsSync(join(actual, 'test.lock')), false)
})
