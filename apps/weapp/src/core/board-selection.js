import { categories, categoryFor } from './catalog.js'

// Match DesktopBoardSelection: defaults exclude archived sources; explicit choices retain them.
export function visibleBoardKinds(category, selections = {}) {
  const item = categoryFor(category), kinds = item.kinds
  const defaults = item.defaultKinds || kinds
  const saved = selections?.[category]
  const selected = Array.isArray(saved) ? kinds.filter(kind => saved.includes(kind)) : defaults
  return selected.length ? selected : defaults
}

export function normalizeBoardSelections(value) {
  return Object.fromEntries(categories.flatMap(category => {
    const kinds = visibleBoardKinds(category.id, value)
    const defaults = category.defaultKinds || category.kinds
    return kinds.length === defaults.length && kinds.every((kind, index) => kind === defaults[index]) ? [] : [[category.id, kinds]]
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
