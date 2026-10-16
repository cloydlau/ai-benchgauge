import { execFileSync } from 'node:child_process'
import { isUtf8 } from 'node:buffer'
import { lstatSync, readFileSync, realpathSync } from 'node:fs'
import { resolve } from 'node:path'

// Match Watrek's public counters; isolated upload builds pass the original repo root.
export function engineeringInvestment(repository) {
  const root = realpathSync(repository)
  const git = args => execFileSync('git', args, { cwd: root, encoding: 'utf8' })
  if (realpathSync(git(['rev-parse', '--show-toplevel']).trim()) !== root) {
    throw new Error('Engineering investment requires the product repository root')
  }
  if (git(['rev-parse', '--is-shallow-repository']).trim() === 'true') {
    throw new Error('Engineering investment requires full Git history; use fetch-depth: 0')
  }
  const commitCount = Number(git(['rev-list', '--count', 'HEAD']).trim())
  const ignored = new Set(git(['ls-files', '-z', '-c', '-i', '--exclude-standard']).split('\0'))
  const tracked = new Set(git(['ls-files', '-z', '--', 'Sources/', 'apps/', 'fc/']).split('\0').filter(Boolean))
  let codeLineCount = 0
  for (const path of tracked) {
    if (ignored.has(path) || /(^|\/)(node_modules|dist|bin|obj|generated)\//.test(path)
      || /(^|\/)(package-lock\.json|pnpm-lock\.yaml)$/.test(path)) continue
    const absolute = resolve(root, path)
    const stat = lstatSync(absolute, { throwIfNoEntry: false })
    if (!stat?.isFile()) continue
    const bytes = readFileSync(absolute)
    if (!bytes.length || bytes.includes(0) || !isUtf8(bytes)) continue
    for (const byte of bytes) if (byte === 10) codeLineCount++
    if (bytes.at(-1) !== 10) codeLineCount++
  }
  if (!Number.isSafeInteger(commitCount) || commitCount <= 0) throw new Error('Invalid Git commit count')
  return { commitCount, codeLineCount }
}
