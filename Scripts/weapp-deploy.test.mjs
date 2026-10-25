import assert from 'node:assert/strict'
import test from 'node:test'
import { mkdtempSync, mkdirSync, writeFileSync, rmSync, readFileSync, existsSync, copyFileSync, cpSync, symlinkSync, realpathSync } from 'node:fs'
import { spawnSync, spawn } from 'node:child_process'
import cp from 'node:child_process'
import { EventEmitter } from 'node:events'
import { createRequire, syncBuiltinESMExports } from 'node:module'
import { pathToFileURL } from 'node:url'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { ci } from './calmmit.mjs'
import { sourcePaths, inputSnapshot, sourceSignature, stageInputs, needsUpload, readReceipt } from './weapp-deploy.mjs'

test('isolated upload retains the calendar fixture and resolves the shared version generator outside its checkout', t => {
  const root = mkdtempSync(join(tmpdir(), 'benchgauge-version-stage-'))
  t.after(() => rmSync(root, { recursive: true, force: true }))
  const inputs = ['Tests/fixtures/calendar-timestamps.json', 'Scripts/calmmit.mjs', 'calmmit.config.json', 'apps/weapp/scripts/version.mjs']
  for (const relative of [...inputs, 'node_modules/.fixture', 'apps/weapp/node_modules/.fixture']) {
    const target = join(root, relative)
    mkdirSync(join(target, '..'), { recursive: true })
    if (inputs.includes(relative)) copyFileSync(new URL(`../${relative}`, import.meta.url), target)
    else writeFileSync(target, '')
  }
  const snapshot = inputSnapshot(root), signature = sourceSignature(snapshot)
  const stage = join(root, 'stage')
  stageInputs(root, stage, snapshot)
  assert.deepEqual(JSON.parse(readFileSync(join(stage, inputs[0]), 'utf8')), JSON.parse(readFileSync(join(root, inputs[0]), 'utf8')))
  const result = spawnSync(process.execPath, ['--input-type=module', '--eval', `
    import { createAutoVersion } from ${JSON.stringify(pathToFileURL(join(stage, inputs[3])).href)};
    console.log(createAutoVersion(new Date('2026-10-24T16:00:00Z')));
  `], { cwd: stage, env: { ...process.env, CALMMIT_PATH: ci.library }, encoding: 'utf8' })
  assert.equal(result.status, 0, result.stdout + result.stderr)
  assert.equal(result.stdout.trim(), '20261025')
  for (const relative of inputs) {
    const original = readFileSync(join(root, relative))
    writeFileSync(join(root, relative), Buffer.concat([original, Buffer.from('\n')]))
    assert.notEqual(sourceSignature(inputSnapshot(root)), signature, relative)
    writeFileSync(join(root, relative), original)
  }
})

test('isolated upload loads shared domain and chart statistics and detects their updates', async t => {
  const root = mkdtempSync(join(tmpdir(), 'benchgauge-domain-stage-'))
  t.after(() => rmSync(root, { recursive: true, force: true }))
  for (const path of ['fc', 'node_modules', 'apps/weapp/node_modules']) mkdirSync(join(root, path), { recursive: true })
  writeFileSync(join(root, 'apps/weapp/package.json'), '{}')
  for (const relative of sourcePaths.filter(path => path.startsWith('fc/'))) {
    copyFileSync(new URL(`../${relative}`, import.meta.url), join(root, relative))
  }
  const files = inputSnapshot(root), signature = sourceSignature(files)
  const stage = join(root, 'stage')
  stageInputs(root, stage, files)
  const domain = await import(pathToFileURL(join(stage, 'fc/domain.mjs')).href)
  assert.equal(domain.countryCode({ name: 'Qwen', organization: 'Alibaba' }), 'CN')
  assert.equal(domain.normalizedCountryCode('HK'), 'CN')
  const { leaderboardDistribution } = await import(pathToFileURL(join(stage, 'fc/distributions.mjs')).href)
  const distribution = leaderboardDistribution([{ name: 'Qwen', organization: 'Alibaba', openness: 'open' }])
  assert.equal(distribution.total, 1)
  assert.equal(distribution.countries[0].id, 'CN')
  const statistics = join(root, 'fc/distributions.mjs')
  const originalStatistics = readFileSync(statistics, 'utf8')
  writeFileSync(statistics, originalStatistics + '\n')
  assert.notEqual(sourceSignature(inputSnapshot(root)), signature)
  writeFileSync(statistics, originalStatistics)
  const catalog = join(root, 'fc/country-catalog.json')
  writeFileSync(catalog, readFileSync(catalog, 'utf8') + '\n')
  assert.notEqual(sourceSignature(inputSnapshot(root)), signature)
  const config = JSON.parse(readFileSync(new URL('../calmmit.config.json', import.meta.url)))
  assert.deepEqual(new Set(config.dev.activity.find(item => item.kind === 'mini-program').sources), new Set(sourcePaths))
})

test('isolated upload renders canonical source marks and tracks scripts, artwork and notices', async t => {
  const root = mkdtempSync(join(tmpdir(), 'benchgauge-source-marks-stage-'))
  t.after(() => rmSync(root, { recursive: true, force: true }))
  for (const path of ['Scripts', 'assets/brand', 'node_modules', 'apps/weapp/node_modules']) mkdirSync(join(root, path), { recursive: true })
  writeFileSync(join(root, 'apps/weapp/package.json'), '{}')
  copyFileSync(new URL('./source-logos.mjs', import.meta.url), join(root, 'Scripts/source-logos.mjs'))
  cpSync(new URL('../assets/brand/partners', import.meta.url), join(root, 'assets/brand/partners'), { recursive: true })
  const snapshot = inputSnapshot(root), signature = sourceSignature(snapshot)
  const stage = join(root, 'stage')
  stageInputs(root, stage, snapshot)
  const { renderSourceLogos } = await import(pathToFileURL(join(stage, 'Scripts/source-logos.mjs')).href)
  const sharp = createRequire(new URL('../apps/weapp/package.json', import.meta.url))('sharp')
  const assets = await renderSourceLogos(sharp)
  const catalog = JSON.parse(readFileSync(join(root, 'assets/brand/partners/sources.json'), 'utf8'))
  assert.equal(assets.length, catalog.sources.length * 2 + 1)
  for (const asset of assets.filter(item => item.name.endsWith('.png'))) {
    const metadata = await sharp(asset.source).metadata()
    assert.equal(metadata.width, 84)
    assert.equal(metadata.height, 84)
  }
  assert.deepEqual(assets.find(item => item.name === 'NOTICE.txt').source, readFileSync(join(root, 'assets/brand/partners/NOTICE.txt')))
  for (const relative of ['Scripts/source-logos.mjs', ...snapshot.keys()].filter((path, index, paths) => paths.indexOf(path) === index)) {
    const original = readFileSync(join(root, relative))
    writeFileSync(join(root, relative), Buffer.concat([original, Buffer.from('\n')]))
    assert.notEqual(sourceSignature(inputSnapshot(root)), signature, `${relative} edits must queue a new upload`)
    writeFileSync(join(root, relative), original)
  }
})

test('upload snapshot detects edits and deletions but excludes credentials and generated files', t => {
  const root = mkdtempSync(join(tmpdir(), 'benchgauge-upload-'))
  t.after(() => rmSync(root, { recursive: true, force: true }))
  mkdirSync(join(root, 'src/dist'), { recursive: true })
  mkdirSync(join(root, 'src/node_modules'), { recursive: true })
  for (const name of ['page.js', 'private.test.key', 'token.pem', '.local', 'dist/app.js', 'node_modules/package.json']) writeFileSync(join(root, 'src', name), 'first')
  const snapshot = inputSnapshot(root, ['src'])
  assert.deepEqual([...snapshot.keys()], ['src/page.js'])
  const first = sourceSignature(snapshot)
  writeFileSync(join(root, 'src/private.test.key'), 'secret rotation')
  assert.equal(sourceSignature(inputSnapshot(root, ['src'])), first)
  writeFileSync(join(root, 'src/page.js'), 'other')
  assert.notEqual(sourceSignature(inputSnapshot(root, ['src'])), first)
  rmSync(join(root, 'src/page.js'))
  assert.notEqual(sourceSignature(inputSnapshot(root, ['src'])), first)
})

test('isolated upload includes every shared category icon and its license, and detects asset changes', t => {
  const root = mkdtempSync(join(tmpdir(), 'benchgauge-category-stage-'))
  t.after(() => rmSync(root, { recursive: true, force: true }))
  const directory = 'apps/ios/UI/Resources/CategoryIcons'
  for (const path of [directory, 'node_modules', 'apps/weapp/node_modules']) mkdirSync(join(root, path), { recursive: true })
  writeFileSync(join(root, 'apps/weapp/package.json'), '{}')
  const names = ['general.png', 'coding.png', 'image.png', 'video.png', 'usage.png', 'LICENSE.txt']
  for (const name of names) copyFileSync(new URL(`../${directory}/${name}`, import.meta.url), join(root, directory, name))
  const snapshot = inputSnapshot(root)
  const signature = sourceSignature(snapshot)
  const stage = join(root, 'stage')
  stageInputs(root, stage, snapshot)
  assert.equal(sourceSignature(inputSnapshot(stage)), signature)
  for (const name of names) {
    const relative = `${directory}/${name}`
    const original = readFileSync(join(root, relative))
    assert.deepEqual(readFileSync(join(stage, relative)), original)
    writeFileSync(join(root, relative), 'updated asset')
    assert.notEqual(sourceSignature(inputSnapshot(root)), signature, `${name} edits must queue a new upload`)
    rmSync(join(root, relative))
    assert.notEqual(sourceSignature(inputSnapshot(root)), signature, `${name} deletions must invalidate the upload`)
    writeFileSync(join(root, relative), original)
  }
})

test('isolated build stage preserves source bytes and never includes private keys or live dist', t => {
  const root = mkdtempSync(join(tmpdir(), 'benchgauge-stage-'))
  t.after(() => rmSync(root, { recursive: true, force: true }))
  mkdirSync(join(root, 'apps/weapp/node_modules'), { recursive: true })
  mkdirSync(join(root, 'node_modules'))
  mkdirSync(join(root, 'apps/weapp/src'))
  writeFileSync(join(root, 'apps/weapp/src/page.js'), 'original')
  writeFileSync(join(root, 'apps/weapp/private.test.key'), 'private')
  const license = 'Sources/LeaderboardKit/Resources/Fonts/SlideFont-OFL.txt'
  mkdirSync(join(root, 'Sources/LeaderboardKit/Resources/Fonts'), { recursive: true })
  writeFileSync(join(root, license), 'font license')
  const files = inputSnapshot(root)
  const signature = sourceSignature(files)
  const stage = join(root, 'stage')
  stageInputs(root, stage, files)
  assert.equal(readFileSync(join(stage, license), 'utf8'), 'font license')
  writeFileSync(join(root, license), 'updated font license')
  assert.notEqual(sourceSignature(inputSnapshot(root)), signature)
  assert.equal(readFileSync(join(stage, license), 'utf8'), 'font license')
  writeFileSync(join(root, 'apps/weapp/src/page.js'), 'edited during build')
  assert.equal(readFileSync(join(stage, 'apps/weapp/src/page.js'), 'utf8'), 'original')
  assert.equal(existsSync(join(stage, 'apps/weapp/private.test.key')), false)
  assert.equal(existsSync(join(stage, 'apps/weapp/dist')), false)
})

test('only successful upload receipts suppress repeats; new source and rotated credentials queue uploads', t => {
  const root = mkdtempSync(join(tmpdir(), 'benchgauge-receipt-'))
  t.after(() => rmSync(root, { recursive: true, force: true }))
  const path = join(root, 'receipt')
  assert.equal(readReceipt(path), null)
  const ready = { ready: true, keyChangedAt: 50 }
  assert.equal(needsUpload(null, 'source', ready), true)
  const receipt = { schemaVersion: 1, status: 'success', publishedAt: 100, sourceSignature: 'source' }
  writeFileSync(path, JSON.stringify(receipt))
  assert.deepEqual(readReceipt(path), receipt)
  assert.equal(needsUpload(receipt, 'source', ready), false)
  assert.equal(needsUpload(receipt, 'new', ready), true)
  assert.equal(needsUpload(receipt, 'source', { ready: true, keyChangedAt: 150 }), true)
  assert.equal(needsUpload(null, 'new', { ready: false }), false)
  writeFileSync(path, JSON.stringify({ ...receipt, status: 'failed' }))
  assert.equal(readReceipt(path), null)
  writeFileSync(path, '{bad')
  assert.equal(readReceipt(path), null)
})

function isolatedUploader(t, mode = 'success') {
  const root = realpathSync(mkdtempSync(join(tmpdir(), 'benchgauge-upload-behavior-')))
  t.after(() => rmSync(root, { recursive: true, force: true }))
  for (const path of ['Scripts', 'bin', 'node_modules', 'apps/weapp/node_modules', 'apps/weapp/src', 'apps/weapp/scripts', 'apps/weapp/ci-runtime']) mkdirSync(join(root, path), { recursive: true })
  writeFileSync(join(root, 'package.json'), '{"type":"module"}')
  copyFileSync(new URL('./weapp-deploy.mjs', import.meta.url), join(root, 'Scripts/weapp-deploy.mjs'))
  copyFileSync(new URL('../apps/weapp/scripts/version.mjs', import.meta.url), join(root, 'apps/weapp/scripts/version.mjs'))
  writeFileSync(join(root, 'apps/weapp/ci-runtime/package-lock.json'), JSON.stringify({ packages: Object.fromEntries(['node', 'miniprogram-ci', 'form-data'].map(name => [`node_modules/${name}`, { version: 'fixture' }])) }))
  writeFileSync(join(root, 'apps/weapp/src/page.js'), 'initial')
  writeFileSync(join(root, 'privacy-guide.json'), '{"items":[]}')
  writeFileSync(join(root, 'Scripts/node-executable.mjs'), 'export const nodeExecutable=()=>process.execPath')
  writeFileSync(join(root, 'Scripts/commit-lock.mjs'), `export const state={acquired:true,released:0};export function acquireCommitLock(){return{acquired:state.acquired && process.env.UPLOAD_MODE!=='busy',release(){state.released++}}}`)
  writeFileSync(join(root, 'Scripts/calmmit.mjs'), `
export const state={ready:true,polls:0,scheduled:[],stops:0,session:null,configCalls:0};
const config=()=>{const n=++state.configCalls,mode=process.env.UPLOAD_MODE;return{ready:state.ready&&mode!=='not-ready'&&!(mode==='config-unready'&&n===2),reason:'fixture credentials unavailable',signature:(mode==='config-rotation'&&n>=2||mode==='late-config'&&n>=3)?'rotated':'first',keyChangedAt:0,appid:'fixture-appid',privateKeyPath:'fixture-private-key'}};
export const ci={root:${JSON.stringify(root)},load:async name=>['privacy-guide','wechat-ci'].includes(name)?import(${JSON.stringify(pathToFileURL(join(ci.library, 'src/')).href)}+name+'.mjs'):name==='deployment-credentials'?{readUploadConfig:config,createUploadConfigMonitor:options=>({initial:options.readConfig(),poll(){state.polls++;if(state.pollError)throw Error('fixture monitor');options.readConfig()}})}:{createWatchSession:options=>{state.session=options;return{schedule:(...args)=>state.scheduled.push(args),stop(){state.stops++}}}}};
`)
  const installRuntime = () => {
    mkdirSync(join(root, 'apps/weapp/ci-runtime/node_modules/node/bin'), { recursive: true })
    mkdirSync(join(root, 'apps/weapp/ci-runtime/node_modules/miniprogram-ci'), { recursive: true })
    symlinkSync(process.execPath, join(root, 'apps/weapp/ci-runtime/node_modules/node/bin/node'))
    symlinkSync(process.execPath, join(root, 'apps/weapp/ci-runtime/node_modules/node/bin/node.exe'))
    for (const name of ['node', 'miniprogram-ci', 'form-data']) { mkdirSync(join(root, 'apps/weapp/ci-runtime/node_modules', name), { recursive: true }); writeFileSync(join(root, 'apps/weapp/ci-runtime/node_modules', name, 'package.json'), JSON.stringify({ version: 'fixture' })) }
  }
  if (!['runtime-install', 'late-config', 'late-source', 'windows'].includes(mode)) installRuntime()
  const npm = `#!${process.execPath}
import fs from 'node:fs';import path from 'node:path';const args=process.argv.slice(2),root=process.cwd(),mode=process.env.UPLOAD_MODE;
fs.appendFileSync('events',JSON.stringify(args)+'\\n');
if(args.includes('build'))fs.writeFileSync('build-version',process.env.MP_VERSION||'');
if(mode==='build-failed'&&args.includes('build'))process.exit(2);
if(args.includes('build')&&mode==='build-source')fs.writeFileSync('apps/weapp/src/page.js','changed');
if(args.includes('ci')){const runtime=args[args.indexOf('--prefix')+1];fs.mkdirSync(path.join(runtime,'node_modules/node/bin'),{recursive:true});fs.mkdirSync(path.join(runtime,'node_modules/miniprogram-ci'),{recursive:true});for(const n of ['node','node.exe'])fs.symlinkSync(process.execPath,path.join(runtime,'node_modules/node/bin',n));for(const name of ['node','miniprogram-ci','form-data']){fs.mkdirSync(path.join(runtime,'node_modules',name),{recursive:true});fs.writeFileSync(path.join(runtime,'node_modules',name,'package.json'),JSON.stringify({version:'fixture'}))};if(mode==='late-source')fs.writeFileSync('apps/weapp/src/page.js','late change')}
`
  writeFileSync(join(root, 'bin/npm'), npm, { mode: 0o755 })
  symlinkSync(join(root,'bin/npm'),join(root,'bin/npm.cmd'))
  writeFileSync(join(root, 'apps/weapp/scripts/upload.mjs'), `import{appendFileSync}from'node:fs';appendFileSync('events',JSON.stringify(['upload',...process.argv.slice(2)])+'\n');if(process.env.UPLOAD_MODE==='upload-failed')process.exit(3)` .replace("+'\n'", "+'\\n'"))
  const hook = join(root, 'hook.cjs')
  writeFileSync(hook, `
const fs=require('node:fs'),cp=require('node:child_process');
if(process.env.UPLOAD_MODE==='copy-source'){const copy=fs.copyFileSync;fs.copyFileSync=(from,to,...args)=>{copy(from,to,...args);if(from.endsWith('page.js'))fs.writeFileSync(to,'changed during copy')}}
if(process.env.UPLOAD_MODE==='spawn-error'){cp.spawn=()=>{const c=new(require('node:events').EventEmitter);queueMicrotask(()=>c.emit('error',Error('fixture spawn error')));return c}}
require('node:module').syncBuiltinESMExports();
`)
  let platformPreload = ''
  if (mode === 'windows') {
    // Load native dependencies for the real host before simulating Windows paths.
    const platformHook = join(root, 'windows-platform.mjs')
    writeFileSync(platformHook, `await import(${JSON.stringify(pathToFileURL(join(ci.library, 'src/privacy-guide.mjs')).href)});\nObject.defineProperty(process,'platform',{value:'win32'});\n`)
    platformPreload = ` --import=${pathToFileURL(platformHook).href}`
  }
  const env = { ...process.env, PATH: join(root, 'bin') + ':' + process.env.PATH, UPLOAD_MODE: mode, MP_VERSION: 'fixture-v1', NODE_OPTIONS: `${process.env.NODE_OPTIONS || ''} --require=${hook}${platformPreload}`.trim() }
  if (mode === 'default-version') delete env.MP_VERSION
  return { root, env, script: join(root, 'Scripts/weapp-deploy.mjs') }
}

test('actual uploader rejects stale inputs, failed builds, changed credentials and failed uploads without success receipts', t => {
  for (const [mode, reason] of [['not-ready','credentials unavailable'],['busy','已有小程序'],['copy-source','复制期间'],['build-source','构建期间'],['config-unready','上传配置或密钥'],['config-rotation','上传配置或密钥'],['late-config','源码或上传配置'],['late-source','源码或上传配置'],['build-failed','退出码 2'],['upload-failed','退出码 3'],['spawn-error','fixture spawn error']]) {
    const f = isolatedUploader(t, mode)
    const result = spawnSync(process.execPath, [f.script, 'upload'], { cwd: f.root, env: f.env, encoding: 'utf8', timeout: 10_000 })
    assert.equal(result.status, 1, mode + ': ' + result.stdout + result.stderr)
    assert.match(result.stderr, new RegExp(reason), mode)
    assert.equal(existsSync(join(f.root, 'apps/weapp/.last-publish')), false, mode)
    assert.equal(existsSync(join(f.root, `work/weapp-deploy/stage-${result.pid}`)), false, mode)
  }
})

test('successful uploader installs its isolated runtime when needed and writes a source-bound receipt only after upload', t => {
  for (const mode of ['success', 'runtime-install', 'default-version', 'windows']) {
    const f = isolatedUploader(t, mode)
    const result = spawnSync(process.execPath, [f.script, 'upload'], { cwd: f.root, env: f.env, encoding: 'utf8', timeout: 10_000 })
    assert.equal(result.status, 0, mode + ': ' + result.stdout + result.stderr)
    const receipt = readReceipt(join(f.root, 'apps/weapp/.last-publish'))
    assert.equal(receipt.sourceSignature, sourceSignature(inputSnapshot(f.root)))
    assert.equal(receipt.version, mode === 'default-version' ? new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Shanghai', year:'numeric',month:'2-digit',day:'2-digit' }).format(new Date()).replaceAll('-','') : 'fixture-v1')
    assert.equal(readFileSync(join(f.root, 'build-version'), 'utf8'), receipt.version)
    const events = readFileSync(join(f.root, 'events'), 'utf8').trim().split('\n').map(JSON.parse)
    assert.equal(events.at(-1)[0], 'upload')
    assert.equal(events.at(-1).at(-1), receipt.version)
    assert.deepEqual(events.at(-1).slice(2,4), ['fixture-appid', 'fixture-private-key'])
    assert.equal(existsSync(join(f.root, 'apps/weapp/.last-publish.tmp')), false)
    assert.equal(existsSync(join(f.root, `work/weapp-deploy/stage-${result.pid}`)), false)
  }
})

test('isolated uploader disables Web Storage before loading the compiler and in compiler subprocesses', t => {
  const f = isolatedUploader(t)
  f.env.NODE_OPTIONS += ' --experimental-webstorage'
  writeFileSync(join(f.root, 'apps/weapp/scripts/upload.mjs'), `
import assert from 'node:assert/strict'
import { execFileSync } from 'node:child_process'
import { Worker } from 'node:worker_threads'
assert.equal(globalThis.localStorage, undefined)
assert.ok(process.env.NODE_OPTIONS.includes('ci-compat.cjs'))
const check = 'require("node:assert/strict").equal(globalThis.localStorage, undefined)'
execFileSync(process.execPath, ['--eval', check])
await new Promise((resolve, reject) => {
  const worker = new Worker(check, { eval: true })
  worker.once('error', reject)
  worker.once('exit', code => code === 0 ? resolve() : reject(new Error('worker exit ' + code)))
})
`)
  const result = spawnSync(process.execPath, [f.script, 'upload'], { cwd: f.root, env: f.env, encoding: 'utf8', timeout: 10_000 })
  assert.equal(result.status, 0, result.stdout + result.stderr)
  assert.ok(readReceipt(join(f.root, 'apps/weapp/.last-publish')))
})

test('privacy failures stop only the isolated upload before build/network and guide edits change its signature', t => {
  const f = isolatedUploader(t)
  writeFileSync(join(f.root, 'apps/weapp/src/page.js'), 'wx.getLocation({})')
  const before = sourceSignature(inputSnapshot(f.root))
  const run = () => spawnSync(process.execPath, [f.script, 'upload'], { cwd: f.root, env: f.env, encoding: 'utf8', timeout: 10_000 })
  const failed = run()
  assert.equal(failed.status, 1, failed.stdout + failed.stderr)
  assert.match(failed.stderr, /隐私底稿缺少必要用途/)
  assert.equal(existsSync(join(f.root, 'events')), false)
  assert.equal(existsSync(join(f.root, 'apps/weapp/.last-publish')), false)
  assert.deepEqual(JSON.parse(readFileSync(join(f.root, 'privacy-guide.json'))).items, [])
  writeFileSync(join(f.root, 'privacy-guide.json'), JSON.stringify({ items: [{ item: '位置信息', apis: ['getLocation'], purpose: '定位用途' }] }))
  assert.notEqual(sourceSignature(inputSnapshot(f.root)), before)
  const success = run()
  assert.equal(success.status, 0, success.stdout + success.stderr)
  assert.equal(readReceipt(join(f.root, 'apps/weapp/.last-publish')).sourceSignature, sourceSignature(inputSnapshot(f.root)))
})

test('upload watcher owns its lifetime, only queues new publishable inputs and forwards one completion per child', async t => {
  const f = isolatedUploader(t)
  const control = await import(pathToFileURL(join(f.root, 'Scripts/calmmit.mjs')).href)
  const locks = await import(pathToFileURL(join(f.root, 'Scripts/commit-lock.mjs')).href)
  const uploader = await import(pathToFileURL(f.script).href)
  const previous = { WEAPP_AUTOPUBLISH:process.env.WEAPP_AUTOPUBLISH, BENCHGAUGE_WEAPP_OWNER_PID:process.env.BENCHGAUGE_WEAPP_OWNER_PID, WEAPP_PUBLISH_DEBOUNCE_MS:process.env.WEAPP_PUBLISH_DEBOUNCE_MS }
  const restore = () => { for(const [key,value]of Object.entries(previous))if(value===undefined)delete process.env[key];else process.env[key]=value }
  t.after(() => { restore();t.mock.restoreAll();syncBuiltinESMExports() })
  const messages=[];t.mock.method(console,'log',value=>messages.push(value))
  process.env.WEAPP_AUTOPUBLISH='0';(await uploader.startWeappUploadWatch())()
  delete process.env.WEAPP_AUTOPUBLISH
  locks.state.acquired=false;(await uploader.startWeappUploadWatch())();locks.state.acquired=true
  let tick;const cleared=[]
  t.mock.method(globalThis,'setInterval',fn=>{tick=fn;return 42});t.mock.method(globalThis,'clearInterval',id=>cleared.push(id))
  const stop=await uploader.startWeappUploadWatch()
  t.after(()=>{stop();process.removeListener('exit',stop)})
  assert.equal(control.state.scheduled.length,1)
  tick();assert.equal(control.state.scheduled.length,1)
  writeFileSync(join(f.root,'apps/weapp/src/page.js'),'updated');tick();assert.equal(control.state.scheduled.length,2)
  control.state.ready=false;writeFileSync(join(f.root,'apps/weapp/src/page.js'),'unready');tick();assert.equal(control.state.scheduled.length,2)
  control.state.pollError=true;tick();assert.ok(messages.some(value=>value.includes('监听检查失败')));control.state.pollError=false
  process.env.BENCHGAUGE_WEAPP_OWNER_PID='12345';t.mock.method(process,'kill',()=>{throw Object.assign(Error('denied'),{code:'EPERM'})});tick()
  process.kill=()=>{throw Object.assign(Error('missing'),{code:'ESRCH'})};tick();assert.ok(cleared.includes(42));assert.ok(control.state.stops>0)
  const options=control.state.session
  assert.equal(options.uploadConfig().ready,false)
  assert.equal(options.classifyFailure('已有小程序构建'), 'retry');assert.equal(options.classifyFailure('broken'),'pause');assert.equal(options.classifyFailure(undefined),'pause')
  options.log('提交已完成，开始完整构建并发布');assert.ok(messages.some(value=>value.includes('开始小程序检查')))
  const child=new EventEmitter();child.stdout=new EventEmitter();child.stderr=new EventEmitter()
  t.mock.method(cp,'spawn',()=>child);syncBuiltinESMExports()
  const done=[];options.startPublish((...args)=>done.push(args),{env:{}})
  const write=process.stdout.write;process.stdout.write=()=>true
  try{child.stdout.emit('data',Buffer.from('fixture stdout'));child.stderr.emit('data',Buffer.from('fixture stderr'))}finally{process.stdout.write=write}
  child.emit('close',2);child.emit('error',Error('late failure'));assert.equal(done.length,1);assert.match(done[0][2].output,/fixture stdoutfixture stderr/)
  const failed=[];options.startPublish((...args)=>failed.push(args),{env:{}});child.emit('error',Error('spawn failed'));child.emit('close',1);assert.equal(failed.length,1)
  restore();control.state.ready=false;const idle=await uploader.startWeappUploadWatch();idle();process.removeListener('exit',idle)
  assert.ok(locks.state.released>0)
})

test('CLI usage failures exit without attempting a publish', t => {
  const f=isolatedUploader(t)
  const result=spawnSync(process.execPath,[f.script,'wrong'],{cwd:f.root,env:f.env,encoding:'utf8',timeout:5000})
  assert.equal(result.status,1);assert.match(result.stderr,/用法/);assert.equal(existsSync(join(f.root,'events')),false)
})

test('standalone upload watcher handles an explicit stop signal and exits cleanly', async t => {
  const f=isolatedUploader(t)
  const entry = `
    process.argv = [process.execPath, ${JSON.stringify(f.script)}, 'watch'];
    const write = process.stdout.write.bind(process.stdout);
    process.stdout.write = function (chunk, ...args) {
      if (String(chunk).includes('已监听源码')) {
        for (const signal of ['SIGINT', 'SIGTERM']) {
          if (process.listenerCount(signal) === 0) throw Error(signal + ' handler missing at readiness');
        }
      }
      return write(chunk, ...args);
    };
    await import(${JSON.stringify(pathToFileURL(f.script).href)});
  `
  const child=spawn(process.execPath,['--input-type=module','--eval',entry],{cwd:f.root,env:{...f.env,WEAPP_AUTOPUBLISH:'1',BENCHGAUGE_WEAPP_OWNER_PID:String(process.pid)},stdio:['ignore','pipe','pipe']})
  let output='';child.stdout.on('data',data=>{output+=data;if(output.includes('已监听源码'))child.kill('SIGTERM')});child.stderr.on('data',data=>{output+=data})
  const timer=setTimeout(()=>child.kill('SIGKILL'),5000)
  const code=await new Promise(resolve=>child.once('close',resolve));clearTimeout(timer)
  assert.equal(code,0,output);assert.match(output,/已监听源码/)
})
