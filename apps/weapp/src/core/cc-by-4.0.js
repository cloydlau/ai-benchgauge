import license from '../../../../Sources/LeaderboardKit/Resources/CC-BY-4.0.json' with { type: 'json' }

export function ccByLicense(language = 'en') {
  // App codes are en / zh-CN / zh-TW. Bare zh is the bundled simplified key.
  const key = language === 'zh-CN' || language === 'zh' ? 'zh' : language === 'zh-TW' ? 'zh-Hant' : language
  return { canonicalURL: license.canonicalURL, text: license[key] || license.en }
}
