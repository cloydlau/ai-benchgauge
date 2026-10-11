import { spawn, spawnSync } from 'node:child_process'
import { createHash, randomUUID } from 'node:crypto'
import { closeSync, cpSync, existsSync, mkdirSync, openSync, readFileSync, renameSync, rmSync, statSync, watch as watchFiles, writeFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

export const root = resolve(import.meta.dirname, '..')
const script = fileURLToPath(import.meta.url)
export const bundleID = 'com.cloydlau.ai-benchgauge.ipad'
export function readJSON(file) {
  try { return JSON.parse(readFileSync(file, 'utf8')) }
  catch (error) { if (error.code === 'ENOENT') return null; throw error }
}
export function writeJSON(file, value) {
  const temporary = `${file}.${randomUUID()}.tmp`
  try { writeFileSync(temporary, JSON.stringify(value, null, 2) + '\n', { mode: 0o600 }); renameSync(temporary, file) }
  finally { rmSync(temporary, { force: true }) }
}
export function deploymentPaths(projectRoot) {
  const directory = resolve(projectRoot, 'work/ios-deploy')
  mkdirSync(directory, { recursive: true })
  return { directory, config: resolve(projectRoot, '.benchgauge-ios.local.json'), checkpoint: resolve(directory, 'checked-source.json'),
    request: resolve(directory, 'request.json'), receipt: resolve(directory, 'installed.json'), status: resolve(directory, 'status.json'),
    built: resolve(directory, 'built.json'), lock: resolve(directory, 'worker.lock'), log: resolve(directory, 'deploy.log'),
    mobileCheck: resolve(directory, 'mobile-check.json'), project: resolve(directory, 'Project/AI-BenchGauge.xcodeproj'),
    app: resolve(directory, 'DerivedData/Build/Products/Debug-iphoneos/AI BenchGauge.app') }
}
export function configuration(paths) {
  const config = readJSON(paths.config)
  if (!config || config.enabled === false) return null
  if (!/^[a-zA-Z0-9-]+$/.test(config.device || '')) throw new Error('本机 iOS 配置需要明确的 device 标识')
  if (!/^[A-Z0-9]{10}$/.test(config.team || '')) throw new Error('本机 iOS 配置需要明确的 Apple Developer team 标识')
  const developerDir = config.developerDir || '/Applications/Xcode.app/Contents/Developer'
  if (!existsSync(resolve(developerDir, 'usr/bin/xcodebuild'))) throw new Error('本机 iOS 配置没有指向完整 Xcode')
  return { ...config, developerDir, launchAfterInstall: config.launchAfterInstall !== false }
}
export function claimWorker(lock, pid = process.pid, alive = workerAlive) {
  try { mkdirSync(lock) }
  catch (error) {
    if (error.code !== 'EEXIST') throw error
    const owner = readJSON(resolve(lock, 'owner.json'))
    if (owner ? alive(owner.pid) : Date.now() - statSync(lock).mtimeMs < 10_000) return null
    rmSync(lock, { recursive: true, force: true })
    try { mkdirSync(lock) } catch (error) { if (error.code === 'EEXIST') return null; throw error }
  }
  const token = randomUUID()
  writeJSON(resolve(lock, 'owner.json'), { pid, token })
  return () => {
    if (readJSON(resolve(lock, 'owner.json'))?.token === token) rmSync(lock, { recursive: true, force: true })
  }
}
function processAlive(pid) {
  if (!Number.isInteger(pid) || pid <= 1) return false
  try { process.kill(pid, 0); return true } catch (error) { return error.code === 'EPERM' }
}
function workerAlive(pid) {
  if (!processAlive(pid)) return false
  const result = spawnSync('ps', ['-p', String(pid), '-o', 'command='], { encoding: 'utf8', timeout: 1500 })
  return result.status === 0 && result.stdout.includes(script) && /\bwatch\b/.test(result.stdout)
}
export function availableDevice(data, identifier) {
  return data?.result?.devices?.find(device => {
    const hardware = device.properties?.hardware || device.hardwareProperties || {}
    const connection = device.properties?.connection || device.connectionProperties || {}
    const state = connection.state || connection.tunnelState
    return (device.identifier === identifier || hardware.udid === identifier)
      && hardware.reality === 'physical' && hardware.platform === 'iOS'
      && connection.pairingState === 'paired' && state && state !== 'unavailable'
  })
}
export async function sourceFingerprint() {
  const { ci } = await import('./calmmit.mjs')
  const { readSourceFingerprint } = await ci.load('dev-source')
  const source = await readSourceFingerprint(root, { revision: 'working-tree', paths: ['Sources', 'Tests', 'apps/ios/App', 'apps/ios/UI',
    'apps/ios/UITests', 'apps/macos/Sources', 'apps/windows', 'assets', 'config', 'Package.swift', 'Package.resolved',
    'Scripts', '.github', 'calmmit.config.json', 'make-app.sh', 'test.sh', 'dev.sh', 'LICENSE'] })
  const config = configuration(deploymentPaths(root))
  return createHash('sha256').update(JSON.stringify([source, config?.device, config?.team, config?.developerDir])).digest('hex')
}
export async function prepareProject(paths, config) {
  const { generateIOSProject } = await import('./ios-project.mjs')
  const catalog = resolve(paths.directory, 'Assets.xcassets')
  cpSync(resolve(root, 'apps/ios/App/Assets.xcassets'), catalog, { recursive: true })
  await runCommand('swift', ['Scripts/ios-icon.swift', resolve(catalog, 'AppIcon.appiconset/AppIcon.png')],
    { env: { ...process.env, DEVELOPER_DIR: config.developerDir }, log: paths.log, timeout: 120_000 })
  generateIOSProject(root, { projectDirectory: resolve(paths.directory, 'Project'), sourceDirectory: resolve(root, 'apps/ios'),
    packageDirectory: root, logoDirectory: resolve(root, 'assets/logos'), assetDirectory: catalog, team: config.team })
}
export function deviceBuildArguments(paths, config) {
  return ['-project', paths.project, '-scheme', 'BenchGauge', '-configuration', 'Debug',
    '-destination', 'generic/platform=iOS', '-derivedDataPath', resolve(paths.directory, 'DerivedData'),
    `DEVELOPMENT_TEAM=${config.team}`, '-allowProvisioningUpdates', '-allowProvisioningDeviceRegistration', 'build']
}
export async function mobileCheck({ paths, config, fingerprint, execute = runCommand }) {
  const checked = readJSON(paths.checkpoint)?.fingerprint
  if (!checked || await fingerprint() !== checked) throw new Error('CI 检查期间源码已变化，未加入 iPhone 更新队列；请按最新源码重新检查')
  if (readJSON(paths.mobileCheck)?.fingerprint === checked) return checked
  const env = { ...process.env, DEVELOPER_DIR: config.developerDir }
  await execute(process.execPath, [script, 'prepare'], { env, log: paths.log, timeout: 120_000 })
  await execute('xcodebuild', ['-project', paths.project, '-scheme', 'BenchGauge', '-configuration', 'Debug',
    '-destination', 'generic/platform=iOS Simulator', '-derivedDataPath', resolve(paths.directory, 'CheckDerivedData'),
    'CODE_SIGNING_ALLOWED=NO', 'build'], { env, log: paths.log, timeout: 600_000 })
  if (await fingerprint() !== checked) throw new Error('iOS 构建检查期间源码已变化，请重新运行 CI')
  writeJSON(paths.mobileCheck, { fingerprint: checked })
  return checked
}
function runCommand(command, args, { env, log, signal, timeout = 60_000, capture = false } = {}) {
  return new Promise((accept, reject) => {
    const fd = capture ? null : openSync(log, 'a', 0o600)
    const child = spawn(command, args, { cwd: root, env, detached: true, stdio: ['ignore', capture ? 'pipe' : fd, capture ? 'pipe' : fd] })
    if (fd != null) closeSync(fd)
    let stdout = '', stderr = '', timedOut = false, killTimer
    if (capture) {
      child.stdout.on('data', data => { stdout += data; if (stdout.length > 8 * 1024 * 1024) stop() })
      child.stderr.on('data', data => { stderr = (stderr + data).slice(-16_000) })
    }
    const terminate = () => {
      try { process.kill(-child.pid, 'SIGTERM') } catch {}
      killTimer = setTimeout(() => { try { process.kill(-child.pid, 'SIGKILL') } catch {} }, 2000)
    }
    const stop = () => { timedOut = true; terminate() }
    const timer = setTimeout(stop, timeout)
    const onAbort = terminate
    signal?.addEventListener('abort', onAbort, { once: true })
    child.once('error', error => { clearTimeout(timer); clearTimeout(killTimer); signal?.removeEventListener('abort', onAbort); reject(error) })
    child.once('close', code => {
      clearTimeout(timer); clearTimeout(killTimer); signal?.removeEventListener('abort', onAbort)
      if (code === 0 && !timedOut && !signal?.aborted) accept(stdout)
      else reject(new Error(`${command} ${args.slice(0, 4).join(' ')} 失败${timedOut ? '（超时）' : `（${code}）`}${stderr ? '\n' + stderr : ''}`))
    })
  })
}

// One iteration is injectable so CI tests never install to a real phone.
export async function deploymentTick({ paths, config, fingerprint, execute, record, signal }) {
  const request = readJSON(paths.request)
  if (!request) return 'idle'
  const receipt = readJSON(paths.receipt)
  if (receipt?.fingerprint === request.fingerprint && receipt.device === config.device) return 'idle'
  const current = await fingerprint()
  if (current !== request.fingerprint) { record('waiting-ci', '源码已变化，等待新一轮检查通过'); return 'pending' }
  const status = readJSON(paths.status)
  if (status?.request === request.id && status.device === config.device && status.phase === 'build-failed') return 'idle'
  const env = { ...process.env, DEVELOPER_DIR: config.developerDir }
  const run = (command, args, options = {}) => execute(command, args, { env, log: paths.log, signal, ...options })
  const data = JSON.parse(await run('xcrun', ['devicectl', 'list', 'devices', '--json-output', '-', '--timeout', '10'], { capture: true, timeout: 15_000 }))
  if (!availableDevice(data, config.device)) { record('waiting-device', 'iPhone 离线，保留待更新版本，重连后自动安装'); return 'pending' }
  const build = readJSON(paths.built)
  const needsBuild = build?.fingerprint !== request.fingerprint || !existsSync(paths.app)
  if (needsBuild) {
    // A new build overwrites the bundle; invalidate any old receipt before doing so.
    rmSync(paths.built, { force: true })
    record('building', '正在为 iPhone 编译并签名')
    try {
      await run(process.execPath, [script, 'prepare'], { timeout: 120_000 })
      await run('xcodebuild', deviceBuildArguments(paths, config), { timeout: 600_000 })
      if (!existsSync(resolve(paths.app, 'embedded.mobileprovision'))) throw new Error('未生成 iPhone 开发描述文件，请先在 Xcode 完成账号和签名配置')
      await run('codesign', ['--verify', '--strict', paths.app])
      const identifier = await run('/usr/libexec/PlistBuddy', ['-c', 'Print :CFBundleIdentifier', resolve(paths.app, 'Info.plist')], { capture: true })
      if (identifier.trim() !== bundleID) throw new Error('签名产物的 Bundle ID 与 BenchGauge 不匹配')
    } catch (error) {
      if (signal?.aborted) throw error
      record('build-failed', 'iPhone 编译或签名失败；请查看日志，解决后重新触发 CI 或运行 retry', error.message)
      return 'idle'
    }
  }
  // Never install a stale or superseded candidate, even if edits arrived mid-build.
  if (await fingerprint() !== request.fingerprint || readJSON(paths.request)?.id !== request.id) {
    record('waiting-ci', '编译期间源码或队列已更新，等待最新检查通过'); return 'pending'
  }
  if (needsBuild) writeJSON(paths.built, { fingerprint: request.fingerprint })
  record('installing', '正在安装到 iPhone')
  await run('xcrun', ['devicectl', 'device', 'install', 'app', '--device', config.device, '--timeout', '60', paths.app], { timeout: 70_000 })
  // A successful installation remains delivered even if a locked phone rejects launch.
  writeJSON(paths.receipt, { fingerprint: request.fingerprint, device: config.device, installedAt: new Date().toISOString() })
  if (config.launchAfterInstall) {
    try { await run('xcrun', ['devicectl', 'device', 'process', 'launch', '--device', config.device, '--terminate-existing', '--timeout', '20', bundleID], { timeout: 25_000 }) }
    catch (error) { record('installed', '已安装；手机暂不能自动打开，请解锁后打开 BenchGauge', error.message); return 'idle' }
  }
  record('installed', '已自动更新到 iPhone' + (config.launchAfterInstall ? '并打开 BenchGauge' : ''))
  return 'idle'
}
function ensureWorker(paths) {
  const owner = readJSON(resolve(paths.lock, 'owner.json'))
  if (owner && workerAlive(owner.pid)) return
  const fd = openSync(paths.log, 'a', 0o600)
  const child = spawn(process.execPath, [script, 'watch'], { cwd: root, detached: true, stdio: ['ignore', fd, fd] })
  closeSync(fd); child.unref()
}
async function watch(paths) {
  const release = claimWorker(paths.lock)
  if (!release) return
  const controller = new AbortController()
  const stop = () => controller.abort()
  process.once('SIGINT', stop); process.once('SIGTERM', stop)
  let wake
  const changes = watchFiles(paths.directory, (_event, file) => { if (file === 'request.json') wake?.() })
  controller.signal.addEventListener('abort', () => wake?.(), { once: true })
  const record = (phase, message, error) => {
    const request = readJSON(paths.request)
    const config = readJSON(paths.config)
    const value = { phase, request: request?.id, device: config?.device, fingerprint: request?.fingerprint, message, ...(error ? { error } : {}) }
    const previous = readJSON(paths.status)
    if (previous?.phase === phase && previous?.request === value.request && previous?.device === value.device && previous?.message === message) return
    writeJSON(paths.status, { ...value, updatedAt: new Date().toISOString() })
    console.log(`[ios-deploy] ${new Date().toISOString()} ${message}${error ? '\n' + error : ''}`)
  }
  try {
    while (!controller.signal.aborted) {
      const config = configuration(paths)
      if (!config) break
      let outcome = 'pending'
      try { outcome = await deploymentTick({ paths, config, fingerprint: sourceFingerprint, execute: runCommand, record, signal: controller.signal }) }
      catch (error) { if (controller.signal.aborted) break; record('waiting-device', '安装暂未完成，将自动重试', error.message) }
      await new Promise(accept => { const timer = setTimeout(accept, outcome === 'idle' ? 60_000 : 30_000); wake = () => { clearTimeout(timer); accept() } })
      wake = null
    }
  } finally { changes.close(); release(); process.removeListener('SIGINT', stop); process.removeListener('SIGTERM', stop) }
}
async function main() {
  const paths = deploymentPaths(root)
  const command = process.argv[2]
  if (command === 'watch') { await watch(paths); return }
  if (command === 'status') { console.log(JSON.stringify(readJSON(paths.status) || { phase: 'not-enabled' }, null, 2)); return }
  if (command === 'stop') {
    const config = readJSON(paths.config)
    if (config) writeJSON(paths.config, { ...config, enabled: false })
    const owner = readJSON(resolve(paths.lock, 'owner.json'))
    if (owner && workerAlive(owner.pid)) process.kill(owner.pid, 'SIGTERM')
    console.log('[ios-deploy] 已关闭本机 iPhone 自动更新'); return
  }
  const config = configuration(paths)
  if (!config) { console.log('[ios-deploy] 本机未启用 iPhone 自动更新，跳过'); return }
  if (command === 'prepare') { await prepareProject(paths, config); return }
  if (command === 'checked') {
    const { testInputSignature } = await import('./test.mjs')
    const passed = readJSON(resolve(root, 'work/test-results/latest.json'))
    const signature = process.env.BENCHGAUGE_TEST_PASS
    if (!signature || passed?.status !== 0 || passed.signature !== signature || testInputSignature() !== signature) throw new Error('手机更新需要当前源码通过完整测试')
    await runCommand(process.execPath, ['Scripts/check-syntax.mjs'], { env: process.env, log: paths.log, timeout: 600_000 })
    const candidate = await sourceFingerprint()
    if (testInputSignature() !== signature) throw new Error('语法检查期间源码已变化，请重新验证')
    writeJSON(paths.checkpoint, { fingerprint: candidate })
  }
  const fingerprint = await sourceFingerprint()
  if (command === 'checkpoint') { writeJSON(paths.checkpoint, { fingerprint }); return }
  if (!['enqueue', 'retry', 'checked'].includes(command)) throw new Error('用法：ios-deploy.mjs checkpoint|enqueue|checked|retry|status|stop|watch|prepare')
  const { testInputSignature } = await import('./test.mjs')
  const passed = readJSON(resolve(root, 'work/test-results/latest.json'))
  if (passed?.status !== 0 || passed.signature !== testInputSignature()) throw new Error('手机更新需要当前源码通过完整测试')
  if (readJSON(paths.checkpoint)?.fingerprint !== fingerprint) throw new Error('CI 检查期间源码已变化，未加入 iPhone 更新队列；请按最新源码重新检查')
  await mobileCheck({ paths, config, fingerprint: sourceFingerprint })
  if (passed.signature !== testInputSignature()) throw new Error('iOS 构建检查期间测试依据已变化，请重新验证')
  const previous = readJSON(paths.request)
  const failed = readJSON(paths.status)?.phase === 'build-failed'
  if (previous?.fingerprint !== fingerprint || command === 'retry' || failed) writeJSON(paths.request, { id: randomUUID(), fingerprint, queuedAt: new Date().toISOString() })
  ensureWorker(paths)
  console.log('[ios-deploy] 已交给本机 iPhone 更新器；状态：node Scripts/ios-deploy.mjs status；日志：work/ios-deploy/deploy.log')
}
if (process.argv[1] && resolve(process.argv[1]) === script) {
  main().catch(error => { console.error('[ios-deploy]', error.message); process.exitCode = 1 })
}
