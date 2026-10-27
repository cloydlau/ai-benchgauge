import assert from 'node:assert/strict'
import test from 'node:test'
import { spawnSync } from 'node:child_process'
import { copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { deploymentConfiguration, existingRuntimeCredentials, checkExistingBucket, isManagedFunction } from './deploy-shared-leaderboards.mjs'

test('legacy repository label requires the dedicated function, runtime and verified bucket', () => {
  const config = { functionName: 'ai-benchgauge', bucket: 'ai-benchgauge' }
  const existing = { description: 'ai-benchgauge', runtime: 'custom.debian10', environmentVariables: { OSS_BUCKET: config.bucket } }
  assert.equal(isManagedFunction(existing, config), true)
  for (const other of [{ ...existing, description: 'Other' }, { ...existing, runtime: 'nodejs20' },
    { ...existing, environmentVariables: undefined }, { ...existing, environmentVariables: { OSS_BUCKET: 'other' } }]) {
    assert.equal(isManagedFunction(other, config), false)
  }
  assert.equal(isManagedFunction(existing, { ...config, functionName: 'other' }), false)
  assert.equal(isManagedFunction(existing, { ...config, bucket: '' }), false)
})

test('deployment rejects invalid endpoints and incomplete runtime credentials', async () => {
  for (const value of [{ region: 'outside' }, { runtimeCredentialsFunction: 'bad/function' }, { proxy: 'https://proxy.invalid' }]) {
    assert.throws(() => deploymentConfiguration(value))
  }
  assert.equal(deploymentConfiguration({ proxy: 'http://proxy.invalid' }).proxy, 'http://proxy.invalid')
  const FC = { GetFunctionRequest: class {} }
  const config = { runtimeCredentialsFunction: 'runtime', runtimeIdentityName: 'fixture' }
  const identity = { accountId: '123', arn: 'acs:ram::123:user/fixture' }
  for (const environmentVariables of [undefined, { ALIBABA_CLOUD_ACCESS_KEY_ID: 'id' }, { ALIBABA_CLOUD_ACCESS_KEY_SECRET: 'secret' }]) {
    await assert.rejects(existingRuntimeCredentials({ getFunction: async () => ({ body: { environmentVariables } }) }, FC, config, '123', async () => identity), /no runtime cloud credentials/)
  }
  const result = await existingRuntimeCredentials({ getFunction: async () => ({ body: { environmentVariables: {
    ALIBABA_CLOUD_ACCESS_KEY_ID: 'id', ALIBABA_CLOUD_ACCESS_KEY_SECRET: 'secret',
  } } }) }, FC, config, '123', async () => identity)
  assert.deepEqual(result.auth, { accessKeyId: 'id', accessKeySecret: 'secret' })
  const info = { Location: 'oss-cn-shenzhen', Owner: { ID: '123' }, AccessControlList: { Grant: 'private' }, StorageClass: 'Standard' }
  const oss = { getBucketInfo: async () => ({ bucket: info }), getBucketVersioning: async () => ({}), getBucketLifecycle: async () => ({}) }
  await checkExistingBucket(oss, 'bucket', 'cn-shenzhen', '123')
  for (const bad of [{ ...info, Owner: undefined }, { ...info, AccessControlList: undefined }, { ...info, StorageClass: 'Archive' }]) {
    await assert.rejects(checkExistingBucket({ ...oss, getBucketInfo: async () => ({ bucket: bad }) }, 'bucket', 'cn-shenzhen', '123'), /private Standard/)
  }
  await assert.rejects(checkExistingBucket({ ...oss, getBucketVersioning: async () => ({ versionStatus: 'Enabled' }) }, 'bucket', 'cn-shenzhen', '123'), /unversioned/)
  await assert.rejects(checkExistingBucket({ ...oss, getBucketLifecycle: async () => { throw { code: 'Other' } } }, 'bucket', 'cn-shenzhen', '123'), e => e.code === 'Other')
  for (const prefix of ['', 'bench', 'benchgauge/nested']) {
    await assert.rejects(checkExistingBucket({ ...oss, getBucketLifecycle: async () => ({ rules: [{ prefix }] }) }, 'bucket', 'cn-shenzhen', '123'), /must not expire/)
  }
  await checkExistingBucket({ ...oss, getBucketLifecycle: async () => ({ rules: [{ prefix: 'unrelated/' }] }) }, 'bucket', 'cn-shenzhen', '123')
})

const runtimeFiles = ['package.json', 'package-lock.json', 'bootstrap', 'server.mjs', 'service.mjs', 'domain.mjs', 'parser.mjs', 'openrouter-usage.mjs', 'vercel-usage.mjs', 'cloudbase-usage.mjs', 'epoch-eci.mjs', 'arena-dataset.mjs', 'arena-collector.mjs', 'arena-attribution.json', 'models-dev.mjs', 'models-dev-license.txt', 'model-openness.mjs', 'source-logos.mjs', 'oss-store.mjs', 'brands.mjs', 'brand-catalog.json', 'leaderboard-policy.json', 'countries.mjs', 'country-catalog.json']
function fixture(t, mode, config) {
  const root = realpathSync(mkdtempSync(join(tmpdir(), 'benchgauge-cloud-boundary-')))
  t.after(() => rmSync(root, { recursive: true, force: true }))
  mkdirSync(join(root, 'Scripts')); mkdirSync(join(root, 'fc'))
  copyFileSync(new URL('./deploy-shared-leaderboards.mjs', import.meta.url), join(root, 'Scripts/deploy-shared-leaderboards.mjs'))
  for (const name of runtimeFiles) writeFileSync(join(root, 'fc', name), name === 'package.json' ? '{}' : 'fixture ' + name)
  if (config) writeFileSync(join(root, '.benchgauge-cloud.local.json'), JSON.stringify(config))
  writeFileSync(join(root, 'credentials.env'), '# no credential in this line\nALIBABA_CLOUD_ACCESS_KEY_ID="file-id"\nALIBABA_CLOUD_ACCESS_KEY_SECRET=\'file-secret\'\n')
  if (['invalid-sync-token', 'invalid-collector-token', 'existing-tokens'].includes(mode)) {
    mkdirSync(join(root, 'work/shared-leaderboards'), { recursive: true })
    writeFileSync(join(root, 'work/shared-leaderboards/models-dev-sync-token'), mode === 'invalid-sync-token' ? 'invalid' : 'T'.repeat(43))
    writeFileSync(join(root, 'work/shared-leaderboards/arena-collector-token'), mode === 'invalid-collector-token' ? 'invalid' : 'C'.repeat(43))
  }
  const preload = join(root, 'sandbox.cjs')
  writeFileSync(preload, `
const cp = require('node:child_process'), fs = require('node:fs'), path = require('node:path');
const root = ${JSON.stringify(root)}, mode = ${JSON.stringify(mode)};
cp.spawnSync = (command, args) => {
  if (command === process.execPath) {
    if (mode === 'validation-failed') return {status: 1};
    if (mode === 'validation-changed') fs.appendFileSync(path.join(root, 'fc/service.mjs'), 'changed');
  } else if (command === 'npm') {
    if (mode === 'npm-failed') return {status: 1};
    if (mode === 'packaging-changed') fs.appendFileSync(path.join(root, 'fc/service.mjs'), 'changed');
  } else if (command === '/usr/bin/zip') fs.writeFileSync(args[2], 'isolated archive');
  else throw Error('Unexpected external command: ' + command);
  return {status: 0};
};
require('node:module').syncBuiltinESMExports();
`)
  const packages = {
    '@alicloud/openapi-client': 'exports.Config = class { constructor(value) { Object.assign(this, value) } };',
    '@alicloud/sts20150401': `exports.default = class { async getCallerIdentity() {
      if (${JSON.stringify(mode)} === 'identity-failed') throw {code:'IdentityFailed'};
      if (${JSON.stringify(mode)} === 'opaque-failure') throw {};
      if (${JSON.stringify(mode)} === 'upload-changed') require('node:fs').appendFileSync(${JSON.stringify(join(root, 'fc/service.mjs'))}, 'changed');
      return {body:{accountId:'123',arn:'acs:ram::123:user/fixture'}};
    }};`,
    'ali-oss': `module.exports = class {
      async getBucketInfo() {return {bucket:{Location:'oss-cn-shenzhen',Owner:{ID:'123'},AccessControlList:{Grant:'private'},StorageClass:'Standard'}}}
      async getBucketVersioning() {return {}}
      async getBucketLifecycle() {return {rules:[]}}
    };`,
    '@alicloud/fc20230330': `
const mode = ${JSON.stringify(mode)}, fs = require('node:fs');
for (const name of ['GetFunctionRequest','InputCodeLocation','CustomRuntimeConfig','UpdateFunctionRequest','UpdateFunctionInput','CreateFunctionRequest','CreateFunctionInput','CreateTriggerRequest','CreateTriggerInput','UpdateTriggerRequest','UpdateTriggerInput']) {
  exports[name] = class {constructor(value) {Object.assign(this,value)}};
}
exports.default = class {
  constructor(config) {this.collector = config.endpoint.includes('ap-southeast-1')}
  async getFunction(name) {
    if (this.collector) {
      if (mode === 'collector-lookup-failed') throw {code:'CollectorDenied'};
      if (mode === 'collector-new') throw {code:'FunctionNotFound'};
      return {body:{description:mode === 'collector-unrelated' ? 'other' : 'BenchGauge official Arena dataset collector (managed by ai-benchgauge)',runtime:mode === 'collector-runtime' ? 'nodejs20' : 'custom.debian10'}};
    }
    if (name === 'runtime') return {body:{environmentVariables:{ALIBABA_CLOUD_ACCESS_KEY_ID:'runtime-id',ALIBABA_CLOUD_ACCESS_KEY_SECRET:'runtime-secret',ALIBABA_CLOUD_SECURITY_TOKEN:'runtime-token'}}};
    if (mode === 'lookup-failed') throw {code:'Denied'};
    if (mode === 'new' || mode === 'trigger-new') throw {code:'FunctionNotFound'};
    return {body:{description:mode === 'unrelated' ? 'someone else' : 'BenchGauge shared leaderboards (managed by ai-benchgauge)', ...(mode === 'openrouter-existing' && {environmentVariables:{OPENROUTER_API_KEY:'fixture-existing-key'}})}};
  }
  async updateFunction(name, request) {fs.writeFileSync(${JSON.stringify(root)} + '/' + (this.collector ? 'collector' : 'request') + '.json',JSON.stringify({name,operation:'update',body:request.body}))}
  async createFunction(request) {fs.writeFileSync(${JSON.stringify(root)} + '/' + (this.collector ? 'collector' : 'request') + '.json',JSON.stringify({operation:'create',body:request.body}))}
  async getTrigger(name, triggerName) {
    if (this.collector) {
      if (mode === 'collector-new') throw {code:'TriggerNotFound'};
      if (mode === 'collector-trigger-failed') throw {code:'CollectorTriggerDenied'};
      if (mode === 'collector-url-empty') return {body:{}};
      return {body:{httpTrigger:{urlInternet:mode === 'collector-url-http' ? 'http://collector.ap-southeast-1.fcapp.run' : mode === 'collector-url-host' ? 'https://evil.invalid' : 'https://collector.ap-southeast-1.fcapp.run/'}}};
    }
    if (triggerName === 'models-dev-sync' || triggerName === 'models-dev-fill') {
      if (mode === 'timer-failed') throw {code:'TimerDenied'};
      if (mode === 'timer-wrong' || mode === 'fill-wrong' && triggerName === 'models-dev-fill') return {body:{triggerType:'http'}};
      if (mode === 'new' || mode === 'trigger-new') throw {code:'TriggerNotFound'};
      return {body:{triggerType:'timer'}};
    }
    if (mode === 'trigger-new') throw {code:'TriggerNotFound'};
    if (mode === 'trigger-failed') throw {code:'DeniedTrigger'};
    return {body:mode === 'trigger-empty' ? {} : {httpTrigger:{urlInternet:mode === 'trigger-http' ? 'http://example.invalid/' : 'https://example.invalid/'}}};
  }
  async updateTrigger(name, triggerName, request) {fs.writeFileSync(${JSON.stringify(root)} + '/' + triggerName + '.json',JSON.stringify({name,triggerName,operation:'update',body:request.body}))}
  async createTrigger(name, request) {
    if (request.body.triggerType === 'timer') fs.writeFileSync(${JSON.stringify(root)} + '/' + request.body.triggerName + '.json',JSON.stringify({name,triggerName:request.body.triggerName,operation:'create',body:request.body}));
    return {body:{httpTrigger:{urlInternet:this.collector ? 'https://collector.ap-southeast-1.fcapp.run/' : 'https://example.invalid/'}}};
  }
};`,
  }
  for (const [name, source] of Object.entries(packages)) {
    const directory = join(root, 'fc/node_modules', name)
    mkdirSync(directory, { recursive: true }); writeFileSync(join(directory, 'index.js'), source)
  }
  return { root, run(args = [], env = {}) {
    const environment = { ...process.env }
    for (const key of ['ALIBABA_CLOUD_ACCESS_KEY_ID', 'ALIBABA_CLOUD_ACCESS_KEY_SECRET', 'ALIBABA_CLOUD_SECURITY_TOKEN', 'OPENROUTER_API_KEY']) delete environment[key]
    Object.assign(environment, env)
    return spawnSync(process.execPath, ['--require', preload, join(root, 'Scripts/deploy-shared-leaderboards.mjs'), ...args], { cwd: root, env: environment, encoding: 'utf8', timeout: 15000 })
  } }
}
const role = { bucket: 'fixture-bucket', roleArn: 'acs:ram::123:role/fixture', credentialsFile: 'credentials.env' }

test('deployment CLI validates, packages and creates or updates only the verified function', t => {
  for (const mode of ['update', 'new', 'trigger-new', 'runtime']) {
    const config = mode === 'runtime' ? { bucket: 'fixture-bucket', runtimeCredentialsFunction: 'runtime', runtimeIdentityName: 'fixture', proxy: 'http://proxy.invalid' } : role
    const sandbox = fixture(t, mode, config)
    const result = sandbox.run([], mode === 'runtime' ? { ALIBABA_CLOUD_ACCESS_KEY_ID: 'env-id', ALIBABA_CLOUD_ACCESS_KEY_SECRET: 'env-secret' } : {})
    assert.equal(result.status, 0, result.stderr)
    const receipt = JSON.parse(readFileSync(join(sandbox.root, 'work/shared-leaderboards/deployment.json'), 'utf8'))
    assert.equal(receipt.functionName, 'ai-benchgauge')
    assert.equal(receipt.endpoint, 'https://example.invalid')
    const request = JSON.parse(readFileSync(join(sandbox.root, 'request.json'), 'utf8'))
    assert.equal(request.operation, ['new', 'trigger-new'].includes(mode) ? 'create' : 'update')
    assert.equal(request.body.environmentVariables.STORAGE_CREDENTIAL_SOURCE, mode === 'runtime' ? 'environment' : 'role')
    assert.equal(request.body.role, mode === 'runtime' ? '' : role.roleArn)
    const timer = JSON.parse(readFileSync(join(sandbox.root, 'models-dev-sync.json'), 'utf8'))
    assert.equal(timer.name, 'ai-benchgauge')
    assert.equal(timer.triggerName, 'models-dev-sync')
    assert.equal(timer.operation, ['new', 'trigger-new'].includes(mode) ? 'create' : 'update')
    const timerConfig = JSON.parse(timer.body.triggerConfig)
    assert.equal(timerConfig.enable, true)
    assert.equal(timerConfig.cronExpression, '0 0 0 * * *')
    assert.deepEqual(JSON.parse(timerConfig.payload), { type: 'models-dev-sync', token: request.body.environmentVariables.MODELS_DEV_SYNC_TOKEN })
    const fill = JSON.parse(readFileSync(join(sandbox.root, 'models-dev-fill.json'), 'utf8'))
    assert.equal(fill.operation, timer.operation)
    assert.equal(fill.triggerName, 'models-dev-fill')
    const fillConfig = JSON.parse(fill.body.triggerConfig)
    assert.equal(fillConfig.enable, true)
    assert.equal(fillConfig.cronExpression, '0 * * * * *')
    assert.deepEqual(JSON.parse(fillConfig.payload), { type: 'models-dev-fill', token: request.body.environmentVariables.MODELS_DEV_SYNC_TOKEN })
    assert.match(request.body.environmentVariables.MODELS_DEV_SYNC_TOKEN, /^[A-Za-z0-9_-]{43}$/)
    assert.ok(!JSON.stringify(receipt).includes('secret'))
    assert.equal(Buffer.from(request.body.code.zipFile, 'base64').toString(), 'isolated archive')
  }
  const packaged = fixture(t, 'update', null)
  const result = packaged.run(['--package'])
  assert.equal(result.status, 0, result.stderr)
  assert.ok(existsSync(result.stdout.trim()))
  for (const config of [{}, role, { runtimeCredentialsFunction: 'runtime', runtimeIdentityName: 'fixture' }]) {
    const planned = fixture(t, 'update', config).run(['--plan'])
    assert.equal(planned.status, 0, planned.stderr)
    const plan = JSON.parse(planned.stdout)
    assert.equal(plan.runtime, 'custom.debian10')
    assert.equal(plan.snapshotExpiry, null)
  }
})

test('deployment CLI rejects failed checks, source changes and cloud errors without an upload receipt', t => {
  const cases = [
    ['usage', role, ['--wrong'], /Usage/], ['usage', role, ['--plan', '--package'], /Usage/],
    ['missing-config', null, [], /Create/], ['validation-failed', role, [], /failed/],
    ['validation-changed', role, [], /during validation/], ['npm-failed', role, [], /failed/],
    ['packaging-changed', role, [], /during packaging/],
    ['missing-credentials', { ...role, credentialsFile: undefined }, [], /Missing deployment credentials/],
    ['identity-failed', role, [], /IdentityFailed/], ['opaque-failure', role, [], /Deployment failed/],
    ['no-bucket', { roleArn: role.roleArn, credentialsFile: 'credentials.env' }, [], /existing OSS/],
    ['no-runtime', { bucket: role.bucket, credentialsFile: 'credentials.env' }, [], /runtime credential/],
    ['upload-changed', role, [], /before cloud upload/], ['lookup-failed', role, [], /Denied/],
    ['unrelated', role, [], /unrelated function/], ['trigger-failed', role, [], /DeniedTrigger/],
    ['trigger-empty', role, [], /HTTPS URL/], ['trigger-http', role, [], /HTTPS URL/],
    ['invalid-sync-token', role, [], /Invalid metadata sync token/],
    ['timer-failed', role, [], /TimerDenied/], ['timer-wrong', role, [], /Unrelated metadata trigger/],
    ['fill-wrong', role, [], /Unrelated metadata trigger/],
  ]
  for (const [mode, config, args, message] of cases) {
    const sandbox = fixture(t, mode, config), result = sandbox.run(args)
    assert.equal(result.status, 1, `${mode}: ${result.stderr}`)
    assert.match(result.stderr, message, mode)
    assert.equal(existsSync(join(sandbox.root, 'work/shared-leaderboards/deployment.json')), false)
  }
})

test('collector deployment keeps credentials local and configures only a verified fixed collector', t => {
  for (const mode of ['update', 'collector-new', 'existing-tokens']) {
    const sandbox = fixture(t, mode, { ...role, arenaCollector: true }), result = sandbox.run()
    assert.equal(result.status, 0, result.stderr)
    const collector = JSON.parse(readFileSync(join(sandbox.root, 'collector.json'), 'utf8'))
    assert.equal(collector.operation, mode === 'collector-new' ? 'create' : 'update')
    assert.equal(collector.body.runtime, 'custom.debian10')
    assert.deepEqual(Object.keys(collector.body.environmentVariables), ['ARENA_COLLECTOR_TOKEN'])
    assert.match(collector.body.environmentVariables.ARENA_COLLECTOR_TOKEN, /^[A-Za-z0-9_-]{43}$/)
    const main = JSON.parse(readFileSync(join(sandbox.root, 'request.json'), 'utf8'))
    assert.equal(main.body.environmentVariables.ARENA_COLLECTOR_ENDPOINT, 'https://collector.ap-southeast-1.fcapp.run')
    assert.equal(main.body.environmentVariables.ARENA_COLLECTOR_TOKEN, collector.body.environmentVariables.ARENA_COLLECTOR_TOKEN)
    assert.ok(!JSON.stringify(collector).includes('file-secret'))
  }
  for (const [mode, message] of [
    ['invalid-collector-token', /Invalid local collector token/], ['collector-lookup-failed', /CollectorDenied/],
    ['collector-unrelated', /unrelated collector/], ['collector-runtime', /unrelated collector/],
    ['collector-trigger-failed', /CollectorTriggerDenied/], ['collector-url-empty', /Invalid collector endpoint/],
    ['collector-url-http', /Invalid collector endpoint/], ['collector-url-host', /Invalid collector endpoint/],
  ]) {
    const sandbox = fixture(t, mode, { ...role, arenaCollector: true }), result = sandbox.run()
    assert.equal(result.status, 1, `${mode}: ${result.stderr}`)
    assert.match(result.stderr, message)
    assert.equal(existsSync(join(sandbox.root, 'work/shared-leaderboards/deployment.json')), false)
    assert.equal(existsSync(join(sandbox.root, 'request.json')), false)
  }
})

test('OpenRouter key is server-only, existing configuration survives redeployment, and a deliberate environment override wins', t => {
  for (const [mode, supplied, expected] of [['openrouter-existing', {}, 'fixture-existing-key'], ['openrouter-existing', { OPENROUTER_API_KEY: 'fixture-new-key' }, 'fixture-new-key'], ['new', { OPENROUTER_API_KEY: 'fixture-new-key' }, 'fixture-new-key'], ['update', {}, undefined]]) {
    const sandbox = fixture(t, mode, role); const result = sandbox.run([], supplied);
    assert.equal(result.status, 0, result.stderr);
    const request = JSON.parse(readFileSync(join(sandbox.root, 'request.json'), 'utf8'));
    assert.equal(request.body.environmentVariables.OPENROUTER_API_KEY, expected);
    assert.ok(!result.stdout.includes('fixture-new-key') && !result.stderr.includes('fixture-existing-key'));
    assert.ok(!readFileSync(join(sandbox.root, 'work/shared-leaderboards/deployment.json'), 'utf8').includes('fixture-new-key'));
  }
});
