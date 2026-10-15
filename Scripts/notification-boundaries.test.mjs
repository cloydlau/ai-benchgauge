import assert from 'node:assert/strict'
import test from 'node:test'
import cp from 'node:child_process'
import fs from 'node:fs'
import { syncBuiltinESMExports } from 'node:module'
import { EventEmitter } from 'node:events'
import { homedir, tmpdir } from 'node:os'
import { join } from 'node:path'
import { notifyDesktop, materializeAvatar } from './desktop-notify.mjs'
import { notificationAppName, ensureNotificationApp, deliverNotification } from './desktop-notify-worker.mjs'

function mockBuiltin(t, object, name, implementation) {
  t.mock.method(object, name, implementation)
  syncBuiltinESMExports()
  t.after(() => { t.mock.restoreAll(); syncBuiltinESMExports() })
}
function directory(t) {
  const root = fs.mkdtempSync(join(tmpdir(), 'benchgauge-notify-boundary-'))
  t.after(() => fs.rmSync(root, { recursive: true, force: true }))
  return root
}

test('notification launch respects opt-out, platform, synchronous failure and detached lifecycle', t => {
  const root = directory(t)
  assert.equal(notifyDesktop(root, 'title', 'body', { env: { DESKTOP_NOTIFY: '0' }, platform: 'darwin' }), false)
  assert.equal(notifyDesktop(root, 'title', '', { env: {}, platform: 'linux' }), false)
  let response = { status: 0 }
  mockBuiltin(t, cp, 'spawnSync', (_command, args, options) => {
    assert.equal(args[3], ' ')
    assert.equal(options.env.CALMMIT_NOTIFY_DIR, join(root, 'work/notify-apps'))
    return response
  })
  assert.equal(notifyDesktop(root, 'title', null, { platform: 'darwin', wait: true, env: {} }), true)
  response = { error: Error('could not launch') }
  assert.equal(notifyDesktop(root, 'title', '', { platform: 'darwin', wait: true, env: {} }), false)
  response = { status: 1 }
  assert.equal(notifyDesktop(root, 'title', '', { platform: 'darwin', wait: true, env: {} }), false)
  let unreferenced = false
  const warnings = []
  t.mock.method(console, 'warn', value => warnings.push(value))
  mockBuiltin(t, cp, 'spawn', (_command, args, options) => {
    assert.equal(args[1], 'failure')
    assert.equal(args[4], 'image.png')
    assert.equal(options.env.CALMMIT_NOTIFY_DIR, 'custom')
    const child = new EventEmitter()
    child.unref = () => { unreferenced = true; child.emit('error', Error('asynchronous launch')) }
    return child
  })
  assert.equal(notifyDesktop(root, 'title', 'body', { kind: 'failure', image: 'image.png', platform: 'darwin', env: { CALMMIT_NOTIFY_DIR: 'custom' } }), true)
  assert.ok(unreferenced)
  assert.match(warnings[0], /asynchronous launch/)
  cp.spawn = () => { throw Error('synchronous launch') }; syncBuiltinESMExports()
  assert.equal(notifyDesktop(root, 'title', 'body', { platform: 'darwin', env: {} }), false)
  assert.match(warnings[1], /synchronous launch/)
})

test('avatar conversion tries candidates, SVG thumbnails, and returns only an existing PNG', t => {
  let mode = 'png'
  const outputs = []
  t.after(() => { for (const output of outputs) fs.rmSync(output, { recursive: true, force: true }) })
  mockBuiltin(t, cp, 'spawnSync', (command, args) => {
    if (command.endsWith('/curl')) {
      if (args.at(-1) === 'bad') return { status: 1 }
      const path = args[args.indexOf('-o') + 1]
      outputs.push(path.substring(0, path.lastIndexOf('/')))
      if (mode !== 'missing') fs.writeFileSync(path, mode === 'not-svg' ? 'invalid format' : '<svg></svg>')
      return { status: 0 }
    }
    if (command.endsWith('/sips')) {
      if (mode === 'png') { fs.writeFileSync(args.at(-1), 'PNG'); return { status: 0 } }
      if (mode === 'unreadable') fs.unlinkSync(args[3])
      return { status: 1 }
    }
    assert.ok(command.endsWith('/qlmanage'))
    if (mode === 'thumbnail-error') return { error: Error('thumbnail failed') }
    if (mode === 'thumbnail-status') return { status: 1 }
    if (mode === 'thumbnail') fs.writeFileSync(join(args[args.indexOf('-o') + 1], 'avatar.svg.png'), 'thumbnail')
    return { status: 0 }
  })
  const png = materializeAvatar({ candidates: ['bad', 'good'] })
  assert.equal(fs.readFileSync(png, 'utf8'), 'PNG')
  mode = 'thumbnail'
  assert.equal(fs.readFileSync(materializeAvatar({ url: 'good' }), 'utf8'), 'thumbnail')
  for (mode of ['missing', 'not-svg', 'unreadable', 'thumbnail-error', 'thumbnail-status', 'no-thumbnail']) {
    assert.equal(materializeAvatar({ url: 'good' }), '', mode)
  }
  mode = 'thumbnail'
  const originalCopy = fs.copyFileSync
  mockBuiltin(t, fs, 'copyFileSync', (source, target) => {
    if (target.endsWith('avatar.svg')) throw Error('copy failed')
    return originalCopy(source, target)
  })
  assert.equal(materializeAvatar({ url: 'good' }), '')
  const originalRemove = fs.rmSync, leaked = []
  t.after(() => { for (const path of leaked) originalRemove(path, {recursive:true,force:true}) })
  mockBuiltin(t, fs, 'rmSync', (path, options) => {
    if (String(path).includes('leaderboard-avatar-thumb-')) { leaked.push(path); throw Error('thumbnail cleanup failed') }
    return originalRemove(path, options)
  })
  assert.throws(() => materializeAvatar({ url: 'good' }), /thumbnail cleanup failed/)
})

test('notification apps are built in staging, reused and cleaned up after compilation errors or races', t => {
  const root = directory(t)
  assert.equal(notificationAppName('failure'), 'Calmmit Failure')
  assert.throws(() => notificationAppName('unknown'), /未知通知类型/)
  let failure = null, race = false, calls = 0
  mockBuiltin(t, cp, 'spawnSync', (command, args) => {
    calls++
    if (failure) return failure
    if (args.includes('clang')) {
      fs.writeFileSync(args.at(-1), 'fixture binary')
      if (race) {
        const app = join(root, 'Calmmit Success.app/Contents')
        fs.mkdirSync(join(app, 'MacOS'), { recursive: true }); fs.mkdirSync(join(app, 'Resources'), { recursive: true })
        fs.writeFileSync(join(app, 'MacOS/notification-settings'), 'another builder')
        fs.writeFileSync(join(app, 'Resources/notification-revision'), '4')
      }
    }
    return { status: 0, stdout: '' }
  })
  const app = ensureNotificationApp('success', root)
  assert.equal(fs.readFileSync(join(app, 'Contents/Resources/notification-revision'), 'utf8'), '4')
  const previous = calls
  assert.equal(ensureNotificationApp('success', root), app)
  assert.equal(calls, previous)
  fs.rmSync(app, { recursive: true })
  race = true
  assert.equal(ensureNotificationApp('success', root), app)
  fs.rmSync(app, { recursive: true }); race = false
  for (failure of [{ error: Error('launch failed') }, { status: 2, stderr: 'compile failed' }, { status: 3 }]) {
    assert.throws(() => ensureNotificationApp('success', root), /launch failed|compile failed|退出码 3/)
    assert.deepEqual(fs.readdirSync(root), [])
  }
  failure = null
  cp.spawnSync = () => {
    const contents = join(app, 'Contents')
    fs.mkdirSync(join(contents, 'MacOS'), { recursive: true }); fs.mkdirSync(join(contents, 'Resources'), { recursive: true })
    fs.writeFileSync(join(contents, 'MacOS/notification-settings'), 'concurrent builder')
    fs.writeFileSync(join(contents, 'Resources/notification-revision'), '4')
    return { status: 1 }
  }; syncBuiltinESMExports()
  assert.equal(ensureNotificationApp('success', root), app)
  ensureNotificationApp('success', root)
  const originalRead = fs.readFileSync
  let first = true
  mockBuiltin(t, fs, 'readFileSync', (path, ...args) => {
    if (String(path).endsWith('notification-revision') && first) { first = false; throw Error('temporarily unreadable') }
    return originalRead(path, ...args)
  })
  // A concurrently restored app is still preferred over the staged build.
  assert.equal(ensureNotificationApp('success', root), app)
  assert.deepEqual(fs.readdirSync(root), ['Calmmit Success.app'])
})

test('delivery validates receipts, stops on permission failures and safely executes an isolated sender', t => {
  const root = directory(t)
  let attempts = 0
  assert.throws(() => deliverNotification('success', '', '', '', { directories: ['first', 'second'], ensureApp: () => { attempts++; throw Error('permission denied') } }), /permission/)
  assert.equal(attempts, 1)
  assert.throws(() => deliverNotification('success', '', '', '', { directories: [], ensureApp: () => '' }), /无法发送通知/)
  assert.throws(() => deliverNotification('success', '', '', '', { directories: [root], ensureApp: () => { throw {} } }))
  assert.throws(() => deliverNotification('success', '', '', '', { directories: [root], ensureApp: () => { throw null } }), /无法发送通知/)
  assert.throws(() => deliverNotification('success', '', '', '', { directories: [root], ensureApp: () => root, send: () => null }), /缺少系统回执/)
  mockBuiltin(t, cp, 'spawnSync', (_command, args) => {
    const payload = JSON.parse(fs.readFileSync(args[1], 'utf8'))
    assert.equal(payload.title, '')
    assert.equal(payload.message, ' ')
    assert.equal(payload.image, '')
    return { status: 0, stdout: JSON.stringify({ accepted: true, notificationId: 'fixture' }) }
  })
  assert.equal(deliverNotification('success', null, null, '', { directories: [root], ensureApp: () => root }).notificationId, 'fixture')
})

test('worker CLI handles native receipts, fallback and failure without sending real notifications', async t => {
  const root = directory(t)
  const exists = fs.existsSync, read = fs.readFileSync
  mockBuiltin(t, fs, 'existsSync', path => String(path).startsWith(join(homedir(), 'Applications/Calmmit')) ? true : exists(path))
  mockBuiltin(t, fs, 'readFileSync', (path, ...args) => String(path).startsWith(join(homedir(), 'Applications/Calmmit')) ? '4' : read(path, ...args))
  let mode = 'native'
  mockBuiltin(t, cp, 'spawnSync', (command) => {
    if (command.endsWith('/osascript')) return mode === 'failed' ? { status: 1 } : { status: 0 }
    return mode === 'native' ? { status: 0, stdout: '{"accepted":true,"notificationId":"fixture"}' } : { status: 1, stderr: 'permission denied' }
  })
  const logs = []
  for (const method of ['log', 'warn', 'error']) t.mock.method(console, method, value => logs.push(value))
  const argv = process.argv, code = process.exitCode, configured = process.env.CALMMIT_NOTIFY_DIR
  t.after(() => { process.argv = argv; process.exitCode = code; if (configured === undefined) delete process.env.CALMMIT_NOTIFY_DIR; else process.env.CALMMIT_NOTIFY_DIR = configured })
  for (mode of ['native', 'fallback', 'failed', 'default-directory']) {
    if (mode === 'default-directory') delete process.env.CALMMIT_NOTIFY_DIR
    else process.env.CALMMIT_NOTIFY_DIR = mode === 'native' ? join(homedir(), 'Applications') : root
    const image = join(root, `leaderboard-avatar-${mode}.png`)
    fs.writeFileSync(image, 'fixture')
    process.argv = [argv[0], '/fixture/desktop-notify-worker.mjs', 'success', 'title', 'body', image]
    await import(`./desktop-notify-worker.mjs?fixture=${mode}`)
    assert.equal(fs.existsSync(image), false)
  }
  assert.equal(process.exitCode, 1)
  assert.ok(logs.some(value => value.includes('系统已接受')))
  assert.ok(logs.some(value => value.includes('已改用')))
})

test('notification CLI validates usage and propagates synchronous failure', async t => {
  const argv = process.argv, code = process.exitCode
  const logs = []
  t.mock.method(console, 'error', value => logs.push(value))
  mockBuiltin(t, cp, 'spawnSync', () => ({ status: 1 }))
  mockBuiltin(t, cp, 'spawn', () => { const child = new EventEmitter(); child.unref = () => {}; return child })
  t.after(() => { process.argv = argv; process.exitCode = code })
  for (const [index, args] of [[], ['--wait', 'success', 'title', 'message'], ['success', 'title', 'message']].entries()) {
    process.argv = [argv[0], '/fixture/desktop-notify.mjs', ...args]
    await import(`./desktop-notify.mjs?fixture=${index}`)
  }
  assert.equal(process.exitCode, 1)
  assert.match(logs[0], /用法/)
})


test('notification delivery accepts a single configured home application directory', async t => {
  const {homedir}=await import('node:os')
  const previous=process.env.CALMMIT_NOTIFY_DIR
  process.env.CALMMIT_NOTIFY_DIR=join(homedir(),'Applications')
  t.after(()=>{if(previous===undefined)delete process.env.CALMMIT_NOTIFY_DIR;else process.env.CALMMIT_NOTIFY_DIR=previous})
  const receipt=deliverNotification('success','fixture','fixture','',{ensureApp:(_kind,directory)=>{assert.equal(directory,process.env.CALMMIT_NOTIFY_DIR);return 'unit-only-app'},send:()=>({accepted:true})})
  assert.equal(receipt.accepted,true)
})
