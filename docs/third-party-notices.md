# License notice inventory

The footer opens one license sheet from two entries: **MIT License** selects
the application license, and **Open-source notices** selects third-party
notices. Complete notices are bundled locally and are selectable and scrollable.

## Current software inventory

- `Package.swift` pins Sparkle **2.10.0**, resolved at
  `eef1a539a373c1f1a320624b1130fc5de7b2e100` in `Package.resolved`.
  Packaging embeds its universal macOS framework and updater helpers.
  The complete upstream distribution `LICENSE`, including its component notices,
  is bundled as `Resources/Licenses/Sparkle.txt` and listed in `ThirdParty.json`.
- `LeaderboardCore` and `leaderboard-menu` are this repository's own targets.
- The application license is the repository's `LICENSE`, MIT, copyright
  2026 Cloyd Lau. Packaging copies it into `Resources/Licenses/AI-BenchGauge.txt`.
- The executable dynamically links the macOS system frameworks, Swift runtime,
  and `/usr/lib/libsqlite3.dylib`; no copies of those libraries are shipped.
  [SQLite's deliverable code is public domain](https://sqlite.org/copyright.html).
- CC Switch, Codex CLI, and qianwen CLI are external integrations, not bundled
  dependencies. Their source code and executables are not distributed in this app.

The Sparkle notice above covers the newly bundled update framework. This is
**not a completed provenance audit of the bundled brand images**.

## Brand image provenance still needs confirmation

The 31 PNGs in `Resources/logos` have no original download URLs, package versions,
or license records. Their introduction in commit
`9341a69f55c4c8515e92c456f86c7218c3aef51c` describes official favicons and
Iconify, but does not identify the source of each file. Similarity to a brand
mark does not establish which icon collection supplied it.

An audit compared the PNG byte hashes with `@lobehub/icons-static-png` 1.97.1:
none matched. Some rendered marks look similar, which is insufficient to
attribute the existing images to that library. Do not list Lobe Icons as a
confirmed dependency on that basis.

The upstream collections investigated have different terms:

- [Lobe Icons](https://github.com/lobehub/lobe-icons/blob/master/LICENSE): MIT;
  retaining the copyright and full license notice would be required for its
  distributed assets.
- [SVG Logos](https://github.com/gilbarbara/logos/blob/master/LICENSE.txt) and
  [Simple Icons](https://github.com/simple-icons/simple-icons/blob/develop/LICENSE.md):
  CC0 1.0; neither was confirmed as the source of every bundled image.
- [Hugeicons](https://github.com/iconify/icon-sets/blob/master/json/hugeicons.json):
  MIT in Iconify's metadata. The `grok` and `grok-02` shapes examined do not match
  the bundled `spacexai.png`. The development notification script's fallback
  URLs do not demonstrate use in the distributed application.

Confirm the original sources before describing the image notice inventory as
complete. Open-source license notices also do not grant rights in brand trademarks.

## Adding a required notice

Place its unabridged upstream copyright/license text in
`apps/macos/Sources/Resources/Licenses/`, then add an entry to
`ThirdParty.json` with `id`, `name`, `license`, `source` (an HTTPS project URL),
`englishDescription`, `chineseDescription`, and `file` (the local notice filename).
The sheet lists all entries; each retains its own full text and source link.
Record the exact source version and included resources here as well.

SwiftPM copies this directory for `swift run`. `Scripts/make-app.sh` copies it
into the signed `.app`, overriding the application notice with the current
repository `LICENSE`. Check that every manifest entry has a nonempty local
notice before release.

## Windows 分发

Windows 使用 .NET / WPF / WinForms、Swift / Foundation / libdispatch、Bouncy Castle、微软 WebView2 SDK 与 NSIS 安装器。
完整许可保存在 `apps/windows/Licenses/`，包含运行时上游第三方声明；构建时还复制 Swift 分发自带的 LICENSE / NOTICE。
这些文本随安装包分发，可从底部声明弹窗离线查看。
NSIS 3.11 LZMA 模块使用 CPL 1.0 及其链接例外，未修改源码来自 https://github.com/kichik/nsis/tree/v311。
WebView2 Evergreen Runtime 由微软独立安装和更新，其条款与 SDK 声明一并提供。
SQLite 使用系统库，不打包第三方 SQLite 二进制。
