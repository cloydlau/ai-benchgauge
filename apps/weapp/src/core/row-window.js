// Same approach as Watrek's stream-layout: a stable total height, absolute
// global offsets, buffered windows and an edge threshold to avoid bridge churn.
const overscan = 11
const edge = 6
const positive = (value, fallback) => Number.isFinite(Number(value)) && Number(value) > 0 ? Number(value) : fallback

export function rowGeometry(info = {}) {
  return { rowHeight: Math.max(48, 96 * positive(info.windowWidth, 375) / 750),
    viewportHeight: positive(info.windowHeight, 667) }
}

export function resolveRowWindow({ count, scrollTop = 0, origin = 0, geometry, start = 0, end = 0, force = false }) {
  if (count <= 0) return { start: 0, end: 0 }
  const capacity = Math.min(count, Math.max(20, Math.ceil(geometry.viewportHeight / geometry.rowHeight) + 1 + overscan * 2))
  const offset = Math.max(0, (Number(scrollTop) || 0) - (Number(origin) || 0))
  const first = Math.min(count - 1, Math.floor(offset / geometry.rowHeight))
  const last = Math.min(count - 1, Math.floor((offset + geometry.viewportHeight) / geometry.rowHeight))
  const valid = start >= 0 && end <= count && end - start === capacity
  if (!force && valid && first >= start && last < end
    && (start === 0 || first - start >= edge) && (end === count || end - last - 1 >= edge)) return { start, end }
  const nextEnd = Math.min(count, Math.max(0, first - overscan) + capacity)
  return { start: Math.max(0, nextEnd - capacity), end: nextEnd }
}

export function createRowRenderer(mapRow) {
  let previous
  return ({ entries, start, end, rowHeight, variant }) => {
    const reuse = previous && previous.entries === entries && previous.rowHeight === rowHeight && previous.variant === variant
    if (reuse && previous.start === start && previous.end === end) return previous.rows
    const rows = Array.from({ length: end - start }, (_, offset) => {
      const index = start + offset
      return reuse && previous.rows[index - previous.start]
        || { ...mapRow(entries[index], entries), top: index * rowHeight }
    })
    previous = { entries, start, end, rowHeight, variant, rows }
    return rows
  }
}
