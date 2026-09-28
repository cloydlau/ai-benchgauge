import assert from 'node:assert/strict'
import { existsSync } from 'node:fs'
import test from 'node:test'

import { avatarForModel } from './commit-identity.mjs'
import { materializeAvatar } from './desktop-notify.mjs'

test('内置头像不下载不转码，直接交给通知附件', () => {
  const avatar = avatarForModel('claude-opus-5.5')
  const image = materializeAvatar(avatar)
  assert.equal(image, avatar.bundled)
  assert.ok(existsSync(image))
})

test('内置图标缺失时退回原来的候选逻辑，不抛异常', () => {
  assert.equal(materializeAvatar({ bundled: '/nonexistent/logos/kimi.png' }), '')
  assert.equal(materializeAvatar({}), '')
  assert.equal(materializeAvatar(null), '')
})
