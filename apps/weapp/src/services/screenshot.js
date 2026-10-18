import { brandLogoSource } from '../core/brand-title.js'
import { planScreenshot, drawScreenshot, screenshotWidth, screenshotStripHeight } from '../core/screenshot.js'
import { createPNGStream } from '../core/png-stream.js'

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
      } else if (!/^\/assets\/(?:(?:logos|openness|flags)\/)?[a-zA-Z0-9_-]+\.png$/.test(source)) return
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

export async function exportScreenshot({ platform, canvas, model, isActive = () => true, progress = () => {} }) {
  const image = planScreenshot(canvas.getContext('2d'), model), fs = platform.getFileSystemManager()
  const path = `${platform.env.USER_DATA_PATH}/benchgauge-screenshot-${Date.now()}-${Math.random().toString(36).slice(2)}.png`
  let assets, complete = false
  try {
    if (!isActive()) throw new Error('Screenshot cancelled')
    // Force-quitting need not deliver onUnload. Reclaim only our old exports.
    try {
      for (const name of fs.readdirSync(platform.env.USER_DATA_PATH)) {
        if (name.startsWith('benchgauge-screenshot-') && name.endsWith('.png')) removeScreenshot(platform, `${platform.env.USER_DATA_PATH}/${name}`)
      }
    } catch { /* Cleanup availability must not prevent a new export. */ }
    assets = await loadImages(platform, canvas, [brandLogoSource(model.dark), ...model.boards.flatMap(board => board.rows.flatMap(row => [row.logo, row.opennessIcon, row.flagImage]))])
    const chunks = []
    let byteLength = 0
    const png = createPNGStream(screenshotWidth, image.height, bytes => { chunks.push(bytes); byteLength += bytes.length })
    for (let offset = 0; offset < image.height; offset += screenshotStripHeight) {
      if (!isActive()) throw new Error('Screenshot cancelled')
      const height = Math.min(screenshotStripHeight, image.height - offset)
      canvas.width = screenshotWidth; canvas.height = height
      const context = canvas.getContext('2d')
      context.translate(0, -offset)
      drawScreenshot(context, model, image, assets.images, { offset, height })
      png.push(context.getImageData(0, 0, screenshotWidth, height).data)
      progress(Math.round((offset + height) / image.height * 100))
      await new Promise(resolve => setTimeout(resolve, 0))
    }
    if (!isActive()) throw new Error('Screenshot cancelled')
    png.finish()
    // Keep only compressed chunks, then write the final file once. Raw pixel
    // memory remains bounded by one strip throughout rendering.
    const output = new Uint8Array(byteLength)
    let position = 0
    for (const bytes of chunks) { output.set(bytes, position); position += bytes.length }
    fs.writeFileSync(path, output.buffer)
    complete = true
    return path
  } finally {
    assets?.cleanup(); canvas.width = 1; canvas.height = 1
    if (!complete) removeScreenshot(platform, path)
  }
}

export function removeScreenshot(platform, path) {
  if (!path || !platform.env?.USER_DATA_PATH || !path.startsWith(`${platform.env.USER_DATA_PATH}/benchgauge-screenshot-`)) return
  try { platform.getFileSystemManager().unlinkSync(path) } catch { /* Already removed or reclaimed by the OS. */ }
}
export const saveScreenshotImage = (platform, filePath) => invoke(platform, 'saveImageToPhotosAlbum', { filePath })
