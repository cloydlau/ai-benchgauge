import { resolve } from 'node:path'

// domain.mjs is shared with the server, where the image catalog is required.
// Keep identity rules in the mini-program while images arrive in snapshots.
export function clientBrandPolicyPlugin(root) {
  const catalogPath = resolve(root, 'fc/brand-catalog.json')
  return {
    name: 'client-brand-policy',
    enforce: 'pre',
    transform(source, id) {
      if (resolve(id.split('?')[0]) !== catalogPath) return null
      const { aliases, families, modelDevelopers, modelDisplayAliases, colors, bundledModelMarks } = JSON.parse(source)
      return { code: JSON.stringify({ aliases, families, modelDevelopers, modelDisplayAliases, colors, bundledModelMarks,
        modelLogos: [], providerLogos: {} }), map: null }
    },
  }
}
