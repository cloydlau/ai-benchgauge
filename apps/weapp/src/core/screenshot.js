import { brandTitleLayout, brandLogoSource, drawBrandGlyphs } from './brand-title.js'
// Canvas presentation only: ranking, filtering, brands and dates come from the
// same view model as the screen. Export every row, independently of its window.
export const screenshotWidth = 1000
export const screenshotMaxHeight = 2000
const top = 238, bottom = 54, margin = 24, gap = 20
const columnWidth = (screenshotWidth - margin * 2 - gap) / 2
const nameWidth = columnWidth - 237

export function wrapText(context, value, width) {
  const lines = []; let line = ''
  for (const character of String(value ?? '')) {
    if (character === '\n') { lines.push(line); line = ''; continue }
    if (line && context.measureText(line + character).width > width) {
      const space = line.lastIndexOf(' ')
      if (space > 0) { lines.push(line.slice(0, space + 1)); line = line.slice(space + 1) }
      else { lines.push(line); line = '' }
    }
    line += character
  }
  lines.push(line)
  return lines
}

export function planScreenshots(context, model) {
  context.font = '14px sans-serif'
  const boards = model.boards.map(board => ({ ...board,
    rows: board.rows.map(row => ({ ...row, lines: wrapText(context, row.name, nameWidth) })) }))
  const count = Math.max(...boards.map(board => board.rows.length), 0)
  const pages = []; let rows = [], height = top
  for (let index = 0; index < count; index++) {
    const pair = boards.map(board => board.rows[index] || null)
    const rowHeight = Math.max(46, ...pair.map(row => row ? row.lines.length * 18 + 14 : 0))
    if (rowHeight > screenshotMaxHeight - top - bottom) throw new Error('Model name is too long to export')
    if (rows.length && height + rowHeight + bottom > screenshotMaxHeight) {
      pages.push({ rows, height: height + bottom }); rows = []; height = top
    }
    rows.push({ pair, height: rowHeight, y: height }); height += rowHeight
  }
  pages.push({ rows, height: Math.max(height + bottom, top + 120) })
  return pages.map((page, index) => ({ ...page, boards, index, count: pages.length }))
}

function rounded(context, x, y, width, height, radius, color) {
  context.fillStyle = color; context.beginPath()
  context.moveTo(x + radius, y); context.lineTo(x + width - radius, y)
  context.quadraticCurveTo(x + width, y, x + width, y + radius)
  context.lineTo(x + width, y + height - radius)
  context.quadraticCurveTo(x + width, y + height, x + width - radius, y + height)
  context.lineTo(x + radius, y + height)
  context.quadraticCurveTo(x, y + height, x, y + height - radius)
  context.lineTo(x, y + radius); context.quadraticCurveTo(x, y, x + radius, y)
  context.closePath(); context.fill()
}
function text(context, value, x, y, size, color, { bold = false, align = 'left' } = {}) {
  context.font = `${bold ? '600 ' : ''}${size}px sans-serif`
  context.fillStyle = color; context.textAlign = align; context.textBaseline = 'middle'
  context.fillText(String(value), x, y)
}

export function drawScreenshot(context, model, page, images) {
  const colors = model.dark
    ? { background: '#10151c', card: '#19212c', ink: '#edf2f7', muted: '#8b98ab', line: '#2a3544', blue: '#67b1ff', purple: '#cd91f7', open: '#77d9a1' }
    : { background: '#f5f7fa', card: '#ffffff', ink: '#17202c', muted: '#7c8797', line: '#e7ebf1', blue: '#1675dc', purple: '#9657c8', open: '#188966' }
  context.fillStyle = colors.background; context.fillRect(0, 0, screenshotWidth, page.height)
  const title = brandTitleLayout(context, model.labels.name, 27)
  const titleY = 40 - title.height / 2
  const headerLogo = images.get(brandLogoSource(model.dark))
  if (headerLogo) context.drawImage(headerLogo, margin, titleY + title.logoTop, title.logoWidth, title.logoHeight)
  context.fillStyle = colors.ink
  drawBrandGlyphs(context, title, margin, titleY)
  text(context, model.labels.subtitle, margin + title.width + 12, 49, 14, colors.muted)
  text(context, `${model.groupingLabel} · ${model.categoryLabel}`, screenshotWidth - margin, 40, 15, colors.muted, { align: 'right' })
  page.boards.forEach((board, column) => {
    const x = margin + column * (columnWidth + gap), accent = column ? colors.purple : colors.blue
    rounded(context, x, 80, columnWidth, page.height - 80 - bottom, 12, colors.card)
    text(context, board.tab, x + 16, 104, 16, accent, { bold: true })
    text(context, board.time, x + columnWidth - 16, 132, 12, colors.muted, { align: 'right' })
    context.font = '13px sans-serif'
    wrapText(context, board.summary, columnWidth - 150).forEach((line, index) => text(context, line, x + 16, 132 + index * 17, 13, colors.muted))
    text(context, board.filterLabel, x + 16, 179, 12, colors.muted)
    const countryX = x + columnWidth - 122, sourceX = x + columnWidth - 75, scoreX = x + columnWidth - 14
    text(context, model.labels.rank, x + 24, 213, 12, colors.muted, { align: 'center' })
    text(context, board.title, x + 49, 213, 13, accent, { bold: true })
    text(context, model.labels.country, countryX, 213, 11, colors.muted, { align: 'center' })
    text(context, model.labels.source, sourceX, 213, 11, colors.muted, { align: 'center' })
    text(context, model.labels.score, scoreX, 213, 12, colors.muted, { align: 'right' })
    context.strokeStyle = colors.line; context.lineWidth = 1; context.beginPath()
    context.moveTo(x + 12, 232); context.lineTo(x + columnWidth - 12, 232); context.stroke()
    if (!board.rows.length) text(context, board.empty, x + columnWidth / 2, top + 48, 14, colors.muted, { align: 'center' })
    else if (!page.rows.some(row => row.pair[column])) text(context, model.labels.leaderboardComplete, x + columnWidth / 2, top + 48, 14, colors.muted, { align: 'center' })
    page.rows.forEach(({ pair, height, y }) => {
      const row = pair[column]; if (!row) return
      const center = y + height / 2
      if (row.rank % 2 === 0) rounded(context, x + 8, y, columnWidth - 16, height, 6, model.dark ? '#1d2733' : '#f8f9fb')
      text(context, row.rank, x + 24, center, 14, colors.muted, { align: 'center' })
      const nameX = x + 48, cellWidth = columnWidth - 190
      rounded(context, nameX, y + 4, cellWidth, height - 8, 5, row.fill.match(/rgba\([^)]*\)/)?.[0] || colors.background)
      const logo = images.get(row.logo)
      if (logo) context.drawImage(logo, nameX + 7, center - 12, 24, 24)
      else {
        rounded(context, nameX + 7, center - 12, 24, 24, 5, '#ffffff')
        text(context, row.initial, nameX + 19, center, 12, '#506070', { bold: true, align: 'center' })
      }
      row.lines.forEach((line, index) => text(context, line, nameX + 39, center + (index - (row.lines.length - 1) / 2) * 18, 14, colors.ink))
      text(context, row.flag, countryX, center, 17, colors.ink, { align: 'center' })
      const statusIcon = images.get(row.opennessIcon)
      if (statusIcon) context.drawImage(statusIcon, sourceX - 7, center - 7, 14, 14)
      else text(context, row.openness === 'open' ? model.labels.open : row.openness === 'closed' ? model.labels.closed : '—', sourceX, center, 10, colors.muted, { align: 'center' })
      text(context, row.scoreText, scoreX, center, 14, colors.muted, { align: 'right' })
    })
  })
  text(context, model.labels.name, margin, page.height - 26, 12, colors.muted)
  text(context, `${page.index + 1} / ${page.count}`, screenshotWidth - margin, page.height - 26, 12, colors.muted, { align: 'right' })
}
