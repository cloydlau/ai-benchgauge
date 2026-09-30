import { readFileSync, writeFileSync, mkdirSync } from 'node:fs'
import { createHash } from 'node:crypto'
import { resolve, join } from 'node:path'

// No browser renderer or modelled Windows UI: embed the captured native pixels.
const root = resolve(import.meta.dirname, '..')
const directory = resolve(process.argv[2] || join(root, 'work/visual-parity'))
const fixtureBytes = readFileSync(join(root, 'tests/fixtures/visual-state.json'))
const fixture = JSON.parse(fixtureBytes)
const fixtureHash = createHash('sha256').update(fixtureBytes).digest('hex')
const windows = JSON.parse(readFileSync(join(directory, 'windows/metadata.json')))
const macos = JSON.parse(readFileSync(join(directory, 'macos/metadata.json')))
for (const item of [...windows, ...macos]) {
  if (item.fixtureHash !== fixtureHash) throw new Error('Screenshots use different fixture data; capture both platforms again')
}
const image = file => `data:image/png;base64,${readFileSync(file).toString('base64')}`
const cases = fixture.cases.map(test => {
  const win = windows.find(item => item.Id === test.id)
  if (!win || win.clientPixelWidth !== Math.round(test.width * win.dpiScale) || win.clientPixelHeight !== Math.round(test.height * win.dpiScale))
    throw new Error('Windows client viewport does not match fixture: ' + test.id)
  return { ...test, windows: win, macos: macos.filter(item => item.id === test.id), frames: [0, 1, 2].map(frame => ({
    windows: image(join(directory, 'windows', `${test.id}-frame-${frame}.png`)),
    light: image(join(directory, 'macos', `${test.id}-light-frame-${frame}.png`)),
    dark: image(join(directory, 'macos', `${test.id}-dark-frame-${frame}.png`)),
  })) }
})
const template = readFileSync(join(root, 'Scripts/visual-report.html'), 'utf8')
const output = template.replace('/* CAPTURE_DATA */', `const captures = ${JSON.stringify(cases).replaceAll('<', '\\u003c')};`)
mkdirSync(directory, { recursive: true })
writeFileSync(join(directory, 'comparison.html'), output)
writeFileSync(join(directory, 'coverage.json'), JSON.stringify({ fixtureHash, cases: cases.length,
  windowsFrames: cases.length * 3, macosFrames: cases.length * 6,
  limitations: ['Windows runner is Server 2022, not Windows 10/11', 'Captured DPI recorded in metadata; 125%/150% not simulated',
    'Three checkpoints per state, not a continuous video', 'No automatic pixel equality across native font renderers',
    'Category switching, company grouping, menus and installed-empty state not covered in this first fixture'] }, null, 2) + '\n')
console.log(`Native comparison: ${cases.length} cases, ${cases.length * 9} frames → ${join(directory, 'comparison.html')}`)
