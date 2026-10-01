# macOS / Windows 更新与发版

每个版本发布两种安装格式：Mac 通用 `.dmg` 与 Windows x64 `-setup.exe`。
两端共用 `config/app.json` 的版本号和更新公钥。只有两边的构建都成功，
汇总任务才创建草稿 Release 并公开，避免用户收到缺少某个平台的版本。

两端在启动时及运行期间每 24 小时自动检查稳定版，无需用户配置。发现新版后直接在后台下载，
不会显示下载前的确认框，也不会激活、打开隐藏的应用窗口。下载准备完成且应用窗口激活时，
才在当前窗口显示更新提示；后台下载完成则等用户下次打开或激活窗口。
其他弹窗尚未结束时也会等待，避免覆盖授权或声明窗口。

提示沿用 Watrek 小程序的强制更新原文：标题 **发现新版本**，正文
**新版本已下载完成，重启后生效。**，唯一按钮 **重启升级**。
没有取消或关闭按钮，Esc 和关闭快捷键也不能略过。点击后退出旧进程、安装更新、启动新版；
网络失败或校验失败不会替换当前应用，下次检查可以重试。点击页脚版本号可立即检查，流程相同。

Windows 使用签名清单 `windows-update.json` 及 `windows-update.json.sig`。
使用与 Sparkle 相同的 Ed25519 公钥验证清单后，才接受递增版本；下载地址必须属于
本仓库对应的版本标签。提示前核对安装器字节数及 SHA256，点击升级时再次核对缓存。
安装器等待旧进程退出后原位更新并启动新版，按当前用户安装，不请求管理员权限。

macOS 使用 [Sparkle 2.10.0](https://sparkle-project.org/documentation/) 检查、下载、验证、安装和重新启动。
启用静默准备，由应用接管安装时机。需要系统安装授权时，已下载更新也等窗口激活、
用户点击 **重启升级** 后再继续，避免后台弹系统授权框。Sparkle 也可能在应用正常退出时
应用已准备好的更新，且不会因下载完成而在后台强行重启应用。

自动检查间隔与 [Clash Verge Rev v2.5.6](https://github.com/clash-verge-rev/clash-verge-rev/blob/v2.5.6/src/hooks/use-update.ts#L31-L40)
对齐为 24 小时；其源码里的 1 小时是查询缓存有效期。

GitHub Release 同时承载安装包和更新清单。更新源固定为：

```text
https://github.com/cloydlau/ai-benchgauge/releases/latest/download/appcast.xml
```

更新 DMG 和清单都由 Ed25519 签名。应用在解压前校验签名，
发布脚本会检查私钥与应用内公钥匹配，并用 Sparkle 的官方工具再次验证。
GitHub 的草稿版、预览版不进入稳定版更新源。

## 一次性配置

先构建以下载锁定的 Sparkle 工具，再为本项目生成密钥：

```bash
./make-app.sh
node Scripts/setup-updates.mjs
```

该脚本把私钥保存到 macOS 登录钥匙串的独立账户
`com.cloydlau.ai-benchgauge`，仅把公钥写入 `Info.plist` 和共用的 `config/app.json`。
重复运行会复用原密钥；公钥已有值且与钥匙串不一致时会停止。
提交包含公钥的源码。保留原签名密钥和安全备份，后续版本使用同一把密钥。

为 GitHub Actions 导出一次私钥：

```bash
node Scripts/setup-updates.mjs --export-key
```

在仓库 **Settings → Secrets and variables → Actions → New repository secret**
添加 `SPARKLE_PRIVATE_KEY`，值为导出文件中的一行内容。
也可以使用已登录的 GitHub CLI：

```bash
gh secret set SPARKLE_PRIVATE_KEY < work/update-signing/sparkle-private-key.txt
rm work/update-signing/sparkle-private-key.txt
```

导出文件权限为仅当前用户可读写，位于被 Git 忽略的 `work/`。
私钥不能进入源码、Release 附件或日志。GitHub Actions 只在签名步骤获得这个 Secret，
测试和普通构建不获得私钥。没有配置公钥的本地构建不会启动更新器；发版校验会阻止发布。

## 每次发版

版本号采用 `主版本.次版本.修订版本`，例如 `1.0.1`。使用递增版本：

```bash
./Scripts/bump-version.sh 1.0.1
./test.sh
# 提交并推送版本号和本次源码后：
git tag v1.0.1
git push origin v1.0.1
```

推送 `v*` 标签会运行 `.github/workflows/release.yml`：

1. 检查标签来自 `main`，与应用版本、构建版本一致，且高于已发布稳定版。
2. 分别在 macOS / Windows 执行共享核心测试、脚本和 Windows 验签测试；Windows 还检查原生窗口及打包引擎。
3. 构建 Apple 芯片与 Intel 通用 `.dmg`、Windows x64 自包含安装 `.exe`，生成含发布说明的更新清单，签名并验证，生成 Homebrew Cask 与 SHA-256 清单。
4. 将所有附件上传为 GitHub 草稿 Release，完整上传成功后发布并设为最新稳定版。
5. 发布成功后，用 GitHub Contents API 把 `Casks/ai-benchgauge.rb` 更新到 `main`，Cask 始终指向当前版本的固定 DMG 地址。

最终附件为 `AI-BenchGauge-版本-macos-universal.dmg`、`AI-BenchGauge-版本-windows-x64-setup.exe`、`appcast.xml`、`windows-update.json`、`windows-update.json.sig`、`ai-benchgauge.rb` 和 `SHA256SUMS.txt`。
首次 Release 成功后，`main` 会包含 `Casks/ai-benchgauge.rb`。用户可通过仓库 tap 安装：

```bash
brew tap cloydlau/ai-benchgauge https://github.com/cloydlau/ai-benchgauge
brew install --cask ai-benchgauge
```

Cask 复用同一个 Developer ID 签名 / 公证 DMG，并设置 `auto_updates true`；日常更新仍由应用内 Sparkle 完成。需要强制同步 Homebrew 记录的版本时，可使用 `brew upgrade --cask --greedy ai-benchgauge`。
失败不会更新线上稳定版清单。已发布的版本不覆盖；修正问题后使用更高版本号。
若仅发布草稿的最后一步失败，可在 GitHub 确认附件齐全后手动发布该草稿。

不带更新器的旧版本，需要先手动安装一次带更新器的版本；之后才会收到应用内更新提示。
已发布的 `0.0.0` 带更新器，但采用旧的“先确认、再下载”流程。它可以收到下一次 `0.0.1`
的更新通知；需先完成这次升级，新的后台下载和强制提示流程才对该用户生效。
仅发布新清单不能改变用户电脑上旧版本的交互逻辑。
用户将应用放在可写的 Applications 目录后再启动，更新器才能直接替换并重启它。

## Apple 签名与公证（可选）

Ed25519 更新签名与 Apple Developer ID 签名是两件事。
默认构建保留现有的临时签名方式，下载后的首次启动仍可能需要在 macOS 中允许打开。
如有 Apple Developer ID，可配置以下 GitHub Secrets：

| Secret | 值 |
| --- | --- |
| `APPLE_CERTIFICATE` | Developer ID Application 证书及私钥的 `.p12` 文件，base64 编码 |
| `APPLE_CERTIFICATE_PASSWORD` | `.p12` 的密码 |
| `APPLE_SIGNING_IDENTITY` | 完整 Developer ID Application 名称 |
| `APPLE_ID` | 公证用 Apple ID |
| `APPLE_APP_PASSWORD` | Apple ID 的应用专用密码 |
| `APPLE_TEAM_ID` | Apple Developer Team ID |

提供证书时会使用 Hardened Runtime，逐层签名 Sparkle 的辅助进程、框架和应用。
提供公证凭据时会提交 Apple 公证并附上票据，再生成最终签名更新包。
临时签名构建也会逐层签名并验证完整应用，不需要 Apple 账号即可验证本地流程。

## 本地验证

```bash
DESKTOP_NOTIFY=0 TEST_AUTO_REPAIR=0 APP_UNIVERSAL=1 ./make-app.sh
```

`Scripts/release.test.mjs` 覆盖版本排序与回退、配置缺失、公私钥不匹配、
安装包篡改、清单篡改和发布说明转义。可运行 `./test.sh --scripts`。
源码、依赖锁文件与工作流变更都使本地测试通过凭据失效。
本地脚本不创建或发布 GitHub Release；线上发布只由标签工作流执行。

## Windows 构建

开发与原生检查见 [Windows 说明](../apps/windows/README.md)。
`windows-build.yml` 是 CI 与 Release 共用的构建流程，发布时启用 NSIS 安装器。
普通构建没有签名私钥；`complete-release.mjs` 在汇总阶段签 Windows 更新清单，
并重新生成包含两种安装包和两种清单的校验和。

安装器包含微软官方 WebView2 引导安装器，构建时检查 Authenticode 的微软签名；
仅当运行时缺失时联网安装。没有运行时且无法联网时，排行榜、其他余量和 CLI 回退仍可用。
Windows 安装器的 Authenticode 发行证书属于独立配置；当前更新签名不代替该证书。

## iPhone / iPad

The universal iPhone/iPad edition has a separate simulator/device build check in `.github/workflows/ipad.yml`. A desktop GitHub release does not publish a mobile build. Both device families use one iOS app record, bundle ID and universal archive; include iPhone and iPad screenshots in the store listing ([Apple screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)). It needs Apple signing and distribution through TestFlight/App Store; see [the iPad build and distribution guide](../apps/ipad/README.md). The Xcode project generator reads the same marketing version from `config/app.json`, while `IPAD_BUILD_NUMBER` supplies the integer App Store Connect build number. No public mobile build has been published yet.

### 自测后直接上架 App Store

当前计划是先看 iPad 原生界面，在模拟器和自己的 iPad 上测试通过，再提交 App Store 正式版。**TestFlight 是可选渠道，不是上架前必须完成的步骤**；正式版获准发布后，用户直接从 App Store 安装。[Apple 发布说明](https://help.apple.com/xcode/mac/current/en.lproj/dev442d7f2ca.html)

1. **预览和自测。**安装完整 Xcode，运行 `node Scripts/ipad-project.mjs`，打开工程，在 BenchGauge scheme 中选择 iPhone 或 iPad 模拟器并运行。要在自己的 iPhone 或 iPad 上测试，连接设备，在 Signing & Capabilities 中选择自己的 Team，再选择该设备运行，无需安装 TestFlight。按 [iPad 验收说明](../apps/ipad/README.md#develop-and-verify)检查横竖屏、分类/国家筛选、公司分数详情、离线重启、语言、深色模式、大字和分享。
2. **准备正式发行。**使用 Apple Developer Program 账号创建 App Store Connect 应用记录；Bundle ID 为 `com.cloydlau.ai-benchgauge.ipad`。按 Apple 当前要求使用 Xcode 26 或更高版本构建，配置签名，用新的 `IPAD_BUILD_NUMBER` 执行下方归档命令，再从 Xcode Organizer 的 TestFlight & App Store 通道上传。这个通道名不要求创建测试组或邀请测试员。[Apple 上传要求](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/)

   ```bash
   APPLE_TEAM_ID=YOURTEAMID IPAD_BUILD_NUMBER=1 node Scripts/ipad-build.mjs archive
   open work/ipad/AI-BenchGauge.xcarchive
   ```

3. **填写商店资料并提交审核。**准备应用说明、实际 iPhone 和 iPad 截图、支持及隐私政策网址、隐私声明、年龄分级、审核联系人和价格/地区配置。在 App Store Connect 的应用版本页面选择已处理好的构建，点击 Add for Review，再点击 Submit for Review。当前排行榜版无需登录，可在审核说明中注明。[Apple 提交审核步骤](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app)
4. **获准后发布。**审核通过后按所选的正式版发布方式发布，并把实际 App Store 地址放回 README。用户通过 App Store 安装和更新，无需邀请或 TestFlight。后续版本仍需上传新的签名构建并完成商店发布流程。

模拟器截图和自动化测试可帮助发现问题，但不能代替真实 iPhone 和 iPad 的触控、旋转、大字、联网及截图复制验收。当前尚未完成 Apple 签名、实机验收或正式上架；本节是发行步骤，不代表应用已可下载。

### TestFlight 分发流程（可选）

TestFlight 是 Apple 的测试版分发渠道：发布者上传应用，用户通过邀请安装，收集反馈后再决定正式上架。每个构建最多可测试 90 天，长期提供应用需要持续上传新构建或发布 App Store 正式版。[Apple 流程说明](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/)

这位反馈问题的普通用户应作为**外部测试员**邀请，无需给他 App Store Connect 后台权限。以下操作目前需要发布者完成，仓库没有自动上传或生成邀请链接。

1. **准备账号和应用记录。**加入 Apple Developer Program，在 Xcode 登录开发者账号，注册 Bundle ID `com.cloydlau.ai-benchgauge.ipad`，在 App Store Connect 创建对应的 iOS 应用记录。它是支持 iPhone 与 iPad 的同一个 iOS 应用记录，不需要分别建应用、分别发版。准备真实的联系邮箱及审核联系人。
2. **配置签名并验收。**安装完整 Xcode，运行 `node Scripts/ipad-project.mjs` 并打开生成的工程，在 BenchGauge target 的 Signing & Capabilities 中选择你的 Team，完成自动签名配置。运行 `node Scripts/ipad-build.mjs check`，并按 [iPad 验收说明](../apps/ipad/README.md#develop-and-verify)做实机检查。目前 Apple 要求上传的 iOS 应用使用 Xcode 26 或更高版本构建；本地最低编译要求不等于商店的上传要求。[Apple 上传要求](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/)
3. **打包并上传。**从仓库根目录执行下面的命令，替换 Team ID；每次上传使用新的整数 build number。归档后在 Xcode Organizer 选择 **Distribute App → TestFlight & App Store**，完成验证和上传。不要选择 **TestFlight Internal Only**，这种构建不能发给外部测试员。等待 Apple 处理完成，构建才会出现在 App Store Connect。

   ```bash
   APPLE_TEAM_ID=YOURTEAMID IPAD_BUILD_NUMBER=1 node Scripts/ipad-build.mjs archive
   open work/ipad/AI-BenchGauge.xcarchive
   ```

4. **填写测试信息并送审。**进入 App Store Connect → Apps → 本应用 → TestFlight，填写 Beta App Description、Feedback Email、审核联系人和 What to Test。当前应用无需登录，可在审核说明中写明。先创建内部测试组，再创建外部测试组，将已处理的构建加入外部组，按页面状态选择 Submit Review / Start Testing。首次外部测试构建需要审核，后续同版本构建也可能需要审核；可勾选 Automatically notify testers，在批准后通知用户。[测试信息说明](https://developer.apple.com/help/app-store-connect/test-a-beta-version/provide-test-information/)、[外部测试与审核说明](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers/)
5. **邀请用户安装。**构建获准测试后，在外部测试组中用邮箱邀请这位用户，或通过 Create Public Link 创建邀请链接。用户在 iPad 的 App Store 安装免费的 TestFlight，打开邀请邮件或链接，接受邀请后安装 AI BenchGauge。此时应用通过 TestFlight 提供，还没有正式上架 App Store。[用户安装流程](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/)
6. **后续更新。**修复问题后递增 `IPAD_BUILD_NUMBER`，重新归档、上传并把新构建加入测试组，按 Apple 页面要求完成审核/开始测试。用户通过 TestFlight 获取新版；留意构建到期日期，在旧构建到期前提供新的可测试构建。GitHub 的 DMG/EXE 发版不会更新 iPad 应用。正式上架仍需另行提交 App Store 审核。

当前状态：已提供工程、原生构建检查和归档命令；尚未完成 Apple 签名、TestFlight 上传、测试审核或用户邀请。TestFlight 审核通过也不等于正式版已上架。
