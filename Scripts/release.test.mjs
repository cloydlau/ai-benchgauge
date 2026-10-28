import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import { createPublicKey, generateKeyPairSync, verify } from 'node:crypto'
import { copyFileSync, existsSync, mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import test from 'node:test'
import { createAutoVersion, platformVersion } from './app-version.mjs'
import { compareVersions, feedURL, releaseVersion, renderAppcast, renderHomebrewCask, signArchive, signingKey, validateRelease } from './release-lib.mjs'

const root = dirname(dirname(fileURLToPath(import.meta.url)))
test('release publishing accepts deliberately disabled Windows and requires every enabled build and human review', () => {
  const workflow = readFileSync(join(root, '.github/workflows/release.yml'), 'utf8')
  const expression = workflow.split('  publish:\n')[1].split('    if: >-\n')[1].split('    runs-on:')[0].trim().slice(3, -2).trim()
  // This condition uses the common JS/GitHub boolean-expression subset.
  const canPublish = new Function('needs', 'cancelled', `return (${expression})`)
  for (const enabled of ['true', 'false']) {
    const needs = {
      configuration: { result: 'success', outputs: { windows_enabled: enabled } },
      macos: { result: 'success' }, visual: { result: 'success' },
      windows: { result: enabled === 'true' ? 'success' : 'skipped' },
    }
    assert.equal(canPublish(needs, () => false), true)
    assert.equal(canPublish(needs, () => true), false)
    for (const job of ['configuration', 'macos', 'visual']) {
      for (const result of ['failure', 'cancelled', 'skipped']) {
        assert.equal(canPublish({ ...needs, [job]: { ...needs[job], result } }, () => false), false)
      }
    }
    for (const result of ['success', 'failure', 'cancelled', 'skipped']) {
      assert.equal(canPublish({ ...needs, windows: { result } }, () => false), result === needs.windows.result)
    }
    assert.equal(canPublish({ ...needs, configuration: { result: 'success', outputs: {} } }, () => false), false)
  }
})
function keys() {
  const { privateKey, publicKey } = generateKeyPairSync('ed25519')
  return { privateKey, publicKey,
    seed: privateKey.export({ format: 'der', type: 'pkcs8' }).subarray(-32).toString('base64'),
    encodedPublic: publicKey.export({ format: 'der', type: 'spki' }).subarray(-32).toString('base64') }
}
function info(publicKey) {
  return { CFBundleIdentifier: 'com.cloydlau.ai-benchgauge', CFBundleShortVersionString: '2026.10.28', CFBundleVersion: '2026.10.28', BenchGaugeVersion: '20261028',
    LSMinimumSystemVersion: '14.0', SUPublicEDKey: publicKey, SUFeedURL: feedURL, SUScheduledCheckInterval: 86400,
    SUEnableAutomaticChecks: true, SUAutomaticallyUpdate: true, SUAllowsAutomaticUpdates: true,
    SURequireSignedFeed: true, SUVerifyUpdateBeforeExtraction: true }
}

test('release versions are numeric and reject prereleases, leading zeros, and shell syntax', () => {
  assert.equal(releaseVersion('v20261028'), '20261028')
  assert.equal(compareVersions('1.10.0', '1.9.9'), 1)
  assert.equal(compareVersions('2.0.0', '10.0.0'), -1)
  assert.equal(compareVersions('20261028', 'v20261028'), 0)
  assert.equal(compareVersions('20261028', '1.10.0'), 1)
  assert.equal(compareVersions('20270101', '20261231'), 1)
  assert.equal(compareVersions('20261028', '2026.10.28'), 0)
  for (const value of ['', '1.0', '1.2.3', '020261028', '20261028-rc.1', '20261028+build', 'v20261028;touch hacked', '20261028\n']) {
    assert.throws(() => releaseVersion(value))
  }
})

test('release validation prevents rollback, version drift, missing keys, and unsafe update configuration', () => {
  const valid = info(keys().encodedPublic)
  assert.equal(validateRelease('v20261028', valid, [{ tagName: 'v20261027' }]), '20261028')
  assert.equal(validateRelease('v20261028', valid, [{ tagName: 'v2.0.0-rc.1', isPrerelease: true }]), '20261028')
  for (const tagName of ['v20261028', 'v20261029', 'v20270101']) assert.throws(() => validateRelease('v20261028', valid, [{ tagName }]))
  for (const changes of [{ CFBundleVersion: '20261027' }, { SUPublicEDKey: '' }, { SUFeedURL: 'http://example.com/feed' },
    { SUScheduledCheckInterval: 60 }, { SUScheduledCheckInterval: 3600 }, { SUAutomaticallyUpdate: false }, { SUAllowsAutomaticUpdates: false },
    { SURequireSignedFeed: false }, { SUVerifyUpdateBeforeExtraction: false }, { CFBundleIdentifier: 'different.app' }]) {
    assert.throws(() => validateRelease('v20261028', { ...valid, ...changes }))
  }
})

test('update signatures use the app public key and reject changed archives and mismatched keys', () => {
  const pair = keys()
  const key = signingKey(pair.seed, pair.encodedPublic)
  assert.deepEqual(createPublicKey(key).export({ format: 'der', type: 'spki' }), pair.publicKey.export({ format: 'der', type: 'spki' }))
  const archive = Buffer.from('signed update fixture')
  const signature = Buffer.from(signArchive(archive, key), 'base64')
  assert.equal(verify(null, archive, pair.publicKey, signature), true)
  assert.equal(verify(null, Buffer.from('tampered update fixture'), pair.publicKey, signature), false)
  assert.throws(() => signingKey(pair.seed, keys().encodedPublic), /does not match/)
  assert.throws(() => signingKey('not a private key', pair.encodedPublic))
})

test('feed uses the exact immutable archive, minimum OS, signature, and escaped release notes', () => {
  const xml = renderAppcast({ version: '20261028', archiveName: 'AI-BenchGauge-20261028-macos-universal.zip',
    signature: Buffer.alloc(64, 1).toString('base64'), length: 987, notes: '<script>bad()</script> & ]]>\n"notes"', date: new Date('2026-09-29T00:00:00Z') })
  assert.match(xml, /releases\/download\/v20261028\/AI-BenchGauge-20261028-macos-universal.zip/)
  assert.match(xml, /<sparkle:minimumSystemVersion>14.0/)
  assert.match(xml, /<sparkle:version>2026\.10\.28<\/sparkle:version>/)
  assert.match(xml, /<sparkle:shortVersionString>20261028<\/sparkle:shortVersionString>/)
  assert.match(xml, /length="987"/)
  assert.match(xml, /&lt;script&gt;bad\(\)&lt;\/script&gt; &amp; \]\]&gt;/)
  assert.equal(xml.includes('<script>'), false)
  assert.throws(() => renderAppcast({ version: '20261028', archiveName: 'arbitrary.zip', signature: '', length: 0 }))
})

test('Homebrew cask points to the exact signed DMG and reports app-managed updates', () => {
  const digest = 'a'.repeat(64)
  const cask = renderHomebrewCask({ version: '20261028', archiveName: 'AI-BenchGauge-20261028-macos-universal.dmg', digest })
  assert.match(cask, /cask "ai-benchgauge"/)
  assert.match(cask, /version "20261028"/)
  assert.match(cask, /sha256 "a{64}"/)
  assert.match(cask, /url "https:\/\/github\.com\/cloydlau\/ai-benchgauge\/releases\/download\/v20261028\/AI-BenchGauge-20261028-macos-universal\.dmg"/)
  assert.match(cask, /auto_updates true/)
  assert.match(cask, /depends_on macos: ">= :sonoma"/)
  assert.match(cask, /app "AI-BenchGauge\.app"/)
  assert.throws(() => renderHomebrewCask({ version: '20261028', archiveName: 'other.dmg', digest }))
  assert.throws(() => renderHomebrewCask({ version: '20261028', archiveName: 'AI-BenchGauge-20261028-macos-universal.dmg', digest: 'not-a-sha256' }))
})

test('official Sparkle verifies signatures and detects tampered signed feeds', { skip: !existsSync(join(root, '.build/artifacts/sparkle/Sparkle/bin/sign_update')) }, (t) => {
  const directory = mkdtempSync(join(tmpdir(), 'benchgauge-signatures-'))
  t.after(() => rmSync(directory, { recursive: true, force: true }))
  const pair = keys()
  const archive = join(directory, 'fixture.zip')
  const bytes = Buffer.from('offline archive fixture')
  writeFileSync(archive, bytes)
  const key = signingKey(pair.seed, pair.encodedPublic)
  const signature = signArchive(bytes, key)
  const signer = join(root, '.build/artifacts/sparkle/Sparkle/bin/sign_update')
  const call = (args) => spawnSync(signer, ['-f', '-', ...args], { input: pair.seed + '\n', encoding: 'utf8' })
  assert.equal(call(['--verify', archive, signature]).status, 0)
  const feed = join(directory, 'appcast.xml')
  writeFileSync(feed, renderAppcast({ version: '20261028', archiveName: 'AI-BenchGauge-20261028-macos-universal.zip', signature, length: bytes.length, notes: 'Offline update fixture' }))
  assert.equal(call(['-p', feed]).status, 0)
  assert.equal(call(['--verify', feed]).status, 0)
  writeFileSync(feed, readFileSync(feed, 'utf8').replace('Offline update fixture', 'Malicious update fixture'))
  assert.notEqual(call(['--verify', feed]).status, 0)
})

test('version bump rejects invalid or older versions without modifying the plist', (t) => {
  const fixture = mkdtempSync(join(tmpdir(), 'benchgauge-version-'))
  t.after(() => rmSync(fixture, { recursive: true, force: true }))
  mkdirSync(join(fixture, 'Scripts'))
  mkdirSync(join(fixture, 'apps/macos/Sources/Resources'), { recursive: true })
  for (const name of ['bump-version.mjs', 'release-lib.mjs', 'app-config.mjs', 'app-version.mjs']) copyFileSync(join(root, 'Scripts', name), join(fixture, 'Scripts', name))
  const plist = join(fixture, 'apps/macos/Sources/Resources/Info.plist')
  const key = Buffer.alloc(32, 1).toString('base64')
  mkdirSync(join(fixture, 'config'))
  writeFileSync(join(fixture, 'config/app.json'), JSON.stringify({ version: '20261028', repository: 'cloydlau/ai-benchgauge', updatePublicKey: key }))
  writeFileSync(plist, JSON.stringify({ CFBundleVersion: '2026.10.28', CFBundleShortVersionString: '2026.10.28', BenchGaugeVersion: '20261028', SUPublicEDKey: key }))
  for (const version of ['20261027', '1.1.0', 'garbage', '20261029-rc.1', '20260230']) {
    const before = readFileSync(plist)
    const result = spawnSync(process.execPath, [join(fixture, 'Scripts/bump-version.mjs'), version])
    assert.notEqual(result.status, 0)
    assert.deepEqual(readFileSync(plist), before)
  }
  assert.equal(spawnSync(process.execPath, [join(fixture, 'Scripts/bump-version.mjs'), '20261029']).status, 0)
  assert.deepEqual(JSON.parse(readFileSync(plist)), { CFBundleVersion: '2026.10.29', CFBundleShortVersionString: '2026.10.29', BenchGaugeVersion: '20261029', SUPublicEDKey: key })
  assert.equal(JSON.parse(readFileSync(join(fixture, 'config/app.json'))).version, '20261029')
  const before = readFileSync(plist)
  assert.equal(spawnSync(process.execPath, [join(fixture, 'Scripts/bump-version.mjs'), '20261029']).status, 0)
  assert.deepEqual(readFileSync(plist), before, 'Same-day version preparation is idempotent')

  // Exercise the actual no-argument CLI without changing this checkout's version.
  const configFile = join(fixture, 'config/app.json')
  const config = JSON.parse(readFileSync(configFile))
  writeFileSync(configFile, JSON.stringify({ ...config, version: '20000101' }))
  writeFileSync(plist, JSON.stringify({ CFBundleVersion: '2000.1.1', CFBundleShortVersionString: '2000.1.1', BenchGaugeVersion: '20000101', SUPublicEDKey: key }))
  const dayBefore = createAutoVersion()
  const automatic = spawnSync(process.execPath, [join(fixture, 'Scripts/bump-version.mjs')], { encoding: 'utf8' })
  assert.equal(automatic.status, 0, automatic.stderr)
  const version = JSON.parse(readFileSync(configFile)).version
  assert.ok([dayBefore, createAutoVersion()].includes(version), 'Automatic version uses the current Beijing date')
  assert.deepEqual(JSON.parse(readFileSync(plist)), { CFBundleVersion: platformVersion(version), CFBundleShortVersionString: platformVersion(version), BenchGaugeVersion: version, SUPublicEDKey: key })
})
