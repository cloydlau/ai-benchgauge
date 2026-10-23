import { epochAttribution } from './epoch-attribution.js'
import { arenaAttribution, isArenaDatasetBoard } from './arena-attribution.js'
import { brandTitleLayout, brandLogoSource, drawBrandGlyphs, drawBrandLogo } from './brand-title.js'
// Canvas presentation only: ranking, filtering, brands and dates come from the
// same view model as the screen. Export every row, independently of its window.
export const screenshotWidth = 1000
export const screenshotStripHeight = 1024
const top = 238, bottom = 54, margin = 24, gap = 20
const boardWidth = count => (screenshotWidth - margin * 2 - gap * (count - 1)) / Math.max(1, count)
const sourceColumnWidth = 47

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

export function planScreenshot(context, model) {
  context.font = '14px sans-serif'
  const columnWidth = boardWidth(model.boards.length)
  const nameWidth = columnWidth - 237 + (model.grouping === 'company' ? sourceColumnWidth : 0)
  const boards = model.boards.map(board => ({ ...board,
    rows: board.rows.map(row => ({ ...row, lines: wrapText(context, row.name, nameWidth) })) }))
  const count = Math.max(...boards.map(board => board.rows.length), 0)
  const rows = []; let height = top
  for (let index = 0; index < count; index++) {
    const pair = boards.map(board => board.rows[index] || null)
    const rowHeight = Math.max(46, ...pair.map(row => row ? row.lines.length * 18 + 14 : 0))
    rows.push({ pair, height: rowHeight, y: height }); height += rowHeight
  }
  context.font = '11px sans-serif'
  const notices = [boards.some(board => board.kind === 'epochECI') ? epochAttribution(model.language).fullText : '',
    ...boards.filter(board => ['openRouterUsage', 'vercelUsage'].includes(board.kind)).map(board => board.sourceNote || ''),
    boards.some(isArenaDatasetBoard) ? arenaAttribution(model.language).fullText : ''].filter(Boolean)
  const attributionLines = notices.flatMap(notice => wrapText(context, notice, screenshotWidth - margin * 2))
  const footerHeight = bottom + (attributionLines.length ? attributionLines.length * 16 + 12 : 0)
  return { rows, boards, attributionLines, footerHeight, height: Math.max(height + bottom, top + 120) + footerHeight - bottom }
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
function text(context, value, x, y, size, color, { bold = false, align = 'left', numeric = false } = {}) {
  context.font = `${bold ? '600 ' : ''}${size}px ${numeric ? 'monospace' : 'sans-serif'}`
  context.fillStyle = color; context.textAlign = align; context.textBaseline = 'middle'
  context.fillText(String(value), x, y)
}

export function drawScreenshot(context, model, image, images, { offset = 0, height: stripHeight = image.height } = {}) {
  const columnWidth = boardWidth(image.boards.length)
  const showSource = model.grouping !== 'company'
  const extraNameWidth = showSource ? 0 : sourceColumnWidth
  const colors = model.dark
    ? { background: '#101216', card: '#1b1f26', ink: '#f2f5fa', muted: '#a2acba', line: '#343b46', blue: '#67b1ff', purple: '#cd91f7', open: '#77d9a1' }
    : { background: '#f4f5f7', card: '#ffffff', ink: '#20262f', muted: '#687382', line: '#dfe3e9', blue: '#1675dc', purple: '#9657c8', open: '#188966' }
  context.fillStyle = colors.background; context.fillRect(0, 0, screenshotWidth, image.height)
  const title = brandTitleLayout(context, model.labels.name, 23)
  const titleY = 40 - title.height / 2
  const headerLogo = images.get(brandLogoSource(model.dark))
  if (headerLogo) drawBrandLogo(context, headerLogo, title, margin, titleY)
  drawBrandGlyphs(context, title, margin, titleY, { dark: model.dark })
  const subtitle = model.labels.subtitle.split(' & '), captionX = margin + title.width + 6
  if (model.labels.name === 'AI BenchGauge') {
    text(context, subtitle[0] + ' &', captionX, 40 - title.height * 0.375, title.height * 0.5, colors.muted)
    text(context, subtitle[1] + ' ?', captionX, 40 + title.height * 0.375, title.height * 0.5, colors.muted)
  } else {
    text(context, model.labels.subtitle + ' ?', captionX, titleY + title.height / 2, 12, colors.muted)
  }
  text(context, `${model.groupingLabel} · ${model.categoryLabel}`, screenshotWidth - margin, 40, 15, colors.muted, { align: 'right' })
  image.boards.forEach((board, column) => {
    const x = margin + column * (columnWidth + gap), accent = board.kind === 'openRouterUsage' ? (model.dark ? '#ffb45c' : '#a76514') : board.kind === 'vercelUsage' ? colors.muted : column ? colors.purple : colors.blue
    rounded(context, x, 80, columnWidth, image.height - 80 - image.footerHeight, 12, colors.card)
    text(context, board.tab, x + 16, 104, 16, accent, { bold: true })
    text(context, board.time, x + columnWidth - 16, 132, 11, board.isSourceTime ? accent : colors.muted,
      { bold: board.isSourceTime, align: 'right', numeric: true })
    context.font = '13px sans-serif'
    wrapText(context, board.summary, columnWidth - 220).forEach((line, index) => text(context, line, x + 16, 132 + index * 17, 13, colors.muted))
    text(context, board.filterLabel, x + 16, 179, 12, colors.muted)
    const countryX = x + columnWidth - 122 + extraNameWidth, sourceX = x + columnWidth - 75, scoreX = x + columnWidth - 14
    text(context, model.labels.rank, x + 24, 213, 12, colors.muted, { align: 'center' })
    text(context, board.title, x + 49, 213, 13, accent, { bold: true })
    text(context, model.labels.country, countryX, 213, 11, colors.muted, { align: 'center' })
    if (showSource) text(context, model.labels.source, sourceX, 213, 11, colors.muted, { align: 'center' })
    text(context, board.kind === 'vercelUsage' ? (model.language === 'en' ? 'Share' : model.language === 'zh-TW' ? '佔比' : '占比') : board.kind === 'openRouterUsage' ? (model.language === 'en' ? 'Tokens' : '用量') : model.labels.score, scoreX, 213, 12, colors.muted, { align: 'right' })
    context.strokeStyle = colors.line; context.lineWidth = 1; context.beginPath()
    context.moveTo(x + 12, 232); context.lineTo(x + columnWidth - 12, 232); context.stroke()
    if (!board.rows.length) text(context, board.empty, x + columnWidth / 2, top + 48, 14, colors.muted, { align: 'center' })
    image.rows.forEach(({ pair, height, y }) => {
      if (y + height <= offset || y >= offset + stripHeight) return
      const row = pair[column]; if (!row) return
      const center = y + height / 2
      if (row.rank % 2 === 0) rounded(context, x + 8, y, columnWidth - 16, height, 6, model.dark ? '#242a33' : '#f8f9fb')
      text(context, row.rank, x + 24, center, 14, colors.muted, { align: 'center', numeric: true })
      const nameX = x + 48
      const fillWidth = (columnWidth - 48 - 8) * row.fillPercent / 100
      if (fillWidth > 0) rounded(context, nameX, y + 4, fillWidth, height - 8, Math.min(5, fillWidth / 2), row.fill.match(/rgba\([^)]*\)/)?.[0] || colors.background)
      const logo = images.get(row.logo)
      if (logo) context.drawImage(logo, nameX + 7, center - 12, 24, 24)
      else {
        rounded(context, nameX + 7, center - 12, 24, 24, 5, '#ffffff')
        text(context, row.initial, nameX + 19, center, 12, '#506070', { bold: true, align: 'center' })
      }
      row.lines.forEach((line, index) => text(context, line, nameX + 39, center + (index - (row.lines.length - 1) / 2) * 18, 14, colors.ink))
      // Canvas fonts on phones may lack regional-indicator emoji. Raster flags
      // render consistently; a failed asset still leaves readable attribution.
      const flag = images.get(row.flagImage)
      if (flag) {
        rounded(context, countryX - 13, center - 10, 26, 20, 1, colors.line)
        context.drawImage(flag, countryX - 12, center - 9, 24, 18)
      } else text(context, row.countryUnknown ? '?' : row.countryCode, countryX, center, 12, colors.ink, { align: 'center' })
      if (showSource) {
        const statusIcon = images.get(row.opennessIcon)
        if (statusIcon) context.drawImage(statusIcon, sourceX - 7, center - 7, 14, 14)
        else text(context, row.openness === 'open' ? model.labels.open : row.openness === 'closed' ? model.labels.closed : '—', sourceX, center, 10, colors.muted, { align: 'center' })
      }
      text(context, row.scoreText, scoreX, center, 14, colors.muted, { align: 'right', numeric: true })
      if (row.scoreShare) {
        text(context, row.scoreShare, scoreX, center + 12, 9, accent, { align: 'right', numeric: true })
      }
    })
  })
  text(context, model.labels.name, margin, image.height - image.footerHeight + 28, 12, colors.muted)
  image.attributionLines.forEach((line, index) =>
    text(context, line, margin, image.height - image.footerHeight + bottom + 4 + index * 16, 11, colors.muted))
}
