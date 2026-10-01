import { resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { ci } from './calmmit.mjs'

const { runCiProcess } = await ci.load('ci-process')

export function updateDependencies({
  platform = process.platform,
  execute = runCiProcess,
  log = console.log,
} = {}) {
  const commands =
    platform === 'win32'
      ? [
          [
            'dotnet',
            [
              'package',
              'update',
              '--project',
              'apps/windows/BenchGauge.Shared/BenchGauge.Shared.csproj',
            ],
          ],
          [
            'dotnet',
            ['package', 'update', '--project', 'apps/windows/BenchGauge/BenchGauge.csproj'],
          ],
        ]
      : [['swift', ['package', 'update']]]
  for (const [command, args] of commands) {
    log(`[upgrade] ${JSON.stringify([command, ...args])}`)
    const result = execute(command, args, {
      cwd: ci.root,
      timeout: 600_000,
      maxBuffer: 64 * 1024 * 1024,
      liveOutput: true,
      progress: { label: 'upgrade' },
    })
    if (result.error || result.status !== 0) {
      log(
        `[upgrade] 更新失败：${result.error?.message || `退出码 ${result.status}`}；交由启动器报告并沿用现有依赖`,
      )
      return 1
    }
  }
  return 0
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url))
  process.exitCode = updateDependencies()
