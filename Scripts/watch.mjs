#!/usr/bin/env node
// 轮询 Sources/、Package.swift、两个 make-app.sh，以及 git 未提交改动。
// 变更停止 WATCH_DEBOUNCE_MS（默认 60 秒），且距上次运行至少 WATCH_THROTTLE_MS（默认 60 秒）后，
// 先按目的拆成原子提交，再在源码变化时重建并重启。
// 构建或提交失败后，同一签名不再空转。WATCH_AUTOCOMMIT=0 关闭自动提交。

import { spawn, spawnSync } from 'node:child_process'
import { existsSync, readdirSync, statSync } from 'node:fs'
import { dirname, join, relative, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { avatarForModel, detectModelName } from './commit-identity.mjs'
import { materializeAvatar, notifyDesktop } from './desktop-notify.mjs'

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const appPath = join(root, 'outputs', 'AI-Leaderboards.app')

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

function gitStatusSignature() {
  const result = spawnSync('git', ['status', '--porcelain', '-z', '--untracked-files=all'], {
    cwd: root,
    encoding: 'utf8',
    maxBuffer: 16 * 1024 * 1024,
  })
  if (result.error) {
    if (!isAccessDenied(result.error)) console.warn(`[watch] git 状态检查失败：${result.error.message}`)
    return null
  }
  if (result.status !== 0) {
    console.warn(`[watch] git 状态检查失败：${(result.stderr || '').trim() || `退出码 ${result.status}`}`)
    return null
  }
  return result.stdout ?? ''
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
  let timer = null
  let busy = false
  let lastChangeAt = 0
  let lastRunAt = null
  let failedSignature = null
  let failedCommitSignature = null
  let lastSignature = ''
  let lastGitSignature = gitStatusSignature()
  let lastRebuiltSignature = null

  function clearTimer() {
    if (!timer) return
    clearTimeout(timer)
    timer = null
  }

  function actionLabel() {
    return commitEnabled ? '原子提交，并在源码变化时重建重启' : '重建并重启'
  }

  function schedule(reason, at) {
    lastChangeAt = at
    if (busy) {
      console.log(`[watch] ${reason}，当前正在提交或构建，结束后再调度`)
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
        const committed = await runNode(join(root, 'Scripts', 'commit.mjs'), { COMMIT_REQUIRE_LOCK: '1' })
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
    if (commitStatus === 75 || sourceMoved || gitMoved) {
      schedule(commitStatus === 75 ? '提交锁被占用，稍后重试' : '运行期间有新变更', Date.now())
    }
  }

  const initial = snapshot()
  const initialSignature = signature(initial)
  lastSignature = initialSignature
  lastRebuiltSignature = sourceNewerThanApp(initial, currentAppMtime()) ? null : initialSignature
  const dirty = commitEnabled && Boolean(lastGitSignature)
  const staleApp = lastRebuiltSignature == null
  if (dirty || staleApp) {
    const reason = dirty && staleApp
      ? '启动时检测到未提交改动，且源码新于已构建应用'
      : dirty
        ? '启动时检测到未提交改动'
        : '源码新于已构建应用'
    schedule(reason, Date.now())
  } else {
    console.log('[watch] 应用已是最新，等待源码变更')
  }
  console.log(commitEnabled
    ? '[watch] 监听 Sources/、Package.swift、make-app.sh，并自动原子提交；Ctrl-C 停止。'
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
    const sourceChanged = next !== lastSignature && next !== failedSignature
    const gitChanged = commitEnabled && nextGit && nextGit !== lastGitSignature && nextGit !== failedCommitSignature
    if (!sourceChanged && !gitChanged) return
    if (sourceChanged) lastSignature = next
    if (nextGit != null && nextGit !== failedCommitSignature) lastGitSignature = nextGit
    schedule(sourceChanged ? '检测到源码变更' : '检测到未提交改动', Date.now())
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
