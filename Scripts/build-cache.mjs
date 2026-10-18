import { spawn, spawnSync } from 'node:child_process'
import { randomUUID } from 'node:crypto'
import { closeSync, existsSync, lstatSync, mkdirSync, openSync, readFileSync, readdirSync, realpathSync, renameSync, rmSync, writeFileSync } from 'node:fs'
import { basename, dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { setTimeout as delay } from 'node:timers/promises'

export const cacheBudgetBytes = 20 * 1024 ** 3
export const cacheIdleMs = 7 * 24 * 60 * 60 * 1000
const xcodeParts = ['Build', 'ModuleCache.noindex', 'SDKExplicitPrecompiledModules', 'SDKStatCaches.noindex', 'Index.noindex', 'CompilationCache.noindex']
export const cacheProfiles = {
  tests: ['work/unit-test-build', 'work/clang-modules', 'work/swiftpm-cache'],
  macos: ['.build', 'work/clang-modules', 'work/swiftpm-cache'],
  ios: xcodeParts.map(part => `work/ios-build/${part}`),
  'ios-check': xcodeParts.map(part => `work/ios-deploy/CheckDerivedData/${part}`),
  'ios-device': xcodeParts.map(part => `work/ios-deploy/DerivedData/${part}`),
}
const allowed = new Set(Object.values(cacheProfiles).flat())
const temporaryPattern = /^work\/build-cache\/temporary\/[a-f0-9-]{36}$/

// Check every path component: an in-repository link must never redirect removal.
export function cachePath(root, name) {
  if (!allowed.has(name) && !temporaryPattern.test(name)) throw new Error(`未登记的缓存路径：${name}`)
  let path = root
  for (const part of name.split('/')) {
    path = join(path, part)
    const stat = lstatSync(path, { throwIfNoEntry: false })
    if (stat && (!stat.isDirectory() || stat.isSymbolicLink())) throw new Error(`缓存路径不是实际目录：${name}`)
  }
  return path
}

export function processStarted(pid, { platform = process.platform, execute = spawnSync } = {}) {
  const windows = platform === 'win32'
  const result = execute(windows ? 'powershell.exe' : 'ps', windows
    ? ['-NoProfile', '-NonInteractive', '-Command', `(Get-CimInstance Win32_Process -Filter "ProcessId = ${pid}").CreationDate.ToUniversalTime().ToString('o')`]
    : ['-p', String(pid), '-o', 'lstart='], { encoding: 'utf8', timeout: 2000, env: { ...process.env, LC_ALL: 'C', TZ: 'UTC' } })
  if (result.error || result.status !== 0 || !result.stdout?.trim()) return null
  const value = Date.parse(windows ? result.stdout.trim() : `${result.stdout.trim()} UTC`)
  return Number.isFinite(value) ? value : null
}

export function ownerState(owner, { kill = process.kill, started = processStarted } = {}) {
  if (!Number.isSafeInteger(owner?.pid) || owner.pid <= 1) return 'unknown'
  try { kill(owner.pid, 0) }
  catch (error) { return error.code === 'ESRCH' ? 'gone' : 'unknown' }
  if (owner.started == null) return 'unknown'
  const current = started(owner.pid)
  return current == null ? 'unknown' : current === owner.started ? 'alive' : 'gone'
}

// A missing inspector is not evidence that a directory is idle. On platforms
// without lsof automatic eviction is deferred, while registered builds still work.
export function cacheInUse(path, { execute = spawnSync } = {}) {
  const processes = execute('ps', ['-A', '-o', 'command='], { encoding: 'utf8', timeout: 2000, maxBuffer: 4 * 1024 * 1024 })
  if (processes.error || processes.status !== 0 || processes.stderr?.trim() || typeof processes.stdout !== 'string') return null
  const buildRoot = xcodeParts.includes(basename(path)) ? dirname(path) : path
  if (processes.stdout.includes(buildRoot)) return true
  if (!existsSync(path)) return false
  const result = execute('lsof', ['-nP', '-t', '+D', path], { encoding: 'utf8', timeout: 10_000, maxBuffer: 1024 * 1024 })
  if (result.error || result.stderr?.trim()) return null
  return result.status === 1 && !result.stdout?.trim() ? false : result.status === 0 ? true : null
}

export function cacheBytes(path) {
  const stat = lstatSync(path, { throwIfNoEntry: false })
  if (!stat) return 0
  return (stat.blocks == null ? stat.size : stat.blocks * 512)
    + (stat.isDirectory() && !stat.isSymbolicLink() ? readdirSync(path).reduce((sum, name) => sum + cacheBytes(join(path, name)), 0) : 0)
}

function writeJSON(path, value) {
  const temporary = `${path}.${randomUUID()}.tmp`
  try { writeFileSync(temporary, JSON.stringify(value, null, 2) + '\n', { mode: 0o600 }); renameSync(temporary, path) }
  finally { rmSync(temporary, { force: true }) }
}

function readJSON(path, fallback) {
  try { return JSON.parse(readFileSync(path, 'utf8')) }
  catch (error) { if (error.code === 'ENOENT') return fallback; throw error }
}

function managementDirectory(root) {
  // root itself may use macOS's /var -> /private/var alias; descendants may not.
  root = realpathSync(root)
  for (const name of ['work', 'work/build-cache']) {
    const path = join(root, name)
    if (existsSync(path) && (!lstatSync(path).isDirectory() || lstatSync(path).isSymbolicLink())) throw new Error('缓存管理目录不能是符号链接或文件')
    mkdirSync(path, { recursive: true })
  }
  return { root, directory: join(root, 'work/build-cache') }
}

export async function cacheLock(root, { waitMs = 600_000, state = ownerState, inUse = cacheInUse,
  started = processStarted, now = Date.now, signal, log = console.log } = {}) {
  const managed = managementDirectory(root), path = join(managed.directory, 'native.lock')
  const since = now(), owner = { pid: process.pid, started: started(process.pid), token: randomUUID(), paths: [] }
  let announced = false
  while (true) {
    signal?.throwIfAborted()
    let fd
    try { fd = openSync(path, 'wx', 0o600) }
    catch (error) { if (error.code !== 'EEXIST') throw error }
    if (fd != null) {
      try { writeFileSync(fd, JSON.stringify(owner)) } finally { closeSync(fd) }
      return { ...managed, owner, update: () => writeJSON(path, owner), release: () => {
        if (readJSON(path, null)?.token === owner.token) rmSync(path)
      } }
    }
    // No age-based stealing: malformed ownership or an unverifiable live process
    // requires inspection. Check open files before reclaiming an orphan's lock.
    let previous
    try { previous = readJSON(path, null) } catch { previous = null }
    if (previous?.token && previous.token === process.env.BENCHGAUGE_BUILD_CACHE_SESSION)
      throw new Error('不能在持有缓存锁的任务内嵌套受管理的构建入口；请直接执行 swift / xcodebuild')
    if (previous && Array.isArray(previous.paths) && state(previous) === 'gone'
      && (!previous.child || state(previous.child) === 'gone')
      && previous.paths.every(name => inUse(cachePath(managed.root, name)) === false)) {
      if (readJSON(path, null)?.token === previous.token) rmSync(path)
      continue
    }
    if (now() - since >= waitMs) throw new Error('另一个构建仍在运行或无法确认已退出，未启动并行构建或清理缓存')
    if (!announced) { log('[cache] 等待当前构建结束，避免并行编译占满内存'); announced = true }
    await delay(Math.min(500, waitMs), undefined, { signal })
  }
}

function registry(lock, now) {
  const path = join(lock.directory, 'registry.json')
  const data = readJSON(path, { version: 1, entries: [] })
  if (data.version !== 1 || !Array.isArray(data.entries)) throw new Error('缓存登记文件损坏，停止自动清理')
  for (const entry of data.entries) {
    cachePath(lock.root, entry.path)
    if (!Number.isFinite(entry.lastUsedAt) || entry.temporary !== temporaryPattern.test(entry.path)) throw new Error('缓存登记记录无效')
  }
  for (const name of allowed) {
    if (existsSync(join(lock.root, name)) && !data.entries.some(entry => entry.path === name))
      data.entries.push({ path: name, temporary: false, lastUsedAt: now })
  }
  return { path, data }
}

// All scans/removals run under the same lock as native builds. Protect the
// current operation, and inspect external/manual users before any eviction.
export function pruneBuildCaches(lock, { now = Date.now(), budgetBytes = cacheBudgetBytes, idleMs = cacheIdleMs,
  protect = [], inUse = cacheInUse, measure = cacheBytes, remove = rmSync } = {}) {
  const registered = registry(lock, now), skipped = [], removed = [], measured = []
  for (const entry of registered.data.entries) {
    try { measured.push({ ...entry, bytes: measure(cachePath(lock.root, entry.path)) }) }
    catch (error) { skipped.push({ path: entry.path, reason: error.message }) }
  }
  let totalBytes = measured.reduce((sum, entry) => sum + entry.bytes, 0)
  const beforeBytes = totalBytes
  for (const entry of measured.sort((a, b) => a.lastUsedAt - b.lastUsedAt || a.path.localeCompare(b.path))) {
    if (protect.includes(entry.path) || (!entry.bytes && !entry.temporary)) continue
    if (!entry.temporary && now - entry.lastUsedAt < idleMs && totalBytes <= budgetBytes) continue
    const path = cachePath(lock.root, entry.path)
    if (inUse(path) !== false) { skipped.push({ path: entry.path, reason: '仍被使用或无法确认空闲' }); continue }
    try {
      // Recheck ancestors after the open-file inspection, immediately before rm.
      remove(cachePath(lock.root, entry.path), { recursive: true, force: true })
      totalBytes -= entry.bytes; removed.push(entry.path)
    } catch (error) { skipped.push({ path: entry.path, reason: error.message }) }
  }
  registered.data.entries = registered.data.entries.filter(entry => !removed.includes(entry.path))
  writeJSON(registered.path, registered.data)
  const report = { checkedAt: now, beforeBytes, remainingBytes: totalBytes, budgetBytes,
    overBudget: totalBytes > budgetBytes || skipped.length > 0, removed, skipped }
  writeJSON(join(lock.directory, 'latest-cleanup.json'), report)
  return report
}

export async function withBuildCache(root, profile, action, options = {}) {
  if (profile !== 'temporary' && !Object.hasOwn(cacheProfiles, profile)) throw new Error(`未知缓存配置：${profile}`)
  const lock = await cacheLock(root, options)
  const now = options.now || Date.now, log = options.log || console.log
  const paths = profile === 'temporary' ? [`work/build-cache/temporary/${randomUUID()}`] : cacheProfiles[profile]
  try {
    lock.owner.paths = paths; lock.update()
    const registered = registry(lock, now())
    for (const name of paths) {
      const entry = registered.data.entries.find(entry => entry.path === name)
      if (entry) entry.lastUsedAt = now()
      else registered.data.entries.push({ path: name, temporary: profile === 'temporary', lastUsedAt: now() })
    }
    writeJSON(registered.path, registered.data)
    if (profile === 'temporary') mkdirSync(cachePath(lock.root, paths[0]), { recursive: true })
    return await action({ directory: profile === 'temporary' ? cachePath(lock.root, paths[0]) : null, owner: lock.owner,
      trackChild: pid => { lock.owner.child = { pid, started: (options.started || processStarted)(pid) }; lock.update() } })
  } finally {
    try {
      const registered = registry(lock, now())
      for (const entry of registered.data.entries) if (paths.includes(entry.path)) entry.lastUsedAt = now()
      writeJSON(registered.path, registered.data)
      // The action (including packaging/install/reporting) has finished. Fresh
      // reusable caches stay warm unless the budget requires LRU eviction.
      const report = pruneBuildCaches(lock, { ...options, now: now() })
      if (report.removed.length) log(`[cache] 已回收 ${report.removed.length} 个缓存目录`)
      if (report.overBudget) log('[cache] 缓存超过预算或有目录暂无法回收，已记录到 work/build-cache/latest-cleanup.json')
    } catch (error) { log(`[cache] 缓存回收未完成：${error.message}`) }
    finally { lock.release() }
  }
}

export async function runCachedCommand(root, profile, command, args, options = {}) {
  return withBuildCache(root, profile, ({ directory, owner, trackChild }) => new Promise((accept, reject) => {
    const child = spawn(command, args, { cwd: root, detached: process.platform !== 'win32', env: { ...process.env, BENCHGAUGE_BUILD_CACHE_SESSION: owner.token,
      ...(directory ? { BENCHGAUGE_TEMP_CACHE: directory } : {}) }, stdio: 'inherit' })
    if (child.pid) trackChild(child.pid)
    const forward = signal => {
      try { if (process.platform === 'win32') child.kill(signal); else process.kill(-child.pid, signal) } catch { /* Already exited. */ }
    }
    const interrupt = () => forward('SIGINT'), terminate = () => forward('SIGTERM')
    process.on('SIGINT', interrupt); process.on('SIGTERM', terminate)
    const unsubscribe = () => { process.removeListener('SIGINT', interrupt); process.removeListener('SIGTERM', terminate) }
    child.once('error', error => { unsubscribe(); reject(error) })
    child.once('close', code => { unsubscribe(); accept(code ?? 1) })
  }), options)
}

async function main() {
  const root = resolve(dirname(fileURLToPath(import.meta.url)), '..')
  const [command, profile, separator, executable, ...args] = process.argv.slice(2)
  if (command === 'run' && separator === '--' && executable) {
    process.exitCode = await runCachedCommand(root, profile, executable, args); return
  }
  if (command === 'clean' && !profile) {
    const lock = await cacheLock(root, { waitMs: 0 })
    try { console.log(JSON.stringify(pruneBuildCaches(lock), null, 2)) } finally { lock.release() }
    return
  }
  if (command === 'status' && !profile) {
    const { directory } = managementDirectory(root)
    console.log(JSON.stringify({ registry: readJSON(join(directory, 'registry.json'), null),
      active: readJSON(join(directory, 'native.lock'), null), latestCleanup: readJSON(join(directory, 'latest-cleanup.json'), null) }, null, 2)); return
  }
  throw new Error('用法：build-cache.mjs status | clean | run macos|tests|ios|ios-check|ios-device|temporary -- command [args]')
}
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch(error => { console.error(`[cache] ${error.message}`); process.exitCode = 1 })
}
