import notice from '../../../../fc/arena-attribution.json' with { type: 'json' }
export { isArenaDatasetBoard } from '../../../../fc/domain.mjs'

export function arenaAttribution(language = 'en') {
  const key = language === 'zh-CN' ? 'zh' : language === 'zh-TW' ? 'zh-Hant' : language
  const changes = notice.changes[key] || notice.changes.en
  const links = `${notice.sourceURL} · ${notice.licenseURL}`
  return { ...notice, changes, links, fullText: `${notice.credit}\n${links}\n${changes}` }
}
