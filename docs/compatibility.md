# 系统兼容与 Intel Mac 支持

核对日期：2026-09-29。安装包的平台和处理器范围见各语言 README 中的系统兼容性表。

## macOS

应用最低要求 macOS 14 Sonoma，`Package.swift`、`Info.plist` 与两个架构的二进制最低系统版本均为 14.0。
Apple 芯片（arm64，M1 / M2 及后续芯片）和 Intel（x86_64）共用一个 Universal `.dmg`，各自运行原生代码，不依赖 Rosetta。
Intel 机型必须能运行相应的 macOS 14、15 或 26；无法升级到 macOS 14 的旧机型不在支持范围内。
[Apple 的 macOS Tahoe 26 机型清单](https://support.apple.com/en-gb/122867)可用于核对能否升级到 26。

本地 `./make-app.sh` 默认构建当前 Mac 的架构；跨两种芯片分发时使用 `APP_UNIVERSAL=1 ./make-app.sh`。
普通 CI 和 Release 都启用通用构建；发版脚本还通过 `lipo` 检查 arm64、x86_64 是否同时存在，缺少任何一个架构会阻止发版。

已验证两种架构均可编译，Universal 可执行文件同时包含 arm64 / x86_64，两个架构的最低系统版本均为 macOS 14.0。
当前开发机和 macOS CI 的实际运行测试在 Apple 芯片上进行，尚未完成 Intel 实机界面验收，不能将交叉编译等同于所有 Intel 机型实测。

## Windows

应用兼容目标是 Windows 10 / 11 的 Intel、AMD 64 位系统，安装器拒绝 Windows 7 / 8 / 8.1 与 32 位 Windows。
当前只提供 `win-x64` 安装包，不提供原生 ARM64 包，也未验证 Windows on ARM 的 x64 模拟运行。
安装包内含 .NET 桌面运行时、Swift 引擎及所需运行库，用户无需自行安装开发工具。

Windows 版使用 .NET 10。按 [Microsoft 的系统支持列表](https://learn.microsoft.com/en-us/dotnet/core/install/windows#supported-versions)，
截至核对日期，Windows 10 的官方维护范围限仍受维护的 LTSC / Enterprise 版本，列有 21H2、1809、1607；
Windows 10 Home / Pro 不在该列表中，本项目尚未完成这些版本的实机验证，不承诺所有 Windows 10 版本均可正常运行。
这一区分不影响安装器允许 Windows 10，但不能用安装器允许安装来证明某个版本已验证兼容。

Windows CI 在 Windows Server 2022 runner 上验证共享核心、更新验签、原生窗口、打包引擎、静默安装卸载和保留用户数据。
该检查不等于逐一验证了 Windows 10 / 11 的所有版本、版本类型和机器配置。
千问网页登录使用 WebView2，安装器在缺少该运行时时调用微软引导安装器。

## iPad

原生排行榜版的最低目标是 iPadOS 17，适用于能运行该系统的 iPad，不限定 M 系列芯片。工程、Info.plist 和共享包的最低系统版本保持一致。采用单窗口、全屏优先展示，不提供桌面的展示模式选择，支持横竖屏。旧系统的 Split View / Slide Over 模式下请求固定全屏；Stage Manager 及 iPadOS 26 起的系统窗口模式由用户控制，不能保证始终占满整块屏幕。详见 [Apple 全屏兼容说明](https://developer.apple.com/documentation/bundleresources/information-property-list/uirequiresfullscreen)。

已加入原生源代码、项目生成器及独立的 iPad CI；尚未发布 TestFlight / App Store 版本。2026-10-01 的 [iPad 原生检查](https://github.com/cloydlau/ai-benchgauge/actions/runs/36820908883)在源码 `88e3f07f9783873a25643150cf596318c083c80e` 上通过模拟器与设备 SDK 的 Release 构建，以及四项模拟器界面测试。已人工查看 [原生截图及测试结果](https://github.com/cloydlau/ai-benchgauge/actions/runs/36820908883/artifacts/11143871994)，覆盖三种语言、横竖屏、模型／公司榜、完整 20 行测试榜单、长名称、未知国家、深色界面、离线状态、来源说明、许可证及截图复制。文案、图标、更新时间、筛选逻辑和底部入口已对齐桌面，移除额外的 iPad 设置页。环境为 iPad Pro 13 英寸（M5）模拟器、iPadOS 26.2、实际 2× 缩放，CI 使用 macOS 15.7.9 / Xcode 16.4。尚未完成 iPad 实机、小尺寸设备、真实完整榜单、大字、空榜及其他 iPadOS 版本验收。开发机只有 Command Line Tools，原生检查在 GitHub Actions 的 Xcode 环境完成。详细构建、验收与分发步骤见 [iPad 说明](../apps/ipad/README.md)。首版提供排行榜，暂不提供电脑的 CC Switch 余量；更新由 TestFlight / App Store 管理。

## Intel 是否值得保留

**决定：继续提供原生 Intel Mac 支持。** 现有共享业务逻辑和原生 Mac 界面无需维护另一套实现；增加 x86_64 构建即可与 arm64 合成通用应用。

本应用没有用户芯片占比统计，不能断言自身 Intel 用户达到 5%。外部数据仅作为产品决策参考：

| 来源 | 时间与样本范围 | Intel 占比 |
| --- | --- | --- |
| [Steam 硬件调查](https://store.steampowered.com/hwsurvey/?platform=mac) | 2026 年 8 月，自愿参与调查的 Steam Mac 用户，Processor Vendor (OSX) 的 GenuineIntel 项 | 11.08% |
| [Omnissa《State of Digital Workspace 2026》](https://omnissa.bynder.com/m/78193e6f0268503f/original/State-of-Digital-Workspace-2026.pdf#page=9) | 企业管理的 Mac 设备样本，第 9 页 CPU 分布 | 21% |

这两个样本均超过 5%，但不代表全部 Mac 用户或本应用用户，也没有单独给出可运行 macOS 14+ 的 Intel 用户占比。
结合已有通用构建和较低的增量维护成本，保留 Intel 是合理选择。后续若评估调整，应重新核对外部数据和依赖的架构支持情况。
