import { collectSources, validGrant } from './acquisition.js'
import { shouldAutoRefresh } from '../core/freshness.js'
import { boards, hasOwn } from '../core/catalog.js'
import { normalizeBoard, canReplace, withContentTimestamp } from '../core/leaderboard.js'

const CACHE_KEY = 'benchgauge.boards.v1'
function snapshotFile(platform) {
  if (!platform.env?.USER_DATA_PATH || !platform.getFileSystemManager) return null
  return { fs: platform.getFileSystemManager(), path: `${platform.env.USER_DATA_PATH}/benchgauge-boards-v1.json` }
}
function loadSnapshots(platform) {
  try {
    const file = snapshotFile(platform)
    if (file) return JSON.parse(file.fs.readFileSync(file.path, 'utf8'))
  } catch { /* A missing or incomplete file can still fall back to the old cache. */ }
  return platform.getStorageSync(CACHE_KEY)
}
export function readCachedBoard(platform, kind) {
  if (!hasOwn(boards, kind)) return null
  try {
    const saved = loadSnapshots(platform)?.[kind]
    return saved ? normalizeBoard(saved, kind) : null
  } catch { return null }
}
function saveSnapshots(platform, snapshots) {
  try {
    const file = snapshotFile(platform)
    if (file) {
      // Provider offers and embedded icons can exceed a single storage key's
      // capacity. Rename only after the complete replacement file is written.
      file.fs.writeFileSync(file.path + '.tmp', JSON.stringify(snapshots), 'utf8')
      file.fs.renameSync(file.path + '.tmp', file.path)
      try { platform.removeStorageSync?.(CACHE_KEY) } catch { /* Migration already saved. */ }
      return
    }
  } catch { /* Preserve the previous file and try the legacy cache. */ }
  platform.setStorageSync(CACHE_KEY, snapshots)
}
export function createBoardStore({ platform, endpoint }) {
  const snapshots = {}
  const pending = new Map()
  const tasks = new Set()
  let disposed = false
  try {
    const saved = loadSnapshots(platform)
    for (const kind of Object.keys(boards)) {
      if (saved?.[kind]) {
        try { snapshots[kind] = normalizeBoard(saved[kind], kind) } catch { /* One corrupt board must not erase the others. */ }
      }
    }
  } catch { /* Cache availability does not control network access. */ }
  function read(kind) { return snapshots[kind] || null }
  function request(options) {
    return new Promise((resolve, reject) => {
      if (disposed) { reject(new Error('Store disposed')); return }
      let task, completed = false
      task = platform.request({ ...options,
        success(result) {
          if (disposed) reject(new Error('Store disposed'))
          else if (result.statusCode !== 200) reject(new Error('Shared service unavailable'))
          else resolve(result)
        },
        fail() { reject(new Error('Shared service unavailable')) },
        complete() { completed = true; tasks.delete(task) },
      })
      if (!completed) tasks.add(task)
    })
  }
  function accept(payload, kind) {
    if (!payload?.board) {
      if (payload?.configurationRequired === true) throw Object.assign(new Error('Data source awaiting configuration'), { code: 'configurationRequired' })
      throw new Error('No shared snapshot yet')
    }
    const next = normalizeBoard(payload.board, kind)
    if (canReplace(next, snapshots[kind])) {
      snapshots[kind] = snapshots[kind] ? withContentTimestamp(next, snapshots[kind]) : next
      try { saveSnapshots(platform, snapshots) } catch { /* Still show valid network data. */ }
    }
    return snapshots[kind]
  }
  function fetch(kind, onCachedBoard, { readFirst = false } = {}) {
    if (!hasOwn(boards, kind)) return Promise.reject(new Error('Unknown leaderboard'))
    if (kind === 'valsSWEbench') return Promise.reject(new Error('Leaderboard retired'))
    if (disposed) return Promise.reject(new Error('Store disposed'))
    if (pending.has(kind)) return pending.get(kind)
    const path = `${endpoint}/v1/boards/${kind}`
    const api = (action, extra = {}) => request({ url: path + action, method: action ? 'POST' : 'GET', timeout: 30000,
      header: { Accept: 'application/json', 'X-BenchGauge-Acquisition': 'client-first', ...extra.header }, ...extra })
    const promise = (async () => {
      if (readFirst) {
        // First render must not wait for a refresh lease or an origin download.
        // Network failure ends this attempt promptly; explicit refresh can retry.
        const shared = (await api('', { timeout: 8000 })).data
        if (shared?.board) {
          const cached = accept(shared, kind)
          onCachedBoard?.(cached)
          if (!shouldAutoRefresh(cached, null)) return cached
        } else if (shared?.configurationRequired) return accept(shared, kind)
      }
      const response = (await api('/refresh')).data
      if (!response?.grant?.acquisition) return accept(response, kind)
      // Persist shared cache before waiting on the user's origin connection.
      if (response.board) onCachedBoard?.(accept(response, kind))
      const grant = response.grant
      if (!validGrant(grant)) {
        if (snapshots[kind]) return snapshots[kind]
        throw new Error('Invalid refresh grant')
      }
      const header = { 'X-BenchGauge-Grant': grant.token, 'Content-Type': 'application/json' }
      try {
        const data = await collectSources(platform, request, grant)
        if (!validGrant(grant)) throw new Error('Expired refresh grant')
        return accept((await api('/acquire', { header, data })).data, kind)
      } catch {
        if (disposed) throw new Error('Store disposed')
        try { return accept((await api('/fallback', { header })).data, kind) }
        catch {
          if (disposed) throw new Error('Store disposed')
          // An upload can commit despite a lost response; check before using cache.
          try { return accept((await api('')).data, kind) }
          catch { if (snapshots[kind]) return snapshots[kind]; throw new Error('Shared service unavailable') }
        }
      }
    })().finally(() => pending.delete(kind))
    pending.set(kind, promise)
    return promise
  }
  function dispose() {
    disposed = true
    for (const task of tasks) task?.abort?.()
    tasks.clear()
  }
  return { read, fetch, dispose }
}
