import { readFileSync } from 'node:fs'
import test from 'node:test'
import assert from 'node:assert/strict'
import catalog from '../../../Sources/LeaderboardKit/Resources/LeaderboardVariantHelp.json' with { type: 'json' }
import { boardVariants, variantLabels, text } from '../src/core/catalog.js'
import { variantHelp } from '../src/core/variant-help.js'

test('every selectable option has one shared localized explanation, from any member of its family', () => {
  assert.deepEqual(Object.keys(catalog.options).sort(), Object.values(boardVariants).flat().sort())
  for (const language of ['en', 'zh-CN', 'zh-TW']) {
    for (const options of Object.values(boardVariants)) {
      for (const selected of options) {
        const help = variantHelp(selected, language)
        assert.equal(help, variantHelp(options[0], language))
        for (const option of options) {
          assert.equal(text(catalog.options[option].title, language), text(variantLabels[option], language))
          assert.ok(help.includes(text(catalog.options[option].detail, language)), option)
        }
      }
    }
    assert.equal(variantHelp('epochMathECI', language), '')
    assert.equal(variantHelp('unknown', language), '')
  }
})

test('speech explanations distinguish matched voices, live dialogue and streaming accuracy', () => {
  const help = variantHelp('artificialAnalysisSpeechControlledVoice', 'zh-CN')
  for (const phrase of ['各厂商提供', '克隆同一组参考声音', '不是情绪或语气控制能力', '实时语音交谈', '按批次', '边接收音频边返回', '不是按响应延迟排名']) assert.ok(help.includes(phrase), phrase)
  assert.ok(variantHelp('arenaMultiImageEditing', 'zh-CN').includes('不是一次生成多张结果'))
})


test('native source-detail scenarios include their comparison boards for both capture engines', () => {
  const fixture = JSON.parse(readFileSync(new URL('../../../Tests/fixtures/visual-state.json', import.meta.url), 'utf8'))
  for (const item of fixture.cases.filter(item => item.id.startsWith('source-details-variants-'))) {
    assert.ok(fixture.state.boards.some(board => board.kind === item.comparisonKind), item.id)
  }
})
