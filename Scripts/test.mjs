#!/usr/bin/env node
import { spawn, spawnSync } from 'node:child_process'
import { createHash } from 'node:crypto'
import { appendFileSync, copyFileSync, existsSync, mkdirSync, readFileSync, readdirSync, statSync, writeFileSync } from 'node:fs'
import { dirname, join, relative, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { acquireCommitLock } from './commit-lock.mjs'

export const testRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..')

// Only a pass for the exact inputs may be reused by child commit/build processes.
export function testInputSignature(root = testRoot, env = process.env, { includeSources = true } = {}) {
  const hash = createHash('sha256')
  hash.update(JSON.stringify([process.version, process.execPath, env.PATH, env.DEVELOPER_DIR, env.TOOLCHAINS, env.SDKROOT, env.TZ,
    env.SWIFT_EXEC, env.SWIFT_DRIVER_SWIFT_FRONTEND_EXEC, env.NODE_OPTIONS, env.LANG, env.LC_ALL]))
  function collect(path) {
    if (!existsSync(path)) return
    const stat = statSync(path)
    if (stat.isDirectory()) {
      for (const name of readdirSync(path).sort()) {
        if (!name.startsWith('.')) collect(join(path, name))
      }
    } else if (stat.isFile()) {
      hash.update(relative(root, path)); hash.update('\0'); hash.update(readFileSync(path)); hash.update('\0')
    }
  }
  for (const path of [...(includeSources ? ['Sources'] : []), 'Tests', 'Scripts', '.github', 'Package.swift', 'Package.resolved', 'test.sh', 'make-app.sh', 'dev.sh', 'LICENSE']) collect(join(root, path))
  return hash.digest('hex')
}

export function testCommands(root = testRoot, { coreOnly = false, scriptsOnly = false, coverage = false, swiftcPath } = {}) {
  const commands = []
  if (!coreOnly) {
    const files = readdirSync(join(root, 'Scripts')).filter((name) => name.endsWith('.test.mjs')).sort().map((name) => join(root, 'Scripts', name))
    if (!files.length) throw new Error('未找到脚本测试，拒绝报告通过')
    commands.push([process.execPath, ['--test', ...(coverage ? ['--experimental-test-coverage',
      `--test-coverage-include=${join(root, 'Scripts', '*.mjs')}`, '--test-coverage-exclude=**/*.test.mjs'] : []), ...files]])
  }
  if (!scriptsOnly) {
    const args = ['test', '--disable-xctest', '--package-path', root,
      '--scratch-path', join(root, 'work', 'unit-test-build'),
      '--cache-path', join(root, 'work', 'swiftpm-cache'), '--manifest-cache', 'local', '--disable-sandbox']
    if (coverage) args.push('--enable-code-coverage')
    // Swift Build in recent Command Line Tools omits TestingMacros from its search path.
    const swiftc = swiftcPath ?? spawnSync('xcrun', ['--find', 'swiftc'], { encoding: 'utf8' }).stdout?.trim()
    if (swiftc) {
      const plugins = resolve(dirname(swiftc), '..', 'lib', 'swift', 'host', 'plugins', 'testing')
      if (existsSync(plugins)) args.push('-Xswiftc', '-plugin-path', '-Xswiftc', plugins)
    }
    commands.push(['swift', args])
  }
  return commands
}

export async function runTests({ root = testRoot, coreOnly = false, scriptsOnly = false, coverage = false, gate = false,
  env = process.env, commands, run, logger = console } = {}) {
  if (coreOnly && scriptsOnly) throw new Error('--core 和 --scripts 不能同时使用')
  const before = testInputSignature(root, env)
  if (gate && !coreOnly && !scriptsOnly && !coverage && env.BENCHGAUGE_TEST_PASS === before) {
    logger.log('[test] 当前代码已通过完整测试，沿用本次流程的结果')
    return { status: 0, signature: before, reused: true }
  }
  const directory = join(root, 'work', 'test-results')
  mkdirSync(directory, { recursive: true })
  const lock = acquireCommitLock({ lockPath: join(directory, 'test.lock') })
  if (!lock.acquired) return { status: 75, signature: null, error: '另一个测试进程正在运行，请稍后重试' }
  try {
    let logPath = env.CI_CHECK_LOG || join(directory, 'latest.log')
    writeFileSync(logPath, '')
    const started = Date.now()
    let status = 0
    const exec = run ?? ((command, args) => new Promise((resolvePromise) => {
      const childEnv = { ...env, CLANG_MODULE_CACHE_PATH: join(root, 'work', 'clang-modules'), TZ: 'Asia/Shanghai' }
      // Never let a private Git index or a parent's pass leak into test fixtures.
      delete childEnv.GIT_INDEX_FILE
      delete childEnv.BENCHGAUGE_TEST_PASS
      const child = spawn(command, args, { cwd: root, env: childEnv, stdio: ['ignore', 'pipe', 'pipe'] })
      for (const stream of [child.stdout, child.stderr]) stream.on('data', (data) => {
        process.stdout.write(data); appendFileSync(logPath, data)
      })
      child.on('error', (error) => {
        logger.error(error.message); appendFileSync(logPath, error.message + '\n'); resolvePromise(1)
      })
      child.on('close', (code) => resolvePromise(code ?? 1))
    }))
    const checks = commands ?? testCommands(root, { coreOnly, scriptsOnly, coverage })
    if (!checks.length) throw new Error('测试列表为空，拒绝报告通过')
    for (const [command, args] of checks) {
      const heading = `\n[test] ${command} ${args.join(' ')}\n`
      logger.log(heading.trim()); appendFileSync(logPath, heading)
      status = await exec(command, args)
      if (status !== 0) break
    }
    const after = testInputSignature(root, env)
    if (status === 0 && before !== after) {
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
      scope: coreOnly ? 'core' : scriptsOnly ? 'scripts' : 'all', coverage }
    writeFileSync(join(directory, 'latest.json'), JSON.stringify(result, null, 2) + '\n')
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
    : await runTests({ coreOnly: args.includes('--core'), scriptsOnly: args.includes('--scripts'), coverage: args.includes('--coverage') })
  process.exitCode = result.status
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((error) => { console.error(`[test] ${error.message}`); process.exitCode = 1 })
}
