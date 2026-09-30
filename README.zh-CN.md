# AI BenchGauge

*AI Benchmarks & Quotas — who's on top, how much you've got left.*

[English](README.md) | **简体中文** | [繁體中文](README.zh-Hant.md)

**两张榜单，一眼对照。模型排名与账户余量，常驻 macOS 菜单栏与 Windows 托盘。**

`macOS 14+` · `Windows 10/11 x64` · `Swift 6 / WPF` · `English / 简中 / 繁中` · [MIT 许可证](LICENSE)

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/leaderboard-model-dark.png">
  <img src="docs/screenshots/leaderboard-model-light.png" alt="AI BenchGauge 浅色模式模型视图，展示双榜与供应商余量" width="850">
</picture>

*真实模型视图：并排查看两份 Top 20 榜单，上方显示 CC Switch 余量条。*

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/leaderboard-company-dark.png">
  <img src="docs/screenshots/leaderboard-company-light.png" alt="AI BenchGauge 浅色模式公司榜，按各公司最强模型排名" width="850">
</picture>

*真实公司视图：每家公司按其上榜的最强模型排名。*

不用在多个榜单网页之间来回切换：打开菜单栏，就能并排查看 Artificial Analysis 与 Arena 的 Top 20。装有 [CC Switch](https://github.com/farion1231/cc-switch) 时，还能在榜单上方查看支持的提供商余量和重置时间。

> 如果它帮你省下了反复查榜单、查余量的时间，欢迎点右上角 **Star ⭐**。

## 系统兼容性

| 系统 | 处理器 | 支持情况 |
| --- | --- | --- |
| Windows 11 | 64 位 Intel / AMD（`x64`） | 支持 |
| Windows 10 | 64 位 Intel / AMD（`x64`） | 兼容目标；.NET 10 官方支持仍受维护的 LTSC / Enterprise 版本，Home / Pro 尚未验证 |
| Windows 7 / 8 / 8.1 | 任意 | 不支持 |
| macOS 14 Sonoma 及以上 | Apple 芯片（`arm64`，M1 / M2 及后续芯片） | 支持 |
| macOS 14 / 15 / 26，且机型支持对应系统 | Intel（`x86_64`） | 支持 |
| macOS 13 Ventura 及以下 | 任意 | 不支持 |

Mac 的 `.dmg` 包含 **Apple 芯片与 Intel 原生通用应用**，两种芯片下载同一个安装包，无需 Rosetta。
Windows 提供 `x64` 的 `-setup.exe`，内含 Swift 和 .NET；不提供 32 位或原生 ARM64 安装包，ARM64 模拟运行尚未验证。
具体版本限制、已验证范围和 Intel 支持评估见[系统兼容说明](docs/compatibility.md)。

## 你会得到什么

| 功能 | 用起来是什么样 |
| --- | --- |
| **双榜对照** | 综合、编程、图片、视频四类榜单，每类并排展示两个来源的 Top 20 与各自分数。 |
| **模型 / 公司切换** | 模型看具体型号；公司以该公司上榜模型的最高分排名，不会因为多上榜或较弱型号而改变分数。 |
| **四种显示模式** | 底部下拉框可选“保持打开”“保持置顶”“失焦关闭”“独立窗口”；“保持打开”点击其他位置不会关闭，再点菜单栏图标关闭。“保持置顶”还会让弹窗显示在其他应用窗口之上。独立窗口首次打开时在菜单栏图标所在屏幕居中，内容宽高与弹窗一致；可拖动、调整大小和 macOS 分屏，切换模式时保留手动调整的位置和大小。 |
| **CC Switch 余量** | 读取本机 CC Switch 数据，查询支持的提供商余量，并在榜单上方显示状态；百分比和金额颜色随余量减少从绿色渐变至红色。金额以 ¥0/10/30/100、$0/2/5/20 分别对应红/橙/黄/绿，中间连续过渡，悬停可查看各币种的参照金额；无需安装 Codex。 |
| **直达套餐与按量页面** | 仅在“公司”分组显示可用的“套餐 / 按量”链接。简中优先打开中国大陆站点，其他界面语言优先打开国际站点。 |
| **许可证与声明** | 底部 MIT License 与“开源声明”打开同一个可滚动弹窗，完整许可正文可离线查看。当前核对情况见[声明清单](docs/third-party-notices.md)。 |
| **少打扰的更新** | 点开菜单栏时检查更新；榜单每天自动更新，失败后按小时重试。缓存让来源暂时不可用时仍能查看上次结果。 |
| **应用自动更新** | 每 24 小时检查 GitHub 稳定版，发现新版提示安装；点击后下载、校验签名、更新并重启。点击标题旁版本号可立即检查。[发版配置](docs/releasing.md)。 |

### CC Switch 余量如何工作？

应用从**本机 CC Switch 数据库**识别支持的提供商，再查询相应服务的账户余量。余量属于账户信息，不会混进模型分数列。当前使用的提供商在满足提醒条件、且你允许通知时，可收到余量提醒。

- 没有 CC Switch：榜单照常可用，余量区域提供官方安装入口。
- 没找到支持的提供商：不显示余量条，榜单照常可用。
- 数据库暂时读取失败：如果有上次的余量数据，就保留并标记为旧数据。
- 复制应用截图：自动把可见余量替换成 CC Switch 引导，并在单行页脚直接显示 `github.com/cloydlau/ai-benchgauge`，方便看到图片的人找到项目。

千问 Token Plan 的剩余比例与重置时间来自登录后的官方页面；首次使用可点击千问余量卡片登录。官方 `qianwen usage summary --format json` 在返回已订阅套餐时作为备用来源。CC Switch 记录的本机请求次数不等于订阅剩余额度，因此不会冒充 Token Plan 余量。

卡片日期统一显示“至”，表示接口提供的本期边界；当前不判断续订或取消续订，也不会仅因日期已过就认定套餐已到期。小时和周度额度重置时间可在提示中查看；缺少套餐或月度日期时，不会用短周期重置时间替代。

额度与日期文字各自使用同一套绿到红连续渐变，互不影响。日期以剩余 14 天及以上为绿、7 天为黄、2 天为橙、到达本期边界为红；卡片背景取额度与日期中更需要关注的一项。悬停可查看日期颜色参照。

OpenAI 显示“需要重新登录”时，点击卡片会直接打开官方授权页。完成同一账号的授权后，卡片自动刷新；后续查询会自动续期，只有续期失败才需要再次授权。直接授权需要本机安装 Codex CLI 或 ChatGPT/Codex 桌面应用；已有 CC Switch 登录的余量查询仍无需安装 Codex。新授权保存在 AI BenchGauge 的独立本机配置中，不需要手动同步 CC Switch。

xAI 显示“需要重新登录”或“未登录”时，点击卡片会打开 CC Switch：余量读取的 Grok 登录由 CC Switch 管理，供应商官网没有登录入口。在 CC Switch 中完成登录后，重新打开面板即会刷新余量。

## 榜单来源

| 分类 | 左侧 | 右侧 |
| --- | --- | --- |
| 综合 | Artificial Analysis Intelligence Index | Arena · Text |
| 编程 | Artificial Analysis Coding Agent Index | Code Arena · WebDev |
| 图片 | Artificial Analysis · 文生图 | Arena · 文生图 |
| 视频 | Artificial Analysis · 文生视频 | Arena · 文生视频 |

图片和视频使用对应的专项榜单。Artificial Analysis 只有编程智能体榜的数据里带批次生成时间 `materializedAt`，应用会在该列标题上显示这个源站数据时间和版本号；综合、文生图、文生视频三块没有公开数据时间，列标题不显示日期，面板顶部仍显示本机抓取时间。Arena 有投票截止时间时会显示该时间。切换分类会优先读取缓存，不必每次重新等待网络。

## 快速开始

从 [GitHub Releases](https://github.com/cloydlau/ai-benchgauge/releases) 下载对应安装包：
Mac 使用 `.dmg`（Apple 芯片 / Intel 通用），Windows 使用 `-setup.exe`（x64）。
Mac 也可以用 Homebrew 安装签名 Cask，后续更新继续由应用内 Sparkle 提供：

```bash
brew tap cloydlau/ai-benchgauge https://github.com/cloydlau/ai-benchgauge
brew install --cask cloydlau/ai-benchgauge/ai-benchgauge
```

Windows 按当前用户安装，不需要单独安装 Swift 或 .NET；[源码构建说明](apps/windows/README.md)。

Mac 源码构建需要 Swift 6、.NET 10 SDK（运行 Windows 更新测试）和 Command Line Tools：

```bash
./Scripts/make-app.sh
open outputs/AI-BenchGauge.app
```

本地默认只构建当前 Mac 的架构；`APP_UNIVERSAL=1 ./make-app.sh` 同时构建 Apple 芯片和 Intel，CI 与正式发版均使用该选项。

脚本会生成临时签名的 `outputs/AI-BenchGauge.app`。首次启动按 macOS 首选语言选择英文、简体中文或繁体中文；也可以在弹窗底部切换。分类、模型 / 公司分组和语言选择会保存在本机。

## 本地开发

<details>
<summary>展开本地 CI 说明</summary>

<br>

本地流程先执行完整的 Swift 核心、Node.js 脚本和 Windows 更新测试，通过后再按目的拆分提交、推送、构建和重启，同时保留模型署名、头像、桌面通知及防抖节流。

```bash
./dev.sh
```

`./dev.sh` 启动时先运行测试，再重新打开最新应用；如果可执行文件缺失或源码较新，会先构建再启动。后续保存按下面的防抖和节流间隔处理。测试失败会阻断后续动作，监听器继续等待，保存修复后重新验证。

`./dev.sh` 监听 `Sources/`、`apps/`、`assets/`、`config/`、`Tests/`、`Scripts/` 和根目录的构建、开发脚本，同时检查未提交改动和未推送提交。变更停止 1 分钟，并且距上次运行至少 1 分钟后，先测试，再按目的提交和推送，监听文件有变化时重建重启。已有的未推送提交也须先通过测试。子提交、构建进程只在测试输入完全一致时复用本次通过的结果。

`WATCH_DEBOUNCE_MS` 和 `WATCH_THROTTLE_MS` 可改这两个间隔，`WATCH_AUTOCOMMIT=0` 关闭自动提交，`COMMIT_PUSH=0` 或 `WATCH_AUTOPUSH=0` 关闭自动推送。构建失败后，同一份源码签名不会空转重试；提交失败后，同一份 git 状态也不会空转重试；推送失败后，同一提交也不会空转重试。再保存一次，或重启 `./dev.sh`，才会重新调度。

```bash
./test.sh                         # 完整离线测试
./test.sh --core                  # 仅 Swift 核心
./test.sh --scripts               # 脚本和 Windows 更新测试
./test.sh --coverage              # Swift 和 Node.js 覆盖率
DESKTOP_NOTIFY=0 node Scripts/ci-checks.mjs  # 语法、测试、正式应用构建
```

单独运行 `Scripts/commit.sh` 或 `./make-app.sh` 也必须先通过测试。门禁失败后，Codex 最多尝试一次源码修复，再运行完整真实测试；模型报告不能替代验证。报告不完整、有待决策项、改动测试或流程配置、复检仍失败都会停止后续流程。`TEST_AUTO_REPAIR=0` 关闭修复；`TEST_REPAIR_CODEX` 指定 CLI，`TEST_REPAIR_TIMEOUT_MS` 调整默认 10 分钟的上限。禁网沙箱和已识别的环境故障不会调用 AI 修复。日志和修复状态保存在忽略的 `work/test-results/`，重启不会重置同一份代码的修复预算。手动 `./test.sh` 只运行测试。

测试范围和可选网页快照见 [测试说明](docs/testing.md)。更新流程脚本后，已经运行的 `./dev.sh` 需要重启一次。

```bash
Scripts/commit.sh                 # 立刻暂存全部改动并拆成原子提交
Scripts/commit.sh --dry-run       # 只打印拆分计划
Scripts/commit.sh --identity      # 查看模型名称、邮箱和头像
Scripts/commit.sh -m "feat(menu): …"
```

作者是 Codex 配置里的当前模型，邮箱按厂商填写，桌面通知会尽量带上模型图标。成功和失败通知都使用临时样式。`COMMIT_SPLIT=0` 合并成一个提交。`COMMIT_CODEX_MESSAGE=0` 不调用模型，按用途分组。`Scripts/commit.sh` 的 `COMMIT_PUSH` 仍默认关闭。`COMMIT_COAUTHOR=1` 才把本人恢复为 committer，并加上 `Co-authored-by`。`DESKTOP_NOTIFY=0` 关闭桌面通知。

截图和录屏一律不允许模型直接提交。暂存区新增或修改录屏（`.gif`、`.mov`、`.mp4` 等）、截图目录或文件名（`docs/screenshots/`、`截屏…`、`frame-0001.png`），或 `assets/logos/`、`docs/logo/` 之外的位图时，`Scripts/commit.mjs` 在写入历史前直接中止。本人逐帧确认画面后加 `COMMIT_MEDIA_REVIEWED=1` 重跑，或用 `COMMIT_COAUTHOR=1` 以本人身份提交；两种方式都会在提交信息里留下 `Media-Reviewed-By` 审核记录。删除画面不受限制。CI 用 `node Scripts/media-gate-ci.mjs <base> <head>` 复查推送范围内的每个提交，绕过 `Scripts/commit.sh` 的裸 `git commit` 也会被拦下。

</details>

两端目录和共享业务层见 [结构说明](docs/architecture.md)，统一发版见 [发版说明](docs/releasing.md)。
