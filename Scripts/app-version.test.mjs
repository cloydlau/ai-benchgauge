import assert from 'node:assert/strict'
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import test from 'node:test'
import { createAutoVersion, dateVersion, platformVersion, readAppVersion } from './app-version.mjs'
import { validateAppConfig } from './app-config.mjs'
import { iosProject } from './ios-project.mjs'

test('calendar versions reject invalid dates, suffixes, whitespace and non-ASCII digits', () => {
  for (const date of ['20261028', '20280229', '20270101']) assert.equal(dateVersion(date), date)
  for (const invalid of ['20260229', '20260230', '20261301', '20260001', '20261000', '20261032',
    '20261028\n', '20261028 ', ' 20261028', '２０２６１０２８', 'v20261028', '1.2.3', 20261028, null]) {
    assert.throws(() => dateVersion(invalid), /YYYYMMDD/)
  }
  assert.equal(platformVersion('20260102'), '2026.1.2')
  assert.equal(createAutoVersion(new Date('2026-12-31T16:00:00Z')), '20270101')
})

test('all clients resolve the shared version and a WeChat-only override cannot diverge', t => {
  const root = mkdtempSync(join(tmpdir(), 'benchgauge-version-source-'))
  t.after(() => rmSync(root, { recursive: true, force: true }))
  mkdirSync(join(root, 'config'))
  writeFileSync(join(root, 'config/app.json'), JSON.stringify({ version: '20261028' }))
  assert.equal(readAppVersion(root), '20261028')
  assert.equal(readAppVersion(root, '20261028'), '20261028')
  assert.throws(() => readAppVersion(root, '20261029'), /must match/)
  assert.throws(() => readAppVersion(root, 'fixture-v1'), /YYYYMMDD/)
  writeFileSync(join(root, 'config/app.json'), JSON.stringify({ version: '20261029' }))
  assert.equal(readAppVersion(root), '20261029')
})

test('real platform metadata and generated iPhone/iPad project match the shared public version', () => {
  const root = new URL('../', import.meta.url)
  const { version } = validateAppConfig(root.pathname)
  const { project } = iosProject({ version })
  assert.ok(project.includes(`BENCHGAUGE_VERSION = "${version}"`))
  assert.ok(project.includes(`MARKETING_VERSION = "${platformVersion(version)}"`))
  assert.ok(project.includes(`CURRENT_PROJECT_VERSION = "${platformVersion(version)}"`))
  const mobileInfo = readFileSync(new URL('../apps/ios/App/Info.plist', import.meta.url), 'utf8')
  assert.match(mobileInfo, /<key>BenchGaugeVersion<\/key><string>\$\(BENCHGAUGE_VERSION\)<\/string>/)
})
