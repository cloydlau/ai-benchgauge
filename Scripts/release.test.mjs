import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import { createPublicKey, generateKeyPairSync, verify } from 'node:crypto'
import { copyFileSync, existsSync, mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import test from 'node:test'
import { compareVersions, feedURL, releaseVersion, renderAppcast, signArchive, signingKey, validateRelease } from './release-lib.mjs'

const root = dirname(dirname(fileURLToPath(import.meta.url)))
function keys() {
  const { privateKey, publicKey } = generateKeyPairSync('ed25519')
  return { privateKey, publicKey,
    seed: privateKey.export({ format: 'der', type: 'pkcs8' }).subarray(-32).toString('base64'),
    encodedPublic: publicKey.export({ format: 'der', type: 'spki' }).subarray(-32).toString('base64') }
}
function info(publicKey) {
  return { CFBundleIdentifier: 'com.cloydlau.ai-benchgauge', CFBundleShortVersionString: '1.2.3', CFBundleVersion: '1.2.3',
    LSMinimumSystemVersion: '14.0', SUPublicEDKey: publicKey, SUFeedURL: feedURL, SUScheduledCheckInterval: 3600,
    SUEnableAutomaticChecks: true, SUAutomaticallyUpdate: false, SUAllowsAutomaticUpdates: false,
    SURequireSignedFeed: true, SUVerifyUpdateBeforeExtraction: true }
}

test('release versions are numeric and reject prereleases, leading zeros, and shell syntax', () => {
  assert.equal(releaseVersion('v1.2.3'), '1.2.3')
  assert.equal(compareVersions('1.10.0', '1.9.9'), 1)
  assert.equal(compareVersions('2.0.0', '10.0.0'), -1)
  assert.equal(compareVersions('1.2.3', 'v1.2.3'), 0)
  for (const value of ['', '1.0', '01.2.3', '1.2.3-rc.1', '1.2.3+build', 'v1.2.3;touch hacked', '1.2.3\n']) {
    assert.throws(() => releaseVersion(value))
  }
})

test('release validation prevents rollback, version drift, missing keys, and unsafe update configuration', () => {
  const valid = info(keys().encodedPublic)
  assert.equal(validateRelease('v1.2.3', valid, [{ tagName: 'v1.2.2' }]), '1.2.3')
  assert.equal(validateRelease('v1.2.3', valid, [{ tagName: 'v2.0.0-rc.1', isPrerelease: true }]), '1.2.3')
  for (const tagName of ['v1.2.3', 'v1.10.0', 'v2.0.0']) assert.throws(() => validateRelease('v1.2.3', valid, [{ tagName }]))
  for (const changes of [{ CFBundleVersion: '1.2.2' }, { SUPublicEDKey: '' }, { SUFeedURL: 'http://example.com/feed' },
    { SUScheduledCheckInterval: 60 }, { SUAutomaticallyUpdate: true }, { SUAllowsAutomaticUpdates: true },
    { SURequireSignedFeed: false }, { SUVerifyUpdateBeforeExtraction: false }, { CFBundleIdentifier: 'different.app' }]) {
    assert.throws(() => validateRelease('v1.2.3', { ...valid, ...changes }))
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
  const xml = renderAppcast({ version: '1.2.3', archiveName: 'AI-BenchGauge-1.2.3-macos-universal.zip',
    signature: Buffer.alloc(64, 1).toString('base64'), length: 987, notes: '<script>bad()</script> & ]]>\n"notes"', date: new Date('2026-09-29T00:00:00Z') })
  assert.match(xml, /releases\/download\/v1\.2\.3\/AI-BenchGauge-1\.2\.3-macos-universal.zip/)
  assert.match(xml, /<sparkle:minimumSystemVersion>14.0/)
  assert.match(xml, /length="987"/)
  assert.match(xml, /&lt;script&gt;bad\(\)&lt;\/script&gt; &amp; \]\]&gt;/)
  assert.equal(xml.includes('<script>'), false)
  assert.throws(() => renderAppcast({ version: '1.2.3', archiveName: 'arbitrary.zip', signature: '', length: 0 }))
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
  writeFileSync(feed, renderAppcast({ version: '1.2.3', archiveName: 'AI-BenchGauge-1.2.3-macos-universal.zip', signature, length: bytes.length, notes: 'Offline update fixture' }))
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
  for (const name of ['bump-version.mjs', 'release-lib.mjs', 'app-config.mjs']) copyFileSync(join(root, 'Scripts', name), join(fixture, 'Scripts', name))
  const plist = join(fixture, 'apps/macos/Sources/Resources/Info.plist')
  const key = Buffer.alloc(32, 1).toString('base64')
  mkdirSync(join(fixture, 'config'))
  writeFileSync(join(fixture, 'config/app.json'), JSON.stringify({ version: '1.2.3', repository: 'cloydlau/ai-benchgauge', updatePublicKey: key }))
  writeFileSync(plist, JSON.stringify({ CFBundleVersion: '1.2.3', CFBundleShortVersionString: '1.2.3', SUPublicEDKey: key }))
  for (const version of ['1.2.3', '1.1.0', 'garbage', '1.2.4-rc.1']) {
    const before = readFileSync(plist)
    const result = spawnSync(process.execPath, [join(fixture, 'Scripts/bump-version.mjs'), version])
    assert.notEqual(result.status, 0)
    assert.deepEqual(readFileSync(plist), before)
  }
  assert.equal(spawnSync(process.execPath, [join(fixture, 'Scripts/bump-version.mjs'), '1.2.4']).status, 0)
  assert.deepEqual(JSON.parse(readFileSync(plist)), { CFBundleVersion: '1.2.4', CFBundleShortVersionString: '1.2.4', SUPublicEDKey: key })
  assert.equal(JSON.parse(readFileSync(join(fixture, 'config/app.json'))).version, '1.2.4')
})
