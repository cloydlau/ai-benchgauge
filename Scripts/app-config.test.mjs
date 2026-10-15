import assert from 'node:assert/strict'
import test from 'node:test'
import { generateKeyPairSync, verify } from 'node:crypto'
import { spawnSync } from 'node:child_process'
import { chmodSync, copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
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
test('Windows release switch accepts booleans and preserves legacy configuration', t => {
  const f = fixture(t)
  const path = join(f.dir, 'config/app.json')
  for (const releaseWindows of [undefined, true, false]) {
    writeFileSync(path, JSON.stringify({ ...f.config, releaseWindows }))
    assert.equal(validateAppConfig(f.dir).releaseWindows, releaseWindows)
  }
  for (const releaseWindows of [null, 'false', 0, []]) {
    writeFileSync(path, JSON.stringify({ ...f.config, releaseWindows }))
    assert.throws(() => validateAppConfig(f.dir), /releaseWindows must be a boolean/)
  }
})
test('Mac-only finalization publishes only Mac assets even with stale Windows files, and Windows can be restored', t => {
  const f = fixture(t)
  for (const file of ['complete-release.mjs', 'app-config.mjs', 'release-lib.mjs']) copyFileSync(join(root, 'Scripts', file), join(f.dir, 'Scripts', file))
  const configPath = join(f.dir, 'config/app.json')
  writeFileSync(configPath, JSON.stringify({ ...f.config, releaseWindows: false }))
  const output = join(f.dir, 'outputs/release')
  const mac = 'AI-BenchGauge-1.2.3-macos-universal.dmg', windows = 'AI-BenchGauge-1.2.3-windows-x64-setup.exe'
  writeFileSync(join(output, mac), Buffer.alloc(1024))
  writeFileSync(join(output, 'appcast.xml'), `/v1.2.3/${mac}`)
  writeFileSync(join(output, 'release-notes.md'), 'Mac-only fixture')
  const invoke = () => spawnSync(process.execPath, [join(f.dir, 'Scripts/complete-release.mjs'), 'v1.2.3'], { encoding: 'utf8', env: { ...process.env, SPARKLE_PRIVATE_KEY: f.seed } })
  assert.equal(invoke().status, 0)
  assert.equal(existsSync(join(output, 'windows-update.json')), false)
  assert.equal(existsSync(join(output, 'windows-update.json.sig')), false)
  const expected = [mac, 'appcast.xml', 'ai-benchgauge.rb']
  const sums = () => readFileSync(join(output, 'SHA256SUMS.txt'), 'utf8').trim().split('\n').map(line => line.split('  ')[1])
  assert.deepEqual(sums(), expected)
  for (const name of [windows, 'windows-update.json', 'windows-update.json.sig']) writeFileSync(join(output, name), 'stale Windows file')
  assert.equal(invoke().status, 0)
  assert.deepEqual(sums(), expected)
  // Run the real workflow upload command with a local gh stub; no network or release is created.
  const workflow = readFileSync(join(root, '.github/workflows/release.yml'), 'utf8')
  const run = workflow.split('      - name: Publish complete stable release\n')[1].split('        run: |\n')[1].split('      - name: Publish Homebrew cask\n')[0].replace(/^          /gm, '')
  const bin = join(f.dir, 'bin'); mkdirSync(bin)
  const gh = join(bin, 'gh'), calls = join(f.dir, 'gh-calls.jsonl')
  writeFileSync(gh, `#!${process.execPath}\nrequire('node:fs').appendFileSync(${JSON.stringify(calls)}, JSON.stringify(process.argv.slice(2)) + '\\n')\n`)
  chmodSync(gh, 0o755)
  const publish = spawnSync('/bin/bash', ['-e', '-c', run], { cwd: f.dir, encoding: 'utf8', env: { ...process.env, PATH: bin + ':' + process.env.PATH, RELEASE_TAG: 'v1.2.3' } })
  assert.equal(publish.status, 0, publish.stderr)
  const [create, edit] = readFileSync(calls, 'utf8').trim().split('\n').map(JSON.parse)
  assert.deepEqual(create.filter(arg => arg.startsWith('outputs/release/') && arg !== 'outputs/release/release-notes.md'), ['outputs/release/SHA256SUMS.txt', ...expected.map(name => 'outputs/release/' + name)])
  assert.deepEqual(edit, ['release', 'edit', 'v1.2.3', '--draft=false', '--latest'])
  writeFileSync(configPath, JSON.stringify({ ...f.config, releaseWindows: true }))
  assert.notEqual(invoke().status, 0) // stale installer must be rejected when enabled again
  writeFileSync(join(output, windows), Buffer.concat([Buffer.from('MZ'), Buffer.alloc(1022)]))
  assert.equal(invoke().status, 0)
  assert.equal(sums().length, 6)
  const payload = readFileSync(join(output, 'windows-update.json'))
  assert.ok(verify(null, payload, f.publicKey, Buffer.from(readFileSync(join(output, 'windows-update.json.sig'), 'utf8').trim(), 'base64')))
})
test('CC Switch preview accepts three states or automatic detection and rejects invalid switches', t => {
  const f = fixture(t)
  for (const previewCCSwitchState of [null, 'notInstalled', 'installedEmpty', 'configured']) {
    writeFileSync(join(f.dir, 'config/app.json'), JSON.stringify({ ...f.config, previewCCSwitchState }))
    assert.equal(validateAppConfig(f.dir).previewCCSwitchState, previewCCSwitchState)
  }
  writeFileSync(join(f.dir, 'config/app.json'), JSON.stringify({ ...f.config, previewCCSwitchEmptyState: true }))
  assert.throws(() => validateAppConfig(f.dir), /previewCCSwitchState/)
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

test('release finalization rejects each installer, feed and encoded metadata boundary', t => {
  const f = fixture(t)
  for (const name of ['complete-release.mjs', 'app-config.mjs', 'release-lib.mjs', 'bump-version.mjs']) copyFileSync(join(root, 'Scripts', name), join(f.dir, 'Scripts', name))
  const output = join(f.dir, 'outputs/release'), mac = join(output, 'AI-BenchGauge-1.2.3-macos-universal.dmg'), windows = join(output, 'AI-BenchGauge-1.2.3-windows-x64-setup.exe')
  const feed = join(output, 'appcast.xml'), notes = join(output, 'release-notes.md')
  const goodWindows = Buffer.concat([Buffer.from('MZ'), Buffer.alloc(1022, 9)])
  const invoke = () => spawnSync(process.execPath, [join(f.dir, 'Scripts/complete-release.mjs')], { encoding: 'utf8', env: { ...process.env, GITHUB_REF_NAME: 'v1.2.3', SPARKLE_PRIVATE_KEY: f.seed } })
  writeFileSync(mac, Buffer.alloc(1024)); writeFileSync(windows, goodWindows)
  writeFileSync(feed, '/v1.2.3/AI-BenchGauge-1.2.3-macos-universal.dmg'); writeFileSync(notes, 'fixture')
  assert.equal(invoke().status, 0)
  for (const [file, invalid] of [[mac, Buffer.alloc(1)], [windows, Buffer.alloc(1)], [windows, Buffer.alloc(1024)]]) {
    writeFileSync(file, invalid)
    assert.match(invoke().stderr, /Invalid platform installers/)
    writeFileSync(mac, Buffer.alloc(1024)); writeFileSync(windows, goodWindows)
  }
  writeFileSync(feed, 'wrong feed'); assert.match(invoke().stderr, /feed does not match/)
  writeFileSync(feed, '/v1.2.3/AI-BenchGauge-1.2.3-macos-universal.dmg')
  writeFileSync(notes, '\u0000'.repeat(12000)); assert.match(invoke().stderr, /metadata exceeds limit/)
  const plist = join(f.dir, 'apps/macos/Sources/Resources/Info.plist')
  writeFileSync(plist, `<plist><key>CFBundleVersion</key><string>1.2.3</string><key>CFBundleShortVersionString</key><string>1.2.3</string><key>SUPublicEDKey</key><string>${f.config.updatePublicKey}</string></plist>`)
  const bumped = spawnSync(process.execPath, [join(f.dir, 'Scripts/bump-version.mjs'), '1.2.4'], { encoding: 'utf8' })
  assert.equal(bumped.status, 0, bumped.stderr)
  assert.match(readFileSync(plist, 'utf8'), /<string>1.2.4<\/string>/)
})
