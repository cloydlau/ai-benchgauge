import { spawnSync } from 'node:child_process'
import { createHash } from 'node:crypto'
import { existsSync, lstatSync, readFileSync, readdirSync, readlinkSync, realpathSync } from 'node:fs'
import { release } from 'node:os'
import { basename, dirname, join, resolve, sep } from 'node:path'

// These are removed from every test child, so they cannot affect test results.
export const testParentVariables = ['GIT_INDEX_FILE', 'BENCHGAUGE_TEST_PASS', 'COMMIT_PUSH',
  'COMMIT_REQUIRE_LOCK', 'CALMMIT_AI_COMMIT_TICKET', 'CALMMIT_AI_COMMIT_ROOT', 'CALMMIT_INTERNAL', 'CALMMIT_TEST_INDEX',
  'CALMMIT_ROOT', 'CALMMIT_CONFIG', 'COMMIT_PLAN_FILE', 'CODEX_TOOL_CALL_ID']

export function testIndexMatchesWorkspace(root, index, env = process.env) {
  if (!index) return false
  const gitEnv = { ...env }
  for (const key of Object.keys(gitEnv)) if (key.startsWith('GIT_')) delete gitEnv[key]
  const directory = spawnSync('git', ['-C', root, 'rev-parse', '--absolute-git-dir'], { env: gitEnv, encoding: 'utf8' })
  if (directory.error || directory.status !== 0) return false
  let path
  try { path = realpathSync(index) } catch { return false }
  if (!/^commit-index-\d+$/.test(path.slice(path.lastIndexOf(sep) + 1)) || resolve(directory.stdout.trim(), path.slice(path.lastIndexOf(sep) + 1)) !== path) return false
  gitEnv.GIT_INDEX_FILE = path
  const diff = spawnSync('git', ['-C', root, 'diff', '--quiet', '--no-ext-diff', '--'], { env: gitEnv })
  if (diff.error || diff.status !== 0) return false
  const untracked = spawnSync('git', ['-C', root, 'ls-files', '-z', '--others', '--exclude-standard'], { env: gitEnv, encoding: 'buffer' })
  return !untracked.error && untracked.status === 0 && untracked.stdout.length === 0
}

export function coverageSummaryDigest(root, directory) {
  try {
    if (typeof directory !== 'string') return null
    const path = resolve(directory)
    if (dirname(path) !== resolve(root, 'work/test-results') || !/^coverage-\d+-[1-9]\d*$/.test(basename(path))) return null
    if (!lstatSync(path).isDirectory() || !lstatSync(join(path, 'summary.json')).isFile()) return null
    return createHash('sha256').update(readFileSync(join(path, 'summary.json'))).digest('hex')
  } catch { return null }
}

// Return no attestation when inputs cannot be enumerated or read. This is only
// used for cross-process reuse; ordinary tests still run when it is unavailable.
export function testReuseSignature(root, env, { native, node, library, versions } = {}) {
  try {
    root = realpathSync(root)
    const hash = createHash('sha256')
    const effectiveEnv = Object.fromEntries(Object.entries(env)
      .filter(([key]) => !testParentVariables.includes(key)).sort(([a], [b]) => a.localeCompare(b)))
    hash.update(JSON.stringify(['benchgauge-full-coverage-v1', process.platform, process.arch,
      release(), process.version, node, native, effectiveEnv]))
    const gitEnv = { ...env }
    for (const key of Object.keys(gitEnv)) if (key.startsWith('GIT_')) delete gitEnv[key]
    const files = spawnSync('git', ['-C', root, 'ls-files', '-z', '--cached', '--others', '--exclude-standard'],
      { env: gitEnv, encoding: 'buffer', maxBuffer: 64 * 1024 * 1024 })
    if (files.error || files.status !== 0) return null
    const effectiveGitEnv = { ...env }
    for (const key of testParentVariables) delete effectiveGitEnv[key]
    const gitConfig = spawnSync('git', ['-C', root, 'config', '--list', '--show-origin', '--null'],
      { env: effectiveGitEnv, encoding: 'buffer', maxBuffer: 64 * 1024 * 1024 })
    if (gitConfig.error || gitConfig.status !== 0) return null
    hash.update(gitConfig.stdout)
    const seen = new Set()
    const allowed = [root, ...(library ? [realpathSync(library)] : [])]
    function collect(path) {
      const info = lstatSync(path)
      hash.update(JSON.stringify([path, info.mode]))
      if (info.isSymbolicLink()) {
        hash.update(readlinkSync(path))
        const target = realpathSync(path)
        if (!allowed.some(base => target === base || target.startsWith(base + sep))) throw Error('external symlink')
        if (!seen.has(target)) collect(target)
      } else if (info.isDirectory()) {
        const actual = realpathSync(path)
        if (seen.has(actual)) return
        seen.add(actual)
        for (const name of readdirSync(path).sort()) collect(join(path, name))
      } else if (info.isFile()) {
        hash.update(readFileSync(path))
      } else throw Error('unsupported input')
    }
    for (const name of [...new Set(files.stdout.toString('utf8').split('\0').filter(Boolean))].sort()) {
      const path = join(root, name)
      if (lstatSync(path, { throwIfNoEntry: false })) collect(path)
      else hash.update(JSON.stringify([path, 'deleted']))
    }
    for (const path of ['node_modules', 'apps/weapp/node_modules', 'fc/node_modules', '.npmrc',
      '.env', '.env.local', '.env.test', '.env.test.local', 'apps/weapp/.env', 'apps/weapp/.env.local',
      'apps/weapp/.env.test', 'apps/weapp/.env.test.local', '.benchgauge-ios.local.json', '.benchgauge-cloud.local.json']) {
      const full = join(root, path)
      if (existsSync(full)) collect(full)
      else hash.update(JSON.stringify([full, 'absent']))
    }
    if (library) for (const path of ['src', 'bin', 'node_modules', 'package.json', 'pnpm-lock.yaml']) {
      const full = join(library, path)
      if (existsSync(full)) collect(full)
      else hash.update(JSON.stringify([full, 'absent']))
    }
    if (versions) hash.update(JSON.stringify(versions))
    else for (const command of ['git', 'swift', 'dotnet', 'xcodebuild']) {
      const result = spawnSync(command, ['--version'], { env, encoding: 'utf8', timeout: 5000 })
      hash.update(JSON.stringify([command, result.status, result.error?.code, result.stdout, result.stderr]))
    }
    if (!versions) for (const command of ['git', 'swift', 'dotnet', 'xcodebuild', 'xcrun', 'npm', 'pnpm', 'sh', 'zsh']) {
      const located = spawnSync('/usr/bin/which', [command], { env, encoding: 'utf8', timeout: 5000 })
      if (located.error) return null
      const path = located.status === 0 ? located.stdout.trim() : ''
      hash.update(JSON.stringify([command, located.status, path]))
      if (path) hash.update(readFileSync(realpathSync(path)))
    }
    if (node) collect(node)
    return hash.digest('hex')
  } catch { return null }
}
