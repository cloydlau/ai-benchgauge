## Arena 文本榜介绍 — 2026-10-30

小程序、iPhone / iPad、Mac 和 Windows 的两个 Arena 文本榜介绍均补充原始总榜与风格控制的区别及 Arena 官方解释链接；榜单数据和排名不变。截图导出不包含介绍弹窗。

## PC 子榜切换 — 2026-10-30

Mac 与 Windows 将每个来源的子榜选择放进对应表头，标题只保留来源名，避免 Arena 文生图等名称与选择项重复；时间保留在表头上方；子榜选择使用适配浅色和深色的圆角背景，截图沿用表头的当前选择。小程序与 iPhone / iPad 保留现有布局。原生视觉对照和安装验收状态见本次交付。

## 榜单时间位置 — 2026-10-30

所有榜单的时间统一放在表头上方右侧，小程序与 iPhone / iPad 位于来源说明行，Mac 与 Windows 位于表头上方的独立时间行。来源详情、时间说明、子榜切换和图片导出继续可用。小程序 121 项相关测试与生产构建、Windows WPF 交叉编译和 Mac Debug 构建通过；iOS Swift 源码语法检查通过。微信开发者工具、iPhone / iPad、Windows 原生运行及桌面同夹具视觉对照尚未验收；本轮未安装或发布。

## 移动端 AA 表头 — 2026-10-30

小程序和 iPhone / iPad 的 Artificial Analysis 表格表头显示为 AA，截图中的表格表头相同；来源详情及无障碍名称仍保留完整名称。桌面端表头维持原样。移动端模拟器及真机视觉验收尚未完成。

## 分类顺序 — 2026-10-30

小程序、iPhone / iPad、Mac 和 Windows 的分类顺序统一为用量、综合、编程、图片、语音、视频；切换和已保存分类仍按标识处理。桌面原生视觉对照与移动端模拟器验收尚未完成。

## Arena 文本与图片转代码 — 2026-10-30

综合榜 Arena 可切换 Style Control 与原始 Text 总榜，分别读取官方数据集 `text_style_control` 和 `text`；编程榜 Arena 可切换 WebDev 与图片转代码，分别读取 `webdev` 的 `overall` 和 `image_to_webdev`，不混用分数、排名或发布日期。选择沿用各端已有入口、保存和小程序分享规则；许可证署名不再笼统称所有文本榜都启用风格控制。小程序构建、共享解析与 Windows WPF 交叉编译 / 选择测试通过；小程序减少一行上下预加载以继续满足万行榜单传输上限，滚动窗口和压力测试通过。本机无法连接 Hugging Face，新增数据集分类只用合成数据验证；共享服务尚未成功部署，也未完成双桌面原生视觉对照或 iPhone / iPad 运行验收。

## 移动端子榜与时间位置 — 2026-10-30

可切换子榜的小程序及 iPhone / iPad 榜单将时间移至说明右侧，将子榜入口移至表头的来源名称旁；没有子榜的榜单保留原时间位置。时间说明、加载提示和榜单切换继续可用，截图保留时间与选中子榜。小程序构建和相关交互 / 导出回归通过；本机缺少完整 Xcode，iPhone / iPad 模拟器未验收，微信开发者工具运行验收尚未完成。

## PC 成本与速度表头 — 2026-10-30

Mac 与 Windows 的成本、速度指标表头将名称和单位放在同一行，并为可切换指标的列预留宽度；切换指标不会引起列宽变化。桌面截图沿用同一表格；移动端保留现有两行布局。双桌面原生视觉对照、安装及发布尚未完成。

Mac Debug 编译通过，并在 macOS 27.0.1 采集成本 / 速度、浅深色和 600 / 950 点宽度的 36 张修改后原生帧；查看英文编程速度和中文窄窗口视频成本，表头完整。Windows 共享测试与 WPF Release 交叉编译通过；未取得修改前同夹具截图、Windows 原生截图或对应 CI 视觉产物。

## 多媒体榜单切换（进行中）— 2026-10-30

图片 / 视频增加同来源切换：AA 文生图、图片编辑、文生视频、图生视频、视频编辑；Arena 文生图、单图编辑、多图编辑、文生视频、图生视频、视频编辑。新增语音分类，AA 可切换文字转语音原生声音、受控声音、语音对话和语音转文字流式 / 非流式。词错误率按百分比显示、从低到高排名，公司取最低错误率。子榜选择保存在本地；PC 入口位置以 “PC 子榜切换” 记录为准；小程序分享与 iPhone / iPad 截图保留选择。各来源单独请求、缓存并保留来源排名；图片费用按张、视频按分钟。Arena 单图和多图使用数据集的不同类别，视频编辑接受至少 10 行。未部署共享服务，新增客户端选项依赖对应新服务与采集数据，线上未验证。

本轮完成共享采集及小程序交互回归、Windows 共享测试和 WPF 交叉编译；Apple 共享 Kit 在隔离包中通过图片 / 视频和语音解析测试，Mac 应用及共享引擎编译通过。本机缺少完整 Xcode，iPhone / iPad 完整构建和模拟器未验收；未进行微信模拟器、Windows 原生或双桌面同夹具视觉对照，未安装或发布。Arena 单图 / 多图数据集类别仅有合成数据回归，实时获取未验收。

Epoch 软件工程、其他综合细分及其他讨论的榜单尚未完成。Epoch 领域指数须按其领域基准重新拟合，不能把通用指数当成领域榜筛选。

## 贡献者头像恢复 — 2026-10-30

恢复贡献者使用的本地模型供应商图标；小程序与 iPhone/iPad 共用头像配置和资源，保留个人首字母及 GitHub Actions 图标。小程序构建检查已覆盖配置中的头像，防止资源迁移时遗漏。

## 榜单展开按钮位置 — 2026-10-30

小程序与 iPhone/iPad 的展开和收起按钮均位于前 20 行之后，展开的后续行排列在按钮下方。桌面端按滚动分批加载，没有此按钮；图片导出继续包含全部榜单行，不包含交互按钮。

## OpenRouter 表头入口暂时隐藏 — 2026-10-30

OpenRouter 用量榜固定显示用量，暂时隐藏最右列的价格及速度下拉入口和对应引导；保留底层指标数据和实现，各端及导出一致。AA 指标入口不变。

## 成本、价格和速度表头 — 2026-10-30

AA 与 OpenRouter 切换成本、价格和速度时，表头第一行展示指标名称，第二行展示单位，箭头与第一行对齐；榜单排名和指标数值不变。各端及图片导出展示相同的名称和单位。

小程序的指标按钮始终占用原有 28px 表头内容高度；两行标题和单位在该空间内排列，切换到单行时不扩大或缩小表头。成本切换、表头定位和 16 项图片导出测试通过，小程序隔离生产构建通过。微信官方开发者工具 MCP 不可用，未完成模拟器或真机视觉验收。

## 桌面国家筛选菜单 — 2026-10-29

Mac 国家筛选菜单将国旗显示在国家名称之后，使 “未知” 与其他选项的文字左对齐；Windows 菜单原本只显示国家名称，文字保持左对齐。筛选逻辑和移动端不变。

## 默认隐藏已归档的 Vals SWE-bench — 2026-10-29

编程分类默认仅显示 Artificial Analysis 与 Code Arena；已归档的 Vals SWE-bench 可在来源选择器中手动启用，保留用户此前明确保存的来源选择。各端设置重置恢复该默认值。

## 指标表头首次引导 — 2026-10-29

带指标下拉菜单的来源榜单，首次实际进入并稳定显示时提示点击最右列表头；引导持续显示直至用户点击表头，每个来源仅在点击后独立记录在本地。Mac 和 Windows 使用指向原表头的独立气泡，iPhone/iPad 与小程序使用各自的可见来源状态。隐藏的预加载、未显示的页面和图片导出不消耗引导；提示不改变排名和数据。

## OpenRouter 用量榜指标切换 — 2026-10-29

移除独立价格分类；OpenRouter 用量榜表头切换用量、价格、速度，沿用原用量排名。价格为官方文本基础输入、输出每百万 token 美元报价；速度取同模型可用供应商最近 30 分钟 P50 输出吞吐量中的最高值，无法确定时显示横线。公司行对应榜内用量最高模型的报价与速度，不代表公司平均值。保存的价格分类迁移到用量分类；导出沿用所选指标。

## AA 指标切换表头稳定 — 2026-10-29

Mac 切换分数、成本和速度时保留原生表格及表头的身份和滚动位置；Windows 原位更新表头文字和已生成的可见行，不重建整个面板。移动端交互未变。

## 桌面百分比对齐 — 2026-10-29

Mac 和 Windows 模型名称栏中的相对百分比统一靠右排列，百分比栏宽、色条尺度、显示条件和数值不变；桌面截图导出复用同一视图。本项明确限定 PC，移动端不变。

## 价格榜排序方向 — 2026-10-29

OpenRouter 价格榜默认按输入价格从高到低，点击价格表头可切为从低到高；同输入价格按输出价格排序。排序仅在客户端投影，导出沿用当前方向，不改变 AA 榜单。详见 [price-comparison.md](price-comparison.md)。

## 排名变化服务部署修复 — 2026-10-30

线上共享服务缺少排名比较逻辑，已基于生产代码包仅更新两份服务文件并核对配置未变；现有的小程序、iPhone/iPad、macOS、Windows 及图片导出继续消费共享结果。修复包通过 6 项排名回归，线上 Arena 文本与编程榜正常刷新，但来源日期未变化，没有新的可确认升降，尚无真实升降的端到端验收。小程序模拟器、Apple 设备和 Windows 原生运行及截图本轮未验证；无需为此安装或重新发布客户端。部署和备份详情见 [shared-leaderboards.md](shared-leaderboards.md)。

## AA 指标切换保持榜单顺序 — 2026-10-28

AA 表头切换分数、成本或速度只改变显示指标，模型及公司始终保持原能力榜顺序，缺失值不改变位置；相关导出一致。此前关于成本和速度重新排序的记录为历史行为，以本节为准。

## PC 榜单分批显示 — 2026-10-28

macOS 和 Windows 榜单初始生成前 20 行，向下滚动到已加载部分时每次追加 20 行；榜单切换、搜索、筛选和排序重新从首批显示。底部分布仍位于榜单之后，排名、完整搜索与排序仍基于全部数据。两端将成绩、成本和速度的最大值从逐行重复计算改为每次列表计算一次。此项明确限定 PC，小程序、iPhone/iPad 不变。长榜原生夹具同步验证首批、后续批次、末尾和回到顶部；Windows WPF 交叉编译及共享测试通过，原生 Windows 截图和运行验收仍需 Windows 环境。Mac 源码已通过语法解析；完整构建和原生截图待原生构建锁可用后验证，本轮没有安装或发布。

## AA 速度指标 — 2026-10-28

AA 综合表头提供 token/秒，编程表头提供秒/任务；与分数、成本互斥，保留原排名，缺失排末。各端及导出共用同一来源数值。图片和视频榜不推断匹配速度。详见 [price-comparison.md](price-comparison.md)。

## Vals SWE-bench Verified — 2026-10-29

编程分类新增 Vals AI 官方榜，保留模型与代理组合及原始排名。表头切换成绩、每次测试美元成本与每次测试耗时（秒），各端与导出沿用来源顺序。官方已归档该榜，不再评测新模型；来源更新时间为页面公布日期，界面注明归档。共享服务和 Apple 直接采集均从官方 HTML 解析，缺失成本或耗时显示横线。

## 价格分类和 AA 成本视图 — 2026-10-28

按用户后续要求，价格分类位于用量与综合之间，只接 OpenRouter 文本 API 报价，models.dev 仍用于现有模型详情。AA 综合、编程、图片、视频在成绩表头切换成绩或成本，色条以同榜最高成本为基准；图片按张、视频按分钟，两个榜单的 API 报价并非编程评测的任务平均值。来源、数据口径及验证见 [price-comparison.md](price-comparison.md)。以下先前 AA 编程记录描述的是当时的双行展示方案，已由本节替代。

## AA 编程每任务成本 — 2026-10-28

服务端与 Apple 直接采集保留 index 级 `mean.costUsd` 为可选 `taskCostUSD`，通过离线快照、公司最强型号投影和 Windows Swift 桥接传递。小程序、iPhone/iPad、macOS 与 Windows 同步展示原成绩和美元/任务成本，支持成本升序/成绩降序；原能力排名及变化保留，缺失排末，零为有效价格。费用变化推进内容时间，其他元数据和原成绩语义不变。相关导出复用相同顺序、原能力名次和费用；单位及口径说明三语一致。详见 [coding-task-cost.md](coding-task-cost.md)。

共享原生夹具新增三语、模型/公司、成绩/成本顺序以及零/缺失/小额费用场景。本轮本地验证记录位于忽略目录 `work/coding-cost/`；各端具体检查、原生运行和交付边界在该目录和费用说明中记录，不将交叉编译视为 Windows 原生视觉验收。

验证：220 项小程序测试及生产构建、Windows 共享测试/WPF Release 交叉编译、Mac 应用/桥接 Debug 构建通过；临时清单编译实际源码的 19 项 Kit 回归与 2 项移动端投影/冻结导出回归通过，iOS 完整视图仅做语法解析。Mac 前后各 72 帧，24 组刷新/稳定内容区域一致；前置二进制未确认与基线源码严格匹配。缺少 Windows 原生/DPI 及匹配 CI 视觉产物、微信和 iPhone/iPad 原生运行；未部署、安装、上传或发布。

后续按用户要求部署了服务端编程成本解析并刷新线上快照；公开发行仍待原生视觉审核。当前运行的本地 Mac 构建包含成本排序代码，用户需刷新编程榜读取新快照。详情见费用说明。

## Shared provider images and local PNG removal — 2026-10-28

Supplier artwork comes from shared snapshot PNG data across Mac, Windows,
iPhone/iPad, the mini-program and leaderboard exports; missing images use
initials. The 53 local supplier PNGs, the local company-image catalog and
native favicon fallback are removed. The mini-program build retains only the
shared catalog's identity rules; embedded server artwork is excluded. Native
quota fixtures include the same provider initials for missing-image states. The traceable Tabler GitHub resource
remains for repository buttons and contributor UI. Desktop quota cards reuse
manufacturer images across all cached boards with stable provider-kind keys;
model marks and account display names cannot select a provider image. The
newest valid manufacturer image wins and persists with the snapshot offline.
Providers absent from cached boards use initials until a shared mark arrives.
models.dev metadata does not supply these images. Remote artwork rights are
tracked separately from the removed local assets; see third-party-notices.md.

Backend coverage follow-up (2026-10-28): 52 of the 53 removed supplier
identities already had server-catalog PNGs. Video Rebirth was missing and is
now covered by its official favicon, with source/output hashes and an explicit
unconfirmed artwork-permission record. The backend catalog contains 62
provider marks and 7 model marks. All clients and exports consume this data
through the existing shared image fields; no client-local resource is restored.
An independent 53-provider acceptance inventory covers cold reads, unavailable
storage and cached snapshots. All 52 focused tests pass (including 3 new coverage
checks), and generated policy validation passes. This source update has not been deployed and
has no new client installation or native visual acceptance claim.

Validation: 214 mini-program tests and production build pass; its output
contains no server-catalog PNG data. Eight shared-domain tests and four source
mark/contributor generation tests pass. A reduced native manifest links the
actual Kit/Core/Bridge sources and tests without the unavailable iOS macro
target: all 37 selected tests pass, including provider identity, model versus
manufacturer separation, company aggregation, malformed/missing images,
newest cached image selection and offline snapshot persistence. Windows shared
tests and WPF Release
cross-compilation pass (zero warnings/errors); the incremental output logo
folder contains only GitHub. Mac application and bridge Debug builds pass.
The iPhone/iPad shared view passes syntax parsing only; full Xcode is absent.

Ignored `work/shared-brand-assets/` contains the synthetic fixture and 48 real
Mac before/after frames in English, Simplified and Traditional Chinese,
including company rows (950×720 content points, 2× backing scale, macOS
27.0.1). Shared quota/row images and initial fallbacks are visible and aligned;
only the native scrollbar changes between after-state frames. The baseline
binary was reused and is not source-matched; the after binary was rebuilt
during this task. Unrelated timestamp changes continued in the same checkout
during verification, so the captures are not presented as a complete current
repository build or an isolated comparison of all visible changes.
Native Windows/DPI screenshots, a matching cross-platform CI artifact, mobile
runtime/export verification and installed-client acceptance remain unavailable.
No client was installed, uploaded or published.

# 跨端变更与验收

千问重新登录后关窗刷新（2026-10-28）：Mac 原流程在手动关闭登录窗口时取消读取、直接结束，可能把余量条留在旧的 “登录失效”。现在关窗后先显示查询中，再使用同一 WebKit 会话重新进入官方余量页，最多等待 25 秒；只有实际读取到余量或官方无套餐信息才保存连接状态，未登录及加载失败继续显示真实错误。后台余量刷新不再导航打断登录，重新打开登录会取消上一轮关窗校验，旧刷新结果不能覆盖较新的千问查询 / 余量状态。Windows 同步在关窗后使用原 WebView2 会话有界重读，并通过会话代次阻止旧异步回写和旧后台读取隐藏新登录窗口。无 Cookie / Token 导出或 CLI 凭据变更；小程序、iPhone/iPad 和榜单图片导出没有账号登录余量消费者。Mac 使用实际 AppKit 窗口和合成 WebView，6 项新增测试覆盖 9 个登录 / 失败 / 超时 / 竞态用例，连同 7 项已有 xAI 刷新回归，共 13 项测试、2 个套件通过；隔离清单编译实际 Mac 应用与 Core，未称为完整 iOS / SwiftUI 包测试通过。Windows WPF Release 交叉编译零警告 / 错误。日志和源码哈希位于忽略目录 `work/qwen-login-close/`；没有使用真实千问账号验收，没有 Windows 原生运行及对应 CI 视觉产物，也没有本轮截图、安装、上传或发布。

未订购套餐隐藏日期（2026-10-28）：修正共享 `AccountQuotaFormatting` 中 xAI 已确认未订购仍拼接历史期末日期的分支，卡片和帮助仅保留 “未订购” / “未訂購” / “Not subscribed”，日期不再影响颜色；历史账号记录继续保存，已订购及待核实状态沿用现有日期规则。Mac 直接消费共享格式化，Windows 通过同一 Swift 引擎接收 runs / help / 颜色；小程序、iPhone/iPad 和榜单图片导出没有账号余量消费者。同步旧日期断言及 Windows 原生夹具，409 项共享 Core 回归、Windows 共享测试、Mac 应用与桌面共享引擎 Debug 编译通过；Core 回归通过隔离清单编译实际共享源码，未将它称为包含 SwiftUI 的完整包测试通过。相同三种状态 / 三语 / 浅深色夹具前后各 54 张 Mac 原生截图，查看简中浅色及英文深色未订购结果；已订购与待核实卡片的日期区域像素未变，18 组刷新 / 稳定日期区域一致，证据位于忽略目录 `work/quota-unsubscribed-date/`。无 Windows 原生运行环境及对应 CI 视觉产物，WPF 显示效果未验收；未安装、上传或发布。

PC 奖牌与排名变化间距（2026-10-28）：Mac 移除奖牌及排名组的向下偏移，增加 1pt 上下间隔；替换 28pt 系统表头为 34pt 自定义表头时同步修正位于顶部的滚动位置，避免第一行被裁掉 6pt。Windows 在原有 32 DIP 行内固定预留 22 / 1 / 9 DIP 的奖牌、间隔、变化区域，保留 17 DIP 奖牌圆面及内部字号。两端列宽和行高不变，移动端保持现状，共用桌面榜单视图的图片导出同步。Mac Debug 和 Windows WPF Release 编译通过；Mac 七个排名夹具、浅深色显示 / 刷新 / 稳定共 42 帧，已查看单榜模型、三榜繁中、双榜公司和单榜公司，证据在忽略目录 `work/rank-desktop-clearance/final/`。前后截图期间其他对话调整了品牌资源和许可文案，因此不将全图差异视为本项变化。没有 Windows 原生运行环境及对应 CI 视觉产物，WPF 原生视觉尚未验收；未安装、上传或发布。

移动端首帧加载态（2026-10-28）：小程序及 iPhone/iPad 将 “没有缓存且尚未请求” 的榜单视为加载中，首次进入和切到未请求来源时立即使用现有骨架屏，避免先闪出柱状图空态；实际请求仍按原来的懒加载、合并与退避规则执行。请求失败后退出骨架屏，保留原失败/待配置提示；有缓存直接显示榜单，刷新期间保留列表，筛选无结果仍显示空态。图片导出继续排除加载 UI，桌面不在本次明确的移动端范围。小程序 213 项回归与生产构建、9 项 iOS 构建脚本检查及 Swift 源码语法检查通过。当前缺少完整 Xcode 和可用官方微信 MCP，未完成微信、iPhone/iPad 原生运行及视觉验收，未安装、上传或发布。

iPhone/iPad 发布暂停（2026-10-28）：共用 `config/app.json` 显式设置 `releaseIOS: false`，两种设备属于同一应用、同一发布开关。发行归档入口在任何 SDK/签名调用前检查开关，缺省也关闭；普通构建、模拟器测试和本机开发安装不受影响。现有 iOS CI 没有商店上传任务，tag 发布继续仅启用 macOS；Windows 发布仍关闭。配置类型及关闭/缺省阻断、显式启用恢复归档的隔离回归通过；未执行真实签名、归档、安装或商店发布。

GitHub 图标来源修复（2026-10-28）：按用户建议选用 Icones 的 `tabler:brand-github-filled`，原始 SVG、MIT 正文及固定上游修订 / 哈希放在 `assets/brand/partners/github/`。`Scripts/source-logos.mjs` 统一生成原有 `assets/logos/github.png`，macOS / Windows 仓库按钮，以及小程序 / iPhone / iPad 共用的贡献者头像与导出保留原引用。Mac 离线声明增加 Tabler，Windows 直接打包源许可，两端移动客户端共用更新后的品牌声明。4 项生成 / 校验 / 贡献者测试、小程序生产构建及实际打包文件核对通过。复用已有 Debug 二进制，仅在忽略的原生测试应用内替换前后图标资源，使用同一 850×720pt 合成夹具采集 Mac 浅深色显示 / 刷新 / 稳定帧，2× backing scale，证据在 `work/github-icon/`；不将这项资源验证称为当前全部源码重新编译通过。Windows 原生截图、iPhone / iPad / 微信运行验收及客户端安装 / 上传 / 发布尚未完成。其他供应商品牌 PNG 的来源与授权状态见 `docs/third-party-notices.md`，本次未将它们标记为已授权。

全端日期版本（2026-10-28）：公开版本统一为 `config/app.json` 的 `20261028`，小程序、iPhone/iPad、macOS 和 Windows 共源；发布脚本默认用北京时间当天日期，同日重复准备保持版本不变。Apple 元数据映射 `2026.10.28`，Windows 数字资源映射 `2026.10.28.0`，公开版本、Git 标签和安装包名使用八位日期。日期/配置/发布/隔离上传/iOS 项目及工具边界 55 项、小程序 211 项回归与生产构建通过；Windows 共享验签/升级测试和 WPF Release 交叉编译通过，实际程序集/文件版本与公开产品版本已核对，PowerShell 安装器脚本语法及日期转换通过。macOS plist 和生成 iOS 工程元数据校验通过，iOS 源码语法通过；本机缺少完整 Xcode，未完成 iPhone/iPad SDK 构建。未执行本轮 Mac 应用打包、Windows 安装器生成、各端原生运行/视觉或安装验收；未上传或发布。已发布 Homebrew Cask 继续指向真实旧版附件，后续正式发布由生成器更新，不伪造新日期包及校验和。

关于入口点击样式（2026-10-28）：小程序榜单底部 “关于” 按钮关闭微信默认灰色按下态（`hover-class="none"`），单独增加左右各 12rpx 内边距和至少 44px 宽度；沿用 44px 最小高度与原打开关于行为。90 项页面测试及小程序生产构建通过；实际模板与 CSS 的浏览器夹具检查 320/375/560px 浅深色六种布局，按钮背景透明、内边距有效，点击区至少 44×44px。iPhone/iPad 现有对应入口使用 `.plain` 样式及最小 44×44pt 点击区域，本轮无须改动；桌面与榜单图片导出没有此 “关于” 按钮。官方微信 MCP 当前不可调用，未完成微信原生按下态及真机运行验收，未上传或发布。

前三名奖牌放大（2026-10-28）：小程序奖牌从 23rpx 调到 40rpx（375px 视口下 11.5→20px），普通名次数字保留原字号；iPhone/iPad 及共用视图导出使用 20pt 奖牌，Mac 使用适合现有行高的 18pt 与固定排名布局，Windows 将奖牌圆面从 13 增到 17 DIP、内部名次从 9 增到 10。列宽、行高、颜色及变化标记沿用原规则。小程序 Canvas 原本使用数字排名，本次不增加新图标。小程序 211 项回归和生产构建、Mac Debug 与 Windows WPF Release 编译通过；iOS 仅完成语法检查。实际模板浏览器量测 320/375px 浅深色，奖牌及变化均在原列宽和 48px 行内，375px 下两者间距 2px。Mac 同一单榜模型/公司夹具采集浅深色前后帧，保存在忽略目录 `work/rank-medals/`；无 Windows 原生环境、完整 Xcode 或可用微信 MCP，三者原生运行及客户端安装尚未验收，不以构建代替。

排名列变化展示（2026-10-28）：小程序、iPhone/iPad、桌面及相关导出改为排名在上、变化在下，保持总宽与行高；红色 `↑n`、绿色 `↓n`、灰色 `—`、蓝色 `新` / `New`。桌面多榜在各来源内部显示独立排名和变化，首榜沿用原排名列，后续榜单从名称列内预留排名宽度，避免混用来源。小程序中性状态由模板补横线，桥接数据保留空串及省略无效 tone 的紧凑表示，不增加万行虚拟列表载荷；四位变化数字使用较小字号。懂车帝官方销量页跳转登录，公开检索没有核实其 App 新上榜样式，暂沿用本产品现有新标记。

全平台复核（2026-10-28）：模型与公司变化、四类服务端写入、Windows 共享桥接及各端导出数据路径均已核对；Apple 共享标记和小程序 Canvas 的新上榜蓝色统一为浅色 `#3276CA`、深色 `#89BBFF`。macOS / Windows 多榜改为各榜排名与变化上下排列，原生列结构、总宽和行高不变，名称区预留 36pt / 40 DIP。新增三榜繁中及双榜公司原生夹具，各来源使用不同变化以检查混用。小程序 211 项测试、排名数据 6 项测试、生产构建、Mac Debug 和 Windows WPF Release 交叉编译通过；iOS 语法检查通过。Mac 采集七个排名场景、两种主题的显示/刷新/稳定共 42 帧，已查看双榜英文、三榜繁中深色与双榜公司浅色，证据保存在忽略目录 `work/rank-all-platforms/`。缺少 Windows、iPhone/iPad 和微信原生运行环境，未完成对应原生运行验收、双桌面 CI 视觉对照或客户端安装与发布。

本轮验证：小程序 211 项测试及生产构建通过，Canvas 回归核对排名/变化同列上下排列、红涨绿跌和行高；实际模板浏览器预览检查 320px 英文、375px 简中及浅深色，包含 `New`、持平与四位变化。Swift 实际共享源的 Codable/公司投影/箭头/横线/极端整数回归通过，iOS 语法检查通过；macOS Debug 编译及 Windows WPF Release 交叉编译通过（Windows 零警告/错误）。Mac 相同多榜夹具前后各 36 帧，新增单榜模型与公司场景 12 帧，2× backing scale；查看长名称、新/持平及两种主题，刷新与稳定帧一致，抽查原共用排名列像素不变。截图及元数据位于忽略目录 `work/rank-column/`。本机缺少官方微信 MCP、完整 Xcode 和 Windows 运行环境，尚未完成微信、iPhone/iPad 或 WPF 原生运行验收，也未取得对应双桌面 CI 视觉产物；未安装、上传或发布客户端。

合影大图横屏配置（2026-10-28）：用户明确反馈微信小程序点开 “跨世纪的同框” 大图后，横置手机没有旋转。关于页补充 `pageOrientation: auto`，保留 `wx.previewImage` 的原生缩放、保存与转发入口；旋转时重新读取状态栏高度（允许横屏为 0）和品牌标题尺寸，并让出左右安全区。新增三语竖屏→横屏→竖屏回归；小程序 208 项测试及生产构建通过，产物确认保留自动方向配置。官方 wechatide-skill 0.3.11 在规范项目的模拟器成功打开关于页，读到正确合影标题与布局数据，console 未匹配到 error。本轮没有手机真机，尚未验证微信原生图片预览随物理方向旋转；不以配置或模拟器结果宣称真机验收通过。未上传或发布。原生 iPhone/iPad、macOS、Windows 及榜单图片导出不在本次明确限定的修复范围。

小程序 “功能说明” 弹窗按钮按从左到右排列为 `OK`、`PC 端链接`（繁中 `PC 端連結`，英文 `PC link`）。三语均用 `OK` 关闭，仅点击右侧链接按钮复制桌面下载地址。此双按钮顺序针对小程序已有的弹窗，原生客户端单按钮帮助弹窗不增加链接操作。

小程序和 iPhone/iPad 的 “关于” 页移除数据来源模块。协议随点击榜单名称打开的说明弹窗展示，macOS / Windows 同步入口：Epoch 和 Arena 数据集保留署名并附完整 CC BY 4.0，OpenRouter / Vercel 保留当前快照来源说明和完整协议；腾讯云只显示来源及权利说明，AA 和旧 Arena 不推定开放许可。协议离线可读，桌面简短悬浮提示不装入整份协议；第三方软件许可仍在原位置，图片导出不增加弹窗。

本次协议迁移验证（2026-10-26）：小程序 199 项测试及构建通过；macOS Debug 编译、Windows 共享测试及 WPF Release 交叉编译通过。iOS 仅完成源码语法检查，未运行 iPhone/iPad UI 测试。独立清单运行实际 Kit 目标为 116/117，通过本次新增协议测试；剩余 `CloudBaseUsageTests.swift:26` 仍期待旧时间说明，默认说明路径与本次改动前一致，未改写这条不相关断言。当前环境无完整 Xcode / Windows 原生运行环境，开发者工具 CUA 捕捉失败（ScreenCaptureKit -3811）；没有本次原生前后截图、双桌面视觉验收或安装验收，不据编译结果宣称界面已验收。

产品优化默认以相关客户端为范围。iPhone / iPad 属于同一应用但必须分别检查窄屏和宽屏。实施前从下表定位消费者；完成时记录本次改动的实现、自动检查、原生验收和安装状态。用户明确限定平台时尊重限定。平台差异应解释理由，不能静默漏改。

一般改动默认同轮落实所有相关端，不逐端征求确认。PC 和移动端以相同产品目标分别适配，不能机械复制界面；常规适配自主完成。只有是否适用、兼容性或产品取舍确实拿不准时，提出具体问题、可选方案、影响和建议，再由人工决定。该默认原则由 Calmmit 的共享 AGENTS.md 和审查入口共同维护。

| 能力 | 共用来源 / 生成入口 | 消费者与核验入口 |
| --- | --- | --- |
| 全端版本号 | `config/app.json`、`Scripts/app-version.mjs` → `Scripts/bump-version.sh [YYYYMMDD]` | 小程序、iPhone/iPad、macOS、Windows 公开版本和发布标签/安装包名统一八位北京时间日期；Apple 元数据映射 `year.month.day`，Windows 数字版本映射 `year.month.day.0`。普通构建读取共用版本；同日准备幂等，拒绝回退和小程序单端覆盖；更新比较兼容已安装旧语义版本。`app-version`、`app-config`、`release`、`ios`、`weapp-deploy` 及 Windows 共享测试覆盖 |
| 共用英文标题、移动标题与导出标题 | `assets/brand/mobile-title.json` → `node Scripts/sync-mobile-brand.mjs` | 小程序 `core/brand-title.js`、SVG / Canvas；iOS `MobileBrandTitle`（主界面、关于、导出）、Mac `EnglishBrandTitle` 及 Windows WPF `EnglishBrandArtwork` 的英文标题。`Scripts/mobile-brand.test.mjs` 检查副本、WPF 嵌入资源与几何；Swift `MobileBrandTitleTests`、`MobileBrandSizingTests`；原生 `testSharedMobileWordmarkInEveryLanguageAndTheme` |
| 桌面标题与图标 | `assets/brand/`、`Scripts/brand-assets.swift`、`Scripts/ios-icon.swift` | Mac `EnglishBrandTitle` / `ChineseBrandTitle`；Windows WPF 标题。桌面英文标题共用 iOS 离线字形、字距和 31° 网络 A 倾斜；中文桌面标题保留原生布局；正式图标和标题网络图仍共源。遵循 `docs/visual-comparison.md` 的双桌面截图要求 |
| OpenAI 套餐与额外额度 | Core `CCSwitchQuotaParsers` / `AccountQuotaFormatting`、`OpenAIManagedQuotaSource` | macOS 余量条与菜单栏、Windows 共享引擎余量条与托盘；任一套餐窗口耗尽时显示 credits 余额，无限 / 未返回数字分别显示状态，缺少 credits 则保留百分比。缓存与路由投影保留余额；`OpenAICreditsTests` 和三语双主题 `openAICredits` 原生截图场景。小程序、iPhone/iPad 及榜单图片导出当前不展示账号余量，不新增该能力 |
| 模型 / 公司排行、地区与开源规则 | `fc/domain.mjs`、`fc/leaderboard-policy.json`、`fc/brand-catalog.json`、`Scripts/generate-leaderboard-policy.mjs` | `Sources/LeaderboardKit`、小程序 `core/leaderboard.js`、Windows 共享引擎；同时检查筛选、公司聚合、离线缓存和图片导出 |
| 排名变化 | 服务端 `withRankChanges` 在写入前对比旧快照，行内 `rankChange` / `companyRankChange` 随新快照保存 | 小程序、iPhone/iPad、macOS、Windows 及各端导出：上升红色 `↑n`、下降绿色 `↓n`、持平 `—`、蓝色新入榜 `新` / `New`。排名和变化上下排列，总宽、名次、行高不变；桌面多榜的每个来源独立显示排名和变化，后续榜单从原名称列内预留排名区。公司独立计算，无基线不误报；重复抓取保留标记，下次数据变化重新比较。JS 服务端与小程序/导出回归、Swift Codable/公司投影回归；共同原生 `rankChanges` 夹具覆盖三语、深浅色、单榜模型、三榜模型及双榜公司布局 |
| 来源标志、主题与关于页 | `assets/brand/partners/`、`Scripts/source-logos.mjs`、`Sources/LeaderboardKit/Resources/SourceTabThemes.json` | 小程序榜单 / 导出，iOS 来源标签 / 导出，Mac / Windows 标题与来源说明；深浅色和离线资源分别验收 |
| 表头榜单简介 | Kit `LeaderboardPresentation.sourceHelp` / `LeaderboardKind.sourceURL`、小程序 `core/catalog.js`、Windows 既有来源说明与 URL | 小程序、iPhone/iPad、macOS、Windows 点击表头名称打开该榜单简介，展示官方链接并提供显式复制链接操作；打开或关闭简介不写剪贴板。小程序 `page.test.mjs` 核对三语、全部类别、两种分组、复制与手势防误触；静态图片保留标题，不增加交互 |
| 发布时间、刷新时间和刷新反馈 | `fc/domain.mjs` / `fc/service.mjs` 持久化 `contentUpdatedAt`，Kit `LeaderboardContent` / 时间策略、小程序 `core/freshness.js`、`Tests/fixtures/content-timestamps.json` 与日历夹具 | 小程序榜单与 Canvas、iOS `LeaderboardPadView` 与导出、Mac / Windows 时间文案。移动下拉检查起始 / 加载 / 完成三态；桌面保留原生刷新交互 |
| 搜索、筛选与来源切换 | Kit 排行投影 / 过滤策略、小程序 `pages/leaderboard/index.js`、iOS `LeaderboardPadStore` / `LeaderboardPadView` | 两移动端分别搜索模型名 / 聚合后的公司名并保留独立关键词，核对搜索清除、空结果、来源 / 类别 / 公司切换、筛选保留和导出；魔方来源不循环，越过末榜进入下一类别首榜，越过首榜进入上一类别末榜，仅类别首尾循环；桌面核对对应筛选与投影，平台专属交互不硬搬 |
| 文案、许可与应用说明 | `config/app.json`、`Scripts/sync-app-description.mjs`、共享 Kit 本地化与离线许可 | 三种语言；各端主界面、关于、导出与应用元数据。不能只更新一个语言或一处显示 |
| 显示榜单 | Kit `DesktopBoardSelection`、小程序 `core/board-selection.js`；各端按分类保存 | 小程序设置页、iPhone/iPad `LeaderboardSettingsView`、桌面既有榜单选择器。默认全选，每类至少一榜，移动设置的重置恢复全部；移动单榜隐藏顶部 tabs 及占位，魔方跨分类按可见来源计数；排行、分布图、刷新和导出仅消费可见榜单，小程序分享保留显示选择 |
| 分布图数值对齐 | Apple `LeaderboardDistributionCharts`、Windows `DistributionValue`、小程序 `.distribution-value` | 国家占比和源码占比均拆为数量、分隔符与百分比三列；百分比固定 42pt / DIP / px 并右对齐，数量单独右对齐，保留等宽数字。macOS / Windows 面板截图复用界面；小程序 Canvas 和 iOS 排名导出不含分布图，不增加额外图表 |

分布图数值对齐验证（2026-10-27）：小程序 204 项测试及生产构建通过；官方 `wechatide-skill` 在规范项目的模拟器中确认 25 个百分比单元格均为 42px，同一图表内国家与源码数量的右边缘一致，实际截图覆盖 3.7%、33.3%、55.6% 等不同位数。macOS Debug 构建通过；相同夹具、视口及 2× backing scale 下，简中单榜、繁中窄三榜、英文双榜的深浅主题分别采集修改前后 shown / refreshed / settled，各 18 帧；检查 0.0%、5.0%、95.0%、100.0% 的对齐和窄布局，未见数值裁切。首帧前后像素一致；本次采集的刷新与稳定帧差异仅在右侧滚动条。截图、夹具、源码哈希、元数据与日志保留在忽略目录 `work/distribution-columns/`。Windows WPF Release 交叉编译零警告/错误，缺少 Windows 环境，未进行 WPF 原生截图验收或安装；iPhone/iPad 共用 Apple 修正，但本机缺少 Xcode，未进行 iOS 构建、模拟器或真机验收。未运行双桌面 CI 视觉对照或发布客户端。
| 切换动效 | 小程序 `core/board-transition.js`、Apple `LeaderboardSwitchStyle` / `CubeFace` | 小程序与 iPhone/iPad 设置提供魔方、滑动、淡入淡出预览卡，默认魔方并本地持久保存；用于单榜视图的手势和标签切换，共用来源边界、跨分类导航、滚动对齐。分享保留接收方动效偏好，显示榜单重置不重置动效。减少动态效果时改为轻量淡入淡出并停用预览动画。iPad 宽屏和 Mac / Windows 的并列榜单保持原布局，静态导出无动效。JS `board-transition` / `settings` / `share-state` / `page` 测试及 Apple `LeaderboardCubeTests` 覆盖 |
| 模型详情 | Kit `ModelDetails` / `ModelDetailsView`、小程序 `core/model-details.js`；Windows 消费共享引擎的详情投影 | 小程序、iPhone/iPad、macOS、Windows：优先展示限额与能力卡片，模型资料、服务商价格和来源可展开查看，保留全部字段与显式复制操作；滚动后提供返回顶部。同步时间按设备本地时区显示 `yyyy-MM-dd HH:mm:ss`，保留秒数；固定截图夹具使用 UTC。图片导出不包含交互详情页 |
| 各端进展与贡献 | 小程序 `core/about-platforms.js` → `Scripts/ios-about.mjs`；微信图形 `assets/brand/partners/wechat/logo.svg` → `Scripts/source-logos.mjs` | 小程序与 iPhone/iPad 关于页，替换原 “余量查询” 卡片；固定七端功能及状态，每端单行显示图标、名称、功能和状态 Tag（无圆点）；七端图标统一为中性灰线框样式，微信保留品牌双气泡与四个圆点；iPad 平台名称三语均显示为 iPadOS，iOS 标注 “（含 iPhone Duo）”。列表下方统一显示可复制仓库链接的 “欢迎贡献代码”（英文 PR welcome），各端无独立链接，macOS 状态同样使用 Tag；桌面 About 和图片导出没有原移动卡片，不新增模块 |
| 成本与工程投入 | Calmmit `cost-calculation.mjs`、`engineering-investment.mjs`、`resources/CostCalculation.swift` | 小程序与 iPhone/iPad 关于页。构建入口同步 JS / Swift 计算适配器；Git 统计、月份取整、按月累计和合计由 Calmmit 维护，项目预算、文案与 UI 独立维护。桌面及图片导出当前没有该成本区 |
| 贡献者圆团 | Calmmit `contributor-circles.mjs` → `Scripts/contributor-circles.mjs`、小程序 `core/contributors.js` → `Scripts/ios-about.mjs` | 小程序与 iPhone/iPad 关于页，提交次数、代码行数、圆团从左至右同一行排列，缩窄前两项为圆团留出宽度；行高由数字卡片决定，圆团保持原尺寸、底边对齐并向上超出数字行，不参与撑高；点按放大后可选择贡献者查看次数，详情仅显示姓名与提交次数。按 Git 作者名保留模型版本，使用本地标志，Cloyd Lau 默认字母 C。统计、归一化圆形布局与自包含 SVG 图片生成由 Calmmit 共用，产品端只呈现布局。桌面及榜单图片导出没有该关于区，不新增模块 |
| 关于页 AI 合影 | `assets/about/ai-models-group-portrait.jpg`、小程序 `core/about-artwork.js` → `Scripts/ios-about.mjs` | 小程序与 iPhone/iPad 关于页简介下方完整展示合影；署名改编作者 tombkeeper（作品原帖）和历史原图摄影者 Benjamin Couprie（1927 年第五届索尔维会议，附原图来源）。作者名使用下划线，图标置于姓名前且与姓名共用同一个出处链接，不另加可见的链接操作文案；小程序点按复制对应地址，原生直接打开。支持大图预览。小程序构建同尺寸 quality 86 JPEG，iOS 项目从同一目录打包原图；三语、深浅色及窄屏分别检查。桌面只有许可窗口，没有独立关于页；榜单图片导出不包含关于页内容 |

基础设施年度预算见 [预算说明](infrastructure-budget.md)。金额估算不细于百元，允许项目采用千元、万元等更粗粒度；各移动端从同一份预算定义生成金额与说明。费用为估算，非实际账单。

关于页 AI 合影验证（2026-10-27）：原始随机文件名改为 `assets/about/ai-models-group-portrait.jpg`，原图 SHA-256 不变。小程序生产构建及 8 项关于页/生成内容检查通过，另核对三语图片预览调用、出处复制、生成数据一致性与 iOS 项目资源路径；小程序图片 311,458 字节，完整产物 1,974,208 字节，低于 2 MiB。Swift 关于页源码语法检查及 2 项项目生成检查通过。使用实际卡片 CSS/文案的浏览器排版夹具核对 320/375px、浅深色，无裁图或溢出；这不是微信原生运行截图。官方微信 MCP 当前未提供，CUA 捕捉返回 ScreenCaptureKit -3811；iOS 构建入口确认本机缺少完整 Xcode SDK，未完成微信模拟器、iPhone/iPad 原生 UI 或真机安装验收。桌面及榜单图片导出没有对应关于页消费者，不涉及；未上传或发布版本。

合影署名修正（2026-10-27）：按用户要求改为 tombkeeper 的个人主页署名，保留单独的原帖图标；补充 Benjamin Couprie 及 1927 年第五届索尔维会议历史原图来源。作者名加下划线，不再显示平台名称或 “复制出处链接” 操作文案。小程序构建、8 项关于页/生成内容检查、三语署名与三类链接目标核对及 Swift 源码语法检查通过；iPhone/iPad 消费同一份署名数据。320/375px 浅深色浏览器排版已查看，未完成新的微信或 iOS 原生运行/安装验收；桌面及图片导出不涉及。预览及检查记录保存在忽略目录 `work/about-artwork-preview/`。

微博图标补充（2026-10-27）：tombkeeper 原帖入口改用 Simple Icons 微博图标，小程序和 iPhone/iPad 共用本地浅深色 PNG；原生大图工具栏同步使用该图标。作者名下划线及两级作者出处保留。10 项相关测试、资源一致性检查、小程序构建及 Swift 语法检查通过；已查看生成图标。主包 1,979,944 字节，低于 2 MiB。既有生成器重导出的 14 张 PNG 仅有编码/元数据变化，逐张解码确认像素不变。未完成新的微信/iOS 原生 UI 或安装验收，桌面和榜单图片导出不涉及。

合影信息精简（2026-10-27）：小程序与 iPhone/iPad 标题及配文合为一行 “跨世纪的同框 · 1927 × AI”（英文 Across a century），出处与原图署名合为另一行；“改编” 改为 “出处”。保留作者下划线、微博原帖图标及摄影者原图链接，会议名称和年份保留在链接的无障碍说明中。8 项关于页/生成内容检查、小程序构建与 Swift 语法检查通过；三语共享内容一致。浏览器夹具核对 375px 简中浅色、英文深色及 320px 繁中浅色，标题和署名均保持单行，两位作者名无截断；已查看预览。这不代表微信或 iOS 原生 UI 验收，本轮未安装客户端；桌面及图片导出不涉及。

原图出处图标（2026-10-27）：小程序与 iPhone/iPad 在 Benjamin Couprie 右侧增加索尔维研究所官网头像，保持原始色彩，深色模式增加浅底衬托；图标链接官方会议相册，摄影者姓名仍链接原图记录。图标身份、链接和三语无障碍说明维护在共享合影数据；正式源图及来源记录位于 `assets/brand/partners/solvay/`，经共用导出器离线打包。导出时移除 PNG 密度元数据，既有图标字节保持不变。10 项关于页/资源导出检查、小程序生产构建、导出一致性及 Swift 语法检查通过；浏览器夹具查看 375px 简中浅色、英文深色和 320px 繁中浅色，出处保持单行，姓名完整显示。尚未完成微信及 iPhone/iPad 原生 UI 验收，本轮未安装客户端；桌面及榜单图片导出无对应消费者。

合影信息条重排（2026-10-27）：小程序与 iPhone/iPad 将标题与两组出处合为一个行内信息区，标题居左；出处角色使用小字置于姓名上方，姓名与来源图标在同一行垂直居中。移除分割线、右侧放大按钮和共享的 “1927 × AI” 配文，仍可点击图片预览大图。空间不足时整个信息区自然换行，避免裁剪姓名；iOS 用 ViewThatFits 保留原生排版。8 项关于页/生成内容检查、小程序生产构建及 Swift 语法检查通过；375px 简中浅色、英文深色和 320px 繁中浅色浏览器预览已查看，姓名与图标中心一致。微信官方 MCP 未提供，CUA 原生捕获仍报 ScreenCaptureKit -3811；iPhone/iPad 缺少完整 Xcode，未完成原生运行、截图或安装验收。桌面和榜单图片导出无此模块，不涉及。

右侧署名两行（2026-10-27）：按后续要求，小程序与 iPhone/iPad 将出处、原图置于标题右侧，上下两行显示；每行标签、作者名与来源图标水平排列。作者名缩至 10px/pt，图标外框同为 10px/pt，标签 9px/pt；文字和图标垂直居中，两行姓名及图标列分别对齐。320px 窄屏也保持左标题、右署名的同一信息条。8 项关于页检查、小程序构建和 Swift 语法检查通过；三语及浅深色浏览器预览已查看，署名为两行、文字与图标中心差为零、图标高 10px。沿用上述原生环境限制，未完成原生运行或安装验收；桌面及导出无此模块。

出处链接合并（2026-10-27）：小程序与 iPhone/iPad 每行图标移到作者名前，并与姓名合并为一个点击目标。tombkeeper 的图标与姓名均指向指定作品原帖，Benjamin Couprie 的图标与姓名均指向 Wikimedia 原图记录；共享数据删除独立图标链接字段，保留 10px/pt 图标及右侧两行布局。8 项关于页检查、小程序生产构建及 Swift 语法检查通过；三语浅深色浏览器预览核对图标顺序、统一链接、10px 图标和垂直居中。原生运行、截图及安装受上述环境限制未验收；桌面及导出无此模块。

合影标题比例修正（2026-10-27）：小程序移除标题 80px 固定上限，iPhone/iPad 移除固定宽度，英文标题保持单行。常规宽度标题由 13 增至 22px/pt，署名由 10 缩至 9px/pt、标签 8px/pt，图标与署名等高；左右信息区域同为 28px/pt 并垂直居中。小程序 360px 以下收小标题为 17px，iOS 在空间不足时允许单行等比缩小，保留左大右小层级。8 项关于页检查、小程序构建及 Swift 语法检查通过；独立 iframe 视口预览查看 375px 简中浅色、英文深色、320px 繁中浅色及英文深色，英文均单行完整，左右区域等高，无姓名裁切。未完成原生运行、截图或安装验收，仍受上述微信捕获和 Xcode 环境限制；桌面及导出不涉及。

微博彩色图标（2026-10-27）：以微博官网 favicon 的 32×32 全彩图层替换 Simple Icons 单色 SVG，保留红黄黑白与透明度，来源及转换哈希记录于 `assets/brand/partners/weibo/README.md`。共用导出器同步小程序与 iPhone/iPad 浅深色资源，显示尺寸、位置和统一出处链接不变；原生大图预览工具栏同样使用新图。2 项导出测试、导出一致性检查及小程序生产构建通过；核对两端两种主题 PNG 字节一致且包含红黄像素，浏览器浅深色已查看。原生运行、截图及安装未验收，桌面与导出无相关图标消费者。

合影副标题恢复（2026-10-27）：按用户要求恢复共享配文 “1927 × AI”，小程序与 iPhone/iPad 将其以 7px/pt 小字紧贴主标题右下方，右边缘跟随主标题文字而非整块可用宽度；主副标题间距 -1px/pt，整体保持 28px/pt，与右侧两行出处等高居中。主标题单行，常规字号 22，窄屏收小；前置彩色微博图标及统一链接保留。8 项关于页检查、小程序生产构建及 Swift 语法检查通过；三语、浅深色和 320/375px 浏览器预览已查看，量测主副标题与出处区域均为 28px、中心差 0、副标题右边缘差 0、间距 -1px。原生运行、截图和安装未验收，桌面及导出无相关消费者。

合影副标题横排（2026-10-27）：按后续要求，将 “1927 × AI” 移至主标题右侧，间距 4px/pt，两者底边对齐；标题组仍为 28px/pt，与右侧出处两行等高居中。小程序与 iPhone/iPad 同步，窄屏收小标题及必要字号，保持英文单行并避免与出处相碰。8 项关于页检查、小程序构建与 Swift 语法检查通过；375px 简中浅色/英文深色、320px 繁中浅色/英文深色浏览器预览已查看，量测主副标题底边差 0、间距 4px、左右区域均高 28px。原生运行、截图及安装未验收；桌面和图片导出不涉及。

合影副标题字号（2026-10-27）：按用户要求，“1927 × AI” 随主标题字号保持 1:2，右侧底边对齐。小程序以 CSS 变量共用字号，361–400px 英文标题组适度收小以避免出处重叠；iPhone/iPad 各个 ViewThatFits 候选均使用主字号的一半，并补充 18pt 候选。8 项关于页检查、小程序生产构建及 Swift 语法检查通过；320/375px、三语及浅深色浏览器排版预览已查看。微信及 iPhone/iPad 原生运行、截图与安装未验收，环境限制同前；macOS、Windows 与图片导出无对应模块，不涉及。

合影标题自动缩放（2026-10-27）：替换固定字号档位。小程序首屏布局及窗口变化时测量左侧可用宽度和未缩放标题组的自然宽度，整体按不大于 1 的比例缩放；独立隐藏测量节点保证变宽时可以恢复，序号及卸载状态防止旧测量覆盖新布局。iPhone/iPad 使用 GeometryReader 与未缩放内容的宽度 Preference 连续缩放。主副标题保持单行、底边对齐和 2:1 字号比例，两组出处保留完整宽度。9 项关于页/生成内容检查、小程序生产构建及 Swift 语法检查通过；使用实际 About 页面测量逻辑的浏览器夹具检查 280/320/375/430px、三语及浅深色，标题可见宽度均未超过可用宽度，主副标题底边差为 0，出处无重叠。微信模拟器及 iPhone/iPad 原生运行、截图和安装未验收，仍缺少可用微信 MCP 与完整 Xcode；macOS、Windows 及榜单图片导出无对应模块，不涉及。






文案与金额精度修正验证（2026-10-26）：小程序 200 项测试及构建、iOS 三语生成数据 2 项检查通过；Swift 粗粒度金额计算实际编译运行 9 项断言通过，iOS 内容模型语法检查通过。Calmmit 前台/后台 review 与公共计算相关 85 项测试通过，产品文案规则已核对两条实际提示入口。千元、万元等更粗金额单位可按项目指定，UI 不展示该内部配置。未运行移动 UI 测试或完成真机安装验收。

金额粒度规则验证（2026-10-26）：Calmmit 公共计算与生成适配 6 项测试通过；AI 天梯小程序 200 项测试及构建、iOS 数据生成 2 项检查通过，Swift 金额计算实际编译运行的 13 项断言通过。Watrek / Weaveo 生成适配同步，核心包分别 283 / 433 项测试通过，Weaveo 小程序 828 项测试通过，均通过原有覆盖率要求。本轮未运行 iPhone/iPad UI 测试或真机安装；桌面与图片导出不含此投入金额模块。

平台名称修正（2026-10-27）：共享平台清单将 iPad 改为 iPadOS，保留 `ipad` 内部标识，三语及小程序、iPhone/iPad 生成内容一致。8 项关于页检查、小程序生产构建及三语生成内容核对通过；未完成原生运行或安装验收。桌面及图片导出没有该列表，不涉及。

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

小程序、iPhone / iPad、macOS 和 Windows 的榜单时间与「发布／刷新」标签均加下划线，点击打开「时间说明」，不触发数据刷新。三语说明强调榜单数据实时更新，区分榜单提供的发布时间，以及未提供发布时间时展示上一次更新到新数据的时间，重复数据保持不变；不展示采集实现细节。Apple 共用 `LeaderboardPresentation.sourceTimeExplanation`，小程序维护在 `core/catalog.js`，Windows 共用 `BoardTimestamp.Explanation`。各端原生弹窗按平台呈现；静态图片继续保留时间信息，不增加弹窗操作。

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

贡献者圆团验证（2026-10-27）：共享能力相关 25 项测试、Calmmit lint、语法和格式检查通过；小程序全量 207 项测试、生产构建及业务/原生三语内容 3 项检查通过。Swift 关于页、解码模型和 UI 用例语法检查通过。使用实际圆团数据与页面 CSS 的浏览器夹具检查 320/375/560px、三语及浅深色共 18 种排版，圆团位于两项数字右侧，无横向溢出、圆形变形、越界或标志加载失败；查看了 375px 简中浅色、320px 英文深色，以及共享 SVG 的浅深色栅格导出。浏览器夹具不代表微信原生运行验收；官方微信 MCP 当前不可调用，现有 CUA 捕捉受 ScreenCaptureKit -3811 限制。当前仅有 Command Line Tools，未完成 iPhone/iPad 完整 UI 构建、运行截图或真机安装，新增原生 UI 用例尚未运行；未上传或发布版本。

贡献者圆团留白收紧（2026-10-27）：Calmmit 按所有可见圆的实际边界居中缩放，替换固定 55/610 边距；最长边占画布 94%，本仓库原先约为 79%。圈内标志由直径的 54% 放大至 68%，有姓名标签时向上微移，标签下移保持间隔。共享 SVG、小程序及 iPhone/iPad 同步；卡片仍在提交次数、代码行数右侧。共享布局 7 项、业务与关于页 12 项测试及小程序生产构建通过，Swift 源码语法、共享模块 lint/格式检查通过。浏览器夹具复查 320/375/560px、三语及浅深色共 18 种排版，无溢出、变形、越界或本地图片加载失败，已查看浅深色生成图片。未完成微信及 iPhone/iPad 原生界面运行验收或安装，环境限制同上。

贡献者布局单行修正（2026-10-27）：按用户澄清，提交次数、代码行数、贡献者圆团必须从左到右处于同一行，前两项缩窄，不再上下堆叠。小程序保留两列数字网格并给右侧圆团 27% 宽度；iPhone/iPad 在同一个 HStack 内依次放置两项数字和圆团，标签保持单行并按需缩小。关于页与共享内容 12 项检查、小程序生产构建及 Swift 语法检查通过。浏览器夹具复查 320/375/560px、三语浅深色共 18 种，三项顺序及垂直中心一致，数字和标签无溢出；圆团无变形和越界。未运行微信及 iPhone/iPad 原生界面验收或安装，当前环境限制同上；桌面及榜单导出没有对应模块。

贡献者底边对齐（2026-10-27）：按用户要求，单行中的提交次数、代码行数和较高的圆团改为底边对齐。小程序使用 `align-items: flex-end`，iPhone/iPad 共用 HStack 使用 `.bottom`；三列顺序及宽度不变。320/375/560px、三语浅深色共 18 种浏览器排版量测，三项底边差均小于 1px；已查看简中浅色预览。小程序生产构建与 Swift 语法检查通过，未运行微信或 iPhone/iPad 原生界面验收及安装，环境限制同上。

贡献者详情去除链接（2026-10-27）：按用户要求删除 “x 次提交” 右侧的复制链接按钮，小程序及 iPhone/iPad 同步；保留姓名、提交次数和头像选择，清理专用文案及样式。12 项关于页与共享内容检查、小程序生产构建、Swift 源码和 UI 用例语法检查通过，原生 UI 用例同步为确认按钮不存在。本轮未运行微信或 iPhone/iPad 原生界面验收及安装；桌面及榜单图片导出不含对应详情。

贡献者圆团限制行高（2026-10-27）：按用户要求，由提交次数和代码行数卡片决定原有行高，圆团不能撑高整行。小程序圆团脱离内部普通流，在拉伸至行高的按钮中按高度等比缩放并靠右下对齐；iPhone/iPad 保留零高占位列，在原有数字行上叠加圆团，边长取列宽与实际行高的较小值。320/375/560px、三语浅深色共 18 种浏览器排版均确认显示或隐藏圆团时行高一致，圆团保持正圆、未超出行高且底边对齐；小程序生产构建及 Swift 语法检查通过。微信及 iPhone/iPad 原生界面运行和安装本轮未验收；桌面及榜单图片导出没有对应消费者。

贡献者圆团原尺寸修正（2026-10-27）：用户澄清圆团不得缩小。小程序恢复原有 27% 列宽和正圆大小，整个按钮绝对定位于数字行右下方，预留横向空间，允许圆团向上超出而不参与行高计算；完整按钮点击区域随圆团保持原大小。iPhone/iPad 继续使用叠加布局，移除以行高限制圆团边长，恢复由第三列宽度确定原尺寸。320/375/560px、三语浅深色共 18 种浏览器排版确认原尺寸及完整点击区域保留、数字行高不变、正圆和底边对齐；已查看浅色预览。小程序生产构建及 Swift 语法检查通过；微信和 iPhone/iPad 原生界面运行及安装本轮未验收。

排名变化验证（2026-10-28）：服务端/共享规则 37 项、小程序最终全量 211 项（含相关 38 项）回归通过，覆盖四类 API 采集、HTML 贡献、写入失败保留旧榜、重复抓取、公司独立聚合、身份歧义、三语和图片导出行高。小程序生产构建、macOS Debug、Swift Windows 引擎桥接构建及 Windows WPF Release 交叉编译通过（Windows 零警告/错误）。实际共享 Swift 来源在受管理临时包中通过新增 Codable/离线缓存/公司投影回归；iPhone/iPad 仅完成源码语法检查，本机无完整 Xcode，未完成 iOS 构建、模拟器或真机验收。小程序官方微信 MCP 和 Windows 原生环境不可用，未完成这两端运行验收。Mac 使用同一夹具、1100×720pt、2× backing scale，采集修改前后各 36 帧，覆盖三语和两种主题；24 组刷新/稳定帧像素一致，已查看英文深色与简中浅色的长名称和升降标记，另查看 850pt 单榜公司布局。修改前基线为既有 Debug 可执行文件，并非 clean HEAD 重建。证据位于忽略目录 `work/rank-changes/`；无 Windows 对照、双桌面 CI 视觉产物、安装或部署记录。完整检查初轮 436 脚本测试、211 小程序测试和精确 100% 脚本覆盖率通过，但因输入变化未取得通过凭据；末轮全量检查另有 `Scripts/ios-deploy-boundaries.test.mjs` 两个用例报 `formatTimestamp is not a function`，未改写这些断言，也不据前一轮结果宣称最终全量通过。

应用许可显示修正（2026-10-28）：仓库 `LICENSE`、macOS 与 iPhone/iPad 随包许可正文此前已是 PolyForm Perimeter License 1.0.0，本轮不修改条款。新增共用 `ApplicationLicense.json` 名称资源，macOS/Windows 页脚使用本地化 “许可证” 入口及完整名称提示，Mac 许可窗口与静态图片署名同步；Windows 图片导出共用该页脚。小程序清理旧 MIT 构建常量名称，移动端没有对应应用许可页脚，第三方原许可继续保留。2 项许可/打包契约检查、Windows 共享测试（含实际载入嵌入名称资源）、WPF Release 交叉编译（零警告/错误）、Mac Debug 编译及小程序生产构建通过。Mac 同一夹具与 850×720pt、2× backing scale，修改前后各采集 18 帧页脚，覆盖三语、浅深色及显示/刷新/稳定状态；另采集 18 帧应用许可窗口，已查看简中深色页脚和英文浅色完整许可名称。基线为本工作区修改前编译，包含其他并行任务修改，非 clean HEAD；证据在忽略目录 `work/license-identity/`。当前没有 Windows 原生运行/视觉截图及 CI 对照产物，本轮未安装或发布客户端，也未替换正在运行的 Mac 旧包。

内容刷新时间（2026-10-28）：`fetchedAt` 继续记录成功采集以保留请求顺序与调度，新增持久化 `contentUpdatedAt` 记录最近一次取得新榜单数据的时刻。各来源写入前以最后持久化榜单比较，排序后核对模型身份、名称、公司、排名、分数、精确 token 用量与投票数；Vercel 新统计日和腾讯累计统计范围变化也视为新数据。数组顺序、排名变化徽标、图标/国家/模型资料补全不推进时间。首次取得数据使用本次采集时间；旧快照缺少该字段时，以已有采集时间作基线，无法据此追溯更早的首次发现时间。重复或被拒绝的旧响应、读缓存、失败的采集/持久化不推进；发布时间继续优先显示。

小程序读写离线缓存、三语页头和 Canvas 图片导出，Apple 共用 Kit 的 Mac / iPhone / iPad 及静态导出，Windows 共享 Swift 引擎桥接、WPF 及图片导出均消费该字段。兼容旧服务端与直接采集时，客户端按同一榜单内容比较保留本地基线；服务端已提供的内容时间优先。网络调度继续使用来源发布时间/成功采集时间，避免数据长期未变导致重复请求。三语时间说明同步明确 “数据没有变化时，时间保持不变”。

内容时间验证：服务端及来源相关 95 项、小程序最终全量 217 项（含三语实际页头/Canvas 导出回归）、实际 Kit 来源下 23 项 Swift 测试（含共用内容夹具、离线 Codable 与服务刷新）通过。小程序生产构建、Mac Debug 与 Swift 引擎桥接编译通过；Windows 共享测试和 WPF Release 交叉编译通过（零警告/错误）；iPhone/iPad 存储源码语法检查通过。Mac 同一时间夹具、850×720pt、2× backing scale，修改前后各采集 18 帧，覆盖三语、浅深色和显示/刷新/稳定状态；查看英文浅色与简中深色，确认刷新标签从最新抓取日改为内容日，发布时间不变。12 组刷新/稳定帧的时间区域像素一致，整幅图片的差异限于系统滚动条淡出。基线为修改前已有的 Debug 可执行文件，包含工作区并行修改，非 clean HEAD；前后另有并行品牌变更，不据此宣称全画面仅时间变化。截图、原生元数据、二进制/夹具校验和与检查日志在忽略目录 `work/content-time/`。本机无完整 Xcode 和 Windows 原生环境，本轮未完成 iPhone/iPad、Windows 与微信原生运行验收或对应 CI 双桌面视觉产物；未部署服务端、上传小程序或安装/发布任何客户端。


PC 英文标题对齐 iOS（2026-10-28）：Mac `EnglishBrandTitle` 直接复用 `MobileBrandTitle`，补回独立 I、采用相同的离线字形与字距，并将网络 A 按共用配置倾斜 31°；宽度与墨迹高度量测同步。Windows WPF 嵌入同一生成 JSON，使用相同路径、倾斜与浅深色金属渐变，保留原生 27 DIP 标题行框。Mac 正式打包和原生截图入口补齐生成字形 JSON，并优先读取主应用资源，避免没有 SwiftPM bundle 的安装包启动失败。中文桌面标题保留原有布局；移动端字形资源未变，iOS 只增加主应用资源查找路径。共用桌面视图的导出使用更新标题，本轮未单独验收导出。

验证：13 项实际 Kit 标题 / 字形 / 渲染测试通过（在最终主资源查找补充前运行）；最终原生截图应用不携带 SwiftPM bundle，已验证主资源加载与生成 JSON 逐字节一致。5 项资源与打包门禁测试、两份脚本语法检查、Mac Debug 编译和 Windows WPF Release 交叉编译通过（Windows 零警告 / 错误）。忽略目录 `work/desktop-english-brand/` 保存同一夹具的 Mac 前后各 36 帧，覆盖英 / 简中 / 繁中、850 / 1100×720pt、浅深色和显示 / 刷新 / 稳定阶段，实际 2× backing scale。已查看四组英文宽度 / 主题及繁中深色原图，I 完整、A 倾斜且无裁切；所有 12 组标题区三阶段像素一致。当前无 Windows 原生环境、对应 CI 视觉产物或完整 Xcode，Windows 视觉、iPhone/iPad 原生构建 / 运行以及客户端安装与发布均未验收；未安装、上传或发布。


PC 来源表头与协议弹窗（2026-10-28）：Mac / Windows 表头只保留来源、说明及时间，不再追加 CC BY 4.0，宽度测量同步去掉协议后缀；使用相同桌面视图的图片导出继承该行为。点击来源仍展示完整署名、许可正文和原始链接，复制链接行为不变。Mac 将文档宽度约束为实际滚动视口宽度（含系统纵向滚动条占位），长文本随宽度换行，仅纵向滚动，并在弹窗完成初始布局后回到顶部；Windows 显式禁用横向滚动并保留 TextWrapping.Wrap。此次用户限定 PC，移动端未修改。

原生视觉验证：使用同一共享夹具，850 / 1100×720pt、2× backing scale，采集 Mac 修改前 30 帧、修改后 30 帧及 6 张协议末尾截图，覆盖 Epoch 英文、Vercel 简中、OpenRouter 繁中与浅深色。已查看英文表头前后、繁中深色用量表头及三语弹窗与协议末尾；6 个弹窗均为 465pt 文档 / 465pt 视口，初始横纵偏移为零，无横向滚动条，全部 6552～17161 字符保留且可滚动到底。修改后 6 组弹窗刷新 / 稳定帧逐像素一致；表头剩余帧差异限于系统纵向滚动条淡出区域。旧弹窗深色基线存在截图背景解析问题，未据此宣称深色前后视觉对比通过；本轮在原生捕捉时使用实际 appearance 的绘制上下文，修改后深色已实图检查。Mac Debug、Windows WPF Release 交叉编译（零警告 / 错误）及源码语法检查通过。截图、原生元数据、几何记录、校验和及完整检查日志在忽略目录 work/source-details/。本机无 Windows 原生环境或对应 CI 视觉产物，Windows 原生运行与视觉仍待验收；未单独验收桌面导出，未安装或发布。

本轮 Calmmit 测试阻断：删除供应商品牌 PNG 后，原有 3 项头像测试仍依赖该目录。现以独立临时目录中的合成 PNG 验证内置头像优先级、模型别名和通知附件，并补充实际仓库缺图时的 URL 回退检查；没有恢复来源不明资源，也没有删除或放宽原断言。相关 14 项测试通过。全量检查进一步发现日期版本脚本缺少无参数 CLI 分支覆盖，补充独立目录用例验证其按北京时间生成版本并同步原生元数据，保留无效 / 旧版本拒绝及同日幂等检查；发布相关 8 项测试通过，原有 100% 脚本覆盖率门禁保留。完整门禁回执及本机缺少完整 Xcode 时的原生测试跳过情况见 work/source-details/full-tests-verified.log；不能以脚本通过代替未运行的 Swift / iOS 原生测试。

本轮最终完整门禁：`./test.sh --coverage` 返回 0，451 项脚本测试、217 项小程序测试通过，每个受测脚本的行 / 分支 / 函数覆盖率均为 100%。已有运行器因本机缺少完整 Xcode 跳过 Swift / iOS 原生测试；Mac 界面仍单独完成 Debug 编译和上述 AppKit 原生截图。


GitHub 图标调整（2026-10-28）：共享资源更换为固定修订的 MIT 授权 `tabler:brand-github` 线描图标，保留原 SVG、来源哈希和完整授权，重新生成 128×128 透明 PNG；Mac、Windows、iPhone / iPad 与小程序沿用共用资源路径。生成与来源校验、贡献者适配共 4 项测试通过；小程序生产构建通过且打包图片与源 PNG 字节一致。复用此前已有的 Mac 原生截图应用，仅替换其资源，使用相同 850×720pt 夹具、2× backing scale 捕获前后浅深色各三帧；已查看修改后两种主题，前后像素变化仅在页脚图标范围，刷新与稳定帧一致。截图及日志在 work/github-outline/；该截图应用并非当前全量源码重编译。没有 Windows 原生截图或对应 CI 视觉产物，也没有 iPhone / iPad / 微信原生运行验收；未安装、上传或发布。


模型品牌图标优先级（2026-10-28）：共享服务对已核实的 Claude、Qwen、Kimi、DeepSeek、MiniMax 等模型家族优先使用品牌目录现有的产品图标，避免榜单来源和历史缓存中的公司图标覆盖；Gemini、Wan、Veo 等已有独立模型资源继续优先使用各自图标，公司聚合仍保留原公司图标。旧快照在共享服务 enrich 时修复，客户端无需分别改映射；Mac、Windows、小程序、iPhone / iPad 及导出消费相同的共享数据。针对共享服务 43 项品牌 / 榜单回归通过，覆盖旧快照、离线、独立模型及公司图标；完整测试和覆盖率结果见 work/model-brand-fix/full-tests.log。此为服务源码变更，未部署云函数或验证线上数据更新；未安装 / 发布客户端，也未完成本轮各端原生视觉验收。

模型品牌图标最终验证：`./test.sh --coverage` 返回 0，456 项脚本和 220 项小程序测试通过，脚本覆盖率门禁通过。本机缺少完整 Xcode，运行器跳过 Swift / iOS 原生测试。


GitHub 官方标志与作者链接（2026-10-28）：共用图标改为 GitHub 官方 Octicons `mark-github-24`，原始 SVG、固定修订、MIT 正文和哈希均保留；Mac / Windows 仓库入口和小程序 / iPhone / iPad 贡献者头像使用同一生成图。Mac 与 Windows 的 Cloyd Lau 姓名和 GitHub 图标均打开同一仓库地址；移动端关于页原有复制链接交互不变，榜单导出不提供可点击链接。Mac 新 Debug 应用与 Windows WPF Release 交叉编译通过，Windows 零警告 / 错误；资源、授权及贡献者 4 项测试、源资源一致性检查和小程序生产构建通过，实际打包图标与 Octicons 授权文件分别与源文件一致。Mac 相同 850×720pt 夹具、2× backing scale 前后浅深色各三帧，已查看修改后两种主题；前图为此前的原生 Debug 应用、后图为本轮源码构建，受并行源码变化影响不声称其余像素一致，刷新与稳定帧差异位于系统滚动条区域。截图与日志存于 work/github-official/。没有 Windows 原生截图 / CI 视觉产物、iPhone / iPad / 微信原生运行及安装或发布验收。


公司榜品牌身份修复（2026-10-28）：共享服务将已识别产品标记为 `model-product-*`，公司图单独保存在 `organizationBrand`；原有 Qwen / Claude 等模型图可继续显示，Wan / Gemini 独立图保持不变。公司来源可用时优先保留与重新获取公司图，不再把已知产品图作为公司回退。共享 JS 聚合（小程序、服务及其导出）和 Swift Kit 聚合（Mac、Windows 共享引擎、iPhone / iPad）优先各成员明确公司图；旧模型图身份不明确时使用首字母，已确认的旧公司图仍可用。使用本地合成公司图、Qwen 产品图及旧缓存夹具验证，不能将测试图当作真实公司标志。针对性品牌 / 服务 / 小程序 76 项通过，小程序构建、Mac Debug 和 Windows WPF Release 编译通过。Mac 使用相同 850×720pt 夹具、2× backing scale 采集模型 / 公司、浅深色前后各 12 帧；查看公司浅深色及模型深色，旧 Qwen 图不再显示在 Alibaba 公司行，有明确公司图时仍显示，模型图保留。前图为先前 Debug 二进制，后图为本次源码构建，非干净 HEAD。原生运行仅验证 Mac；Windows 原生视觉与 CI 视觉产物、iPhone / iPad、微信原生运行尚未验收。服务端未部署，旧线上数据不会立即改变；未安装、上传或发布。完整检查与 Swift 复测见 work/company-brand-fix/。

补充：原生端通过从共享品牌目录生成的图像指纹识别已知的旧产品图片，即使 Wan 等独立模型图不同于误存的 Qwen 公司图也不复用；未识别模型家族的历史图片仍依赖现有来源字段和回退规则。完整门禁和最终 Swift 复测日志见 work/company-brand-fix/full-tests-last.log 与 swift-tests-last.log。

最终验证：生成策略文件一致性检查、Mac Debug 和 Windows WPF Release 编译通过；隔离 Core 测试使用本机 TestingMacros 插件运行，7 项 OrganizationBrandTests 通过，包含旧 Wan / Qwen 图像指纹。Mac 额外采集 Wan 旧缓存前后浅深色各三帧，查看浅色结果。完整脚本 458 项和小程序 221 项及脚本覆盖率均通过，但运行期间共享工作区输入变化，测试运行器拒绝签发有效回执；不得称完整门禁通过。日志在 work/company-brand-fix/。
## 小程序美元符号对齐 — 2026-10-30

小程序榜单的美元金额将 `$` 单独向上微调 0.06em，输入／输出价格、极小金额前缀和图片导出均保留原有金额及顺序。Mac 上 Menlo 12pt 的字形度量中，`$` 中心比数字约低 0.7pt；该偏移按字号缩放。榜单与导出 42 项测试、成本切换和一万行桥接测试以及小程序隔离生产构建通过。当前没有可调用的微信官方开发者工具 MCP，开发者工具的系统截图接口返回 ScreenCaptureKit -3811，因此未完成小程序模拟器／真机视觉验收。桌面及 iPhone/iPad 本次不涉及。

## Qwen 余量图标 — 2026-10-30

Mac 余量卡片和 Windows 共享引擎使用同一 Qwen 产品图标，来自品牌目录中已核验的千问图片，不再从榜单缓存中选择 Alibaba 公司图标；其他余量供应商继续使用缓存的供应商标志。小程序、iPhone / iPad 及榜单图片导出不展示账号余量。本轮原生双桌面视觉对照、安装及发布尚未完成。


## OpenRouter 指标入口恢复 — 2026-11-01

恢复小程序、iPhone/iPad、macOS、Windows 的 OpenRouter 用量／价格／速度下拉选择及对应引导，覆盖表格和图片导出；取代 2026-10-30 的临时隐藏状态。切换指标仍保持用量排名，价格展示输入与输出单价（美元／百万 token），速度为 token/s。

实测共享接口 50 个用量模型中有 46 个具备价格和速度。其余 4 个模型不在 OpenRouter 当前公开模型目录中，缺失指标保留破折号，不推测价格或速度。客户端回归验证和原生运行验证分别记录，不以源码恢复代替各端运行验收。


本轮验证：小程序页面、共用展示、图片导出及 OpenRouter 采集相关 157 项测试通过；追加的页面价格导出断言通过；小程序正式构建通过。微信官方模拟器验证旧快照从 0 项指标刷新为 46 项价格／速度，并在模型、厂商视图切换用量、价格、速度；自动选择菜单回调后已恢复原 API。Apple 共用 UI 和 Mac AppKit 编译通过，移动缓存及导出冻结状态定向测试通过；Windows WPF Release 交叉编译通过（0 警告、0 错误）。

`work/openrouter-metrics/` 保留共用夹具、Mac 原生三语浅深色截图及哈希记录。没有完整需求前截图基线、Windows 原生截图／DPI 或对应 CI 视觉工件；iPhone／iPad 本轮未运行或安装，不宣称全部原生端验收完成。完整门禁由 Calmmit 执行，本轮运行的是定向检查。
