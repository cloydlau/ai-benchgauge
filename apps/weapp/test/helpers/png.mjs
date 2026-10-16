import assert from 'node:assert/strict'
import { crc32, inflateSync } from 'node:zlib'

// Decode with Node's independent native zlib and verify every PNG chunk CRC.
export function decodePNG(bytes) {
  assert.deepEqual([...bytes.subarray(0, 8)], [137, 80, 78, 71, 13, 10, 26, 10])
  let width, height, ended = false
  const data = []
  for (let offset = 8; offset < bytes.length;) {
    const length = bytes.readUInt32BE(offset), type = bytes.toString('ascii', offset + 4, offset + 8)
    assert.equal(crc32(bytes.subarray(offset + 4, offset + 8 + length)), bytes.readUInt32BE(offset + 8 + length))
    const body = bytes.subarray(offset + 8, offset + 8 + length)
    if (type === 'IHDR') {
      width = body.readUInt32BE(0); height = body.readUInt32BE(4)
      assert.deepEqual([...body.subarray(8)], [8, 6, 0, 0, 0])
    } else if (type === 'IDAT') data.push(body)
    else if (type === 'IEND') ended = true
    offset += length + 12
  }
  assert.ok(ended)
  const raw = inflateSync(Buffer.concat(data)), stride = width * 4, pixels = Buffer.alloc(stride * height)
  assert.equal(raw.length, height * (stride + 1))
  for (let row = 0; row < height; row++) {
    const offset = row * (stride + 1), target = row * stride
    assert.equal(raw[offset], 1)
    for (let byte = 0; byte < stride; byte++) pixels[target + byte] = raw[offset + byte + 1] + (byte < 4 ? 0 : pixels[target + byte - 4])
  }
  return { width, height, pixels }
}
