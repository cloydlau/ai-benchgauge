import test from 'node:test'
import assert from 'node:assert/strict'
import { categories, boardVariants, variantLabels, normalizeVariants, boards } from '../src/core/catalog.js'
import { sourceTabTheme, sourceTabLogo } from '../src/core/source-tab-theme.js'
import { rowView } from '../src/core/leaderboard.js'

test('Epoch domain boards use specialist and coding categories and keep their source identity', () => {
  assert.deepEqual(categories.find(c => c.id === 'speech').kinds, ['artificialAnalysisSpeechProviderVoice', 'epochMathECI', 'epochCyberECI'])
  assert.ok(categories.find(c => c.id === 'coding').kinds.includes('epochSoftwareECI'))
  assert.equal(boardVariants.epochECI, undefined)
  assert.deepEqual(normalizeVariants({ epochECI: 'epochMathECI' }), {})
  for (const kind of ['epochMathECI', 'epochCyberECI', 'epochSoftwareECI']) {
    assert.equal(boards[kind].title, 'Epoch ECI')
    assert.deepEqual(sourceTabTheme(kind, false), sourceTabTheme('epochECI', false))
    assert.equal(sourceTabLogo(kind, false), sourceTabLogo('epochECI', false))
    assert.equal(rowView({ rank: 1, name: 'Fixture', score: 153.42 }, { kind, leaderScore: 153.42 }).scoreText, '153.42')
  }
})
