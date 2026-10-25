export const categories = [
  { id: 'usage', labels: ['Usage', '用量', '用量'], kinds: ['openRouterUsage', 'vercelUsage', 'cloudbaseUsage'] },
  { id: 'general', labels: ['General', '综合', '綜合'], kinds: ['artificialAnalysis', 'arenaText', 'epochECI'] },
  { id: 'coding', labels: ['Coding', '编程', '編程'], kinds: ['artificialAnalysisCodingAgent', 'codeArenaWebDev'] },
  { id: 'image', labels: ['Image', '图片', '圖片'], kinds: ['artificialAnalysisTextToImage', 'arenaTextToImage'] },
  { id: 'video', labels: ['Video', '视频', '影片'], kinds: ['artificialAnalysisTextToVideo', 'arenaTextToVideo'] },
]
export const repositoryURL = 'https://github.com/cloydlau/ai-benchgauge'
export const desktopDownloadURL = `${repositoryURL}/releases/latest`
export const leaderboardSources = [
  { id: 'cloudbase', title: 'Tencent Cloud', url: 'https://docs.cloudbase.net/ai/announcement/model-token-volume' },
  { id: 'vercel', title: 'Vercel AI Gateway', url: 'https://vercel.com/ai-gateway/leaderboards/models' },
  { id: 'openRouter', title: 'OpenRouter', url: 'https://openrouter.ai/rankings' },
  { id: 'artificialAnalysis', title: 'Artificial Analysis', url: 'https://artificialanalysis.ai/' },
  { id: 'arena', title: 'Arena', url: 'https://arena.ai/leaderboard' },
  { id: 'epoch', title: 'Epoch AI', url: 'https://epoch.ai/eci' },
]
export const boards = {
  cloudbaseUsage: { title: 'Tencent Cloud', summaries: ['Cumulative text-token share across sampled Beijing-time days; full dates unavailable.', '北京时间抽样统计日的文本 token 累计占比；未公开完整日期。', '北京時間抽樣統計日的文字 token 累計佔比；未公開完整日期。'], methodology: ['Input + output tokens including cache hits; official model-family buckets. Other excluded; company shares sum listed families. No absolute volumes or open-data license stated.', '输入与输出 token 之和，含缓存命中；按官方模型系列汇总，排除 Other。公司占比仅汇总榜内系列。未公开绝对用量或开放数据许可。', '輸入與輸出 token 之和，含快取命中；按官方模型系列彙總，排除 Other。公司佔比僅彙總榜內系列。未公開絕對用量或開放資料授權。'], url: 'https://docs.cloudbase.net/ai/announcement/model-token-volume' },
  vercelUsage: { title: 'Vercel AI Gateway', summaries: ['Latest complete day · text token share · absolute volumes unavailable.', '最近完整一天的文本 token 用量占比；不提供绝对用量。', '最近完整一天的文字 token 用量佔比；不提供絕對用量。'], methodology: ['Daily data uses UTC 00:00 to 00:00 the next day (08:00 to 08:00 the next day in Beijing). Includes input, output, reasoning and cached tokens. Only published models are listed; Other is excluded. Company shares sum listed models only. Not comparable to OpenRouter absolute totals.', '按 UTC 当天 00:00 至次日 00:00 统计，对应北京时间当天 08:00 至次日 08:00。包含输入、输出、推理及缓存 token；仅列出官方公布的模型，Other 不作为模型展示。公司占比只汇总榜内模型。与 OpenRouter 绝对用量口径不同。', '按 UTC 當天 00:00 至次日 00:00 統計，對應北京時間當天 08:00 至次日 08:00。包含輸入、輸出、推理及快取 token；僅列出官方公布的模型，Other 不作為模型展示。公司佔比只彙總榜內模型。與 OpenRouter 絕對用量口徑不同。'], url: 'https://vercel.com/ai-gateway/leaderboards/models' },
  openRouterUsage: { title: 'OpenRouter', summaries: ['Latest complete UTC day · input + output tokens · 1B = 1 billion tokens.', '最近完整 UTC 日输入与输出 token 用量；1B = 十亿 token。', '最近完整 UTC 日輸入與輸出 token 用量；1B = 十億 token。'], methodology: ['Latest complete UTC day · prompt + completion tokens · top 50 public models. 1B = 1 billion tokens. Excludes private and zero-data-retention traffic; provider tokenizers differ. Company totals cover listed models only.', '最近完整 UTC 日的输入与输出 token 用量，展示公开流量前 50 名。1B = 十亿 token。排除私有及零数据留存流量；各供应商分词方式不同。公司用量仅汇总榜内模型。', '最近完整 UTC 日的輸入與輸出 token 用量，展示公開流量前 50 名。1B = 十億 token。排除私有及零資料留存流量；各供應商分詞方式不同。公司用量僅彙總榜內模型。'], url: 'https://openrouter.ai/rankings' },
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
export const categoryFor = id => categories.find(category => category.id === id) || categories.find(category => category.id === 'general')

const tagline = ['Compare leaderboards to make informed choices; track quotas to know where you stand.',
  '多榜对照，选得明白；余量追踪，用得有数。',
  '多榜對照，選得明白；餘量追蹤，用得有數。']
const rankingSummary = ['Task benchmarks show results; blind user votes show the experience; difficulty-calibrated tests show overall capability.',
  '任务测评看成绩，用户盲测看体验，难度校准看实力。',
  '任務測評看成績，使用者盲測看體驗，難度校準看實力。']

export const copy = {
  usageDay: ['Data', '数据', '資料'],
  tokenShare: ['Share', '占比', '佔比'],
  usageShareSum: ['Sum of listed model shares only.', '仅汇总榜内模型的用量占比。', '僅彙總榜內模型的用量佔比。'],
  usage: ['Usage ranking', '用量排行', '用量排行'], tokens: ['Tokens', '用量', '用量'],
  dataPending: ['Data source awaiting configuration', '数据源待配置', '資料來源待設定'],
  dataPendingHelp: ['An OpenRouter API key must be configured on the server.', '服务端尚未配置 OpenRouter API Key。', '伺服器尚未設定 OpenRouter API Key。'],
  usageSum: ['Sum of listed models only; 1B = 1 billion tokens.', '仅汇总榜内模型；1B = 十亿 token。', '僅彙總榜內模型；1B = 十億 token。'],
  tagline,
  rankingSummary,
  description: rankingSummary.map((summary, index) => `${summary}${index === 0 ? ' ' : ''}${tagline[index]}`),
  name: ['AI BenchGauge', 'AI 天梯', 'AI 天梯'], subtitle: tagline,
  capabilityIndex: ['Calibrated tests', '难度校准', '難度校準'],
  dailyUsage: ['Daily usage', '每日用量', '每日用量'],
  dailyShare: ['Daily share', '每日占比', '每日佔比'],
  cumulativeShare: ['Cumulative share', '累计占比', '累計佔比'],
  tasks: ['Task benchmarks', '任务测评', '任務測評'], votes: ['User votes', '用户盲测', '使用者盲測'],
  models: ['Models', '模型', '模型'], companies: ['Companies', '公司', '公司'], rank: ['Rank', '排名', '排名'],
  showAll: ['Show all {count}', '展开全部 {count} 条', '展開全部 {count} 條'], showLess: ['Show less', '收起', '收起'],
  searchModels: ['Search models', '搜索模型', '搜尋模型'], clearSearch: ['Clear search', '清空搜索', '清空搜尋'],
  searchCompanies: ['Search companies', '搜索公司', '搜尋公司'],
  score: ['Score', '分数', '分數'], source: ['Source', '源码', '原始碼'], country: ['Country', '国家', '國家'],
  unknownCountryTitle: ['Why no country?', '为什么没有国家归属？', '為什麼沒有國家歸屬？'],
  unknownCountryExplanation: [
    'Country reflects the model developer’s headquarters. Some models are community projects or collaborations, or lack enough reliable information to identify one developer and headquarters. We leave them unassigned rather than guess from the model name, language, base model or hosting provider.',
    '国家归属依据模型开发者的总部所在地。部分模型属于社区项目或多方合作，也可能缺少足够可靠的信息来确认开发者及其总部，因此暂不归属到某个国家。我们不会根据模型名称、语言、基座模型或托管平台猜测归属。',
    '國家歸屬依據模型開發者的總部所在地。部分模型屬於社群專案或多方合作，也可能缺少足夠可靠的資訊來確認開發者及其總部，因此暫不歸屬到某個國家。我們不會根據模型名稱、語言、基礎模型或託管平台猜測歸屬。'],
  all: ['All', '全部', '全部'], open: ['Open', '开源', '開源'], closed: ['Closed', '闭源', '閉源'], unknown: ['Unknown', '未知', '未知'],
  countryShare: ['Country share', '国家占比', '國家占比'], sourceShare: ['Source share', '源码占比', '原始碼占比'],
  distributionBasis: ['All models on this board · counts, not scores', '按全榜模型数量统计，不按分数加权', '按全榜模型數量統計，不按分數加權'],
  noModels: ['No model data yet', '暂无模型数据', '暫無模型資料'], other: ['Other', '其他', '其他'],
  published: ['Published', '发布', '發佈'], updated: ['Refreshed', '刷新', '刷新'], refresh: ['Refresh', '刷新', '重新整理'],
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
