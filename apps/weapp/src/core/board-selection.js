import { categories, categoryFor } from './catalog.js'

// Match DesktopBoardSelection: catalog order, all visible by default, never empty.
export function visibleBoardKinds(category, selections = {}) {
  const kinds = categoryFor(category).kinds
  const saved = selections?.[category]
  const selected = Array.isArray(saved) ? kinds.filter(kind => saved.includes(kind)) : kinds
  return selected.length ? selected : kinds
}

export function normalizeBoardSelections(value) {
  return Object.fromEntries(categories.flatMap(category => {
    const kinds = visibleBoardKinds(category.id, value)
    return kinds.length === category.kinds.length ? [] : [[category.id, kinds]]
  }))
}

export function toggleBoardSelection(category, kind, selections = {}) {
  const current = visibleBoardKinds(category, selections)
  if (!categoryFor(category).kinds.includes(kind) || (current.length === 1 && current.includes(kind))) return selections
  const next = current.includes(kind) ? current.filter(item => item !== kind) : [...current, kind]
  return normalizeBoardSelections({ ...selections, [category]: next })
}

export function selectedBoardFace(category, face, previous, next) {
  const kind = visibleBoardKinds(category, previous)[face]
  const kinds = visibleBoardKinds(category, next)
  const index = kinds.indexOf(kind)
  return index >= 0 ? index : Math.max(0, Math.min(face, kinds.length - 1))
}
