# 跨端变更与验收

产品优化默认以相关客户端为范围。iPhone / iPad 属于同一应用但必须分别检查窄屏和宽屏。实施前从下表定位消费者；完成时记录本次改动的实现、自动检查、原生验收和安装状态。用户明确限定平台时尊重限定。平台差异应解释理由，不能静默漏改。

一般改动默认同轮落实所有相关端，不逐端征求确认。PC 和移动端以相同产品目标分别适配，不能机械复制界面；常规适配自主完成。只有是否适用、兼容性或产品取舍确实拿不准时，提出具体问题、可选方案、影响和建议，再由人工决定。该默认原则由 Calmmit 的共享 AGENTS.md 和审查入口共同维护。

| 能力 | 共用来源 / 生成入口 | 消费者与核验入口 |
| --- | --- | --- |
| 移动标题与导出标题 | `assets/brand/mobile-title.json` → `node Scripts/sync-mobile-brand.mjs` | 小程序 `core/brand-title.js`、SVG / Canvas；iOS `MobileBrandTitle`（主界面、关于、导出）。`Scripts/mobile-brand.test.mjs` 检查两端副本与几何；Swift `MobileBrandTitleTests`、`MobileBrandSizingTests`；原生 `testSharedMobileWordmarkInEveryLanguageAndTheme` |
| 桌面标题与图标 | `assets/brand/`、`Scripts/brand-assets.swift`、`Scripts/ios-icon.swift` | Mac `EnglishBrandTitle` / `ChineseBrandTitle`；Windows WPF 标题。桌面标题保留原生基线 / 字体布局，移动标题使用独立的紧凑字距；正式图标和标题网络图仍共源。遵循 `docs/visual-comparison.md` 的双桌面截图要求 |
| 模型 / 公司排行、地区与开源规则 | `fc/domain.mjs`、`fc/leaderboard-policy.json`、`fc/brand-catalog.json`、`Scripts/generate-leaderboard-policy.mjs` | `Sources/LeaderboardKit`、小程序 `core/leaderboard.js`、Windows 共享引擎；同时检查筛选、公司聚合、离线缓存和图片导出 |
| 来源标志、主题与关于页 | `assets/brand/partners/`、`Scripts/source-logos.mjs`、`Sources/LeaderboardKit/Resources/SourceTabThemes.json` | 小程序榜单 / 关于 / 导出，iOS 来源标签 / 关于 / 导出，Mac / Windows 标题与来源说明；深浅色和离线资源分别验收 |
| 发布时间、刷新时间和刷新反馈 | 共享 Kit 时间策略、小程序 `core/freshness.js`、`Tests/fixtures/calendar-timestamps.json` | 小程序榜单与 Canvas、iOS `LeaderboardPadView` 与导出、Mac / Windows 时间文案。移动下拉检查起始 / 加载 / 完成三态；桌面保留原生刷新交互 |
| 搜索、筛选与来源切换 | Kit 排行投影 / 过滤策略、小程序 `pages/leaderboard/index.js`、iOS `LeaderboardPadStore` / `LeaderboardPadView` | 两移动端分别搜索模型名 / 聚合后的公司名并保留独立关键词，核对搜索清除、空结果、来源 / 类别 / 公司切换、筛选保留和导出；桌面核对对应筛选与投影，平台专属交互不硬搬 |
| 文案、许可与应用说明 | `config/app.json`、`Scripts/sync-app-description.mjs`、共享 Kit 本地化与离线许可 | 三种语言；各端主界面、关于、导出与应用元数据。不能只更新一个语言或一处显示 |

## 英文移动表头

英文移动榜单表头固定两行：榜单名称在模型/公司名称列的第一行，时间和搜索按钮在第二行，普通与吸顶状态一致。小程序和 iPhone/iPad 均采用该结构。图片导出有独立的完整标题、时间元数据及列宽，不放交互式搜索按钮；桌面保留现有宽度测量、原生表头和独立搜索交互。两行布局解决移动端可用列宽不足，不把同样的排版硬套到已经计算宽度的桌面。

## 移动标题防漂移

参数和字形只维护 `assets/brand/mobile-title.json`。生成器一次计算 I、BenchGauge / 天 / 梯的位置、A 的 31° 倾斜和宽高；小程序与 iOS 缩放同一份结果。主界面、关于与导出共用各端标题组件。iOS 不再依赖系统字体逐字拆分移动英文标题。

更换字形时，先运行 `swift Scripts/weapp-brand-glyphs.swift` 更新正式源与 SVG，再运行 `node Scripts/sync-mobile-brand.mjs`。一般排版参数修改只需运行后者。`node Scripts/sync-mobile-brand.mjs --check` 和常规 `./test.sh` 会拒绝未同步的副本；测试还会修改临时源确认检查确实能发现漂移。

这个检查保证标题资源与几何同步，不代表能自动识别所有产品行为的语义差异。其他优化仍必须按上表检查实际消费者。新增可共享规则应优先扩展共用来源和测试，不能用一张 “已同步” 表替代原生验收。

## 2026-10-25 初次对照范围

发现并修复移动英文标题的确定差异：原生旧 `EnglishBrandArtwork` 只将字符串索引大于 1 的字形加入路径，遗漏索引 1 的 I；A 未设置倾斜。小程序已有相应排版优化。本轮移动端改用同源几何；桌面标题的排版差异另行保留。

代码核对确认 iOS 已有模型搜索、全局筛选、三点下拉刷新、来源标志和关于页等对应实现，不能据此断言全部小程序优化都已逐帧对齐。它们此前的具体验收范围见 `apps/ios/README.md` 和 `docs/visual-comparison.md`。另发现小程序最新的公司名称搜索尚未同步，本轮补齐 iOS 并验证分组独立关键词、聚合后筛选和导出快照。非空查询失焦时小程序保留输入框，iOS 延续原生收起输入框并保留结果的既有交互；这项差异明确保留。原生验收结果见 iOS README。未进行全应用、全平台的完整视觉审计。
