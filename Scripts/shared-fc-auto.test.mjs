import test from 'node:test'
import assert from 'node:assert/strict'
import { mkdtempSync, mkdirSync, realpathSync, rmSync, writeFileSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { tmpdir } from 'node:os'
import { classifySharedFcFailure, configSignature, gateTests, readReceipt, sameConfig, sameStamp, sourceSignature, startSharedFcWatch } from './shared-fc-auto.mjs'
import { runtimeFiles } from './deploy-shared-leaderboards.mjs'

function fixture(t) {
  const root = realpathSync(mkdtempSync(join(tmpdir(), 'benchgauge-fc-auto-')))
  t.after(() => rmSync(root, { recursive: true, force: true }))
  for (const name of [...runtimeFiles.map(name => `fc/${name}`), ...gateTests]) {
    const path = join(root, name)
    mkdirSync(dirname(path), { recursive: true })
    writeFileSync(path, name)
  }
  return root
}

test('a deploy candidate changes when runtime or gate tests change', t => {
  const root = fixture(t), initial = sourceSignature(root)
  assert.equal(sourceSignature(root), initial)
  writeFileSync(join(root, 'fc/domain.mjs'), 'changed')
  const runtime = sourceSignature(root)
  assert.notEqual(runtime, initial)
  writeFileSync(join(root, gateTests[0]), 'changed test')
  assert.notEqual(sourceSignature(root), runtime)
})

test('configuration signatures detect private credential changes without exposing their values', t => {
  const root = fixture(t)
  writeFileSync(join(root, '.benchgauge-cloud.local.json'), JSON.stringify({ credentialsFile: 'credentials' }))
  writeFileSync(join(root, 'credentials'), 'first-secret')
  const first = configSignature(root)
  assert.match(first, /^[a-f0-9]{64}$/)
  assert.ok(!first.includes('secret'))
  writeFileSync(join(root, 'credentials'), 'second-secret')
  assert.notEqual(configSignature(root), first)
  writeFileSync(join(root, '.benchgauge-cloud.local.json'), '{}')
  assert.match(configSignature(root), /^[a-f0-9]{64}$/)
})

test('receipts require success and the supported version', t => {
  const root = fixture(t), path = join(root, 'receipt')
  assert.equal(readReceipt(path), null)
  for (const value of [{ version: 2, status: 'success' }, { version: 1, status: 'failed' }]) {
    writeFileSync(path, JSON.stringify(value)); assert.equal(readReceipt(path), null)
  }
  writeFileSync(path, '{'); assert.equal(readReceipt(path), null)
  const receipt = { version: 1, status: 'success', sourceSignature: 'fixture' }
  writeFileSync(path, JSON.stringify(receipt)); assert.deepEqual(readReceipt(path), receipt)
})

test('a changed live code stamp or runtime configuration cannot be overwritten', () => {
  const before = { codeChecksum: 'a', lastModifiedTime: '1', runtime: 'custom.debian10', environmentVariables: { SECRET: 'fixture' } }
  assert.equal(sameStamp(before, { ...before }), true)
  assert.equal(sameStamp(before, { ...before, codeChecksum: 'b' }), false)
  assert.equal(sameStamp(before, { ...before, lastModifiedTime: '2' }), false)
  assert.equal(sameConfig(before, { ...before, codeChecksum: 'b' }), true)
  assert.equal(sameConfig(before, { ...before, runtime: 'nodejs20' }), false)
  assert.equal(sameConfig(before, { ...before, environmentVariables: { SECRET: 'changed' } }), false)
})

test('automatic watcher has an explicit local opt-out', async t => {
  const old = process.env.SHARED_FC_AUTODEPLOY
  t.after(() => old === undefined ? delete process.env.SHARED_FC_AUTODEPLOY : process.env.SHARED_FC_AUTODEPLOY = old)
  process.env.SHARED_FC_AUTODEPLOY = '0'
  const stop = await startSharedFcWatch()
  assert.equal(typeof stop, 'function'); stop()
})

test('only identified download network failures are retried', () => {
  assert.equal(classifySharedFcFailure('线上代码包下载暂时失败：连接中断'), 'retry')
  assert.equal(classifySharedFcFailure('线上代码包下载暂时失败：连接超时'), 'retry')
  assert.equal(classifySharedFcFailure('无法下载线上代码包：HTTP 403'), 'pause')
  assert.equal(classifySharedFcFailure('aborted'), 'pause')
})

test('deployment updates code only after the gate and records success only after both functions and smoke checks', async t => {
  const { copyFileSync, existsSync, readFileSync } = await import('node:fs')
  const { execFile } = await import('node:child_process')
  const spawnResult = (command, args, options) => new Promise(resolve => {
    execFile(command, args, { ...options, maxBuffer: 1024 * 1024 }, (error, stdout, stderr) => resolve({
      status: error ? typeof error.code === 'number' ? error.code : null : 0,
      signal: error?.signal ?? null, error, stdout, stderr,
    }))
  })
  const modes = ['success', 'auto-repair', 'repair-disabled', 'untested-source', 'missing-test-proof', 'cached-proof', 'cached-proof-change', 'uppercase-etag', 'proxy', 'env-credentials', 'idle-deploy', 'busy-during-deploy', 'invalid-cli', 'full-gate-fail', 'test-locked', 'gate-fail', 'source-change', 'collector-fail', 'cloud-change', 'archive-mismatch', 'smoke-fail', 'bad-board', 'bad-upload', 'bad-etag', 'bad-download', 'network-download', 'bad-config', 'no-credentials', 'unrelated-main', 'unrelated-collector', 'bad-collector-token', 'missing-collector-token', 'bad-trigger', 'changed-config', 'deploy-locked']
  let nextMode = 0
  const runModes = async () => {
    while (nextMode < modes.length) {
      const mode = modes[nextMode++]
    const root = fixture(t)
    writeFileSync(join(root, 'fc/package.json'), '{}')
    for (const name of ['deploy-shared-leaderboards.mjs', 'shared-fc-auto.mjs']) copyFileSync(new URL(`./${name}`, import.meta.url), join(root, 'Scripts', name))
    writeFileSync(join(root, 'Scripts/calmmit.mjs'), `import {resolve} from 'node:path';export const ci={root:resolve(import.meta.dirname,'..'),load:async name=>name==='deployment-watch'?{createWatchSession(){}}:{createRepositoryActivity:()=>({snapshot:()=>({blocked:${mode === 'busy-during-deploy'}})})}}`)
    writeFileSync(join(root, 'Scripts/commit-lock.mjs'), `export const acquireCommitLock=()=>({acquired:${mode !== 'deploy-locked'},release(){}})`)
    writeFileSync(join(root, 'Scripts/test-repair.mjs'), `export const runTestGate=async({test,env})=>{if(env.TEST_AUTO_REPAIR!==${mode === 'repair-disabled' ? "'0'" : 'undefined'})throw Error('repair environment changed');return ${mode.startsWith('cached-proof') ? "({status:0,signature:'gate-signature',reused:true,reuseFingerprint:'proof'})" : 'test()'}}`)
    writeFileSync(join(root, 'Scripts/test.mjs'), `import {appendFileSync} from 'node:fs';let revision='gate-signature';export const fullCoverageReuseSignature=()=> '${mode === 'cached-proof-change' ? 'changed' : 'proof'}';export const testInputSignature=()=>revision;export const runTests=async options=>{${['auto-repair', 'untested-source'].includes(mode) ? `appendFileSync(${JSON.stringify(join(root, 'fc/domain.mjs'))},'\\n// repaired source');revision='repaired';` : ''}return {status:options.lockWaitMs===300000?${mode === 'full-gate-fail' ? 1 : mode === 'test-locked' ? 75 : 0}:1,signature:${mode === 'missing-test-proof' ? 'null' : mode === 'untested-source' ? "'gate-signature'" : 'revision'}}}`)
    writeFileSync(join(root, '.benchgauge-cloud.local.json'), JSON.stringify({ region: 'cn-shenzhen', bucket: mode === 'bad-config' ? undefined : 'fixture-bucket', arenaCollector: true, runtimeCredentialsFunction: 'runtime', runtimeIdentityName: 'fixture', ...(mode !== 'env-credentials' && { credentialsFile: 'credentials' }), ...(mode === 'proxy' && { proxy: 'http://proxy.invalid' }) }))
    writeFileSync(join(root, 'credentials'), mode === 'no-credentials' ? '# empty\n' : 'ALIBABA_CLOUD_ACCESS_KEY_ID=id\nALIBABA_CLOUD_ACCESS_KEY_SECRET=secret\n')
    const preload = join(root, 'preload.cjs')
    writeFileSync(preload, `
const fs=require('fs'), path=require('path'), cp=require('child_process');
const mode=${JSON.stringify(mode)},root=${JSON.stringify(root)};
const actual=${JSON.stringify(new URL('./shared-fc-auto.mjs', import.meta.url).href)};
require('node:module').registerHooks({resolve(specifier,context,next){
 if(context.parentURL===actual&&['./calmmit.mjs','./commit-lock.mjs','./deploy-shared-leaderboards.mjs','./test-repair.mjs','./test.mjs'].includes(specifier))
  return {url:require('node:url').pathToFileURL(path.join(root,'Scripts',specifier)).href,shortCircuit:true};
 return next(specifier,context);
}});
global.fixture={mode,root,updates:[],uploaded:null,states:{main:{},collector:{}}};
cp.spawnSync=(cmd,args)=>{
 if(cmd===process.execPath){if(mode==='gate-fail')return {status:1};if(mode==='source-change')fs.appendFileSync(path.join(root,'fc/domain.mjs'),'changed')}
 if(cmd==='/usr/bin/zip')fs.writeFileSync(args[2],'validated-archive');
 return {status:0};
};require('module').syncBuiltinESMExports();
global.fetch=async url=>({status:String(url).includes('models-dev')?403:mode==='smoke-fail'?503:200,json:async()=>({board:{kind:String(url).split('/').pop(),entries:mode==='bad-board'?[]:[{}]}})});
`)
    const packages = {
      '@alicloud/openapi-client': `exports.Config=class{constructor(v){if(v.protocol!=='https')throw Error('Cloud API must use https');Object.assign(this,v)}}`,
      '@alicloud/sts20150401': `exports.default=class{async getCallerIdentity(){return {body:{accountId:'123',arn:'acs:ram::123:user/fixture'}}}}`,
      '@alicloud/fc20230330': `
const fs=require('fs'),f=global.fixture;
for(const n of ['GetFunctionRequest','GetFunctionCodeRequest','UpdateFunctionRequest','UpdateFunctionInput','InputCodeLocation','CustomRuntimeConfig'])exports[n]=class{constructor(v){Object.assign(this,v)}};
exports.default=class{
 constructor(c){this.target=c.endpoint.includes('ap-southeast-1')?'collector':'main';this.calls=0}
 async getFunction(name){
  if(name==='runtime')return {body:{environmentVariables:{ALIBABA_CLOUD_ACCESS_KEY_ID:'runtime-id',ALIBABA_CLOUD_ACCESS_KEY_SECRET:'runtime-secret',...(f.mode==='proxy'&&{ALIBABA_CLOUD_SECURITY_TOKEN:'runtime-token'})}}};
  this.calls++;const s=f.states[this.target];
  const base={description:f.mode==='unrelated-'+this.target?'other':this.target==='main'?'BenchGauge shared leaderboards (managed by ai-benchgauge)':'BenchGauge official Arena dataset collector (managed by ai-benchgauge)',runtime:'custom.debian10',environmentVariables:this.target==='collector'?(f.mode==='missing-collector-token'?{}:{ARENA_COLLECTOR_TOKEN:f.mode==='bad-collector-token'?'invalid':'a'.repeat(43)}):{OSS_BUCKET:'fixture-bucket'},codeChecksum:s.updated?'new':f.mode==='cloud-change'&&this.target==='collector'&&this.calls>1?'other':'old',lastModifiedTime:s.updated?'2':'1'};
  return {body:{...base,...s.config,...(s.updated&&f.mode==='changed-config'?{environmentVariables:{changed:'yes'}}:{})}};
 }
 async getFunctionCode(){return {body:{url:(f.mode==='proxy'?(this.target==='main'?'http://archive.invalid/':'HTTPS://archive.invalid/'):'https://archive.invalid/')+this.target}}}
 async getTrigger(){return {body:{httpTrigger:{urlInternet:f.mode==='bad-trigger'?'https://invalid.example':this.target==='main'?'https://main.cn-shenzhen.fcapp.run':'https://collector.ap-southeast-1.fcapp.run'}}}}
 async updateFunction(name,request){
  if(f.mode==='collector-fail'&&this.target==='collector')throw Error('fixture failure');
  f.states[this.target].updated=true;f.states[this.target].config=request.body;f.updates.push({target:this.target,body:request.body});fs.writeFileSync(f.root+'/updates.json',JSON.stringify(f.updates));
 }
}`,
      'ali-oss': `const crypto=require('crypto'),f=global.fixture;module.exports=class{
 async getBucketInfo(){return {bucket:{Location:'oss-cn-shenzhen',Owner:{ID:'123'},AccessControlList:{Grant:'private'},StorageClass:'Standard'}}}
 async getBucketVersioning(){return {}}
 async getBucketLifecycle(){return {rules:[]}}
 async put(k,b){f.uploaded=b}
 async head(){const hash=crypto.createHash('md5').update(f.uploaded).digest('hex');return {res:{headers:{'content-length':String(f.mode==='bad-upload'?0:f.uploaded.length),etag:f.mode==='bad-etag'?'00000000000000000000000000000000':f.mode==='uppercase-etag'?'"'+hash.toUpperCase()+'"':hash}}}}
 async delete(){}
}`,
      'httpx': `const {Readable}=require('stream'),f=global.fixture;exports.request=async (url,options)=>{if(options.timeout!==600000)throw Error('unexpected timeout');if(f.mode==='proxy'&&options.agent?.kind!==(new URL(url).protocol==='https:'?'https':'http'))throw Error('incorrect proxy agent');const target=url.split('/').pop(), updated=f.states[target].updated;if(f.mode==='network-download'&&target==='collector'){const r=new Readable({read(){this.destroy(Object.assign(Error('aborted'),{code:'ECONNRESET'}))}});r.statusCode=200;return r}const data=updated?(f.mode==='archive-mismatch'?'wrong':'validated-archive'):'original';const r=Readable.from([Buffer.from(data)]);r.statusCode=f.mode==='bad-download'?503:200;return r}`,
      'https-proxy-agent': `module.exports=class{constructor(url){this.url=url;this.kind='https'}}`,
      'http-proxy-agent': `module.exports=class{constructor(url){this.url=url;this.kind='http'}}`,
    }
    for (const [name, source] of Object.entries(packages)) {
      const path = join(root, 'fc/node_modules', name)
      mkdirSync(path, { recursive: true }); writeFileSync(join(path, 'index.js'), source)
    }
    const env = { ...process.env }; delete env.TEST_AUTO_REPAIR; if (mode === 'repair-disabled') env.TEST_AUTO_REPAIR = '0'; delete env.ALIBABA_CLOUD_ACCESS_KEY_ID; delete env.ALIBABA_CLOUD_ACCESS_KEY_SECRET
    if (mode === 'env-credentials') { env.ALIBABA_CLOUD_ACCESS_KEY_ID = 'env-id'; env.ALIBABA_CLOUD_ACCESS_KEY_SECRET = 'env-secret' }
    if (['idle-deploy', 'busy-during-deploy'].includes(mode)) env.SHARED_FC_REQUIRE_IDLE = '1'
    const result = await spawnResult(process.execPath, ['--require', preload, new URL('./shared-fc-auto.mjs', import.meta.url).pathname, mode === 'invalid-cli' ? 'invalid' : 'deploy'], { cwd: root, env, encoding: 'utf8', timeout: 15000 })
    const receiptPath = join(root, 'work/shared-fc-auto/success.json')
    if (['success', 'auto-repair', 'repair-disabled', 'cached-proof', 'uppercase-etag', 'proxy', 'env-credentials', 'idle-deploy'].includes(mode)) {
      assert.equal(result.status, 0, result.stderr)
      assert.equal(JSON.parse(readFileSync(receiptPath, 'utf8')).status, 'success')
      const updates = JSON.parse(readFileSync(join(root, 'updates.json'), 'utf8'))
      assert.deepEqual(updates.map(item => item.target), ['collector', 'main'])
      assert.deepEqual(updates[0].body, {
        description: 'BenchGauge official Arena dataset collector (managed by ai-benchgauge)',
        code: { zipFile: Buffer.from('validated-archive').toString('base64') }, runtime: 'custom.debian10', handler: 'index.handler',
        memorySize: 512, cpu: 0.25, diskSize: 512, timeout: 25, instanceConcurrency: 8,
        internetAccess: true, role: '', customRuntimeConfig: { command: ['/var/fc/lang/nodejs20/bin/node', '/code/arena-collector.mjs'], port: 9000 },
        environmentVariables: { ARENA_COLLECTOR_TOKEN: 'a'.repeat(43) },
      })
      assert.deepEqual(Object.keys(updates[1].body), ['code'])
      assert.ok(!readFileSync(receiptPath, 'utf8').includes('secret'))
    } else {
      assert.notEqual(result.status, 0, mode)
      assert.equal(existsSync(receiptPath), false, mode)
      if (mode === 'network-download') assert.match(result.stderr, /线上代码包下载暂时失败：连接中断/)
      if (mode === 'missing-collector-token') assert.match(result.stderr, /采集器缺少已核实的专用令牌/)
      if (mode === 'bad-etag') assert.match(result.stderr, /OSS 发布包校验失败/)
      if (['untested-source', 'missing-test-proof', 'cached-proof-change', 'gate-fail', 'source-change', 'collector-fail', 'cloud-change', 'network-download', 'missing-collector-token', 'bad-etag'].includes(mode)) assert.equal(existsSync(join(root, 'updates.json')), false, mode)
    }
  }
  }
  await Promise.all(Array.from({ length: 4 }, runModes))
})

test('watcher schedules a stable pending candidate and forwards the publish result', async t => {
  const { spawnSync } = await import('node:child_process')
  const { readFileSync } = await import('node:fs')
  const root = fixture(t)
  writeFileSync(join(root, 'fc/package.json'), '{}')
  writeFileSync(join(root, '.benchgauge-cloud.local.json'), JSON.stringify({ credentialsFile: 'credentials' }))
  writeFileSync(join(root, 'credentials'), 'fixture')
  writeFileSync(join(root, 'Scripts/commit-lock.mjs'), `export const acquireCommitLock=()=>({acquired:process.env.FIXTURE_MODE!=='locked',release(){}})`)
  writeFileSync(join(root, 'Scripts/test-repair.mjs'), `export const runTestGate=async()=>({status:0})`)
  writeFileSync(join(root, 'Scripts/test.mjs'), `import {readFileSync} from 'node:fs';export const fullCoverageReuseSignature=()=> 'proof';export const testInputSignature=()=>process.env.FIXTURE_MODE==='retry'?readFileSync('gate-input','utf8'):'fixture';export const runTests=async()=>({status:0})`)
  writeFileSync(join(root, 'gate-input'), 'before')
  const { copyFileSync } = await import('node:fs')
  copyFileSync(new URL('./deploy-shared-leaderboards.mjs', import.meta.url), join(root, 'Scripts/deploy-shared-leaderboards.mjs'))
  writeFileSync(join(root, 'Scripts/calmmit.mjs'), `
import {appendFileSync,readFileSync,writeFileSync,unlinkSync} from 'node:fs'; import {resolve,join} from 'node:path';
const root=resolve(import.meta.dirname,'..');
export const ci={root,load:async name=>name==='ai-activity'?{createRepositoryActivity:()=>({snapshot:()=>({blocked:process.env.FIXTURE_MODE==='blocked'})})}:{createWatchSession:options=>({
 schedule(reason){appendFileSync(join(root,'events'),'scheduled\\n');options.uploadConfig();const config=join(root,'.benchgauge-cloud.local.json'),saved=readFileSync(config);unlinkSync(config);options.uploadConfig();writeFileSync(config,saved);options.classifyFailure('源码或部署配置发生变化');options.classifyFailure('failure');options.classifyFailure();options.startPublish((code,error,result)=>{appendFileSync(join(root,'events'),'finished\\n'+(error?'error\\n':''));if(result)writeFileSync(join(root,'failure-path'),result.logPath)})},stop(){appendFileSync(join(root,'events'),'stopped\\n')}
})}}`)
  const preload = join(root, 'preload.cjs')
  writeFileSync(preload, `
const cp=require('child_process'),{EventEmitter}=require('events'),path=require('path'),{pathToFileURL}=require('url');
const actual=${JSON.stringify(new URL('./shared-fc-auto.mjs', import.meta.url).href)},root=${JSON.stringify(root)};
let fixtureNow=Date.now();const fixtureIntervals=new Set();
Date.now=()=>fixtureNow;
global.setInterval=callback=>{fixtureIntervals.add(callback);return callback};
global.clearInterval=callback=>fixtureIntervals.delete(callback);
global.runFixtureIntervals=elapsed=>{fixtureNow+=elapsed;for(const callback of [...fixtureIntervals])callback()};
require('module').registerHooks({resolve(s,c,n){if(c.parentURL===actual&&['./calmmit.mjs','./commit-lock.mjs','./deploy-shared-leaderboards.mjs','./test-repair.mjs','./test.mjs'].includes(s))return {url:pathToFileURL(path.join(root,'Scripts',s)).href,shortCircuit:true};return n(s,c)}});
cp.spawn=()=>{const child=new EventEmitter();child.stdout=new EventEmitter();child.stderr=new EventEmitter();queueMicrotask(()=>{child.stdout.emit('data',Buffer.from('publish fixture'));if(process.env.FIXTURE_MODE==='child-error')child.emit('error',Error('fixture'));child.emit('close',0)});return child};
require('module').syncBuiltinESMExports();`)
  const script = `const api=await import(${JSON.stringify(new URL('./shared-fc-auto.mjs', import.meta.url).href)});if(process.env.FIXTURE_MODE==='matching'){const {mkdirSync,writeFileSync}=await import('node:fs');mkdirSync('work/shared-fc-auto',{recursive:true});writeFileSync('work/shared-fc-auto/success.json',JSON.stringify({version:1,status:'success',sourceSignature:api.sourceSignature(),configSignature:api.configSignature()}))}if(process.env.FIXTURE_MODE==='missing'){const {unlinkSync}=await import('node:fs');unlinkSync('.benchgauge-cloud.local.json')}if(process.env.FIXTURE_MODE==='log-error'){const {mkdirSync}=await import('node:fs');mkdirSync('work/shared-fc-auto/publish.log',{recursive:true})}const stop=await api.startSharedFcWatch();global.runFixtureIntervals(20);await new Promise(resolve=>setImmediate(resolve));if(process.env.FIXTURE_MODE==='retry'){const {writeFileSync}=await import('node:fs');writeFileSync('gate-input','after');global.runFixtureIntervals(20);global.runFixtureIntervals(20);await new Promise(resolve=>setImmediate(resolve))}stop();process.exit(0)`
  const originalConfig = readFileSync(join(root, '.benchgauge-cloud.local.json'))
  for (const mode of ['normal', 'child-error', 'retry', 'matching', 'blocked', 'locked', 'missing', 'default-delay', 'log-error']) {
    writeFileSync(join(root, '.benchgauge-cloud.local.json'), originalConfig)
    writeFileSync(join(root, 'events'), '')
    rmSync(join(root, 'work/shared-fc-auto/success.json'), { force: true })
    rmSync(join(root, 'work/shared-fc-auto/publish.log'), { force: true, recursive: true })
    const env = { ...process.env, FIXTURE_MODE: mode, SHARED_FC_AUTODEPLOY: '1', SHARED_FC_DEBOUNCE_MS: '1' }
    if (mode === 'default-delay') delete env.SHARED_FC_DEBOUNCE_MS
    const result = spawnSync(process.execPath, ['--require', preload, '--input-type=module', '-e', script], { cwd: root, env, encoding: 'utf8', timeout: 15000 })
    assert.equal(result.status, 0, result.stderr)
    if (['normal', 'child-error', 'retry', 'log-error'].includes(mode)) {
      assert.match(readFileSync(join(root, 'events'), 'utf8'), /scheduled\nfinished\n/)
      assert.match(result.stdout, /publish fixture/)
      if (mode === 'log-error') assert.match(readFileSync(join(root, 'events'), 'utf8'), /error\n/)
      if (!['child-error', 'log-error'].includes(mode)) {
        assert.equal(readFileSync(join(root, 'failure-path'), 'utf8'), 'work/shared-fc-auto/publish.log')
        assert.match(readFileSync(join(root, 'work/shared-fc-auto/publish.log'), 'utf8'), /publish fixture/)
      }
      if (mode === 'retry') assert.equal(readFileSync(join(root, 'events'), 'utf8').match(/scheduled/g)?.length, 2)
    } else assert.doesNotMatch(readFileSync(join(root, 'events'), 'utf8'), /scheduled/)
  }
})
