# AI BenchGauge for iPad

Native SwiftUI app targeting **iPadOS 17 or later**, on any iPad that can run that system. The project is in the repository; there is currently **no public TestFlight invitation or App Store release**. A desktop DMG/EXE cannot be installed on iPad.

The first iPad edition supports the four categories, both leaderboard sources, model/company grouping, country filters, English/Simplified Chinese/Traditional Chinese, offline cache, manual refresh, company score details and purchase links. Wide windows show both boards side by side; narrow windows stack them. All orientations, Split View and resizable windows are enabled. Shared images include the full GitHub address.

Desktop CC Switch account quotas are not included. Data stays in this app's sandbox. The app contacts the public leaderboard sources directly over HTTPS; there is no project-operated proxy, login or analytics service. On foreground activation/category selection, data older than 24 hours refreshes. A failed source keeps its previous cached board with a warning, and retries automatically after at least five minutes. Pull-to-refresh retries immediately. iPadOS background execution is not used to promise a fixed polling schedule.

## Structure

- `Sources/LeaderboardKit`: portable data models, parsing, fetching, cache, ranking, filtering and refresh policy; also used by both desktop editions.
- `apps/ipad/UI`: shared Apple SwiftUI presentation and observable store. The ordinary Mac test run compiles this module and tests its state transitions.
- `apps/ipad/App`: iPad app entry point, icon, Info.plist and privacy manifest. Debug-only fixtures make simulator tests independent of the live sources.
- `apps/ipad/UITests`: simulator checks for categories, grouping, filters, orientation, cached offline results, settings and image sharing.
- `Scripts/ipad-project.mjs`: generates a deterministic, ignored Xcode project using the version from `config/app.json` and the local Swift package. No third-party project generator is required.

The iPad app links only `LeaderboardPadUI` and its `LeaderboardKit` dependency. Desktop quota subprocesses, CC Switch database access, SQLite, Sparkle and Windows runtimes are not linked. It includes this project's full MIT notice; organization initials are drawn locally rather than shipping the desktop logo files with incomplete provenance.

## Develop and verify

Install full Xcode (Command Line Tools alone do not include the iOS SDK), select it with `xcode-select`, and install an iPad simulator runtime in Xcode Settings → Platforms. Use Xcode 16 or later / Swift 6.

From the repository root:

```bash
node Scripts/ipad-project.mjs
open apps/ipad/AI-BenchGauge.xcodeproj
node Scripts/ipad-build.mjs check
```

Select the **BenchGauge** scheme and an iPad simulator/device in Xcode. `check` builds Release for simulator and device with signing disabled, then runs Debug simulator UI tests. `test` runs just the simulator tests. Logs and `.xcresult` reports are saved by the separate [iPad GitHub Actions check](../../.github/workflows/ipad.yml); shared unit tests also run through `./test.sh`.

Simulator checks cover portrait/landscape. Before distribution, also verify on a real iPad in a narrow Split View/resized window, with large Dynamic Type, dark mode, offline relaunch, company details and the system share sheet. A Mac compilation of the SwiftUI module is not a substitute for this iPad validation.

## Install and distribute

For your own iPad, select an Apple signing team in Xcode and run on the connected device. For users, use **TestFlight or the App Store** with an Apple Developer Program account and an App Store Connect app for bundle ID `com.cloydlau.ai-benchgauge.ipad`.

```bash
APPLE_TEAM_ID=YOURTEAMID IPAD_BUILD_NUMBER=1 node Scripts/ipad-build.mjs archive
```

Use your real 10-character team ID and a new integer build number for each upload. The script produces a signed Release archive under `work/ipad/AI-BenchGauge.xcarchive`, using your existing Xcode provisioning configuration. Open the archive in Xcode Organizer, validate it, and upload to App Store Connect. An archive generated without valid signing is not an installable release. External TestFlight distribution may require Apple's beta review.

GitHub `v*` releases continue to publish the desktop DMG/EXE. The iPad workflow checks the native app but does not automatically upload an unsigned IPA, publish to App Store Connect or reuse the desktop signing keys. iPad updates follow TestFlight/App Store rather than Sparkle or the Windows installer. Configure screenshots, privacy details and distribution in App Store Connect before inviting users.

- [Apple distribution guide](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases)
- [TestFlight](https://developer.apple.com/testflight/)
- [Required-reason APIs](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)
