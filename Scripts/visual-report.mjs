import { readFileSync, writeFileSync, mkdirSync } from 'node:fs'
import { createHash } from 'node:crypto'
import { resolve, join } from 'node:path'
import { pathToFileURL } from 'node:url'

const root = resolve(import.meta.dirname, '..')
export const limitations = [
  'Windows runner is Server 2022, not Windows 10/11',
  'Captured DPI recorded in metadata; 125%/150% not simulated',
  'Three checkpoints per state, not a continuous video',
  'Capture success is not visual approval; native font renderers differ',
  'Category switching, company grouping, menus, installed-empty and update/auth dialogs are not yet covered',
]

export function validateCaptureMetadata(fixture, windows, macos, fixtureHash, sourceCommit) {
  const ids = fixture.cases.map(item => item.id)
  if (new Set(ids).size !== ids.length || ids.some(id => !/^[\w-]+$/.test(id))) throw new Error('Invalid or duplicate fixture case ID')
  if (windows.length !== ids.length || macos.length !== ids.length * 2 ||
    new Set(windows.map(item => item.Id)).size !== windows.length ||
    new Set(macos.map(item => `${item.id}/${item.theme}`)).size !== macos.length) throw new Error('Incomplete or duplicate capture metadata')
  for (const item of [...windows, ...macos]) {
    if (item.fixtureHash !== fixtureHash) throw new Error('Screenshots use different fixture data; capture both platforms again')
    if (sourceCommit && item.sourceCommit !== sourceCommit) throw new Error('Screenshots use a different source revision; capture this commit on both platforms')
  }
  for (const test of fixture.cases) {
    const win = windows.find(item => item.Id === test.id)
    if (!win || !Number.isFinite(win.dpiScale) || win.dpiScale <= 0 ||
      win.Width !== test.width || win.Height !== test.height ||
      win.clientPixelWidth !== Math.round(test.width * win.dpiScale) ||
      win.clientPixelHeight !== Math.round(test.height * win.dpiScale))
      throw new Error('Windows client viewport does not match fixture: ' + test.id)
    for (const theme of ['light', 'dark']) {
      const mac = macos.find(item => item.id === test.id && item.theme === theme)
      if (!mac || Number(mac.width) !== test.width || Number(mac.height) !== test.height ||
        !Number.isFinite(Number(mac.backingScale)) || Number(mac.backingScale) <= 0)
        throw new Error('Mac client viewport or theme does not match fixture: ' + test.id)
    }
  }
}

export function validatePNG(bytes, width, height, label) {
  if (bytes.length < 33 || !bytes.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10])) ||
    bytes.toString('ascii', 12, 16) !== 'IHDR' || bytes.readUInt32BE(16) !== width || bytes.readUInt32BE(20) !== height)
    throw new Error('Missing, invalid or incorrectly sized native PNG: ' + label)
}

// Embed actual native pixels, never a browser imitation of either application.
export function buildVisualReport(directory = join(root, 'work/visual-parity'), env = process.env) {
  directory = resolve(directory)
  const fixtureBytes = readFileSync(join(root, 'Tests/fixtures/visual-state.json'))
  const fixture = JSON.parse(fixtureBytes)
  const fixtureHash = createHash('sha256').update(fixtureBytes.toString('utf8').replaceAll('\r\n', '\n')).digest('hex')
  const windows = JSON.parse(readFileSync(join(directory, 'windows/metadata.json')))
  const macos = JSON.parse(readFileSync(join(directory, 'macos/metadata.json')))
  const sourceCommit = env.GITHUB_SHA || null
  validateCaptureMetadata(fixture, windows, macos, fixtureHash, sourceCommit)
  const image = (platform, name, width, height) => {
    const bytes = readFileSync(join(directory, platform, name))
    validatePNG(bytes, width, height, `${platform}/${name}`)
    return `data:image/png;base64,${bytes.toString('base64')}`
  }
  const cases = fixture.cases.map(test => {
    const win = windows.find(item => item.Id === test.id)
    const mac = macos.filter(item => item.id === test.id)
    return { ...test, windows: win, macos: mac, frames: [0, 1, 2].map(frame => ({
      windows: image('windows', `${test.id}-frame-${frame}.png`, win.clientPixelWidth, win.clientPixelHeight),
      ...Object.fromEntries(['light', 'dark'].map(theme => {
        const scale = Number(mac.find(item => item.theme === theme).backingScale)
        return [theme, image('macos', `${test.id}-${theme}-frame-${frame}.png`, Math.round(test.width * scale), Math.round(test.height * scale))]
      })),
    })) }
  })
  const coverage = { fixtureHash, sourceCommit, sourceVerified: Boolean(sourceCommit), cases: cases.length,
    windowsFrames: cases.length * 3, macosFrames: cases.length * 6, visualApproval: 'not-automated',
    environments: { windows: [...new Set(windows.map(item => `${item.os} / ${Math.round(item.dpiScale * 100)}%`))],
      macos: [...new Set(macos.map(item => `${item.os} / ${item.backingScale}x`))] }, limitations }
  const template = readFileSync(join(root, 'Scripts/visual-report.html'), 'utf8')
  const output = template.replace('/* CAPTURE_DATA */', `const captures = ${JSON.stringify(cases).replaceAll('<', '\\u003c')};\nconst coverage = ${JSON.stringify(coverage).replaceAll('<', '\\u003c')};`)
  mkdirSync(directory, { recursive: true })
  writeFileSync(join(directory, 'comparison.html'), output)
  writeFileSync(join(directory, 'coverage.json'), JSON.stringify(coverage, null, 2) + '\n')
  console.log(`Native comparison: ${cases.length} cases, ${cases.length * 9} frames → ${join(directory, 'comparison.html')}`)
  return coverage
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) buildVisualReport(process.argv[2])
