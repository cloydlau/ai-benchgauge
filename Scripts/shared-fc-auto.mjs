import { createHash, randomUUID } from 'node:crypto'
import { spawn, spawnSync } from 'node:child_process'
import { mkdirSync, readFileSync, writeFileSync, renameSync } from 'node:fs'
import { createRequire } from 'node:module'
import { join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { ci } from './calmmit.mjs'
import { acquireCommitLock } from './commit-lock.mjs'
import { deploymentConfiguration, existingRuntimeCredentials, checkExistingBucket, isManagedFunction, packageCode, runtimeFiles } from './deploy-shared-leaderboards.mjs'
import { runTestGate } from './test-repair.mjs'
import { runTests, testInputSignature } from './test.mjs'

const root = ci.root
const state = join(root, 'work/shared-fc-auto')
const receiptPath = join(state, 'success.json')
const log = message => console.log(`[shared-fc] ${message}`)
const collectorDescription = 'BenchGauge official Arena dataset collector (managed by ai-benchgauge)'
const { createWatchSession } = await ci.load('deployment-watch')
const { createRepositoryActivity } = await ci.load('ai-activity')
const hash = input => createHash('sha256').update(input).digest('hex')
export const gateTests = ['cloudbase-usage', 'vercel-usage', 'openrouter-usage', 'epoch-eci', 'arena-dataset', 'models-dev', 'shared-leaderboards', 'brand-discovery', 'country-discovery'].map(name => `Scripts/${name}.test.mjs`)
export function sourceSignature(directory = root) {
  const h = createHash('sha256')
  for (const name of [...runtimeFiles.map(name => `fc/${name}`), ...gateTests]) h.update(name).update('\0').update(readFileSync(join(directory, name))).update('\0')
  return h.digest('hex')
}
export function readReceipt(path = receiptPath) {
  try { const value = JSON.parse(readFileSync(path, 'utf8')); return value.version === 1 && value.status === 'success' ? value : null } catch { return null }
}
export function configSignature(directory = root) {
  const configBytes = readFileSync(join(directory, '.benchgauge-cloud.local.json'))
  const config = deploymentConfiguration(JSON.parse(configBytes))
  const credentials = config.credentialsFile ? readFileSync(resolve(directory, config.credentialsFile)) : Buffer.alloc(0)
  return hash(Buffer.concat([configBytes, Buffer.from('\0'), credentials, Buffer.from('\0'), Buffer.from(process.env.ALIBABA_CLOUD_ACCESS_KEY_ID ?? ''), Buffer.from('\0'), Buffer.from(process.env.ALIBABA_CLOUD_ACCESS_KEY_SECRET ?? '')]))
}
export function sameStamp(a, b) { return a.codeChecksum === b.codeChecksum && a.lastModifiedTime === b.lastModifiedTime }
export function sameConfig(a, b) {
  const keys = ['functionName', 'description', 'runtime', 'handler', 'memorySize', 'cpu', 'diskSize', 'timeout', 'instanceConcurrency', 'internetAccess', 'role', 'customRuntimeConfig', 'environmentVariables']
  return keys.every(key => JSON.stringify(a[key]) === JSON.stringify(b[key]))
}
function collectorToken(before) {
  const token = before.environmentVariables?.ARENA_COLLECTOR_TOKEN
  if (!/^[A-Za-z0-9_-]{43}$/.test(token ?? '')) throw new Error('采集器缺少已核实的专用令牌')
  return token
}
function collectorUpdate(FC, before, code) {
  const token = collectorToken(before)
  return new FC.UpdateFunctionInput({ description: collectorDescription,
    code: new FC.InputCodeLocation(code), runtime: 'custom.debian10', handler: 'index.handler',
    memorySize: 512, cpu: 0.25, diskSize: 512, timeout: 25, instanceConcurrency: 8,
    internetAccess: true, role: '',
    customRuntimeConfig: new FC.CustomRuntimeConfig({ command: ['/var/fc/lang/nodejs20/bin/node', '/code/arena-collector.mjs'], port: 9000 }),
    environmentVariables: { ARENA_COLLECTOR_TOKEN: token } })
}
function run(command, args, options = {}) {
  const result = spawnSync(command, args, { cwd: root, stdio: 'inherit', ...options })
  if (result.status !== 0) throw new Error(`${command} failed`)
}
function assertCurrent(source, config, gate) {
  if (sourceSignature() !== source || configSignature() !== config || testInputSignature() !== gate || process.env.SHARED_FC_REQUIRE_IDLE === '1' && createRepositoryActivity({ root }).snapshot().blocked) throw new Error('源码或部署配置发生变化，等待下一轮发布')
}
function credentials(config) {
  const values = config.credentialsFile ? Object.fromEntries(readFileSync(resolve(root, config.credentialsFile), 'utf8').split('\n').flatMap(line => {
    const match = /^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$/.exec(line)
    return match ? [[match[1], match[2].replace(/^["']|["']$/g, '')]] : []
  })) : {}
  const accessKeyId = process.env.ALIBABA_CLOUD_ACCESS_KEY_ID ?? values.ALIBABA_CLOUD_ACCESS_KEY_ID
  const accessKeySecret = process.env.ALIBABA_CLOUD_ACCESS_KEY_SECRET ?? values.ALIBABA_CLOUD_ACCESS_KEY_SECRET
  if (!accessKeyId || !accessKeySecret) throw new Error('缺少云端部署凭据')
  return { accessKeyId, accessKeySecret }
}
async function download(httpx, client, FC, name, destination) {
  const url = (await client.getFunctionCode(name, new FC.GetFunctionCodeRequest())).body.url
  let content
  try {
    const response = await httpx.request(url, { timeout: 600000 })
    if (response.statusCode !== 200) throw new Error(`无法下载线上代码包：HTTP ${response.statusCode}`)
    const chunks = []
    for await (const chunk of response) chunks.push(chunk)
    content = Buffer.concat(chunks)
  } catch (error) {
    const reason = { ECONNRESET: '连接中断', ETIMEDOUT: '连接超时', EAI_AGAIN: '域名解析暂时失败', ECONNREFUSED: '连接被拒绝', EPIPE: '连接断开' }[error.code]
    if (reason) throw new Error(`线上代码包下载暂时失败：${reason}`)
    throw error
  }
  writeFileSync(destination, content, { mode: 0o600, flag: 'wx' })
  return hash(content)
}
export function classifySharedFcFailure(output = '') {
  return /源码或部署配置发生变化|已有云函数发布任务|线上代码包下载暂时失败：(?:连接中断|连接超时|域名解析暂时失败|连接被拒绝|连接断开)/.test(output) ? 'retry' : 'pause'
}
async function verifyHttp(url, expected) {
  const response = await fetch(url, { signal: AbortSignal.timeout(30000) })
  if (response.status !== expected) throw new Error(`线上接口校验失败：HTTP ${response.status}`)
  return response
}
export async function deploy() {
  mkdirSync(state, { recursive: true })
  const lock = acquireCommitLock({ lockPath: join(state, 'deploy.lock'), verifyProcessStart: true })
  if (!lock.acquired) throw new Error('已有云函数发布任务')
  try {
    const source = sourceSignature(), configHash = configSignature(), gate = testInputSignature()
    log('执行项目完整测试和覆盖率门禁')
    const gateEnv = { ...process.env, TEST_AUTO_REPAIR: '0' }
    const result = await runTestGate({ env: gateEnv,
      test: () => runTests({ root, env: gateEnv, gate: true, coverage: true, lockWaitMs: 300_000 }) })
    if (result.status === 75) throw new Error('已有云函数发布任务或源码发生变化，等待下一轮发布')
    if (result.status !== 0) throw new Error('完整测试或覆盖率门禁未通过，详见 work/test-results/latest.log')
    assertCurrent(source, configHash, gate)
    log('执行服务端测试')
    run(process.execPath, ['--test', ...gateTests])
    assertCurrent(source, configHash, gate)
    log('打包已验证的服务端代码')
    const archive = packageCode()
    assertCurrent(source, configHash, gate)
    const archiveBytes = readFileSync(archive), archiveHash = hash(archiveBytes)
    const config = deploymentConfiguration(JSON.parse(readFileSync(join(root, '.benchgauge-cloud.local.json'))))
    if (!config.bucket || !config.runtimeCredentialsFunction || config.arenaCollector !== true) throw new Error('自动部署需要已有主函数、运行身份和采集函数配置')
    const require = createRequire(join(root, 'fc/package.json'))
    const { Config } = require('@alicloud/openapi-client'), FC = require('@alicloud/fc20230330'), STS = require('@alicloud/sts20150401'), OSS = require('ali-oss'), httpx = require('httpx')
    if (config.proxy) {
      const original = httpx.request
      const HttpsProxyAgent = require('https-proxy-agent'), HttpProxyAgent = require('http-proxy-agent')
      httpx.request = (url, options) => original(url, { ...options, agent: new URL(url).protocol === 'https:' ? new HttpsProxyAgent(config.proxy) : new HttpProxyAgent(config.proxy) })
    }
    const common = { ...credentials(config), protocol: 'https', connectTimeout: 10000, readTimeout: 300000 }
    const account = (await new STS.default(new Config({ ...common, endpoint: `sts.${config.region}.aliyuncs.com` })).getCallerIdentity()).body.accountId
    const main = new FC.default(new Config({ ...common, endpoint: `${account}.${config.region}.fc.aliyuncs.com` }))
    const collector = new FC.default(new Config({ ...common, endpoint: `${account}.ap-southeast-1.fc.aliyuncs.com` }))
    const runtime = await existingRuntimeCredentials(main, FC, config, account, async auth => (await new STS.default(new Config({ ...common, ...auth, endpoint: `sts.${config.region}.aliyuncs.com` })).getCallerIdentity()).body)
    const oss = new OSS({ ...runtime.auth, ...(runtime.auth.securityToken ? { stsToken: runtime.auth.securityToken } : {}), bucket: config.bucket, region: `oss-${config.region}`, secure: true, timeout: 30000, ...(config.proxy ? { httpsAgent: new (require('https-proxy-agent'))(config.proxy) } : {}) })
    await checkExistingBucket(oss, config.bucket, config.region, account)
    const targets = [{ client: main, name: config.functionName, main: true }, { client: collector, name: `${config.functionName}-arena-dataset`, main: false }]
    const id = randomUUID(), stageKey = `benchgauge/deployments/auto/${id}.zip`
    for (const target of targets) {
      target.before = (await target.client.getFunction(target.name, new FC.GetFunctionRequest())).body
      if (target.main ? !isManagedFunction(target.before, config) : target.before.description !== collectorDescription) throw new Error('拒绝更新非 BenchGauge 云函数')
      if (!target.main) collectorToken(target.before)
      await download(httpx, target.client, FC, target.name, join(state, `${id}-${target.main ? 'main' : 'collector'}-before.zip`))
      target.trigger = (await target.client.getTrigger(target.name, 'http')).body.httpTrigger?.urlInternet
      const url = new URL(target.trigger)
      if (url.protocol !== 'https:' || !url.hostname.endsWith(target.main ? `.${config.region}.fcapp.run` : '.ap-southeast-1.fcapp.run')) throw new Error('云函数接口地址不符合预期')
    }
    assertCurrent(source, configHash, gate)
    log('上传主服务发布包')
    await oss.put(stageKey, archiveBytes, { headers: { 'x-oss-forbid-overwrite': 'true' } })
    const uploaded = await oss.head(stageKey)
    if (Number(uploaded.res.headers['content-length']) !== archiveBytes.length || String(uploaded.res.headers.etag).replaceAll('"', '').toLowerCase() !== createHash('md5').update(archiveBytes).digest('hex')) throw new Error('OSS 发布包校验失败')
    // Update the collector first so new main-service calls never target an older collector.
    for (const target of targets.slice().reverse()) {
      assertCurrent(source, configHash, gate)
      const current = (await target.client.getFunction(target.name, new FC.GetFunctionRequest())).body
      if (!sameStamp(current, target.before) || !sameConfig(current, target.before)) throw new Error('线上函数已变化，停止覆盖并等待重新部署')
      const code = target.main ? { ossBucketName: config.bucket, ossObjectName: stageKey } : { zipFile: archiveBytes.toString('base64') }
      const input = target.main
        ? new FC.UpdateFunctionInput({ code: new FC.InputCodeLocation(code) })
        : collectorUpdate(FC, target.before, code)
      log(`更新${target.main ? '主服务' : '采集器'}代码`)
      await target.client.updateFunction(target.name, new FC.UpdateFunctionRequest({ body: input }))
      const after = (await target.client.getFunction(target.name, new FC.GetFunctionRequest())).body
      if (!sameConfig(after, target.main ? target.before : { ...target.before, ...input })) throw new Error('云函数配置变化，部署核验失败')
      if (await download(httpx, target.client, FC, target.name, join(state, `${id}-${target.main ? 'main' : 'collector'}-after.zip`)) !== archiveHash) throw new Error('线上代码与发布包不一致')
    }
    log('验证线上接口')
    await verifyHttp(new URL('/v1/models-dev', targets[1].trigger), 403)
    for (const kind of ['arenaText', 'codeArenaWebDev', 'artificialAnalysis']) {
      const response = await verifyHttp(new URL(`/v1/boards/${kind}`, targets[0].trigger), 200)
      const data = await response.json()
      if (!data.board || data.board.kind !== kind || !Array.isArray(data.board.entries) || !data.board.entries.length) throw new Error(`线上榜单 ${kind} 校验失败`)
    }
    assertCurrent(source, configHash, gate)
    await oss.delete(stageKey)
    const tmp = `${receiptPath}.${id}.tmp`
    writeFileSync(tmp, JSON.stringify({ version: 1, status: 'success', sourceSignature: source, configSignature: configHash, archiveHash, publishedAt: Date.now() }) + '\n', { mode: 0o600 })
    renameSync(tmp, receiptPath)
    log('线上代码与接口验证通过，自动部署完成')
  } finally { lock.release() }
}

export async function startSharedFcWatch() {
  if (process.env.SHARED_FC_AUTODEPLOY === '0') return () => {}
  mkdirSync(state, { recursive: true })
  const lock = acquireCommitLock({ lockPath: join(state, 'watch.lock'), verifyProcessStart: true })
  if (!lock.acquired) { log('自动部署监听已在运行'); return () => {} }
  let previous = '', changedAt = Date.now(), scheduled = '', warned = false, gateSignature = '', gateCheckedAt = 0
  const repositoryActivity = createRepositoryActivity({ root })
  const activity = { snapshot() { const snapshot = repositoryActivity.snapshot(); return { ...snapshot, ready: !snapshot.blocked } } }
  const session = createWatchSession({ root, activity, autocommit: false, debounceMs: Number(process.env.SHARED_FC_DEBOUNCE_MS || 60000), now: Date.now, setTimeoutFn: setTimeout, clearTimeoutFn: clearTimeout, log,
    uploadConfig: () => { try { configSignature(); return { ready: true } } catch { return { ready: false, reason: '缺少云函数部署配置或凭据' } } },
    classifyFailure: classifySharedFcFailure,
    startPublish: done => {
      let output = ''
      let finished = false
      const finish = (...args) => { if (!finished) { finished = true; done(...args) } }
      const child = spawn(process.execPath, [fileURLToPath(import.meta.url), 'deploy'], { cwd: root, env: { ...process.env, SHARED_FC_REQUIRE_IDLE: '1' }, stdio: ['ignore', 'pipe', 'pipe'] })
      for (const stream of [child.stdout, child.stderr]) stream.on('data', data => { output = (output + data).slice(-32000); process.stdout.write(data) })
      child.once('error', error => finish(null, error))
      child.once('close', code => {
        const logPath = 'work/shared-fc-auto/publish.log'
        try { writeFileSync(join(root, logPath), output, { mode: 0o600 }) }
        catch (error) { finish(code, error); return }
        finish(code, undefined, { output, logPath })
      })
    },
  })
  const poll = () => {
    try {
      const signature = `${sourceSignature()}:${configSignature()}`
      warned = false
      if (signature !== previous) { previous = signature; changedAt = Date.now(); scheduled = '' }
      const receipt = readReceipt()
      const pending = !receipt || `${receipt.sourceSignature}:${receipt.configSignature}` !== signature
      const debounce = Number(process.env.SHARED_FC_DEBOUNCE_MS || 60000)
      if (pending && !activity.snapshot().blocked && Date.now() - gateCheckedAt >= Math.min(5000, debounce)) {
        gateCheckedAt = Date.now()
        const currentGate = testInputSignature()
        if (currentGate !== gateSignature) { gateSignature = currentGate; changedAt = Date.now(); scheduled = '' }
      }
      if (pending && scheduled !== signature && !activity.snapshot().blocked && Date.now() - changedAt >= debounce) {
        scheduled = signature
        session.schedule('发现待发布的共享服务源码或配置', { publish: true })
      }
    } catch { previous = ''; scheduled = ''; if (!warned) { warned = true; log('无法读取自动部署配置；等待配置恢复') } }
  }
  poll()
  const timer = setInterval(poll, 1000)
  const stop = () => { clearInterval(timer); session.stop(); lock.release() }
  process.once('exit', stop)
  log('已监听共享服务；源码稳定后自动测试、发布并验证线上')
  return stop
}
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  if (process.argv[2] === 'deploy') deploy().catch(error => { console.error(`[shared-fc] 发布失败：${String(error.message).replace(/[A-Za-z0-9+\/_=-]{24,}/g, '[redacted]').slice(0, 250)}`); process.exitCode = 1 })
  else { console.error('用法：node Scripts/shared-fc-auto.mjs deploy'); process.exitCode = 1 }
}
