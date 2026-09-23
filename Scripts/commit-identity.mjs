import { existsSync, readFileSync } from 'node:fs'
import { homedir } from 'node:os'
import { join } from 'node:path'

// 每次提交前重新读取 Codex 当前模型。头像只给桌面通知用，不写入提交说明。
const DEFAULT_CONFIG_PATH = join(homedir(), '.codex', 'config.toml')
const ICONES_FALLBACK = 'https://api.iconify.design/mdi:robot-outline.svg'
// GitHub associates these official coding-agent Bots with their numeric
// noreply addresses. Keep the selected model name separate from the email so
// a commit can still say `grok-4.7` while GitHub resolves the Bot avatar.
const GROK_GITHUB_EMAIL = '304785771+grokkybara[bot]@users.noreply.github.com'
const QWEN_GITHUB_EMAIL = '269191875+qwen-code-dev-bot@users.noreply.github.com'
const GEMINI_GITHUB_EMAIL = '224641728+gemini-cli-robot@users.noreply.github.com'
// OpenAI Codex's official commit-attribution implementation uses this address.
const OPENAI_GITHUB_EMAIL = 'noreply@openai.com'
// Public contact address listed on the official Xiaomi MiMo GitHub profile.
const MIMO_EMAIL = 'mimo@xiaomi.com'
const HUMAN = Object.freeze({
  name: 'Cloyd Lau',
  email: '31238760+cloydlau@users.noreply.github.com',
})

const MODEL_AVATAR_PROVIDERS = Object.freeze([
  {
    key: 'glm',
    brands: ['glm', 'zhipu', 'zai'],
    email: 'noreply@z.ai',
    favicon: 'https://open.bigmodel.cn/favicon.ico',
    icon: 'https://api.iconify.design/simple-icons:zhipuai.svg',
  },
  {
    key: 'deepseek',
    brands: ['deepseek'],
    email: 'noreply@deepseek.com',
    favicon: 'https://www.deepseek.com/favicon.ico',
    icon: 'https://api.iconify.design/simple-icons:deepseek.svg',
  },
  {
    key: 'openai',
    brands: ['gpt', 'openai', 'codex', 'o1', 'o3', 'o4'],
    email: OPENAI_GITHUB_EMAIL,
    favicon: 'https://openai.com/favicon.ico',
    icon: 'https://api.iconify.design/logos:openai-icon.svg',
  },
  {
    key: 'claude',
    brands: ['claude', 'anthropic', 'fable'],
    email: 'noreply@anthropic.com',
    favicon: 'https://www.anthropic.com/favicon.ico',
    icon: 'https://api.iconify.design/simple-icons:anthropic.svg',
  },
  {
    key: 'kimi',
    brands: ['kimi', 'moonshot'],
    email: 'noreply@kimi.com',
    favicon: 'https://www.kimi.com/favicon.ico',
    icon: 'https://api.iconify.design/simple-icons:moonshot.svg',
  },
  {
    key: 'grok',
    brands: ['grok', 'xai'],
    email: GROK_GITHUB_EMAIL,
    // grok.com/favicon.ico 已 404。不能回退成 X 的图标。
    favicon: 'https://grok.com/images/favicon.svg',
    icon: 'https://api.iconify.design/hugeicons:grok.svg',
  },
  {
    key: 'qwen',
    brands: ['qwen', 'tongyi'],
    email: QWEN_GITHUB_EMAIL,
    favicon: 'https://qwen.ai/favicon.ico',
    icon: 'https://api.iconify.design/simple-icons:alibabacloud.svg',
  },
  {
    key: 'gemini',
    brands: ['gemini', 'google'],
    email: GEMINI_GITHUB_EMAIL,
    favicon: 'https://www.google.com/favicon.ico',
    icon: 'https://api.iconify.design/logos:google-icon.svg',
  },
  {
    key: 'meta',
    brands: ['llama', 'meta'],
    email: 'noreply@meta.com',
    favicon: 'https://about.meta.com/favicon.ico',
    icon: 'https://api.iconify.design/logos:meta-icon.svg',
  },
  {
    key: 'mimo',
    brands: ['mimo', 'xiaomi'],
    email: MIMO_EMAIL,
    favicon: 'https://mimo.xiaomi.com/favicon.ico',
    icon: 'https://api.iconify.design/simple-icons:xiaomi.svg',
  },
  {
    key: 'cursor',
    brands: ['cursor'],
    email: 'cursoragent@cursor.com',
    favicon: 'https://cursor.com/favicon.ico',
    icon: 'https://api.iconify.design/simple-icons:cursor.svg',
  },
  {
    key: 'devin',
    brands: ['devin'],
    email: 'noreply@cognition.ai',
    favicon: 'https://devin.ai/favicon.ico',
    icon: 'https://api.iconify.design/simple-icons:devin.svg',
  },
])

function providerForModel(model) {
  const name = String(model || '').trim().toLowerCase()
  return MODEL_AVATAR_PROVIDERS.find(({ brands }) => brands.some((brand) => name.includes(brand))) || null
}

export function avatarForModel(model) {
  const provider = providerForModel(model)
  if (!provider) {
    const normalized = String(model || '').trim().toLowerCase().replace(/[^a-z0-9]+/g, '-') || 'model'
    const icon = `https://api.iconify.design/logos:${normalized}.svg`
    return {
      provider: '',
      source: 'icones',
      candidates: [icon, ICONES_FALLBACK],
      favicon: '',
      icon,
      fallback: ICONES_FALLBACK,
      url: icon,
    }
  }
  return {
    provider: provider.key,
    source: 'official-favicon',
    candidates: [provider.favicon, provider.icon, ICONES_FALLBACK],
    favicon: provider.favicon,
    icon: provider.icon,
    fallback: ICONES_FALLBACK,
    url: provider.favicon,
  }
}

async function probeUrl(url, timeoutMs) {
  if (typeof fetch !== 'function') return false
  try {
    const response = await fetch(url, { method: 'GET', redirect: 'follow', signal: AbortSignal.timeout(timeoutMs) })
    if (!response?.ok) return false
    const type = response.headers.get('content-type') || ''
    // grok.com/images/favicon.svg 的 HEAD 是 200，GET 却返回 HTML 403。
    return !type.includes('text/html')
  } catch {
    return false
  }
}

/** 提交不等待图标服务；探测失败时仍返回确定性候选，不中断提交。 */
export async function resolveModelAvatar(model, { fetchBudgetMs = 2000 } = {}) {
  const avatar = avatarForModel(model)
  const deadline = Date.now() + fetchBudgetMs
  for (const url of avatar.candidates) {
    const remaining = deadline - Date.now()
    if (remaining < 200) break
    const ok = await probeUrl(url, Math.min(remaining, 1200))
    if (!ok) continue
    return {
      ...avatar,
      url,
      probed: true,
      source: url === avatar.favicon ? 'official-favicon' : 'icones',
    }
  }
  return { ...avatar, probed: false }
}

export function detectModelName({ configPath = DEFAULT_CONFIG_PATH, env = process.env } = {}) {
  const override = env.MODEL_NAME?.trim()
  if (override) return override
  if (!existsSync(configPath)) return 'codex'
  const config = readFileSync(configPath, 'utf8')
  const match = config.match(/^model\s*=\s*"([^"]+)"/m)
  return match?.[1]?.trim() || 'codex'
}

export function emailForModel(model) {
  const provider = providerForModel(model)
  if (provider) return provider.email
  const name = String(model || 'codex').trim().toLowerCase()
  return `${name}@users.noreply.github.com`
}

export function resolveCommitIdentity(options = {}) {
  const env = options.env ?? process.env
  const model = detectModelName({ ...options, env })
  const modelIdentity = { name: model, email: emailForModel(model) }
  const coauthor = env.COMMIT_COAUTHOR === '1'
  return {
    model,
    avatar: avatarForModel(model),
    author: { ...modelIdentity },
    committer: coauthor ? { ...HUMAN } : { ...modelIdentity },
    coauthor: coauthor ? { ...HUMAN } : null,
  }
}

export function commitIdentityEnv(identity) {
  return {
    GIT_AUTHOR_NAME: identity.author.name,
    GIT_AUTHOR_EMAIL: identity.author.email,
    GIT_COMMITTER_NAME: identity.committer.name,
    GIT_COMMITTER_EMAIL: identity.committer.email,
  }
}

export function formatCommitIdentity(identity) {
  return `${identity.author.name} <${identity.author.email}>`
}

export function commitArgs(message, identity) {
  const args = [
    '-c', `user.name=${identity.committer.name}`,
    '-c', `user.email=${identity.committer.email}`,
    'commit',
    '-m', message,
    '--author', `${identity.author.name} <${identity.author.email}>`,
  ]
  if (identity.coauthor) {
    args.push('--trailer', `Co-authored-by: ${identity.coauthor.name} <${identity.coauthor.email}>`)
  }
  return args
}
