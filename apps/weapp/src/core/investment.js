import { text } from './catalog.js'

const count = value => String(value).replace(/\B(?=(\d{3})+(?!\d))/g, ',')

// Reference budgets from Watrek's PRODUCT_COSTS, restricted to services used here.
// All amounts below are annual CNY budgets; tokens use its ¥2,000/month budget.
const costGroups = [
  { id: 'infrastructure', title: ['Infrastructure', '基础设施', '基礎設施'], items: [
    { id: 'server', amount: 1200, title: ['Cloud services', '云服务', '雲端服務'],
      body: ['Runs shared leaderboard queries and synchronization.', '支撑共享榜单查询与同步服务的日常运行。', '支撐共用榜單查詢與同步服務的日常運作。'] },
    { id: 'storage', amount: 400, title: ['Object storage', '对象存储', '物件儲存'],
      body: ['Stores leaderboard snapshots, model and company metadata, and icons.', '存放榜单快照、模型与厂商资料及图标。', '存放榜單快照、模型與廠商資料及圖示。'] },
    { id: 'logs', amount: 600, title: ['Service logs', '运行日志', '執行日誌'],
      body: ['Supports troubleshooting; cost varies with log volume and retention.', '用于排查服务异常，费用随日志量与留存周期浮动。', '用於排查服務異常，費用隨日誌量與保留週期浮動。'] },
  ] },
  { id: 'platform', title: ['Platform certification', '平台认证', '平台認證'], items: [
    { id: 'weapp', amount: 300, title: ['Mini-program certification', '小程序认证', '小程式認證'],
      body: ['Uses Watrek’s certification budget as a provision; actual fees depend on the registered entity and platform rules.',
        '参考 Watrek 同项认证预算预留，实际费用按主体类型与平台规则确定。', '參考 Watrek 同項認證預算預留，實際費用按主體類型與平台規則確定。'] },
  ] },
  { id: 'development', title: ['Development and operations', '研发与经营', '研發與經營'], items: [
    { id: 'tokens', amount: 2000 * 12, title: ['AI tokens', '词元', '詞元'],
      body: ['Budgeted at ¥2,000 per month for research, development and validation; annualized over 12 months.',
        '用于研究、开发与验证，按每月 ¥2,000、全年 12 个月折算。', '用於研究、開發與驗證，按每月 ¥2,000、全年 12 個月換算。'] },
    { id: 'staff', amount: null, title: ['Labor', '人力', '人力'],
      body: ['Feature development, platform adaptation, testing and release maintenance.', '功能研发、各端适配、测试验证与版本维护。', '功能研發、各端適配、測試驗證與版本維護。'] },
    { id: 'data', amount: null, title: ['Data maintenance', '数据维护', '資料維護'],
      body: ['Source integration, model and company matching, and scoring consistency.', '榜单来源接入、模型与厂商归属整理、分数口径校验。', '榜單來源接入、模型與廠商歸屬整理、分數口徑校驗。'] },
    { id: 'operations', amount: null, title: ['Operations', '运营', '營運'],
      body: ['User feedback, release delivery and ongoing product operations.', '用户反馈、版本分发与日常产品运营。', '使用者回饋、版本分發與日常產品營運。'] },
  ] },
]

export function investmentContent(stats, language) {
  const money = amount => amount == null ? text(['Not totaled', '暂未核算', '暫未核算'], language)
    : `${text(['~¥', '约¥', '約¥'], language)}${count(amount)}`
  const groups = costGroups.map(group => {
    const amount = group.items.reduce((sum, item) => sum + (item.amount ?? 0), 0)
    return { id: group.id, title: text(group.title, language), amount, amountText: money(amount),
      items: group.items.map(item => ({ ...item, title: text(item.title, language), body: text(item.body, language), amountText: money(item.amount) })) }
  })
  const total = groups.reduce((sum, group) => sum + group.amount, 0)
  return {
    title: text(['Costs and investment', '成本与投入', '成本與投入'], language),
    engineeringTitle: text(['Engineering investment', '工程投入', '工程投入'], language),
    metrics: [
      { id: 'commits', value: count(stats.commitCount), label: text(['Commits', '提交次数', '提交次數'], language) },
      { id: 'lines', value: count(stats.codeLineCount), label: text(['Lines of code', '代码行数', '程式碼行數'], language) },
    ],
    note: text([
      'Commits cover the full Git history. Lines count tracked text across the apps, shared components and services, excluding dependencies, generated output and binary files. Updated at build time.',
      '提交次数按完整 Git 历史累计；代码行数统计各端应用、共享组件与服务的已跟踪文本，不含依赖、生成产物和二进制。构建时自动更新。',
      '提交次數按完整 Git 歷史累計；程式碼行數統計各端應用、共用元件與服務的已追蹤文字，不含依賴、產生的檔案和二進位檔案。建置時自動更新。',
    ], language),
    budgetTitle: text(['Annual budget', '年度预算', '年度預算'], language),
    budgetIntro: text(['Reference annual budgets from Watrek for comparable items, assuming about 1,000 users. Amounts are in CNY and are estimates, not actual bills; usage affects costs.',
      '参考 Watrek 同类项目的年度预算，按约一千名用户估算，金额单位为人民币元。以下为预算参考，非实际账单，随用量浮动。',
      '參考 Watrek 同類項目的年度預算，按約一千名使用者估算，金額單位為人民幣元。以下為預算參考，非實際帳單，隨用量浮動。'], language),
    groups, total, totalText: money(total),
    totalTitle: text(['Estimated annual total', '年度预算合计', '年度預算合計'], language),
    costNote: text(['Labor, data maintenance and operations are not yet included in this total. Engineering counters are not converted to monetary costs.',
      '暂未计入人力、数据维护、运营等开销；工程统计不折算为金额。', '暫未計入人力、資料維護、營運等開銷；工程統計不折算為金額。'], language),
  }
}
