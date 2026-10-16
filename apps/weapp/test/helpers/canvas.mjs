export function canvasHarness() {
  const commands = [], files = new Set(), contents = new Map(), exported = [], saved = []
  const context = { measureText: value => ({ width: [...value].length * 7 }) }
  for (const name of ['beginPath', 'moveTo', 'lineTo', 'quadraticCurveTo', 'bezierCurveTo', 'closePath', 'fill', 'stroke', 'fillRect', 'fillText', 'drawImage', 'scale', 'translate', 'save', 'transform', 'restore']) {
    context[name] = (...args) => commands.push([name, ...args])
  }
  const canvas = { width: 1, height: 1, getContext: () => context, createImage: () => ({
    set src(path) { queueMicrotask(() => path.includes('missing') ? this.onerror() : this.onload()) },
  }) }
  context.getImageData = (x, y, width, height) => {
    exported.push({ width: canvas.width, height: canvas.height })
    return { data: new Uint8ClampedArray(width * height * 4) }
  }
  const platform = { env: { USER_DATA_PATH: '/private-test' },
    getFileSystemManager: () => ({
      mkdirSync: path => files.add(path),
      readdirSync: root => [...files].filter(path => path.startsWith(root + '/')).map(path => path.slice(root.length + 1)),
      writeFileSync: (path, data, encoding) => { files.add(path); contents.set(path, [Buffer.from(data, encoding)]) },
      unlinkSync: path => { files.delete(path); contents.delete(path) }, rmdirSync: path => files.delete(path),
    }),
    canvasToTempFilePath(options) {
      exported.push({ width: canvas.width, height: canvas.height })
      options.success({ tempFilePath: `/tmp/page-${exported.length}.png` })
    },
    saveImageToPhotosAlbum(options) { saved.push(options.filePath); options.success({}) },
  }
  return { canvas, context, platform, commands, files, contents, exported, saved }
}
