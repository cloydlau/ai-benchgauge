import assert from 'node:assert/strict'
import { existsSync, mkdtempSync, readFileSync, renameSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import test from 'node:test'

import { avatarForModel } from './commit-identity.mjs'
import { materializeAvatar } from './desktop-notify.mjs'
import { deliverNotification } from './desktop-notify-worker.mjs'

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

test('系统移动通知附件后原图仍存在，失败后另一路发送也使用独立副本', (t) => {
  const root = mkdtempSync(join(tmpdir(), 'benchgauge-notification-test-'))
  t.after(() => rmSync(root, { recursive: true, force: true }))
  const image = join(root, 'openai.png')
  const bytes = Buffer.from('fixture-avatar')
  writeFileSync(image, bytes)
  const payloadPaths = []
  let sends = 0
  const receipt = deliverNotification('success', 'fixture', 'body', image, {
    directories: ['first', 'fallback'],
    ensureApp: (_kind, directory) => directory,
    send: (_app, payloadPath) => {
      payloadPaths.push(payloadPath)
      const payload = JSON.parse(readFileSync(payloadPath, 'utf8'))
      assert.notEqual(payload.image, image)
      assert.match(payload.image, /avatar\.png$/)
      assert.deepEqual(readFileSync(payload.image), bytes)
      // 模拟系统实际接管附件，不触发用户的桌面通知。
      renameSync(payload.image, join(root, `system-attachment-${++sends}.png`))
      assert.deepEqual(readFileSync(image), bytes)
      if (sends === 1) throw Error('temporary delivery failure')
      return { accepted: true, notificationId: 'fixture' }
    },
  })
  assert.equal(receipt.accepted, true)
  assert.equal(sends, 2)
  assert.deepEqual(readFileSync(image), bytes)
  assert.notEqual(payloadPaths[0], payloadPaths[1])
  for (const path of payloadPaths) assert.equal(existsSync(path), false)
})
