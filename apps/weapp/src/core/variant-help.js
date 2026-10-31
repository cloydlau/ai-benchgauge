import catalog from '../../../../Sources/LeaderboardKit/Resources/LeaderboardVariantHelp.json' with { type: 'json' }
import { boardVariants, variantBase, text } from './catalog.js'

export function variantHelp(kind, language) {
  const base = variantBase(kind)
  if (!base) return ''
  const options = boardVariants[base].map(option => {
    const entry = catalog.options[option]
    return `${text(entry.title, language)}\n${text(entry.detail, language)}`
  })
  return [text(catalog.heading, language), ...options, ...(catalog.references[base] || [])].join('\n\n')
}
