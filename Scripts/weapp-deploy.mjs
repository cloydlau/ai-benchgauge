import { spawn } from 'node:child_process'
import { createHash } from 'node:crypto'
import { appendFileSync, copyFileSync, existsSync, mkdirSync, readFileSync, readdirSync, renameSync, rmSync, statSync, symlinkSync, writeFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { ci } from './calmmit.mjs'
import { acquireCommitLock } from './commit-lock.mjs'
import { nodeExecutable } from './node-executable.mjs'
import { createAutoVersion } from '../apps/weapp/scripts/version.mjs'

const { readUploadConfig, createUploadConfigMonitor } = await ci.load('deployment-credentials')
const { createWatchSession } = await ci.load('deployment-watch')
const { checkPrivacyGuide } = await ci.load('privacy-guide')
const root = ci.root
const receiptPath = join(root, 'apps/weapp/.last-publish')
const log = message => console.log(`[weapp-upload] ${message}`)

// Explicit inputs only: never snapshot private keys, local settings, dist or dependencies.
export const sourcePaths = [
  'apps/weapp/src', 'apps/weapp/test', 'apps/weapp/assets', 'apps/weapp/scripts',
  'apps/weapp/vite.config.js', 'apps/weapp/postcss.config.js', 'apps/weapp/tsconfig.json',
  'apps/weapp/package.json', 'apps/weapp/project.config.json',
  'apps/weapp/ci-runtime/package.json', 'apps/weapp/ci-runtime/package-lock.json',
  'fc/domain.mjs', 'fc/distributions.mjs', 'fc/brand-catalog.json', 'fc/leaderboard-policy.json', 'fc/country-catalog.json',
  'fc/purchase-links.json', 'Scripts/generate-purchase-links.mjs',
  'Sources/LeaderboardKit/PurchaseLinkData.generated.swift',
  'assets/brand/header-logo.png', 'assets/brand/header-logo-dark.png', 'assets/logos',
  'apps/ios/UI/Resources/CategoryIcons',
  'Sources/LeaderboardKit/SharedLeaderboardConfiguration.swift', 'config/app.json',
  'Sources/LeaderboardKit/Resources/Fonts/SlideFont-OFL.txt',
  'Sources/LeaderboardKit/Resources/EpochAttribution.json',
  'Sources/LeaderboardKit/Resources/CC-BY-4.0.json',
  'Sources/LeaderboardKit/Resources/ModelDetailLabels.json',
  'Sources/LeaderboardKit/Resources/SourceTabThemes.json',
  'fc/models-dev-license.txt',
  'Tests/fixtures/model-details.json',
  'fc/arena-attribution.json',
  'LICENSE', 'package.json', 'pnpm-lock.yaml', 'pnpm-workspace.yaml',
  'Scripts/weapp-deploy.mjs', 'Scripts/sync-privacy-guide.mjs', 'privacy-guide.json',
]

export function inputSnapshot(repo = root, paths = sourcePaths) {
  const files = new Map()
  const collect = relative => {
    const path = join(repo, relative)
    const stat = statSync(path, { throwIfNoEntry: false })
    if (!stat) return
    if (stat.isDirectory()) {
      for (const name of readdirSync(path).sort()) {
        if (name.startsWith('.') || /\.(key|pem)$/.test(name) || ['node_modules', 'dist'].includes(name)) continue
        collect(`${relative}/${name}`)
      }
    } else if (stat.isFile()) files.set(relative, createHash('sha256').update(readFileSync(path)).digest('hex'))
  }
  paths.forEach(collect)
  return files
}

export function sourceSignature(files) {
  return createHash('sha256').update(JSON.stringify([...files].sort(([a], [b]) => a.localeCompare(b)))).digest('hex')
}

export function readReceipt(path = receiptPath) {
  try {
    const receipt = JSON.parse(readFileSync(path, 'utf8'))
    return receipt.schemaVersion === 1 && receipt.status === 'success' && Number.isFinite(receipt.publishedAt) ? receipt : null
  } catch { return null }
}

export function needsUpload(receipt, signature, config) {
  return config.ready && (!receipt || receipt.sourceSignature !== signature || config.keyChangedAt > receipt.publishedAt)
}

function run(command, args, { cwd = root, env = process.env } = {}) {
  return new Promise((done, reject) => {
    const child = spawn(command, args, { cwd, env, stdio: 'inherit', timeout: 600_000 })
    child.once('error', reject)
    child.once('close', code => code === 0 ? done() : reject(new Error(`${command} 退出码 ${code}`)))
  })
}

export function stageInputs(repo, destination, files) {
  mkdirSync(destination, { recursive: true })
  for (const relative of files.keys()) {
    const target = join(destination, relative)
    mkdirSync(dirname(target), { recursive: true })
    copyFileSync(join(repo, relative), target)
  }
  for (const relative of ['node_modules', 'apps/weapp/node_modules']) {
    symlinkSync(join(repo, relative), join(destination, relative), 'dir')
  }
}

async function upload() {
  const config = readUploadConfig(root)
  if (!config.ready) throw new Error(config.reason)
  const state = join(root, 'work/weapp-deploy')
  mkdirSync(state, { recursive: true })
  const lock = acquireCommitLock({ lockPath: join(state, 'upload.lock'), verifyProcessStart: true })
  if (!lock.acquired) throw new Error('已有小程序构建或上传任务，稍后再试')
  const stage = join(state, `stage-${process.pid}`)
  try {
    const files = inputSnapshot()
    const signature = sourceSignature(files)
    stageInputs(root, stage, files)
    if (sourceSignature(inputSnapshot(stage)) !== signature) throw new Error('复制期间源码发生变化，等待下一轮上传')
    checkPrivacyGuide({ root: stage, write: false })
    log('开始小程序测试与独立构建（不会改写开发中的 dist）')
    // Freeze once before building so the displayed and uploaded versions match,
    // including builds that finish after Shanghai midnight.
    const version = process.env.MP_VERSION || createAutoVersion()
    // npm runs the exact package scripts against the existing locked binaries;
    // pnpm's pre-run dependency sync cannot operate on this isolated symlink tree.
    const npm = process.platform === 'win32' ? 'npm.cmd' : 'npm'
    await run(npm, ['--prefix', join(stage, 'apps/weapp'), 'test'])
    await run(npm, ['--prefix', join(stage, 'apps/weapp'), 'run', 'build'], {
      env: { ...process.env, MP_VERSION: version, BENCHGAUGE_INVESTMENT_ROOT: root },
    })
    if (sourceSignature(inputSnapshot()) !== signature) throw new Error('构建期间源码发生变化，等待下一轮上传')
    const current = readUploadConfig(root)
    if (!current.ready || current.signature !== config.signature) throw new Error('上传配置或密钥发生变化，等待下一轮上传')
    const runtime = join(root, 'apps/weapp/ci-runtime')
    const binary = join(runtime, 'node_modules/node/bin', process.platform === 'win32' ? 'node.exe' : 'node')
    if (!existsSync(binary) || !existsSync(join(runtime, 'node_modules/miniprogram-ci/package.json'))) {
      await run(process.platform === 'win32' ? 'npm.cmd' : 'npm', ['ci', '--prefix', runtime, '--no-audit', '--no-fund'])
    }
    // Dependency installation may take minutes. Revalidate immediately before uploading.
    if (sourceSignature(inputSnapshot()) !== signature || readUploadConfig(root).signature !== config.signature) throw new Error('源码或上传配置已更新，等待下一轮上传')
    await run(binary, [join(root, 'apps/weapp/scripts/upload.mjs'), join(stage, 'apps/weapp'), config.appid, config.privateKeyPath, version])
    const receipt = { schemaVersion: 1, status: 'success', publishedAt: Date.now(), version, sourceSignature: signature }
    writeFileSync(`${receiptPath}.tmp`, `${JSON.stringify(receipt, null, 2)}\n`)
    renameSync(`${receiptPath}.tmp`, receiptPath)
    log(`微信上传成功，版本 ${version}`)
  } finally {
    rmSync(stage, { recursive: true, force: true })
    lock.release()
  }
}

export async function startWeappUploadWatch() {
  if (process.env.WEAPP_AUTOPUBLISH === '0') return () => {}
  const directory = join(root, 'work/weapp-deploy')
  mkdirSync(directory, { recursive: true })
  const lock = acquireCommitLock({ lockPath: join(directory, 'watch.lock'), verifyProcessStart: true })
  if (!lock.acquired) { log('自动上传监听已在运行，复用现有任务'); return () => {} }
  let previous = sourceSignature(inputSnapshot())
  const session = createWatchSession({
    debounceMs: Number(process.env.WEAPP_PUBLISH_DEBOUNCE_MS || 60_000),
    now: Date.now, setTimeoutFn: setTimeout, clearTimeoutFn: clearTimeout,
    autocommit: false, uploadConfig: () => readUploadConfig(root),
    log: message => log(message.replace('提交已完成，开始完整构建并发布', '开始小程序检查、构建与上传')),
    classifyFailure: output => /已有小程序构建|源码发生变化|源码或上传配置已更新|密钥发生变化/.test(output || '') ? 'retry' : 'pause',
    startPublish: (done, { env }) => {
      let output = ''
      let finished = false
      const finish = (...args) => { if (!finished) { finished = true; done(...args) } }
      const child = spawn(nodeExecutable({ env }), [fileURLToPath(import.meta.url), 'upload'], { cwd: root, env, stdio: ['ignore', 'pipe', 'pipe'] })
      const forward = stream => stream.on('data', data => {
        output = (output + data).slice(-32_000)
        appendFileSync(join(directory, 'watch.log'), data)
        process.stdout.write(data)
      })
      forward(child.stdout); forward(child.stderr)
      child.once('error', error => finish(null, error))
      child.once('close', code => finish(code, undefined, { output, logPath: 'work/weapp-deploy/watch.log' }))
    },
  })
  const monitor = createUploadConfigMonitor({ readConfig: () => readUploadConfig(root), schedule: session.schedule, log })
  if (needsUpload(readReceipt(), previous, monitor.initial)) session.schedule('发现尚未上传的小程序源码或新密钥', { publish: true })
  const timer = setInterval(() => {
    try {
      // An attached watcher follows the existing dev session's lifetime.
      const owner = Number(process.env.BENCHGAUGE_WEAPP_OWNER_PID)
      if (Number.isInteger(owner) && owner > 1) {
        try { process.kill(owner, 0) } catch (error) { if (error.code === 'ESRCH') { stop(); return } }
      }
      monitor.poll()
      const signature = sourceSignature(inputSnapshot())
      if (signature !== previous) {
        previous = signature
        if (needsUpload(readReceipt(), signature, readUploadConfig(root))) session.schedule('小程序源码已更新', { publish: true })
      }
    } catch (error) { log(`监听检查失败：${error.message}`) }
  }, 1000)
  const stop = () => { clearInterval(timer); session.stop(); lock.release() }
  process.once('exit', stop)
  log(`已监听源码和上传密钥；静默 ${Number(process.env.WEAPP_PUBLISH_DEBOUNCE_MS || 60_000) / 1000} 秒后检查、构建并上传开发版`)
  return stop
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    if (process.argv[2] === 'upload') await upload()
    else if (process.argv[2] === 'watch') {
      // Install signal handling before the watcher announces readiness. Its exit
      // listener releases the timer, session and lock when the CLI stops.
      for (const signal of ['SIGINT', 'SIGTERM']) process.once(signal, () => process.exit())
      await startWeappUploadWatch()
    } else throw new Error('用法：node Scripts/weapp-deploy.mjs upload|watch')
  } catch (error) { console.error(`[weapp-upload] ${error.message}`); process.exitCode = 1 }
}
