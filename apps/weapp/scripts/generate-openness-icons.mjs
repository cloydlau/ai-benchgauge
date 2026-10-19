import { opennessColors } from '../src/core/openness-icon.js'
import { readFileSync } from 'node:fs'
import { createRequire } from 'node:module'
import { fileURLToPath } from 'node:url'

const sharp = createRequire(new URL('../../../fc/package.json', import.meta.url))('sharp')
const directory = new URL('../assets/openness/', import.meta.url)
// Local Lucide sources and their ISC license are kept alongside the outputs.
// PNGs let WeChat image and Canvas use exactly the same paths and shapes.
for (const [state, name] of [['open', 'lock-keyhole-open'], ['closed', 'lock-keyhole']]) {
  const source = readFileSync(new URL(`${name}.svg`, directory), 'utf8')
  for (const [theme, color] of Object.entries(opennessColors[state])) {
    const svg = source.replace('currentColor', color)
    await sharp(Buffer.from(svg)).resize(96, 96).png().toFile(fileURLToPath(new URL(`${state}-${theme}.png`, directory)))
  }
}
