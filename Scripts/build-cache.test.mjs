import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import cp from 'node:child_process'
import { EventEmitter } from 'node:events'
import fs from 'node:fs'
import { syncBuiltinESMExports } from 'node:module'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import test from 'node:test'
import { cacheBudgetBytes, cacheIdleMs, cacheProfiles, cachePath, cacheBytes, cacheInUse,
  processStarted, ownerState, cacheLock, pruneBuildCaches, withBuildCache, runCachedCommand } from './build-cache.mjs'

const logger = () => {}, free = () => false, started = () => 123
function fixture(t) {
  const root = fs.realpathSync(fs.mkdtempSync(join(tmpdir(), 'benchgauge-cache-')))
  t.after(() => fs.rmSync(root, { recursive: true, force: true }))
  const directory = join(root, 'work/build-cache')
  const registry = join(directory, 'registry.json'), lockPath = join(directory, 'native.lock')
  fs.mkdirSync(directory, { recursive: true })
  const create = (path, content = 'cache') => {
    fs.mkdirSync(join(root, path), { recursive: true }); fs.writeFileSync(join(root, path, 'generated'), content)
  }
  const seed = entries => fs.writeFileSync(registry, JSON.stringify({ version: 1, entries }))
  const entry = (path, lastUsedAt = 1) => ({ path, lastUsedAt, temporary: path.startsWith('work/build-cache/temporary/') })
  const lock = options => cacheLock(root, { started, log: logger, ...options })
  return { root, directory, registry, lockPath, create, seed, entry, lock }
}

test('cache allowlist rejects traversal, unregistered directories, files and linked ancestors', t => {
  const f = fixture(t), outside = join(f.root, 'private')
  fs.mkdirSync(outside); fs.writeFileSync(join(outside, 'source.swift'), 'keep')
  for (const path of ['.', 'work', '../other', 'Sources', 'work/test-results', 'work/ios', '.build/../Sources', 'work/build-cache/temporary/not-a-uuid']) {
    assert.throws(() => cachePath(f.root, path), /未登记/)
  }
  fs.symlinkSync(outside, join(f.root, '.build'), 'junction')
  assert.throws(() => cachePath(f.root, '.build'), /实际目录/)
  fs.rmSync(join(f.root, '.build')); fs.writeFileSync(join(f.root, '.build'), 'file')
  assert.throws(() => cachePath(f.root, '.build'), /实际目录/)
  fs.rmSync(join(f.root, '.build')); fs.symlinkSync(join(f.root, 'missing'), join(f.root, '.build'), 'junction')
  assert.throws(() => cachePath(f.root, '.build'), /实际目录/)
  assert.equal(fs.readFileSync(join(outside, 'source.swift'), 'utf8'), 'keep')
  for (const paths of Object.values(cacheProfiles)) for (const path of paths.filter(path => path !== '.build')) assert.ok(cachePath(f.root, path).startsWith(f.root))
})

test('allocated-size counting never follows internal links, including broken links', t => {
  const f = fixture(t); f.create('.build')
  const outside = join(f.root, 'outside'); fs.mkdirSync(outside); fs.writeFileSync(join(outside, 'keep'), 'source')
  fs.symlinkSync(outside, join(f.root, '.build/framework'), 'junction')
  fs.symlinkSync(join(f.root, 'missing'), join(f.root, '.build/broken'), 'junction')
  assert.ok(cacheBytes(join(f.root, '.build')) > 0)
  assert.equal(cacheBytes(join(f.root, 'missing')), 0)
  const original = fs.lstatSync
  t.mock.method(fs, 'lstatSync', (path, ...args) => path === join(f.root, '.build/generated')
    ? { size: 5, isDirectory: () => false, isSymbolicLink: () => false } : original(path, ...args))
  syncBuiltinESMExports(); t.after(() => { t.mock.restoreAll(); syncBuiltinESMExports() })
  assert.equal(cacheBytes(join(f.root, '.build/generated')), 5)
})

test('owner identity distinguishes exit, PID reuse, permission denial and unavailable start times', () => {
  for (const owner of [null, {}, { pid: 1 }, { pid: '2' }]) assert.equal(ownerState(owner), 'unknown')
  const owner = { pid: 123, started: 10 }
  assert.equal(ownerState(owner, { kill() {}, started: () => 10 }), 'alive')
  assert.equal(ownerState(owner, { kill() {}, started: () => 11 }), 'gone')
  assert.equal(ownerState(owner, { kill() {}, started: () => null }), 'unknown')
  assert.equal(ownerState({ pid: 123 }, { kill() {} }), 'unknown')
  for (const code of ['ESRCH', 'EPERM']) assert.equal(ownerState(owner, { kill() { throw Object.assign(Error(), { code }) } }), code === 'ESRCH' ? 'gone' : 'unknown')
  for (const platform of ['darwin', 'win32']) {
    let args
    assert.equal(processStarted(123, { platform, execute: (...values) => { args = values; return { status: 0, stdout: platform === 'win32' ? '2026-10-17T10:00:00Z' : 'Sat Oct 17 10:00:00 2026' } } }), Date.parse('2026-10-17T10:00:00Z'))
    assert.equal(args[0], platform === 'win32' ? 'powershell.exe' : 'ps')
    for (const result of [{ error: Error('missing') }, { status: 1 }, { status: 0 }, { status: 0, stdout: 'invalid' }, { status: 0, stdout: ' ' }])
      assert.equal(processStarted(123, { platform, execute: () => result }), null)
  }
})

test('external process arguments and open files prevent eviction; missing inspectors defer it', t => {
  const f = fixture(t), path = join(f.root, 'work/ios-build/Build'); f.create('work/ios-build/Build')
  assert.equal(cacheInUse(join(f.root, 'missing'), { execute: () => ({ status: 0, stdout: '' }) }), false)
  assert.equal(cacheInUse(join(f.root, 'missing'), { execute: () => ({ status: 0, stdout: `swift --scratch-path ${join(f.root, 'missing')}` }) }), true)
  assert.equal(cacheInUse(path, { execute: () => ({ status: 0, stdout: `xcodebuild -derivedDataPath ${join(f.root, 'work/ios-build')}` }) }), true)
  for (const result of [{ error: Error() }, { status: 1 }, { status: 0, stderr: 'denied', stdout: '' }, { status: 0 }]) assert.equal(cacheInUse(path, { execute: () => result }), null)
  const invoke = result => cacheInUse(path, { execute: command => command === 'ps' ? { status: 0, stdout: 'unrelated process' } : result })
  assert.equal(invoke({ status: 1, stdout: '' }), false)
  assert.equal(invoke({ status: 0, stdout: '123' }), true)
  assert.equal(invoke({ status: 2 }), null)
  assert.equal(invoke({ error: Error('missing') }), null)
  assert.equal(invoke({ status: 1, stderr: 'permission denied' }), null)
  f.create('work/clang-modules')
  assert.equal(cacheInUse(join(f.root, 'work/clang-modules'), { execute: command => command === 'ps' ? { status: 0, stdout: '' } : { status: 1 } }), false)
})

test('idle expiry and LRU budget preserve fresh, busy, unknown and current caches', async t => {
  const f = fixture(t), paths = ['.build', 'work/unit-test-build', 'work/clang-modules', 'work/swiftpm-cache']
  for (const path of paths) f.create(path)
  f.seed(paths.map((path, i) => f.entry(path, i + 1)))
  const lock = await f.lock()
  try {
    let report = pruneBuildCaches(lock, { now: 5, idleMs: 10, budgetBytes: 100, inUse: free, measure: () => 10 })
    assert.equal(report.removed.length, 0)
    report = pruneBuildCaches(lock, { now: 5, idleMs: 10, budgetBytes: 30, inUse: free, measure: () => 10 })
    assert.deepEqual(report.removed, ['.build']); assert.equal(report.remainingBytes, 30)
    report = pruneBuildCaches(lock, { now: 100, idleMs: 10, budgetBytes: 1, protect: ['work/swiftpm-cache'],
      measure: path => fs.existsSync(path) ? 10 : 0, inUse: path => path.endsWith('unit-test-build') ? true : null })
    assert.equal(report.removed.length, 0); assert.equal(report.skipped.length, 2); assert.equal(report.overBudget, true)
    report = pruneBuildCaches(lock, { now: 100, idleMs: 10, budgetBytes: 100, protect: ['work/swiftpm-cache'], inUse: free })
    assert.deepEqual(report.removed.sort(), ['work/clang-modules', 'work/unit-test-build'])
    assert.equal(fs.existsSync(join(f.root, 'work/swiftpm-cache/generated')), true)
    assert.equal(JSON.parse(fs.readFileSync(join(f.directory, 'latest-cleanup.json'))).removed.length, 2)
  } finally { lock.release() }
})

test('unregistered work products, sources, test results and release archives survive cleanup', async t => {
  const f = fixture(t)
  for (const path of ['Sources', 'work/random-task', 'work/test-results', 'work/ios/Release.xcarchive', 'work/ios-build/Logs', 'outputs']) f.create(path)
  f.create('.build'); fs.symlinkSync(join(f.root, 'Sources'), join(f.root, '.build/link'), 'junction')
  f.seed([f.entry('.build')])
  const lock = await f.lock()
  try { assert.deepEqual(pruneBuildCaches(lock, { now: Date.now(), inUse: free }).removed, ['.build']) } finally { lock.release() }
  for (const path of ['Sources', 'work/random-task', 'work/test-results', 'work/ios/Release.xcarchive', 'work/ios-build/Logs', 'outputs']) assert.equal(fs.readFileSync(join(f.root, path, 'generated'), 'utf8'), 'cache')
})

test('invalid registry data, linked ancestors, measurement errors and deletion failures fail safely', async t => {
  const f = fixture(t); f.create('.build')
  const lock = await f.lock()
  try {
    for (const data of [{ version: 2, entries: [] }, { version: 1, entries: {} }, { version: 1, entries: [f.entry('Sources')] },
      { version: 1, entries: [{ ...f.entry('.build'), lastUsedAt: null }] }, { version: 1, entries: [{ ...f.entry('.build'), temporary: true }] }]) {
      fs.writeFileSync(f.registry, JSON.stringify(data)); assert.throws(() => pruneBuildCaches(lock)); assert.equal(fs.existsSync(join(f.root, '.build/generated')), true)
    }
    f.seed([f.entry('.build')])
    assert.equal(pruneBuildCaches(lock, { measure() { throw Error('cannot measure') } }).skipped[0].reason, 'cannot measure')
    const report = pruneBuildCaches(lock, { now: Date.now(), inUse: free, remove() { throw Error('cannot delete') } })
    assert.equal(report.skipped[0].reason, 'cannot delete')
    assert.equal(report.overBudget, true)
    assert.equal(fs.existsSync(join(f.root, '.build/generated')), true)
  } finally { lock.release() }
})

test('temporary caches are removed on success and failure; reusable caches are kept', async t => {
  const f = fixture(t); let temporary
  for (const fail of [false, true]) {
    const run = () => withBuildCache(f.root, 'temporary', ({ directory }) => {
      temporary = directory; fs.writeFileSync(join(directory, 'object.o'), 'rebuildable')
      if (fail) throw Error('fixture compiler failed')
      return 23
    }, { started, inUse: free, log: logger })
    if (fail) await assert.rejects(run(), /compiler failed/)
    else assert.equal(await run(), 23)
    assert.equal(fs.existsSync(temporary), false)
    assert.equal(fs.existsSync(f.lockPath), false)
  }
  await withBuildCache(f.root, 'temporary', ({ directory }) => { temporary = directory }, { started, inUse: free, log: logger })
  assert.equal(fs.existsSync(temporary), false, 'An empty temporary directory must also be reclaimed')
  f.create('.build')
  assert.equal(await withBuildCache(f.root, 'macos', () => 0, { started, inUse: free, log: logger }), 0)
  assert.equal(fs.existsSync(join(f.root, '.build/generated')), true)
  assert.equal(JSON.parse(fs.readFileSync(f.registry)).entries.find(entry => entry.path === '.build').temporary, false)
  await assert.rejects(withBuildCache(f.root, 'unknown', () => assert.fail()), /未知/)
  assert.equal(cacheBudgetBytes, 20 * 1024 ** 3); assert.equal(cacheIdleMs, 7 * 24 * 60 * 60 * 1000)
})

test('cleanup errors preserve the original action result and always release the lease', async t => {
  const f = fixture(t), logs = []
  const result = await withBuildCache(f.root, 'macos', () => {
    fs.writeFileSync(f.registry, '{broken'); return 7
  }, { started, log: text => logs.push(text) })
  assert.equal(result, 7); assert.equal(fs.existsSync(f.lockPath), false)
  assert.ok(logs.some(text => text.includes('回收未完成')))
})

test('a busy temporary cache is reported and reclaimed by a later finished task', async t => {
  const f = fixture(t), logs = []; let temporary
  await withBuildCache(f.root, 'temporary', ({ directory }) => {
    temporary = directory; fs.writeFileSync(join(directory, 'object.o'), 'busy')
  }, { started, inUse: () => null, log: text => logs.push(text) })
  assert.equal(fs.existsSync(temporary), true)
  assert.ok(logs.some(text => text.includes('超过预算或有目录暂无法回收')))
  await withBuildCache(f.root, 'macos', () => 0, { started, inUse: free, log: logger })
  assert.equal(fs.existsSync(temporary), false)
})

test('native operations queue, time out and honor abort without stealing active locks', async t => {
  const f = fixture(t), events = [], logs = []
  const first = await f.lock()
  // Queue acquisition must not expire if filesystem work or timer delivery is slow.
  const waiting = f.lock({ state: () => 'alive', waitMs: 30, now: () => 0, log: text => logs.push(text) }).then(lock => { events.push('second'); return lock })
  await new Promise(accept => setTimeout(accept, 5)); assert.deepEqual(events, [])
  first.release(); const second = await waiting
  assert.equal(logs.length, 1); assert.deepEqual(events, ['second'])
  await assert.rejects(f.lock({ waitMs: 0, state: () => 'unknown' }), /另一个构建/)
  const controller = new AbortController(); controller.abort()
  await assert.rejects(f.lock({ signal: controller.signal }), { name: 'AbortError' })
  // Release is token-specific, even when a stale instance attempts it twice.
  first.release(); assert.equal(fs.existsSync(f.lockPath), true)
  second.release(); second.release()
})

test('only verifiably dead owners with unused directories allow orphan-lock recovery', async t => {
  const f = fixture(t)
  const owner = { pid: 123, started: 1, token: 'old', paths: ['.build'] }
  fs.writeFileSync(f.lockPath, JSON.stringify(owner))
  const oldSession = process.env.BENCHGAUGE_BUILD_CACHE_SESSION
  process.env.BENCHGAUGE_BUILD_CACHE_SESSION = 'old'
  try { await assert.rejects(f.lock({ waitMs: 0 }), /嵌套/) }
  finally {
    if (oldSession == null) delete process.env.BENCHGAUGE_BUILD_CACHE_SESSION
    else process.env.BENCHGAUGE_BUILD_CACHE_SESSION = oldSession
  }
  for (const value of [true, null]) await assert.rejects(f.lock({ waitMs: 0, state: () => 'gone', inUse: () => value }), /另一个构建/)
  const recovered = await f.lock({ waitMs: 0, state: () => 'gone', inUse: free }); recovered.release()
  fs.writeFileSync(f.lockPath, JSON.stringify({ ...owner, child: { pid: 456, started: 2 } }))
  await assert.rejects(f.lock({ waitMs: 0, state: value => value.pid === 123 ? 'gone' : 'alive', inUse: free }), /另一个构建/)
  const childExited = await f.lock({ waitMs: 0, state: () => 'gone', inUse: free }); childExited.release()
  for (const text of ['', '{broken', 'null']) {
    fs.writeFileSync(f.lockPath, text)
    await assert.rejects(f.lock({ waitMs: 0 }), /另一个构建/)
    assert.equal(fs.readFileSync(f.lockPath, 'utf8'), text)
  }
})

test('management directories refuse linked or file ancestors and propagate filesystem errors', async t => {
  const f = fixture(t)
  fs.rmSync(join(f.root, 'work'), { recursive: true })
  fs.writeFileSync(join(f.root, 'work'), 'source')
  await assert.rejects(f.lock(), /管理目录/)
  fs.rmSync(join(f.root, 'work')); fs.mkdirSync(join(f.root, 'private'))
  fs.symlinkSync(join(f.root, 'private'), join(f.root, 'work'), 'junction')
  await assert.rejects(f.lock(), /管理目录/)
  fs.rmSync(join(f.root, 'work')); fs.mkdirSync(f.directory, { recursive: true })
  fs.mkdirSync(f.lockPath)
  await assert.rejects(f.lock({ waitMs: 0 }), /另一个构建/)
})

test('command wrapper preserves exit codes, generated outputs and temporary-cache cleanup', async t => {
  const f = fixture(t), before = process.listenerCount('SIGTERM')
  const code = `const fs=require('node:fs');fs.writeFileSync(process.env.BENCHGAUGE_TEMP_CACHE+'/object.o','cache');fs.writeFileSync('output.txt','keep');process.exitCode=17`
  assert.equal(await runCachedCommand(f.root, 'temporary', process.execPath, ['-e', code], { started, inUse: free, log: logger }), 17)
  assert.equal(fs.readFileSync(join(f.root, 'output.txt'), 'utf8'), 'keep')
  assert.equal(fs.readdirSync(join(f.directory, 'temporary')).length, 0)
  await assert.rejects(runCachedCommand(f.root, 'temporary', join(f.root, 'missing-command'), [], { started, inUse: free, log: logger }), /ENOENT/)
  assert.equal(process.listenerCount('SIGTERM'), before)
  assert.equal(fs.existsSync(f.lockPath), false)
})

test('command cancellation forwards signals to the owned process group and handles terminated children', async t => {
  const f = fixture(t), listeners = new Map(), signals = [], descriptor = Object.getOwnPropertyDescriptor(process, 'platform')
  const on = process.on
  t.mock.method(process, 'on', function(event, handler) {
    if (event === 'SIGINT' || event === 'SIGTERM') { listeners.set(event, handler); return this }
    return on.call(this, event, handler)
  })
  let denied = false
  t.mock.method(process, 'kill', (pid, signal) => { signals.push([pid, signal]); if (denied) throw Error('already gone') })
  t.mock.method(cp, 'spawn', (_command, _args, options) => {
    const child = new EventEmitter(); child.pid = 900000; child.kill = signal => signals.push(['child', signal])
    assert.equal(options.detached, process.platform !== 'win32')
    queueMicrotask(() => { listeners.get('SIGINT')(); listeners.get('SIGTERM')(); child.emit('close', null) })
    return child
  })
  syncBuiltinESMExports()
  t.after(() => { Object.defineProperty(process, 'platform', descriptor); t.mock.restoreAll(); syncBuiltinESMExports() })
  for (const platform of ['darwin', 'win32']) {
    Object.defineProperty(process, 'platform', { ...descriptor, value: platform })
    assert.equal(await runCachedCommand(f.root, 'macos', 'fixture', [], { started, inUse: free, log: logger }), 1)
  }
  Object.defineProperty(process, 'platform', descriptor); denied = true
  assert.equal(await runCachedCommand(f.root, 'macos', 'fixture', [], { started, inUse: free, log: logger }), 1)
  assert.ok(signals.some(([pid, signal]) => pid === -900000 && signal === 'SIGTERM'))
  assert.ok(signals.some(([pid, signal]) => pid === 'child' && signal === 'SIGINT'))
})

test('CLI status, cleanup and managed temporary commands only touch an isolated repository', t => {
  const f = fixture(t); fs.mkdirSync(join(f.root, 'Scripts'))
  fs.copyFileSync(new URL('build-cache.mjs', import.meta.url), join(f.root, 'Scripts/build-cache.mjs'))
  const invoke = args => spawnSync(process.execPath, [join(f.root, 'Scripts/build-cache.mjs'), ...args], { cwd: f.root, encoding: 'utf8', timeout: 15_000 })
  const initial = invoke(['status']); assert.equal(initial.status, 0); assert.equal(JSON.parse(initial.stdout).registry, null)
  assert.match(invoke(['unknown']).stderr, /用法/)
  assert.match(invoke(['run', 'unknown', '--', process.execPath]).stderr, /未知/)
  const generated = invoke(['run', 'temporary', '--', process.execPath, '-e', "require('node:fs').writeFileSync(process.env.BENCHGAUGE_TEMP_CACHE+'/cache','generated')"])
  assert.equal(generated.status, 0, generated.stdout + generated.stderr)
  assert.equal(fs.readdirSync(join(f.directory, 'temporary')).length, 0)
  f.create('work/clang-modules'); f.seed([f.entry('work/clang-modules')])
  const cleaned = invoke(['clean']); assert.equal(cleaned.status, 0, cleaned.stderr)
  assert.deepEqual(JSON.parse(cleaned.stdout).removed, ['work/clang-modules'])
  const status = JSON.parse(invoke(['status']).stdout)
  assert.equal(status.active, null); assert.equal(status.registry.version, 1)
  assert.equal(status.latestCleanup.removed[0], 'work/clang-modules')
})
