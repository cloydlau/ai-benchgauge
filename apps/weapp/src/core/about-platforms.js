import { text, desktopDownloadURL, repositoryURL } from './catalog.js'

// Product availability is explicitly maintained, not inferred from build targets.
const platforms = [
  { id: 'weapp', names: ['WeChat Mini Program', '微信小程序', '微信小程式'], status: 'live', features: ['boards'] },
  { id: 'ios', names: ['iOS', 'iOS', 'iOS'], status: 'development', features: ['boards'] },
  { id: 'ipad', names: ['iPad', 'iPad', 'iPad'], status: 'development', features: ['boards'] },
  { id: 'android', names: ['Android', '安卓', '安卓'], status: 'unavailable', features: [] },
  { id: 'harmony', names: ['HarmonyOS', '鸿蒙', '鴻蒙'], status: 'unavailable', features: [] },
  { id: 'macos', names: ['macOS', 'macOS', 'macOS'], status: 'live', features: ['boards', 'quota'] },
  { id: 'windows', names: ['Windows', 'Windows', 'Windows'], status: 'development', features: ['boards', 'quota'] },
]
const statuses = {
  live: ['Live', '已上线', '已上線'],
  development: ['In development', '开发中', '開發中'],
  unavailable: ['Unavailable', '暂无', '暫無'],
}
const features = { boards: ['Leaderboards', '榜单', '榜單'], quota: ['Quota', '余量', '餘量'] }

export function aboutPlatforms(language) {
  return {
    title: text(['Platforms', '各端进展', '各端進展'], language),
    copyLinkLabel: text(['Copy link', '复制链接', '複製連結'], language),
    contributeLabel: text(['PR welcome', '欢迎贡献代码', '歡迎貢獻程式碼'], language),
    repositoryURL,
    items: platforms.map(platform => ({
      id: platform.id, name: text(platform.names, language),
      note: platform.id === 'ios' ? text(['(incl. iPhone Duo)', '（含 iPhone Duo）', '（含 iPhone Duo）'], language) : '',
      status: platform.status, statusLabel: text(statuses[platform.status], language),
      features: platform.features.map(feature => text(features[feature], language)),
      featureText: platform.features.map(feature => text(features[feature], language)).join(' · '),
    })),
  }
}
