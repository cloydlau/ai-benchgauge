import assert from 'node:assert/strict'
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { resolve } from 'node:path'
import { availableDevice, claimWorker, deploymentPaths, deploymentTick, mobileCheck, deviceBuildArguments, bundleID, readJSON, writeJSON } from './ios-deploy.mjs'

const directory = mkdtempSync(resolve(tmpdir(), 'benchgauge-ios-deploy-'))
const paths = deploymentPaths(directory)
const config = { device: 'phone', team: 'ABCDEFGHIJ', developerDir: '/test/Xcode', launchAfterInstall: true }
const devices = { result: { devices: [{ identifier: 'device-uuid', properties: {
  hardware: { udid: 'phone', reality: 'physical', platform: 'iOS' }, connection: { pairingState: 'paired', state: 'connected' },
} }] } }
let current = 'checked', offline = false, failure = '', editDuringBuild = false
let calls = []
function record(phase, message, error) {
  writeJSON(paths.status, { phase, message, error, device: config.device, request: readJSON(paths.request)?.id })
}
async function execute(command, args) {
  calls.push([command, ...args])
  if (command === 'xcrun' && args[1] === 'list') return JSON.stringify(offline ? { result: { devices: [] } } : devices)
  if ((command === 'xcodebuild' && failure === 'build') || (args.includes('install') && failure === 'install') || (args.includes('launch') && failure === 'launch')) throw new Error('simulated ' + failure)
  if (command === 'xcodebuild') {
    mkdirSync(paths.app, { recursive: true }); writeFileSync(resolve(paths.app, 'embedded.mobileprovision'), 'signed')
    if (editDuringBuild) current = 'newer-unchecked'
  }
  return command === '/usr/libexec/PlistBuddy' ? 'com.cloydlau.ai-benchgauge.ipad' : ''
}
const tick = () => deploymentTick({ paths, config, fingerprint: async () => current, execute, record })
function request(id = 'job') { writeJSON(paths.request, { id, fingerprint: 'checked', sourceFingerprint: 'a'.repeat(64) }); calls = [] }
try {
  assert.equal(availableDevice(devices, 'phone').identifier, 'device-uuid')
  assert.ok(availableDevice({ result: { devices: [{ identifier: 'legacy', hardwareProperties: { udid: 'phone', reality: 'physical', platform: 'iOS' }, connectionProperties: { pairingState: 'paired', tunnelState: 'connected' } }] } }, 'phone'))
  assert.equal(availableDevice(devices, 'another-phone'), undefined)
  assert.equal(await tick(), 'idle'); assert.equal(calls.length, 0)
  const signedArguments = deviceBuildArguments(paths, config)
  assert.ok(signedArguments.includes(paths.project) && signedArguments.includes('BenchGauge'))
  assert.ok(signedArguments.includes('DEVELOPMENT_TEAM=ABCDEFGHIJ'))
  assert.ok(paths.app.endsWith('/AI BenchGauge.app'))
  assert.equal(bundleID, 'com.cloydlau.ai-benchgauge.ipad')
  await assert.rejects(mobileCheck({ paths, config, fingerprint: async () => current, execute }), /源码已变化/)
  assert.equal(calls.length, 0, 'Mobile compilation must require the exact checked source')
  writeJSON(paths.checkpoint, { fingerprint: 'checked' })
  await mobileCheck({ paths, config, fingerprint: async () => current, execute })
  assert.ok(calls.some(call => call.includes('CODE_SIGNING_ALLOWED=NO') && call.includes('generic/platform=iOS Simulator')))
  calls = []
  await mobileCheck({ paths, config, fingerprint: async () => current, execute })
  assert.equal(calls.length, 0, 'A matching mobile check must be reused')
  rmSync(paths.mobileCheck); editDuringBuild = true
  await assert.rejects(mobileCheck({ paths, config, fingerprint: async () => current, execute }), /源码已变化/)
  assert.equal(readJSON(paths.mobileCheck), null, 'An edited mobile build must not produce a pass')
  current = 'checked'; editDuringBuild = false; calls = []
  request(); offline = true
  assert.equal(await tick(), 'pending'); assert.equal(readJSON(paths.status).phase, 'waiting-device')
  assert.equal(calls.length, 1); assert.equal(readJSON(paths.receipt), null)
  offline = false; current = 'unchecked'
  assert.equal(await tick(), 'pending'); assert.equal(calls.length, 1, 'Unchecked changes must never reach device commands')
  current = 'checked'; failure = 'build'; calls = []
  assert.equal(await tick(), 'idle'); assert.equal(readJSON(paths.status).phase, 'build-failed')
  calls = []; await tick(); assert.equal(calls.length, 0, 'Signing failures must not retry continuously')
  failure = ''; request('retry'); editDuringBuild = true
  assert.equal(await tick(), 'pending'); assert.ok(!calls.some(call => call.includes('install')), 'Edits arriving during compilation must block installation')
  assert.equal(readJSON(paths.built), null, 'A build made during edits must not become reusable')
  current = 'checked'; editDuringBuild = false; failure = 'install'; request('retry-install')
  await assert.rejects(tick(), /simulated install/); assert.equal(readJSON(paths.receipt), null)
  failure = 'launch'; calls = []
  assert.equal(await tick(), 'idle'); assert.equal(readJSON(paths.receipt).fingerprint, 'checked')
  assert.equal(readJSON(paths.status).phase, 'installed')
  assert.equal(readJSON(paths.receipt).schemaVersion, 1)
  assert.equal(readJSON(paths.receipt).status, 'success')
  assert.equal(readJSON(paths.receipt).sourceFingerprint, 'a'.repeat(64), 'Only the installed candidate supplies the per-client source version')
  assert.ok(Number.isFinite(Date.parse(readJSON(paths.receipt).installedAt)))
  assert.ok(!calls.some(call => call[0] === 'xcodebuild'), 'An installation retry must reuse the signed build')
  calls = []; await tick(); assert.equal(calls.length, 0, 'Delivered versions must not poll the phone or reinstall')
  const release = claimWorker(paths.lock, 123, () => true)
  assert.ok(release); assert.equal(claimWorker(paths.lock, 124, () => true), null)
  release()
  const stale = claimWorker(paths.lock, 123, () => false)
  const replacement = claimWorker(paths.lock, 124, () => false)
  stale(); assert.equal(readJSON(resolve(paths.lock, 'owner.json')).pid, 124, 'A stale owner must not release its replacement')
  replacement()
  console.log('PASS: iPhone deployment queue / offline reconnect / checked-source gate / mid-build edits / signature failures / installation retry / locked-phone launch / single worker.')
} finally { rmSync(directory, { recursive: true, force: true }) }
