import assert from 'node:assert/strict'
import test from 'node:test'
import { spawnSync } from 'node:child_process'
import { copyFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { copy, text } from '../apps/weapp/src/core/catalog.js'

const documents = [['README.md', 'en'], ['README.zh-CN.md', 'zh-CN'], ['README.zh-Hant.md', 'zh-TW']]
const stale = '# Introduction\n\n<!-- app-description:start -->\nOld description\n<!-- app-description:end -->\n\nKeep this section.\n'

function fixture(t) {
  const root = mkdtempSync(join(tmpdir(), 'benchgauge-description-'))
  t.after(() => rmSync(root, { recursive: true, force: true }))
  for (const folder of ['Scripts', 'apps/weapp/src/core']) mkdirSync(join(root, folder), { recursive: true })
  writeFileSync(join(root, 'package.json'), '{"type":"module"}')
  copyFileSync(new URL('./sync-app-description.mjs', import.meta.url), join(root, 'Scripts/sync-app-description.mjs'))
  copyFileSync(new URL('../apps/weapp/src/core/catalog.js', import.meta.url), join(root, 'apps/weapp/src/core/catalog.js'))
  for (const [file] of documents) writeFileSync(join(root, file), stale)
  const run = (...args) => spawnSync(process.execPath, [join(root, 'Scripts/sync-app-description.mjs'), ...args], { encoding: 'utf8', cwd: root })
  const read = file => readFileSync(join(root, file), 'utf8')
  return { root, run, read }
}

test('description sync uses each language, preserves surrounding documentation, and is idempotent', t => {
  const f = fixture(t)
  const check = f.run('--check')
  assert.notEqual(check.status, 0)
  assert.match(check.stderr, /README\.md: app description is out of date/)
  for (const [file] of documents) assert.equal(f.read(file), stale)
  const sync = f.run()
  assert.equal(sync.status, 0, sync.stderr)
  assert.match(sync.stdout, /synced in all three READMEs/)
  for (const [file, language] of documents) {
    assert.equal(f.read(file), `# Introduction\n\n<!-- app-description:start (generated from apps/weapp/src/core/catalog.js) -->\n**${text(copy.description, language)}**\n<!-- app-description:end -->\n\nKeep this section.\n`)
  }
  const snapshot = documents.map(([file]) => f.read(file))
  assert.equal(f.run().status, 0)
  const verified = f.run('--check')
  assert.equal(verified.status, 0, verified.stderr)
  assert.match(verified.stdout, /verified in all three READMEs/)
  assert.deepEqual(documents.map(([file]) => f.read(file)), snapshot)
})

test('description sync rejects missing or duplicate generated blocks without overwriting the document', t => {
  const f = fixture(t)
  for (const original of ['# No generated block\n', stale + stale]) {
    writeFileSync(join(f.root, 'README.md'), original)
    const result = f.run()
    assert.notEqual(result.status, 0)
    assert.match(result.stderr, /Expected one app description block in README\.md/)
    assert.equal(f.read('README.md'), original)
    for (const [file] of documents.slice(1)) assert.equal(f.read(file), stale)
  }
})
