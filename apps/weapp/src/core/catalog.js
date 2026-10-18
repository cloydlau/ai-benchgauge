export const categories = [
  { id: 'general', labels: ['General', '综合', '綜合'], kinds: ['artificialAnalysis', 'arenaText', 'epochECI'] },
  { id: 'coding', labels: ['Coding', '编程', '編程'], kinds: ['artificialAnalysisCodingAgent', 'codeArenaWebDev'] },
  { id: 'image', labels: ['Image', '图片', '圖片'], kinds: ['artificialAnalysisTextToImage', 'arenaTextToImage'] },
  { id: 'video', labels: ['Video', '视频', '影片'], kinds: ['artificialAnalysisTextToVideo', 'arenaTextToVideo'] },
]
export const desktopDownloadURL = 'https://github.com/cloydlau/ai-benchgauge/releases/latest'
export const leaderboardSources = [
  { id: 'epoch', title: 'Epoch AI', url: 'https://epoch.ai/eci' },
  { id: 'artificialAnalysis', title: 'Artificial Analysis', url: 'https://artificialanalysis.ai/' },
  { id: 'arena', title: 'Arena', url: 'https://arena.ai/leaderboard' },
]
export const boards = {
  epochECI: { title: 'Epoch ECI', summaries: ['Estimates general capability from benchmark results, accounting for difficulty and discrimination.', '结合不同测试的难度与区分度，估计模型的综合能力', '結合不同測試的難度與區分度，估計模型的綜合能力'], url: 'https://epoch.ai/eci' },
  artificialAnalysis: { title: 'Artificial Analysis', summaries: ['Combines standardized tests across several abilities.', '汇总多项标准化测试，适合看综合能力', '彙總多項標準化測試，適合看綜合能力'], url: 'https://artificialanalysis.ai/evaluations/artificial-analysis-intelligence-index' },
  arenaText: { title: 'Text Arena', summaries: ['People compare anonymous answers to real prompts.', '真实提问下盲选回答，贴近用户偏好', '真實提問下盲選回答，貼近使用者偏好'], url: 'https://arena.ai/leaderboard/text' },
  artificialAnalysisCodingAgent: { title: 'Artificial Analysis 编程', titles: ["Artificial Analysis Coding", "Artificial Analysis 编程", "Artificial Analysis 編程"], summaries: ['Scores coding agents on software engineering tasks.', '通过软件工程任务，检验编程智能体的完成能力', '透過軟體工程任務，檢驗程式設計智能體的完成能力'], url: 'https://artificialanalysis.ai/agents/coding-agents' },
  codeArenaWebDev: { title: 'Code Arena', summaries: ['People pick the better result from paired web builds.', '用户盲选网页成品，侧重实际观感', '使用者盲選網頁成品，側重實際觀感'], url: 'https://arena.ai/leaderboard/code/webdev' },
  artificialAnalysisTextToImage: { title: 'Artificial Analysis 文生图', titles: ["Artificial Analysis Text to Image", "Artificial Analysis 文生图", "Artificial Analysis 文生圖"], summaries: ['Blind votes across a balanced set of image use cases.', '按用途均衡选题，盲选图片质量', '按用途均衡選題，盲選圖片品質'], url: 'https://artificialanalysis.ai/image/leaderboard/text-to-image' },
  arenaTextToImage: { title: 'Arena 文生图', titles: ["Text to Image Arena", "Arena 文生图", "Arena 文生圖"], summaries: ['People vote on images made from their own prompts.', '用户自由出题并盲选，贴近日常审美', '使用者自由出題並盲選，貼近日常審美'], url: 'https://arena.ai/leaderboard/text-to-image' },
  artificialAnalysisTextToVideo: { title: 'Artificial Analysis 文生视频', titles: ["Artificial Analysis Text to Video", "Artificial Analysis 文生视频", "Artificial Analysis 文生影片"], summaries: ['Blind votes on videos made with comparable settings.', '相同提示词、统一设置下盲选视频质量', '相同提示詞、統一設定下盲選影片品質'], url: 'https://artificialanalysis.ai/video/leaderboard/text-to-video' },
  arenaTextToVideo: { title: 'Arena 文生视频', titles: ["Text to Video Arena", "Arena 文生视频", "Arena 文生影片"], summaries: ['People vote on paired videos from real prompts.', '用户自由出题并盲选，贴近日常偏好', '使用者自由出題並盲選，貼近日常偏好'], url: 'https://arena.ai/leaderboard/text-to-video' },
}
export const languages = ['en', 'zh-CN', 'zh-TW']
export const hasOwn = (value, key) => Object.prototype.hasOwnProperty.call(value, key)
export const text = (values, language) => values[Math.max(0, languages.indexOf(language))]
export const boardTitle = (kind, language) => boards[kind].titles ? text(boards[kind].titles, language) : boards[kind].title
export const categoryFor = id => categories.find(category => category.id === id) || categories[0]

const tagline = ['Compare leaderboards to make informed choices; track quotas to know where you stand.',
  '多榜对照，选得明白；余量追踪，用得有数。',
  '多榜對照，選得明白；餘量追蹤，用得有數。']

export const copy = {
  tagline,
  description: [`Blind user votes show the experience; task benchmarks show capability. ${tagline[0]}`,
    `用户盲测看体验，任务测评看能力。${tagline[1]}`,
    `使用者盲測看體驗，任務測評看能力。${tagline[2]}`],
  name: ['AI BenchGauge', 'AI 天梯', 'AI 天梯'], subtitle: ['Dual boards & quota tracking', '双榜对照 & 余量追踪', '雙榜對照 & 餘量追蹤'],
  capabilityIndex: ['Calibrated tests', '难度校准', '難度校準'],
  tasks: ['Task benchmarks', '任务测评', '任務測評'], votes: ['User votes', '用户盲测', '使用者盲測'],
  models: ['Models', '模型', '模型'], companies: ['Companies', '公司', '公司'], rank: ['Rank', '排名', '排名'],
  searchModels: ['Search models', '搜索模型', '搜尋模型'], clearSearch: ['Clear search', '清空搜索', '清空搜尋'],
  score: ['Score', '分数', '分數'], source: ['Source', '源码', '原始碼'], country: ['Country', '国家', '國家'],
  unknownCountryTitle: ['Why no country?', '为什么没有国家归属？', '為什麼沒有國家歸屬？'],
  unknownCountryExplanation: [
    'Country reflects the model developer’s headquarters. Some models are community projects or collaborations, or lack enough reliable information to identify one developer and headquarters. We leave them unassigned rather than guess from the model name, language, base model or hosting provider.',
    '国家归属依据模型开发者的总部所在地。部分模型属于社区项目或多方合作，也可能缺少足够可靠的信息来确认开发者及其总部，因此暂不归属到某个国家。我们不会根据模型名称、语言、基座模型或托管平台猜测归属。',
    '國家歸屬依據模型開發者的總部所在地。部分模型屬於社群專案或多方合作，也可能缺少足夠可靠的資訊來確認開發者及其總部，因此暫不歸屬到某個國家。我們不會根據模型名稱、語言、基礎模型或託管平台猜測歸屬。'],
  all: ['All', '全部', '全部'], open: ['Open', '开源', '開源'], closed: ['Closed', '闭源', '閉源'], unknown: ['Unknown', '未知', '未知'],
  updated: ['Updated', '更新', '更新'], fetched: ['Fetched', '抓取', '擷取'], refresh: ['Refresh', '刷新', '重新整理'],
  loading: ['Loading shared rankings…', '正在读取共享榜单…', '正在讀取共享榜單…'],
  empty: ['No matching entries', '暂无符合筛选的条目', '暫無符合篩選的項目'],
  noBoard: ['No shared snapshot yet', '暂未取得共享榜单', '暫未取得共享榜單'],
  reset: ['Clear filters', '清除筛选', '清除篩選'], about: ['About', '关于', '關於'],
  copied: ['Copied', '已复制', '已複製'], copyName: ['Copy', '复制', '複製'], cancel: ['Cancel', '取消', '取消'], language: ['Language', '语言', '語言'], theme: ['Appearance', '外观', '外觀'],
  plan: ['Plan', '套餐', '套餐'], payAsYouGo: ['Usage', '按量', '按量'],
  copyLink: ['Copy link', '复制链接', '複製連結'],
  copyLinkFailed: ['Could not copy. Try again.', '链接复制失败，请重试。', '連結複製失敗，請重試。'],
  automatic: ['System', '跟随系统', '跟隨系統'], light: ['Light', '浅色', '淺色'], dark: ['Dark', '深色', '深色'],
  details: ['Model details', '模型详情', '模型詳情'], strongest: ['Strongest listed model sets the company score.', '公司分数以榜内最强模型为准。', '公司分數以榜內最強模型為準。'],
  missingTime: ['The source provides no publication time.', '来源未提供实际更新时间。', '來源未提供實際更新時間。'],
  screenshot: ['Screenshot', '截图', '截圖'], back: ['Back', '返回', '返回'],
  generating: ['Generating image', '正在生成截图', '正在產生截圖'],
  preview: ['Preview', '预览大图', '預覽大圖'], saveImages: ['Save to Photos', '保存到相册', '儲存至相簿'],
  saveAllImages: ['Save all to Photos', '全部保存到相册', '全部儲存至相簿'],
  savingImages: ['Saving', '正在保存', '正在儲存'], savedImages: ['Saved to Photos', '已保存到相册', '已儲存至相簿'],
  screenshotFailed: ['Could not generate the image. Try again.', '截图生成失败，请重试。', '截圖產生失敗，請重試。'],
  saveFailed: ['Could not save the image. Try again.', '保存失败，请重试。', '儲存失敗，請重試。'],
  photoPermission: ['Allow saving to Photos in Settings, then try again.', '请在设置中允许保存到相册，再点击保存。', '請在設定中允許儲存至相簿，再點選儲存。'],
  settings: ['Open', '打开设置', '開啟設定'], close: ['Close', '关闭', '關閉'],
  leaderboardComplete: ['End of this leaderboard', '本榜单已列完', '本榜單已列完'],
  featureDetails: ['Multiple leaderboards & quota tracking', '多榜对照 & 余量追踪', '多榜對照 & 餘量追蹤'],
  gotIt: ['Got it', '我知道了', '我知道了'], desktopLink: ['PC link', 'PC 端链接', 'PC 端連結'],
  quotaHelp: ['Quota tracking is available in the PC edition. Open the desktop app to check account balances and usage.', '余量追踪目前在 PC 端提供。请在电脑上打开 AI 天梯查看账号额度与使用进度。', '餘量追蹤目前在 PC 端提供。請在電腦上開啟 AI 天梯查看帳號額度與使用進度。'],
  cubeScroll: ['Scroll', '上下滚动', '上下捲動'], cubeSwitch: ['Switch boards', '左右切换', '左右切換'],
}
