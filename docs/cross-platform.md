# 跨端变更与验收

小程序 “功能说明” 弹窗按钮按从左到右排列为 `OK`、`PC 端链接`（繁中 `PC 端連結`，英文 `PC link`）。三语均用 `OK` 关闭，仅点击右侧链接按钮复制桌面下载地址。此双按钮顺序针对小程序已有的弹窗，原生客户端单按钮帮助弹窗不增加链接操作。

小程序和 iPhone/iPad 的 “关于” 页移除数据来源模块。协议随点击榜单名称打开的说明弹窗展示，macOS / Windows 同步入口：Epoch 和 Arena 数据集保留署名并附完整 CC BY 4.0，OpenRouter / Vercel 保留当前快照来源说明和完整协议；腾讯云只显示来源及权利说明，AA 和旧 Arena 不推定开放许可。协议离线可读，桌面简短悬浮提示不装入整份协议；第三方软件许可仍在原位置，图片导出不增加弹窗。

本次协议迁移验证（2026-10-26）：小程序 199 项测试及构建通过；macOS Debug 编译、Windows 共享测试及 WPF Release 交叉编译通过。iOS 仅完成源码语法检查，未运行 iPhone/iPad UI 测试。独立清单运行实际 Kit 目标为 116/117，通过本次新增协议测试；剩余 `CloudBaseUsageTests.swift:26` 仍期待旧时间说明，默认说明路径与本次改动前一致，未改写这条不相关断言。当前环境无完整 Xcode / Windows 原生运行环境，开发者工具 CUA 捕捉失败（ScreenCaptureKit -3811）；没有本次原生前后截图、双桌面视觉验收或安装验收，不据编译结果宣称界面已验收。

产品优化默认以相关客户端为范围。iPhone / iPad 属于同一应用但必须分别检查窄屏和宽屏。实施前从下表定位消费者；完成时记录本次改动的实现、自动检查、原生验收和安装状态。用户明确限定平台时尊重限定。平台差异应解释理由，不能静默漏改。

一般改动默认同轮落实所有相关端，不逐端征求确认。PC 和移动端以相同产品目标分别适配，不能机械复制界面；常规适配自主完成。只有是否适用、兼容性或产品取舍确实拿不准时，提出具体问题、可选方案、影响和建议，再由人工决定。该默认原则由 Calmmit 的共享 AGENTS.md 和审查入口共同维护。

| 能力 | 共用来源 / 生成入口 | 消费者与核验入口 |
| --- | --- | --- |
| 移动标题与导出标题 | `assets/brand/mobile-title.json` → `node Scripts/sync-mobile-brand.mjs` | 小程序 `core/brand-title.js`、SVG / Canvas；iOS `MobileBrandTitle`（主界面、关于、导出）。`Scripts/mobile-brand.test.mjs` 检查两端副本与几何；Swift `MobileBrandTitleTests`、`MobileBrandSizingTests`；原生 `testSharedMobileWordmarkInEveryLanguageAndTheme` |
| 桌面标题与图标 | `assets/brand/`、`Scripts/brand-assets.swift`、`Scripts/ios-icon.swift` | Mac `EnglishBrandTitle` / `ChineseBrandTitle`；Windows WPF 标题。桌面标题保留原生基线 / 字体布局，移动标题使用独立的紧凑字距；正式图标和标题网络图仍共源。遵循 `docs/visual-comparison.md` 的双桌面截图要求 |
| OpenAI 套餐与额外额度 | Core `CCSwitchQuotaParsers` / `AccountQuotaFormatting`、`OpenAIManagedQuotaSource` | macOS 余量条与菜单栏、Windows 共享引擎余量条与托盘；任一套餐窗口耗尽时显示 credits 余额，无限 / 未返回数字分别显示状态，缺少 credits 则保留百分比。缓存与路由投影保留余额；`OpenAICreditsTests` 和三语双主题 `openAICredits` 原生截图场景。小程序、iPhone/iPad 及榜单图片导出当前不展示账号余量，不新增该能力 |
| 模型 / 公司排行、地区与开源规则 | `fc/domain.mjs`、`fc/leaderboard-policy.json`、`fc/brand-catalog.json`、`Scripts/generate-leaderboard-policy.mjs` | `Sources/LeaderboardKit`、小程序 `core/leaderboard.js`、Windows 共享引擎；同时检查筛选、公司聚合、离线缓存和图片导出 |
| 来源标志、主题与关于页 | `assets/brand/partners/`、`Scripts/source-logos.mjs`、`Sources/LeaderboardKit/Resources/SourceTabThemes.json` | 小程序榜单 / 导出，iOS 来源标签 / 导出，Mac / Windows 标题与来源说明；深浅色和离线资源分别验收 |
| 表头榜单简介 | Kit `LeaderboardPresentation.sourceHelp` / `LeaderboardKind.sourceURL`、小程序 `core/catalog.js`、Windows 既有来源说明与 URL | 小程序、iPhone/iPad、macOS、Windows 点击表头名称打开该榜单简介，展示官方链接并提供显式复制链接操作；打开或关闭简介不写剪贴板。小程序 `page.test.mjs` 核对三语、全部类别、两种分组、复制与手势防误触；静态图片保留标题，不增加交互 |
| 发布时间、刷新时间和刷新反馈 | 共享 Kit 时间策略、小程序 `core/freshness.js`、`Tests/fixtures/calendar-timestamps.json` | 小程序榜单与 Canvas、iOS `LeaderboardPadView` 与导出、Mac / Windows 时间文案。移动下拉检查起始 / 加载 / 完成三态；桌面保留原生刷新交互 |
| 搜索、筛选与来源切换 | Kit 排行投影 / 过滤策略、小程序 `pages/leaderboard/index.js`、iOS `LeaderboardPadStore` / `LeaderboardPadView` | 两移动端分别搜索模型名 / 聚合后的公司名并保留独立关键词，核对搜索清除、空结果、来源 / 类别 / 公司切换、筛选保留和导出；魔方来源不循环，越过末榜进入下一类别首榜，越过首榜进入上一类别末榜，仅类别首尾循环；桌面核对对应筛选与投影，平台专属交互不硬搬 |
| 文案、许可与应用说明 | `config/app.json`、`Scripts/sync-app-description.mjs`、共享 Kit 本地化与离线许可 | 三种语言；各端主界面、关于、导出与应用元数据。不能只更新一个语言或一处显示 |
| 显示榜单 | Kit `DesktopBoardSelection`、小程序 `core/board-selection.js`；各端按分类保存 | 小程序设置页、iPhone/iPad `LeaderboardSettingsView`、桌面既有榜单选择器。默认全选，每类至少一榜，移动设置的重置恢复全部；移动单榜隐藏顶部 tabs 及占位，魔方跨分类按可见来源计数；排行、分布图、刷新和导出仅消费可见榜单，小程序分享保留显示选择 |
| 切换动效 | 小程序 `core/board-transition.js`、Apple `LeaderboardSwitchStyle` / `CubeFace` | 小程序与 iPhone/iPad 设置提供魔方、滑动、淡入淡出预览卡，默认魔方并本地持久保存；用于单榜视图的手势和标签切换，共用来源边界、跨分类导航、滚动对齐。分享保留接收方动效偏好，显示榜单重置不重置动效。减少动态效果时改为轻量淡入淡出并停用预览动画。iPad 宽屏和 Mac / Windows 的并列榜单保持原布局，静态导出无动效。JS `board-transition` / `settings` / `share-state` / `page` 测试及 Apple `LeaderboardCubeTests` 覆盖 |
| 模型详情 | Kit `ModelDetails` / `ModelDetailsView`、小程序 `core/model-details.js`；Windows 消费共享引擎的详情投影 | 小程序、iPhone/iPad、macOS、Windows：优先展示限额与能力卡片，模型资料、服务商价格和来源可展开查看，保留全部字段与显式复制操作；滚动后提供返回顶部。同步时间按设备本地时区显示 `yyyy-MM-dd HH:mm:ss`，保留秒数；固定截图夹具使用 UTC。图片导出不包含交互详情页 |
| 各端进展与贡献 | 小程序 `core/about-platforms.js` → `Scripts/ios-about.mjs`；微信图形 `assets/brand/partners/wechat/logo.svg` → `Scripts/source-logos.mjs` | 小程序与 iPhone/iPad 关于页，替换原 “余量查询” 卡片；固定七端功能及状态，每端单行显示图标、名称、功能和状态 Tag（无圆点）；七端图标统一为中性灰线框样式，微信保留品牌双气泡与四个圆点；iOS 标注 “（含 iPhone Duo）”。列表下方统一显示可复制仓库链接的 “欢迎贡献代码”（英文 PR welcome），各端无独立链接，macOS 状态同样使用 Tag；桌面 About 和图片导出没有原移动卡片，不新增模块 |
| 成本与工程投入 | Calmmit `cost-calculation.mjs`、`engineering-investment.mjs`、`resources/CostCalculation.swift` | 小程序与 iPhone/iPad 关于页。构建入口同步 JS / Swift 计算适配器；Git 统计、月份取整、按月累计和合计由 Calmmit 维护，项目预算、文案与 UI 独立维护。桌面及图片导出当前没有该成本区 |
| 关于页 AI 合影 | `assets/about/ai-models-group-portrait.jpg`、小程序 `core/about-artwork.js` → `Scripts/ios-about.mjs` | 小程序与 iPhone/iPad 关于页简介下方完整展示合影；署名改编作者 tombkeeper（个人主页及原帖）和历史原图摄影者 Benjamin Couprie（1927 年第五届索尔维会议，附原图来源）。作者名使用下划线，原帖使用链接图标，不另加可见的链接操作文案；小程序点按复制对应地址，原生直接打开。支持大图预览。小程序构建同尺寸 quality 86 JPEG，iOS 项目从同一目录打包原图；三语、深浅色及窄屏分别检查。桌面只有许可窗口，没有独立关于页；榜单图片导出不包含关于页内容 |

基础设施年度预算见 [预算说明](infrastructure-budget.md)。金额估算不细于百元，允许项目采用千元、万元等更粗粒度；各移动端从同一份预算定义生成金额与说明。费用为估算，非实际账单。

关于页 AI 合影验证（2026-10-27）：原始随机文件名改为 `assets/about/ai-models-group-portrait.jpg`，原图 SHA-256 不变。小程序生产构建及 8 项关于页/生成内容检查通过，另核对三语图片预览调用、出处复制、生成数据一致性与 iOS 项目资源路径；小程序图片 311,458 字节，完整产物 1,974,208 字节，低于 2 MiB。Swift 关于页源码语法检查及 2 项项目生成检查通过。使用实际卡片 CSS/文案的浏览器排版夹具核对 320/375px、浅深色，无裁图或溢出；这不是微信原生运行截图。官方微信 MCP 当前未提供，CUA 捕捉返回 ScreenCaptureKit -3811；iOS 构建入口确认本机缺少完整 Xcode SDK，未完成微信模拟器、iPhone/iPad 原生 UI 或真机安装验收。桌面及榜单图片导出没有对应关于页消费者，不涉及；未上传或发布版本。

合影署名修正（2026-10-27）：按用户要求改为 tombkeeper 的个人主页署名，保留单独的原帖图标；补充 Benjamin Couprie 及 1927 年第五届索尔维会议历史原图来源。作者名加下划线，不再显示平台名称或 “复制出处链接” 操作文案。小程序构建、8 项关于页/生成内容检查、三语署名与三类链接目标核对及 Swift 源码语法检查通过；iPhone/iPad 消费同一份署名数据。320/375px 浅深色浏览器排版已查看，未完成新的微信或 iOS 原生运行/安装验收；桌面及图片导出不涉及。预览及检查记录保存在忽略目录 `work/about-artwork-preview/`。

微博图标补充（2026-10-27）：tombkeeper 原帖入口改用 Simple Icons 微博图标，小程序和 iPhone/iPad 共用本地浅深色 PNG；原生大图工具栏同步使用该图标。作者名下划线及两级作者出处保留。10 项相关测试、资源一致性检查、小程序构建及 Swift 语法检查通过；已查看生成图标。主包 1,979,944 字节，低于 2 MiB。既有生成器重导出的 14 张 PNG 仅有编码/元数据变化，逐张解码确认像素不变。未完成新的微信/iOS 原生 UI 或安装验收，桌面和榜单图片导出不涉及。

文案与金额精度修正验证（2026-10-26）：小程序 200 项测试及构建、iOS 三语生成数据 2 项检查通过；Swift 粗粒度金额计算实际编译运行 9 项断言通过，iOS 内容模型语法检查通过。Calmmit 前台/后台 review 与公共计算相关 85 项测试通过，产品文案规则已核对两条实际提示入口。千元、万元等更粗金额单位可按项目指定，UI 不展示该内部配置。未运行移动 UI 测试或完成真机安装验收。

金额粒度规则验证（2026-10-26）：Calmmit 公共计算与生成适配 6 项测试通过；AI 天梯小程序 200 项测试及构建、iOS 数据生成 2 项检查通过，Swift 金额计算实际编译运行的 13 项断言通过。Watrek / Weaveo 生成适配同步，核心包分别 283 / 433 项测试通过，Weaveo 小程序 828 项测试通过，均通过原有覆盖率要求。本轮未运行 iPhone/iPad UI 测试或真机安装；桌面与图片导出不含此投入金额模块。

“各端进展” 验证（2026-10-26）：小程序 200 项测试及构建通过；已通过 CUA 核对当前仓库 `apps/weapp` 的微信开发者工具实际关于页，七端图标、单行信息及底部统一贡献入口均可见，macOS 无独立链接。iPhone/iPad 共用生成数据三语一致性检查与 Swift 源码语法检查通过，UI 用例已改为逐行核对七端功能与状态、确认无独立链接，并核对底部统一贡献入口。补跑 Apple 共用 UI 模块实际编译时，当前 Command Line Tools 缺少 `SwiftUIMacros.StateMacro` 插件，编译失败；未运行 iPhone/iPad UI 测试或完成真机安装验收。macOS/Windows 的运行界面与图片导出不涉及本次移动关于页替换。

七端图标线框统一验证（2026-10-26）：小程序微信改为双线框气泡，Android 改为空心轮廓并保留眼睛与天线，Windows 改为线框窗格；iPhone/iPad 共用视图同步 Android 与 Windows 的线框样式，其余已有线框图标保留。小程序 201 项测试及构建、iOS 生成数据 2 项检查与 Swift 语法检查通过。当前未提供可调用的官方微信开发者工具 MCP，CUA 两次读取开发者工具窗口均返回截图失败，因此本轮尚未完成小程序实际界面及深浅主题截图验收；当前仅安装 Command Line Tools，未完成 iPhone/iPad 完整构建、模拟器 UI 验收或真机安装。桌面与图片导出无此平台列表，不涉及本次图标调整。

微信图形辨识度修正（2026-10-26）：用 Tabler `brand-wechat` 线框源图替换普通聊天气泡及 SF Symbols 双气泡，保留大小双气泡、相反方向的尾部和四个圆点。小程序与 iPhone/iPad 共用 PNG 导出，原生以模板模式继承系统次要文字色，小程序使用现有深浅主题中性灰；MIT 许可随资源打包。24 项相关测试、共享资源一致性检查、小程序构建与 Swift 语法检查通过，已查看实际生成的 PNG；此资源核对不代表运行界面验收。CUA 仍因 ScreenCaptureKit 捕捉失败无法获取小程序窗口，iPhone/iPad 完整构建、模拟器 UI 和真机安装仍未完成；桌面与导出不含此列表。

移动设置的 “显示榜单” 勾选状态使用绿色，小程序搭配白色勾号，iPhone/iPad 使用系统绿色；未选中维持中性色，最后一个必选榜单维持禁用弱化样式。

小程序设置的榜单行关闭原生按钮默认点击态（`hover-class="none"`），由勾选框变化反馈选择，避免整行文字和图标按下时短暂变淡。保留按钮的禁用及无障碍语义；此修复仅针对小程序，原生客户端继续使用各自控件。

设置中的魔方、滑动、淡入淡出三张动效预览在挂载、首屏渲染完成后自动循环播放，无需选中。每 3 秒循环一次：起始画面停留 300ms、切换 1,050ms、结束画面停留 1,650ms。选择卡片仅更改实际榜单的动效偏好，不重启预览。小程序隐藏页面、iPhone/iPad 离开页面或进入后台时停止，重新显示时从头开始；减少动态效果时保持静态。此周期仅用于设置示例，不改变实际榜单的切换速度。

预览与实际榜单共用变换：小程序直接调用 `boardFaceStyle`，魔方透视按面宽保持 `1200:750` 的比例并同步面阴影；Apple 直接使用 `CubeFace`，预览没有来源 tabs 留白，因此阴影从顶部开始。翻转轴、整面宽位移和明暗不再单独近似；滑动和淡入淡出也共用各端实际变换与缓动。

移动顶部来源 tabs 在底部分类、可见来源数量及配色变化时，保留选中背景并以 420ms 平滑过渡宽度、位置和颜色；来源标签切换淡入。小程序保留按位置标识的按钮和按来源标识的标签，避免相同文案误复用来源；iPhone/iPad 同步动画并在单榜时收起选择器，两端均尊重减少动态效果设置。桌面并列榜单没有对应的上下 tab 联动，静态图片导出保留最终选中状态，无动画。

左右拖动单榜时，来源 tabs 选中背景直接跟随榜单的连续翻转进度，不额外叠加缓动；松手完成或取消回弹共用榜单的动画时长与缓动。小程序等待原生滚动对齐时与魔方一起停留在起始位置，准备完成后的追赶也共用时长；iPhone/iPad 使用同一位置与动画事务。来源首尾的最短路径映射到真实标签位置，开场提示及直接拖动 tabs 保留原有交互。此规则同样适用于滑动、淡入淡出设置，宽屏并列榜单与静态导出无对应进度动画。

tabs 与魔方进度同步验证（2026-10-27）：小程序 203 项全量测试、最终 5 项定向同步检查及构建通过，覆盖连续拖动、反向拖动、取消回弹、原生滚动准备与 120ms 追赶、420ms 收尾。iPhone/iPad 共用源码及测试语法检查通过，提取实际 `LeaderboardCube` 规则编译运行的 63 项断言通过；本机未安装完整 Xcode，未完成原生 UI 构建、模拟器或真机安装验收。CUA 确认当前开发者工具打开本仓库 `apps/weapp` 的实际榜单页，但截图返回 ScreenCaptureKit -3811，未完成拖动过程视觉验收。macOS、Windows、iPad 宽屏并列榜单及图片导出无此横向来源切换动画，不涉及修改。

## 榜单时间说明

时间说明弹窗的确认按钮在所有语言下固定为「OK」，不使用系统本地化的「确定」或「知道了」。

时间值与「发布／刷新」作为一个整体绘制连续下划线，覆盖中间空格；移动端加载时保留标签占位和整条线，避免分段文字或加载图标造成断口。图片导出不绘制交互下划线。

小程序、iPhone / iPad、macOS 和 Windows 的榜单时间与「发布／刷新」标签均加下划线，点击打开「时间说明」，不触发数据刷新。三语说明强调榜单数据实时更新，区分榜单提供的发布时间，以及未提供发布时间时展示的最近刷新时间；不展示采集实现细节。Apple 共用 `LeaderboardPresentation.sourceTimeExplanation`，小程序维护在 `core/catalog.js`，Windows 共用 `BoardTimestamp.Explanation`。各端原生弹窗按平台呈现；静态图片继续保留时间信息，不增加弹窗操作。

## 英文移动表头

英文移动榜单表头固定两行：榜单名称在模型/公司名称列的第一行，时间和搜索按钮在第二行，普通与吸顶状态一致。小程序和 iPhone/iPad 均采用该结构。图片导出有独立的完整标题、时间元数据及列宽，不放交互式搜索按钮；桌面保留现有宽度测量、原生表头和独立搜索交互。两行布局解决移动端可用列宽不足，不把同样的排版硬套到已经计算宽度的桌面。

## 移动标题防漂移

参数和字形只维护 `assets/brand/mobile-title.json`。生成器一次计算 I、BenchGauge / 天 / 梯的位置、A 的 31° 倾斜和宽高；小程序与 iOS 缩放同一份结果。主界面、关于与导出共用各端标题组件。iOS 不再依赖系统字体逐字拆分移动英文标题。

更换字形时，先运行 `swift Scripts/weapp-brand-glyphs.swift` 更新正式源与 SVG，再运行 `node Scripts/sync-mobile-brand.mjs`。一般排版参数修改只需运行后者。`node Scripts/sync-mobile-brand.mjs --check` 和常规 `./test.sh` 会拒绝未同步的副本；测试还会修改临时源确认检查确实能发现漂移。

这个检查保证标题资源与几何同步，不代表能自动识别所有产品行为的语义差异。其他优化仍必须按上表检查实际消费者。新增可共享规则应优先扩展共用来源和测试，不能用一张 “已同步” 表替代原生验收。

## 2026-10-25 初次对照范围

发现并修复移动英文标题的确定差异：原生旧 `EnglishBrandArtwork` 只将字符串索引大于 1 的字形加入路径，遗漏索引 1 的 I；A 未设置倾斜。小程序已有相应排版优化。本轮移动端改用同源几何；桌面标题的排版差异另行保留。

代码核对确认 iOS 已有模型搜索、全局筛选、三点下拉刷新、来源标志和关于页等对应实现，不能据此断言全部小程序优化都已逐帧对齐。它们此前的具体验收范围见 `apps/ios/README.md` 和 `docs/visual-comparison.md`。另发现小程序最新的公司名称搜索尚未同步，本轮补齐 iOS 并验证分组独立关键词、聚合后筛选和导出快照。非空查询失焦时小程序保留输入框，iOS 延续原生收起输入框并保留结果的既有交互；这项差异明确保留。原生验收结果见 iOS README。未进行全应用、全平台的完整视觉审计。

Artificial Analysis 的综合、编程、文生图、文生视频榜单表头统一显示 `Artificial Analysis`，三语一致，不追加分类后缀；分类由现有分类导航表达。小程序使用 catalog 标题，Apple 表头共用 `LeaderboardPresentation.columnTitle`，Windows 使用 `BoardTitle`。保留时间完整内容、来源说明及官方链接。

模型详情与状态 Tag 验证（2026-10-26）：小程序 201 项测试及构建通过，覆盖本地时间格式、时区跨日、秒数、折叠状态与返回顶部；Swift 时间格式 5 项实际运行断言通过。Windows WPF Release 交叉编译零警告/错误，共享测试通过。Apple 共享详情模块在独立清单下完成编译，但原生测试受当前工具链缺失 `TestingMacros` 影响；完整 Apple UI 构建仍受缺少 `SwiftUIMacros.StateMacro` 阻塞。微信开发者工具 CUA 再次出现 ScreenCaptureKit -3811，尚未完成本轮界面截图、iPhone/iPad UI 测试及双桌面视觉验收；未安装或发布客户端版本。

微信平台图标线宽修正（2026-10-26）：原始 Tabler SVG 保持不变，共用导出器将 24 单位坐标内的描边从 2 调整为 4/3，因此 18pt / 36rpx 显示时由约 1.5pt 减为 1pt；小程序及 iPhone/iPad 的浅深色 PNG 同步。2 项来源导出测试、6 项关于页检查、导出一致性检查及小程序完整生产构建通过。小程序全量测试停在既有清空搜索手势用例，本轮已中止自己的测试进程，未宣称全量通过。官方开发者工具 project_list / 状态检查持续未响应，备用 CUA 窗口捕获报 ScreenCaptureKit -3811，未完成模拟器截图验收；iPhone/iPad 本轮仅同步资源，未运行原生 UI 验收或真机安装。macOS/Windows 与图片导出没有此平台列表，不涉及。

关于页平台图标垂直居中修正（2026-10-26）：小程序名称与 iOS 小字号备注改为各自居中，和图标共用 40rpx 行内高度；安卓按包含天线的可见范围下移 2rpx，鸿蒙按包含底线的范围上移 2.5rpx。iPhone/iPad 共用视图将名称与备注分开居中并共用 24pt 行内高度，iPhone 图标使用显式缩放框，安卓 Canvas 按完整轮廓居中；鸿蒙原生 VStack 已将圆环与底线一起计入布局。6 项关于页检查、小程序生产构建及 Swift 源码语法检查通过。开发者工具状态检查仍无响应，未完成模拟器截图验收；当前仅有 Command Line Tools，未运行 iPhone/iPad 原生构建、UI 验收或真机安装。桌面与图片导出不含该平台列表，不涉及。
