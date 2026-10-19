import assert from 'node:assert/strict'
import test from 'node:test'
import { copyFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'
import { tmpdir } from 'node:os'
import { inputSnapshot, sourceSignature, stageInputs } from './weapp-deploy.mjs'

test('isolated mini-program deployment carries the shared data notice and detects notice-only changes', t => {
  const root = mkdtempSync(join(tmpdir(), 'epoch-notice-stage-'))
  t.after(() => rmSync(root, { recursive: true, force: true }))
  const relative = 'Sources/LeaderboardKit/Resources/EpochAttribution.json'
  for (const folder of ['Sources/LeaderboardKit/Resources', 'node_modules', 'apps/weapp/node_modules']) mkdirSync(join(root, folder), { recursive: true })
  writeFileSync(join(root, 'apps/weapp/package.json'), '{}')
  copyFileSync(new URL(`../${relative}`, import.meta.url), join(root, relative))
  const original = readFileSync(join(root, relative), 'utf8')
  const snapshot = inputSnapshot(root), signature = sourceSignature(snapshot)
  const stage = join(root, 'stage')
  stageInputs(root, stage, snapshot)
  assert.equal(readFileSync(join(stage, relative), 'utf8'), original)
  writeFileSync(join(root, relative), original + '\n')
  assert.notEqual(sourceSignature(inputSnapshot(root)), signature)
  assert.equal(readFileSync(join(stage, relative), 'utf8'), original)
})
