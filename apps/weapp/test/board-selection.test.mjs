import assert from 'node:assert/strict'
import test from 'node:test'
import { categories } from '../src/core/catalog.js'
import { visibleBoardKinds, normalizeBoardSelections, toggleBoardSelection, selectedBoardFace } from '../src/core/board-selection.js'

test('visibility uses catalog order, repairs obsolete selections and never empties a category', () => {
  for (const category of categories) {
    for (const saved of [undefined, null, {}, [], { [category.id]: [] }, { [category.id]: ['retired'] }, { [category.id]: 'bad' }]) {
      assert.deepEqual(visibleBoardKinds(category.id, saved), category.defaultKinds || category.kinds)
    }
    const selected = category.kinds.at(-1)
    const value = { [category.id]: [selected, 'retired', selected] }
    assert.deepEqual(normalizeBoardSelections(value), category.kinds.length === 1 ? {} : { [category.id]: [selected] })
    assert.deepEqual(toggleBoardSelection(category.id, selected, value), value)
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


test('archived Vals is hidden by default and remains explicitly selectable and shareable', () => {
  assert.deepEqual(visibleBoardKinds('coding'), ['artificialAnalysisCodingAgent', 'codeArenaWebDev'])
  const enabled = toggleBoardSelection('coding', 'valsSWEbench')
  assert.deepEqual(visibleBoardKinds('coding', enabled), ['artificialAnalysisCodingAgent', 'codeArenaWebDev', 'valsSWEbench'])
  assert.deepEqual(normalizeBoardSelections(enabled), enabled)
  assert.deepEqual(visibleBoardKinds('coding', toggleBoardSelection('coding', 'valsSWEbench', enabled)), ['artificialAnalysisCodingAgent', 'codeArenaWebDev'])
})
