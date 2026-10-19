#!/usr/bin/env node
import { spawn, spawnSync } from 'node:child_process'
import { createHash } from 'node:crypto'
import { appendFileSync, copyFileSync, existsSync, lstatSync, mkdirSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from 'node:fs'
import { dirname, join, relative, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { setTimeout as delay } from 'node:timers/promises'
import { acquireCommitLock, pidState } from './commit-lock.mjs'
import { nodeExecutable } from './node-executable.mjs'
import { withBuildCache } from './build-cache.mjs'
import { prepareSwiftWorkspace } from './prepare-swift-workspace.mjs'

export const testRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..')
export const testEnvironmentKeys = ['PATH', 'DEVELOPER_DIR', 'TOOLCHAINS', 'SDKROOT', 'TZ',
  'SWIFT_EXEC', 'SWIFT_DRIVER_SWIFT_FRONTEND_EXEC', 'NODE_OPTIONS', 'LANG', 'LC_ALL']

export function testEnvironment(env = process.env, { platform = process.platform,
  xcodeDeveloperDir = '/Applications/Xcode.app/Contents/Developer', selectedDeveloperDir } = {}) {
  // The Command Line Tools SDK lacks SwiftUI's platform macro plugins. Use the
  // installed full Xcode for native tests, without changing global xcode-select.
  if (platform !== 'darwin' || ['DEVELOPER_DIR', 'TOOLCHAINS', 'SDKROOT', 'SWIFT_EXEC',
    'SWIFT_DRIVER_SWIFT_FRONTEND_EXEC'].some(key => env[key])
    || !existsSync(join(xcodeDeveloperDir, 'usr/bin/xcodebuild'))) return env
  const selected = selectedDeveloperDir ?? spawnSync('xcode-select', ['-p'], { env, encoding: 'utf8' }).stdout?.trim()
  return selected?.endsWith('/CommandLineTools') ? { ...env, DEVELOPER_DIR: xcodeDeveloperDir } : env
}

export function nativeTestAvailability(env = process.env, options = {}) {
  const platform = options.platform ?? process.platform
  if (platform !== 'darwin') return { available: true }
  const resolvedEnv = testEnvironment(env, options)
  const selected = resolvedEnv.DEVELOPER_DIR || options.selectedDeveloperDir
    || spawnSync('xcode-select', ['-p'], { env: resolvedEnv, encoding: 'utf8' }).stdout?.trim()
  if (selected && existsSync(join(selected, 'usr/bin/xcodebuild'))) {
    return { available: true, developerDir: selected }
  }
  return {
    available: false,
    reason: '当前 macOS 未安装或未选择完整 Xcode；已跳过 Swift/iOS 原生测试，其余测试继续',
  }
}

export function testExecutionContext(env = process.env) {
  env = testEnvironment(env)
  return { node: nodeExecutable({ env }), env: Object.fromEntries([...testEnvironmentKeys, 'CALMMIT_PATH']
    .map(key => [key, env[key] ?? null])) }
}

// Only a pass for the exact inputs may be reused by child commit/build processes.
export function testInputSignature(root = testRoot, env = process.env, { includeSources = true } = {}) {
  env = testEnvironment(env)
  const hash = createHash('sha256')
  hash.update(JSON.stringify([process.version, nodeExecutable({ env }), ...testEnvironmentKeys.map(key => env[key])]))
  function collect(path) {
    if (!existsSync(path)) return
    const stat = statSync(path)
    if (stat.isDirectory()) {
      for (const name of readdirSync(path).sort()) {
        if (!name.startsWith('.') && !['bin', 'obj', 'node_modules'].includes(name)) collect(join(path, name))
      }
    } else if (stat.isFile()) {
      hash.update(relative(root, path)); hash.update('\0'); hash.update(readFileSync(path)); hash.update('\0')
    }
  }
  for (const path of [...(includeSources ? ['Sources', 'apps/macos/Sources', 'apps/ios/App', 'apps/ios/UI', 'apps/windows/BenchGauge', 'apps/windows/BenchGauge.Shared'] : []), 'Tests', 'apps/ios/UITests', 'apps/windows/BenchGauge.Tests', 'apps/windows/Directory.Build.props', 'apps/windows/BenchGauge/BenchGauge.csproj', 'apps/windows/BenchGauge/packages.lock.json', 'apps/windows/BenchGauge.Shared/BenchGauge.Shared.csproj', 'apps/windows/BenchGauge.Shared/packages.lock.json', 'apps/windows/installer', 'apps/windows/Licenses', 'assets', 'config', 'Scripts', '.github', 'Package.swift', 'Package.resolved', 'test.sh', 'make-app.sh', 'dev.sh', 'LICENSE']) collect(join(root, path))
  collect(join(root, 'fc'))
  for (const path of ['apps/weapp/src', 'apps/weapp/test', 'apps/weapp/scripts', 'apps/weapp/package.json',
    'apps/weapp/vite.config.js', 'apps/weapp/postcss.config.js', 'apps/weapp/project.config.json',
    'package.json', 'pnpm-workspace.yaml', 'pnpm-lock.yaml']) collect(join(root, path))
  const ciConfig = join(root, 'calmmit.config.json')
  if (existsSync(ciConfig)) {
    collect(ciConfig)
    const config = JSON.parse(readFileSync(ciConfig, 'utf8'))
    const library = resolve(root, env.CALMMIT_PATH || config.library)
    // A cached pass also belongs to the exact shared implementation used by script tests.
    collect(join(library, 'src'))
    collect(join(library, 'bin'))
  }
  return hash.digest('hex')
}

export function testCommands(root = testRoot, { coreOnly = false, scriptsOnly = false, coverage = false, swiftcPath,
  env = testEnvironment(), node = nodeExecutable({ env }) } = {}) {
  const commands = []
  if (!coreOnly) {
    const files = readdirSync(join(root, 'Scripts')).filter((name) => name.endsWith('.test.mjs')).sort().map((name) => join(root, 'Scripts', name))
    if (!files.length) throw new Error('未找到脚本测试，拒绝报告通过')
    commands.push([node, ['--test', ...(coverage ? ['--experimental-test-coverage',
      `--test-coverage-include=${join(root, 'Scripts', '*.mjs')}`, '--test-coverage-exclude=**/*.test.mjs'] : []), ...files]])
    const miniTests = join(root, 'apps/weapp/test')
    if (existsSync(miniTests)) {
      const files = readdirSync(miniTests).filter(name => name.endsWith('.test.mjs')).sort().map(name => join(miniTests, name))
      if (!files.length) throw new Error('未找到小程序测试，拒绝报告通过')
      commands.push([node, ['--test', ...files]])
    }
  }
  if (!scriptsOnly) {
    // Native rendering holds MainActor; serialize suites so it cannot consume
    // unrelated network/pipe fixtures' deadlines while their tasks are suspended.
    const args = ['test', '--no-parallel', '--disable-xctest', '--package-path', root,
      '--scratch-path', join(root, 'work', 'unit-test-build'),
      '--cache-path', join(root, 'work', 'swiftpm-cache'), '--manifest-cache', 'local', '--disable-sandbox']
    if (coverage) args.push('--enable-code-coverage')
    // Swift Build in recent Command Line Tools omits TestingMacros from its search path.
    const swiftc = swiftcPath ?? spawnSync('xcrun', ['--find', 'swiftc'], { env, encoding: 'utf8' }).stdout?.trim()
    if (swiftc) {
      const plugins = resolve(dirname(swiftc), '..', 'lib', 'swift', 'host', 'plugins', 'testing')
      if (existsSync(plugins)) args.push('-Xswiftc', '-plugin-path', '-Xswiftc', plugins)
    }
    commands.push(['swift', args])
  }
  if (!coreOnly && existsSync(join(root, 'apps/windows/BenchGauge.Tests/BenchGauge.Tests.csproj'))) {
    commands.push([node, [join(root, 'Scripts/windows-tests.mjs')]])
  }
  return commands
}

// Caller must hold test.lock. Only the just-finished run may bypass its live
// owner PID; interrupted runs with a live or unverifiable owner stay untouched.
export function pruneTestResults(directory, { completedCoverageDirectory = null, state = pidState } = {}) {
  if (!lstatSync(directory).isDirectory()) throw new Error('拒绝清理非真实测试结果目录')
  const newestFirst = (a, b) => b.started - a.started || b.name.localeCompare(a.name)
  const coverage = [], failures = []
  for (const name of readdirSync(directory)) {
    const path = join(directory, name)
    const match = /^(coverage|failure)-(\d+)-([1-9]\d*)(\.log)?$/.exec(name)
    if (!match) continue
    const stat = lstatSync(path)
    if (match[1] === 'coverage' && !match[4] && stat.isDirectory()) {
      if (path !== completedCoverageDirectory && state(Number(match[3])) !== 'gone') continue
      const summary = join(path, 'summary.json')
      coverage.push({ name, path, started: Number(match[2]), summary: existsSync(summary) && lstatSync(summary).isFile() })
    } else if (match[1] === 'failure' && match[4] && stat.isFile()) {
      failures.push({ name, path, started: Number(match[2]) })
    }
  }
  const latestSummary = coverage.sort(newestFirst).find(run => run.summary)
  for (const run of coverage) {
    if (run === latestSummary) {
      for (const name of readdirSync(run.path)) {
        if (name !== 'summary.json') rmSync(join(run.path, name), { recursive: true, force: true })
      }
    } else rmSync(run.path, { recursive: true, force: true })
  }
  for (const run of failures.sort(newestFirst).slice(1)) rmSync(run.path)
}

export async function runTests({ root = testRoot, coreOnly = false, scriptsOnly = false, coverage = false, gate = false,
  env = process.env, commands, run, logger = console, lockWaitMs = 0, nativeAvailable } = {}) {
  env = testEnvironment(env)
  if (coreOnly && scriptsOnly) throw new Error('--core 和 --scripts 不能同时使用')
  const native = !scriptsOnly && commands == null && run == null
    ? (nativeAvailable == null ? nativeTestAvailability(env) : {
        available: nativeAvailable,
        reason: '当前 macOS 未安装或未选择完整 Xcode；已跳过 Swift/iOS 原生测试，其余测试继续',
      })
    : { available: true }
  const skipNative = !native.available
  let before = testInputSignature(root, env)
  if (gate && !coreOnly && !scriptsOnly && !coverage && env.BENCHGAUGE_TEST_PASS === before) {
    logger.log('[test] 当前代码已通过完整测试，沿用本次流程的结果')
    return { status: 0, signature: before, reused: true }
  }
  const directory = join(root, 'work', 'test-results')
  mkdirSync(directory, { recursive: true })
  const lockPath = join(directory, 'test.lock')
  const waitStarted = Date.now()
  let lock = acquireCommitLock({ lockPath })
  let waited = false
  while (!lock.acquired && ['busy', 'busy_unverifiable'].includes(lock.reason) && Date.now() - waitStarted < lockWaitMs) {
    if (!waited) logger.log(`[test] 等待正在运行的测试释放锁（pid ${lock.owner || '未知'}，最多 ${Math.ceil(lockWaitMs / 1000)} 秒）`)
    waited = true
    await delay(Math.min(1000, Math.max(1, lockWaitMs - (Date.now() - waitStarted))))
    lock = acquireCommitLock({ lockPath })
  }
  if (!lock.acquired) return { status: 75, signature: null,
    error: `无法获取测试锁：${lockPath}（${lock.reason}，pid ${lock.owner || '未知'}${waited ? '，等待超时' : ''}）` }
  try {
    // Edits made while waiting belong to the new run, not its previous owner.
    if (waited) before = testInputSignature(root, env)
    let logPath = env.CI_CHECK_LOG || join(directory, 'latest.log')
    writeFileSync(logPath, '')
    if (skipNative) {
      const warning = `[test] 警告：${native.reason}`
      if (typeof logger.warn === 'function') logger.warn(warning)
      else logger.log(warning)
      appendFileSync(logPath, warning + '\n')
    }
    const started = Date.now()
    const coverageDirectory = coverage && !coreOnly && !run
      ? join(directory, `coverage-${started}-${process.pid}`) : null
    const nativeCoverage = coverage && !scriptsOnly && !run && !skipNative
    let status = 0
    const exec = run ?? ((command, args) => new Promise((resolvePromise) => {
      const childEnv = { ...env, CLANG_MODULE_CACHE_PATH: join(root, 'work', 'clang-modules'), TZ: 'Asia/Shanghai' }
      // Never let a private Git index or a parent's pass leak into test fixtures.
      delete childEnv.GIT_INDEX_FILE
      delete childEnv.BENCHGAUGE_TEST_PASS
      // Commit workflows set this to 0 while running checks. Isolated watcher
      // fixtures must choose their own push policy rather than inherit it.
      delete childEnv.COMMIT_PUSH
      if (coverageDirectory) {
        childEnv.NODE_V8_COVERAGE = coverageDirectory
        childEnv.BENCHGAUGE_COVERAGE_DIRECTORY = coverageDirectory
        childEnv.BENCHGAUGE_COVERAGE_ROOT = root
        childEnv.NODE_OPTIONS = `${childEnv.NODE_OPTIONS || ''} --require=${JSON.stringify(join(root, 'Scripts', 'coverage-preload.cjs'))}`.trim()
      }
      const child = spawn(command, args, { cwd: root, env: childEnv, stdio: ['ignore', 'pipe', 'pipe'] })
      for (const stream of [child.stdout, child.stderr]) stream.on('data', (data) => {
        process.stdout.write(data); appendFileSync(logPath, data)
      })
      child.on('error', (error) => {
        logger.error(error.message); appendFileSync(logPath, error.message + '\n'); resolvePromise(1)
      })
      child.on('close', (code) => resolvePromise(code ?? 1))
    }))
    const checks = commands ?? testCommands(root, { coreOnly, scriptsOnly: scriptsOnly || skipNative, coverage, env })
    if (!checks.length && !skipNative) throw new Error('测试列表为空，拒绝报告通过')
    const runChecks = async () => {
      if (nativeCoverage) {
        status = await exec(nodeExecutable({ env }), [join(root, 'Scripts', 'swift-coverage.cjs'), root, '--clear'])
      }
      for (const [command, args] of checks) {
        if (status !== 0) break
        const heading = `\n[test] ${command} ${args.join(' ')}\n`
        logger.log(heading.trim()); appendFileSync(logPath, heading)
        status = await exec(command, args)
        if (status !== 0) break
      }
      if (status === 0 && coverageDirectory) {
        const result = spawnSync(nodeExecutable({ env }), ['--expose-internals', join(root, 'Scripts', 'coverage-report.cjs'), coverageDirectory, root],
          { cwd: root, env, encoding: 'utf8' })
        const output = `${result.stdout || ''}${result.stderr || ''}`
        process.stdout.write(output); appendFileSync(logPath, output)
        status = result.status ?? 1
      }
      if (status === 0 && nativeCoverage) {
        status = await exec(nodeExecutable({ env }), [join(root, 'Scripts', 'swift-coverage.cjs'), root])
      }
    }
    // Hold the native-build lease through Swift's coverage validation, so its
    // scratch directory cannot be reclaimed between testing and reporting.
    if (!scriptsOnly && !run && !skipNative) await withBuildCache(root, 'tests', async () => {
      // Packaging previously prepared these before its gate. Keep relocation
      // recovery ahead of Swift tests, now while holding the shared cache lease.
      prepareSwiftWorkspace(root, { log: message => logger.log(message) })
      await runChecks()
    }, { log: message => logger.log(message) })
    else await runChecks()
    const after = testInputSignature(root, env)
    // A failure belongs to the inputs that were tested too. If those inputs
    // changed, revalidate the new version instead of freezing it or asking an
    // AI to repair an obsolete failure (including stale coverage manifests).
    if (before !== after) {
      status = 75
      const message = '[test] 测试期间代码发生变化，本次结果不能用于提交或构建，请重新验证'
      logger.error(message); appendFileSync(logPath, message + '\n')
    }
    if (status !== 0) {
      const failurePath = join(directory, `failure-${Date.now()}-${process.pid}.log`)
      copyFileSync(logPath, failurePath)
      logPath = failurePath
    }
    const result = { status, signature: status === 0 && !coreOnly && !scriptsOnly ? before : null, logPath, durationMs: Date.now() - started,
      scope: coreOnly ? 'core' : scriptsOnly ? 'scripts' : 'all', coverage, coverageDirectory,
      skipped: skipNative ? [{ suite: 'swift', reason: native.reason }] : [] }
    writeFileSync(join(directory, 'latest.json'), JSON.stringify(result, null, 2) + '\n')
    // Reporting and all coverage checks have finished before discarding profiles.
    // Cleanup trouble must not turn either a pass or a failure into a new verdict.
    try { pruneTestResults(directory, { completedCoverageDirectory: coverageDirectory }) }
    catch (error) { logger.error(`[test] 测试记录清理未完成：${error.message}`) }
    logger.log(status === 0 ? '[test] 测试通过' : `[test] 测试未通过，日志：${logPath}`)
    return result
  } finally {
    lock.release()
  }
}

async function main() {
  const args = process.argv.slice(2)
  if (args.some((arg) => !['--core', '--scripts', '--coverage', '--gate'].includes(arg))) throw new Error('用法：./test.sh [--core | --scripts] [--coverage]')
  if (args.includes('--gate') && args.length !== 1) throw new Error('--gate 必须运行完整测试')
  const result = args.includes('--gate')
    ? await (await import('./test-repair.mjs')).runTestGate()
    // A complete coverage run can take about three minutes. Let a concurrent
    // run finish before starting our own checks, within the outer CI deadline.
    : await runTests({ coreOnly: args.includes('--core'), scriptsOnly: args.includes('--scripts'), coverage: args.includes('--coverage'), lockWaitMs: 300_000 })
  if (result.error) console.error(`[test] ${result.error}`)
  process.exitCode = result.status
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((error) => { console.error(`[test] ${error.message}`); process.exitCode = 1 })
}
