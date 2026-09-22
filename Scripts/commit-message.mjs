// 提交信息校验。禁止「更新 N 个文件」这类只报数量的说明。

export const TYPES = [
  'feat', 'fix', 'docs', 'style', 'refactor', 'perf', 'test', 'build', 'ci', 'chore', 'revert',
]
export const HEADER_RE = /^([a-z]+)(\(([a-z0-9\-/]+)\))?(!)?: (.+)$/
const GENERIC_FILE_COUNT_SUBJECT_RE = /^(?:新增|移除|更新)(?:\s*\d+\s*个(?:文件|脚本)|\s+.+\s+等\s*\d+\s*处)$|^(?:add|remove|update|change)s?\s+\d+\s+(?:files?|scripts?)$/iu
const PROMPT_ECHO_RE = [
  /先查看暂存区/,
  /再生成符合/,
  /生成一条.{0,24}提交信息/,
  /根据暂存区变更生成提交信息/,
  /conventional commits/i,
  /git diff --cached/,
  /不要修改任何文件/,
  /不要运行任何命令/,
  /最终回复只输出/,
  /不要附加任何其他文字/,
]

export function inferScope(files) {
  const scopes = new Set()
  for (const file of files) {
    if (file.startsWith('Sources/LeaderboardCore/')) scopes.add('core')
    else if (file.startsWith('Sources/LeaderboardMenu/')) scopes.add('menu')
    else if (file.startsWith('Tests/')) scopes.add('tests')
    else if (file.startsWith('Scripts/') || file === 'dev.sh') scopes.add('scripts')
    else if (file.endsWith('.md') || file === 'LICENSE') scopes.add('docs')
    else scopes.add('root')
  }
  if (scopes.size !== 1) return null
  const scope = [...scopes][0]
  return scope === 'root' ? null : scope
}

export function bannedCommitReason(header) {
  const line = String(header || '').trim()
  if (!line) return '提交说明为空'
  const subject = line.includes(':') ? line.slice(line.indexOf(':') + 1).trim() : line
  if (GENERIC_FILE_COUNT_SUBJECT_RE.test(subject)) return '提交说明不能只列文件路径或数量'
  return null
}

function isPromptEcho(text) {
  return PROMPT_ECHO_RE.some((pattern) => pattern.test(text))
}

function stripSubjectPunctuation(subject) {
  return subject.replace(/[。！？.]+$/u, '').trim()
}

export function normalizeMessage(raw, scope, options = {}) {
  const allowBareSubject = options.allowBareSubject !== false
  const rejectPromptEcho = options.rejectPromptEcho === true
  const newline = String(raw ?? '').indexOf('\n')
  const header = (newline === -1 ? String(raw ?? '') : String(raw).slice(0, newline)).trim()
  const rest = newline === -1 ? '' : String(raw).slice(newline)
  if (!header) return null
  if (rejectPromptEcho && (isPromptEcho(header) || /部署快照/.test(header))) return null
  const match = HEADER_RE.exec(header)
  if (match) {
    if (!TYPES.includes(match[1])) return null
    const subject = stripSubjectPunctuation(match[5])
    if (!subject || bannedCommitReason(subject)) return null
    if (rejectPromptEcho && (isPromptEcho(subject) || /部署快照/.test(subject))) return null
    if (rejectPromptEcho && subject.length > 72) return null
    const bang = match[4] ?? ''
    if (!match[2] && scope && scope !== 'root') return `${match[1]}(${scope})${bang}: ${subject}${rest}`
    return `${match[1]}${match[2] ?? ''}${bang}: ${subject}${rest}`
  }
  if (!allowBareSubject || header.includes(':')) return null
  const subject = stripSubjectPunctuation(header)
  if (!subject || bannedCommitReason(subject)) return null
  return `chore${scope ? `(${scope})` : ''}: ${subject}${rest}`
}

const THEMES = [
  [/CategoryPreference/, 'remember the last selected category'],
  [/PurchaseLink/, 'add purchase links'],
  [/OrganizationLogo|\/logos\//, 'update model icons'],
  [/LeaderboardView/, 'adjust leaderboard columns'],
  [/HTMLLeaderboardParser/, 'update leaderboard parsing'],
  [/LeaderboardFetcher/, 'update leaderboard fetching'],
  [/OrganizationRegion/, 'update provider regions'],
  [/commit-split|commit\.mjs/, 'split commits by purpose'],
  [/commit-identity/, 'credit the model name and avatar'],
  [/desktop-notify/, 'send desktop notifications'],
  [/watch\.mjs|dev\.sh/, 'restart after debounced changes'],
  [/make-app\.sh|restart\.sh/, 'update the build and relaunch scripts'],
]

export function themeKey(path) {
  const file = String(path || '')
  for (const [pattern, label] of THEMES) {
    if (pattern.test(file)) return label
  }
  return ''
}

function themesFor(paths) {
  const joined = paths.join('\n')
  const found = []
  for (const [pattern, label] of THEMES) {
    if (pattern.test(joined) && !found.includes(label)) found.push(label)
  }
  return found
}

function stems(paths) {
  const preferred = paths.filter((file) => /\.(swift|mjs|sh|md)$/.test(file))
  const source = preferred.length ? preferred : paths
  return source
    .map((file) => file.split('/').pop().replace(/\.[^.]+$/, ''))
    .filter((name) => name && name !== 'logos')
    .slice(0, 2)
}

export function localGroupMessage(bucket, paths) {
  const themes = themesFor(paths)
  const type = bucket === 'tests' ? 'test'
    : bucket === 'docs' ? 'docs'
      : bucket === 'ci' ? 'ci'
        : bucket === 'build' ? 'build'
          : bucket === 'logos' ? 'chore'
            : 'feat'
  const scope = bucket === 'core' ? 'core'
    : bucket === 'menu' || bucket === 'logos' ? 'menu'
      : bucket === 'tests' ? 'tests'
        : bucket === 'docs' ? 'docs'
          : bucket === 'ci' || bucket === 'build' ? 'scripts'
            : inferScope(paths)
  let subject = themes.slice(0, 2).join(' and ')
  if (!subject) {
    const names = stems(paths)
    subject = names.length ? `update ${names.join(' and ')}` : 'update the related implementation'
  }
  if (subject.length > 72) subject = subject.slice(0, 72).trim()
  const message = `${type}${scope ? `(${scope})` : ''}: ${subject}`
  return normalizeMessage(message, scope, { allowBareSubject: false }) || message
}
