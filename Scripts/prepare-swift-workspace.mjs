import { existsSync, lstatSync, mkdtempSync, readFileSync, renameSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { basename, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

// SwiftPM persists absolute remote-artifact paths. After a repository move,
// preserve the old generated workspace and let SwiftPM resolve it afresh.
export function prepareSwiftWorkspace(root, { log = console.log } = {}) {
  const backups = []
  for (const relative of ['.build', 'work/unit-test-build']) {
    const cache = resolve(root, relative)
    const stateFile = join(cache, 'workspace-state.json')
    if (!existsSync(stateFile) || lstatSync(cache).isSymbolicLink()) continue
    const state = JSON.parse(readFileSync(stateFile, 'utf8'))
    const marker = `/${basename(cache)}/artifacts/`
    const moved = (state.object?.artifacts || []).some((artifact) => {
      if (artifact.source?.type !== 'remote' || typeof artifact.path !== 'string') return false
      const index = artifact.path.lastIndexOf(marker)
      if (index < 0) return false
      const current = join(cache, 'artifacts', artifact.path.slice(index + marker.length))
      return resolve(artifact.path) !== current && existsSync(current)
    })
    if (!moved) continue
    const backup = join(mkdtempSync(join(tmpdir(), 'benchgauge-swift-workspace-')), basename(cache))
    renameSync(cache, backup)
    backups.push(backup)
    log(`[build] 检测到仓库搬迁留下的 Swift 缓存，已备份到 ${backup}；重新解析依赖并构建`)
  }
  return backups
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url))
  prepareSwiftWorkspace(resolve(fileURLToPath(new URL('../', import.meta.url))))
