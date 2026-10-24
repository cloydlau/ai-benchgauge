# Mobile category templates

`usage.svg` (ring statistics) and `general.svg` (trophy) are original BenchGauge
glyphs, licensed under the repository root MIT license. The other three SVGs
adapt Microsoft Fluent UI System Color Icons into monochrome templates; their
MIT notice remains in `LICENSE.txt`. Per-icon provenance is in `sources.json`. Geometry for
picture/video details uses transparent cutouts or strokes so tinting cannot
turn a picture into a solid square. The SVGs are the editable sources; PNGs
are 54×54 native template exports (18 points at 3×).

iOS renders the PNG alpha as a template in the current source's accent.
The mini-program build reads the same SVGs and `SourceTabThemes.json`, rendering
one small PNG for each distinct accent. Both appearances and fallback colors
are included locally; switching sources requires no image service or CSS masks.

Regenerate native exports from the repository root (after installing `fc` dependencies):

```sh
node --input-type=module <<'JS'
import { createRequire } from 'node:module'
import { readFileSync } from 'node:fs'
const sharp = createRequire(new URL('./fc/package.json', import.meta.url))('sharp')
for (const name of ['general', 'coding', 'image', 'video', 'usage']) {
  const path = `apps/ios/UI/Resources/CategoryIcons/${name}`
  const svg = readFileSync(`${path}.svg`, 'utf8').replaceAll('currentColor', '#000000')
  await sharp(Buffer.from(svg)).resize(54, 54).png().toFile(`${path}.png`)
}
JS
```
