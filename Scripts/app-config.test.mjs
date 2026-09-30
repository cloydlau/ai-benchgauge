import assert from 'node:assert/strict'
import test from 'node:test'
import { generateKeyPairSync, verify } from 'node:crypto'
import { spawnSync } from 'node:child_process'
import { copyFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { validateAppConfig } from './app-config.mjs'
import { renderAppcast, sha256 } from './release-lib.mjs'
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..')
function fixture(t) {
  const dir = mkdtempSync(join(tmpdir(), 'benchgauge-release-'))
  t.after(() => rmSync(dir, { recursive: true, force: true }))
  for (const folder of ['config', 'apps/macos/Sources/Resources', 'Scripts', 'outputs/release']) mkdirSync(join(dir, folder), { recursive: true })
  const { privateKey, publicKey } = generateKeyPairSync('ed25519')
  const publicEncoded = publicKey.export({ type: 'spki', format: 'der' }).subarray(-32).toString('base64')
  const seed = privateKey.export({ type: 'pkcs8', format: 'der' }).subarray(-32).toString('base64')
  const config = { version: '1.2.3', repository: 'cloydlau/ai-benchgauge', updatePublicKey: publicEncoded }
  writeFileSync(join(dir, 'config/app.json'), JSON.stringify(config))
  const info = { CFBundleVersion: config.version, CFBundleShortVersionString: config.version, SUPublicEDKey: publicEncoded }
  writeFileSync(join(dir, 'apps/macos/Sources/Resources/Info.plist'), JSON.stringify(info))
  return { dir, config, info, seed, publicKey }
}
test('shared version and update key cannot diverge by platform', t => {
  const f = fixture(t)
  assert.deepEqual(validateAppConfig(f.dir, 'v1.2.3'), f.config)
  assert.throws(() => validateAppConfig(f.dir, 'v1.2.4'))
  const plist = join(f.dir, 'apps/macos/Sources/Resources/Info.plist')
  writeFileSync(plist, JSON.stringify({ ...f.info, CFBundleVersion: '1.2.4' }))
  assert.throws(() => validateAppConfig(f.dir))
  writeFileSync(plist, JSON.stringify({ ...f.info, SUPublicEDKey: Buffer.alloc(32).toString('base64') }))
  assert.throws(() => validateAppConfig(f.dir))
})
test('CC Switch preview accepts three states or automatic detection and rejects invalid switches', t => {
  const f = fixture(t)
  for (const previewCCSwitchState of [null, 'notInstalled', 'installedEmpty', 'configured']) {
    writeFileSync(join(f.dir, 'config/app.json'), JSON.stringify({ ...f.config, previewCCSwitchState }))
    assert.equal(validateAppConfig(f.dir).previewCCSwitchState, previewCCSwitchState)
  }
  for (const previewCCSwitchState of [true, false, 'empty']) {
    writeFileSync(join(f.dir, 'config/app.json'), JSON.stringify({ ...f.config, previewCCSwitchState }))
    assert.throws(() => validateAppConfig(f.dir), /previewCCSwitchState/)
  }
})
test('release summary requires both installers and signs immutable Windows metadata', t => {
  const f = fixture(t)
  for (const file of ['complete-release.mjs', 'app-config.mjs', 'release-lib.mjs']) copyFileSync(join(root, 'Scripts', file), join(f.dir, 'Scripts', file))
  const output = join(f.dir, 'outputs/release'); const mac = 'AI-BenchGauge-1.2.3-macos-universal.dmg'; const windows = 'AI-BenchGauge-1.2.3-windows-x64-setup.exe'
  writeFileSync(join(output, mac), Buffer.alloc(1024, 7))
  writeFileSync(join(output, 'release-notes.md'), 'Fixture notes')
  writeFileSync(join(output, 'appcast.xml'), renderAppcast({ version: '1.2.3', archiveName: mac, signature: Buffer.alloc(64).toString('base64'), length: 1024, notes: 'test' }))
  const invoke = () => spawnSync(process.execPath, [join(f.dir, 'Scripts/complete-release.mjs'), 'v1.2.3'], { env: { ...process.env, SPARKLE_PRIVATE_KEY: f.seed } })
  assert.notEqual(invoke().status, 0)
  const bytes = Buffer.concat([Buffer.from('MZ'), Buffer.alloc(1022, 9)])
  writeFileSync(join(output, windows), bytes)
  assert.equal(invoke().status, 0)
  const payload = readFileSync(join(output, 'windows-update.json'))
  const signature = Buffer.from(readFileSync(join(output, 'windows-update.json.sig'), 'utf8').trim(), 'base64')
  assert.ok(verify(null, payload, f.publicKey, signature))
  const update = JSON.parse(payload); assert.equal(update.length, bytes.length); assert.equal(update.sha256, sha256(bytes)); assert.ok(update.url.endsWith('/v1.2.3/' + windows))
  const changed = Buffer.from(payload); changed[20] ^= 1; assert.equal(verify(null, changed, f.publicKey, signature), false)
  const sums = readFileSync(join(output, 'SHA256SUMS.txt'), 'utf8')
  const cask = readFileSync(join(output, 'ai-benchgauge.rb'), 'utf8')
  assert.match(sums, new RegExp(`^${sha256(Buffer.from(cask))}  ai-benchgauge\\.rb$`, 'm'))
  assert.match(cask, /version "1\.2\.3"/)
  assert.match(cask, /url "https:\/\/github\.com\/cloydlau\/ai-benchgauge\/releases\/download\/v1\.2\.3\/AI-BenchGauge-1\.2\.3-macos-universal\.dmg"/)
  assert.match(cask, new RegExp(`sha256 "${sha256(Buffer.alloc(1024, 7))}"`))
  assert.equal(sums.trim().split('\n').length, 6)
})
