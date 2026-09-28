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
