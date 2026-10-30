import assert from 'node:assert/strict'
import test from 'node:test'
import catalog from '../../../Sources/LeaderboardKit/Resources/SourceTabThemes.json' with { type: 'json' }
import { categories, boardVariants } from '../src/core/catalog.js'
import { sourceTabTheme } from '../src/core/source-tab-theme.js'

const luminance = hex => {
  const channels = hex.slice(1).match(/../g).map(value => parseInt(value, 16) / 255)
    .map(value => value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4)
  return channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722
}

test('source themes cover enabled boards exactly once and retain readable light and dark pairs', () => {
  const kinds = catalog.sources.flatMap(source => source.kinds)
  assert.equal(kinds.length, new Set(kinds).size)
  assert.deepEqual([...kinds].sort(), categories.flatMap(category => category.kinds).flatMap(kind => boardVariants[kind] || [kind]).sort())
  for (const source of [...catalog.sources, catalog.fallback]) {
    for (const mode of ['light', 'dark']) {
      const palette = source[mode]
      for (const hex of Object.values(palette)) assert.match(hex, /^#[0-9A-F]{6}$/)
      const bg = luminance(palette.background), fg = luminance(palette.foreground)
      assert.ok((Math.max(bg, fg) + 0.05) / (Math.min(bg, fg) + 0.05) >= 4.5)
      // Header/time text sits on the card rather than on the selected tab fill.
      for (const surface of mode === 'dark' ? ['#101216', '#29292B'] : ['#FFFFFF', '#F4F5F7']) {
        const a = luminance(palette.accent), b = luminance(surface)
        assert.ok((Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05) >= 4.5,
          `${source.id || 'fallback'} ${mode}: unreadable source text on ${surface}`)
      }
      for (const kind of source.kinds || ['unknown-source']) {
        assert.deepEqual(sourceTabTheme(kind, mode === 'dark'), palette)
      }
    }
  }
})
