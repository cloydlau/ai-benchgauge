// 同一仓库同时只允许一个提交流程。属主被强杀时按锁龄回收，
// 避免沙箱里 process.kill 返回 EPERM 时把残留锁当成活锁。

import { closeSync, openSync, readFileSync, statSync, unlinkSync, writeSync } from 'node:fs'

export const DEFAULT_LOCK_STALE_MS = 10 * 60_000

const defaultFs = { openSync, writeSync, closeSync, statSync, readFileSync, unlinkSync }

export function pidState(pid) {
  if (!Number.isFinite(pid) || pid <= 0) return 'unknown'
  try {
    process.kill(pid, 0)
    return 'alive'
  } catch (error) {
    return error?.code === 'ESRCH' ? 'gone' : 'unknown'
  }
}

function removeStaleLock(fs, lockPath, before) {
  const after = fs.statSync(lockPath)
  if (after.ino === before.ino && after.mtimeMs === before.mtimeMs) fs.unlinkSync(lockPath)
}

export function acquireCommitLock({
  lockPath,
  pid = process.pid,
  staleMs = DEFAULT_LOCK_STALE_MS,
  now = Date.now(),
  state = pidState,
  fs = defaultFs,
  warn = () => {},
} = {}) {
  let released = false
  const release = () => {
    if (released) return
    released = true
    try {
      fs.unlinkSync(lockPath)
    } catch {
      /* 已被清理 */
    }
  }

  for (let attempt = 0; attempt < 2; attempt += 1) {
    try {
      const fd = fs.openSync(lockPath, 'wx')
      try {
        fs.writeSync(fd, String(pid))
      } finally {
        fs.closeSync(fd)
      }
      return { acquired: true, release }
    } catch {
      /* 锁已存在 */
    }

    let before
    let owner = 0
    try {
      before = fs.statSync(lockPath)
      owner = Number(fs.readFileSync(lockPath, 'utf8')) || 0
    } catch {
      return { acquired: false, reason: 'unreadable' }
    }

    const ownerState = state(owner)
    if (ownerState === 'alive') return { acquired: false, reason: 'busy' }
    if (ownerState === 'gone' || now - before.mtimeMs > staleMs) {
      try {
        removeStaleLock(fs, lockPath, before)
      } catch {
        return { acquired: false, reason: 'unreadable' }
      }
      if (ownerState !== 'gone') {
        warn(`回收残留提交锁：属主 pid ${owner || '未知'} 已超过 ${Math.round(staleMs / 60_000)} 分钟`)
      }
      continue
    }
    warn(`另一个提交进程持锁（pid ${owner || '未知'}）`)
    return { acquired: false, reason: 'busy_unverifiable' }
  }
  return { acquired: false, reason: 'attempts_exhausted' }
}
