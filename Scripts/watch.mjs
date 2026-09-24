#!/usr/bin/env node
// 轮询 Sources/、Package.swift、两个 make-app.sh，以及 git 未提交改动。
// 变更停止 WATCH_DEBOUNCE_MS（默认 60 秒），且距上次运行至少 WATCH_THROTTLE_MS（默认 60 秒）后，
// 先按目的拆成原子提交并推送到上游，再在源码变化时重建并重启。
// 构建、提交或推送失败后，同一签名不再空转。WATCH_AUTOCOMMIT=0 关闭自动提交。
// COMMIT_PUSH=0 或 WATCH_AUTOPUSH=0 关闭自动推送。
// git 不读 macOS 系统代理；未设置 https_proxy 时，推送改用 scutil 读到的代理。

import { spawn, spawnSync } from 'node:child_process'
import { existsSync, lstatSync, readdirSync, statSync } from 'node:fs'
import { dirname, join, relative, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { avatarForModel, detectModelName } from './commit-identity.mjs'
import { materializeAvatar, notifyDesktop } from './desktop-notify.mjs'
import { gitProxyArgs, gitProxyValue } from './git-network.mjs'

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const appPath = join(root, 'outputs', 'AI-BenchGauge.app')

export function nextWaitMs({ now, lastChangeAt, lastRunAt = null, debounceMs, throttleMs }) {
  const sinceChange = Number(lastChangeAt)
  const debounceRemaining = Number.isFinite(sinceChange) ? Math.max(0, sinceChange + debounceMs - now) : debounceMs
  const throttleRemaining = lastRunAt == null ? 0 : Math.max(0, lastRunAt + throttleMs - now)
  return Math.max(debounceRemaining, throttleRemaining)
}

export function sourceNewerThanApp(files, appMtime) {
  if (appMtime == null) return true
  for (const mtime of files.values()) {
    if (mtime > appMtime) return true
  }
  return false
}

export function autocommitEnabled(env = process.env) {
  return env.WATCH_AUTOCOMMIT !== '0' && env.DEPLOY_AUTOCOMMIT !== '0'
}

export function autopushEnabled(env = process.env) {
  if (!autocommitEnabled(env)) return false
  return env.COMMIT_PUSH !== '0' && env.WATCH_AUTOPUSH !== '0'
}

function readDuration(name, fallback) {
  const raw = process.env[name]
  if (raw == null || raw === '') return fallback
  const value = Number(raw)
  if (!Number.isFinite(value) || value < 0) throw new Error(`${name} 无效：${raw}`)
  return value
}

function watchTargets() {
  return [
    join(root, 'Sources'),
    join(root, 'Package.swift'),
    join(root, 'make-app.sh'),
    join(root, 'Scripts', 'make-app.sh'),
  ].filter((path) => existsSync(path))
}

function isAccessDenied(error) {
  return error?.code === 'EPERM' || error?.code === 'EACCES'
}

function collect(path, files) {
  let stat
  try {
    stat = statSync(path, { throwIfNoEntry: false })
  } catch (error) {
    if (isAccessDenied(error)) {
      console.warn(`[watch] 无法读取 ${path}：${error.code}，本轮跳过`)
      return
    }
    throw error
  }
  if (!stat) return
  if (stat.isFile()) {
    files.set(relative(root, path), stat.mtimeMs)
    return
  }
  if (!stat.isDirectory()) return
  let names
  try {
    names = readdirSync(path)
  } catch (error) {
    if (isAccessDenied(error)) {
      console.warn(`[watch] 无法读取 ${path}：${error.code}，本轮跳过`)
      return
    }
    throw error
  }
  for (const name of names) {
    if (name.startsWith('.')) continue
    collect(join(path, name), files)
  }
}

function snapshot() {
  const files = new Map()
  for (const path of watchTargets()) collect(path, files)
  return files
}

function signature(files) {
  return [...files.entries()]
    .sort(([left], [right]) => left.localeCompare(right))
    .map(([path, mtime]) => `${path}:${mtime}`)
    .join('\0')
}

function currentAppMtime() {
  const stat = statSync(appPath, { throwIfNoEntry: false })
  return stat ? stat.mtimeMs : null
}

function gitSync(args) {
  return spawnSync('git', args, {
    cwd: root,
    encoding: 'utf8',
    maxBuffer: 16 * 1024 * 1024,
  })
}

export function dirtyStatusSignature(status, fingerprintForPath) {
  if (!status) return ''
  const fingerprints = []
  const entries = status.split('\0')
  for (let index = 0; index < entries.length; index += 1) {
    const entry = entries[index]
    if (!entry) continue
    const path = entry.slice(3)
    fingerprints.push(`${path}:${fingerprintForPath(path)}`)
    // rename/copy 在 -z 格式中多带一个旧路径记录。
    if (/[RC]/.test(entry.slice(0, 2))) index += 1
  }
  fingerprints.push(`index:${fingerprintForPath('.git/index')}`)
  return `${status}\u0001${fingerprints.join('\0')}`
}

function fileFingerprint(path) {
  try {
    const stat = lstatSync(join(root, path), { bigint: true, throwIfNoEntry: false })
    return stat ? `${stat.size}:${stat.mtimeNs}:${stat.ctimeNs}` : 'missing'
  } catch (error) {
    if (isAccessDenied(error)) return `unreadable:${error.code}`
    throw error
  }
}

function gitStatusSignature() {
  const result = gitSync(['status', '--porcelain', '-z', '--untracked-files=all'])
  if (result.error) {
    if (!isAccessDenied(result.error)) console.warn(`[watch] git 状态检查失败：${result.error.message}`)
    return null
  }
  if (result.status !== 0) {
    console.warn(`[watch] git 状态检查失败：${(result.stderr || '').trim() || `退出码 ${result.status}`}`)
    return null
  }
  const status = result.stdout ?? ''
  // porcelain 只包含文件名和状态；同一批文件继续编辑时，它不会变化。
  // 失败后的重试判断还需要文件及暂存区的变化时间。
  return dirtyStatusSignature(status, fileFingerprint)
}

export function parseAheadCount(stdout) {
  const parts = String(stdout || '').trim().split(/\s+/)
  if (parts.length < 2) return null
  const ahead = Number(parts[1])
  return Number.isFinite(ahead) ? ahead : null
}

let loggedUpstreamError = ''

function unpushedState() {
  const result = gitSync(['rev-list', '--left-right', '--count', '@{upstream}...HEAD'])
  if (result.error) {
    if (!isAccessDenied(result.error) && result.error.message !== loggedUpstreamError) {
      loggedUpstreamError = result.error.message
      console.warn(`[watch] 上游检查失败：${result.error.message}`)
    }
    return { state: 'unknown', signature: '', count: 0 }
  }
  if (result.status !== 0) return { state: 'no-upstream', signature: '', count: 0 }
  loggedUpstreamError = ''
  const ahead = parseAheadCount(result.stdout)
  if (ahead == null) return { state: 'unknown', signature: '', count: 0 }
  if (ahead <= 0) return { state: 'synced', signature: '', count: 0 }
  const head = gitSync(['rev-parse', 'HEAD'])
  if (head.status !== 0 || head.error) return { state: 'unknown', signature: '', count: ahead }
  return { state: 'ahead', signature: (head.stdout || '').trim(), count: ahead }
}

function run(script) {
  return new Promise((resolvePromise) => {
    const child = spawn(script, [], {
      cwd: root,
      env: { ...process.env, LOCAL_CI_NOTIFY_OWNER: 'watch' },
      stdio: 'inherit',
    })
    child.on('error', (error) => resolvePromise({ status: 1, error }))
    child.on('close', (status) => resolvePromise({ status: status ?? 1 }))
  })
}

function runNode(script, extraEnv = {}) {
  return new Promise((resolvePromise) => {
    const child = spawn(process.execPath, [script], {
      cwd: root,
      env: { ...process.env, ...extraEnv },
      stdio: 'inherit',
    })
    child.on('error', (error) => resolvePromise({ status: 1, error }))
    child.on('close', (status) => resolvePromise({ status: status ?? 1 }))
  })
}

let announcedProxy = false

function runGit(args) {
  const proxy = gitProxyValue()
  const gitArgs = [...gitProxyArgs(), ...args]
  if (!announcedProxy && proxy) {
    announcedProxy = true
    console.log(`[watch] git 没有代理环境变量，推送改用系统代理 ${proxy}`)
  }
  return new Promise((resolvePromise) => {
    const child = spawn('git', gitArgs, {
      cwd: root,
      env: { ...process.env, GIT_TERMINAL_PROMPT: '0' },
      stdio: 'inherit',
    })
    child.on('error', (error) => resolvePromise({ status: 1, error }))
    child.on('close', (status) => resolvePromise({ status: status ?? 1 }))
  })
}

async function notify(ok, title, message) {
  if (process.env.DESKTOP_NOTIFY === '0') return
  let image = ''
  try {
    image = materializeAvatar(avatarForModel(detectModelName()))
  } catch {
    image = ''
  }
  try {
    notifyDesktop(root, title, message, { kind: ok ? 'success' : 'failure', image, wait: true })
  } catch (error) {
    console.warn(`[watch] 桌面通知失败：${error.message}`)
  }
}

async function rebuild() {
  console.log('[watch] 开始重建…')
  const built = await run(join(root, 'Scripts', 'make-app.sh'))
  if (built.status !== 0) {
    const detail = built.error ? built.error.message : `make-app.sh 退出码 ${built.status}`
    console.error(`[watch] 构建失败：${detail}`)
    await notify(false, '构建失败', detail)
    return false
  }
  console.log('[watch] 开始重启…')
  const restarted = await run(join(root, 'Scripts', 'restart.sh'))
  if (restarted.status !== 0) {
    const detail = restarted.error ? restarted.error.message : `restart.sh 退出码 ${restarted.status}`
    console.error(`[watch] 重启失败：${detail}`)
    await notify(false, '重启失败', detail)
    return false
  }
  console.log('[watch] 已重建并重启')
  await notify(true, '已重启', `${detectModelName()}\n菜单栏应用已使用最新代码重新打开。`)
  return true
}

function main() {
  let debounceMs
  let throttleMs
  let pollMs
  try {
    debounceMs = readDuration('WATCH_DEBOUNCE_MS', 60_000)
    throttleMs = readDuration('WATCH_THROTTLE_MS', 60_000)
    pollMs = Math.max(200, readDuration('WATCH_POLL_MS', 1_000))
  } catch (error) {
    console.error(`[watch] ${error.message}`)
    process.exit(1)
  }

  const commitEnabled = autocommitEnabled()
  const pushEnabled = autopushEnabled()
  let timer = null
  let busy = false
  let lastChangeAt = 0
  let lastRunAt = null
  let failedSignature = null
  let failedCommitSignature = null
  let failedPushSignature = null
  let lastAheadSignature = ''
  let warnedNoUpstream = false
  let lastSignature = ''
  let lastGitSignature = gitStatusSignature()
  let lastRebuiltSignature = null

  function clearTimer() {
    if (!timer) return
    clearTimeout(timer)
    timer = null
  }

  function actionLabel() {
    if (!commitEnabled) return '重建并重启'
    return pushEnabled ? '原子提交并推送，并在源码变化时重建重启' : '原子提交，并在源码变化时重建重启'
  }

  function schedule(reason, at, { retryPush = false } = {}) {
    if (retryPush) failedPushSignature = null
    lastChangeAt = at
    if (busy) {
      console.log(`[watch] ${reason}，当前正在提交、推送或构建，结束后再调度`)
      return
    }
    const wait = nextWaitMs({
      now: Date.now(),
      lastChangeAt,
      lastRunAt,
      debounceMs,
      throttleMs,
    })
    clearTimer()
    const eta = new Date(Date.now() + wait).toLocaleTimeString('zh-CN', { hour12: false })
    console.log(`[watch] ${reason}，将于 ${eta} ${actionLabel()}（防抖 ${Math.round(debounceMs / 1000)} 秒，节流 ${Math.round(throttleMs / 1000)} 秒）`)
    timer = setTimeout(runScheduled, wait)
  }

  async function runScheduled() {
    timer = null
    const builtSignature = signature(snapshot())
    const gitSignature = gitStatusSignature()
    busy = true
    lastRunAt = Date.now()
    let commitStatus = 0
    let rebuiltOk = true
    let attemptedRebuild = false
    try {
      if (commitEnabled && gitSignature && gitSignature !== failedCommitSignature) {
        console.log('[watch] 开始原子提交…')
        const commitEnv = { COMMIT_REQUIRE_LOCK: '1' }
        if (pushEnabled) commitEnv.COMMIT_PUSH = '0'
        const committed = await runNode(join(root, 'Scripts', 'commit.mjs'), commitEnv)
        commitStatus = committed.status
        if (committed.status === 0) {
          const after = gitStatusSignature()
          if (after && after === gitSignature) {
            console.warn('[watch] 提交进程已退出，但改动仍在，这一版不再自动重试')
            failedCommitSignature = gitSignature
          } else {
            console.log('[watch] 原子提交完成')
            failedCommitSignature = null
          }
        } else if (committed.status === 75) {
          console.log('[watch] 提交锁被占用，稍后重试')
        } else {
          const detail = committed.error ? committed.error.message : `commit.mjs 退出码 ${committed.status}`
          console.error(`[watch] 原子提交失败：${detail}`)
          failedCommitSignature = gitSignature
          if (committed.error) await notify(false, '提交失败', detail)
        }
      } else if (commitEnabled && gitSignature && gitSignature === failedCommitSignature) {
        console.log('[watch] 这一版提交已失败，等待下次保存')
      }

      if (pushEnabled) {
        const ahead = unpushedState()
        if (ahead.state === 'no-upstream') {
          if (!warnedNoUpstream) {
            console.warn('[watch] 当前分支没有上游，跳过自动推送')
            warnedNoUpstream = true
          }
        } else if (ahead.state === 'ahead' && ahead.signature !== failedPushSignature) {
          console.log(`[watch] 开始推送 ${ahead.count} 个提交…`)
          const pushed = await runGit(['push'])
          if (pushed.status === 0) {
            const after = unpushedState()
            if (after.state === 'ahead') {
              const detail = 'git push 已退出，但上游仍落后'
              console.error(`[watch] 推送失败：${detail}`)
              failedPushSignature = after.signature
              lastAheadSignature = after.signature
              await notify(false, '推送失败', detail)
            } else {
              console.log('[watch] 已推送')
              failedPushSignature = null
              lastAheadSignature = ''
            }
          } else {
            const detail = pushed.error ? pushed.error.message : `git push 退出码 ${pushed.status}`
            console.error(`[watch] 推送失败：${detail}`)
            failedPushSignature = ahead.signature
            lastAheadSignature = ahead.signature
            await notify(false, '推送失败', detail)
          }
        }
      }

      attemptedRebuild = builtSignature !== lastRebuiltSignature && builtSignature !== failedSignature
      if (builtSignature === failedSignature) {
        console.log('[watch] 这一版已经构建失败，等待下次保存')
        rebuiltOk = false
      } else if (attemptedRebuild) {
        rebuiltOk = await rebuild()
        if (rebuiltOk) lastRebuiltSignature = builtSignature
        failedSignature = rebuiltOk ? null : builtSignature
      } else {
        console.log('[watch] 源码未变，跳过重建')
      }
    } catch (error) {
      console.error(`[watch] ${error.message}`)
      await notify(false, '自动任务失败', error.message)
      rebuiltOk = false
    }
    busy = false
    const latest = signature(snapshot())
    const latestGit = gitStatusSignature()
    lastSignature = latest
    if (latestGit != null) lastGitSignature = latestGit
    if (!rebuiltOk && attemptedRebuild) console.log('[watch] 同一签名不再自动重试，请再保存一次或重启 ./dev.sh')
    const sourceMoved = latest !== builtSignature && latest !== failedSignature
    const gitMoved = commitEnabled && latestGit && latestGit !== failedCommitSignature
    const latestAhead = pushEnabled ? unpushedState() : null
    if (latestAhead && latestAhead.state !== 'ahead') lastAheadSignature = ''
    const aheadMoved = latestAhead?.state === 'ahead'
      && latestAhead.signature
      && latestAhead.signature !== failedPushSignature
    if (commitStatus === 75 || sourceMoved || gitMoved || aheadMoved) {
      if (aheadMoved) lastAheadSignature = latestAhead.signature
      schedule(commitStatus === 75 ? '提交锁被占用，稍后重试' : '运行期间有新变更', Date.now(), {
        retryPush: sourceMoved || gitMoved,
      })
    }
  }

  const initial = snapshot()
  const initialSignature = signature(initial)
  lastSignature = initialSignature
  lastRebuiltSignature = sourceNewerThanApp(initial, currentAppMtime()) ? null : initialSignature
  const dirty = commitEnabled && Boolean(lastGitSignature)
  const staleApp = lastRebuiltSignature == null
  const initialAhead = pushEnabled ? unpushedState() : { state: 'synced', signature: '', count: 0 }
  lastAheadSignature = initialAhead.signature
  if (initialAhead.state === 'no-upstream') {
    console.warn('[watch] 当前分支没有上游，跳过自动推送')
    warnedNoUpstream = true
  }
  const ahead = initialAhead.state === 'ahead'
  if (dirty || staleApp) {
    const reason = dirty && staleApp
      ? '启动时检测到未提交改动，且源码新于已构建应用'
      : dirty
        ? '启动时检测到未提交改动'
        : '源码新于已构建应用'
    schedule(ahead ? `${reason}，且有未推送提交` : reason, Date.now())
  } else if (ahead) {
    schedule('启动时检测到未推送提交', Date.now() - debounceMs)
  } else {
    console.log('[watch] 应用已是最新，等待源码变更')
  }
  console.log(commitEnabled
    ? `[watch] 监听 Sources/、Package.swift、make-app.sh，并自动原子提交${pushEnabled ? '、推送' : ''}；Ctrl-C 停止。`
    : '[watch] 监听 Sources/、Package.swift、make-app.sh；Ctrl-C 停止。不自动提交。')

  const poll = setInterval(() => {
    let next
    try {
      next = signature(snapshot())
    } catch (error) {
      console.warn(`[watch] 扫描源码失败：${error.message}`)
      return
    }
    const nextGit = gitStatusSignature()
    const nextAhead = pushEnabled ? unpushedState() : null
    const sourceChanged = next !== lastSignature && next !== failedSignature
    const gitChanged = commitEnabled && nextGit && nextGit !== lastGitSignature && nextGit !== failedCommitSignature
    const aheadChanged = nextAhead?.state === 'ahead'
      && nextAhead.signature
      && nextAhead.signature !== lastAheadSignature
      && nextAhead.signature !== failedPushSignature
    if (nextAhead && nextAhead.state !== 'ahead') lastAheadSignature = ''
    if (!sourceChanged && !gitChanged && !aheadChanged) return
    if (sourceChanged) lastSignature = next
    if (nextGit != null && nextGit !== failedCommitSignature) lastGitSignature = nextGit
    if (aheadChanged) lastAheadSignature = nextAhead.signature
    const reason = sourceChanged ? '检测到源码变更' : gitChanged ? '检测到未提交改动' : '检测到未推送提交'
    schedule(reason, Date.now(), { retryPush: sourceChanged || gitChanged })
  }, pollMs)

  const stop = () => {
    clearTimer()
    clearInterval(poll)
    console.log('\n[watch] 已停止')
    process.exit(0)
  }
  process.on('SIGINT', stop)
  process.on('SIGTERM', stop)
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main()
