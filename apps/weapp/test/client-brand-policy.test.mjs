import assert from 'node:assert/strict'
import test from 'node:test'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { clientBrandPolicyPlugin } from '../scripts/client-brand-policy.mjs'
import { createBrandRules } from '../../../fc/domain.mjs'

test('mini-program keeps shared identities while excluding server artwork from its bundle', () => {
  const root = fileURLToPath(new URL('../../..', import.meta.url))
  const path = fileURLToPath(new URL('../../../fc/brand-catalog.json', import.meta.url))
  const source = readFileSync(path, 'utf8'), original = JSON.parse(source)
  const plugin = clientBrandPolicyPlugin(root)
  const transformed = plugin.transform(source, path)
  const policy = JSON.parse(transformed.code)
  for (const key of ['aliases', 'families', 'modelDevelopers', 'colors', 'bundledModelMarks'])
    assert.deepEqual(policy[key], original[key], key)
  assert.deepEqual(policy.modelLogos, [])
  assert.deepEqual(policy.providerLogos, {})
  assert.doesNotMatch(transformed.code, /pngData|sourceURL/)
  assert.ok(original.modelLogos.some(item => item.pngData))
  assert.ok(Object.values(original.providerLogos).some(item => item.pngData))
  const shared = createBrandRules(original), client = createBrandRules(policy)
  for (const organization of Object.keys(original.colors)) {
    const entry = { organization, name: 'Model' }
    assert.equal(client.brandKey(entry), shared.brandKey(entry))
  }
  for (const entry of [{ organization: 'Anthropic', name: 'Claude Code - Qwen3.8 Max' },
    { organization: null, name: 'Devin Fusion CLI - Claude Opus + GPT' },
    { organization: null, name: 'trinity-large-thinking' }])
    assert.equal(client.brandKey(entry), shared.brandKey(entry))
  assert.equal(client.knownModelBrand({ name: 'Wan 3', organization: 'Alibaba' }), null)
  assert.deepEqual(plugin.transform(source, path + '?import'), transformed)
  assert.equal(plugin.transform(source, path + '.unrelated'), null)
})
