# AI BenchGauge for iPhone and iPad

Universal native SwiftUI app for iOS / iPadOS 17 or later. There is currently no public TestFlight invitation or App Store release.

The mobile interface follows the mini-program: the shared calligraphic title, subtitle help and model/company selector form an adaptive header; a floating glass category bar stays at the bottom. English displays only the main title and does not reserve space for the subtitle. Simplified and Traditional Chinese retain the two subtitle sentences, each on one line. Brand and caption share a continuous fitting scale based on the available width; the help icon overlays the right edge without participating in text layout, and navigation controls and the help hit target keep their original size. Narrow windows switch boards with the existing cube gesture. The source selector stays outside the rotating faces and scrolls away with their content. Wider windows use a two- or three-column grid, with at least 360 points per board, based on the live available width rather than the device family. Narrow grid cards use compact source symbols so names remain readable. Folding, resizing and rotation settle interrupted cube animations while retaining the current source, query and filters. The first entrance reveal yields immediately to interaction and respects Reduce Motion.

Country flags and model source symbols are tappable: a native popover spells out the localized country name or Open / Closed / Unknown status. Tap outside to dismiss it. Image exports retain the plain symbols.

All eight leaderboards share one country filter and one openness filter. Choices survive category/source changes and relaunch, and country options include the union of cached boards. Old per-board preferences migrate from the visible category; clearing a global filter takes precedence over older saved values. Models retain their source ranks. Company standings use the strongest matching model. A model-name tap copies its complete name; company names and scores open company score details.

Cached rows remain visible during refresh. An uncached request shows table-shaped skeleton rows sized to fill the current viewport, including after rotation; a finished empty request shows the empty state. Each live board has one latest source/fetch timestamp and quiet automatic refresh. Existing shared-service refresh/contribution rules remain in place, and source failures keep the previous data and original timestamps.

The scrolling footer contains About, language, appearance and screenshot actions. About includes the app version, desktop-download/source links that can be copied, and expandable offline font notices with neutral numbering. The live mobile interface does not display author attribution, desktop purchase links or the application-license menu. Language follows the system until an explicit choice is saved; English, Simplified and Traditional Chinese and system/light/dark appearance are supported.

The camera opens an image preview. Complete filtered comparisons are generated from a frozen data/settings snapshot in pages of up to 24 rows per source, with generation progress shown on screen. Pages retain full model names, source ranks and filter labels, can be browsed or copied individually, and can all be saved to Photos. Saving retries resume at the first unsaved page. Images are generated sequentially into temporary files; closing the preview cleans them up. An optional numeric App Store ID in `config/app.json` enables the existing region-independent download credit; unpublished apps retain a plain app-name credit.

Desktop account quotas, login and analytics are not part of this app. Data remains in the app sandbox. Shared metadata and PNGs persist with cached boards and render offline. iPhone supports portrait and both landscape orientations; iPad supports all orientations.

## Local iPhone auto-update with Calmmit

The local Calmmit `check`, `commit` and `push` profiles now finish with `iosDeploy`. `./dev.sh` also queues a phone update at startup and after changes, including when Mac auto-deployment is disabled. Enabling this is local and optional: create an ignored `.benchgauge-ios.local.json` with `{"enabled":true,"device":"YOUR_DEVICE_UDID","team":"YOUR_APPLE_TEAM_ID","launchAfterInstall":true}` after pairing your phone and configuring the developer account in Xcode. The default full Xcode path is `/Applications/Xcode.app/Contents/Developer`; an optional `developerDir` overrides it without changing `xcode-select`.

The exact current sources must pass syntax checks, all script/shared Swift tests and an unsigned iOS simulator SDK build before entering the queue. The independent worker then builds and verifies an Apple Development signed universal app, installs it over the same `com.cloydlau.ai-benchgauge.ipad` Bundle ID, and opens it. Existing Mac development and public distribution continue using their respective flows. This does not upload to TestFlight/App Store or approve the protected human release review.

Generated projects, copied icon resources, build products, receipts and logs live in ignored `work/ios-deploy/`; the Xcode project you open manually is not rewritten by this updater. New sources arriving during checks/builds prevent installing that candidate. Offline phones retain the queue and retry every 30 seconds; new candidates wake the worker through file events. Once installed with no pending work, the updater does not poll the phone. Signing/build errors pause that candidate; installation errors retry the existing signed build. A locked phone that rejects launch still counts as successfully installed, so it is not repeatedly installed.

Use `node Scripts/ios-deploy.mjs status` to inspect the last status, `retry` after correcting account/signing issues, or `stop` to disable local phone updates. Details are in `work/ios-deploy/deploy.log`. Updates work over a cable or a reachable, previously paired wireless connection; device identifiers and team configuration stay out of Git.

Local verification on 2026-10-11: the Calmmit check profile passed script tests, 283 shared Swift tests, desktop packaging and the iOS simulator SDK build. A separate physical-device SDK Debug build passed Apple Development signing, strict signature verification and Bundle ID validation; its provisioning profile covers the configured test iPhone. Local updater and restarted development watcher are running. The phone is offline, so actual automatic installation/launch remains pending. This updates the historical signing limitation below; real-device UI and public distribution remain separate checks.

## Presentation policy

`UIApplicationSupportsMultipleScenes` is disabled. `UIRequiresFullScreen` requests full screen on older systems using Split View / Slide Over. Apple allows Stage Manager to show even full-screen compatibility apps in windows, and deprecates that compatibility mode from iPadOS 26. `UIRequiresFullScreenIgnoredStartingWithVersion = 26` avoids scaling the entire interface in newer windowing modes; the existing adaptive layout fits the system-provided size. Thus the app offers no presentation-mode choice, but cannot force users out of system windowing. See [Apple's full-screen behavior](https://developer.apple.com/documentation/bundleresources/information-property-list/uirequiresfullscreen) and [migration guidance](https://developer.apple.com/documentation/technotes/tn3192-migrating-your-app-from-the-deprecated-uirequiresfullscreen-key).

## One application for both devices

`TARGETED_DEVICE_FAMILY = 1,2` enables both iPhone and iPad in the existing app target. The bundle ID remains `com.cloydlau.ai-benchgauge.ipad`, despite its historical suffix: use one App Store Connect iOS app record, one universal archive and one marketing version, with screenshots for both device families ([Apple screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)). No separate phone publication is needed. Mobile sources live in `apps/ios`, with `Scripts/ios-*` build entry points and `.github/workflows/ios.yml` covering both device families. The existing internal `LeaderboardPadUI` library name and bundle identifier remain compatible with earlier builds.

## Structure

- `Sources/LeaderboardKit`: portable data models, parsing, fetching, cache, ranking, filtering and refresh policy; also used by both desktop editions.
- `apps/ios/UI`: shared Apple SwiftUI presentation and observable store. The ordinary Mac test run compiles this module and tests its state transitions.
- `apps/ios/App`: universal iOS app entry point, icon, Info.plist and privacy manifest. Debug-only fixtures make simulator tests independent of the live sources.
- `apps/ios/UITests`: simulator checks for categories, grouping, filters, orientation, cached offline results, license notices and screenshot copying.
- `Scripts/ios-project.mjs`: generates a deterministic, ignored Xcode project using the version from `config/app.json` and the local Swift package. No third-party project generator is required.

The universal app links only `LeaderboardPadUI` and its `LeaderboardKit` dependency. Desktop quota subprocesses, CC Switch database access, SQLite, Sparkle and Windows runtimes are not linked. It includes this project's full MIT notice and reuses the desktop brand PNGs. Their existing provenance audit remains unresolved; see `docs/third-party-notices.md`.

## Develop and verify

Install full Xcode (Command Line Tools alone do not include the iOS SDK), select it with `xcode-select`, and install available iPhone and iPad simulators in Xcode Settings → Platforms. Use Xcode 16 or later / Swift 6.

From the repository root:

```bash
node Scripts/ios-project.mjs
open apps/ios/AI-BenchGauge.xcodeproj
node Scripts/ios-build.mjs check
```

Select the **BenchGauge** scheme and an iPhone or iPad simulator/device in Xcode. `check` builds Release for simulator and device with signing disabled, then runs the separate iPad and iPhone Debug simulator UI suites. `test` runs both simulator test suites without the Release builds. CI runs the two Release SDK builds and the two device-family UI suites as independent jobs; a failure retains that family’s results without cancelling the other family. Logs and `.xcresult` reports are saved by the separate [iPhone/iPad GitHub Actions check](../../.github/workflows/ios.yml); shared unit tests also run through `./test.sh`.

Simulator checks cover portrait/landscape. Before distribution, also verify on a real iPhone and iPad in portrait and landscape, with large Dynamic Type, dark mode, offline relaunch, company details and screenshot copying. Confirm full-screen presentation on older systems and check system-controlled windowing on newer ones. A Mac compilation of the SwiftUI module is not a substitute for native mobile validation.

## Validation status

### Resizable and folding windows (2026-10-18)

The layout recomputes from `GeometryReader` on every size change. A universal iOS 27 SDK build can resize on the folding iPhone; this project no longer assumes an iPhone always uses the narrow layout. The shared category bar stays within the current safe area. The local Xcode 27.0 installation has no iPhone Duo simulator: ordinary iPhone/iPad rotation and adaptive-width tests do not validate fold poses, the reserved folding region, or iOS 27.1 edge-to-edge behavior. Complete those checks with Xcode 27.1 / iPhone Duo before claiming full device support ([Apple preparation guide](https://developer.apple.com/iphone-duo/prepare/)).

Two layout policy tests and four native UI tests passed on iPhone 18 Pro Max and iPad Pro 11-inch (M5), iOS 27.0. Reviewed light/dark English/Chinese captures cover portrait → landscape → portrait, readable column widths and gaps, and retention of the source, search query and openness filter. The 12 captures and native result bundles remain in ignored `work/ios-resizable/`.

### Shared mobile model search (2026-10-17)

The model column heading has a search button. Its bounds anchor a 320 ms two-sided expansion to the entire header row while the original headings fade out; focus is delayed until expansion finishes. Reduce Motion skips the transition. Search filters existing model names locally with case, accent and width folding and whitespace-separated terms, intersecting the country/openness filters. Original ranks and the source's pre-search leading score remain unchanged, including exported pages.

The query is shared across sources and categories for the current store session. Losing focus collapses the field without clearing the query. Pinned search fields have square corners. Company standings ignore the query and omit the control; returning to models restores it. Clear keeps editing, Cancel clears and collapses, and Clear filters also resets the query. Search does not issue requests or save preferences. Native interaction fixtures cover English/light, Chinese/dark, source/category/grouping changes, empty results, clear/cancel and filtering from a pinned header. Review evidence is kept in ignored `work/mobile-model-search/`.

### Scroll update isolation and ProMotion (2026-10-17)

The phone cube previously published its source-tab offset for every scroll geometry update, even after the offset had reached its 48-point limit. Both complete boards and the brand heading observed that object. Scroll geometry now lives in a separate object observed only by the source tabs and return-to-top overlay. Comparison rank and measured row/header heights remain current without publishing; unchanged offset and button visibility values no longer publish. The drag-axis gesture state is also written only when its direction changes.

Inactive and rotating faces disable their controls as well as hit testing. Attribute hints dismiss when disabled, so a horizontal gesture that starts over a badge cannot leave a popover blocking the incoming board.

The incoming board now aligns to the comparison rank when a horizontal drag begins, rather than waiting for face selection at the end. This prevents its initial source-tab spacer and metadata from appearing as a blank shaded band above the scrolled table during rotation. Native before/after recordings and the source-switch regression remain in ignored `work/ios-cube-tab-remnant/`.

`CADisableMinimumFrameDurationOnPhone` enables refresh rates above the system default on ProMotion iPhones, following [Apple's guidance](https://developer.apple.com/documentation/quartzcore/optimizing-iphone-and-ipad-apps-to-support-promotion-displays). SwiftUI retains control of frame pacing; this does not force a fixed 120 Hz rate. Notification-count regression tests simulate 360 scroll geometry updates and verify that they do not invalidate the cube, while preserving comparison position, variable row heights and returning to the top. Simulator interaction checks and notification counts cannot establish frame pacing on the reported iPhone 17 Pro; real-device profiling remains necessary.

### Screenshot actions (2026-10-12)

On iOS, the screenshot button opens a native menu with **Copy image** and **Save to Photos**. Rendering happens only after choosing an action. Saving requests add-only Photos authorization, with localized permission text and success/failure feedback; denied access offers a link to Settings. iPhone and iPad use the same actions.

### Visible source introductions (2026-10-12)

Each iOS board now shows the desktop's one-sentence source introduction below its short emphasis label. General, coding, image and video categories use the existing localized source descriptions, shared with the source-help sheet. Introductions wrap naturally on phones and also appear in the iPad layout and copied images; source-help and refresh-error controls remain available.

### Score and compact columns (2026-10-12)

Live rows and copied images share a score column sized by the longest localized, single-line score among the displayed rows, with a 44-point minimum. Header and row cells use the same reference, so Arena values such as `1,499.9` remain aligned without wrapping or reducing the font size. Rank columns are 28 points in English and 24 in Chinese; country columns use their header's intrinsic width with a 32-point minimum. Country text and its chevron now have a 2-point gap.

Native iPhone 18 Pro captures reproduce the original wrapping in both the live Arena face and the iOS ImageRenderer export. Reviewed final captures cover light/dark live views and model/company exports, plus Chinese headers; source hashes and original pixels remain in ignored `work/export-score-spacing/`. Environment: iOS 27.0, Xcode 27.0 (27A266a), live captures at 3× and exports at 2×. This is simulator validation; real-device visual review remains separate.

The existing `testSwipeAndTapBothFacesThenRefresh` native iPhone regression passes, including country filtering, company score details, source switching and refresh. Its result bundle is `work/export-score-spacing/interaction.xcresult`.

Debug fixture arguments `--ui-testing --arena-scores` supply four-digit Arena values. Add `--arena-preview` to start on Arena, `--preview-companies` for company rows, or `--capture-export` to write the normal image renderer's output to `Documents/leaderboard-export.png` in the simulator app container. All preview hooks are excluded from Release builds. Set the simulator appearance before launching a dark export preview so its first render receives the intended scheme.

### Wrapped model-name spacing (2026-10-11)

Brand backgrounds now have 4-point vertical margins outside the color fill, preserving an 8-point gap between consecutive wrapped names. The inner padding and 44-point minimum row height are unchanged. Debug launches with `--ui-testing --full-board --wrapped-names` provide three consecutive multiline names for native visual review. Before/after light and dark iPhone 18 Pro captures (iOS 27.0, 3×, Xcode 27.0) remain in ignored `work/wrapped-name-spacing/`; reviewed captures show separated backgrounds and unchanged single-line row height. Real-device visual review remains separate.

### AA / Arena source-switch headers (2026-10-11)

Switching from the top now retains the source title, column headers and first row. Scrolled comparisons still align the visible rank, using explicit enum scroll targets so the row number cannot collide with `ForEach`'s integer index. On iOS 26 or later, the compact board disables its automatic top scroll-edge effect; its fixed source controls already sit outside the scroll viewport. The API is guarded for older SDKs and systems.

The new full-board regression failed on the original source because the Arena headers disappeared. On the final working source based on `1d8139154d18b9d8ccc42f78e3abb8a7a8f4494f`, four native iPhone tests pass: light/dark top and scrolled switching, dark landscape comparison, and Reduced Motion. Original before/after screenshots and source hashes remain in ignored `work/mobile-scroll-edge/`; `final.xcresult` retains the final native test results. Reviewed captures show clear source/column headings and first rows at the top, and readable aligned rows after scrolling. Environment: iPhone 18 Pro simulator, iOS 27.0, actual 3× scale, Xcode 27.0 (27A266a). This is simulator validation; real-device visual review remains separate.

The final source also passes syntax checks, 107 script tests, 283 shared Swift tests, 39 Windows harness cases and the local updater's unsigned iOS simulator SDK build.

### Earlier universal CI validation

The [universal native CI check](https://github.com/cloydlau/ai-benchgauge/actions/runs/36826949674) passed on 2026-10-01 at revision `217f68411a142c832b224d8c23f6058845878f1f`: two unsigned Release SDK builds, five iPhone UI tests and four iPad UI tests, with zero failures. Six build-script checks and thirteen shared-library/UI unit tests also passed locally at that revision. This records the retained implementation after withdrawing an experimental screenshot-pixel assertion and footer layout change; the source-switch fix above supersedes that revision's mobile view and tests.

The run retains 21 original iPhone PNGs in [ios-iPhone-test-results](https://github.com/cloydlau/ai-benchgauge/actions/runs/36826949674/artifacts/11146300071), 17 iPad PNGs in [ios-iPad-test-results](https://github.com/cloydlau/ai-benchgauge/actions/runs/36826949674/artifacts/11145418958), and [SDK build logs](https://github.com/cloydlau/ai-benchgauge/actions/runs/36826949674/artifacts/11144599722). The iPhone captures use iPhone 17 Pro / iOS 26.2 at actual 3× scale; iPad uses iPad Pro 13-inch (M5) / iPadOS 26.2 at 2×. The runner uses macOS 15.7.9 (24G830), arm64, Xcode 16.4 and the iOS 18.5 SDK. Screenshots retain their original pixels and orientation metadata, including landscape captures.

Agent inspection covers the phone's shown/refreshed/settled faces, a fixed mid-turn perspective frame, three languages, model/company rows, source/offline/license sheets, screenshot feedback, long names, dark portrait/landscape, Reduced Motion and rank alignment. Tests also exercise independent country filters, equal category widths after rotation/copying, grouping reset, and native footer menus after sheet dismissal. Phone fixtures use the same content and viewport as the earlier phone captures; the company name/purchase layout and source-sheet heading were made readable, and the actual visible rank now aligns when turning. Wide iPad remains a paired board layout; fresh native iPad regression captures also passed in [run 36828374600](https://github.com/cloydlau/ai-benchgauge/actions/runs/36828374600/artifacts/11146741104). All data in these captures is synthetic. Extracted originals and agent review notes stay in ignored `work/ipad/`; this is not human release approval.

Real iPhones/iPads, smaller devices and narrow iPad windows, large Dynamic Type, live Top 20 results, empty/source-date states, other iOS/iPadOS versions and Apple signing/distribution remain unverified. The fixed mid-turn capture verifies a production rendering state, not continuous animation smoothness on real devices. Desktop interface changes are outside this mobile validation.

### Prior iPad baseline

On 2026-10-01, the [native iPad CI check](https://github.com/cloydlau/ai-benchgauge/actions/runs/36820908883) passed at source revision `88e3f07f9783873a25643150cf596318c083c80e`: unsigned Release builds for both simulator and physical-device SDKs, followed by four simulator UI tests with zero failures. The tests cover all categories, model/company grouping, country/unknown filtering, company score details, name copying, portrait/landscape rotation, all three languages, desktop-aligned titles, offline cache, source details, the MIT license/notices, and screenshot clipboard feedback. Equal category widths are checked after rotation and screenshot copying. Five script checks and ten shared-library/UI unit checks also pass locally. Changed application/library/test sources match the isolated validation revision.

The run's [ipad-test-results artifact](https://github.com/cloydlau/ai-benchgauge/actions/runs/36820908883/artifacts/11143871994) contains native results and 17 unmodified screenshot attachments. Captures use an iPad Pro 13-inch (M5) simulator on iPadOS 26.2, with actual 2× scale; the runner uses macOS 15.7.9 (24G830), arm64, and Xcode 16.4 / iOS 18.5 SDK. Native review includes English and Chinese portrait/landscape model/company views, Traditional Chinese, full 20-row dark boards with long names, unknown country, image/video categories, offline/source sheets, notices and screenshot feedback. Three-row before/after views use the same fixture and viewport as [the preceding interface](https://github.com/cloydlau/ai-benchgauge/actions/runs/36814542075). The extra fetched labels/settings toolbar have been removed, desktop brand assets and footer actions are present, names wrap without clipping, category spacing remains equal after copying, and long source-sheet headings are fully visible. Full boards can scroll to their footer in landscape. A layout-callback implementation caused an event-loop stall during intermediate native checks; it was removed, and the passing revision sets segment widths once at creation. All screenshots use synthetic fixtures, not live leaderboard data. Extracted PNGs and review records stay in ignored `work/ipad/` and CI artifacts.

This verifies native compilation and the listed simulator states, not the absence of bugs. Real iPads, smaller devices, live Top 20 data, large Dynamic Type, empty/source-date states, other iPadOS versions, Apple signing and public distribution remain pending. The earlier approved scope excludes computer quotas and display-mode selection. This iPad review does not certify concurrent desktop changes or grant release approval. Store uploads must also meet Apple's SDK requirements below; Xcode 16.4 validation does not establish upload eligibility.

## Install and distribute

The intended release path is to preview and test locally, then publish directly to the App Store. TestFlight is optional. See [自测后直接上架 App Store（中文）](../../docs/releasing.md#自测后直接上架-app-store) for that path, or [TestFlight 分发流程（可选）](../../docs/releasing.md#testflight-分发流程可选) for external beta testing. Both explain signing, upload and review.

For your own iPhone or iPad, select an Apple signing team in Xcode and run on the connected device. For users, use **TestFlight or the App Store** with an Apple Developer Program account. The publisher still needs to configure signing, create the App Store Connect record, upload a signed build and complete the applicable review/distribution steps; writing the app or passing GitHub CI does not publish it. Use bundle ID `com.cloydlau.ai-benchgauge.ipad`.

```bash
APPLE_TEAM_ID=YOURTEAMID IOS_BUILD_NUMBER=1 node Scripts/ios-build.mjs archive
```

Use your real 10-character team ID and a new integer build number for each upload. The script produces a signed Release archive under `work/ios/AI-BenchGauge.xcarchive`, using your existing Xcode provisioning configuration. Open the archive in Xcode Organizer, validate it, and upload to App Store Connect. An archive generated without valid signing is not an installable release. External TestFlight distribution may require Apple's beta review.

Apple currently requires iOS apps uploaded to App Store Connect to be built with Xcode 26 or later; the local compilation minimum above does not establish upload eligibility. Choose **TestFlight & App Store**, rather than **TestFlight Internal Only**, when distributing to this external user. Each TestFlight build is available for up to 90 days. See [Apple's upload requirements](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/) and [TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/).

GitHub `v*` releases continue to publish the desktop DMG/EXE. The iPhone/iPad workflow checks the native app but does not automatically upload an unsigned IPA, publish to App Store Connect or reuse the desktop signing keys. iPhone/iPad updates follow TestFlight/App Store rather than Sparkle or the Windows installer. Configure screenshots, privacy details and distribution in App Store Connect before inviting users.

- [Apple distribution guide](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases)
- [TestFlight](https://developer.apple.com/testflight/)
- [Required-reason APIs](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)

## Mobile parity and verification

The user-facing mobile workflow follows the mini-program, with native touch targets, system menus, photo permissions and wide iPad paired boards. `Scripts/ios.test.mjs` verifies the shared build/project and source-copy rules. Swift tests cover shared filters, migration, offline/independent source updates, stable row presentations, export page ranges and image rendering. `LeaderboardMobileParityTests` exercises bottom categories, global filters across categories/sources, About, viewport-filling loading states, rotation and paginated preview/copy/save. Existing gesture and scrolling regressions continue to cover name-copy guards and long rankings.

Current local source snapshots, before/after native originals, build/test logs and xcresult bundles are retained in ignored `work/ios-weapp-parity/`. Historical validation sections above describe their own revisions and do not certify this change. Physical-device installation and App Store/TestFlight distribution require their normal build/signing/release gates; local simulator verification does not imply a public release.

On 2026-10-15, the final source passed an unsigned Release build for the physical-device SDK, a simulator test build, 17 Swift UI/store/rendering tests and 9 iOS build-script checks. The final `phone-final.xcresult` contains three passing tests for paginated preview/copy/save, top/scrolled source switching and swipe-versus-copy gestures; `pad-final.xcresult` contains four passing tests for the adaptive header/global filters/About, portrait/landscape skeleton coverage, paginated preview/permission feedback and Chinese model/company layouts. Earlier checks in the same work directory also passed complete rankings/return-to-top, footer reachability, combined filters, Reduced Motion and iPad company/country details. A stale test that tapped the scrolled-away selector was updated to use the swipe gesture, and the Chinese title's accessibility label was restored before the final reruns.

Native originals were reviewed on iPhone 18 Pro (402 × 874 points, 3×) and iPad Pro 11-inch M5 (834 × 1210 points, 2×), iOS/iPadOS 27.0 with Xcode 27.0. Review covers light/dark headers, About/version alignment, full-viewport skeletons, long names, company layouts, source-switch positions and multi-page images. System menus/sheets and the paired wide-iPad layout are intentional native differences. Source hashes are recorded in `source-sha256.txt`; no physical-device or public-release verification is claimed.

### Mobile spacing parity (2026-10-16)

The mobile heading places the introduction's closing tagline below the title/grouping row, split into two rows at the semicolon in every supported language, while retaining its 44-point help target. Desktop clients keep the tagline on one line. Source tabs leave a 10-point gap before the card; metadata/column-heading spacing is tighter and source symbols use 14-point sizing. At the end of a ranking, reserved content space places the return-to-top control below the footer and above the bottom categories. Wide iPad overlays already sit inside the bottom safe area; the extended phone viewport includes that inset explicitly.

Verified with Xcode 27.0 on iOS 27.0 simulators: iPhone 18 Pro at 3× and iPad Pro 11-inch (M5) at 2×. Four iPhone regressions (header/icons, footer reachability, source switching and landscape comparison) and two iPad regressions pass, with the landscape case passing separately in `landscape-verified.xcresult`. Earlier landscape runs exposed stale test gestures over the category bar and an offscreen-rank-1 assertion incompatible with lazy rows; those checks now finish scrolling within the clear viewport and wait for the preserved visible rows. Nine iOS build-script checks also pass. Source hashes, native originals, logs and result bundles remain in ignored `work/ios-spacing-20261016/`; this covers simulator rendering and interaction, not a physical-device or release review.

### Cube projection containment (2026-10-16)

Cube faces now share a fixed-size compositing group before the viewport clip. Native vertical scroll indicators are hidden while dragging, turning, entering, or holding a projected preview, then return when the face is flat. This keeps scroll chrome from becoming a stretched vertical edge during the turn. Debug-only `--cube-preview` accepts `BENCHGAUGE_UI_CUBE_POSITION` for repeatable intermediate poses; it consumes the entrance animation so vertical scrolling preserves the chosen pose.

The native regression compares a blank strip immediately above the ranking viewport with the flat reference at multiple projected angles, before/after scrolling and in both themes; it also captures landscape. Static pre-fix previews did not reproduce the reported intermittent upward overflow. Originals and verification records stay in ignored `work/ios-cube-clipping-20261016/`.

The final simulator build and both native regressions pass on iPhone 18 Pro / iOS 27.0 at 3× with Xcode 27.0. The interaction regression covers swipes, tabs, refresh, company details and country menus after turning. A native Simulator recording also covers both turn directions: 96 decoded sampled frames across the two turn windows leave the header guard strip unchanged, with no vertical intrusions. The recording, extracted frames, source hashes and `after.xcresult` are retained with the native originals; real-device frame timing remains unverified.

### Source tab transitions (2026-10-16)

The compact source selector now shares one sliding selection background. Its position, blue/purple fill and label colors use the mini-program's 320 ms cubic Bézier curve `(0.22, 0.7, 0.2, 1)`. Reduced Motion disables this selector animation. An opaque page-colored backing keeps the rotating cube's shading out of the stationary tabs while retaining their scroll-away behavior and touch targets.

The final simulator build and both light/dark source-switch regressions pass on iPhone 18 Pro / iOS 27.0 at 3× with Xcode 27.0. These exercise taps in both directions, swipes and preserved scrolled ranks. The Reduced Motion swipe/button regression also passed before the final backing-only adjustment. Native recording frames were reviewed in both themes and directions: the selection moves between the labels, their colors interpolate, and cube shading stays behind the tabs. Sources, recordings, extracted frames and result bundles remain in ignored `work/ios-source-tabs-20261016/`, with final verification under `final/`. Physical-device animation timing remains unverified.

### About page parity (2026-10-16)

About now follows the mini-program's hero/version, sentence-separated description, quota lookup link, two-column source cards, engineering counters, independently expandable cost groups, estimated total and contribution/notices footer. The version retains painted-bottom alignment with the brand. Native sheet navigation, system symbols and the font license actually bundled by iOS remain platform-specific; dependency notices from the web runtime are not presented as iOS dependencies.

Project preparation (`node Scripts/ios-project.mjs`, the build script, or local deployment preparation) generates and bundles `AboutContent.json` under ignored build output. It imports the mini-program's descriptions, source URLs, localized investment content and engineering counter implementation. CI fetches full history for those counters. Native code recalculates monthly token investment using the same start date, average month and rounding rule, leaving unaccounted costs excluded from the total. Shared About inputs also participate in native CI triggers and local deployment fingerprints.

The final simulator test build, 29 targeted JavaScript checks and the Swift monthly-cost boundary test pass. Native About interaction tests pass on iPhone 18 Pro (3×) and iPad Pro 11-inch M5 (2×), iOS/iPadOS 27.0 with Xcode 27.0, covering Chinese/light and English/dark layouts, desktop/source/contribution link copying, expanded cost sections, totals, full license text and dismissal. Native originals were reviewed for those states; source hashes, generated content, logs and results stay in ignored `work/ios-about-20261016/`. The current mini-program runtime was inspected through DevTools; its window produced a small 93 × 200 reference, so layout matching also follows its WXML/CSS. Physical devices, landscape and large Dynamic Type for this page remain unverified.

### Search keyboard and bottom categories (2026-10-17)

The leaderboard root ignores the keyboard's bottom safe-area inset, so the keyboard covers the floating category bar instead of lifting it above the keys. Dismissing the keyboard reveals the bar at its original position. The search field, query filtering and subsequent category changes retain their existing behavior.

A native baseline regression reproduced a 295-point upward shift on iPhone (category minY 774 → 479). After the fix, all four native UI regressions pass: English/light and Simplified Chinese/dark on iPhone 18 Pro and iPad Pro 11-inch (M5), iOS/iPadOS 27.0 with Xcode 27.0. Tests compare category positions within one point before/during/after keyboard presentation, keep search above the keyboard, submit a query and verify category switching after dismissal. Reviewed original simulator captures show the keyboard covering the bar and the restored bar after dismissal. Originals (phone 1206×2622 at 3×, iPad 1668×2420 at 2×), frozen sources, source hashes, logs and xcresult bundles remain under ignored `work/ios-keyboard-tabbar/`. This validates simulator behavior; physical devices, landscape and floating/split iPad keyboards were not covered in this run.

### Pinned search horizontal insets (2026-10-17)

Pinned native search fields use zero horizontal padding; ordinary fields retain their 8-point inset. The mini-program also removes the pinned open header's horizontal margin/padding and the search content's horizontal padding, preserving the ordinary 12rpx content inset. Page/card spacing remains unchanged.

The existing iPhone pinned-header search UI regression passes on iPhone 18 Pro, iOS 27.0 (3×), covering query entry with the software keyboard, visible filtered results, submission and cancellation. Original simulator captures were reviewed. The mini-program build passes; DevTools confirms pinned header margin/padding and search padding are all zero, while ordinary search padding remains 6px at the 375-point viewport (12rpx). Before/after mini-program originals and native xcresult/screenshots remain in ignored `work/pinned-search-insets/`. Physical-device verification was not performed for this styling change.

The follow-up `testSearchPaddingChangesOnlyAfterHeaderPins` compares the same iPhone search field before scrolling and after its header pins. It verifies both leading and trailing positions differ by exactly 8 points (±1), and passes against the existing conditional implementation without a UI code change. Original normal/pinned captures and xcresult are retained under ignored `work/search-padding-state/`. Mini-program runtime readback also confirms horizontal search padding transitions 6px → 0px → 6px when scrolling down and back to the top.

### Pinned header vertical insets (2026-10-18)

Pinned column headers redistribute the existing 12-point vertical inset from top 4/bottom 8 to top 6/bottom 6. The same measured pinned state controls the column labels and expanded search. Header height and ordinary 4/8 spacing remain unchanged; horizontal search padding still becomes zero only when pinned.

The simulator build and existing horizontal search-padding UI regression pass on iPhone 18 Pro, iOS 27.0 (3×). Reviewed original search captures show normal and pinned spacing; logs, xcresult and originals remain under ignored `work/pinned-header-center/`. Two new centering tests compare header height and content centers in English/light and Chinese/dark, including expanded search. Their initial locator incorrectly expected an Other element; the native header is StaticText. The corrected type-independent locator has not completed its final rerun: it remained behind other native builds and was cancelled while queued. Those centering assertions, collapsed-header visual review, iPad and physical-device verification are not signed off by this local run.


### Drag selection on mobile navigation — 2026-10-18

The bottom category bar and compact source tabs accept horizontal drags directly on their controls. The segment under the finger previews the selection; releasing commits one category/source change. Crossing intermediate categories does not start their refreshes. The shared `MobileTabDrag` modifier clamps both ends, ignores vertical intent, clears cancelled previews and leaves ordinary button taps and accessibility selection intact. The board swipe recognizer is attached before the source-tabs overlay so a selector drag cannot also turn the cube.

Verification artifacts and frozen source live in ignored `work/mobile-tab-drag/`. The native simulator checks cover category dragging in both directions, ordinary taps and vertical movement on iPhone 18 Pro and iPad Pro 11-inch (M5), in English/light and Simplified Chinese/dark; the compact source-tab checks run on iPhone. Wide iPad keeps its existing paired boards without a source selector. Physical-device gestures and narrow iPad multitasking remain outside this simulator coverage.

The final run passed all seven native UI regressions (five on iPhone, two on iPad), including existing board swipes, diagonal scrolling and swipe-versus-copy behavior. Settled selection screenshots were reviewed in both themes; final result bundles are `phone-regression.xcresult` and `pad-final.xcresult`. The mini-program passed all 124 tests and its production build.

### English mobile heading (2026-10-18)

English omits the subtitle and its sizing constraint; its header height is 44 points rather than reserving the Chinese caption row. Simplified and Traditional Chinese retain the existing subtitle/help. Targeted native UI tests pass on iPhone 18 Pro (iOS 27.0, 3×) and iPad Pro 11-inch M5 (iPadOS 27.0, 2×). Reviewed English/dark and Chinese/light originals, source snapshot and result bundles remain in ignored `work/mobile-english-title/`. Mini-program page tests (57) and the production build pass; the official IDE refresh succeeds, but runtime automation times out, so mini-program simulator visual verification is not claimed.
