import notice from '../../../../Sources/LeaderboardKit/Resources/EpochAttribution.json' with { type: 'json' }

export function epochAttribution(language = 'en') {
  const key = language === 'zh-CN' ? 'zh' : language === 'zh-TW' ? 'zh-Hant' : language
  const changes = notice.changes[key] || notice.changes.en
  const links = `${notice.sourceURL} · ${notice.licenseURL}`
  return { ...notice, changes, links, fullText: [notice.credit, links, changes].join('\n') }
}
