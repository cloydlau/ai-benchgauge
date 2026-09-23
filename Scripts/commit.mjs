#!/usr/bin/env node
// 本地提交：
//   Scripts/commit.sh                      自动暂存并按目的拆成多个提交
//   Scripts/commit.sh -m "feat(menu): …"   手动信息，整批一个提交
//   Scripts/commit.sh --identity           查看模型名、邮箱和头像
//   Scripts/commit.sh --dry-run            只打印拆分计划，不创建提交
// COMMIT_SPLIT=0 关闭拆分。COMMIT_CODEX_MESSAGE=0 不用模型生成计划。
// COMMIT_PUSH=1 才会推送。COMMIT_COAUTHOR=1 恢复本人为 committer 并联合署名。
// 模型不可用或计划不合规时，退回按目录和用途分组，不中止提交。

import { spawnSync } from 'node:child_process'
import {
  closeSync, copyFileSync, existsSync, openSync, readdirSync, readFileSync, rmSync, statSync, unlinkSync, utimesSync, writeFileSync,
} from 'node:fs'
import { homedir, tmpdir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { acquireCommitLock, pidState } from './commit-lock.mjs'
import {
  commitArgs, commitIdentityEnv, formatCommitIdentity, resolveCommitIdentity, resolveModelAvatar,
} from './commit-identity.mjs'
import { bannedCommitReason, inferScope, normalizeMessage } from './commit-message.mjs'
import {
  COMMIT_PLAN_SCHEMA, buildCommitPlanPrompt, buildLocalPlan, buildSelectedPatch,
  normalizeCommitPlan, parseStagedPatch, redactBinaryPatchesForPrompt, stagedPatchInventory,
} from './commit-split.mjs'
import { materializeAvatar, notifyDesktop } from './desktop-notify.mjs'

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const lockPath = join(root, '.git', 'commit.lock')
const PLAN_DIFF_MAX = Number(process.env.COMMIT_PLAN_DIFF_MAX ?? 1_000_000)
const PLAN_TIMEOUT_MS = Number(process.env.COMMIT_CODEX_MESSAGE_TIMEOUT_MS ?? 90_000)
const SECRET_RE = /-----BEGIN (?:RSA |EC |OPENSSH |ENCRYPTED )?PRIVATE KEY-----/

const cleanup = new Set()
function onExit(handler) {
  cleanup.add(handler)
  process.on('exit', () => {
    for (const item of cleanup) {
      try { item() } catch { /* 清理失败不阻塞退出 */ }
    }
  })
}

let privateIndex = null
let suppressNotify = false
function privateIndexEnv(extra = {}) {
  return {
    ...process.env,
    ...(privateIndex ? { GIT_INDEX_FILE: privateIndex } : {}),
    ...extra,
  }
}

function git(args, { input, inherit = false, env } = {}) {
  return spawnSync('git', args, {
    cwd: root,
    encoding: 'utf8',
    input,
    stdio: inherit ? 'inherit' : undefined,
    maxBuffer: 64 * 1024 * 1024,
    env: env ?? privateIndexEnv(),
  })
}

function gitOk(args, options = {}) {
  const result = git(args, options)
  if (result.error) throw result.error
  if (result.status !== 0) {
    throw new Error((result.stderr || result.stdout || `git ${args.join(' ')} 失败`).trim())
  }
  return result.stdout ?? ''
}

function setupPrivateIndex() {
  const gitDir = join(root, '.git')
  for (const name of readdirSync(gitDir)) {
    const match = /^commit-index-(\d+)$/.exec(name)
    if (!match) continue
    const path = join(gitDir, name)
    let stale = pidState(Number(match[1])) === 'gone'
    if (!stale) {
      try { stale = Date.now() - statSync(path).mtimeMs > 20 * 60_000 } catch { stale = false }
    }
    if (stale) {
      try { unlinkSync(path) } catch { /* 忽略 */ }
    }
  }
  privateIndex = join(gitDir, `commit-index-${process.pid}`)
  const shared = join(gitDir, 'index')
  if (existsSync(shared)) {
    copyFileSync(shared, privateIndex)
    const { atime, mtime } = statSync(shared)
    utimesSync(privateIndex, atime, mtime)
  }
  onExit(() => {
    try { unlinkSync(privateIndex) } catch { /* 已清理 */ }
  })
}

function parseArgs(argv) {
  const args = argv.slice(2)
  if (args.includes('--help') || args.includes('-h')) return { mode: 'help' }
  if (args.includes('--identity')) return { mode: 'identity' }
  const dryRun = args.includes('--dry-run')
  const rest = args.filter((arg) => arg !== '--dry-run')
  if (rest.some((arg) => ['--amend', '--no-edit', '--allow-empty'].includes(arg) || arg.startsWith('--fixup'))) {
    return { mode: 'passthrough', args: rest, dryRun }
  }
  if (rest[0] === '-m' || rest[0] === '--message') return { mode: 'message', message: rest.slice(1).join(' ').trim(), dryRun }
  if (rest.length === 0) return { mode: 'auto', dryRun }
  if (rest[0].startsWith('-')) return { mode: 'passthrough', args: rest, dryRun }
  return { mode: 'message', message: rest.join(' ').trim(), dryRun }
}

function findCodex() {
  const candidates = [
    'codex',
    '/Applications/ChatGPT.app/Contents/Resources/codex',
    join(homedir(), '.local', 'bin', 'codex'),
    '/opt/homebrew/bin/codex',
    '/usr/local/bin/codex',
  ]
  for (const candidate of candidates) {
    const probe = spawnSync(candidate, ['--version'], { cwd: root, stdio: 'ignore' })
    if (!probe.error && probe.status === 0) return candidate
  }
  return null
}

function parseJson(text) {
  try { return JSON.parse(text) } catch { /* 继续截取 */ }
  const start = text.indexOf('{')
  const end = text.lastIndexOf('}')
  if (start === -1 || end <= start) return null
  try { return JSON.parse(text.slice(start, end + 1)) } catch { return null }
}

function codexPlan({ stat, diff, inventory, split }) {
  if (process.env.COMMIT_CODEX_MESSAGE === '0') return null
  const codex = findCodex()
  if (!codex) {
    console.warn('[commit] 未找到 codex，改为按用途分组')
    return null
  }
  const textSize = redactBinaryPatchesForPrompt(diff).length
  if (textSize > PLAN_DIFF_MAX) {
    console.warn(`[commit] diff 文本超过 ${PLAN_DIFF_MAX} 字符，改为按用途分组`)
    return null
  }
  const schemaPath = join(tmpdir(), `leaderboard-plan-schema-${process.pid}.json`)
  const outputPath = join(tmpdir(), `leaderboard-plan-${process.pid}.json`)
  const stderrPath = join(tmpdir(), `leaderboard-plan-err-${process.pid}.log`)
  writeFileSync(schemaPath, JSON.stringify(COMMIT_PLAN_SCHEMA))
  const prompt = buildCommitPlanPrompt({ stat, diff, inventory, split })
  const args = [
    'exec', '--ephemeral', '--sandbox', 'read-only', '--color', 'never',
    '--output-schema', schemaPath, '-o', outputPath, '-',
  ]
  const model = process.env.COMMIT_CODEX_MESSAGE_MODEL
  if (model) args.splice(1, 0, '-m', model)
  const effort = process.env.COMMIT_CODEX_MESSAGE_EFFORT ?? 'low'
  if (effort && effort !== '0') args.splice(1, 0, '-c', `model_reasoning_effort=${JSON.stringify(effort)}`)
  console.log(`[commit] 正在生成提交计划（上限 ${Math.round(PLAN_TIMEOUT_MS / 1000)} 秒）`)
  const stderrFd = openSync(stderrPath, 'w')
  let run
  try {
    run = spawnSync(codex, args, {
      cwd: root,
      input: prompt,
      encoding: 'utf8',
      timeout: PLAN_TIMEOUT_MS,
      killSignal: 'SIGKILL',
      maxBuffer: 64 * 1024 * 1024,
      stdio: ['pipe', 'ignore', stderrFd],
    })
  } finally {
    closeSync(stderrFd)
    rmSync(schemaPath, { force: true })
  }
  if (run.error || run.status !== 0) {
    console.warn(`[commit] 模型计划失败：${run.error?.message || `退出码 ${run.status}`}，改为按用途分组`)
    rmSync(outputPath, { force: true })
    rmSync(stderrPath, { force: true })
    return null
  }
  rmSync(stderrPath, { force: true })
  let output = ''
  try { output = readFileSync(outputPath, 'utf8') } catch { /* 无输出 */ }
  rmSync(outputPath, { force: true })
  const report = parseJson(output)
  if (!report?.commits) {
    console.warn('[commit] 模型没有返回合法拆分计划，改为按用途分组')
    return null
  }
  return report
}

function stagedPatch() {
  return gitOk([
    '-c', 'core.quotePath=false', 'diff', '--cached', '--binary', '--no-color', '--no-renames',
  ])
}

function assertNoSecrets(diff) {
  const hits = []
  let file = ''
  for (const line of diff.split('\n')) {
    if (line.startsWith('+++ b/')) file = line.slice(6)
    else if (line.startsWith('+') && !line.startsWith('+++') && SECRET_RE.test(line)) hits.push(file || '未知文件')
  }
  if (hits.length) throw new Error(`暂存区含私钥，已中止：${[...new Set(hits)].join('、')}`)
}

function applyCachedPatch(patch, label) {
  const check = git(['apply', '--cached', '--check', '--whitespace=nowarn', '-'], { input: patch })
  if (check.status !== 0) throw new Error(`${label}：${(check.stderr || '').trim() || 'git apply --check 失败'}`)
  const applied = git(['apply', '--cached', '--whitespace=nowarn', '-'], { input: patch })
  if (applied.status !== 0) throw new Error(`${label}：${(applied.stderr || '').trim() || 'git apply 失败'}`)
}

function printPlan(commits) {
  console.log(`[commit] 将拆成 ${commits.length} 个提交：`)
  for (const [index, commit] of commits.entries()) {
    console.log(`  ${index + 1}. ${commit.message}`)
    for (const file of commit.files) {
      const hunks = file.hunks?.length ? ` hunk ${file.hunks.join(',')}` : ''
      console.log(`     - ${file.path}${hunks}`)
    }
  }
}

async function buildPlan(split) {
  const diff = stagedPatch()
  assertNoSecrets(diff)
  const files = parseStagedPatch(diff)
  const inventory = stagedPatchInventory(files)
  const stat = gitOk(['diff', '--cached', '--stat']).trim()
  let source = '用途分组'
  let raw = null
  if (split && process.env.COMMIT_CODEX_MESSAGE !== '0') {
    raw = codexPlan({ stat, diff, inventory, split })
  }
  let normalized = null
  if (raw) {
    try {
      normalized = normalizeCommitPlan(raw, inventory, { single: !split }).map((commit) => {
        const paths = commit.files.map((file) => file.path)
        const message = normalizeMessage(commit.message, inferScope(paths), {
          allowBareSubject: false,
          rejectPromptEcho: true,
        })
        if (!message) throw new Error(`提交信息不合规：${commit.message}`)
        const banned = bannedCommitReason(message.split('\n')[0])
        if (banned) throw new Error(banned)
        return { ...commit, message }
      })
      source = '模型计划'
    } catch (error) {
      console.warn(`[commit] 模型计划无效：${error.message}，改为按用途分组`)
      normalized = null
    }
  }
  if (!normalized) {
    const local = buildLocalPlan(files, { single: !split })
    normalized = normalizeCommitPlan(local, inventory, { single: !split })
    source = '用途分组'
  }
  return {
    source,
    commits: normalized.map((commit) => ({
      ...commit,
      patch: buildSelectedPatch(files, commit.selection),
    })),
  }
}

function commitOne(message, identity, { replayPatch = '' } = {}) {
  if (replayPatch) applyCachedPatch(replayPatch, `重放 ${message} 失败`)
  const result = git(commitArgs(message, identity), {
    inherit: true,
    env: privateIndexEnv(commitIdentityEnv(identity)),
  })
  if (result.status !== 0) throw new Error(`git commit 失败（退出码 ${result.status}）`)
}

function alignSharedIndex() {
  const drift = git(['diff', '--cached', '--quiet', 'HEAD'], { env: process.env })
  if (drift.status === 0) return
  const reset = git(['reset', '-q', '--mixed', 'HEAD'], { env: process.env })
  if (reset.status !== 0) console.warn(`[commit] 共享暂存区对齐失败：${(reset.stderr || '').trim()}`)
}

function planFromFiles(files, { single, source }) {
  const inventory = stagedPatchInventory(files)
  const normalized = normalizeCommitPlan(buildLocalPlan(files, { single }), inventory, { single })
  return {
    source,
    commits: normalized.map((commit) => ({
      ...commit,
      patch: buildSelectedPatch(files, commit.selection),
    })),
  }
}

function replayMatches(commits, expectedTree) {
  let failed = null
  try {
    gitOk(['read-tree', 'HEAD'])
    for (const commit of commits) applyCachedPatch(commit.patch, `检查 ${commit.message} 失败`)
    const replayed = gitOk(['write-tree']).trim()
    if (replayed !== expectedTree) throw new Error('拆分重放后的 tree 与暂存快照不一致')
  } catch (error) {
    failed = error
  }
  gitOk(['read-tree', expectedTree])
  if (failed) throw failed
}

async function ensureReplayablePlan(expectedTree) {
  const plan = await buildPlan(true)
  if (plan.commits.length <= 1) return plan
  try {
    replayMatches(plan.commits, expectedTree)
    return plan
  } catch (error) {
    console.warn(`[commit] ${error.message}，改为按用途分组`)
  }
  const files = parseStagedPatch(stagedPatch())
  const grouped = planFromFiles(files, { single: false, source: '用途分组' })
  if (grouped.commits.length <= 1) return grouped
  try {
    replayMatches(grouped.commits, expectedTree)
    return grouped
  } catch (error) {
    console.warn(`[commit] 用途分组也无法重放：${error.message}，改为单个提交`)
  }
  return planFromFiles(files, { single: true, source: '单个提交' })
}

async function notifyResult(ok, title, message, avatar) {
  if (suppressNotify) return
  let image = ''
  try { image = materializeAvatar(avatar) } catch { image = '' }
  notifyDesktop(root, title, message, { kind: ok ? 'success' : 'failure', image, wait: true })
}

async function main() {
  const parsed = parseArgs(process.argv)
  suppressNotify = Boolean(parsed.dryRun)
  if (parsed.mode === 'help') {
    console.log(`用法：
  Scripts/commit.sh                     自动拆分并提交
  Scripts/commit.sh -m "feat(menu): …"  整批一个提交
  Scripts/commit.sh --identity          查看模型名称和头像
  Scripts/commit.sh --dry-run           只打印计划`)
    return
  }
  const identity = resolveCommitIdentity()
  const avatar = await resolveModelAvatar(identity.model, { fetchBudgetMs: parsed.mode === 'identity' ? 5000 : 2000 })
  identity.avatar = avatar
  if (parsed.mode === 'identity') {
    console.log(`模型：${identity.model}`)
    console.log(`author：${formatCommitIdentity(identity)}`)
    console.log(`committer：${identity.committer.name} <${identity.committer.email}>`)
    console.log(`头像：${avatar.url}（${avatar.probed ? avatar.source : `${avatar.source}，探测未确认`}）`)
    console.log(`候选：${avatar.candidates.join(' ')}`)
    return
  }

  const lock = acquireCommitLock({
    lockPath,
    warn: (message) => console.warn(`[commit] ${message}`),
  })
  if (!lock.acquired) {
    console.log('[commit] 已有另一个提交进程在运行，跳过')
    process.exit(process.env.COMMIT_REQUIRE_LOCK === '1' ? 75 : 0)
  }
  onExit(lock.release)

  if (parsed.mode === 'passthrough') {
    if (parsed.dryRun) {
      console.log(`[commit] dry-run，将以 ${formatCommitIdentity(identity)} 执行 git commit ${parsed.args.join(' ')}`)
      return
    }
    const result = git(['-c', 'gc.auto=0', '-c', `user.name=${identity.committer.name}`, '-c', `user.email=${identity.committer.email}`, 'commit', ...parsed.args, '--author', `${identity.author.name} <${identity.author.email}>`], {
      inherit: true,
      env: privateIndexEnv(commitIdentityEnv(identity)),
    })
    if (result.status !== 0) process.exit(result.status ?? 1)
    return
  }

  setupPrivateIndex()
  if (!privateIndex) throw new Error('私有 index 未就绪，拒绝改动暂存区')
  gitOk(['add', '-A'])
  const names = gitOk(['diff', '--cached', '--name-only', '-z']).split('\0').filter(Boolean)
  if (names.length === 0) {
    console.log('[commit] 没有新改动')
    return
  }
  const expectedTree = gitOk(['write-tree']).trim()
  const split = parsed.mode === 'auto' && process.env.COMMIT_SPLIT !== '0'
  console.log(`[commit] 署名：${formatCommitIdentity(identity)}`)
  console.log(`[commit] 头像：${avatar.url}（${avatar.probed ? avatar.source : `${avatar.source}，探测未确认`}）`)

  if (!split) {
    let message = parsed.message ? normalizeMessage(parsed.message, inferScope(names)) : ''
    if (!message && !parsed.message) {
      const single = await buildPlan(false)
      message = single.commits[0]?.message || ''
      if (message) {
        printPlan(single.commits)
        console.log(`[commit] 拆分来源：${single.source}`)
      }
    }
    if (!message) {
      console.error('[commit] 提交信息需符合 <type>(<scope>): <subject>')
      process.exit(1)
    }
    console.log(`[commit] 提交信息：${message}`)
    if (parsed.dryRun) {
      console.log('[commit] dry-run，未创建提交')
      return
    }
    commitOne(message, identity)
    alignSharedIndex()
    await notifyResult(true, '提交完成', `${identity.model}\n${message}`, avatar)
    if (process.env.COMMIT_PUSH === '1') gitOk(['push'], { inherit: true, env: process.env })
    return
  }

  const plan = await ensureReplayablePlan(expectedTree)
  printPlan(plan.commits)
  console.log(`[commit] 拆分来源：${plan.source}`)
  if (parsed.dryRun) {
    console.log(`[commit] dry-run，${plan.commits.length > 1 ? '重放校验通过，' : ''}未创建提交`)
    return
  }

  if (plan.commits.length === 1) {
    commitOne(plan.commits[0].message, identity)
  } else {
    gitOk(['read-tree', 'HEAD'])
    let completed = 0
    try {
      for (const commit of plan.commits) {
        commitOne(commit.message, identity, { replayPatch: commit.patch })
        completed += 1
      }
    } catch (error) {
      console.error(`[commit] 拆分在第 ${completed + 1} 个提交失败，前 ${completed} 个已创建`)
      alignSharedIndex()
      throw error
    }
    const headTree = gitOk(['rev-parse', 'HEAD^{tree}']).trim()
    if (headTree !== expectedTree) throw new Error('拆分重放后的最终 tree 与预期快照不一致')
  }
  alignSharedIndex()
  const summary = plan.commits.map((commit) => commit.message).join('\n')
  console.log(`[commit] 已创建 ${plan.commits.length} 个提交`)
  await notifyResult(true, `已提交 ${plan.commits.length} 个`, `${identity.model}\n${summary}`, avatar)
  if (process.env.COMMIT_PUSH === '1') gitOk(['push'], { inherit: true, env: process.env })
}

try {
  await main()
} catch (error) {
  console.error(`[commit] ${error.message}`)
  if (!suppressNotify) {
    try {
      notifyDesktop(root, '提交失败', error.message, { kind: 'failure', wait: true })
    } catch { /* 通知失败不掩盖提交错误 */ }
  }
  process.exit(1)
}
