export function canvasHarness() {
  const commands = [], files = new Set(), exported = [], saved = []
  const context = { measureText: value => ({ width: [...value].length * 7 }) }
  for (const name of ['beginPath', 'moveTo', 'lineTo', 'quadraticCurveTo', 'closePath', 'fill', 'stroke', 'fillRect', 'fillText', 'drawImage', 'scale']) {
    context[name] = (...args) => commands.push([name, ...args])
  }
  const canvas = { width: 1, height: 1, getContext: () => context, createImage: () => ({
    set src(path) { queueMicrotask(() => path.includes('missing') ? this.onerror() : this.onload()) },
  }) }
  const platform = { env: { USER_DATA_PATH: '/private-test' },
    getFileSystemManager: () => ({
      mkdirSync: path => files.add(path), writeFileSync: path => files.add(path),
      unlinkSync: path => files.delete(path), rmdirSync: path => files.delete(path),
    }),
    canvasToTempFilePath(options) {
      exported.push({ width: canvas.width, height: canvas.height })
      options.success({ tempFilePath: `/tmp/page-${exported.length}.png` })
    },
    saveImageToPhotosAlbum(options) { saved.push(options.filePath); options.success({}) },
  }
  return { canvas, context, platform, commands, files, exported, saved }
}
