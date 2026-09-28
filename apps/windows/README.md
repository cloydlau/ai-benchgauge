# Windows 原生客户端

Windows 10/11 x64，WPF + 共享 Swift 核心。支持托盘、四种窗口模式、
四类双榜、公司分组、国家筛选、三种界面语言、余量渐变、隐私截图与每 24 小时检查应用更新。
千问登录采用 WebView2 独立浏览器配置；OpenAI 授权沿用共享核心的独立 Codex 配置。

用户从同一 GitHub Release 下载 `AI-BenchGauge-<版本>-windows-x64-setup.exe`。
程序按当前用户安装，不需要自行安装 Swift 或 .NET。

开发环境需要 Node.js 24、.NET SDK 10.0.401、Swift 6.4.0，
以及 Swift 官方说明要求的 Visual Studio C++ / Windows SDK。
安装器构建另需 NSIS 3.11。参考 [Swift 官方 Windows 安装说明](https://www.swift.org/install/windows/)。

```powershell
./Scripts/make-windows.ps1            # 测试、自包含程序、引擎与原生截图检查
./Scripts/make-windows.ps1 -Installer # 同上，并生成 .exe 安装包
```

共享核心测试不查询真实账户。更新测试用随机测试密钥，窗口测试用模拟数据。
构建脚本还会移除工具链 PATH 后测试打包的引擎，避免只在开发机上能启动。
原生窗口测试截图保存在 `work/windows-ui-smoke/`。

分发版本的 WebView2 Runtime 由微软 Evergreen 更新机制维护。
未配置 Windows Authenticode 证书时安装器为未签名程序；更新真实性由应用内
Ed25519 公钥与安装包 SHA256 验证。正式安装、卸载和安装后自动更新应在 Windows 测试机验收。
