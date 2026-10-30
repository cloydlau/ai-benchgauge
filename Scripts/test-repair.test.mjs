import assert from 'node:assert/strict'
import { execFileSync } from 'node:child_process'
import { copyFileSync, mkdtempSync, mkdirSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import test from 'node:test'
import { ci } from './calmmit.mjs'
import { readBoundCoveragePass, readSharedCoveragePass, repairTests, runTestGate } from './test-repair.mjs'
import { fullCoverageReuseSignature, testInputSignature } from './test.mjs'
import { coverageSummaryDigest } from './test-reuse.mjs'

const passReport = { completed: true, verdict: 'pass', summary: 'fixed', fixes: [], decisions: [], issues: [] }
const protectedSignature = () => 'same'

test('test gate permits authorized test and script repairs and verifies the full gate', async t => {
  const root = mkdtempSync(join(tmpdir(), 'benchgauge-shared-repair-'))
  t.after(() => rmSync(root, { recursive: true, force: true }))
  execFileSync('git', ['init', '-q', root])
  mkdirSync(join(root, 'Scripts'))
  writeFileSync(join(root, 'Scripts/check.test.mjs'), 'original\n')
  execFileSync('git', ['-C', root, 'add', '.'])
  execFileSync('git', ['-C', root, '-c', 'user.name=fixture', '-c', 'user.email=fixture@example.test', 'commit', '-qm', 'fixture'])
  const { saveRepairContext } = await ci.load('repair-context')
  saveRepairContext(root, { request: '同步测试', paths: ['Scripts/check.test.mjs', 'Scripts/check.mjs'], testUpdates: ['Scripts/check.test.mjs'] })
  let calls = 0
  const result = await runTestGate({ root, env: {}, test: async () => ({ status: ++calls === 1 ? 1 : 0 }),
    repairWithAi: async () => {
      writeFileSync(join(root, 'Scripts/check.test.mjs'), 'updated\n')
      writeFileSync(join(root, 'Scripts/check.mjs'), 'fixed\n')
      return passReport
    },
  })
  assert.equal(result.status, 0)
  assert.equal(calls, 2)
})

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
  execFileSync('git', ['init', '-q', root])
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

test('an empty coverage worker profile retries the full gate once without editing source',async t=>{
  const root=mkdtempSync(join(tmpdir(),'benchgauge-coverage-retry-'))
  execFileSync('git',['init','-q',root])
  t.after(()=>rmSync(root,{recursive:true,force:true}))
  const logPath=join(root,'failed.log')
  writeFileSync(logPath,'ℹ fail 0\nℹ Warning: Could not report code coverage. Error [ERR_OPERATION_FAILED]: Operation failed: coverage file is empty: fixture.json\n')
  for(const secondStatus of [0,1]){
    let attempts=0,repairs=0
    const result=await runTestGate({root,env:{},
      test:async()=>++attempts===1?{status:1,logPath}:{status:secondStatus,signature:secondStatus===0?'full-pass':null},
      repairWithAi:()=>{repairs++;throw Error('must not modify source for infrastructure failure')},
    })
    assert.equal(attempts,2)
    assert.equal(repairs,0)
    assert.equal(result.status,secondStatus)
    if(secondStatus===0)assert.equal(result.signature,'full-pass')
  }
  writeFileSync(logPath,'ℹ fail 1\nWarning: Could not report code coverage. Error [ERR_OPERATION_FAILED]: Operation failed: coverage file is empty: fixture.json\n')
  let attempts=0
  await runTestGate({root,env:{TEST_AUTO_REPAIR:'0'},test:async()=>{attempts++;return{status:1,logPath}}})
  assert.equal(attempts,1)
})

test('child gates reject caller-bound results without cross-process evidence',async t=>{
 const root=mkdtempSync(join(tmpdir(),'benchgauge-verified-coverage-'))
 t.after(()=>rmSync(root,{recursive:true,force:true}))
 mkdirSync(join(root,'Sources'));writeFileSync(join(root,'Sources/example.swift'),'initial')
 mkdirSync(join(root,'work/test-results'),{recursive:true})
 const env={...process.env}
 const signature=testInputSignature(root,env)
 const valid={status:0,scope:'all',coverage:true,signature}
 const path=join(root,'work/test-results/latest.json')
 for(const cached of ['invalid',JSON.stringify({...valid,status:1}),JSON.stringify({...valid,scope:'core'}),
   JSON.stringify({...valid,coverage:false}),JSON.stringify({...valid,signature:'old'}),JSON.stringify(valid)]){
  writeFileSync(path,cached)
  let calls=0
  const result=await runTestGate({root,env:{...env,BENCHGAUGE_TEST_PASS:signature},test:async()=>{calls++;return{status:0,signature:'fresh'}}})
  assert.equal(calls,1)
  assert.notEqual(result.reused,true)
 }
 for(const bound of [undefined,'wrong']){
  writeFileSync(path,JSON.stringify(valid))
  let calls=0
  await runTestGate({root,env:{...env,BENCHGAUGE_TEST_PASS:bound},test:async()=>{calls++;return{status:0}}})
  assert.equal(calls,1)
 }
 writeFileSync(join(root,'Sources/example.swift'),'new source')
 let calls=0
 await runTestGate({root,env:{...env,BENCHGAUGE_TEST_PASS:signature},test:async()=>{calls++;return{status:0}}})
 assert.equal(calls,1)
})

test('independent gates reject incomplete, failed, stale or unverifiable coverage evidence', t => {
  const root = mkdtempSync(join(tmpdir(), 'benchgauge-shared-proof-'))
  t.after(() => rmSync(root, { recursive: true, force: true }))
  mkdirSync(join(root, 'work/test-results'), { recursive: true })
  const env = { ...process.env }
  const path = join(root, 'work/test-results/latest.json')
  const coverageDirectory = join(root, 'work/test-results/coverage-123-456')
  mkdirSync(coverageDirectory)
  writeFileSync(join(coverageDirectory, 'summary.json'), '{}')
  const valid = { status: 0, scope: 'all', coverage: true,
    signature: testInputSignature(root, env), reuseFingerprint: 'same', coverageDirectory,
    coverageDigest: coverageSummaryDigest(root, coverageDirectory) }
  let count = 0
  const read = fingerprint => readSharedCoveragePass({ root, env, fingerprint: () => { count++; return fingerprint } })
  assert.equal(read('same'), null)
  for (const invalid of [{ ...valid, status: 1 }, { ...valid, scope: 'core' },
    { ...valid, coverage: false }, { ...valid, signature: 'old' }, { ...valid, reuseFingerprint: '' }]) {
    writeFileSync(path, JSON.stringify(invalid))
    assert.equal(read('same'), null)
  }
  assert.equal(count, 0)
  writeFileSync(path, JSON.stringify(valid))
  assert.equal(read(null), null)
  assert.equal(read('different'), null)
  assert.equal(read('same').reused, true)
  assert.equal(count, 3)
  writeFileSync(path, JSON.stringify({ ...valid, skipped: [{ suite: 'swift', reason: 'unavailable' }] }))
  assert.equal(read('same').skipped[0].suite, 'swift')
  writeFileSync(join(coverageDirectory, 'summary.json'), '{"changed":true}')
  assert.equal(read('same'), null)
})

test('deployment cannot accept a parent-only pass without a cross-process proof', async t => {
  const root = mkdtempSync(join(tmpdir(), 'benchgauge-require-proof-'))
  t.after(() => rmSync(root, { recursive: true, force: true }))
  mkdirSync(join(root, 'work/test-results'), { recursive: true })
  const env = { ...process.env }
  const signature = testInputSignature(root, env)
  writeFileSync(join(root, 'work/test-results/latest.json'), JSON.stringify({ status: 0, scope: 'all', coverage: true, signature }))
  let runs = 0
  const result = await runTestGate({ root, env: { ...env, BENCHGAUGE_TEST_PASS: signature }, requireSharedProof: true,
    test: async () => { runs++; return { status: 0 } } })
  assert.equal(runs, 1)
  assert.equal(result.reused, undefined)
})

test('independent process reuses a real matching proof and rejects an edited input', async t => {
  const root = mkdtempSync(join(tmpdir(), 'benchgauge-real-proof-'))
  t.after(() => rmSync(root, { recursive: true, force: true }))
  execFileSync('git', ['init', '-q', root])
  mkdirSync(join(root, 'library/src'), { recursive: true })
  mkdirSync(join(root, 'work/test-results'), { recursive: true })
  const coverageDirectory = join(root, 'work/test-results/coverage-123-456')
  mkdirSync(coverageDirectory)
  writeFileSync(join(coverageDirectory, 'summary.json'), '{}')
  writeFileSync(join(root, '.gitignore'), 'work/\n')
  writeFileSync(join(root, 'calmmit.config.json'), JSON.stringify({ library: 'library' }))
  writeFileSync(join(root, 'library/src/library.mjs'), 'library')
  writeFileSync(join(root, 'source'), 'one')
  execFileSync('git', ['-C', root, 'add', '-A'])
  const index = join(root, '.git/commit-index-9001')
  copyFileSync(join(root, '.git/index'), index)
  const env = { ...process.env }
  delete env.CALMMIT_PATH
  env.CALMMIT_ROOT = root
  const signature = testInputSignature(root, env)
  const reuseFingerprint = fullCoverageReuseSignature(root, env)
  assert.match(reuseFingerprint, /^[a-f0-9]{64}$/)
  writeFileSync(join(root, 'work/test-results/latest.json'), JSON.stringify({ status: 0, scope: 'all', coverage: true, signature, reuseFingerprint, coverageDirectory, coverageDigest: coverageSummaryDigest(root, coverageDirectory) }))
  assert.equal(readBoundCoveragePass({ root, env: { ...env, BENCHGAUGE_TEST_PASS: 'different' } }), null)
  assert.equal(readBoundCoveragePass({ root, env: { ...env, BENCHGAUGE_TEST_PASS: signature } }).reused, true)
  assert.equal(readSharedCoveragePass({ root, env }).reused, true)
  const commitEnv = { ...env, COMMIT_REQUIRE_LOCK: '1', CALMMIT_INTERNAL: '1', CALMMIT_TEST_INDEX: index }
  delete commitEnv.CALMMIT_ROOT
  assert.equal(readSharedCoveragePass({ root, env: commitEnv, requireIndex: true }).reused, true)
  assert.equal(readSharedCoveragePass({ root, env: commitEnv, requireIndex: true, fingerprint: () => {
    writeFileSync(join(root, 'source'), 'changed during verification')
    return reuseFingerprint
  } }), null)
  writeFileSync(join(root, 'source'), 'one')
  let calls = 0
  const result = await runTestGate({ root, env, requireSharedProof: true, test: async () => { calls++; return { status: 1 } } })
  assert.equal(result.reused, true)
  assert.equal(calls, 0)
  const custom = await runTestGate({ root, env, test: async () => { calls++; return { status: 0 } } })
  assert.equal(custom.reused, undefined)
  assert.equal(calls, 1)
  writeFileSync(join(root, 'source'), 'two')
  assert.equal(readSharedCoveragePass({ root, env }), null)
  assert.equal(readSharedCoveragePass({ root, env: commitEnv, requireIndex: true }), null)
})
