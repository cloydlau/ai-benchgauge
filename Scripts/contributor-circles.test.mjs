import assert from 'node:assert/strict'
import test from 'node:test'
import { fileURLToPath } from 'node:url'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
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

test('configured contributor avatars remain available for both mobile clients', () => {
  const root = fileURLToPath(new URL('..', import.meta.url))
  const { identity } = JSON.parse(readFileSync(resolve(root, 'calmmit.config.json'), 'utf8'))
  for (const file of Object.values(identity.avatarFiles)) {
    const data = readFileSync(resolve(root, identity.avatarDirectory, file))
    assert.deepEqual(data.subarray(0, 8), Buffer.from('89504e470d0a1a0a', 'hex'), file)
  }
  const nodes = contributorCircles(root).nodes
  for (const [prefix, file] of [['gpt-', 'openai.png'], ['grok-', 'spacexai.png'], ['qwen', 'qwen.png'], ['glm-', 'zai.png'], ['deepseek-', 'deepseek.png'], ['kimi-', 'kimi.png']]) {
    for (const node of nodes.filter(node => node.name.startsWith(prefix)))
      assert.equal(node.avatar, `assets/logos/${file}`, node.name)
  }
})
