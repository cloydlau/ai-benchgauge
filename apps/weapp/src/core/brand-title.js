import { brandGlyphs } from './brand-glyphs.js'

export const brandLogoAspect = 142 / 166
export const brandLogoSource = dark => `/assets/header-logo${dark ? '-dark' : ''}.png`

// Native iOS font outlines give both the view and exported Canvas the same ink
// bounds on every platform, including the first offline render.
export function brandTitleLayout(_context, name, fontSize) {
  const english = name === 'AI BenchGauge', scale = fontSize / 21
  const keys = english ? ['en-I', 'en-name'] : ['zh-I', 'zh-tian', 'zh-ti']
  const logoHeight = brandGlyphs[keys[0]].height * scale, logoWidth = logoHeight * brandLogoAspect
  const logoSlant = english ? 12 : 0, logoShear = Math.tan(logoSlant * Math.PI / 180)
  const height = Math.max(...keys.map(key => brandGlyphs[key].height * scale))
  const logoTop = (height - logoHeight) / 2, gap = 2.5 * scale
  // Keep the sheared image rectangle inside the title and clear of I.
  const logoInkWidth = logoWidth + logoHeight * logoShear
  let x = logoInkWidth
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
  return { width: x, height, scale, logoWidth, logoHeight, logoTop, logoShear, logoInkWidth, glyphs,
    style: `width:${x}px;height:${height}px;`,
    logoStyle: `width:${logoWidth}px;height:${logoHeight}px;top:${logoTop}px;`
      + (english ? `transform-origin:left bottom;transform:skewX(-${logoSlant}deg);` : '') }
}

export function createBrandMeasurer() {
  return (name, fontSize) => brandTitleLayout(null, name, fontSize)
}

export function drawBrandLogo(context, image, title, x, y) {
  if (!title.logoShear) {
    context.drawImage(image, x, y + title.logoTop, title.logoWidth, title.logoHeight)
    return
  }
  context.save()
  try {
    context.transform(1, 0, -title.logoShear, 1,
      x + title.logoHeight * title.logoShear, y + title.logoTop)
    context.drawImage(image, 0, 0, title.logoWidth, title.logoHeight)
  } finally {
    context.restore()
  }
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
