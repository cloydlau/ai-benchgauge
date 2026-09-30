import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { requireVisualReviewer, checkVisualReviewPolicy } from './visual-review-policy.mjs'
import { validateCaptureMetadata, validatePNG } from './visual-report.mjs'

const fixture = { cases: [{ id: 'normal', width: 900, height: 820 }] }
const revision = 'a'.repeat(40)
const win = () => [{ Id: 'normal', Width: 900, Height: 820, clientPixelWidth: 900, clientPixelHeight: 820,
  dpiScale: 1, fixtureHash: 'hash', sourceCommit: revision }]
const mac = () => ['light', 'dark'].map(theme => ({ id: 'normal', theme, width: '900', height: '820',
  backingScale: '2', fixtureHash: 'hash', sourceCommit: revision }))
const check = (w, m) => validateCaptureMetadata(fixture, w, m, 'hash', revision)

test('incomplete states, duplicate metadata and missing Mac themes block comparison', () => {
  assert.doesNotThrow(() => check(win(), mac()))
  assert.throws(() => check([], mac()), /Incomplete/)
  assert.throws(() => check(win(), [mac()[0], mac()[0]]), /duplicate/)
  const themes = mac(); themes[1].theme = 'other'
  assert.throws(() => check(win(), themes), /theme/)
})
test('different fixtures or old source revisions cannot be reported as this CI run', () => {
  const w = win(); w[0].fixtureHash = 'old'; assert.throws(() => check(w, mac()), /fixture data/)
  const m = mac(); m[1].sourceCommit = 'old'; assert.throws(() => check(win(), m), /source revision/)
  const absent = win(); delete absent[0].sourceCommit; assert.throws(() => check(absent, mac()), /source revision/)
})
test('both platform viewports and actual DPI must match the fixture', () => {
  const w = win(); w[0].dpiScale = 1.5; assert.throws(() => check(w, mac()), /Windows client/)
  w[0].clientPixelWidth = 1350; w[0].clientPixelHeight = 1230; assert.doesNotThrow(() => check(w, mac()))
  const m = mac(); m[0].width = '901'; assert.throws(() => check(win(), m), /Mac client/)
  m[0].width = '900'; m[0].backingScale = 'unknown'; assert.throws(() => check(win(), m), /Mac client/)
})
test('wrong file format, cropped PNG and scaled image dimensions fail validation', () => {
  const png = Buffer.alloc(33)
  Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]).copy(png)
  png.write('IHDR', 12); png.writeUInt32BE(900, 16); png.writeUInt32BE(820, 20)
  assert.doesNotThrow(() => validatePNG(png, 900, 820, 'test'))
  assert.throws(() => validatePNG(png, 1800, 1640, 'test'), /incorrectly sized/)
  assert.throws(() => validatePNG(Buffer.from('fake screenshot'), 900, 820, 'test'), /invalid/)
})
const protectedEnvironment = { name: 'native-visual-review', protection_rules: [
  { type: 'required_reviewers', reviewers: [{ type: 'User', reviewer: { id: 1 } }] },
] }
test('an absent or unprotected environment never silently accepts visual review', () => {
  for (const value of [null, { name: 'native-visual-review', protection_rules: [] },
    { name: 'native-visual-review', protection_rules: [{ type: 'required_reviewers', reviewers: [] }] }])
    assert.throws(() => requireVisualReviewer(value), /release is blocked/)
  assert.doesNotThrow(() => requireVisualReviewer(protectedEnvironment))
})
test('API errors and removed reviewers fail closed', async () => {
  const env = { GITHUB_REPOSITORY: 'owner/repo', GH_TOKEN: 'test-value' }
  await assert.rejects(checkVisualReviewPolicy({ env, request: async () => ({ ok: false, status: 404 }) }), /release is blocked/)
  await assert.rejects(checkVisualReviewPolicy({ env, request: async () => ({ ok: true, json: async () => ({}) }) }), /release is blocked/)
  await assert.rejects(checkVisualReviewPolicy({ env, request: async () => { throw new Error('network unavailable') } }), /network/)
})
test('PR CI always captures and release publishing depends on the protected review', () => {
  const read = name => readFileSync(new URL(`../.github/workflows/${name}`, import.meta.url), 'utf8').replaceAll('\r\n', '\n')
  const ci = read('ci.yml'), release = read('release.yml'), visual = read('visual-parity.yml')
  assert.match(ci, /visual:\n\s+uses: \.\/\.github\/workflows\/visual-parity.yml/)
  assert.match(release, /visual:\n\s+uses: \.\/\.github\/workflows\/visual-parity.yml\n\s+with:\n\s+require_review: true/)
  assert.match(release, /publish:\n\s+needs: \[macos, windows, visual\]/)
  assert.match(visual, /name: native-visual-review/)
  assert.match(visual, /needs: \[comparison, review-policy\]/)
  assert.match(visual, /run: node Scripts\/visual-review-policy.mjs/)
  assert.doesNotMatch(ci + visual, /\n\s+paths:/)
  assert.doesNotMatch(release + visual, /continue-on-error: true/)
})
