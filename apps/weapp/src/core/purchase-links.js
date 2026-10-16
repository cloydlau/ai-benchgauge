import catalog from '../../../../fc/purchase-links.json' with { type: 'json' }
import { hasOwn } from './catalog.js'

const normalized = value => String(value || '').toLowerCase().replace(/[^\p{L}\p{N}]/gu, '')

export function purchaseLinks(organization, { modelName = '', category = 'general' } = {}) {
  const name = normalized(organization)
  const key = name ? (hasOwn(catalog.aliases, name) ? catalog.aliases[name] : name)
    : normalized(modelName).startsWith('devin') ? 'devin' : ''
  const variants = hasOwn(catalog.vendors, key) ? catalog.vendors[key] : null
  const links = variants && (hasOwn(variants, category) ? variants[category] : variants.default)
  return { codingPlan: links?.codingPlan || [], payAsYouGo: links?.payAsYouGo || [] }
}

export function preferredPurchaseLink(links, language) {
  const chineseDomain = link => new RegExp('^https://[^/]+\\.cn(?:/|$)', 'i').test(link.url)
  if (language === 'zh-CN') return links.find(link => link.site === 'mainlandChina' || chineseDomain(link)) || links[0]
  return links.find(link => link.site === 'international')
    || links.find(link => link.site === 'universal' && !chineseDomain(link)) || links[0]
}
