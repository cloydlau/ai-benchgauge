# License notice inventory

The footer opens one license sheet from two entries: **License** selects
the application license, and **Open-source notices** selects third-party
notices. Complete notices are bundled locally and are selectable and scrollable.

## Current software inventory

- `Package.swift` pins Sparkle **2.10.0**, resolved at
  `eef1a539a373c1f1a320624b1130fc5de7b2e100` in `Package.resolved`.
  Packaging embeds its universal macOS framework and updater helpers.
  The complete upstream distribution `LICENSE`, including its component notices,
  is bundled as `Resources/Licenses/Sparkle.txt` and listed in `ThirdParty.json`.
- `LeaderboardCore` and `leaderboard-menu` are this repository's own targets.
- The application license is the repository's `LICENSE`: PolyForm Perimeter License 1.0.0,
  with the project's licensing notices, copyright 2026 Cloyd Lau. Display identity is shared
  through `Sources/LeaderboardKit/Resources/ApplicationLicense.json`. Packaging copies it into `Resources/Licenses/AI-BenchGauge.txt`.
- The executable dynamically links the macOS system frameworks, Swift runtime,
  and `/usr/lib/libsqlite3.dylib`; no copies of those libraries are shipped.
  [SQLite's deliverable code is public domain](https://sqlite.org/copyright.html).
- CC Switch's native quota adapters reference its request and response contracts
  at revision `7c0d0fc615f7e9391de9784958c918368455cbcc` (MIT, copyright
  2025 Jason Young). The full notice is bundled as `CC-Switch.txt` on both
  desktop platforms and listed in the macOS `ThirdParty.json`. The adapter
  implementation is Swift; the CC Switch executable and JavaScript runtime
  are not bundled. Sources: [subscription queries](https://github.com/farion1231/cc-switch/blob/7c0d0fc615f7e9391de9784958c918368455cbcc/src-tauri/src/services/subscription.rs),
  [Coding Plan queries](https://github.com/farion1231/cc-switch/blob/7c0d0fc615f7e9391de9784958c918368455cbcc/src-tauri/src/services/coding_plan.rs),
  and [balance queries](https://github.com/farion1231/cc-switch/blob/7c0d0fc615f7e9391de9784958c918368455cbcc/src-tauri/src/services/balance.rs).
- Codex CLI and qianwen CLI remain external integrations; their executables
  are not distributed in this app.

The Sparkle notice above covers the bundled update framework. Brand artwork
is tracked separately below.

## GitHub icon provenance confirmed

On 2026-10-28, the old `assets/logos/github.png` was replaced with a deterministic
export of **`tabler:brand-github-filled`**, selected through
[Icones](https://icones.js.org/collection/tabler?s=brand-github).
The unmodified SVG and complete MIT license are kept in
[`assets/brand/partners/github`](../assets/brand/partners/github/README.md).
`source.json` records revision `ed177a085b652fe04ec4f37ced867c94621e7840`,
exact download URLs, source/license SHA-256 hashes and export settings.
`node Scripts/source-logos.mjs --check` checks both hashes and generated copies.

The same 128×128 transparent PNG serves macOS/Windows repository buttons,
and GitHub Actions contributor avatars in the
mini-program and iPhone/iPad. The original MIT text, copyright
2020–2026 Paweł Kuna, is shipped in the macOS `Tabler.txt` manifest entry,
Windows `Licenses/Tabler.txt` and both mobile clients' source-mark notices.
The artwork license does not grant GitHub trademark rights or imply endorsement.
This replacement confirms the new asset's provenance; it does not retroactively
attribute the removed PNG to Tabler.

## Supplier PNG removal and shared images — 2026-10-28

The other **53 supplier PNGs** and `assets/logos/company-catalog.json` have
been removed. The directory now contains only the traceable GitHub export.
This resolves the incomplete provenance inventory for these bundled files by
removing them, rather than asserting an unverified license. The removed set
comprised 30 legacy images with no verified per-file attribution and 23 newer
company images whose page/download URLs and hashes did not establish artwork
redistribution permission. Git history retains their previous records.

macOS, Windows, iPhone/iPad, the mini-program and leaderboard exports use PNGs
provided with shared leaderboard snapshots, with initials when unavailable.
There is no local supplier PNG or direct-favicon download fallback. Desktop
quota cards reuse manufacturer images from **all cached boards**, matched by
provider identity rather than account labels. Dedicated model marks cannot
become quota provider icons. Snapshot persistence preserves shared images for
offline use; a provider absent from all downloaded boards shows its initial.

The image service is separate from models.dev, which supplies model metadata.
Removing local PNGs does not establish redistribution permission for remote
artwork. The shared service's source URLs, acquired artwork and embedded
`fc/brand-catalog.json` images remain a separate rights inventory; availability
from a website is not recorded as written authorization. Brand trademarks
remain owned by their respective holders. No complete artwork-rights clearance
is claimed by this change.

## Backend coverage reconciliation — 2026-10-28

The 53 supplier identities removed from client asset bundles were compared
with `fc/brand-catalog.json`. **52 already had server-side PNGs; Video Rebirth
was the only missing identity.** Its image is now supplied by the same backend
catalog rather than restoring client-local PNGs. The server catalog now has
62 provider marks, plus the existing 7 dedicated model marks. This is source
code coverage, not confirmation of what an already deployed service contains.

Video Rebirth's official homepage declares `/fav-icon.svg` as its favicon.
The new entry uses `https://www.videorebirth.com/fav-icon.svg`, normalized by
`fc/brands.mjs` into a 64×64 PNG. Its provenance records retrieval time,
source SHA-256 `e325f09d2e7be3d572554c0c2b409f2a5a46926de7e328b1ccef584b4e0c6dc5`
and output SHA-256 `088349df1f7fa0b9dd09f51ee7dd66c2dee53df85650da21684f76706b3ca66d`.
This identifies the source without copying an unattributed historical PNG.
The entry explicitly records artwork permission as **not confirmed**.

`Scripts/provider-logo-coverage.test.mjs` retains the 53 former client keys
as an independent acceptance inventory and exercises shared images with cold
storage, unavailable storage and saved snapshots. The other 52 images were
already in the backend and have not been duplicated or retroactively granted
permission by this reconciliation. All 52 focused tests pass, including the
3 new backend-coverage checks. No deployment is performed here.

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
WebView2 Evergreen Runtime 由微软独立安装和更新，运行时条款由微软安装程序提供；SDK 的完整声明随本应用分发。
SQLite 使用系统库，不打包第三方 SQLite 二进制。

## iPad edition

The universal iOS target links the repository's own `LeaderboardKit` and `LeaderboardPadUI` plus Apple system frameworks. It does not ship Sparkle, SQLite, desktop command-line integrations, Windows dependencies, or desktop quota adapters. It uses the shared snapshot images and initial fallback described above; supplier PNGs are not bundled. The separately licensed GitHub export remains available for repository and contributor UI. The complete project licensing notices and PolyForm Perimeter License 1.0.0 are bundled in `apps/ios/UI/Resources/AI-BenchGauge.txt`. The current mobile footer has no application-license entry. Third-party notices retain their respective original licenses.


## Chinese brand calligraphy

The Chinese header uses 演示夏行楷 / Slide Xiaxing 1.000 by the SlideFont Project Authors, under [SIL OFL 1.1](https://github.com/maoken-fonts/slidefont/blob/main/OFL.txt). Only the space and “天梯” glyphs are bundled in a 4,888-byte subset, renamed **BenchGauge Calligraphy**. `Scripts/generate-brand-font.py` reproduces it from `Slidexiaxing-Regular.ttf` whose SHA-256 is `fac1f0ec044b63aa45c0775c17a2f03cbf6427b4bd7b93da87dde9e7e2020cfc`. The source copyright remains in font metadata and the complete upstream license is packaged offline.

The same subset is registered via CoreText by the shared Apple library and embedded as a WPF font resource. In Chinese branding, upright system semibold “AI” at 21 pt accompanies calligraphic “天梯” at 25 pt. Each glyph's actual ink bounds determines its position, leaving a 2.5-point visible gap between A, I, 天 and 梯; all four share one baseline. The title remains accessible as “AI 天梯”. English branding retains Snell Roundhand / Segoe Script. Mac, Windows and iOS include the full OFL notice in their offline license views.

The mini-program uses offline vector outlines of the same Apple title fonts: system semibold I, BenchGauge Calligraphy 天梯, and Snell Roundhand Bold for English. `swift Scripts/weapp-brand-glyphs.swift` regenerates the light/dark SVG artwork and Canvas contours on macOS. The leaderboard, About page and exported images share these outlines and visible glyph geometry; no network font load or device font fallback is needed. The original logo replaces A and its visible bottom aligns with I. The full SlideFont OFL notice is included in the package and the About page's offline notices.
