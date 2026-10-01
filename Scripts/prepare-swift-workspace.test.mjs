import assert from 'node:assert/strict'
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import test from 'node:test'
import { prepareSwiftWorkspace } from './prepare-swift-workspace.mjs'

test('搬迁的远程框架缓存完整备份，新的构建不会继续引用旧目录', (t) => {
  const root = mkdtempSync(join(tmpdir(), 'swift-moved-fixture-'))
  const backups = []
  t.after(() => { rmSync(root, { recursive: true, force: true }); for (const path of backups) rmSync(path, { recursive: true, force: true }) })
  for (const relative of ['.build', 'work/unit-test-build']) {
    const cache = join(root, relative)
    const artifact = join(cache, 'artifacts/fixture/Kit.xcframework')
    mkdirSync(artifact, { recursive: true })
    writeFileSync(join(artifact, 'fixture'), 'preserved framework')
    writeFileSync(join(cache, 'workspace-state.json'), JSON.stringify({ object: { artifacts: [{ source: { type: 'remote' }, path: join('/previous/project', relative, 'artifacts/fixture/Kit.xcframework') }] } }))
  }
  backups.push(...prepareSwiftWorkspace(root, { log: () => {} }))
  assert.equal(backups.length, 2)
  for (const backup of backups) assert.equal(readFileSync(join(backup, 'artifacts/fixture/Kit.xcframework/fixture'), 'utf8'), 'preserved framework')
  assert.equal(existsSync(join(root, '.build')), false)
  assert.equal(existsSync(join(root, 'work/unit-test-build')), false)
  assert.deepEqual(prepareSwiftWorkspace(root, { log: () => {} }), [])
})

test('当前缓存和本地框架引用不触发搬迁恢复', (t) => {
  const root = mkdtempSync(join(tmpdir(), 'swift-current-fixture-'))
  t.after(() => rmSync(root, { recursive: true, force: true }))
  const cache = join(root, '.build')
  const artifact = join(cache, 'artifacts/fixture/Kit.xcframework')
  mkdirSync(artifact, { recursive: true })
  for (const entry of [{ source: { type: 'remote' }, path: artifact }, { source: { type: 'local' }, path: '/other/project/.build/artifacts/fixture/Kit.xcframework' }]) {
    writeFileSync(join(cache, 'workspace-state.json'), JSON.stringify({ object: { artifacts: [entry] } }))
    assert.deepEqual(prepareSwiftWorkspace(root, { log: () => {} }), [])
    assert.ok(existsSync(artifact))
  }
})
