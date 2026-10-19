import assert from 'node:assert/strict'
import test from 'node:test'
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'
import { tmpdir } from 'node:os'
import { inputSnapshot, sourceSignature, stageInputs } from './weapp-deploy.mjs'

test('models.dev notice retains the complete upstream MIT text in Apple and isolated mini-program inputs', t => {
  const relative = 'fc/models-dev-license.txt'
  const original = readFileSync(new URL('../' + relative, import.meta.url), 'utf8')
  assert.equal(readFileSync(new URL('../Sources/LeaderboardKit/Resources/ModelsDev-MIT.txt', import.meta.url), 'utf8'), original)
  assert.match(original, /Copyright \(c\) 2025 models\.dev/)
  assert.match(original, /THE SOFTWARE IS PROVIDED "AS IS"/)
  const root = mkdtempSync(join(tmpdir(), 'models-dev-notice-'))
  t.after(() => rmSync(root, { recursive: true, force: true }))
  for (const folder of ['fc', 'node_modules', 'apps/weapp/node_modules']) mkdirSync(join(root, folder), { recursive: true })
  writeFileSync(join(root, 'apps/weapp/package.json'), '{}')
  writeFileSync(join(root, relative), original)
  const snapshot = inputSnapshot(root), signature = sourceSignature(snapshot)
  const stage = join(root, 'stage')
  stageInputs(root, stage, snapshot)
  assert.equal(readFileSync(join(stage, relative), 'utf8'), original)
  writeFileSync(join(root, relative), original + '\n')
  assert.notEqual(sourceSignature(inputSnapshot(root)), signature)
  assert.equal(readFileSync(join(stage, relative), 'utf8'), original)
})
