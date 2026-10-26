import { brandGlyphs } from './brand-glyphs.js'

import { brandBaseSize, brandLayouts } from './brand-layouts.js'
export { brandLogoAspect } from './brand-layouts.js'
export const brandLogoSource = dark => `/assets/header-logo${dark ? '-dark' : ''}.png`

// Both mobile clients consume the same precomputed geometry and offline paths.
export function brandTitleLayout(_context, name, fontSize) {
  const layout = brandLayouts[name === 'AI BenchGauge' ? 'english' : 'chinese']
  const scale = fontSize / brandBaseSize
  const title = Object.fromEntries(Object.entries(layout).filter(([, value]) => typeof value === 'number')
    .map(([key, value]) => [key, ['logoShear', 'logoSlant'].includes(key) ? value : value * scale]))
  const glyphs = layout.glyphs.map(part => {
    const { key } = part, { text } = brandGlyphs[key]
    const x = part.x * scale, y = part.y * scale, width = part.width * scale, height = part.height * scale
    return { key, text, x, y, width, height, source: `/assets/brand-glyphs/${key}`,
      style: `left:${x}px;top:${y}px;width:${width}px;height:${height}px;` }
  })
  return { ...title, scale, glyphs, style: `width:${title.width}px;height:${title.height}px;`,
    logoStyle: `width:${title.logoWidth}px;height:${title.logoHeight}px;top:${title.logoTop}px;`
      + (title.logoSlant ? `transform-origin:left bottom;transform:skewX(-${title.logoSlant}deg);` : '') }
}

export function createBrandMeasurer() {
  return (name, fontSize) => brandTitleLayout(null, name, fontSize)
}

export function createSubtitleMeasurer(platform) {
  let context
  try { context = platform.createOffscreenCanvas({ type: '2d', width: 1, height: 1 }).getContext('2d') } catch {}
  if (context) context.font = '500 12px sans-serif'
  const widths = new Map()
  return rows => Math.max(1, ...rows.map(row => {
    if (!widths.has(row)) {
      const measured = context?.measureText(row).width
      // Older renderers can lack an offscreen 2D context. Use conservative
      // glyph widths when unavailable, never a zero-width caption.
      const fallback = [...row].reduce((width, glyph) => width + (/[^\x00-\x7F]/.test(glyph) ? 12 : 7.2), 0)
      widths.set(row, measured > 0 && Number.isFinite(measured) ? measured : fallback)
    }
    return widths.get(row)
  }))
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

export function drawBrandGlyphs(context, title, x, y, { dark = false } = {}) {
  const methods = { M: 'moveTo', L: 'lineTo', Q: 'quadraticCurveTo', C: 'bezierCurveTo', Z: 'closePath' }
  // Match the native wordmark's neutral silver reflection bands in both themes.
  const colors = dark ? ['#F5F7FA', '#A5AFBC', '#E0E6EE', '#8D99A8'] : ['#303945', '#8894A2', '#414D5C', '#6C7888']
  const offsets = [0, 0.42, 0.5, 1]
  const gradient = context.createLinearGradient(0, y, 0, y + title.height)
  offsets.forEach((offset, index) => gradient.addColorStop(offset, colors[index]))
  context.fillStyle = gradient
  for (const glyph of title.glyphs) {
    context.beginPath()
    for (const [command, ...points] of brandGlyphs[glyph.key].commands) {
      context[methods[command]](...points.map((value, index) => value * title.scale + (index % 2 ? y + glyph.y : x + glyph.x)))
    }
    context.fill()
  }
}
