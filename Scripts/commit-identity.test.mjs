import assert from 'node:assert/strict'
import test from 'node:test'

import {
  avatarForModel,
  commitArgs,
  emailForModel,
  resolveCommitIdentity,
} from './commit-identity.mjs'

test('uses official GitHub Bot emails for model identities', () => {
  assert.equal(emailForModel('gpt-5-codex'), 'noreply@openai.com')
  assert.equal(emailForModel('grok-4.7'), '304785771+grokkybara[bot]@users.noreply.github.com')
  assert.equal(emailForModel('qwen3-coder'), '269191875+qwen-code-dev-bot@users.noreply.github.com')
  assert.equal(emailForModel('gemini-2.5-pro'), '224641728+gemini-cli-robot@users.noreply.github.com')
  assert.equal(emailForModel('MiMo-V2.5-Pro'), 'mimo@xiaomi.com')
  assert.equal(emailForModel('minimax-m2'), 'minimax-m2@users.noreply.github.com')
  assert.equal(emailForModel('mistral-large'), 'mistral-large@users.noreply.github.com')
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
  assert.ok(commitArgs('test commit', resolveCommitIdentity({ env: { MODEL_NAME: 'grok-4.7' } }))
    .includes('--trailer'))
})
