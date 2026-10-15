export const brandLogoAspect = 142 / 166
export const brandLogoSource = dark => `/assets/header-logo${dark ? '-dark' : ''}.png`
const finite = (value, fallback) => Number.isFinite(value) ? value : fallback

// One geometry for native text elements and Canvas exports. The logo occupies
// A's place, takes I's painted height, and participates in visible-edge gaps.
export function brandTitleLayout(context, name, fontSize) {
  if (context) context.font = `700 ${fontSize}px sans-serif`
  const parts = name === 'AI BenchGauge' ? ['I', 'BenchGauge'] : ['I', '天', '梯']
  const measured = parts.map(value => {
    const metrics = context?.measureText(value) || {}
    const left = -finite(metrics.actualBoundingBoxLeft, 0)
    const right = finite(metrics.actualBoundingBoxRight, finite(metrics.width, [...value].length * fontSize * 0.8))
    const ascent = finite(metrics.actualBoundingBoxAscent, fontSize * 0.72)
    const descent = finite(metrics.actualBoundingBoxDescent, value === 'I' ? 0 : fontSize * 0.12)
    const fontAscent = finite(metrics.fontBoundingBoxAscent, fontSize * 0.9)
    const fontDescent = finite(metrics.fontBoundingBoxDescent, fontSize * 0.25)
    return { value, left, width: Math.max(1, right - left), ascent, height: ascent + descent,
      lineBaseline: fontAscent + (fontSize - fontAscent - fontDescent) / 2 }
  })
  const logoHeight = measured[0].height, logoWidth = logoHeight * brandLogoAspect
  const height = Math.max(logoHeight, ...measured.map(part => part.height))
  const gap = fontSize / 6
  let x = logoWidth
  const glyphs = measured.map((part, index) => {
    x += index === 1 && name === 'AI BenchGauge' ? fontSize * 0.34 : gap
    const baseline = (height - part.height) / 2 + part.ascent
    const result = { text: part.value, x, width: part.width, baseline,
      style: `left:${x - part.left}px;top:${baseline - part.lineBaseline}px;line-height:${fontSize}px;` }
    x += part.width
    return result
  })
  return { width: x, height, logoWidth, logoHeight, glyphs,
    style: `width:${x}px;height:${height}px;font-size:${fontSize}px;`,
    logoStyle: `width:${logoWidth}px;height:${logoHeight}px;top:${(height - logoHeight) / 2}px;` }
}

export function createBrandMeasurer(platform) {
  let context
  try { context = platform.createOffscreenCanvas?.({ type: '2d', width: 1, height: 1 }).getContext('2d') } catch { /* Older renderers retain a proportional fallback. */ }
  return (name, fontSize) => brandTitleLayout(context, name, fontSize)
}
