import { createHash } from 'node:crypto'
import { readFileSync, mkdirSync, writeFileSync } from 'node:fs'
import { createRequire } from 'node:module'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const partners = resolve(root, 'assets/brand/partners')
const exportsDirectory = resolve(root, 'apps/ios/UI/Resources/SourceLogos')

// Canonical vendor artwork stays in assets/brand/partners. Every runtime PNG is
// an aspect-preserving export, never a template tinted with the app's accent.
export async function renderSourceLogos(sharp) {
  const { sources } = JSON.parse(readFileSync(resolve(partners, 'sources.json'), 'utf8'))
  const assets = []
  for (const item of sources) {
    for (const dark of [false, true]) {
      const file = dark && item.darkFile ? item.darkFile : item.file
      let data = readFileSync(resolve(partners, item.id, file))
      const expected = dark && item.darkFile ? item.darkSHA256 : item.sha256
      if (createHash('sha256').update(data).digest('hex') !== expected) throw new Error(`Source mark changed without provenance update: ${item.id}/${file}`)
      // Arena's official favicon supplies its own white dark-mode variant.
      if (dark && item.darkMedia) {
        const svg = data.toString('utf8')
        const media = /@media \(prefers-color-scheme: dark\)\s*\{\s*(path\s*\{[^}]+\})\s*\}/
        if (!media.test(svg)) throw new Error(`Missing official dark variant: ${item.id}`)
        // SVG rasterizers do not consistently evaluate media queries. Flatten
        // the vendor's own dark rule, keeping its exact path/color definitions.
        data = Buffer.from(svg.replace(media, '$1'))
      }
      const source = await sharp(data).resize(84, 84, {
        fit: 'contain', background: { r: 0, g: 0, b: 0, alpha: 0 },
      }).png().toBuffer()
      assets.push({ name: `${item.id}${dark ? '-dark' : ''}.png`, source })
    }
  }
  assets.push({ name: 'NOTICE.txt', source: readFileSync(resolve(partners, 'NOTICE.txt')) })
  return assets
}

// The platform row uses Tabler's recognizable WeChat outline, not a pair of
// generic chat symbols. Both clients consume the same theme-specific exports.
export async function renderPlatformIcons(sharp) {
  // A 24-unit outline at 18pt needs 4/3 units for a 1pt stroke, matching the
  // neighboring platform icons (2rpx in WeChat, about 1pt on Apple).
  const template = readFileSync(resolve(partners, 'wechat/logo.svg'), 'utf8')
    .replace('stroke-width="2"', `stroke-width="${4 / 3}"`)
  const assets = []
  for (const [suffix, color] of [['', '#687382'], ['-dark', '#a2acba']]) {
    const source = await sharp(Buffer.from(template.replaceAll('currentColor', color)))
      .resize(54, 54).png().toBuffer()
    assets.push({ name: `wechat${suffix}.png`, source })
  }
  return assets
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const sharp = createRequire(new URL('../fc/package.json', import.meta.url))('sharp')
  const check = process.argv.includes('--check')
  if (!check) mkdirSync(exportsDirectory, { recursive: true })
  for (const { name, source } of [...await renderSourceLogos(sharp), ...await renderPlatformIcons(sharp)]) {
    const destination = resolve(exportsDirectory, name)
    if (check) {
      if (!readFileSync(destination).equals(source)) throw new Error(`Stale source mark export: ${name}`)
    } else writeFileSync(destination, source)
  }
  console.log(check ? 'Source mark exports match official artwork.' : 'Exported local source marks for Apple and WeChat clients.')
}
