import assert from 'node:assert/strict'
import test from 'node:test'
import { createPNGStream } from '../src/core/png-stream.js'
import { decodePNG } from './helpers/png.mjs'

test('streamed PNG pixels survive uneven strip boundaries, compression and CRC validation', () => {
  const width = 17, height = 2033, chunks = []
  const pixels = Uint8Array.from({ length: width * height * 4 }, (_, index) => (index * 31 + Math.floor(index / 68)) & 255)
  const png = createPNGStream(width, height, bytes => chunks.push(Buffer.from(bytes)))
  let offset = 0
  for (const rows of [512, 1, 1024, 496]) {
    png.push(pixels.subarray(offset * width * 4, (offset + rows) * width * 4)); offset += rows
  }
  png.finish()
  const decoded = decodePNG(Buffer.concat(chunks))
  assert.equal(decoded.width, width); assert.equal(decoded.height, height)
  assert.deepEqual(decoded.pixels, Buffer.from(pixels))
  assert.throws(() => png.push(pixels)); assert.throws(() => png.finish())
})

test('PNG writer refuses invalid dimensions, misaligned strips and incomplete images', () => {
  for (const size of [0, -1, NaN, 1.5]) assert.throws(() => createPNGStream(size, 2, () => {}))
  const png = createPNGStream(2, 3, () => {})
  assert.throws(() => png.push(new Uint8Array(7)))
  assert.throws(() => png.push(new Uint8Array(32)))
  png.push(new Uint8Array(8)); assert.throws(() => png.finish())
})
