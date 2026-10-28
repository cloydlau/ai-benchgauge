import assert from 'node:assert/strict'
import test from 'node:test'
import { createHash } from 'node:crypto'
import { spawnSync } from 'node:child_process'
import { copyFileSync, cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, symlinkSync, writeFileSync } from 'node:fs'
import { createRequire } from 'node:module'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'

function fixture(t) {
  const root = realpathSync(mkdtempSync(join(tmpdir(), 'benchgauge-source-logos-')))
  t.after(() => rmSync(root, { recursive: true, force: true }))
  for (const path of ['Scripts', 'assets/brand', 'fc']) mkdirSync(join(root, path), { recursive: true })
  copyFileSync(new URL('./source-logos.mjs', import.meta.url), join(root, 'Scripts/source-logos.mjs'))
  cpSync(new URL('../assets/brand/partners', import.meta.url), join(root, 'assets/brand/partners'), { recursive: true })
  writeFileSync(join(root, 'fc/package.json'), '{}')
  symlinkSync(fileURLToPath(new URL('../fc/node_modules', import.meta.url)), join(root, 'fc/node_modules'), 'dir')
  const script = join(root, 'Scripts/source-logos.mjs')
  const output = join(root, 'apps/ios/UI/Resources/SourceLogos')
  const run = (...args) => spawnSync(process.execPath, [script, ...args], { encoding: 'utf8' })
  return { root, script, output, run }
}

test('source mark export writes canonical variants and check mode verifies without repairing output', t => {
  const { root, script, output, run } = fixture(t)
  const missing = run('--check')
  assert.equal(missing.status, 1)
  assert.equal(existsSync(output), false)
  const exported = run()
  assert.equal(exported.status, 0, exported.stderr)
  assert.match(exported.stdout, /Exported local source marks/)
  const check = run('--check')
  assert.equal(check.status, 0, check.stderr)
  assert.match(check.stdout, /match official artwork/)
  assert.deepEqual(readFileSync(join(output, 'NOTICE.txt')), readFileSync(join(root, 'assets/brand/partners/NOTICE.txt')))
  const stale = join(output, 'arena.png')
  writeFileSync(stale, 'stale export')
  const rejected = run('--check')
  assert.equal(rejected.status, 1)
  assert.match(rejected.stderr, /Stale source mark export: arena.png/)
  assert.equal(readFileSync(stale, 'utf8'), 'stale export')
  const imported = spawnSync(process.execPath, ['--input-type=module', '-e', `await import(${JSON.stringify(pathToFileURL(script).href)})`], { encoding: 'utf8' })
  assert.equal(imported.status, 0, imported.stderr)
  assert.equal(imported.stdout, '')
})

test('source marks reject unverified artwork and absent official dark-mode rules', async t => {
  const { root, script } = fixture(t)
  const { renderSourceLogos } = await import(pathToFileURL(script).href)
  const sharp = createRequire(new URL('../fc/package.json', import.meta.url))('sharp')
  const catalogPath = join(root, 'assets/brand/partners/sources.json')
  const catalog = JSON.parse(readFileSync(catalogPath, 'utf8'))
  catalog.sources[0].sha256 = '0'.repeat(64)
  writeFileSync(catalogPath, JSON.stringify(catalog))
  await assert.rejects(renderSourceLogos(sharp), /Source mark changed without provenance update/)
  const svg = '<svg xmlns="http://www.w3.org/2000/svg" width="2" height="2"><path d="M0 0h2v2H0z"/></svg>'
  const arena = catalog.sources.find(item => item.id === 'arena')
  arena.sha256 = createHash('sha256').update(svg).digest('hex')
  writeFileSync(join(root, 'assets/brand/partners/arena', arena.file), svg)
  writeFileSync(catalogPath, JSON.stringify({ sources: [arena] }))
  await assert.rejects(renderSourceLogos(sharp), /Missing official dark variant: arena/)
})

test('GitHub export uses pinned Tabler artwork and packages its full license across clients', async t => {
  const { root, script, output, run } = fixture(t)
  const { renderGitHubIcon } = await import(pathToFileURL(script).href)
  const sharp = createRequire(new URL('../fc/package.json', import.meta.url))('sharp')
  const exported = run()
  assert.equal(exported.status, 0, exported.stderr)
  const png = await renderGitHubIcon(sharp)
  assert.deepEqual(readFileSync(join(root, 'assets/logos/github.png')), png)
  assert.deepEqual(readFileSync(new URL('../assets/logos/github.png', import.meta.url)), png)
  assert.equal((await sharp(png).metadata()).width, 128)
  const license = readFileSync(join(root, 'assets/brand/partners/github/LICENSE.txt'), 'utf8')
  assert.match(license, /Copyright \(c\) 2020-2026 Paweł Kuna/)
  assert.equal(readFileSync(join(root, 'apps/macos/Sources/Resources/Licenses/Tabler.txt'), 'utf8'), license)
  assert.equal(readFileSync(new URL('../apps/macos/Sources/Resources/Licenses/Tabler.txt', import.meta.url), 'utf8'), license)
  assert.ok(readFileSync(join(output, 'NOTICE.txt'), 'utf8').includes(license.trim()))
  const windows = readFileSync(new URL('../apps/windows/BenchGauge/BenchGauge.csproj', import.meta.url), 'utf8')
  assert.match(windows, /assets\/brand\/partners\/github\/LICENSE\.txt" Link="Licenses\/Tabler\.txt"/)
  const manifest = JSON.parse(readFileSync(new URL('../apps/macos/Sources/Resources/Licenses/ThirdParty.json', import.meta.url), 'utf8'))
  assert.equal(manifest.find(item => item.id === 'tabler').file, 'Tabler.txt')
  const path = join(root, 'assets/logos/github.png')
  writeFileSync(path, 'stale')
  assert.equal(run('--check').status, 1)
  assert.equal(readFileSync(path, 'utf8'), 'stale')
  for (const file of ['logo.svg', 'LICENSE.txt']) {
    const path = join(root, 'assets/brand/partners/github', file)
    const original = readFileSync(path)
    writeFileSync(path, Buffer.concat([original, Buffer.from('\n')]))
    await assert.rejects(renderGitHubIcon(sharp), /GitHub icon changed without provenance update/)
    writeFileSync(path, original)
  }
})
