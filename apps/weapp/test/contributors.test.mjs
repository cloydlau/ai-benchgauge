import assert from 'node:assert/strict'
import test from 'node:test'
import { contributorsContent } from '../src/core/contributors.js'

const snapshot = { nodes: [{ id: 'human', name: 'Cloyd Lau', count: 1234, avatar: '', initial: 'C', monochrome: false,
  url: 'https://github.com/owner/repo/commit/abc', x: 0.5, y: 0.5, r: 0.2 },
{ id: 'model', name: 'gpt-6-sol', count: 2, avatar: 'assets/logos/openai.png', initial: '', monochrome: true, url: '', x: 0.2, y: 0.2, r: 0.1 }] }

test('localized clients retain Calmmit geometry, monograms and offline avatar paths', () => {
  for (const language of ['en', 'zh-CN', 'zh-TW']) {
    const content = contributorsContent(snapshot, language)
    assert.equal(content.title, { en: 'Contributors', 'zh-CN': '贡献者', 'zh-TW': '貢獻者' }[language])
    assert.equal(content.nodes[0].initial, 'C')
    assert.equal(content.nodes[0].avatar, '')
    assert.equal(content.nodes[0].countLabel, language === 'en' ? '1,234 commits' : '1,234 次提交')
    assert.equal(content.nodes[0].style, 'left:30%;top:30%;width:40%;height:40%;')
    assert.equal(content.nodes[1].avatar, '/assets/logos/openai.png')
    assert.equal(content.nodes[1].x, snapshot.nodes[1].x)
    assert.ok(content.note && content.hint && content.expandLabel && content.closeLabel)
    assert.equal(Object.hasOwn(content, 'copyLabel'), false)
  }
  assert.deepEqual(contributorsContent(null, 'en').nodes, [])
  assert.equal(snapshot.nodes[1].avatar, 'assets/logos/openai.png')
})
