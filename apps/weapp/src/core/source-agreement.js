import { ccByLicense, openRouterLicense, vercelLicense, cloudbaseNotice } from './cc-by-4.0.js'
import { epochAttribution } from './epoch-attribution.js'
import { arenaAttribution, isArenaDatasetBoard } from './arena-attribution.js'

// Resolve from the displayed snapshot so cached provenance remains available offline.
export function sourceAgreement(kind, board, language = 'en') {
  if (kind === 'openRouterUsage') return openRouterLicense(board?.sourceNote, language)
  if (kind === 'vercelUsage') return vercelLicense(board?.sourceNote, language)
  if (kind === 'cloudbaseUsage') return cloudbaseNotice(board?.sourceNote, language)
  const attribution = kind === 'epochECI' ? epochAttribution(language)
    : board?.kind === kind && isArenaDatasetBoard(board) ? arenaAttribution(language) : null
  return attribution ? `${attribution.fullText}\n\n${ccByLicense(language).text}` : ''
}
