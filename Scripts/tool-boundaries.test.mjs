import assert from 'node:assert/strict'
import test from 'node:test'
import cp from 'node:child_process'
import { syncBuiltinESMExports } from 'node:module'
import { copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { pathToFileURL } from 'node:url'
import { readAppConfig, plistString, validateAppConfig } from './app-config.mjs'
import { platformVersion } from './app-version.mjs'
import { proxyUrlsFromScutil, gitProxyValue } from './git-network.mjs'
import { updateDependencies } from './dev-update-deps.mjs'
import { runWindowsTests } from './windows-tests.mjs'
import crypto from 'node:crypto'
import { releaseVersion, decodePublicKey, signingKey, signArchive, renderAppcast, renderHomebrewCask } from './release-lib.mjs'
import { iosProject } from './ios-project.mjs'
import { prepareSwiftWorkspace } from './prepare-swift-workspace.mjs'

function directory(t) {
  const root = realpathSync(mkdtempSync(join(tmpdir(), 'benchgauge-tool-boundary-')))
  t.after(() => rmSync(root, { recursive: true, force: true }))
  return root
}
function processMock(t, implementation) {
  t.mock.method(cp, 'spawnSync', implementation); syncBuiltinESMExports()
  t.after(() => { t.mock.restoreAll(); syncBuiltinESMExports() })
}

test('public application configuration rejects removed options, drift and missing plist fields', t => {
  const root = directory(t)
  const config = JSON.parse(readFileSync(new URL('../config/app.json', import.meta.url)))
  mkdirSync(join(root, 'config')); mkdirSync(join(root, 'apps/macos/Sources/Resources'), { recursive: true })
  function save(value) { writeFileSync(join(root, 'config/app.json'), JSON.stringify(value)) }
  save({ ...config, previewCCSwitchEmptyState: false })
  assert.throws(() => readAppConfig(root), /previewCCSwitchState/)
  save({ ...config, previewCCSwitchState: 'invalid' })
  assert.throws(() => readAppConfig(root), /previewCCSwitchState/)
  save({ ...config, repository: 'unrelated/repo' })
  assert.throws(() => readAppConfig(root), /repository/)
  for (const state of [undefined, null, 'notInstalled', 'installedEmpty', 'configured']) {
    save({ ...config, previewCCSwitchState: state })
    assert.equal(readAppConfig(root).version, config.version)
  }
  assert.throws(() => plistString('<plist/>', 'missing'), /Missing/)
  assert.equal(plistString('{"key":"value"}', 'key'), 'value')
  assert.equal(plistString('<key>key</key><string>value</string>', 'key'), 'value')
  const plist = join(root, 'apps/macos/Sources/Resources/Info.plist')
  writeFileSync(plist, JSON.stringify({ CFBundleVersion: platformVersion(config.version), CFBundleShortVersionString: platformVersion(config.version), BenchGaugeVersion: config.version, SUPublicEDKey: config.updatePublicKey }))
  assert.equal(validateAppConfig(root).version, config.version)
  assert.throws(() => validateAppConfig(root, 'v999.0.0'), /tag/)
  writeFileSync(plist, JSON.stringify({ CFBundleVersion: platformVersion(config.version), CFBundleShortVersionString: platformVersion(config.version), BenchGaugeVersion: config.version, SUPublicEDKey: 'different' }))
  assert.throws(() => validateAppConfig(root), /must match/)
})

test('release signatures fail closed and metadata validates missing optional values', t => {
  assert.throws(() => releaseVersion(null), /YYYYMMDD/)
  assert.throws(() => decodePublicKey(undefined), /SUPublicEDKey/)
  const key = crypto.generateKeyPairSync('ed25519').privateKey
  t.mock.method(crypto, 'verify', () => false); syncBuiltinESMExports()
  t.after(() => { t.mock.restoreAll(); syncBuiltinESMExports() })
  assert.throws(() => signArchive(Buffer.from('fixture'), key), /signature verification/)
  assert.throws(() => signingKey(undefined, undefined), /SUPublicEDKey/)
  assert.throws(() => renderAppcast({ version: '20261028', archiveName: 'AI-BenchGauge-20261028-macos-universal.dmg', length: 10 }), /metadata/)
  assert.throws(() => renderHomebrewCask({ version: '20261028', archiveName: 'AI-BenchGauge-20261028-macos-universal.dmg' }), /metadata/)
  for (const length of [0, 1.5]) assert.throws(() => renderAppcast({ version: '20261028', archiveName: 'AI-BenchGauge-20261028-macos-universal.dmg', length, signature: Buffer.alloc(64).toString('base64') }), /metadata/)
  assert.throws(() => iosProject({ version: '20261028', buildNumber: 'wrong' }), /build number/)
  assert.throws(() => iosProject({ version: '20261028', team: 'wrong' }), /team/)
})

test('Swift workspace recovery tolerates absent artifact metadata and unmatched remote paths', t => {
  const root = directory(t), cache = join(root, '.build')
  mkdirSync(cache)
  for (const state of [{}, { object: { artifacts: [{ source: { type: 'remote' }, path: '/unmatched/kit' }] } }]) {
    writeFileSync(join(cache, 'workspace-state.json'), JSON.stringify(state))
    assert.deepEqual(prepareSwiftWorkspace(root), [])
  }
})

test('project and visual policy CLI entry points validate their input in an isolated directory', t => {
  const root = directory(t)
  mkdirSync(join(root, 'Scripts')); mkdirSync(join(root, 'config'))
  for (const name of ['ios-project.mjs', 'ios-build.mjs', 'build-cache.mjs', 'app-config.mjs', 'release-lib.mjs', 'app-version.mjs', 'visual-review-policy.mjs', 'prepare-swift-workspace.mjs']) copyFileSync(new URL('./' + name, import.meta.url), join(root, 'Scripts', name))
  // ios-about.mjs imports weapp core modules outside Scripts/, so the sandbox stubs it.
  writeFileSync(join(root, 'Scripts/ios-about.mjs'), 'export function writeIOSAbout(directory, targetPath) { return targetPath }\n')
  copyFileSync(new URL('../config/app.json', import.meta.url), join(root, 'config/app.json'))
  const preload = join(root, 'sandbox.cjs')
  writeFileSync(preload, `
const cp = require('node:child_process');
cp.spawnSync = () => ({status:1});
require('node:module').syncBuiltinESMExports();
global.fetch = async () => ({ok: process.env.POLICY_OK === '1',status:403,json:async()=>({name:'native-visual-review',protection_rules:[{type:'required_reviewers',reviewers:[{type:'User',reviewer:{id:1}}]}]})});
`)
  function cli(name, args = [], extraEnv = {}) {
    return cp.spawnSync(process.execPath, ['--require', preload, join(root, 'Scripts', name), ...args], { encoding: 'utf8', cwd: root, env: { ...process.env, GH_TOKEN: 'fixture', GITHUB_REPOSITORY: 'fixture/repo', ...extraEnv } })
  }
  assert.equal(cli('ios-project.mjs').status, 0)
  assert.equal(cli('prepare-swift-workspace.mjs').status, 0)
  assert.equal(cli('ios-build.mjs').status, 1)
  assert.equal(cli('ios-build.mjs', ['test', 'iPhone']).status, 1)
  assert.equal(cli('visual-review-policy.mjs', [], { POLICY_OK: '1' }).status, 0)
  assert.equal(cli('visual-review-policy.mjs', [], { POLICY_OK: '0' }).status, 1)
})

test('proxy lookup handles missing system values and command failures without guessing', t => {
  processMock(t, () => ({ status: 1 }))
  assert.equal(gitProxyValue({}), '')
  cp.spawnSync = () => ({ status: 0 }); syncBuiltinESMExports()
  assert.equal(gitProxyValue({}), '')
  for (const text of ['HTTPEnable : 1', 'HTTPEnable : 1\nHTTPProxy : localhost', 'HTTPEnable : 1\nHTTPPort : 80', 'SOCKSEnable : 1\nSOCKSProxy : localhost', 'SOCKSEnable : 1\nSOCKSPort : 80']) {
    assert.deepEqual(proxyUrlsFromScutil(text), { https: '', http: '', socks: '' })
  }
  assert.equal(gitProxyValue({}, 'HTTPEnable : 1\nHTTPProxy : localhost\nHTTPPort : 80'), 'http://localhost:80')
})

test('dependency updates and Windows checks retain actual failure status', t => {
  const messages = []
  assert.equal(updateDependencies({ platform: 'darwin', execute: () => ({ status: 7 }), log: value => messages.push(value) }), 1)
  assert.match(messages.at(-1), /退出码 7/)
  processMock(t, () => ({ error: Error('SDK missing'), status: null }))
  const errors = []
  t.mock.method(console, 'error', value => errors.push(value))
  assert.equal(runWindowsTests(), 1)
  assert.match(errors[0], /SDK missing/)
  cp.spawnSync = () => ({ status: 8 }); syncBuiltinESMExports()
  assert.equal(runWindowsTests(), 8)
})

test('iOS build orchestration uses isolated projects and propagates SDK, simulator and compiler failures', async t => {
  const root = directory(t)
  mkdirSync(join(root, 'Scripts')); mkdirSync(join(root, 'config'))
  for (const name of ['ios-build.mjs', 'build-cache.mjs', 'ios-project.mjs', 'app-config.mjs', 'release-lib.mjs', 'app-version.mjs']) copyFileSync(new URL('./' + name, import.meta.url), join(root, 'Scripts', name))
  // ios-about.mjs imports weapp core modules outside Scripts/, so the sandbox stubs it.
  writeFileSync(join(root, 'Scripts/ios-about.mjs'), 'export function writeIOSAbout(directory, targetPath) { return targetPath }\n')
  copyFileSync(new URL('../config/app.json', import.meta.url), join(root, 'config/app.json'))
  const { runIOSBuild } = await import(pathToFileURL(join(root, 'Scripts/ios-build.mjs')).href)
  let mode = 'sdk', builds = [], simulator = 0, processCalls = 0
  const uuid = '00000000-0000-0000-0000-000000000001', phone = '00000000-0000-0000-0000-000000000002'
  processMock(t, (command, args) => {
    processCalls++
    if (args.includes('--show-sdk-path')) return { status: mode === 'sdk' ? 1 : 0 }
    if (args.includes('simctl')) {
      simulator++
      return { status: mode === 'simulator' ? 1 : 0, stdout: JSON.stringify({ devices: { 'iOS-26-0': [{ name: 'iPad Pro', isAvailable: true, udid: uuid }, { name: 'iPhone', isAvailable: true, udid: phone }] } }) }
    }
    assert.equal(command, 'xcodebuild')
    builds.push(args)
    return mode === 'error' ? { error: Error('compiler unavailable') } : { status: mode === 'failed' ? 5 : mode === 'no-status' ? null : 0 }
  })
  const configFile = join(root, 'config/app.json')
  const config = JSON.parse(readFileSync(configFile, 'utf8'))
  for (const releaseIOS of [false, undefined]) {
    writeFileSync(configFile, JSON.stringify({ ...config, releaseIOS }))
    assert.throws(() => runIOSBuild('archive', { APPLE_TEAM_ID: 'ABCDEFGHIJ' }), /iPhone\/iPad release is disabled/)
    assert.equal(processCalls, 0, 'A disabled release must stop before any SDK, signing or archive command')
  }
  writeFileSync(configFile, JSON.stringify({ ...config, releaseIOS: false }))
  assert.throws(() => runIOSBuild(), /Full Xcode/)
  mode = 'simulator'; assert.throws(() => runIOSBuild('check', {}), /simulators/)
  mode = 'error'; assert.throws(() => runIOSBuild('build', {}), /compiler unavailable/)
  mode = 'failed'; assert.equal(runIOSBuild('build', {}), 5)
  mode = 'no-status'; assert.equal(runIOSBuild('build', {}), 1)
  mode = 'ok'; builds = []
  assert.equal(runIOSBuild('check', { IPAD_BUILD_NUMBER: '2' }), 0)
  assert.equal(builds.length, 4)
  assert.equal(runIOSBuild('test', { IOS_BUILD_NUMBER: '3' }, 'iPad'), 0)
  assert.equal(runIOSBuild('test', {}, 'iPhone'), 0)
  writeFileSync(configFile, JSON.stringify({ ...config, releaseIOS: true }))
  assert.equal(runIOSBuild('archive', { APPLE_TEAM_ID: 'ABCDEFGHIJ' }), 0)
  assert.ok(simulator >= 4)
})

test('iOS CLI holds its managed cache lease through SDK builds and simulator checks', t => {
  const root = directory(t)
  mkdirSync(join(root, 'Scripts')); mkdirSync(join(root, 'config'))
  for (const name of ['ios-build.mjs', 'build-cache.mjs', 'ios-project.mjs', 'app-config.mjs', 'release-lib.mjs', 'app-version.mjs']) copyFileSync(new URL('./' + name, import.meta.url), join(root, 'Scripts', name))
  writeFileSync(join(root, 'Scripts/ios-about.mjs'), 'export function writeIOSAbout(directory, targetPath) { return targetPath }\n')
  copyFileSync(new URL('../config/app.json', import.meta.url), join(root, 'config/app.json'))
  const preload = join(root, 'managed-ios.cjs')
  writeFileSync(preload, `
const cp=require('node:child_process'), fs=require('node:fs'), path=require('node:path');
cp.spawnSync=(command,args)=>{
  if(command==='ps')return {status:0,stdout:'Sat Oct 17 10:00:00 2026'};
  if(args.includes('simctl'))return {status:0,stdout:JSON.stringify({devices:{'iOS-26-0':[
    {name:'iPad',isAvailable:true,udid:'00000000-0000-0000-0000-000000000001'},
    {name:'iPhone',isAvailable:true,udid:'00000000-0000-0000-0000-000000000002'}]}})};
  if(command==='xcodebuild'){
    const owner=JSON.parse(fs.readFileSync(path.join(process.env.UNIT_ROOT,'work/build-cache/native.lock')));
    if(!owner.paths.includes('work/ios-build/Build'))throw Error('Missing build-cache lease');
  }
  return {status:0};
};require('node:module').syncBuiltinESMExports();`)
  for (const args of [[], ['build'], ['test', 'iPhone']]) {
    const result = cp.spawnSync(process.execPath, ['--require', preload, join(root, 'Scripts/ios-build.mjs'), ...args], {
      cwd: root, encoding: 'utf8', env: { ...process.env, UNIT_ROOT: root },
    })
    assert.equal(result.status, 0, result.stderr)
    assert.equal(existsSync(join(root, 'work/build-cache/native.lock')), false)
    assert.ok(JSON.parse(readFileSync(join(root, 'work/build-cache/registry.json'))).entries.some(entry => entry.path === 'work/ios-build/Build'))
  }
})

test('simulator selection rejects missing runtimes, unavailable names and missing destination IDs', () => import('./ios-build.mjs').then(({ iosSimulator, iosBuildPlan }) => {
  for (const devices of [{}, { devices: { 'unrelated-runtime': [] } }, { devices: { 'iOS-16': [] } }]) assert.throws(() => iosSimulator(devices), /Install an available/)
  assert.throws(() => iosSimulator({}, 'invalid'), /Unsupported simulator/)
  assert.throws(() => iosBuildPlan('test', { family: 'invalid' }), /Unsupported simulator/)
  assert.throws(() => iosBuildPlan('test', { family: 'iPad' }), /Valid iPad/)
}))

test('proxy discovery does not invoke macOS tools on another platform', t => {
  const descriptor = Object.getOwnPropertyDescriptor(process, 'platform')
  Object.defineProperty(process, 'platform', { value: 'win32' })
  t.after(() => Object.defineProperty(process, 'platform', descriptor))
  processMock(t, () => { throw Error('must not spawn') })
  assert.equal(gitProxyValue({}), '')
})


test('entry points honor empty policy inputs and bundled Windows SDK selection', t => {
  const root = directory(t)
  mkdirSync(join(root, 'Scripts'))
  for (const name of ['windows-tests.mjs', 'dev-update-deps.mjs', 'node-executable.mjs']) copyFileSync(new URL('./' + name, import.meta.url), join(root, 'Scripts', name))
  writeFileSync(join(root, 'Scripts/test.mjs'), `export const testRoot=${JSON.stringify(root)}`)
  writeFileSync(join(root, 'Scripts/calmmit.mjs'), `export const ci={root:${JSON.stringify(root)},load:async()=>({runCiProcess:()=>({status:0}),updateNativeDependencies:()=>0}),run:args=>{if(args.join()!=='update-deps')throw Error('unexpected shared command')}}`)
  writeFileSync(join(root, 'hook.cjs'), `const cp=require('node:child_process'),fs=require('node:fs');Object.defineProperty(process,'platform',{value:process.env.UNIT_PLATFORM});cp.spawnSync=()=>({status:0});fs.existsSync=()=>process.env.UNIT_BUNDLED==='1';require('node:module').syncBuiltinESMExports();`)
  for (const platform of ['darwin','win32']) for (const bundled of ['0','1']) {
    const result = cp.spawnSync(process.execPath, ['--require', join(root, 'hook.cjs'), join(root, 'Scripts/windows-tests.mjs')], {encoding:'utf8',env:{...process.env,UNIT_PLATFORM:platform,UNIT_BUNDLED:bundled,BENCHGAUGE_DOTNET:''}})
    assert.equal(result.status,0,result.stderr)
  }
  assert.equal(cp.spawnSync(process.execPath, ['--require', join(root,'hook.cjs'),join(root,'Scripts/dev-update-deps.mjs')], {encoding:'utf8',env:{...process.env,UNIT_PLATFORM:'linux'}}).status,0)
})

test('visual policy refuses missing repository or missing authentication before making any request', async () => {
  const { checkVisualReviewPolicy } = await import('./visual-review-policy.mjs')
  const request = () => { throw Error('A request must not be sent') }
  await assert.rejects(checkVisualReviewPolicy({env:{},request}), /required/)
  await assert.rejects(checkVisualReviewPolicy({env:{GITHUB_REPOSITORY:'fixture/repo'},request}), /required/)
})


test('a selected simulator family may omit the other family entirely', async () => {
  const {iosBuildPlan}=await import('./ios-build.mjs')
  assert.throws(()=>iosBuildPlan('invalid'),/Usage/)
  const plans=iosBuildPlan('test',{family:'iPad',device:'11111111-1111-1111-1111-111111111111'})
  assert.equal(plans.length,1)
})
