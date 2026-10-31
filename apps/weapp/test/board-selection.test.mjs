import assert from 'node:assert/strict'
import test from 'node:test'
import { categories } from '../src/core/catalog.js'
import { visibleBoardKinds, normalizeBoardSelections, toggleBoardSelection, selectedBoardFace, visibleCategories, selectedBoardCount } from '../src/core/board-selection.js'
import { createBoardStore } from '../src/services/boards.js'

test('visibility uses catalog order, repairs obsolete selections and allows empty categories', () => {
  for (const category of categories) {
    for (const saved of [undefined, null, {}, [], { [category.id]: ['retired'] }, { [category.id]: 'bad' }]) {
      assert.deepEqual(visibleBoardKinds(category.id, saved), category.defaultKinds || category.kinds)
    }
    const selected = category.kinds.at(-1)
    const value = { [category.id]: [selected, 'retired', selected] }
    assert.deepEqual(normalizeBoardSelections(value), category.kinds.length === 1 ? {} : { [category.id]: [selected] })
    assert.deepEqual(visibleBoardKinds(category.id, toggleBoardSelection(category.id, selected, value)), [])
    assert.deepEqual(visibleBoardKinds(category.id, { [category.id]: [] }), [])
    const next = toggleBoardSelection(category.id, category.kinds[0], value)
    assert.deepEqual(visibleBoardKinds(category.id, next), [...new Set([category.kinds[0], selected])])
    assert.deepEqual(toggleBoardSelection(category.id, 'retired', next), next)
  }
})

test('visibility changes preserve the active board identity or choose a nearby remaining board', () => {
  const selected = { general: ['epochECI'] }
  assert.equal(selectedBoardFace('general', 2, {}, selected), 0)
  assert.equal(selectedBoardFace('general', 0, selected, {}), 2)
  assert.equal(selectedBoardFace('general', 1, {}, selected), 0)
  assert.equal(selectedBoardFace('general', 2, {}, { general: ['artificialAnalysis', 'arenaText'] }), 1)
})


test('retired Vals selections fall back to supported coding sources', () => {
  assert.deepEqual(visibleBoardKinds('coding'), ['artificialAnalysisCodingAgent', 'codeArenaWebDev', 'epochSoftwareECI'])
  const enabled = toggleBoardSelection('coding', 'valsSWEbench')
  assert.deepEqual(visibleBoardKinds('coding', enabled), ['artificialAnalysisCodingAgent', 'codeArenaWebDev', 'epochSoftwareECI'])
  assert.deepEqual(normalizeBoardSelections(enabled), enabled)
  assert.deepEqual(visibleBoardKinds('coding', { coding: ['valsSWEbench'] }), ['artificialAnalysisCodingAgent', 'codeArenaWebDev', 'epochSoftwareECI'])
})

test('retired Vals cannot be fetched from the mini-program', async () => {
  let requested = false
  const store = createBoardStore({ platform: { getStorageSync: () => ({}), request: () => { requested = true } }, endpoint: 'https://example.test' })
  await assert.rejects(store.fetch('valsSWEbench'), /retired/)
  assert.equal(requested, false)
})

test('only the final board globally is protected and an all-empty saved dashboard recovers', () => {
  let selections = {}
  const keep = categories.at(-1).kinds.at(-1)
  for (const category of categories) for (const kind of visibleBoardKinds(category.id, selections)) {
    if (kind !== keep) selections = toggleBoardSelection(category.id, kind, selections)
  }
  assert.equal(selectedBoardCount(selections), 1)
  assert.deepEqual(visibleCategories(selections).map(item => item.id), [categories.at(-1).id])
  assert.equal(toggleBoardSelection(categories.at(-1).id, keep, selections), selections)
  assert.deepEqual(normalizeBoardSelections(Object.fromEntries(categories.map(item => [item.id, []]))), {})
  selections = toggleBoardSelection('general', 'epochECI', selections)
  assert.deepEqual(visibleCategories(selections).map(item => item.id), ['general', categories.at(-1).id])
})
