import { brandGlyphs } from './brand-glyphs.js'

export const brandLogoAspect = 142 / 166
export const brandLogoSource = dark => `/assets/header-logo${dark ? '-dark' : ''}.png`

// Native iOS font outlines give both the view and exported Canvas the same ink
// bounds on every platform, including the first offline render.
export function brandTitleLayout(_context, name, fontSize) {
  const english = name === 'AI BenchGauge', scale = fontSize / 21
  const keys = english ? ['en-I', 'en-name'] : ['zh-I', 'zh-tian', 'zh-ti']
  const logoHeight = brandGlyphs[keys[0]].height * scale, logoWidth = logoHeight * brandLogoAspect
  const height = Math.max(...keys.map(key => brandGlyphs[key].height * scale))
  const logoTop = (height - logoHeight) / 2, gap = 2.5 * scale
  let x = logoWidth
  const glyphs = keys.map((key, index) => {
    const part = brandGlyphs[key], width = part.width * scale, glyphHeight = part.height * scale
    x += english && index === 1 ? fontSize * 0.34 : gap
    const y = (height - glyphHeight) / 2
    const glyph = { key, text: part.text, x, y, width, height: glyphHeight,
      source: `/assets/brand-glyphs/${key}`,
      style: `left:${x}px;top:${y}px;width:${width}px;height:${glyphHeight}px;` }
    x += width
    return glyph
  })
  return { width: x, height, scale, logoWidth, logoHeight, logoTop, glyphs,
    style: `width:${x}px;height:${height}px;`,
    logoStyle: `width:${logoWidth}px;height:${logoHeight}px;top:${logoTop}px;` }
}

export function createBrandMeasurer() {
  return (name, fontSize) => brandTitleLayout(null, name, fontSize)
}

export function drawBrandGlyphs(context, title, x, y) {
  const methods = { M: 'moveTo', L: 'lineTo', Q: 'quadraticCurveTo', C: 'bezierCurveTo', Z: 'closePath' }
  for (const glyph of title.glyphs) {
    context.beginPath()
    for (const [command, ...points] of brandGlyphs[glyph.key].commands) {
      context[methods[command]](...points.map((value, index) => value * title.scale + (index % 2 ? y + glyph.y : x + glyph.x)))
    }
    context.fill()
  }
}
