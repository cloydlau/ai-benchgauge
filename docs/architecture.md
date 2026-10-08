# 平台结构

保留两端原生界面，业务规则只有一份 Swift 实现。

```text
apps/
  macos/Sources/                AppKit / SwiftUI 界面与 Sparkle 更新器
  windows/
    BenchGauge/                WPF 界面、托盘、窗口和 WebView2 登录
    BenchGauge.Shared/         JSON 通信、配置和签名更新客户端
    BenchGauge.Tests/          Windows 更新完整性测试，可在 Mac 上运行
    installer/                 NSIS 安装器
    Licenses/                  Windows 分发声明
Sources/
  LeaderboardCore/            两端共享的解析、榜单、余量、提醒与格式化
  LeaderboardBridge/          Windows 调用共享核心的 JSON-lines 引擎
  CSQLite/                   系统 SQLite 导入（Mac sqlite3 / Windows winsqlite3）
  CPlatformSupport/          Windows 系统 SHA256 适配
assets/logos/                 两端共用的图标
config/app.json               共用版本号、仓库和更新公钥
Tests/LeaderboardCoreTests/   共享核心测试
Scripts/                      测试、构建、签名与发版
.github/workflows/            两端 CI 与汇总发版
```

Mac 直接调用共享核心；Windows 界面通过独立的常驻 `benchgauge-engine.exe`
调用同一份核心，使用进程标准输入输出传递 JSON。没有本地 HTTP 端口。
密钥、令牌、账号配置不会进入界面的 DTO 或日志。
退出时 Windows 会终止引擎及其子进程。

SwiftPM 在 Windows 上不解析 AppKit 或 Sparkle。SQLite 由系统提供，
Windows 使用 Windows 10+ 自带的 `winsqlite3.dll`；SHA256 使用 Windows CNG。
Windows 安装包包括 .NET 自包含运行时和 Swift 引擎的 DLL 依赖闭包，
不包含编译器，也不要求用户安装开发环境。千问登录使用独立 WebView2 配置，
安装器在缺少 Evergreen Runtime 时调用微软官方引导安装器。

Mac 缓存路径保持兼容；Windows 缓存、设置和独立授权位于
`%LOCALAPPDATA%\AI-BenchGauge`，程序位于
`%LOCALAPPDATA%\Programs\AI-BenchGauge`。账号文件继承用户配置目录的 ACL。
安装、更新不需要管理员权限，卸载保留用户设置与授权配置。

两端共用 `config/app.json` 的稳定版本和 Ed25519 公钥。
`bump-version.mjs` 同步更新 Mac Info.plist，WPF 从配置读取版本号。
每次发布先独立测试、构建，全部成功后才公开同一份 Release；
Mac 发布 `.dmg`，Windows 发布 `-setup.exe`，更新器按平台读取自己的清单。

## 榜单供应商与余量查询范围

开发范围取四类榜单、两套来源各 Top 20 的供应商并集，而不是当前选中的页面。
2026-10-01 的公开抓取快照保存在
`Tests/fixtures/quota-priority-2026-10-01.json`，共 8 张榜、160 个条目，归并为 27 家供应商。
同一供应商的模型名称、地区名称和历史名称按 `OrganizationLogoCatalog` 归并。
开发范围用于确定接入优先级；供应商跌出榜单不会删除已有账号。

| 分类 | Artificial Analysis | Arena |
| --- | --- | --- |
| 综合 | [Intelligence Index](https://artificialanalysis.ai/evaluations/artificial-analysis-intelligence-index) | [Text](https://arena.ai/leaderboard/text) |
| 编程 | [Coding Agents](https://artificialanalysis.ai/agents/coding-agents) | [Code / WebDev](https://arena.ai/leaderboard/code/webdev) |
| 图片 | [Text to Image](https://artificialanalysis.ai/image/leaderboard/text-to-image) | [Text to Image](https://arena.ai/leaderboard/text-to-image) |
| 视频 | [Text to Video](https://artificialanalysis.ai/video/leaderboard/text-to-video) | [Text to Video](https://arena.ai/leaderboard/text-to-video) |

本批共 12 家已实现查询，新增 Claude、Gemini、MiniMax、StepFun、Black Forest Labs 和 Luma。
接入一家供应商不代表已能查询它旗下所有模型、所有套餐的余量。

| 供应商 | 当前查询的账户产品 | 无 CC Switch 时的入口 |
| --- | --- | --- |
| OpenAI | Codex 官方账户额度 | 已有 `.codex/auth.json` 中的官方登录；卡片授权仍沿用现有流程 |
| Anthropic | Claude 订阅额度 | Claude Code 本地 OAuth 配置或可读取的 macOS 钥匙串 |
| Google | Gemini Code Assist 配额 | Gemini CLI 本地 OAuth 配置或可读取的 macOS 钥匙串 |
| Moonshot | Kimi Code 套餐 | Kimi 官方本地 OAuth / 配置 Key，或手动添加套餐 Key |
| Z.ai | GLM Coding Plan | 手动添加中国／国际区套餐 Key |
| DeepSeek | 官方 API 余额 | 手动添加 API Key |
| Alibaba | Qwen Token Plan | 现有 CC Switch 卡片中的官方页面登录／官方 CLI 备用来源；尚无独立添加入口 |
| xAI | CC Switch 管理的 Grok OAuth 额度 | 当前仍依赖 CC Switch 登录 |
| MiniMax | Coding Plan | 手动添加中国／国际区套餐 Key |
| StepFun | 官方 API 余额（CNY） | 手动添加 API Key |
| Black Forest Labs | 官方 API credits（不换算美元） | 手动添加 API Key |
| Luma | 官方 API 余额（接口返回美分，展示 USD） | 手动添加 API Key |

仍在本次榜内、尚未实现查询的 15 家：ByteDance、Meta、Microsoft AI、Xiaomi、Tencent、
Devin、Fal、Ideogram、Reve、KlingAI、PixVerse、Sand.ai、Sapiens AI、Skywork AI、Utopai Studios。
这些供应商保留为下一批核实对象，需分别确认账户产品、认证方式和官方余额接口。
“未实现”不表示官方没有查询接口。榜外的 SiliconFlow、OpenRouter、Novita 等暂不增加适配。

CC Switch 优先读取：兼容其本地数据库的不同应用配置、启用状态以及已接入模板的
`apiKey` / `baseUrl` 覆盖。CC Switch 的供应商目录数量不能作为余量查询覆盖数量；
本应用不执行任意 JavaScript 自定义查询脚本，也不打包 CC Switch 的 Tauri / QuickJS 运行时。
新接入的官网接口只识别明确的 HTTPS 官方域名，不把中转地址猜成官网账户。

官方账号补充：自动检测明确的本地账号文件，不通过进程名推断账户或正在使用的模型。
未知配置由用户在“添加模型”中选供应商、填 Key，成功查询后才保存；只列已实现的 Key 查询。
多账号以凭据／账户标识去重，不按供应商名字合并。仅 CC Switch 的 Codex 当前供应商决定
现有菜单栏的当前额度和提醒；自动发现账号不会被猜成当前供应商。

Kimi 同时读取 OpenCode 的 `options.apiKey` / `options.baseURL` 和 Codex 配置。
同一 Key 在不同工具中只显示一次，优先保留当前供应商的模型与标识；不同 Key 保留独立条目，
并标注 OpenCode / Codex 等来源。有配置 Key 时，自动发现的 Kimi CLI OAuth 仅作为备用来源，
不会再额外列出旧登录；没有 Key 的条目可复用本地登录，避免“未配置”和“登录失效”并列。
API Key 查询不需要 OAuth 保活。Kimi 官方 CLI 使用 refresh token 自动续期；本应用继续只读
其登录文件，不与官方客户端并发轮换令牌。

xAI 的周额度重置日只用于用量详情，不能补成套餐日期。套餐接口成功时使用并保存明确的
套餐周期结束日；接口暂时不可用时，仅可复用同一登录账号尚未过期、此前实际查询成功的日期，
并在提示里注明缓存来源。后台订阅接口被安全验证拦住时，可点击 xAI 卡片在应用内连接官网；
macOS 使用独立 WebKit 数据存储，Windows 使用独立 WebView2 配置目录，浏览器自行保存
官网会话，不导入 Chrome 凭据。已连接会话随余量刷新在后台读取 `/rest/subscriptions`。
接收日期前，使用官方 Grok Build 的 `/v1/user?include=subscription` 查询当前 OAuth 账号，
核对订阅记录的账号归属，并在网络调用前后检查当前登录未切换；`xaiUserId` 明确不匹配时
拒绝保存，字段省略时依赖账号级身份校验。
网页原始响应和 Cookie 不进入日期缓存、卡片或日志，缓存仅保存账号作用域和实际返回的日期。
手填日期不可用，旧手填记录也会被忽略。换账号不复用其他账号的日期，
不自动推算续期。
所有卡片日期统一使用“至M月d日”。

余量卡片先按计费类型分组：额度／套餐在前，按量余额／积分在后。套餐组内按卡片显示的
到期日从近到远排列；没有日期、查询失败、未登录或查询中的套餐仍在按量服务之前。
DeepSeek、StepFun、Black Forest Labs、Luma 的按量类型由供应商决定，查询失败不会改变
分组；其他明确返回余额的来源也归入按量组。组内相同日期或没有日期时保持原始顺序，
当前供应商不额外置顶。Mac 卡片与 Windows 引擎投影共用同一排序函数。

Claude、Gemini、Kimi 的官方 OAuth 登录只读，续期由官方客户端负责；过期时显示登录失效。
Gemini Code Assist 不代表 Google 图片／视频计费，MiniMax Coding Plan 不代表海螺视频额度，
Luma API 不代表 Dream Machine 网页订阅。卡片和添加表单明确显示查询范围。
手动添加的 Key 保存在独立本地账号文件，macOS 写入前即设置 0600 权限，Windows 继承
用户配置目录 ACL；密钥不会进入引擎响应的账号摘要、显示卡片或日志。

解析和请求使用模拟响应验证（包括缺失字段、单位、区域、认证失败和多账号），未用真实账号
对新增六家的接口完成端到端验证。接口或官方本地存储结构变化时需更新适配。
