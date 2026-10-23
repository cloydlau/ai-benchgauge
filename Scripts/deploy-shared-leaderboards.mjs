import { createRequire } from 'node:module';
import { createHash, randomBytes } from 'node:crypto';
import { cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const managedDescription = 'BenchGauge shared leaderboards (managed by ai-benchgauge)';

export function isManagedFunction(existing, config) {
  if (existing.description === managedDescription) return true;
  // The existing BenchGauge deployment uses the repository name as its label.
  // Require the dedicated function, runtime and already verified OSS bucket as well.
  return existing.description === 'ai-benchgauge'
    && config.functionName === 'ai-benchgauge'
    && existing.runtime === 'custom.debian10'
    && Boolean(config.bucket) && existing.environmentVariables?.OSS_BUCKET === config.bucket;
}

export function deploymentConfiguration(value) {
  const region = value.region ?? 'cn-shenzhen';
  const functionName = value.functionName ?? 'ai-benchgauge';
  if (!/^cn-[a-z]+$/.test(region) || !/^[a-z][a-z0-9-]{2,63}$/.test(functionName)) throw new Error('Invalid deployment name or region');
  if (value.bucket && !/^[a-z][a-z0-9-]{2,62}$/.test(value.bucket)) throw new Error('Invalid OSS bucket');
  if (value.roleArn && !/^acs:ram::[0-9]+:role\/[a-zA-Z0-9.-]+$/.test(value.roleArn)) throw new Error('Invalid FC execution role ARN');
  if (value.runtimeCredentialsFunction && !/^[a-z][a-z0-9-]{2,63}$/.test(value.runtimeCredentialsFunction)) throw new Error('Invalid runtime credentials function');
  if (value.runtimeCredentialsFunction && !/^[a-zA-Z0-9.@_-]{1,64}$/.test(value.runtimeIdentityName ?? '')) throw new Error('Specify the existing runtime RAM user name');
  if (value.roleArn && value.runtimeCredentialsFunction) throw new Error('Choose one runtime credential source');
  if (value.proxy && new URL(value.proxy).protocol !== 'http:') throw new Error('Expected an HTTP proxy URL');
  return { ...value, region, functionName };
}
export async function existingRuntimeCredentials(client, FC, config, account, verifyIdentity) {
  const environment = (await client.getFunction(config.runtimeCredentialsFunction, new FC.GetFunctionRequest())).body.environmentVariables ?? {};
  const accessKeyId = environment.ALIBABA_CLOUD_ACCESS_KEY_ID;
  const accessKeySecret = environment.ALIBABA_CLOUD_ACCESS_KEY_SECRET;
  if (!accessKeyId || !accessKeySecret) throw new Error('Existing function has no runtime cloud credentials');
  const auth = { accessKeyId, accessKeySecret,
    ...(environment.ALIBABA_CLOUD_SECURITY_TOKEN && { securityToken: environment.ALIBABA_CLOUD_SECURITY_TOKEN }) };
  const identity = await verifyIdentity(auth);
  if (identity.accountId !== account || identity.arn !== `acs:ram::${account}:user/${config.runtimeIdentityName}`) {
    throw new Error('Existing runtime credentials do not match the configured RAM user and account');
  }
  return { auth, environmentVariables: { STORAGE_CREDENTIAL_SOURCE: 'environment',
    ALIBABA_CLOUD_ACCESS_KEY_ID: accessKeyId, ALIBABA_CLOUD_ACCESS_KEY_SECRET: accessKeySecret,
    ...(auth.securityToken && { ALIBABA_CLOUD_SECURITY_TOKEN: auth.securityToken }) } };
}
export async function checkExistingBucket(oss, bucket, region, account) {
  const info = (await oss.getBucketInfo(bucket)).bucket;
  if (info.Location !== `oss-${region}` || info.Owner?.ID !== account || info.AccessControlList?.Grant !== 'private' || info.StorageClass !== 'Standard') {
    throw new Error('Use a private Standard OSS bucket in the function account and region');
  }
  const versioning = await oss.getBucketVersioning(bucket);
  if (versioning.versionStatus === 'Enabled' || versioning.versionStatus === 'Suspended') throw new Error('Use a new unversioned OSS bucket for append coordination and latest-only snapshots');
  let lifecycle = { rules: [] };
  try { lifecycle = await oss.getBucketLifecycle(bucket); }
  catch (error) { if (error.code !== 'NoSuchLifecycle') throw error; }
  if (lifecycle.rules?.some(rule => !rule.prefix || 'benchgauge/'.startsWith(rule.prefix) || rule.prefix.startsWith('benchgauge/'))) {
    throw new Error('OSS lifecycle rules must not expire shared snapshots or coordination');
  }
}
function run(command, args, cwd = root) {
  const result = spawnSync(command, args, { cwd, stdio: 'inherit' });
  if (result.status !== 0) throw new Error(`${command} failed`);
}
function credentials(file) {
  const values = file ? Object.fromEntries(readFileSync(resolve(root, file), 'utf8').split('\n').flatMap(line => {
    const match = /^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$/.exec(line);
    return match ? [[match[1], match[2].replace(/^["']|["']$/g, '')]] : [];
  })) : {};
  const accessKeyId = process.env.ALIBABA_CLOUD_ACCESS_KEY_ID ?? values.ALIBABA_CLOUD_ACCESS_KEY_ID;
  const accessKeySecret = process.env.ALIBABA_CLOUD_ACCESS_KEY_SECRET ?? values.ALIBABA_CLOUD_ACCESS_KEY_SECRET;
  if (!accessKeyId || !accessKeySecret) throw new Error('Missing Alibaba Cloud RAM credentials in the local environment');
  return { accessKeyId, accessKeySecret };
}
const runtimeFiles = ['package.json', 'package-lock.json', 'bootstrap', 'server.mjs', 'service.mjs', 'domain.mjs', 'parser.mjs', 'openrouter-usage.mjs', 'epoch-eci.mjs', 'arena-dataset.mjs', 'arena-collector.mjs', 'arena-attribution.json', 'models-dev.mjs', 'models-dev-license.txt', 'model-openness.mjs', 'source-logos.mjs', 'oss-store.mjs', 'brands.mjs', 'brand-catalog.json', 'leaderboard-policy.json', 'countries.mjs', 'country-catalog.json'];
function runtimeSignature() {
  const hash = createHash('sha256');
  for (const name of runtimeFiles) hash.update(name).update(readFileSync(join(root, 'fc', name)));
  return hash.digest('hex');
}
export function packageCode() {
  const directory = join(root, 'work/shared-leaderboards');
  mkdirSync(directory, { recursive: true });
  const packageDirectory = mkdtempSync(join(directory, 'package-'));
  for (const name of runtimeFiles) cpSync(join(root, 'fc', name), join(packageDirectory, name));
  run('npm', ['ci', '--omit=dev', '--include=optional', '--ignore-scripts', '--os=linux', '--cpu=x64', '--libc=glibc', '--no-audit', '--no-fund'], packageDirectory);
  const archive = join(directory, `code-${Date.now()}.zip`);
  run('/usr/bin/zip', ['-q', '-r', archive, '.'], packageDirectory);
  return archive;
}
async function main() {
  const args = process.argv.slice(2);
  if (args.length > 1 || args.some(arg => !['--plan', '--package'].includes(arg))) throw new Error('Usage: deploy-shared-leaderboards.mjs [--plan | --package]');
  if (args.includes('--package')) {
    run(process.execPath, ['--test', 'Scripts/openrouter-usage.test.mjs', 'Scripts/epoch-eci.test.mjs', 'Scripts/arena-dataset.test.mjs', 'Scripts/models-dev.test.mjs', 'Scripts/shared-leaderboards.test.mjs', 'Scripts/brand-discovery.test.mjs', 'Scripts/country-discovery.test.mjs']);
    console.log(packageCode()); return;
  }
  const file = join(root, '.benchgauge-cloud.local.json');
  if (!existsSync(file)) throw new Error('Create .benchgauge-cloud.local.json; see docs/shared-leaderboards.md');
  const config = deploymentConfiguration(JSON.parse(readFileSync(file, 'utf8')));
  if (process.argv.includes('--plan')) {
    console.log(JSON.stringify({ region: config.region, functionName: config.functionName,
      bucket: config.bucket ?? '(existing bucket required)', runtime: 'custom.debian10',
      credentialSource: config.runtimeCredentialsFunction ?? config.roleArn ?? '(existing identity required)',
      snapshotExpiry: null, refreshIntervalSeconds: 1800, grantLifetimeSeconds: 90 })); return;
  }
  // Test the exact working tree before packaging. Cloud credentials are never
  // placed in the ZIP or the app. Existing runtime credentials are transferred
  // in memory between FC configurations, never written into local artifacts.
  const signature = runtimeSignature();
  run(process.execPath, ['--test', 'Scripts/openrouter-usage.test.mjs', 'Scripts/epoch-eci.test.mjs', 'Scripts/arena-dataset.test.mjs', 'Scripts/models-dev.test.mjs', 'Scripts/shared-leaderboards.test.mjs', 'Scripts/brand-discovery.test.mjs', 'Scripts/country-discovery.test.mjs']);
  if (runtimeSignature() !== signature) throw new Error('Runtime changed during validation');
  const archive = packageCode();
  if (runtimeSignature() !== signature) throw new Error('Runtime changed during packaging');
  const require = createRequire(join(root, 'fc/package.json'));
  const { Config } = require('@alicloud/openapi-client');
  const FC = require('@alicloud/fc20230330');
  const STS = require('@alicloud/sts20150401');
  const OSS = require('ali-oss');
  const auth = credentials(config.credentialsFile);
  const proxy = config.proxy ? { httpProxy: config.proxy, httpsProxy: config.proxy } : {};
  const common = { ...auth, ...proxy, connectTimeout: 30000, readTimeout: 60000 };
  console.log('[shared] Checking cloud identity');
  const identity = await new STS.default(new Config({ ...common, endpoint: `sts.${config.region}.aliyuncs.com` })).getCallerIdentity();
  const account = identity.body.accountId;
  const bucket = config.bucket;
  if (!bucket) throw new Error('Specify the existing OSS bucket; this script does not create buckets');
  if (!config.roleArn && !config.runtimeCredentialsFunction) throw new Error('Specify an existing runtime credential function or execution role');
  const client = new FC.default(new Config({ ...common, endpoint: `${account}.${config.region}.fc.aliyuncs.com` }));
  const runtime = config.runtimeCredentialsFunction
    ? await existingRuntimeCredentials(client, FC, config, account, async credentials =>
      (await new STS.default(new Config({ ...common, ...credentials, endpoint: `sts.${config.region}.aliyuncs.com` })).getCallerIdentity()).body)
    : { auth, environmentVariables: { STORAGE_CREDENTIAL_SOURCE: 'role' } };
  const oss = new OSS({ accessKeyId: runtime.auth.accessKeyId, accessKeySecret: runtime.auth.accessKeySecret,
    ...(runtime.auth.securityToken && { stsToken: runtime.auth.securityToken }),
    region: `oss-${config.region}`, secure: true, timeout: 10000,
    ...(config.proxy ? { proxy: config.proxy } : {}) });
  console.log('[shared] Checking dedicated OSS bucket');
  await checkExistingBucket(oss, bucket, config.region, account);
  const description = managedDescription;
  if (runtimeSignature() !== signature) throw new Error('Runtime changed before cloud upload');
  const collectorEnvironment = {};
  const syncTokenFile = join(root, 'work/shared-leaderboards/models-dev-sync-token');
  if (!existsSync(syncTokenFile)) writeFileSync(syncTokenFile, randomBytes(32).toString('base64url'), { mode: 0o600 });
  const syncToken = readFileSync(syncTokenFile, 'utf8');
  if (!/^[A-Za-z0-9_-]{43}$/.test(syncToken)) throw new Error('Invalid metadata sync token');
  if (config.arenaCollector === true) {
    // The fixed-source collector serves Arena, models.dev and OpenRouter usage.
    // OSS/cloud credentials stay in the main function. OpenRouter's API key is
    // sent only with its authenticated HTTPS usage request, never stored here.
    const tokenFile = join(root, 'work/shared-leaderboards/arena-collector-token');
    if (!existsSync(tokenFile)) writeFileSync(tokenFile, randomBytes(32).toString('base64url'), { mode: 0o600 });
    const token = readFileSync(tokenFile, 'utf8');
    if (!/^[A-Za-z0-9_-]{43}$/.test(token)) throw new Error('Invalid local collector token');
    const collectorName = `${config.functionName}-arena-dataset`;
    const collectorDescription = 'BenchGauge official Arena dataset collector (managed by ai-benchgauge)';
    const collector = new FC.default(new Config({ ...common, endpoint: `${account}.ap-southeast-1.fc.aliyuncs.com` }));
    const input = { description: collectorDescription,
      code: new FC.InputCodeLocation({ zipFile: readFileSync(archive).toString('base64') }),
      runtime: 'custom.debian10', handler: 'index.handler', memorySize: 512, cpu: 0.25,
      diskSize: 512, timeout: 25, instanceConcurrency: 8, internetAccess: true,
      customRuntimeConfig: new FC.CustomRuntimeConfig({ command: ['/var/fc/lang/nodejs20/bin/node', '/code/arena-collector.mjs'], port: 9000 }),
      environmentVariables: { ARENA_COLLECTOR_TOKEN: token } };
    let prior;
    try { prior = (await collector.getFunction(collectorName, new FC.GetFunctionRequest())).body; }
    catch (error) { if (error.code !== 'FunctionNotFound') throw error; }
    if (prior) {
      if (prior.description !== collectorDescription || prior.runtime !== 'custom.debian10') throw new Error('Refusing unrelated collector');
      await collector.updateFunction(collectorName, new FC.UpdateFunctionRequest({ body: new FC.UpdateFunctionInput(input) }));
    } else await collector.createFunction(new FC.CreateFunctionRequest({ body: new FC.CreateFunctionInput({ ...input, functionName: collectorName }) }));
    let trigger;
    try { trigger = (await collector.getTrigger(collectorName, 'http')).body; }
    catch (error) {
      if (error.code !== 'TriggerNotFound') throw error;
      trigger = (await collector.createTrigger(collectorName, new FC.CreateTriggerRequest({ body: new FC.CreateTriggerInput({
        triggerName: 'http', triggerType: 'http', triggerConfig: JSON.stringify({ authType: 'anonymous', methods: ['GET'], disableURLInternet: false }) }) }))).body;
    }
    const endpoint = trigger.httpTrigger?.urlInternet?.replace(/\/$/, '');
    if (!endpoint || new URL(endpoint).protocol !== 'https:' || !new URL(endpoint).hostname.endsWith('.ap-southeast-1.fcapp.run')) throw new Error('Invalid collector endpoint');
    Object.assign(collectorEnvironment, { ARENA_COLLECTOR_ENDPOINT: endpoint, ARENA_COLLECTOR_TOKEN: token });
    console.log('[shared] Singapore Arena dataset collector updated');
  }
  const body = { description, code: new FC.InputCodeLocation({ zipFile: readFileSync(archive).toString('base64') }),
    runtime: 'custom.debian10', handler: 'index.handler', memorySize: 512, cpu: 0.25,
    diskSize: 512, timeout: 30, instanceConcurrency: 8, internetAccess: true, role: config.roleArn ?? '',
    customRuntimeConfig: new FC.CustomRuntimeConfig({ command: ['/code/bootstrap'], port: 9000 }),
    environmentVariables: { OSS_BUCKET: bucket, OSS_REGION: `oss-${config.region}`, ...runtime.environmentVariables, ...collectorEnvironment, MODELS_DEV_SYNC_TOKEN: syncToken } };
  let existing;
  try { existing = (await client.getFunction(config.functionName, new FC.GetFunctionRequest())).body; }
  catch (error) { if (error.code !== 'FunctionNotFound') throw error; }
  if (existing) {
    if (!isManagedFunction(existing, config)) throw new Error('Refusing to replace an unrelated function');
    const openRouterKey = process.env.OPENROUTER_API_KEY?.trim() || existing.environmentVariables?.OPENROUTER_API_KEY;
    if (openRouterKey) body.environmentVariables.OPENROUTER_API_KEY = openRouterKey;
    await client.updateFunction(config.functionName, new FC.UpdateFunctionRequest({ body: new FC.UpdateFunctionInput(body) }));
  } else {
    if (process.env.OPENROUTER_API_KEY?.trim()) body.environmentVariables.OPENROUTER_API_KEY = process.env.OPENROUTER_API_KEY.trim();
    await client.createFunction(new FC.CreateFunctionRequest({ body: new FC.CreateFunctionInput({ ...body, functionName: config.functionName }) }));
  }
  let trigger;
  try { trigger = (await client.getTrigger(config.functionName, 'http')).body; }
  catch (error) {
    if (error.code !== 'TriggerNotFound') throw error;
    trigger = (await client.createTrigger(config.functionName, new FC.CreateTriggerRequest({ body: new FC.CreateTriggerInput({
      triggerName: 'http', triggerType: 'http', triggerConfig: JSON.stringify({ authType: 'anonymous', methods: ['GET', 'POST'], disableURLInternet: false }) }) }))).body;
  }
  const endpoint = trigger.httpTrigger?.urlInternet?.replace(/\/$/, '');
  if (!endpoint?.startsWith('https://')) throw new Error('HTTP trigger did not return an HTTPS URL');
  for (const [triggerName, cronExpression] of [['models-dev-sync', '0 0 0 * * *'], ['models-dev-fill', '0 * * * * *']]) {
    const triggerConfig = JSON.stringify({ enable: true, cronExpression,
      payload: JSON.stringify({ type: triggerName, token: syncToken }) });
    let timer;
    try { timer = (await client.getTrigger(config.functionName, triggerName)).body; }
    catch (error) { if (error.code !== 'TriggerNotFound') throw error; }
    if (timer) {
      if (timer.triggerType !== 'timer') throw new Error('Unrelated metadata trigger');
      await client.updateTrigger(config.functionName, triggerName, new FC.UpdateTriggerRequest({ body: new FC.UpdateTriggerInput({ triggerConfig }) }));
    } else await client.createTrigger(config.functionName, new FC.CreateTriggerRequest({ body: new FC.CreateTriggerInput({
      triggerName, triggerType: 'timer', triggerConfig }) }));
  }
  console.log('[shared] Models.dev daily checks and minute gap worker configured');
  // Save only non-secret deployment details. The caller must smoke-test the
  // read endpoint before enabling the embedded shared client endpoint.
  const receipt = { region: config.region, functionName: config.functionName, bucket, endpoint, deployedAt: new Date().toISOString() };
  writeFileSync(join(root, 'work/shared-leaderboards/deployment.json'), JSON.stringify(receipt, null, 2) + '\n');
  console.log(JSON.stringify(receipt));
  console.log('Verify GET /v1/boards/{kind}; refresh Arena through the official dataset loader and seed other sources through a grant before enabling clients.');
}
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch(error => { console.error(`[shared] ${error.code ?? error.message ?? 'Deployment failed'}`); process.exitCode = 1; });
}
