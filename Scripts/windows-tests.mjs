import { spawnSync } from 'node:child_process'
import { existsSync } from 'node:fs'
import { join } from 'node:path'
import { testRoot } from './test.mjs'
const bundled = join(testRoot, 'work', 'toolchains', 'dotnet', process.platform === 'win32' ? 'dotnet.exe' : 'dotnet')
export const dotnet = process.env.BENCHGAUGE_DOTNET || (existsSync(bundled) ? bundled : 'dotnet')
export function runWindowsTests() {
  const env = { ...process.env, DOTNET_CLI_TELEMETRY_OPTOUT: '1', DOTNET_NOLOGO: '1', DOTNET_CLI_HOME: join(testRoot, 'work', 'dotnet-home'), NUGET_PACKAGES: join(testRoot, 'work', 'nuget') }
  const result = spawnSync(dotnet, ['run', '--project', join(testRoot, 'apps/windows/BenchGauge.Tests/BenchGauge.Tests.csproj'), '-c', 'Release'], { env, stdio: 'inherit' })
  if (result.error) console.error('Windows unit tests require .NET 10 SDK: ' + result.error.message)
  return result.status ?? 1
}
if (process.argv[1]?.endsWith('windows-tests.mjs')) process.exitCode = runWindowsTests()
