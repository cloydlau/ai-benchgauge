# AI BenchGauge for iPad

Native SwiftUI app targeting **iPadOS 17 or later**, on any iPad that can run that system. The project is in the repository; there is currently **no public TestFlight invitation or App Store release**. A desktop DMG/EXE cannot be installed on iPad.

The first iPad edition supports the four categories, both leaderboard sources, model/company grouping, country filters, English/Simplified Chinese/Traditional Chinese, offline cache, manual refresh, company score details and purchase links. The app uses one window, requests full-screen presentation, and has no desktop display-mode selector. All orientations are supported. Leaderboard copy and actions follow the desktop edition: source titles and explanations, one top-level update label, rank/score/country columns, medals, company scoring, Plan/Pay as you go links, name copying, branding colors, and the single-row footer with its language selector. The title is **智衡** in both Chinese languages and **AI BenchGauge** in English, with the desktop font policy. No separate iPad settings/about page is added. The model/company selector comes before the category selector, matching the desktop order; when controls wrap, grouping stays in the first row. Native grouping/category controls enforce equal segment widths across rotation and screenshot copying. Wide layouts show both boards side by side; narrow layouts stack them. Shared images include the full GitHub address.

Desktop CC Switch account quotas are not included. Data stays in this app's sandbox. The app contacts the public leaderboard sources directly over HTTPS; there is no project-operated proxy, login or analytics service. On foreground activation/category selection, data older than 24 hours refreshes. A failed source keeps its previous cached board with a warning, and retries automatically after at least five minutes. Pull-to-refresh retries immediately. iPadOS background execution is not used to promise a fixed polling schedule.

## Presentation policy

`UIApplicationSupportsMultipleScenes` is disabled. `UIRequiresFullScreen` requests full screen on older systems using Split View / Slide Over. Apple allows Stage Manager to show even full-screen compatibility apps in windows, and deprecates that compatibility mode from iPadOS 26. `UIRequiresFullScreenIgnoredStartingWithVersion = 26` avoids scaling the entire interface in newer windowing modes; the existing adaptive layout fits the system-provided size. Thus the app offers no presentation-mode choice, but cannot force users out of system windowing. See [Apple's full-screen behavior](https://developer.apple.com/documentation/bundleresources/information-property-list/uirequiresfullscreen) and [migration guidance](https://developer.apple.com/documentation/technotes/tn3192-migrating-your-app-from-the-deprecated-uirequiresfullscreen-key).

## Structure

- `Sources/LeaderboardKit`: portable data models, parsing, fetching, cache, ranking, filtering and refresh policy; also used by both desktop editions.
- `apps/ipad/UI`: shared Apple SwiftUI presentation and observable store. The ordinary Mac test run compiles this module and tests its state transitions.
- `apps/ipad/App`: iPad app entry point, icon, Info.plist and privacy manifest. Debug-only fixtures make simulator tests independent of the live sources.
- `apps/ipad/UITests`: simulator checks for categories, grouping, filters, orientation, cached offline results, license notices and screenshot copying.
- `Scripts/ipad-project.mjs`: generates a deterministic, ignored Xcode project using the version from `config/app.json` and the local Swift package. No third-party project generator is required.

The iPad app links only `LeaderboardPadUI` and its `LeaderboardKit` dependency. Desktop quota subprocesses, CC Switch database access, SQLite, Sparkle and Windows runtimes are not linked. It includes this project's full MIT notice and reuses the desktop brand PNGs. Their existing provenance audit remains unresolved; see `docs/third-party-notices.md`.

## Develop and verify

Install full Xcode (Command Line Tools alone do not include the iOS SDK), select it with `xcode-select`, and install an iPad simulator runtime in Xcode Settings → Platforms. Use Xcode 16 or later / Swift 6.

From the repository root:

```bash
node Scripts/ipad-project.mjs
open apps/ipad/AI-BenchGauge.xcodeproj
node Scripts/ipad-build.mjs check
```

Select the **BenchGauge** scheme and an iPad simulator/device in Xcode. `check` builds Release for simulator and device with signing disabled, then runs Debug simulator UI tests. `test` runs just the simulator tests. Logs and `.xcresult` reports are saved by the separate [iPad GitHub Actions check](../../.github/workflows/ipad.yml); shared unit tests also run through `./test.sh`.

Simulator checks cover portrait/landscape. Before distribution, also verify on a real iPad in portrait and landscape, with large Dynamic Type, dark mode, offline relaunch, company details and screenshot copying. Confirm full-screen presentation on older systems and check system-controlled windowing on newer ones. A Mac compilation of the SwiftUI module is not a substitute for this iPad validation.

## Validation status

On 2026-10-01, the [native iPad CI check](https://github.com/cloydlau/ai-benchgauge/actions/runs/36820908883) passed at source revision `88e3f07f9783873a25643150cf596318c083c80e`: unsigned Release builds for both simulator and physical-device SDKs, followed by four simulator UI tests with zero failures. The tests cover all categories, model/company grouping, country/unknown filtering, company score details, name copying, portrait/landscape rotation, all three languages, desktop-aligned titles, offline cache, source details, the MIT license/notices, and screenshot clipboard feedback. Equal category widths are checked after rotation and screenshot copying. Five script checks and ten shared-library/UI unit checks also pass locally. Changed application/library/test sources match the isolated validation revision.

The run's [ipad-test-results artifact](https://github.com/cloydlau/ai-benchgauge/actions/runs/36820908883/artifacts/11143871994) contains native results and 17 unmodified screenshot attachments. Captures use an iPad Pro 13-inch (M5) simulator on iPadOS 26.2, with actual 2× scale; the runner uses macOS 15.7.9 (24G830), arm64, and Xcode 16.4 / iOS 18.5 SDK. Native review includes English and Chinese portrait/landscape model/company views, Traditional Chinese, full 20-row dark boards with long names, unknown country, image/video categories, offline/source sheets, notices and screenshot feedback. Three-row before/after views use the same fixture and viewport as [the preceding interface](https://github.com/cloydlau/ai-benchgauge/actions/runs/36814542075). The extra fetched labels/settings toolbar have been removed, desktop brand assets and footer actions are present, names wrap without clipping, category spacing remains equal after copying, and long source-sheet headings are fully visible. Full boards can scroll to their footer in landscape. A layout-callback implementation caused an event-loop stall during intermediate native checks; it was removed, and the passing revision sets segment widths once at creation. All screenshots use synthetic fixtures, not live leaderboard data. Extracted PNGs and review records stay in ignored `work/ipad/` and CI artifacts.

This verifies native compilation and the listed simulator states, not the absence of bugs. Real iPads, smaller devices, live Top 20 data, large Dynamic Type, empty/source-date states, other iPadOS versions, Apple signing and public distribution remain pending. The earlier approved scope excludes computer quotas and display-mode selection. This iPad review does not certify concurrent desktop changes or grant release approval. Store uploads must also meet Apple's SDK requirements below; Xcode 16.4 validation does not establish upload eligibility.

## Install and distribute

The intended release path is to preview and test locally, then publish directly to the App Store. TestFlight is optional. See [自测后直接上架 App Store（中文）](../../docs/releasing.md#自测后直接上架-app-store) for that path, or [TestFlight 分发流程（可选）](../../docs/releasing.md#testflight-分发流程可选) for external beta testing. Both explain signing, upload and review.

For your own iPad, select an Apple signing team in Xcode and run on the connected device. For users, use **TestFlight or the App Store** with an Apple Developer Program account. The publisher still needs to configure signing, create the App Store Connect record, upload a signed build and complete the applicable review/distribution steps; writing the app or passing GitHub CI does not publish it. Use bundle ID `com.cloydlau.ai-benchgauge.ipad`.

```bash
APPLE_TEAM_ID=YOURTEAMID IPAD_BUILD_NUMBER=1 node Scripts/ipad-build.mjs archive
```

Use your real 10-character team ID and a new integer build number for each upload. The script produces a signed Release archive under `work/ipad/AI-BenchGauge.xcarchive`, using your existing Xcode provisioning configuration. Open the archive in Xcode Organizer, validate it, and upload to App Store Connect. An archive generated without valid signing is not an installable release. External TestFlight distribution may require Apple's beta review.

Apple currently requires iOS apps uploaded to App Store Connect to be built with Xcode 26 or later; the local compilation minimum above does not establish upload eligibility. Choose **TestFlight & App Store**, rather than **TestFlight Internal Only**, when distributing to this external user. Each TestFlight build is available for up to 90 days. See [Apple's upload requirements](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/) and [TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/).

GitHub `v*` releases continue to publish the desktop DMG/EXE. The iPad workflow checks the native app but does not automatically upload an unsigned IPA, publish to App Store Connect or reuse the desktop signing keys. iPad updates follow TestFlight/App Store rather than Sparkle or the Windows installer. Configure screenshots, privacy details and distribution in App Store Connect before inviting users.

- [Apple distribution guide](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases)
- [TestFlight](https://developer.apple.com/testflight/)
- [Required-reason APIs](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)

## Desktop parity

The iPad interface adapts the desktop leaderboard to the available width; it does not invent alternative source names, timestamps, purchase terminology or an about/settings flow. Language and screenshot actions live in the footer alongside the GitHub mark, author/license attribution and notices. Sources appear as links when space permits and collapse into a menu on narrower layouts. Refresh failures replace the source explanation with the desktop failure label; tap it for the reason and source details, instead of adding an extra warning row to the leaderboard. Both editions filter model rows by country before deriving company standings, then number the displayed rows by position. Unknown country is available when the source contains unrecognized developers. Company score detail uses the existing shared scoring explanation; taps replace desktop hover where needed. The intentional platform differences are native touch controls, 44-point minimum rows, adaptive board stacking and scrolling, and tap sheets for desktop hover details. Desktop update/quit/display-mode controls and computer account quotas remain outside the approved iPad scope. The screenshot action copies the rendered image to the clipboard and shows the same success message as desktop. The earlier approved scope still excludes desktop account quotas and display-mode controls.

`Scripts/ipad.test.mjs` compares source titles and explanatory copy against the Mac UI source. Swift tests cover country filtering before the company Top 20 limit, unknown-filter persistence, the oldest-visible-board update label, clipboard-free rendering and intentional medal colors. Native fixtures cover three-row baseline views and a separate full 20-row board with long names and an unknown developer. Bundled brand PNGs are the same assets used by the desktop; their unresolved provenance audit in `docs/third-party-notices.md` still applies, and is not represented as completed by this UI change.
