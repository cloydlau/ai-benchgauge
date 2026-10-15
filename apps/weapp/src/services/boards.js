import { boards, hasOwn } from '../core/catalog.js'
import { normalizeBoard, canReplace } from '../core/leaderboard.js'

const CACHE_KEY = 'benchgauge.boards.v1'
export function createBoardStore({ platform, endpoint }) {
  const snapshots = {}
  const pending = new Map()
  const tasks = new Set()
  let disposed = false
  try {
    const saved = platform.getStorageSync(CACHE_KEY)
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
        url: `${endpoint}/v1/boards/${kind}`, method: 'GET', timeout: 15000,
        header: { Accept: 'application/json' },
        success(result) {
          if (disposed) { reject(new Error('Store disposed')); return }
          try {
            if (result.statusCode !== 200) throw new Error('Shared service unavailable')
            if (!result.data?.board) throw new Error('No shared snapshot yet')
            const next = normalizeBoard(result.data.board, kind)
            if (canReplace(next, snapshots[kind])) {
              snapshots[kind] = next
              try { platform.setStorageSync(CACHE_KEY, snapshots) } catch { /* Still show a valid network result. */ }
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
