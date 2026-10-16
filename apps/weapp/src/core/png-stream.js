import { Zlib } from 'fflate'

const crcTable = Uint32Array.from({ length: 256 }, (_, value) => {
  for (let bit = 0; bit < 8; bit++) value = value & 1 ? 0xedb88320 ^ (value >>> 1) : value >>> 1
  return value >>> 0
})
function uint32(bytes, offset, value) { new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength).setUint32(offset, value) }
function chunk(type, data = new Uint8Array()) {
  const bytes = new Uint8Array(data.length + 12)
  uint32(bytes, 0, data.length)
  for (let index = 0; index < 4; index++) bytes[index + 4] = type.charCodeAt(index)
  bytes.set(data, 8)
  let crc = 0xffffffff
  for (let index = 4; index < bytes.length - 4; index++) crc = crcTable[(crc ^ bytes[index]) & 255] ^ (crc >>> 8)
  uint32(bytes, bytes.length - 4, (crc ^ 0xffffffff) >>> 0)
  return bytes
}

// Encode one PNG a strip at a time. The canvas and raw pixels stay bounded
// even when the full comparison is taller than a device's canvas limit.
export function createPNGStream(width, height, write) {
  if (![width, height].every(value => Number.isInteger(value) && value > 0 && value <= 0x7fffffff)) throw new Error('Invalid PNG dimensions')
  write(new Uint8Array([137, 80, 78, 71, 13, 10, 26, 10]))
  const header = new Uint8Array(13)
  uint32(header, 0, width); uint32(header, 4, height)
  header[8] = 8; header[9] = 6
  write(chunk('IHDR', header))
  let rows = 0, finished = false
  const compressor = new Zlib({ level: 3 }, (data, final) => {
    if (data.length) write(chunk('IDAT', data))
    if (final) write(chunk('IEND'))
  })
  return {
    push(pixels) {
      const stride = width * 4, count = pixels.length / stride
      if (finished || !Number.isInteger(count) || rows + count > height) throw new Error('Invalid PNG strip')
      for (let start = 0; start < count; start += 64) {
        const lines = Math.min(64, count - start), filtered = new Uint8Array(lines * (stride + 1))
        for (let line = 0; line < lines; line++) {
          const source = (start + line) * stride, target = line * (stride + 1)
          filtered[target] = 1 // PNG Sub filter keeps flat fills and text compact.
          for (let byte = 0; byte < stride; byte++) filtered[target + byte + 1] = pixels[source + byte] - (byte >= 4 ? pixels[source + byte - 4] : 0)
        }
        compressor.push(filtered)
      }
      rows += count
    },
    finish() {
      if (finished || rows !== height) throw new Error('Incomplete PNG image')
      finished = true
      compressor.push(new Uint8Array(), true)
    },
  }
}
