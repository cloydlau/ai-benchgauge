import assert from 'node:assert/strict'
import test from 'node:test'
import { copyFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { spawnSync } from 'node:child_process'

function fixture(t) {
  const root = mkdtempSync(join(tmpdir(), 'purchase-link-generator-'))
  t.after(() => rmSync(root, { recursive: true, force: true }))
  for (const folder of ['Scripts', 'fc', 'Sources/LeaderboardKit']) mkdirSync(join(root, folder), { recursive: true })
  const script = join(root, 'Scripts/generate-purchase-links.mjs')
  copyFileSync(new URL('./generate-purchase-links.mjs', import.meta.url), script)
  const output = join(root, 'Sources/LeaderboardKit/PurchaseLinkData.generated.swift')
  return { output, write: link => writeFileSync(join(root, 'fc/purchase-links.json'), JSON.stringify({
    aliases: { alias: 'vendor' }, vendors: { vendor: { default: { codingPlan: [link], payAsYouGo: null }, image: {} } },
  })), run: (...args) => spawnSync(process.execPath, [script, ...args], { encoding: 'utf8' }) }
}

test('purchase-link generation preserves validated links, empty categories and detects stale output', t => {
  const f = fixture(t)
  for (const site of ['mainlandChina', 'international', 'universal']) {
    f.write({ label: 'Plan "A"', url: 'https://example.com/pricing', site })
    const generated = f.run(); assert.equal(generated.status, 0, generated.stderr)
    const source = readFileSync(f.output, 'utf8')
    assert.ok(source.includes(`site: .${site}`))
    assert.ok(source.includes('Plan \\"A\\"'))
    assert.match(source, /PurchaseLinks\(codingPlan: \[\], payAsYouGo: \[\]\)/)
    const checked = f.run('--check'); assert.equal(checked.status, 0, checked.stderr)
  }
  writeFileSync(f.output, 'stale')
  const stale = f.run('--check'); assert.notEqual(stale.status, 0); assert.match(stale.stderr, /Purchase links are stale/)
  assert.equal(readFileSync(f.output, 'utf8'), 'stale')
})

test('purchase-link generation rejects unsafe URLs and unknown site classifications before writing', t => {
  const f = fixture(t)
  for (const link of [
    { url: 'http://example.com/pricing', site: 'universal' },
    { url: 'https://user@example.com/pricing', site: 'universal' },
    { url: 'https://:secret@example.com/pricing', site: 'universal' },
    { url: 'https://example.com/price list', site: 'universal' },
    { url: 'https://example.com/pricing', site: 'unknown' },
    { url: 'invalid', site: 'universal' },
  ]) {
    f.write({ label: 'Plan', ...link }); writeFileSync(f.output, 'keep existing output')
    assert.notEqual(f.run().status, 0, link.url)
    assert.equal(readFileSync(f.output, 'utf8'), 'keep existing output')
  }
})
