import assert from 'node:assert/strict'
import test from 'node:test'
import { fileURLToPath } from 'node:url'
import { contributorCircles, contributorCirclesSVG } from './contributor-circles.mjs'
import { iosAboutContent } from './ios-about.mjs'
import { contributorsContent } from '../apps/weapp/src/core/contributors.js'

test('business adapter calls Calmmit with shared defaults and exports identical native content', () => {
  const root = fileURLToPath(new URL('..', import.meta.url))
  const snapshot = contributorCircles(root)
  const owner = snapshot.nodes.find(node => node.name === 'Cloyd Lau')
  assert.equal(owner.initial, 'C')
  assert.equal(owner.avatar, '')
  assert.equal(snapshot.commitCount, snapshot.nodes.reduce((sum, node) => sum + node.count, 0))
  assert.ok(snapshot.nodes.some(node => node.name === 'gpt-6-sol'))
  assert.equal(snapshot.nodes.find(node => node.name === 'github-actions[bot]').avatar, 'assets/logos/github.png')
  const native = iosAboutContent({ commitCount: snapshot.commitCount, codeLineCount: 100 }, snapshot)
  for (const language of ['en', 'zh-CN', 'zh-TW']) assert.deepEqual(native.languages[language].contributors, contributorsContent(snapshot, language))
  for (const dark of [false, true]) {
    const svg = contributorCirclesSVG(root, { dark })
    assert.ok(svg.includes('>C</text>'))
    assert.ok(svg.includes('data:image/png;base64,'))
    assert.ok(svg.includes('<title>Contributors</title>'))
  }
})
