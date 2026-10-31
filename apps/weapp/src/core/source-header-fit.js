// Measurements are taken at the original font sizes; growing the window can
// restore those sizes, but must never enlarge them.
export function fitSourceHeader({ width, headingWidth, variantWidth = 0, chromeWidth = 0 }) {
  if (![width, headingWidth, variantWidth, chromeWidth].every(Number.isFinite)
    || width <= 0 || headingWidth <= 0 || variantWidth < 0 || chromeWidth < 0) return { headingScale: 1, variantScale: 1 }
  const available = Math.max(0, width - chromeWidth - 2)
  const down = value => Math.max(0.001, Math.floor(Math.min(1, Math.max(0, value)) * 1000) / 1000)
  if (!variantWidth) return { headingScale: down(available / headingWidth), variantScale: 1 }
  const variantScale = (available - headingWidth) / variantWidth
  if (variantScale >= 0.8) return { headingScale: 1, variantScale: down(variantScale) }
  // Share the reduction once the task would lose more than 20% of its size,
  // rather than making the task unreadably small while leaving the source at full size.
  const scale = down(available / (headingWidth + variantWidth))
  return { headingScale: scale, variantScale: scale }
}
