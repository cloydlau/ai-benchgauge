import license from '../../../../Sources/LeaderboardKit/Resources/CC-BY-4.0.json' with { type: 'json' }

export function ccByLicense(language = 'en') {
  // App codes are en / zh-CN / zh-TW. Bare zh is the bundled simplified key.
  const key = language === 'zh-CN' || language === 'zh' ? 'zh' : language === 'zh-TW' ? 'zh-Hant' : language
  return { canonicalURL: license.canonicalURL, text: license[key] || license.en }
}

export function openRouterLicense(sourceNote, language = 'en') {
  const attribution = sourceNote?.trim() || 'Source: OpenRouter (openrouter.ai/rankings).\nLicensed under CC BY 4.0.\nhttps://creativecommons.org/licenses/by/4.0/'
  return `${attribution}\n\n${ccByLicense(language).text}`
}

export function vercelLicense(sourceNote, language = 'en') {
  const attribution = sourceNote?.trim() || '© 2026 Vercel. "AI Gateway Leaderboard Data" is licensed under CC BY 4.0. To view a copy of this license, visit https://creativecommons.org/licenses/by/4.0/\nSource: https://vercel.com/ai-gateway/leaderboards/models'
  return `${attribution}\n\n${ccByLicense(language).text}`
}

export function cloudbaseNotice(sourceNote, language) {
  const notices = ['Tencent CloudBase · Source notice. Cumulative token shares across sampled Beijing-time days; model families, including cached input tokens. No absolute volumes or full sample dates are published. No open-data license is stated; rights retained by Tencent. This is not CC BY data.', '腾讯 CloudBase · 来源说明。北京时间抽样统计日的 token 累计占比，按模型系列汇总，包含缓存命中；未公开绝对用量或完整抽样日期。来源未声明开放数据许可，相关权利归腾讯所有，此数据不适用 CC BY 4.0。', '騰訊 CloudBase · 來源說明。北京時間抽樣統計日的 token 累計佔比，按模型系列彙總，包含快取命中；未公開絕對用量或完整抽樣日期。來源未聲明開放資料授權，相關權利歸騰訊所有，此資料不適用 CC BY 4.0。']
  return notices[language === 'en' ? 0 : language === 'zh-TW' ? 2 : 1] + '\n\n' + (sourceNote?.trim() || 'Source: Tencent CloudBase\nhttps://docs.cloudbase.net/ai/announcement/model-token-volume')
}
