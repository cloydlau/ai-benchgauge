import assert from 'node:assert/strict'
import test from 'node:test'
import { ccByLicense } from '../src/core/cc-by-4.0.js'
import { arenaAttribution } from '../src/core/arena-attribution.js'
import { epochAttribution } from '../src/core/epoch-attribution.js'

test('about-page license dialog uses the official CC BY 4.0 text, not the attribution notice', () => {
  const english = ccByLicense('en')
  const simplified = ccByLicense('zh-CN')
  const traditional = ccByLicense('zh-TW')
  assert.equal(english.canonicalURL, 'https://creativecommons.org/licenses/by/4.0/')
  assert.equal(simplified.text, ccByLicense('zh').text)
  assert.match(english.text, /Section 1 -- Definitions\./)
  assert.match(english.text, /Section 8 -- Interpretation\./)
  assert.match(simplified.text, /第一条 定义/)
  assert.match(simplified.text, /第八条 解释/)
  assert.match(traditional.text, /姓名標示 4\.0/)
  assert.match(traditional.text, /第1條 定義/)
  for (const license of [english, simplified, traditional]) {
    assert.equal(license.text.includes('Epoch AI'), false)
    assert.equal(license.text.includes('Arena Leaderboard Dataset'), false)
    assert.equal(license.text.includes('no Epoch AI endorsement'), false)
    assert.equal(license.text.includes('无 Epoch AI 背书'), false)
  }
  assert.notEqual(english.text, epochAttribution('en').fullText)
  assert.notEqual(english.text, arenaAttribution('en').fullText)
  assert.equal(ccByLicense('fr').text, english.text)
})
