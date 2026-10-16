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

const runtimeFiles = ['package.json', 'package-lock.json', 'bootstrap', 'server.mjs', 'service.mjs', 'domain.mjs', 'parser.mjs', 'model-openness.mjs', 'source-logos.mjs', 'oss-store.mjs', 'brands.mjs', 'brand-catalog.json', 'leaderboard-policy.json', 'countries.mjs', 'country-catalog.json']
function fixture(t, mode, config) {
  const root = realpathSync(mkdtempSync(join(tmpdir(), 'benchgauge-cloud-boundary-')))
  t.after(() => rmSync(root, { recursive: true, force: true }))
  mkdirSync(join(root, 'Scripts')); mkdirSync(join(root, 'fc'))
  copyFileSync(new URL('./deploy-shared-leaderboards.mjs', import.meta.url), join(root, 'Scripts/deploy-shared-leaderboards.mjs'))
  for (const name of runtimeFiles) writeFileSync(join(root, 'fc', name), name === 'package.json' ? '{}' : 'fixture ' + name)
  if (config) writeFileSync(join(root, '.benchgauge-cloud.local.json'), JSON.stringify(config))
  writeFileSync(join(root, 'credentials.env'), '# no credential in this line\nALIBABA_CLOUD_ACCESS_KEY_ID="file-id"\nALIBABA_CLOUD_ACCESS_KEY_SECRET=\'file-secret\'\n')
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
for (const name of ['GetFunctionRequest','InputCodeLocation','CustomRuntimeConfig','UpdateFunctionRequest','UpdateFunctionInput','CreateFunctionRequest','CreateFunctionInput','CreateTriggerRequest','CreateTriggerInput']) {
  exports[name] = class {constructor(value) {Object.assign(this,value)}};
}
exports.default = class {
  async getFunction(name) {
    if (name === 'runtime') return {body:{environmentVariables:{ALIBABA_CLOUD_ACCESS_KEY_ID:'runtime-id',ALIBABA_CLOUD_ACCESS_KEY_SECRET:'runtime-secret',ALIBABA_CLOUD_SECURITY_TOKEN:'runtime-token'}}};
    if (mode === 'lookup-failed') throw {code:'Denied'};
    if (mode === 'new' || mode === 'trigger-new') throw {code:'FunctionNotFound'};
    return {body:{description:mode === 'unrelated' ? 'someone else' : 'BenchGauge shared leaderboards (managed by ai-benchgauge)'}};
  }
  async updateFunction(name, request) {fs.writeFileSync(${JSON.stringify(join(root, 'request.json'))},JSON.stringify({name,operation:'update',body:request.body}))}
  async createFunction(request) {fs.writeFileSync(${JSON.stringify(join(root, 'request.json'))},JSON.stringify({operation:'create',body:request.body}))}
  async getTrigger() {
    if (mode === 'trigger-new') throw {code:'TriggerNotFound'};
    if (mode === 'trigger-failed') throw {code:'DeniedTrigger'};
    return {body:mode === 'trigger-empty' ? {} : {httpTrigger:{urlInternet:mode === 'trigger-http' ? 'http://example.invalid/' : 'https://example.invalid/'}}};
  }
  async createTrigger() {return {body:{httpTrigger:{urlInternet:'https://example.invalid/'}}}}
};`,
  }
  for (const [name, source] of Object.entries(packages)) {
    const directory = join(root, 'fc/node_modules', name)
    mkdirSync(directory, { recursive: true }); writeFileSync(join(directory, 'index.js'), source)
  }
  return { root, run(args = [], env = {}) {
    const environment = { ...process.env }
    for (const key of ['ALIBABA_CLOUD_ACCESS_KEY_ID', 'ALIBABA_CLOUD_ACCESS_KEY_SECRET', 'ALIBABA_CLOUD_SECURITY_TOKEN']) delete environment[key]
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
    ['missing-credentials', { ...role, credentialsFile: undefined }, [], /Missing Alibaba/],
    ['identity-failed', role, [], /IdentityFailed/], ['opaque-failure', role, [], /Deployment failed/],
    ['no-bucket', { roleArn: role.roleArn, credentialsFile: 'credentials.env' }, [], /existing OSS/],
    ['no-runtime', { bucket: role.bucket, credentialsFile: 'credentials.env' }, [], /runtime credential/],
    ['upload-changed', role, [], /before cloud upload/], ['lookup-failed', role, [], /Denied/],
    ['unrelated', role, [], /unrelated function/], ['trigger-failed', role, [], /DeniedTrigger/],
    ['trigger-empty', role, [], /HTTPS URL/], ['trigger-http', role, [], /HTTPS URL/],
  ]
  for (const [mode, config, args, message] of cases) {
    const sandbox = fixture(t, mode, config), result = sandbox.run(args)
    assert.equal(result.status, 1, `${mode}: ${result.stderr}`)
    assert.match(result.stderr, message, mode)
    assert.equal(existsSync(join(sandbox.root, 'work/shared-leaderboards/deployment.json')), false)
  }
})
