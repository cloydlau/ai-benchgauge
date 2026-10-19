import test from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import cp from 'node:child_process'
import { syncBuiltinESMExports } from 'node:module'
import { createHash } from 'node:crypto'
import { tmpdir } from 'node:os'
import { resolve, join } from 'node:path'
import { availableConfiguration, claimWorker, configuration, deploymentPaths, deploymentTick, mobileCheck, readJSON, writeJSON, bundleID, availableDevice } from './ios-deploy.mjs'

const root = resolve(import.meta.dirname, '..')
const preload = String.raw`
const fs = require('node:fs'), cp = require('node:child_process'), { EventEmitter } = require('node:events')
const { syncBuiltinESMExports } = require('node:module'), path = require('node:path')
const root = process.env.UNIT_ROOT, mode = process.env.UNIT_MODE, log = path.join(root, 'calls.jsonl')
const record = value => fs.appendFileSync(log, JSON.stringify(value) + '\n')
let fingerprintReads = 0, signatureReads = 0, sleeps = 0
const timer = global.setTimeout
let commandChild
process.kill = (pid, signal) => {
  record(['kill', pid, signal])
  if (mode === 'kill-error' && pid < 0) throw new Error('fixture denied kill')
  if (mode === 'command-timeout' && pid < 0) queueMicrotask(() => commandChild.emit('close', null))
  if (mode === 'permission-owner' && signal === 0) throw Object.assign(new Error('permission'), { code: 'EPERM' })
  if (mode === 'dead-owner' && signal === 0) throw Object.assign(new Error('dead'), { code: 'ESRCH' })
}
global.unitFingerprint = () => { fingerprintReads++; return mode === 'source-drift' && fingerprintReads > 1 ? 'changed' : 'fixture' }
global.unitSignature = () => { signatureReads++; return (mode === 'signature-drift' && signatureReads > 1 || mode === 'post-mobile-signature' && signatureReads > 1) ? 'changed' : 'pass' }
cp.spawnSync = (command, args) => { record([command, ...args]); return { status: mode === 'bad-ps' ? 1 : 0, stdout: path.join(root, 'Scripts/ios-deploy.mjs') + ' watch' } }
cp.spawn = (command, args, options) => {
  record([command, ...args]); const child = new EventEmitter(); child.pid = 900000
  commandChild = child
  child.stdout = new EventEmitter(); child.stderr = new EventEmitter(); child.unref = () => record(['unref'])
  if (args.includes('watch')) return child
  queueMicrotask(() => {
    if (mode === 'spawn-error') { child.emit('error', new Error('fixture spawn failure')); return }
    const device = { identifier: 'phone', properties: { hardware: { reality: 'physical', platform: 'iOS' }, connection: { pairingState: 'paired', state: 'connected' } } }
    if (command === 'xcrun') child.stdout.emit('data', ['oversized-output', 'kill-error'].includes(mode) ? 'x'.repeat(9 * 1024 * 1024) : mode === 'invalid-json' ? 'invalid' : JSON.stringify({ result: { devices: [device] } }))
    if (command === 'xcodebuild' && args.includes('generic/platform=iOS')) {
      const app = path.join(root, 'work/ios-deploy/DerivedData/Build/Products/Debug-iphoneos/AI BenchGauge.app')
      fs.mkdirSync(app, { recursive: true }); fs.writeFileSync(path.join(app, 'embedded.mobileprovision'), 'unit fixture')
    }
    if (command === '/usr/libexec/PlistBuddy') child.stdout.emit('data', 'com.cloydlau.ai-benchgauge.ipad')
    if (mode === 'command-error' || mode === 'capture-stderr') child.stderr.emit('data', 'fixture stderr')
    // A timed-out process stays running; scheduling a successful close here
    // races the timeout timer and sometimes tests the success path instead.
    const close = () => child.emit('close', mode === 'command-error' || mode === 'capture-stderr' ? 2 : 0)
    if (mode === 'abort-command') { process.emit('SIGTERM'); timer(close, 20) }
    else if (['command-timeout', 'oversized-output', 'kill-error'].includes(mode)) timer(close, 20)
    else setImmediate(close)
  })
  return child
}
fs.watch = (directory, callback) => {
  record(['watch', directory]); queueMicrotask(() => { callback('change', 'unrelated.json'); callback('change', 'request.json') }); if (mode === 'wake-request') timer(() => callback('change', 'request.json'), 0)
  return { close: () => record(['watch-close']) }
}
global.setTimeout = (callback, ms, ...args) => {
  if (mode === 'command-timeout' && ms >= 60000) return timer(callback, 0, ...args)
  if (ms === 30000 || ms === 60000) {
    sleeps++; return timer(() => { if (sleeps >= 2) process.emit('SIGTERM'); callback(...args) }, 0)
  }
  if (ms === 2000 && ['oversized-output','ignore-term','kill-error'].includes(mode)) return timer(callback, 0, ...args)
  return timer(callback, ms, ...args)
}
syncBuiltinESMExports()
`

function fixture(t, mode = '') {
  const directory = fs.realpathSync(fs.mkdtempSync(join(tmpdir(), 'benchgauge-ios-unit-')))
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }))
  fs.mkdirSync(join(directory, 'Scripts'))
  fs.copyFileSync(join(root, 'Scripts/ios-deploy.mjs'), join(directory, 'Scripts/ios-deploy.mjs'))
  fs.writeFileSync(join(directory, 'Scripts/build-cache.mjs'), 'export async function withBuildCache(root, profile, action) { return action() }')
  fs.writeFileSync(join(directory, 'Scripts/node-executable.mjs'), 'export const nodeExecutable = () => process.env.BENCHGAUGE_NODE || process.execPath')
  fs.writeFileSync(join(directory, 'Scripts/calmmit.mjs'), `export const ci = { load: async () => ({ readSourceFingerprint: async () => globalThis.unitFingerprint() }) }`)
  fs.writeFileSync(join(directory, 'Scripts/test.mjs'), `export const testInputSignature = () => globalThis.unitSignature()`)
  fs.writeFileSync(join(directory, 'Scripts/ios-project.mjs'), `export function generateIOSProject(root, options) { if (options.team !== 'ABCDEFGHIJ') throw new Error('wrong team') }`)
  fs.mkdirSync(join(directory, 'apps/ios/App/Assets.xcassets'), { recursive: true })
  fs.writeFileSync(join(directory, 'apps/ios/App/Assets.xcassets/fixture.txt'), 'unit fixture')
  const xcode = join(directory, 'Xcode'); fs.mkdirSync(join(xcode, 'usr/bin'), { recursive: true }); fs.writeFileSync(join(xcode, 'usr/bin/xcodebuild'), '')
  writeJSON(join(directory, 'calmmit.config.json'), { dev: { activity: [{ kind: 'ios-app', sources: ['apps/ios'] }] } })
  const paths = deploymentPaths(directory)
  writeJSON(paths.config, { device: 'phone', team: 'ABCDEFGHIJ', developerDir: xcode })
  fs.mkdirSync(join(directory, 'work/test-results'), { recursive: true })
  writeJSON(join(directory, 'work/test-results/latest.json'), { status: 0, signature: 'pass' })
  const fingerprint = createHash('sha256').update(JSON.stringify(['fixture', 'phone', 'ABCDEFGHIJ', xcode])).digest('hex')
  writeJSON(paths.checkpoint, { fingerprint })
  const hook = join(directory, 'unit-preload.cjs'); fs.writeFileSync(hook, preload)
  const invoke = command => cp.spawnSync(process.execPath, ['--require', hook, join(directory, 'Scripts/ios-deploy.mjs'), command], {
    encoding: 'utf8', timeout: 10000, env: { ...process.env, UNIT_ROOT: directory, UNIT_MODE: mode, BENCHGAUGE_TEST_PASS: 'pass' },
  })
  const calls = () => fs.existsSync(join(directory, 'calls.jsonl')) ? fs.readFileSync(join(directory, 'calls.jsonl'), 'utf8').trim().split('\n').map(JSON.parse) : []
  return { directory, paths, fingerprint, invoke, calls }
}

test('CLI validates exact source evidence and queues work without starting real device commands', t => {
  const f = fixture(t)
  assert.equal(f.invoke('status').status, 0)
  assert.equal(f.invoke('prepare').status, 0)
  assert.ok(fs.existsSync(join(f.paths.directory, 'Assets.xcassets/fixture.txt')))
  assert.equal(f.invoke('checkpoint').status, 0)
  assert.equal(readJSON(f.paths.checkpoint).fingerprint, f.fingerprint)
  assert.equal(f.invoke('checked').status, 0)
  assert.equal(readJSON(f.paths.request).fingerprint, f.fingerprint)
  assert.equal(readJSON(f.paths.request).sourceFingerprint, 'fixture', 'Queue records the client source separately from device/signing inputs')
  const id = readJSON(f.paths.request).id
  assert.equal(f.invoke('enqueue').status, 0)
  assert.equal(readJSON(f.paths.request).id, id)
  assert.equal(f.invoke('retry').status, 0)
  assert.notEqual(readJSON(f.paths.request).id, id)
  assert.ok(f.calls().some(call => call[0] === 'unref'))
  assert.equal(f.invoke('unknown').status, 1)
  writeJSON(join(f.directory, 'work/test-results/latest.json'), { status: 1, signature: 'pass' })
  assert.match(f.invoke('checked').stderr, /完整测试/)
  assert.match(f.invoke('enqueue').stderr, /完整测试/)
  writeJSON(join(f.directory, 'work/test-results/latest.json'), { status: 0, signature: 'pass' })
  writeJSON(f.paths.checkpoint, { fingerprint: 'stale' })
  assert.match(f.invoke('enqueue').stderr, /源码已变化/)
})

test('CLI refuses signature drift and reports command failures', t => {
  for (const mode of ['signature-drift', 'spawn-error', 'command-error', 'command-timeout']) {
    const f = fixture(t, mode)
    const result = f.invoke(mode === 'signature-drift' ? 'checked' : 'prepare')
    assert.equal(result.status, 1, `${mode}: ${result.stdout} ${result.stderr}`)
    assert.match(result.stderr, mode === 'signature-drift' ? /源码已变化/ : mode === 'spawn-error' ? /fixture spawn failure/ : /失败|超时/)
  }
})

test('single worker ownership checks process state and releases only its own lock', t => {
  for (const mode of ['', 'permission-owner', 'dead-owner', 'bad-ps']) {
    const f = fixture(t, mode)
    fs.mkdirSync(f.paths.lock)
    writeJSON(join(f.paths.lock, 'owner.json'), { pid: 900000, token: 'fixture' })
    assert.equal(f.invoke('stop').status, 0)
    assert.equal(readJSON(f.paths.config).enabled, false)
    assert.equal(f.calls().some(call => call[0] === 'kill' && call[2] === 'SIGTERM'), mode === '' || mode === 'permission-owner')
  }
  const f = fixture(t)
  fs.mkdirSync(f.paths.lock)
  assert.equal(claimWorker(f.paths.lock, 2, () => false), null, 'An ownerless newly-created lock must not be stolen')
  const old = new Date(Date.now() - 11000); fs.utimesSync(f.paths.lock, old, old)
  const release = claimWorker(f.paths.lock, 2, () => false); assert.equal(typeof release, 'function'); release()
  assert.throws(() => claimWorker(join(f.paths.directory, 'missing/lock'), 2, () => false), { code: 'ENOENT' })
})

test('watcher wakes, retries transient failures and stops without touching a real phone', t => {
  for (const mode of ['', 'invalid-json', 'oversized-output', 'source-drift', 'capture-stderr', 'spawn-error']) {
    const f = fixture(t, mode)
    if (mode !== '') writeJSON(f.paths.request, { id: 'fixture', fingerprint: f.fingerprint })
    const result = f.invoke('watch')
    assert.equal(result.status, 0, `${mode}: ${result.stderr}`)
    assert.ok(f.calls().some(call => call[0] === 'watch-close'))
    assert.equal(fs.existsSync(f.paths.lock), false)
    if (['invalid-json','oversized-output','capture-stderr','spawn-error'].includes(mode)) assert.equal(readJSON(f.paths.status).phase, 'waiting-device')
  }
  const f = fixture(t); writeJSON(f.paths.config, { enabled: false })
  assert.equal(f.invoke('watch').status, 0)
  assert.equal(f.invoke('stop').status, 0)
  fs.rmSync(f.paths.config)
  assert.equal(f.invoke('stop').status, 0)
  assert.match(f.invoke('prepare').stdout, /未启用/)
})

test('configuration and filesystem failures remain actionable', t => {
  const f = fixture(t)
  for (const value of [{}, { device: 'phone' }, { device: 'phone', team: 'ABCDEFGHIJ', developerDir: '/definitely-missing-fixture' }]) {
    writeJSON(f.paths.config, value)
    assert.throws(() => configuration(f.paths), /device|team|Xcode/)
  }
  writeJSON(f.paths.config, {})
  assert.throws(() => availableConfiguration(f.paths, { warn() {} }), /device/)
  writeJSON(f.paths.config, { enabled: false }); assert.equal(configuration(f.paths), null)
  fs.writeFileSync(f.paths.config, 'invalid'); assert.throws(() => readJSON(f.paths.config), SyntaxError)
  const originalMkdir = fs.mkdirSync
  t.mock.method(fs, 'mkdirSync', (file, ...args) => { if (file === f.paths.lock) throw Object.assign(new Error('fixture denied'), { code: 'EACCES' }); return originalMkdir(file, ...args) })
  syncBuiltinESMExports(); t.after(() => { t.mock.restoreAll(); syncBuiltinESMExports() })
  assert.throws(() => claimWorker(f.paths.lock), /fixture denied/)
  assert.equal(availableDevice({ result: { devices: [{ identifier: 'phone' }] } }, 'phone'), undefined)
})

test('missing full Xcode is recorded as a warning and skips iOS CLI work', t => {
  const f = fixture(t), warnings = []
  writeJSON(f.paths.config, { device: 'phone', team: 'ABCDEFGHIJ', developerDir: '/definitely-missing-fixture' })
  assert.equal(availableConfiguration(f.paths, { warn: message => warnings.push(message) }), null)
  assert.match(warnings[0], /已跳过本机 iPhone 更新；其他端继续/)
  assert.equal(readJSON(f.paths.status).phase, 'toolchain-unavailable')
  const result = f.invoke('checked')
  assert.equal(result.status, 0)
  assert.match(result.stderr, /警告.*已跳过本机 iPhone 更新/)
  assert.deepEqual(f.calls(), [])
})


test('deployment distinguishes invalid signatures, superseded requests and cancelled builds', async t => {
  const device={result:{devices:[{identifier:'phone',properties:{hardware:{reality:'physical',platform:'iOS'},connection:{pairingState:'paired',state:'connected'}}}]}}
  for(const mode of ['missing-profile','wrong-bundle','aborted','superseded','superseded-missing','signature-changed','already-built','no-launch']) {
    const f=fixture(t),events=[]
    writeJSON(f.paths.request,{id:'request',fingerprint:'fixture'})
    const config={device:'phone',team:'ABCDEFGHIJ',developerDir:'fixture',launchAfterInstall:mode!=='no-launch'}
    if(mode==='already-built') {fs.mkdirSync(f.paths.app,{recursive:true});writeJSON(f.paths.built,{fingerprint:'fixture'})}
    let fingerprints=0
    const controller=new AbortController()
    const execute=async(command,args)=>{
      if(command==='xcrun'&&args.includes('list')) return JSON.stringify(device)
      if(command==='xcodebuild') {
        fs.mkdirSync(f.paths.app,{recursive:true})
        if(mode!=='missing-profile')fs.writeFileSync(join(f.paths.app,'embedded.mobileprovision'),'fixture')
        if(mode==='aborted'){controller.abort();throw Error('fixture cancellation')}
      }
      if(command==='/usr/libexec/PlistBuddy') {
        if(mode==='superseded')writeJSON(f.paths.request,{id:'new-request',fingerprint:'fixture'})
        if(mode==='superseded-missing')fs.rmSync(f.paths.request)
        return mode==='wrong-bundle'?'wrong':bundleID
      }
      return ''
    }
    const operation=()=>deploymentTick({paths:f.paths,config,fingerprint:async()=>++fingerprints>1&&mode==='signature-changed'?'changed':'fixture',execute,record:(...values)=>events.push(values),signal:controller.signal})
    if(mode==='aborted')await assert.rejects(operation(),/fixture cancellation/)
    else{
      const outcome=await operation()
      assert.equal(outcome,['superseded','superseded-missing','signature-changed'].includes(mode)?'pending':'idle')
      assert.equal(events.at(-1)[0],['missing-profile','wrong-bundle'].includes(mode)?'build-failed':['superseded','superseded-missing','signature-changed'].includes(mode)?'waiting-ci':'installed')
    }
  }
})

test('failed receipts are scoped to both request and device', async t => {
  const f=fixture(t);writeJSON(f.paths.request,{id:'request',fingerprint:'fixture'})
  const config={device:'phone'},events=[]
  const run=()=>deploymentTick({paths:f.paths,config,fingerprint:async()=> 'fixture',execute:async()=> '{"result":{"devices":[]}}',record:(...v)=>events.push(v)})
  for(const value of [{request:'request',device:'phone',phase:'build-failed'},{request:'different',device:'phone',phase:'build-failed'},{request:'request',device:'other',phase:'build-failed'},{request:'request',device:'phone',phase:'installed'}]){
    writeJSON(f.paths.status,value)
    assert.equal(await run(),value.request==='request'&&value.device==='phone'&&value.phase==='build-failed'?'idle':'pending')
  }
})


test('CLI reuses active workers, rejects invalid owners, and replaces failed requests', t => {
  const f = fixture(t)
  fs.mkdirSync(f.paths.lock)
  writeJSON(join(f.paths.lock, 'owner.json'), { pid: 900000 })
  assert.equal(f.invoke('enqueue').status, 0)
  assert.equal(f.invoke('watch').status, 0)
  assert.equal(f.calls().some(call => call.includes('watch') && call[0] === process.execPath), false)
  const id = readJSON(f.paths.request).id
  writeJSON(f.paths.status, { phase: 'build-failed' })
  assert.equal(f.invoke('enqueue').status, 0)
  assert.notEqual(readJSON(f.paths.request).id, id)
  writeJSON(join(f.paths.lock, 'owner.json'), { pid: 1 })
  assert.equal(f.invoke('stop').status, 0)
  assert.equal(f.calls().some(call => call[0] === 'kill' && call[1] === 1), false)
  const drift = fixture(t, 'post-mobile-signature')
  assert.match(drift.invoke('enqueue').stderr, /测试依据已变化/)
})

test('default Xcode directory is resolved without requiring a host installation', t => {
  const f = fixture(t)
  const expected = '/Applications/Xcode.app/Contents/Developer'
  const original = fs.existsSync
  t.mock.method(fs, 'existsSync', file => file === join(expected, 'usr/bin/xcodebuild') || original(file))
  syncBuiltinESMExports(); t.after(() => { t.mock.restoreAll(); syncBuiltinESMExports() })
  writeJSON(f.paths.config, { device: 'phone', team: 'ABCDEFGHIJ' })
  assert.equal(configuration(f.paths).developerDir, expected)
})

test('worker handles queue wakeups, in-flight cancellation and failed termination safely', t => {
  for (const mode of ['wake-request', 'abort-command', 'kill-error']) {
    const f = fixture(t, mode)
    if (mode !== 'wake-request') writeJSON(f.paths.request, { id: 'fixture', fingerprint: f.fingerprint })
    const result = f.invoke('watch')
    assert.equal(result.status, 0, `${mode}: ${result.stderr}`)
    assert.equal(fs.existsSync(f.paths.lock), false)
    if (mode === 'kill-error') assert.ok(f.calls().some(call => call[0] === 'kill' && call[2] === 'SIGKILL'))
  }
})


test('a contender cannot steal a worker lock recreated between its two mkdir calls', t => {
 const f=fixture(t), original=fs.mkdirSync
 for(const code of ['EEXIST','EACCES']){
  fs.mkdirSync=fakeMkdir
  let calls=0
  function fakeMkdir(file,...args){if(file===f.paths.lock){calls++;throw Object.assign(Error('fixture race'),{code:calls===1?'EEXIST':code})}return original(file,...args)}
  syncBuiltinESMExports()
  fs.mkdirSync=original;original(f.paths.lock);writeJSON(join(f.paths.lock,'owner.json'),{pid:1});fs.mkdirSync=fakeMkdir;syncBuiltinESMExports()
  try{
   if(code==='EEXIST')assert.equal(claimWorker(f.paths.lock,2,()=>false),null)
   else assert.throws(()=>claimWorker(f.paths.lock,2,()=>false),{code:'EACCES'})
  }finally{fs.mkdirSync=original;syncBuiltinESMExports();fs.rmSync(f.paths.lock,{recursive:true,force:true})}
 }
})


test('mobile checks and device builds recover after their running Node binary is removed', async t => {
  const f = fixture(t), calls = []
  const config = { device: 'phone', team: 'ABCDEFGHIJ', developerDir: 'fixture', launchAfterInstall: false }
  writeJSON(f.paths.checkpoint, { fingerprint: 'fixture' })
  writeJSON(f.paths.request, { id: 'request', fingerprint: 'fixture' })
  const bin = join(f.directory, 'bin')
  fs.mkdirSync(bin)
  fs.symlinkSync(process.execPath, join(bin, 'node'))
  const expected = fs.realpathSync(process.execPath)
  const original = { execPath: process.execPath, PATH: process.env.PATH,
    BENCHGAUGE_NODE: process.env.BENCHGAUGE_NODE, CALMMIT_NODE: process.env.CALMMIT_NODE }
  const execute = async (command, args) => {
    calls.push([command, ...args])
    if (command === 'xcrun') return JSON.stringify({ result: { devices: [{ identifier: 'phone', properties: {
      hardware: { reality: 'physical', platform: 'iOS' }, connection: { pairingState: 'paired', state: 'connected' },
    } }] } })
    if (command === 'xcodebuild') {
      fs.mkdirSync(f.paths.app, { recursive: true })
      fs.writeFileSync(join(f.paths.app, 'embedded.mobileprovision'), 'fixture')
    }
    return command === '/usr/libexec/PlistBuddy' ? bundleID : ''
  }
  try {
    process.execPath = join(f.directory, 'removed-runtime/node')
    process.env.PATH = bin
    delete process.env.BENCHGAUGE_NODE
    delete process.env.CALMMIT_NODE
    await mobileCheck({ paths: f.paths, config, fingerprint: async () => 'fixture', execute })
    assert.equal(await deploymentTick({ paths: f.paths, config, fingerprint: async () => 'fixture', execute,
      record: () => {} }), 'idle')
    const preparations = calls.filter(call => call.includes('prepare'))
    assert.equal(preparations.length, 2)
    assert.ok(preparations.every(call => call[0] === expected))
    assert.ok(calls.some(call => call.includes('install')))
    assert.equal(readJSON(f.paths.receipt).status, 'success')
  } finally {
    process.execPath = original.execPath
    for (const key of ['PATH', 'BENCHGAUGE_NODE', 'CALMMIT_NODE']) {
      if (original[key] === undefined) delete process.env[key]
      else process.env[key] = original[key]
    }
  }
})

test('checked CLI and detached workers honor the selected Node runtime', t => {
  const f = fixture(t)
  const previous = process.env.BENCHGAUGE_NODE
  try {
    process.env.BENCHGAUGE_NODE = join(f.directory, 'selected-node')
    const result = f.invoke('checked')
    assert.equal(result.status, 0, result.stderr)
    for (const action of ['Scripts/check-syntax.mjs', 'prepare', 'watch']) {
      const calls = f.calls().filter(call => call.includes(action))
      assert.ok(calls.length > 0, action)
      assert.ok(calls.every(call => call[0] === process.env.BENCHGAUGE_NODE), action)
    }
  } finally {
    if (previous === undefined) delete process.env.BENCHGAUGE_NODE
    else process.env.BENCHGAUGE_NODE = previous
  }
})
