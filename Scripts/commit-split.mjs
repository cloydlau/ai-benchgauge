// 提交拆分计划的解析与校验。模型只提供分组意图；
// 实际提交内容由 hunk 编号重放，漏项或重复都会拒绝执行。

import { inferScope, localGroupMessage, themeKey } from './commit-message.mjs'

export const COMMIT_PLAN_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  properties: {
    commits: {
      type: 'array',
      minItems: 1,
      items: {
        type: 'object',
        additionalProperties: false,
        properties: {
          message: { type: 'string' },
          files: {
            type: 'array',
            items: {
              type: 'object',
              additionalProperties: false,
              properties: {
                path: { type: 'string' },
                hunks: { type: 'array', items: { type: 'integer', minimum: 1 } },
              },
              required: ['path', 'hunks'],
            },
          },
        },
        required: ['message', 'files'],
      },
    },
  },
  required: ['commits'],
}

const DIFF_GIT_RE = /^diff --git a\/(.*) b\/(.*)$/
const HUNK_RE = /^@@ -\d+(?:,\d+)? \+\d+(?:,\d+)? @@/

function filePath(diffGitLine) {
  const match = DIFF_GIT_RE.exec(diffGitLine)
  if (!match || match[1] !== match[2]) return null
  return match[1]
}

export function parseStagedPatch(diff) {
  const files = []
  let current = null
  for (const line of String(diff ?? '').split('\n')) {
    if (line.startsWith('diff --git ')) {
      const path = filePath(line)
      if (!path) throw new Error(`无法解析 diff 文件路径：${line}`)
      current = { path, header: [line], hunks: [] }
      files.push(current)
      continue
    }
    if (!current) continue
    if (HUNK_RE.test(line)) {
      current.hunks.push({ id: current.hunks.length + 1, lines: [line] })
      continue
    }
    if (current.hunks.length > 0) current.hunks[current.hunks.length - 1].lines.push(line)
    else current.header.push(line)
  }
  return files
}

export function stagedPatchInventory(files) {
  return files.map((file) => ({
    path: file.path,
    hunks: file.hunks.map((hunk) => hunk.id),
  }))
}

function joinPatchLines(lines) {
  // 按换行拆开再拼回去时，二进制补丁结尾的空行会丢掉，
  // git apply 就会报 corrupt binary patch，重放后的 tree 也对不上。
  let text = lines.join('\n')
  if (!text.endsWith('\n')) text += '\n'
  if (lines.includes('GIT binary patch') && !text.endsWith('\n\n')) text += '\n'
  return text
}

export function buildSelectedPatch(files, selection) {
  const patches = []
  for (const file of files) {
    if (!selection.has(file.path)) continue
    const selected = selection.get(file.path)
    if (file.hunks.length === 0) {
      if (file.header.length === 0) continue
      patches.push(joinPatchLines(file.header))
      continue
    }
    const body = file.hunks.filter((hunk) => selected.has(hunk.id)).flatMap((hunk) => hunk.lines)
    if (body.length === 0) continue
    patches.push(joinPatchLines([...file.header, ...body]))
  }
  return patches.join('')
}

function expectedSelections(inventory) {
  const expected = new Map()
  for (const file of inventory) {
    if (expected.has(file.path)) throw new Error(`diff 文件重复：${file.path}`)
    expected.set(file.path, new Set(file.hunks))
  }
  return expected
}

function normalizeSelections(commits, inventory, expected) {
  const seen = new Map(inventory.map((file) => [file.path, new Set()]))
  const wholeFileChanges = new Set()
  const normalized = []
  for (const commit of commits) {
    const message = String(commit?.message ?? '').trim()
    const rawFiles = Array.isArray(commit?.files) ? commit.files : []
    if (!message || rawFiles.length === 0) throw new Error('拆分计划包含空提交')
    const files = []
    const paths = new Set()
    for (const rawFile of rawFiles) {
      const path = String(rawFile?.path ?? '')
      const hunks = Array.isArray(rawFile?.hunks) ? rawFile.hunks : []
      if (!seen.has(path)) throw new Error(`拆分计划包含未知文件：${path}`)
      if (paths.has(path)) throw new Error(`同一提交重复列出文件：${path}`)
      paths.add(path)
      const selected = new Set()
      for (const hunk of hunks) {
        const id = Number(hunk)
        if (!Number.isInteger(id) || id < 1 || id > expected.get(path).size) {
          throw new Error(`${path} 的 hunk 编号无效：${hunk}`)
        }
        if (seen.get(path).has(id)) throw new Error(`${path} 的 hunk ${id} 被重复分配`)
        seen.get(path).add(id)
        selected.add(id)
      }
      const expectedHunks = expected.get(path)
      if (expectedHunks.size > 0 && selected.size === 0) throw new Error(`${path} 未选择任何 hunk`)
      if (expectedHunks.size === 0 && selected.size > 0) throw new Error(`${path} 没有 hunk，不能分配编号`)
      if (expectedHunks.size === 0) {
        if (wholeFileChanges.has(path)) throw new Error(`没有 hunk 的文件被重复分配：${path}`)
        wholeFileChanges.add(path)
      }
      files.push({ path, hunks: [...selected].sort((a, b) => a - b) })
    }
    normalized.push({ message, files })
  }
  for (const [path, assigned] of seen) {
    const required = expected.get(path)
    if (required.size === 0) {
      if (!wholeFileChanges.has(path)) throw new Error(`文件未分配：${path}`)
      continue
    }
    for (const id of required) {
      if (!assigned.has(id)) throw new Error(`${path} 的 hunk ${id} 未分配`)
    }
  }
  return normalized
}

function bucketFor(path) {
  if (path.includes('/Resources/logos/')) return 'logos'
  if (path.startsWith('Sources/LeaderboardCore/')) return 'core'
  if (path.startsWith('Sources/LeaderboardMenu/')) return 'menu'
  if (path.startsWith('Tests/')) return 'tests'
  if (path.endsWith('.md') || path === 'LICENSE') return 'docs'
  if (
    path === 'Package.swift'
    || path === 'make-app.sh'
    || path === 'Scripts/make-app.sh'
    || path === 'Scripts/restart.sh'
    || path === 'Scripts/bump-version.sh'
  ) return 'build'
  if (path.startsWith('Scripts/') || path === 'dev.sh') return 'ci'
  return 'other'
}

function absorbLogos(groups) {
  const logos = groups.get('logos')
  if (!logos?.length) return groups
  const core = groups.get('core') || []
  const menu = groups.get('menu') || []
  const coreUsesLogos = core.some((file) => file.path.includes('OrganizationLogo'))
  const host = coreUsesLogos ? 'core' : menu.length ? 'menu' : core.length ? 'core' : null
  if (!host) return groups
  groups.set(host, [...(groups.get(host) || []), ...logos])
  groups.delete('logos')
  return groups
}

function isLogo(path) {
  return path.includes('/Resources/logos/')
}

function subgroup(bucket, files) {
  const logos = files.filter((file) => isLogo(file.path))
  const rest = files.filter((file) => !isLogo(file.path))
  if (rest.length === 0) return [files]
  const byTheme = new Map()
  for (const file of rest) {
    const key = themeKey(file.path) || `__${bucket}`
    if (!byTheme.has(key)) byTheme.set(key, [])
    byTheme.get(key).push(file)
  }
  if (logos.length) {
    const hostKey = [...byTheme.keys()].find((key) => key.includes('icon')) || [...byTheme.keys()][0]
    byTheme.get(hostKey).push(...logos)
  }
  return [...byTheme.values()]
}

export function buildLocalPlan(files, { single = false } = {}) {
  const inventory = stagedPatchInventory(files)
  if (single || files.length <= 1) {
    return {
      commits: [{
        message: localGroupMessage('other', inventory.map((file) => file.path)),
        files: inventory.map((file) => ({ path: file.path, hunks: file.hunks })),
      }],
    }
  }
  const groups = new Map()
  for (const file of files) {
    const bucket = bucketFor(file.path)
    if (!groups.has(bucket)) groups.set(bucket, [])
    groups.get(bucket).push(file)
  }
  absorbLogos(groups)
  const commits = []
  for (const bucket of ['ci', 'build', 'core', 'menu', 'logos', 'tests', 'docs', 'other']) {
    const grouped = groups.get(bucket)
    if (!grouped?.length) continue
    for (const themed of subgroup(bucket, grouped)) {
      commits.push({
        message: localGroupMessage(bucket, themed.map((file) => file.path)),
        files: themed.map((file) => ({
          path: file.path,
          hunks: file.hunks.map((hunk) => hunk.id),
        })),
      })
    }
  }
  if (commits.length === 0) throw new Error('没有可提交的文件')
  return { commits }
}

export function normalizeCommitPlan(plan, inventory, { single = false } = {}) {
  const commits = Array.isArray(plan?.commits) ? plan.commits : null
  if (!commits?.length) throw new Error('拆分计划缺少 commits')
  if (single && commits.length !== 1) throw new Error('已关闭拆分时只能生成一个提交')
  return normalizeSelections(commits, inventory, expectedSelections(inventory)).map((commit) => ({
    ...commit,
    selection: new Map(commit.files.map((file) => [file.path, new Set(file.hunks)])),
  }))
}

export function redactBinaryPatchesForPrompt(diff) {
  const lines = String(diff ?? '').split('\n')
  const out = []
  let skipping = false
  for (const line of lines) {
    if (line === 'GIT binary patch' || line === 'Binary files differ' || line.startsWith('literal ')) {
      if (!skipping) out.push('GIT binary patch', '<二进制内容已省略：该文件按整个文件级变更分配>')
      skipping = true
      continue
    }
    if (skipping) {
      if (line.startsWith('diff --git ')) {
        skipping = false
        out.push(line)
      }
      continue
    }
    out.push(line)
  }
  return out.join('\n')
}

export function buildCommitPlanPrompt({ stat, diff, inventory, split }) {
  const text = redactBinaryPatchesForPrompt(diff)
  const splitRule = split
    ? '把下方 diff 按真实变更目的拆成多个提交；确实同属一个目的时也可以只给一个提交，不要为了拆而拆。'
    : '本次已明确关闭拆分，只能生成一个提交，所有 hunk 都归入它。'
  return `请根据下面暂存区 diff 生成提交计划。
要求：
1. ${splitRule}
2. 清单里每个文件的每个 hunk 编号必须且只能分配给一个提交；没有 hunk 的文件用空数组表示整个文件级变更。
3. 同一文件里服务不同目的的相邻改动必须按 hunk 分开；强相关、拆开会破坏原子性的改动保持在一起。
4. Resources/logos 下的图标是资源。若同一 diff 里还有功能改动，把图标并入使用它们的功能提交，不要单独提交图标。只有整个 diff 都是图标时才单独提交。
5. 每个提交一条 Conventional Commits 英文信息，风格与本仓库现有提交一致：格式 <type>(<scope>): <subject>，单行，无 body，无句号。subject 用英文，不超过 72 个字符。
6. type 从 feat / fix / docs / style / refactor / perf / test / build / ci / chore / revert 中选择。
7. scope：Sources/LeaderboardCore → core，Sources/LeaderboardMenu → menu，Scripts 或 dev.sh → scripts，Tests → tests，README 或 docs → docs；跨目录则省略 scope。
8. subject 不超过 72 个字符，必须描述该组 diff 实际做了什么；禁止只列文件数量，禁止复述本 prompt。
注意：生成所需的全部信息都在下面，不要运行任何命令，不要读取或修改任何文件，直接输出。
最终回复只输出 JSON 本身，不要用 markdown 代码块包裹，不要附加任何其他文字。

git diff --cached --stat：
${stat}

hunk 清单：
${JSON.stringify(inventory, null, 2)}

git diff --cached：
${text}`
}

export function scopeForPlan(files) {
  return inferScope(files)
}
