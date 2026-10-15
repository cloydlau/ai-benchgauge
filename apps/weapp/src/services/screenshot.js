import { brandLogoSource } from '../core/brand-title.js'
import { planScreenshots, drawScreenshot, screenshotWidth } from '../core/screenshot.js'

const invoke = (platform, name, options) => new Promise((resolve, reject) => platform[name]({ ...options, success: resolve, fail: reject }))

async function loadImages(platform, canvas, sources) {
  const images = new Map(), files = [], fs = platform.getFileSystemManager()
  const directory = `${platform.env.USER_DATA_PATH}/benchgauge-capture-${Date.now()}-${Math.random().toString(36).slice(2)}`
  fs.mkdirSync(directory)
  let index = 0
  async function load(source) {
    let path = source
    try {
      if (/^data:image\/png;base64,[A-Za-z0-9+/=]+$/.test(source)) {
        path = `${directory}/${index++}.png`; fs.writeFileSync(path, source.split(',')[1], 'base64'); files.push(path)
      } else if (!/^\/assets\/(?:(?:logos|openness)\/)?[a-zA-Z0-9_-]+\.png$/.test(source)) return
      const image = canvas.createImage()
      await new Promise((resolve, reject) => {
        const timer = setTimeout(() => reject(new Error('Logo load timed out')), 5000)
        image.onload = () => { clearTimeout(timer); resolve() }
        image.onerror = () => { clearTimeout(timer); reject(new Error('Logo unavailable')) }
        image.src = path
      })
      images.set(source, image)
    } catch { /* Unavailable images use the same initial placeholder as the screen. */ }
  }
  const queue = [...new Set(sources.filter(Boolean))]
  await Promise.all(Array.from({ length: Math.min(4, queue.length) }, async () => {
    while (queue.length) await load(queue.shift())
  }))
  return { images, cleanup() {
    for (const path of files) { try { fs.unlinkSync(path) } catch { /* Temporary cleanup must not discard an exported image. */ } }
    try { fs.rmdirSync(directory) } catch { /* OS storage cleanup can finish later. */ }
  } }
}

export async function exportScreenshots({ platform, canvas, model, isActive = () => true, progress = () => {} }) {
  const context = canvas.getContext('2d'), pages = planScreenshots(context, model)
  const assets = await loadImages(platform, canvas, [brandLogoSource(model.dark), ...model.boards.flatMap(board => board.rows.flatMap(row => [row.logo, row.opennessIcon]))])
  const paths = []
  try {
    for (const page of pages) {
      if (!isActive()) throw new Error('Screenshot cancelled')
      progress(page.index + 1, pages.length)
      // Bound both dimensions and memory; sequential pages avoid retaining
      // giant canvases for complete lists with hundreds of rows.
      canvas.width = screenshotWidth * 2; canvas.height = page.height * 2
      const context = canvas.getContext('2d'); context.scale(2, 2)
      drawScreenshot(context, model, page, assets.images)
      const result = await invoke(platform, 'canvasToTempFilePath', { canvas,
        x: 0, y: 0, width: canvas.width, height: canvas.height,
        destWidth: canvas.width, destHeight: canvas.height, fileType: 'png' })
      paths.push(result.tempFilePath)
    }
    return paths
  } finally {
    assets.cleanup(); canvas.width = 1; canvas.height = 1
  }
}

export const saveScreenshotImage = (platform, filePath) => invoke(platform, 'saveImageToPhotosAlbum', { filePath })
