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
  function fetch(kind) {
    if (!hasOwn(boards, kind)) return Promise.reject(new Error('Unknown leaderboard'))
    if (disposed) return Promise.reject(new Error('Store disposed'))
    if (pending.has(kind)) return pending.get(kind)
    const promise = new Promise((resolve, reject) => {
      let task
      task = platform.request({
        url: `${endpoint}/v1/boards/${kind}`, method: 'GET', timeout: kind === 'openRouterPrice' ? 30000 : 15000,
        header: { Accept: 'application/json' },
        success(result) {
          if (disposed) { reject(new Error('Store disposed')); return }
          try {
            if (result.statusCode !== 200) throw new Error('Shared service unavailable')
            if (!result.data?.board) {
              if (result.data?.configurationRequired === true) throw Object.assign(new Error('Data source awaiting configuration'), { code: 'configurationRequired' })
              throw new Error('No shared snapshot yet')
            }
            const next = normalizeBoard(result.data.board, kind)
            if (canReplace(next, snapshots[kind])) {
              // Legacy first reads already carry their baseline in fetchedAt.
              snapshots[kind] = snapshots[kind] ? withContentTimestamp(next, snapshots[kind]) : next
              try { saveSnapshots(platform, snapshots) } catch { /* Still show a valid network result. */ }
            }
            resolve(snapshots[kind])
          } catch (error) { reject(error) }
        },
        fail() { reject(new Error('Shared service unavailable')) },
        complete() { tasks.delete(task) },
      })
      tasks.add(task)
    }).finally(() => pending.delete(kind))
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
