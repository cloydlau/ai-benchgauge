import { readFileSync, writeFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = fileURLToPath(new URL('../', import.meta.url))

// Compute geometry once. Both clients scale these exact positions and paths.
export function mobileBrandLayouts(spec) {
  return Object.fromEntries([false, true].map(english => {
    const keys = english ? ['en-I', 'en-name'] : ['zh-I', 'zh-tian', 'zh-ti']
    const policy = english ? spec.english : spec.chinese
    const logoHeight = spec.glyphs[keys[0]].height, logoWidth = logoHeight * spec.logoAspect
    const logoShear = english ? Math.tan(policy.slantDegrees * Math.PI / 180) : 0
    const height = Math.max(...keys.map(key => spec.glyphs[key].height))
    const lift = english ? spec.baseSize * policy.initialsLift : 0
    const logoTop = (height - logoHeight) / 2 - lift
    const logoInkWidth = logoWidth + logoHeight * logoShear
    let x = english ? Math.max(logoWidth + logoHeight * logoShear * policy.kernRectangle,
      logoWidth * policy.kernTriangle + logoHeight * logoShear) : logoInkWidth
    const glyphs = keys.map((key, index) => {
      const { width, height: glyphHeight } = spec.glyphs[key]
      x += english && index === 1 ? spec.baseSize * policy.nameGap : policy.gap
      const glyph = { key, x, y: (height - glyphHeight) / 2 - (english && index === 0 ? lift : 0), width, height: glyphHeight }
      x += width
      return glyph
    })
    return [english ? 'english' : 'chinese', { width: x, height, logoWidth, logoHeight, logoTop,
      logoShear, logoSlant: english ? policy.slantDegrees : 0, logoInkWidth, glyphs }]
  }))
}

export function syncMobileBrand(directory = root, check = false) {
  const spec = JSON.parse(readFileSync(resolve(directory, 'assets/brand/mobile-title.json'), 'utf8'))
  const layouts = mobileBrandLayouts(spec)
  const header = '// Generated from assets/brand/mobile-title.json by Scripts/sync-mobile-brand.mjs.\n'
  const outputs = {
    'apps/weapp/src/core/brand-glyphs.js': `${header}export const brandGlyphs = ${JSON.stringify(spec.glyphs)}\n`,
    'apps/weapp/src/core/brand-layouts.js': `${header}export const brandBaseSize = ${spec.baseSize}\nexport const brandLogoAspect = ${spec.logoAspect}\nexport const brandLayouts = ${JSON.stringify(layouts)}\n`,
    'Sources/LeaderboardKit/Resources/Brand/mobile-title.json': JSON.stringify({ baseSize: spec.baseSize, layouts, glyphs: spec.glyphs }) + '\n',
  }
  for (const [path, content] of Object.entries(outputs)) {
    if (check) {
      if (readFileSync(resolve(directory, path), 'utf8') !== content) throw new Error(`${path} is stale. Run node Scripts/sync-mobile-brand.mjs`)
    } else writeFileSync(resolve(directory, path), content)
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  syncMobileBrand(root, process.argv.includes('--check'))
}
