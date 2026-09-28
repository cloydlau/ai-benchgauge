import assert from 'node:assert/strict'
import { existsSync } from 'node:fs'
import test from 'node:test'

import {
  avatarForModel,
  commitArgs,
  emailForModel,
  resolveCommitIdentity,
  resolveModelAvatar,
} from './commit-identity.mjs'

test('uses official GitHub Bot emails for model identities', () => {
  assert.equal(emailForModel('gpt-5-codex'), 'noreply@openai.com')
  assert.equal(emailForModel('grok-4.7'), '304785771+grokkybara[bot]@users.noreply.github.com')
  assert.equal(emailForModel('qwen3-coder'), '269191875+qwen-code-dev-bot@users.noreply.github.com')
  assert.equal(emailForModel('gemini-2.5-pro'), '224641728+gemini-cli-robot@users.noreply.github.com')
  assert.equal(emailForModel('MiMo-V2.5-Pro'), 'mimo@xiaomi.com')
  assert.equal(emailForModel('minimax-m2'), 'minimax-m2@users.noreply.github.com')
  assert.equal(emailForModel('mistral-large'), 'mistral-large@users.noreply.github.com')
  assert.equal(emailForModel('kimi-k3'), 'kimi-k3@users.noreply.github.com')
})

test('keeps the model username while changing only its GitHub identity email', () => {
  const identity = resolveCommitIdentity({ env: { MODEL_NAME: 'grok-4.7' } })
  assert.equal(identity.model, 'grok-4.7')
  assert.equal(identity.author.name, 'grok-4.7')
  assert.equal(identity.committer.name, 'grok-4.7')
  assert.equal(identity.author.email, '304785771+grokkybara[bot]@users.noreply.github.com')
  assert.equal(identity.committer.email, identity.author.email)
})

test('keeps the existing avatar URL candidates independent of commit email', () => {
  const avatar = avatarForModel('grok-4.7')
  assert.equal(avatar.provider, 'grok')
  assert.equal(avatar.favicon, 'https://grok.com/images/favicon.svg')
  assert.ok(avatar.candidates.includes('https://api.iconify.design/hugeicons:grok.svg'))
  const args = commitArgs('test commit', resolveCommitIdentity({ env: { MODEL_NAME: 'grok-4.7' } }))
  assert.equal(args[0], '-c')
  assert.equal(args[1], 'gc.auto=0')
  assert.equal(args.includes('--trailer'), false)
  assert.equal(args.some((arg) => String(arg).includes('Model-Avatar')), false)
})

test('kimi 使用月之暗面官方 favicon，图标用存在的 moonrepo', () => {
  const avatar = avatarForModel('kimi-k3')
  assert.equal(avatar.provider, 'kimi')
  assert.equal(avatar.favicon, 'https://kimi.moonshot.cn/favicon.ico')
  assert.equal(avatar.candidates[0], avatar.favicon)
  assert.equal(avatar.candidates[1], 'https://api.iconify.design/simple-icons:moonrepo.svg')
})

test('llama 按未知模型处理，不归到 Meta 身份', () => {
  const avatar = avatarForModel('llama-4')
  assert.equal(avatar.provider, '')
  assert.match(avatar.candidates[0], /^https:\/\/api\.iconify\.design\/logos:/)
  assert.equal(emailForModel('llama-4'), 'llama-4@users.noreply.github.com')
})

test('内置头像优先，断网也直接给出仓库里的 PNG', async () => {
  const originalFetch = globalThis.fetch
  let probed = 0
  globalThis.fetch = async () => { probed += 1; throw new Error('offline') }
  try {
    const avatar = await resolveModelAvatar('kimi-k3', { fetchBudgetMs: 1000 })
    assert.equal(avatar.source, 'bundled')
    assert.equal(avatar.probed, true)
    assert.equal(avatar.url, avatar.bundled)
    assert.equal(avatar.favicon, 'https://kimi.moonshot.cn/favicon.ico')
    assert.ok(existsSync(avatar.bundled))
    assert.equal(probed, 0)
  } finally {
    globalThis.fetch = originalFetch
  }
})

test('没有内置头像时才探测网络，全部失败回退到通用机器人图标', async () => {
  const originalFetch = globalThis.fetch
  let probed = 0
  globalThis.fetch = async () => { probed += 1; throw new Error('offline') }
  try {
    const avatar = await resolveModelAvatar('cursor-agent', { fetchBudgetMs: 1000 })
    assert.equal(avatar.bundled, '')
    assert.equal(avatar.url, avatar.fallback)
    assert.equal(avatar.source, 'icones')
    assert.equal(avatar.probed, false)
    assert.ok(probed > 0)
  } finally {
    globalThis.fetch = originalFetch
  }
})

test('每家有内置图标的模型都指向仓库里真实存在的 PNG', () => {
  const models = [
    'glm-4.6', 'deepseek-v3.2', 'gpt-6-sol', 'claude-opus-5.5', 'kimi-k3', 'grok-4.7',
    'qwen3-coder', 'gemini-2.5-pro', 'meta-ai', 'MiMo-V2.5-Pro', 'devin-1.2',
  ]
  for (const model of models) {
    const avatar = avatarForModel(model)
    assert.ok(avatar.bundled, model)
    assert.ok(existsSync(avatar.bundled), `${model} -> ${avatar.bundled}`)
    assert.equal(avatar.url, avatar.bundled, model)
  }
})
