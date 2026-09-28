# macOS / Windows 更新与发版

每个版本发布两种安装格式：Mac 通用 `.dmg` 与 Windows x64 `-setup.exe`。
两端共用 `config/app.json` 的版本号和更新公钥。只有两边的构建都成功，
汇总任务才创建草稿 Release 并公开，避免用户收到缺少某个平台的版本。

Windows 每小时读取签名清单 `windows-update.json` 及 `windows-update.json.sig`。
使用与 Sparkle 相同的 Ed25519 公钥验证清单后，才接受递增版本；下载地址必须属于
本仓库对应的版本标签。安装前核对清单中的字节数及 SHA256，用户确认后
下载、等待旧进程退出、原位安装并重启。程序按当前用户安装，不请求管理员权限。

macOS 使用 [Sparkle 2.10.0](https://sparkle-project.org/documentation/)
检查、下载、验证、安装和重新启动。应用运行期间默认每小时检查一次；
发现新版本后提示用户，点击 **Install Update / 安装更新** 后继续下载、安装并重启。
下载途中可以取消，网络失败或校验失败会保留当前应用。
点击应用标题旁的版本号可立即检查更新。

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
3. 构建 Apple 芯片与 Intel 通用应用、Windows x64 自包含程序，并打包 ZIP，生成含发布说明的更新清单，签名并验证两者，生成 SHA-256 清单。
4. 将所有附件上传为 GitHub 草稿 Release，完整上传成功后发布并设为最新稳定版。

最终附件为 `AI-BenchGauge-版本-macos-universal.zip`、`appcast.xml` 和 `SHA256SUMS.txt`。
失败不会更新线上稳定版清单。已发布的版本不覆盖；修正问题后使用更高版本号。
若仅发布草稿的最后一步失败，可在 GitHub 确认附件齐全后手动发布该草稿。

不带更新器的旧版本，需要先手动安装一次带更新器的版本；之后才会收到应用内更新提示。
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
