# 单元测试

本地安装 .NET 10 SDK（或 `BENCHGAUGE_DOTNET` 指定路径）后，运行 `./test.sh` 执行 Swift Testing 核心测试、Node.js 内置测试和 Windows 更新验签测试。Swift 6 工具链自带 Swift Testing，不依赖 XCTest 或额外下载测试库。脚本自动设置本项目的模块缓存，并为需要的工具链补充 TestingMacros 搜索路径。日期测试使用 `Asia/Shanghai` 时区。

核心测试覆盖榜单解析、公司聚合和排名、模型匹配、地区及语言、购买链接、CC Switch 配置及数据库、额度解析和格式化、截止日期、提醒、颜色过渡、面板模式偏好，以及模拟的账号授权、刷新和错误恢复。账号相关用例使用临时目录、模拟 RPC 和 HTTP 传输，不读取真实账号，不连接生产服务。

脚本测试覆盖模型署名、通知附件、Git 代理、测试入口和通过结果的复用、失败阻断、并发测试锁、修复预算、截图与录屏的人工审核门禁及真实复检。监听器、提交和打包的流程回归使用隔离目录和模拟命令，不启动用户应用，不推送远程仓库。

`HTMLLeaderboardParserTests` 的两项已保存网页测试沿用原先的可选快照条件：`Tests/work/artificial-analysis.html` 和 `Tests/work/arena-webdev.html`。缺少文件时，测试报告明确标记为跳过；其余解析用例使用内置合成数据，仍会执行。原生窗口交互、网页结构的实时变化和生产服务连通性需要单独验证，单元测试不覆盖这些行为。

`./test.sh --coverage` 开启两种语言的覆盖率输出。Node.js 在终端显示覆盖报告，Swift 的报告保存在 `work/unit-test-build/` 下；不设未经基线评估的覆盖率门槛，也不将模型报告或用例数量作为覆盖率。`DESKTOP_NOTIFY=0 node Scripts/ci-checks.mjs` 依次检查脚本语法、完整测试、正式应用构建和签名，不打开应用。

开发监听、独立提交及打包入口均有测试门禁。通过结果只能在本次流程内且源码、测试、脚本、构建配置和相关环境一致时复用；测试期间发生修改，结果作废并重新验证。失败日志、状态和一次修复的记录在 `work/test-results/`，不会进入版本库。自动修复只允许修改源码，测试或流程配置变化会阻断复检；只有完整测试通过且没有待决策项才能继续。

截图和录屏另有独立门禁，与测试门禁互不替代。屏幕画面会带出账号、余量、时间等隐私，模型不得直接提交：`Scripts/commit.mjs` 在写入历史前检查暂存区，命中录屏（`.gif`、`.mov`、`.mp4` 等）、截图目录或文件名（`docs/screenshots/`、`截屏…`、`frame-0001.png`），或 `assets/logos/`、`docs/logo/` 之外的位图就中止，只有删除画面不受限制。本人逐帧确认后加 `COMMIT_MEDIA_REVIEWED=1` 重跑，或用 `COMMIT_COAUTHOR=1` 以本人身份提交，提交信息都会写入 `Media-Reviewed-By` 审核记录。透传 git 参数（`--amend`、`-a` 等）补不了审核记录，只接受本人署名。`node Scripts/media-gate-ci.mjs <base> <head>` 在 CI 复查推送范围内的每个提交，裸 `git commit` 绕不过去；`Scripts/media-gate.test.mjs` 与 `Scripts/test-gates.test.mjs` 覆盖判据、放行方式、审核记录和端到端阻断。

Windows 更新测试覆盖合法签名、清单篡改、错误密钥、签名长度、下载地址、稳定版格式、安装包长度与哈希。
`Scripts/make-windows.ps1` 在 Windows 上运行全部共享核心测试、更新测试、打包引擎通信和四种原生窗口的截图检查。
POSIX 权限专用用例在 Windows 明确跳过；Windows 数据库并发和不可读场景通过平台文件共享检查。
两端源码、资源、配置及锁文件都进入本地测试签名，`bin/` / `obj/` 不进入监听或测试输入。

## Windows 原生检查

Windows CI 运行同一套 Swift 核心测试与更新验签测试，生成四种窗口模式的模拟数据截图，并在移除工具链 PATH 后验证打包引擎。
安装包还会在临时 CI 机器上静默安装、运行已安装引擎、卸载，检查用户数据和偏好是否保留。
安装器测试拒绝覆盖已有安装，不在开发电脑上运行。

## 双端逐帧视觉检查

主 CI 的每个 PR 和 main 推送自动调用 `visual-parity.yml`，在真实 Windows WPF 和 Mac AppKit / SwiftUI 上使用同一份合成数据截图。当前覆盖 10 个状态；每个状态记录打开、刷新、稳定三帧，Mac 另拍深色，共 90 张。报告校验本次提交、数据哈希、双端内容尺寸、主题和帧完整性，失败即阻断检查。

在 CI 的 comparison 作业摘要下载 `native-visual-comparison`，打开 `comparison.html` 逐帧并排、叠加或查看差异。界面改动须保留修改前后截图，在 PR 中记录报告和差异；缺少对应状态就先补测试场景。捕获成功不代表视觉验收通过。正式发布还必须通过 `native-visual-review` 环境的人工审查，publish 才会运行。

流程与本地命令见 [双端视觉检查](visual-comparison.md)。当前 Windows CI 是 Server 2022 / 实际 100% 缩放，不代表已验证 Windows 10/11 或 125%/150%；报告连续三个检查点，不是完整动画录屏。这套检查与提交截图的隐私审核分别执行。
