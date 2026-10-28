import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import { readFileSync, mkdirSync, mkdtempSync, writeFileSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import test from 'node:test'
import { syncMobileBrand } from './sync-mobile-brand.mjs'
import { brandTitleLayout } from '../apps/weapp/src/core/brand-title.js'

const root = fileURLToPath(new URL('../', import.meta.url))
test('both mobile clients ship the canonical title, including I and the leaning A, at every size', () => {
  const command = spawnSync(process.execPath, ['Scripts/sync-mobile-brand.mjs', '--check'], { cwd: root, encoding: 'utf8' })
  assert.equal(command.status, 0, command.stderr)
  syncMobileBrand(root, true)
  const native = JSON.parse(readFileSync(new URL('../Sources/LeaderboardKit/Resources/Brand/mobile-title.json', import.meta.url)))
  for (const [key, name] of [['english', 'AI BenchGauge'], ['chinese', 'AI 天梯']]) {
    for (const size of [14, 21, 24, 32, 42]) {
      const web = brandTitleLayout(null, name, size), scale = size / native.baseSize
      const expected = native.layouts[key]
      for (const field of ['width', 'height', 'logoWidth', 'logoHeight', 'logoTop']) {
        assert.ok(Math.abs(web[field] - expected[field] * scale) < 1e-9)
      }
      assert.equal(web.logoShear, expected.logoShear)
      assert.ok(key !== 'english' || expected.logoShear > 0.6)
      assert.equal(web.glyphs[0].text, 'I')
      assert.ok(native.glyphs[web.glyphs[0].key].commands.length > 0)
      assert.ok(web.glyphs[0].width > 0 && web.glyphs[0].height > 0)
      for (const [index, glyph] of web.glyphs.entries()) {
        for (const field of ['x', 'y', 'width', 'height']) {
          assert.ok(Math.abs(glyph[field] - expected.glyphs[index][field] * scale) < 1e-9)
        }
      }
    }
  }
})

test('a changed canonical title fails checks until both client exports are regenerated', () => {
  const directory = mkdtempSync(join(tmpdir(), 'benchgauge-mobile-brand-'))
  try {
    for (const path of ['assets/brand/mobile-title.json', 'apps/weapp/src/core/brand-glyphs.js',
      'apps/weapp/src/core/brand-layouts.js', 'Sources/LeaderboardKit/Resources/Brand/mobile-title.json']) {
      mkdirSync(dirname(join(directory, path)), { recursive: true })
      writeFileSync(join(directory, path), readFileSync(join(root, path)))
    }
    const path = join(directory, 'assets/brand/mobile-title.json')
    const spec = JSON.parse(readFileSync(path))
    spec.english.slantDegrees = 29
    writeFileSync(path, JSON.stringify(spec))
    assert.throws(() => syncMobileBrand(directory, true), /is stale/)
    syncMobileBrand(directory)
    syncMobileBrand(directory, true)
    const native = JSON.parse(readFileSync(join(directory, 'Sources/LeaderboardKit/Resources/Brand/mobile-title.json')))
    assert.equal(native.layouts.english.logoShear, Math.tan(29 * Math.PI / 180))
  } finally { rmSync(directory, { recursive: true, force: true }) }
})

test('Windows embeds the same generated wordmark resource as iOS and macOS', () => {
  const project = readFileSync(join(root, 'apps/windows/BenchGauge/BenchGauge.csproj'), 'utf8')
  const resource = project.match(/<EmbeddedResource Include="([^"]+)" LogicalName="BrandWordmark.json"\s*\/>/)
  assert.ok(resource, 'WPF must ship the shared wordmark, including the separate I and A shear')
  const windows = readFileSync(join(root, 'apps/windows/BenchGauge', resource[1]))
  const apple = readFileSync(join(root, 'Sources/LeaderboardKit/Resources/Brand/mobile-title.json'))
  assert.deepEqual(windows, apple)
  const spec = JSON.parse(windows)
  assert.deepEqual(spec.layouts.english.glyphs.map(glyph => glyph.key), ['en-I', 'en-name'])
  assert.equal(spec.layouts.english.logoShear, Math.tan(31 * Math.PI / 180))
})
