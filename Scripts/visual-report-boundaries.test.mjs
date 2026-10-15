import test from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import { spawnSync } from 'node:child_process'
import { createHash } from 'node:crypto'
import { tmpdir } from 'node:os'
import { join, resolve } from 'node:path'
import { syncBuiltinESMExports } from 'node:module'
import { buildVisualReport, validateCaptureMetadata } from './visual-report.mjs'

const root = resolve(import.meta.dirname, '..')
function png(width, height) {
  // A header fixture for the metadata validator; this is never a native capture or release approval.
  const bytes = Buffer.alloc(33)
  Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]).copy(bytes)
  bytes.write('IHDR', 12); bytes.writeUInt32BE(width, 16); bytes.writeUInt32BE(height, 20)
  return bytes
}
function fixture(directory, dark, revision) {
  const cases = [{ id: 'fixture-case', width: 40, height: 30, description: '<unit fixture>' }]
  const bytes = Buffer.from(JSON.stringify({ cases }) + '\r\n')
  const hash = createHash('sha256').update(bytes.toString().replaceAll('\r\n', '\n')).digest('hex')
  const windows = (dark ? ['light', 'dark'] : ['light']).map(theme => ({ Id: 'fixture-case', theme, Width: 40, Height: 30, dpiScale: 1.25, clientPixelWidth: 50, clientPixelHeight: 38, fixtureHash: hash, sourceCommit: revision, os: 'unit fixture' }))
  const macos = ['light', 'dark'].map(theme => ({ id: 'fixture-case', theme, width: 40, height: 30, backingScale: 2, fixtureHash: hash, sourceCommit: revision, os: 'unit fixture' }))
  fs.mkdirSync(directory, { recursive: true })
  for (const [platform, metadata] of [['windows', windows], ['macos', macos]]) {
    fs.mkdirSync(join(directory, platform), { recursive: true })
    fs.writeFileSync(join(directory, platform, 'metadata.json'), JSON.stringify(metadata))
  }
  for (let frame = 0; frame < 3; frame++) {
    fs.writeFileSync(join(directory, 'windows', `fixture-case-frame-${frame}.png`), png(50, 38))
    if (dark) fs.writeFileSync(join(directory, 'windows', `fixture-case-dark-frame-${frame}.png`), png(50, 38))
    for (const theme of ['light', 'dark']) fs.writeFileSync(join(directory, 'macos', `fixture-case-${theme}-frame-${frame}.png`), png(80, 60))
  }
  return { bytes, cases, windows, macos, hash }
}

test('report assembly embeds only validated fixture bytes and records its limitations', t => {
  const directory = fs.mkdtempSync(join(tmpdir(), 'benchgauge-report-unit-'))
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }))
  const originalRead = fs.readFileSync
  let fixtureBytes
  t.mock.method(fs, 'readFileSync', (file, ...args) => resolve(String(file)) === join(root, 'Tests/fixtures/visual-state.json') ? fixtureBytes : originalRead(file, ...args))
  syncBuiltinESMExports()
  t.after(() => { t.mock.restoreAll(); syncBuiltinESMExports() })
  for (const dark of [false, true]) {
    const f = fixture(directory, dark, 'unit-revision'); fixtureBytes = f.bytes
    const report = buildVisualReport(directory, dark ? { GITHUB_SHA: 'unit-revision' } : {})
    assert.equal(report.cases, 1); assert.equal(report.windowsFrames, dark ? 6 : 3)
    assert.equal(report.macosFrames, 6); assert.equal(report.sourceVerified, dark)
    assert.equal(report.visualApproval, 'not-automated')
    assert.equal(report.fixtureHash, f.hash)
    const html = originalRead(join(directory, 'comparison.html'), 'utf8')
    assert.ok(html.includes('data:image/png;base64,'))
    assert.ok(html.includes('\\u003cunit fixture>'))
    assert.equal(html.includes('/* CAPTURE_DATA */'), false)
    assert.deepEqual(JSON.parse(originalRead(join(directory, 'coverage.json'), 'utf8')), report)
  }
})

test('metadata validation rejects missing cases even if list lengths match', () => {
  const f = { cases: [{ id: 'expected', width: 40, height: 30 }] }
  const windows = [{ Id: 'unexpected', dpiScale: 1, Width: 40, Height: 30, clientPixelWidth: 40, clientPixelHeight: 30, fixtureHash: 'hash' }]
  const mac = ['light', 'dark'].map(theme => ({ id: 'expected', theme, width: 40, height: 30, backingScale: 1, fixtureHash: 'hash' }))
  assert.throws(() => validateCaptureMetadata(f, windows, mac, 'hash'), /Windows client/)
  windows[0].Id = 'expected'
  mac[0].id = 'unexpected'
  assert.throws(() => validateCaptureMetadata(f, windows, mac, 'hash'), /Mac client/)
})

test('command line report generation uses the same validator', t => {
  const directory = fs.realpathSync(fs.mkdtempSync(join(tmpdir(), 'benchgauge-report-cli-')))
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }))
  const f = fixture(directory, false, null)
  fs.mkdirSync(join(directory, 'Scripts'))
  fs.mkdirSync(join(directory, 'Tests/fixtures'), { recursive: true })
  fs.writeFileSync(join(directory, 'Tests/fixtures/visual-state.json'), f.bytes)
  for (const name of ['visual-report.mjs', 'visual-report.html']) fs.copyFileSync(join(root, 'Scripts', name), join(directory, 'Scripts', name))
  const result = spawnSync(process.execPath, [join(directory, 'Scripts/visual-report.mjs'), directory], { encoding: 'utf8', env: { ...process.env, GITHUB_SHA: '' } })
  assert.equal(result.status, 0, result.stderr)
  assert.equal(fs.existsSync(join(directory, 'comparison.html')), true)
})


test('visual capture metadata rejects a nonidentifier case name', () => {
  assert.throws(() => validateCaptureMetadata({cases:[{id:'invalid id'}]},[],[],'fixture','fixture'), /Invalid or duplicate/)
})
