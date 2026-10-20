## Copy icon beside the model title — 2026-10-20

The shared Apple detail view, Windows dialog and mini-program now size the model
name to its content and place its copy button immediately after it with a gap.
The name can still wrap within the available width; the button keeps its touch
target. Copy feedback and detail content are unchanged.

Ignored `work/copy-title-inline/` retains the common offline synthetic fixture,
source snapshots, native Mac captures and actual verification results. Native
Windows screenshots/actual DPI and the CI comparison artifact are unavailable
on this Mac host. WeChat DevTools reports an expired login, so its simulator
visual review is unavailable. Compilation is recorded separately from visual
verification; no protected release approval is claimed.

## Neutral active country/source filter ink — 2026-10-20

All four clients use their existing primary text color for active country/source
headers: dark neutral ink in light mode and light neutral ink in dark mode.
The task-benchmark title retains its blue theme. Semibold text, filter icons,
transparent backgrounds, spacing and filtering behavior stay unchanged.

Ignored `work/filter-header-neutral/` retains before/after native Mac captures,
the common synthetic fixture, source hashes and actual verification results.
The baseline reuses the previous change's final captures after confirming all
four source hashes match. Each phase has 36 native frames across three languages
and both themes; all 12 refreshed/settled pairs are stable outside the scrollbar.
Settled differences are limited to the active filter text/icons, with the blue
source title unchanged. Representative originals were reviewed.

The mini-program production build and Windows Release cross-build pass (zero
Windows warnings/errors). All 527 native package cases passed after compilation,
but the native check exited 75 because concurrent workspace edits invalidated
its final input signature; it is not a final commit/release receipt. Final checks
are coordinated with the active installation flow. iOS and mini-program runtime
visual review is not claimed for this color change.
Windows native screenshots/actual DPI and the CI
`native-visual-comparison` artifact remain unavailable on this Mac host; no
Windows native visual verification or protected release approval is claimed.

## Country/source filter headers without a background — 2026-10-20

Mac, Windows, iPhone/iPad and the mini-program remove the active country/source
header fill and outline. Existing text colors, font weights, icons, padding and
column geometry stay unchanged; filtering and image exports are unchanged.

Ignored `work/filter-header-no-background/` retains a frozen pre-change Mac
executable, source snapshots, identical offline fixtures and 36 native frames
per phase. The cases cover EN / 简中 / 繁中, both themes, country-only and both
filters, at 850/1100 × 720 points on macOS 27.0.1 (26A434), native 1× scale.
Representative originals were reviewed. All 12 refreshed/settled pairs match
outside the scrollbar strip, and all refreshed/settled before/after differences
outside that strip are restricted to the filter headers. Two initial frames also differ while
brand images load; their settled rows match. `verification.json` records the
fixture and source hashes and the actual checks.

All 527 native package tests and 151 mini-program tests pass; the mini-program
production build and Windows Release cross-build pass (zero Windows warnings
and errors). Native Windows screenshots/actual DPI and a source-matched CI
`native-visual-comparison` artifact are unavailable on this Mac host. iOS and
mini-program runtime visual verification are not claimed for this change, nor
is protected human release approval.

## Model details and explicit name copy — 2026-10-19

## models.dev source and MIT notices — 2026-10-20

All clients list “Model information: models.dev” (模型资料：models.dev) with its source link. Complete MIT copyright, permission and disclaimer text is bundled for offline reading in their existing third-party notices. Existing notices remain available.

Ignored `work/models-dev-notice/` contains the synthetic fixture, capture intent, native originals and verification reports. Mac has 36 before and 36 after captures using the same fixture hash, covering EN / 简中 / 繁中 in both themes at 850×720 (main panel) and 560×520 (notices). Actual environment is macOS 27.0.1 (26A434), 1× backing scale, local uncommitted sources. All six notice refreshed/settled pairs are pixel-identical; main-panel differences are confined to the rightmost scrollbar strip. Representative originals were reviewed. These captures precede a concurrent filter-header style change; the main-panel fixture uses inactive filters.

Native iPhone and iPad About interaction tests passed in Chinese/light and English/dark, verifying the named source and expanded MIT copyright/disclaimer. Result bundles and exported attachments remain under that directory. The mini-program passed 151 tests and a production build; its built About module contains the complete license. Windows cross-compilation passed with zero warnings/errors and the packaged license was checked byte-for-byte. The Apple resource integrity test and isolated mini-program upload staging test passed.

Windows native screenshots and a CI native visual artifact are unavailable on this Mac host. WeChat DevTools reports expired login, so simulator runtime verification is outstanding. The repository's full coverage check remains blocked by existing `Scripts/deploy-shared-leaderboards.mjs` coverage (189/223 lines, required 100%). A duplicate queued core run was cancelled because a concurrent filter-header task already owned the newer full regression. No protected native release approval was requested or bypassed.


Model names open details; copying moves to a separate icon beside the original ranking name. Desktop uses scrollable dialogs, iPhone/iPad a large sheet, and the mini-program a dedicated page. Provider offers start collapsed. Empty metadata, long names, EN / 简中 / 繁中 and both desktop themes share fixture scenarios at a 560×640 content viewport.

Ignored `work/model-details/` retains capture intent, pre-change executable and source hashes, the common fixture, native captures and verification reports. Desktop captures render the real detail component with deterministic data; capture alone does not verify click-to-open wiring. Windows native captures and the CI protected visual review are unavailable on this Mac host. Its WPF runner implements the same cases and localized sections, with Swift/JavaScript fixture parity checked separately. No native client release approval is claimed. The mini-program IDE reports an expired login; controller tests and a production build do not constitute simulator validation.

Verification completed on 2026-10-20: 85 server tests, 151 mini-program tests, 526 core tests, the mini-program production build, both iOS SDK builds, Windows cross-build (zero warnings/errors), and Windows unit tests passed. iPhone/iPad native interaction tests passed in English/light and Chinese/dark, covering opening without copying, the explicit copy icon, closing, and missing metadata. Representative phone/tablet captures were reviewed. The shared Mac fixture produced 54 before and 54 after frames at native 1× scale; all 18 refreshed/settled file pairs are identical. The long-name, missing-data and Chinese/light plus Traditional/dark captures were reviewed. `verification.json` records fixture/source hashes and the host OS. The Windows engine was also exercised offline with nine real production boards: the three-board list response is 1,517,302 bytes and a selected model's detail response is 7,313 bytes, below its 4 MiB IPC limit. No client release was published.

## iOS cube shade excludes the tab spacer — 2026-10-19

The cube's darkening overlay now starts at each face's measured board origin.
The empty space reserved for source tabs stays unshaded, removing the gray
extension above the board's timestamp during turns. Each face uses its own
scroll geometry, including when the outgoing board is scrolled while the
incoming board remains at the top. Projection and scroll layout are unchanged.

On an iOS 27.0 iPhone simulator at 3× scale, the expanded native pixel test
detects the original bug at position 0.2. The final projection test and the
mid-turn/button-switch test both pass. Captures cover positions 0/0.2/0.5/0.8
in light mode and 0/0.5 in dark mode, at the top and after scrolling, plus
landscape transitions. The test also compares the incoming face's empty spacer
when the two faces have different scroll positions. Representative native
before/after, scrolled, dark and landscape captures were reviewed.
Ignored `work/ios-cube-top/` retains source snapshots, hashes, result bundles
and original captures; `final-verification.json` identifies the final sources.
Physical-device verification is not claimed.

## iOS inline brand subtitle — 2026-10-19

iPhone and iPad place the two Chinese subtitle rows beside the brand title,
matching the mini-program's horizontal brand composition. Both texts share
one width-dependent scale; title ink height, subtitle size and row spacing
follow the mini-program's control-height proportions. The help glyph follows
the final subtitle row, with a 44-point touch target and full-size grouping
controls. The header no longer reserves a separate subtitle row.

The sizing test passes across all three languages and seven widths. The native
subtitle layout/help interaction test passes on iPhone and iPad simulators
(iOS 27.0, 3× and 2×). Representative Chinese light and English dark captures
were reviewed. Ignored `work/ios-title-inline/` retains the frozen source
snapshot, hashes, test results and original captures, including Chinese
shown/refreshed/settled phases.
The installed pre-change phone capture is an older build, not a source-matched
baseline. Mini-program alignment was checked against source; its live runtime
was unavailable because the developer-tool login had expired. Physical-device
and CI visual verification are not claimed.


## Epoch ECI data attribution — 2026-10-19

The Mac and Windows interfaces and shared images retain the Epoch AI author credit, dataset title, source URL, CC BY 4.0 link and processing/non-endorsement statement. iPhone/iPad source help, About and image exports and the mini-program source help, About and Canvas exports use the same bundled notice. Other sources are not labelled as Epoch-licensed.

The common native fixture adds six attribution cases: EN / 简中 / 繁中 at 850×720 with Epoch only and 1100×720 with all three general boards, in both themes. The 850 px case uses the desktop's supported minimum width. Initial exploratory captures at 580 px showed pre-existing control/footer overflow below that minimum and are retained separately; they are not used to claim supported-width verification.

Native Mac before/after evidence is in ignored `work/epoch-attribution/`, with the same offline fixture, shown/refreshed/settled frames and metadata recording the fixture hash, OS and actual backing scale. Capture consent/intent is recorded in `capture-intent.json`. The reviewed EN minimum-width/light, 繁中 minimum-width/dark and 简中 three-board/dark frames retain all notice lines; all 24 before/after refreshed-versus-settled pairs are pixel-identical. `verification.json` records the full evidence. Windows native screenshots and a CI `native-visual-comparison` artifact are unavailable on this Mac host; a cross-build is not a native visual review. No protected visual release approval has been granted.

The mini-program DevTools connection reports `loginExpired: true`; runtime simulator validation is unavailable. Build and Canvas export tests cover the bundled notice and footer bounds. iOS build checks do not replace full phone/tablet visual review. Targeted deployment tests (11), mini-program tests (146), mini-program build, Windows cross-build (0 warnings/errors) and iOS Simulator/device builds passed. All full-suite test cases also passed, but the final run returned 75 because concurrent iOS edits changed its input signature; that run is not a valid current-workspace release receipt. See `work/epoch-attribution/verification.json` and `full-test-verified.log`.

## Active country/source filter headers on every client — 2026-10-19

Mac, Windows and iPhone/iPad now match the mini-program's visible filter state:
an active country or source header uses blue text, a tinted rounded background,
a border and a filter icon. Selecting all restores its ordinary dropdown label.
The two attributes are independent; exports retain plain, noninteractive labels.
Apple mobile uses its native filter symbol; desktop and mini-program use funnel
outlines. Country normalization and filtering logic are unchanged.

Ignored `work/filter-header-all-platforms/` retains the synthetic fixture,
baseline sources/binary, native Mac originals, `review.html` and
`verification.json`. Each phase has 108 frames: three languages, both themes,
inactive/country/open/both/closed/unknown states, one/three sources, and
shown/refreshed/settled checkpoints at 850/1100 × 720 points. Before and after
use identical fixture hashes. Reviewed originals show readable labels and
unobstructed adjacent columns. All 36 refreshed/settled pairs are identical
outside the rightmost scrollbar strip. Actual environment: macOS 27.0.1
(26A434), 1× backing scale, local uncommitted sources.
The baseline also precedes a concurrent quota freshness copy update; its text
differences are outside the filter change.

Windows Release cross-compilation passes with zero warnings/errors; iOS
simulator and device SDK builds pass. Native Windows screenshots/actual DPI,
iPhone/iPad device visual review and a source-matched CI comparison artifact
remain unavailable. These compilation checks do not replace native visual
review or protected human release approval. The shared CI fixture includes
the new filter states, and the WPF capture runner now reads source filters.

## Inline quota freshness — 2026-10-19

With board times now in their own table headers, the application header uses
one muted text label, “Quotas updated …” / “余量…更新”, without the separate
UPDATED heading or a capsule background. Relative age and exact-date tooltips
remain available; pending and unavailable states retain their status and
unavailable data retains its warning color. No quota data leaves no time label.

Relative Chinese uses natural word order, such as “余量刚刚更新” /
“餘量剛剛更新” and “余量 23 分钟前更新”; exact-time tooltips retain
“余量更新于…”. Ignored `work/quota-wording/` retains identical-fixture native
Mac before/after shown/refreshed/settled frames for the same ten cases and
both themes. Native compilation/tests and the Windows WPF cross-build pass;
Windows native screenshots and a source-matched CI artifact remain unavailable.

Ignored `work/quota-freshness-inline/` retains one fixture and native Mac
before/after shown/refreshed/settled frames covering all languages/themes,
recent/minute/day ages, pending/stale values and the empty quota state. Native
Windows screenshots and a source-matched CI artifact remain unavailable;
Windows visual verification and protected release approval are not claimed.

## Per-board header timestamps — 2026-10-19

Each desktop source header places its title at the leading edge and its own
snapshot time at the trailing edge, with an explicit gap. The former global
ranking freshness pill is removed; the quota freshness indicator stays in the
application header. Both clients use the later of source publication and fetch
time, matching the mini-program. Tooltips label publication and fetch dates
separately, including missing source dates. Narrow headers shorten Artificial
Analysis to AA and omit the explanation before truncating the source name.

Ignored `work/desktop-board-header-time/` holds the same fixture and native Mac
before/after shown/refreshed/settled frames for one/two/three boards, all three
languages, both themes and the empty quota state. Native Windows screenshots
and a source-matched CI artifact are unavailable on this Mac; Windows visual
verification and protected release approval are not claimed.

## Single-line quota row centering — 2026-10-19

The desktop quota cards and Add model action now center as a group when they
fit on one line. Wrapped rows retain leading alignment, and an empty quota row
centers its setup/Add model actions. This applies to the quota tracker beneath
the title, independently of leaderboard model-name cells.

Ignored `work/quota-row-single-line-center/` retains one fixture and native Mac
before/after shown/refreshed/settled captures: all languages/themes, one/two
providers, wrapped providers, a wide single row and the empty setup state.
Windows uses the same fitting rule; native Windows screenshots and a source-
matched CI visual artifact remain unavailable. Windows visual verification and
protected release approval are not claimed.

## Unknown distribution markers — 2026-10-19

Unknown country/source chart legends use a question mark instead of a dash.
This is scoped to charts; known flag and lock icons retain their appearance.
Ignored `work/distribution-unknown-question/` retains before/after native Mac
shown/refreshed/settled evidence using the same fixture, all languages, both
themes and one/three boards. The baseline is the unchanged prior task's final
capture. Windows native screenshots and a source-matched CI artifact remain
unavailable; Windows visual verification and protected release approval are
not claimed.

## Source chart and lock palette — 2026-10-19

Open source uses green and closed source uses neutral gray, with separate
light/dark values. Each client reuses the same palette for its chart segments
and lock icons; the mini-program icon generator consumes that palette too.
Apple and Windows now use the same hex colors as the mini-program.

Ignored `work/distribution-source-colors/` retains identical-fixture native Mac
before/after captures for all languages, both themes and one/three boards.
Windows native capture and a source-matched CI visual artifact are unavailable;
Windows visual verification and protected release approval are not claimed.

## Country chart label width — 2026-10-19

English country labels now have up to 144 points/pixels instead of 96. The
progress track retains at least 24 and narrow cards let complete country names
wrap rather than truncating them. Chinese labels retain their existing width.
The mini-program reduces the country value column from 94 to 86 pixels.

Ignored `work/distribution-country-width/` retains an identical long-country
fixture for native Mac before/after shown/refreshed/settled captures in English,
Simplified/Traditional Chinese, both themes and single/three-board layouts.
Windows native captures and a source-matched CI artifact are unavailable on
this Mac; Windows visual verification and protected release approval are not
claimed.

## Hide zero-count unknown chart items — 2026-10-18

Country/source distribution charts omit Unknown when its model count is zero.
Nonzero unknown counts remain visible and remain part of the denominator. Open
and Closed entries keep their existing zero-count behavior. The shared Apple
and JavaScript distributions and Windows fallback use the same rule.

Ignored `work/distribution-hide-zero-unknown/` retains the same fixture and
native Mac before/after shown/refreshed/settled captures, including known-only,
mixed and empty data, three languages and both themes. Windows native capture
and a source-matched cloud CI artifact are unavailable on this Mac; Windows
visual verification and protected release approval are not claimed.

## Left-align desktop model names — 2026-10-18 (corrected direction)

Mac and Windows align each model/company logo and name group to the left of its
available name area. This supersedes the earlier centering request, which the
user clarified was a speech-recognition error. Single-line names are also left
aligned. Empty placeholders remain centered. Bar widths, the external score-
share label, vertical centering and native row virtualization stay unchanged.

Ignored `work/desktop-model-name-left-corrected/` retains frozen source and the
same native fixture before/after, with shown/refreshed/settled captures for
one/two/three boards, model/company mode, long names, all supported languages
and both themes. Native Windows screenshots and a source-matched CI artifact
are unavailable on this Mac; Windows visual verification is not claimed.

## Mac scroll cell layout — 2026-10-18

Mac model cells now use the exact fixed TableColumn width directly instead of
measuring it again through nested GeometryReaders. The background bar, centered
name group and external score-share label retain their geometry. NSTableView
continues to recycle visible rows; WPF already uses a recycling virtualizing
stack panel and is unchanged in this pass.

Ignored `work/desktop-scroll-pass2/` retains frozen source, identical 2,000-model
fixtures, native Mac before/after shown/refreshed/settled captures and scroll
measurements for one/three boards, narrow/wide layouts, all languages and both
themes. Measurements cover 240 synchronous scroll/layout/display steps and are
main-thread work durations, not display FPS. Native Windows captures and a
source-matched cloud CI artifact are unavailable; Windows visual verification
and protected release approval are not claimed.

## Distribution chart flags and source locks — 2026-10-18

Country rows now include the country's flag beside its existing localized name;
source legends include open/closed lock icons instead of colored dots. Apple
charts reuse ModelOpennessBadge, WPF legends reuse OpennessBadge, and the mini-
program uses its bundled flag and theme-specific lock images. WPF packages the
same flag PNGs with their license. Other/unknown categories use neutral symbols;
no flag is assigned to an aggregate or missing metadata. Statistics are unchanged.

Ignored `work/distribution-icons/` retains baseline/final source, one shared
fixture and native Mac shown/refreshed/settled captures covering board counts,
languages, themes, company mode and empty data, plus mini-program captures.
Windows native screenshots and a source-matched CI artifact are unavailable on
this Mac; Windows visual verification is not claimed.

## Desktop search label — 2026-10-18

Desktop search placeholders, tooltips and accessibility labels now say “Search
models” / “搜索模型” / “搜尋模型”, matching the existing mobile labels. Search
continues to cover all selected boards. Ignored `work/desktop-search-models-copy/`
retains the shared fixture and native Mac before/after shown, expanded and
settled frames in all languages and both themes. Windows native captures and
a source-matched CI artifact are unavailable; Windows visual verification is
not claimed.

## Center desktop model names — 2026-10-18 (superseded)

Mac and Windows horizontally center the model/company logo and name group in
its available name area. This supersedes the previous left-alignment direction.
The external score-share label retains its position; bar widths and row geometry
remain unchanged. Empty placeholders stay centered.

Ignored `work/desktop-model-name-center-final/` retains the fixture, frozen source
and native Mac before/after shown, refreshed and settled captures for one/two/
three boards, model/company mode, all languages, both themes and 850–1600-point
viewports. Windows native screenshots and a source-matched cloud CI artifact
remain unavailable on this Mac; Windows visual verification is not claimed.

## Uniform source tint in desktop board headers — 2026-10-18

Mac and Windows draw each board name and its following explanation in the same
existing source/category tint. This also applies to abbreviated names when the
column is narrow. Font sizes, weights, truncation,
header background and table geometry are unchanged.

Ignored `work/desktop-header-tint/` retains frozen source, the shared fixture
and native Mac before/after shown, refreshed and settled captures across all
nine source kinds, three languages, both themes and one/two/three-board layouts.
Windows native screenshots and a source-matched cloud CI artifact are unavailable
on this Mac; Windows visual verification is not claimed.

## Re-anchor the Mac popover after board-count changes — 2026-10-18

Changing the selected boards recomputes the native popover's anchor after its
content size changes. The old code resized a saved window frame while preserving
its right edge, even when AppKit had centered the popover under the status item;
that could move the entire window past the anchor. The resize path now releases
the stale frame pin, asks AppKit to reposition against the current status button,
and settles the new frame. The existing window level, edge inset and animation
policy remain in force. Window mode and Windows WPF are unchanged.

The separate `Tests/fixtures/popover-board-anchor.json` fixture uses
`popoverBoardResize` to open the production status popover,
changes the selected boards, closes/reopens it and captures a settled frame.
Ignored `work/popover-board-anchor/` retains baseline/fixed source, native Mac
captures and screen-space window/button geometry for three-to-one, one-to-three
and two-to-one transitions, all languages and both themes. Cached AppKit chrome
captures do not reproduce the compositor's arrow/backdrop; screen-space anchor
geometry is retained separately. Windows has no change; native Windows captures
and a source-matched cloud CI artifact are unavailable on this Mac.

## Desktop source icons match the mini-program — 2026-10-18

Mac and Windows use the mini-program's Lucide lock-keyhole outlines and theme
colors in a fixed 14-point square. Both states share the same lock body,
keyhole, 24-point coordinate space and center, preventing state-dependent
vertical offsets. Unknown source placeholders and accessible labels remain.
The Apple mobile badge remains unchanged. Bundled Lucide notices accompany
the desktop drawings.

Ignored `work/desktop-openness-icons/` retains the fixture, frozen sources and
native Mac before/after shown, refreshed and settled captures. Explicit open,
closed and unknown rows cover one/two/three boards, company mode, all supported
languages, both themes and 850–1600-point viewports. Windows native screenshots
and a matching cloud CI artifact are unavailable on this Mac; Windows visual
verification is not claimed.

## Left-align all desktop model names — 2026-10-18

Mac and Windows now align the model/company name group to the left, including
single-line names. This supersedes the earlier single-line centering rule.
The score-share badge keeps its existing external position and gap; bar widths,
row heights and centered empty placeholders remain unchanged.

Ignored `work/desktop-model-name-left-final/` retains the shared fixture, frozen
before/after sources, native Mac captures and verification metadata. The fixture
covers one/two/three boards, company mode, all supported languages, both themes
and 850–1600-point widths. Native Windows screenshots and a source-matched cloud
CI comparison artifact remain unavailable; Windows visual verification is not
claimed.

## Mac search collapse after outside clicks — 2026-10-18

Mac now explicitly ends search editing after a click outside the search overlay
or when its window resigns key status. AppKit does not consistently end editing
when the clicked view cannot receive keyboard focus. Empty and whitespace-only
queries collapse; populated searches remain expanded. Clicks inside the overlay
retain normal editing, and detached views release their event monitor.

The native `desktopSearchOutside` scenarios dispatch a real mouse click on the
non-focusable title area, rather than relying on `makeFirstResponder(nil)`.
Ignored `work/desktop-search-blur/` retains the reproduced baseline failure and
native before/after captures. Windows is unchanged; native Windows captures and
a source-matched cloud CI comparison artifact are unavailable on this host.

## Search across selected desktop leaderboards — 2026-10-18

Mac and Windows add a search icon immediately after the category control.
Clicking it focuses a search input that animates left over both navigation
controls without changing their measured width. Empty input collapses on blur;
nonempty input stays visible. Clear buttons allow resetting the query. Filtering
runs locally across every currently selected source, including company mode,
while retaining country/source filters and the unsearched leading scores for
bar ratios. Refreshes retain the query; WPF also restores typing focus and caret
when its header is rebuilt. An empty match set has a localized empty-state label.

Ignored `work/desktop-search/verification.json` records frozen sources, fixture,
executables and 96 native Mac before/after frames. Eight cases cover one/two/three
boards, a nondefault subset, company mode, China filters, no results and empty
blur, in three languages, both themes and 850/1600-point viewports. The native
fixture clicks the real AppKit button, checks keyboard focus, enters queries,
asserts selected-board row counts, refreshes and blurs with/without text. Original
focused panels in both themes plus collapsed, populated-blur and empty-blur
frames were reviewed. Navigation is covered only while expanded; headers,
footers, score ratios and existing name alignment remain intact. Synthetic
refresh dates are current in search cases to avoid starting upstream fetches.
Sparse search results also required sampling the first body rows in screenshot
validation; single-result and no-result captures now pass in both themes.

Swift native compilation, WPF cross-compilation and the shared Windows tests
pass. Search tests cover case/width/diacritic folding, unordered words, whitespace
and unmatched terms. The Windows fixture supports the same search scenarios,
but Windows native screenshots and a CI comparison artifact are unavailable;
Windows visual verification remains outstanding. No release was published.

## Board names in desktop table headers — 2026-10-18

Mac and Windows show the concise leaderboard name followed by its explanation
in each model-name column, matching the mini-program's board names. Examples
include `Artificial Analysis · 任务测评`, `Text Arena · 用户盲测` and
`Epoch ECI · 难度校准`. All nine source kinds across general, coding, image and
video have named headers. The primary name uses the normal header ink; the
smaller explanation retains its source tint. In narrow columns, source identity
takes priority: Artificial Analysis abbreviates to AA if necessary, and the
explanation yields when it cannot fit. The tooltip retains the full name and
source explanation. Native popup width calculations now account for both labels.

Ignored `work/desktop-board-titles/verification.json` records source, executable,
fixture and screenshot hashes for 108 native Mac before/after frames on macOS
27.0.1 (26A434), backing scale 1.0. All eighteen original after panels and
representative baseline panels were reviewed across nine scenarios, three
languages, both themes, model/company modes, one/two/three visible boards and
850/1200/1600-point widths. Wide columns show names and explanations; the narrow
three-board case preserves recognizable source names without wrapping. Table
body geometry remains pixel-identical; shown/refreshed/settled variations outside
the changed header labels are confined to native scrollbar fading. Swift native
compilation and Windows WPF cross-compilation pass. Windows native screenshots
and a CI comparison artifact remain unavailable; Windows visual verification
is outstanding.

## Static desktop subtitle — 2026-10-18

Mac and Windows display the two-row subtitle beside the title as static text.
The question mark, help tooltip, hand cursor and click-to-open quota introduction
are removed because the desktop already exposes quota tracking. The shared
subtitle artwork offers an optional help symbol; existing callers retain their
default behavior, while the Mac header explicitly disables it. This supersedes
the earlier desktop caption's help interaction.

Ignored `work/desktop-subtitle-static/verification.json` records source,
executable, fixture and image hashes for 72 native Mac before/after frames on
macOS 27.0.1 (26A434), backing scale 1.0. All twelve original after panels and
representative baseline originals were reviewed across three languages, both
themes, model/company modes, one/two/three boards and 850/1200/1600-point widths.
The symbol is absent, caption placement is preserved, and all shown pixels
below the header's first 40 points remain identical. Refreshed frames match;
settled differences only show the native scrollbar. Source review confirms
both desktop headers have no subtitle button or click handler. Swift compilation
and Windows WPF cross-compilation pass. Windows native screenshots and a CI
comparison artifact remain unavailable; Windows visual verification is outstanding.

## Center single-line desktop model names — 2026-10-18

Mac and Windows center the single-line model/company name group within its
available name area. Desktop name labels already have a one-line limit with
truncation, so the previous unconditional left alignment incorrectly affected
these labels. This supersedes the earlier left-aligned desktop name layout.
The external percentage remains absolutely positioned with its four-point gap;
bar widths, row heights and empty-row alignment are unchanged.

Ignored `work/single-line-name-center/verification.json` records exact source,
executable, fixture and image hashes for 72 native Mac before/after frames on
macOS 27.0.1 (26A434), backing scale 1.0. Original after panels and representative
baselines were reviewed across single/two/three boards, model/company mode,
three languages, both themes and 850/1200/1600-point widths. Extreme three-board
850-point names retain their existing heavy truncation. Header/footer/rank
geometry remains pixel-identical. Refreshed frames match shown frames; settled
differences only show the native scrollbar. Swift compilation and Windows WPF
cross-compilation pass. Windows native screenshots and a CI comparison artifact
remain unavailable; Windows visual verification is outstanding.

## Compact single-board header tabs — 2026-10-18

Mac and Windows reduce horizontal whitespace in the model/company and category
segmented controls when exactly one leaderboard is visible. Equal segment widths
are measured from the widest label with eight points of space on either side;
font sizes remain unchanged. The single-board header fits its controls beside
the title when all content fits, retaining the existing two-row fallback when
necessary. Multi-board control widths remain unchanged. Live visibility changes
update both the native control widths and header layout.

Ignored `work/single-board-tabs/verification.json` records source, executable,
fixture and image hashes for 84 before/after native Mac frames on macOS 27.0.1
(26A434), backing scale 1.0. Seven scenarios cover model/company mode, three
languages, both themes, 850/1200/1600-point viewports and a live two-to-single
transition. Original after panels and representative baseline panels were
reviewed. Chinese single-board headers fit one row at 850 points; English retains
readable compact controls in the two-row fallback at 850/1200 points. Static
refreshed frames match, settled differences only show the native scrollbar, and
multi-board shown frames remain pixel-identical. Swift compilation and Windows
WPF cross-compilation pass. Windows native captures and a CI comparison artifact
remain unavailable; Windows visual verification is outstanding.

## Left-aligned desktop model names — 2026-10-18

Mac and Windows align the model/company name group to the left of its colored
background, including names that fit on one line. The external score percentage,
four-point gap, vertical centering, bar geometry, row heights and empty-cell
alignment remain unchanged. This supersedes the earlier centered-name layout.

Ignored `work/model-name-left/verification.json` records 72 native before/after
Mac frames and hashes for the exact sources, executable, fixture and captures.
The baseline reuses the prior executable after verifying every Swift source hash
matches the pre-edit source. Original after panels and the matching baseline
were reviewed across three languages, both themes, 850/1600-point widths,
two/three boards and model/company grouping. Row geometry is pixel-identical;
refreshed frames match and settled differences only show the native scrollbar.
Swift native compilation and Windows WPF cross-compilation pass. Windows native
screenshots and a CI comparison artifact remain unavailable; Windows visual
verification and release approval are outstanding.

## Score percentage beside the colored bar — 2026-10-18

Mac and Windows place each score percentage four points beyond the colored
name background's right edge, centered vertically. The badge remains absolutely
positioned. A fixed trailing gutter keeps near-full bars inside the model column
and uses one scale across the rows. Names are centered within the available bar
area and truncate before the badge; the existing tooltip retains the full name.
Very narrow columns use tighter icon/text gaps and tail ellipses to improve
truncation with the reduced text width. Rounded 100% and tiny/zero fills retain their suppressed badge behavior. Empty
Mac cells retain their original natural height and alignment.

Local native evidence is in ignored `work/score-share-outside/verification.json`:
72 before/after AppKit/SwiftUI frames cover shown/refreshed/settled stages,
English and Simplified/Traditional Chinese, light/dark, 850×720 / 1600×720
content viewports, two/three simultaneous boards, model/company mode, long names, tied leaders and shorter
score bars. The report records source, executable, fixture and capture hashes,
OS and actual display scale. The original native images are reviewed for badge
alignment, clear spacing, clipping and list density. Swift native builds and
Windows WPF cross-compilation pass. Windows native captures and a CI comparison
artifact remain unavailable; no Windows visual verification or release approval
is implied.

## Confirm desktop leaderboard visibility — 2026-10-18

Mac and Windows stage the footer leaderboard checkboxes until Confirm. Several
checkbox changes therefore produce one preference write and one refresh pass,
instead of immediately changing the visible columns and active requests. Cancel,
Escape and dismissal discard the draft. Reopening starts from the committed
selection, and the final checked source cannot be unchecked. Confirming an
unchanged selection does not save preferences or start refresh requests.

Mac uses a transient native popover so checkboxes remain open during multi-select;
Windows retains its native context menu and adds Confirm/Cancel actions. Both
retain source descriptions, category-specific choices and existing refresh limits.
The Mac `boardSelectionConfirm` fixture exercises pending edits across a state
refresh, confirmation, cancellation and dismissal through the actual native controls.

Ignored `work/board-selection-confirm/verification.json` records source manifests,
executable/fixture/image hashes and 72 original native Mac frames: before/after,
three interaction stages, three languages, light/dark, and 850×720 / 1600×720
content viewports on macOS 27.0.1 (26A434), backing scale 1.0. Original panels and
popovers were reviewed for layout, labels, contrast and clipping. Native assertions
check that the table keeps all three source groups during draft edits and changes
only after confirmation. Pending and committed popovers are pixel-identical for
the same choices. The old menu itself was not captured; baseline panels show its
immediate-apply behavior. The source report identifies the separate concurrent
Epoch label changes; all confirmation implementation files match the captures.

Seven focused Swift tests passed, including preference writes, request cancellation,
minimum selection, cancellation and unchanged confirmation. Windows shared tests
and WPF cross-compilation passed (zero warnings/errors). Windows native captures
and a CI comparison artifact remain unavailable, so Windows visual verification
is outstanding. No release approval is implied by these local checks.

## Desktop caption beside the title — 2026-10-18

Mac and Windows now place the subtitle immediately to the right of the brand,
with its two sentences stacked, matching the mini-program placement confirmed
by the user. The subtitle no longer occupies a separate row below the header.
The quota-help interaction remains attached to the caption. Compact windows
retain their separate navigation-control row; wide windows retain centered
navigation controls and right-aligned update times.

Mac reuses the existing two-row subtitle artwork with a small vertical inset
inside the title's ink height. Windows centers two native caption labels on the
title's painted ink and scales the pair together if needed, with a small gap
between the rows.

Local evidence is in ignored `work/desktop-caption-position/verification.json`:
72 native Mac frames cover before/after, shown/refreshed/settled, English,
simplified/traditional Chinese, light/dark, and 850×720 / 1600×720 content
viewports on macOS 27.0.1 (26A434), actual backing scale 1.0. Original native
images were reviewed; both caption lines remain complete beside the title and
clear of the other header controls. The frozen native source snapshots differ
only in `LeaderboardView.swift`; the report records source manifests,
executable hashes, fixture hash, capture metadata and screenshot hashes.
Six focused Swift tests passed. Windows cross-compilation passed without
warnings or errors, but Windows native screenshots and a CI comparison artifact
remain unavailable; Windows visual verification is outstanding.

## Mini-program caption beside the title — 2026-10-18

The caption belongs inside `brand-copy`, immediately to the right of the title,
with its two sentences stacked. Moving it below the entire header was an
incorrect interpretation of the earlier fitting request. The shared font scale
now fits the combined title/caption widths into the space before the grouping
control and WeChat capsule, accounting for both gaps and an absolute help glyph.
No caption-only row remains below the header. The follow-up polish reduces the
caption base size from 12 to 11 points (bounded further when capsule height is
short), and leaves a scaled 1.5-point inset above and below relative to the
wordmark. The absolute help glyph is anchored after the second sentence, not
centered across the two-row block. The subsequent spacing fix removes the
remaining 18-point help allowance from both caption width and font fitting.
The grouping control has matching eight-point layout gaps on both sides.
The caption stays at the right edge of its available area even on wide windows;
the absolute help glyph adds no text width. It now uses the full caption font
size again. For a Chinese full-width stop it moves 0.55em into the trailing
blank portion; English keeps a small 0.08em separation. Responsive checks cover
the restored-size icon staying clear of the grouping control.
Its line-height-free wrapper and block icon align to the second text line,
without an inline component baseline gap. A final small adjustment adds one
scaled point between the caption rows while preserving their font sizes.
iPhone/iPad layout is unchanged by this mini-program correction.

All 127 mini-program tests and the production build pass. The responsive
heading check covers three languages, widths 280–1024 and capsule heights
28–36, checking the combined title/caption width and shared font scale.
The canonical DevTools project still shows its existing startup failure
(`app.json is not found in the project root directory`) after refresh, despite
the valid `dist/app.json`; the original captures in ignored
`work/weapp-subtitle-wrap/` show that error. No simulator or phone visual
verification is claimed.

## Mobile brand and caption fitting — 2026-10-18

The mobile caption retains its two intentional rows, each constrained to a single
line. iPhone/iPad measure the brand and both sentences before deriving a common
scale for their font sizes; the model/company control and 44-point help target
remain unchanged. The help glyph overlays the right edge rather than participating
in the text stack. Chinese brand layout uses its actual measured width instead
of an approximate trailing padding. Desktop subtitle rendering is unchanged.

The mini-program measures the two sentences with a reusable offscreen 2D context
and caches the widths. Older renderers use conservative fallback widths. The
existing title fit beside the WeChat capsule/selector establishes its base size;
caption fitting then applies the same extra scale to the brand and caption. The
help glyph is an absolute overlay and both rows explicitly prohibit wrapping.

Ignored `work/mobile-brand-fit/` contains source hashes, native result bundles and
original screenshots. `testTaglineSubtitleFitsAndOpensHelp` passes on iPhone 18 Pro
(iOS 27.0, 3×) and iPad 11-inch M5 (iOS 27.0, 2×), covering Simplified Chinese/light
and English/dark. Original native review confirms complete captions, no collision
between brand and selector, and a working help alert. Sizing unit checks also
cover Traditional Chinese and narrow/wide content widths. Sixty focused
mini-program tests and the production mini-program build pass. The final
focused run against the current heading controller also passes both selected
checks. An isolated source-matched native run passes all four heading/sizing
unit checks, allowing native host pixel rounding when comparing glyph widths.

The attempted complete `./test.sh --coverage` run is blocked by separate
in-progress ECI changes: the About board-count expectation is still two and
the new CSV parser rejects an old shared-source fixture (`Invalid ECI CSV`).
Those edits are preserved; no complete green repository gate is claimed.

Mini-program visual verification is blocked: the canonical imported project
reports “app.json is not found in the project root directory”, although its
configured `dist/app.json` exists and the build verification passes. Recompiling
and opening the page did not recover it; automator calls time out. Captures show
the launch error, so no application screenshot verification is claimed there.

## Desktop quota authorization states — 2026-10-18

OpenAI reauthorization now reads “需重新授权” / “Reauthorize” and explains
that BenchGauge's saved authorization is separate from the current ChatGPT or
Codex session. The existing sign-in action and internal reauthorization state
are preserved. Revoked credentials still require the user to authorize again.

xAI shared-token ownership deferral is a neutral “退出 CC Switch 后同步” /
“Quit CC Switch to sync”
state rather than a network error. A previous successful quota remains visible
as stale. Deferral has a 60-second keep-alive retry interval; normal successful
renewals retain their six-hour interval and real failures their one-hour backoff.
Both desktop clients include CC Switch process ownership in the shared-login
revision, so their existing watcher detects an exit even if the login file does
not change and requests a quota refresh. No process is stopped and no real
credential is copied, rotated or modified by the visual fixture.

Ignored `work/quota-auth-status/verification.json` records before/after source
and executable hashes, the shared fixture hash and native capture metadata.
The fixture uses a synthetic refresh token and the real client's denied-refresh
policy (zero network requests), producing the previous network error and new
neutral state from the same event. All 36 original Mac frames cover shown,
refreshed and settled states in English, Simplified/Traditional Chinese and both
themes at 900×720 points, macOS 27.0.1 (26A434), actual 1× scale. Original native
review confirms readable labels, preserved controls and no clipping. All 18
before/after pairs differ only in the quota strip. Within each phase, shown and
refreshed frames match; settled frames differ only as the native scrollbar fades.

`./test.sh --coverage` passes, including ownership deferral/release, cached
quota preservation, zero token writes/network calls while deferred and
provider-specific reauthorization copy checks. The Swift gate reports all
57 files at 100% lines/functions/regions; `git diff --check` passes.

The follow-up wording change replaces the vague waiting label with the short
instruction to quit CC Switch. `work/quota-deferred-copy/` isolates this copy
change against the previous native fixture/source snapshot while unrelated ECI
work continues. The focused authorization-copy test passes for Simplified and
Traditional Chinese and English; no new full-repository gate is claimed for
this follow-up. All 36 original Mac captures (three languages, both themes,
shown/refreshed/settled) confirm a complete, unclipped instruction. All 18
before/after differences stay within the xAI chip and its adjacent button's
position; the quota strip remains stable across all three frames. The report
records native OS/DPI, fixture, frozen-source and executable hashes. Windows
native coverage remains unavailable.

Windows uses the shared formatting, ownership revision and retry policy, but a
native Windows capture environment and source-matched CI visual artifact are
unavailable. No Windows visual verification or protected release approval is
claimed.

## Desktop list scrolling work — 2026-10-18

Mac row logos now reuse bounded decoded-image caches: immutable bundled marks
use their resource key, while provider PNGs use their contents so an updated
image replaces the previous one. The table-chrome probe coalesces pending work
and keeps weak references to the mounted table/scroll view instead of traversing
all realized cells on each layout. It re-discovers a detached/replaced table and
still configures the header when view inputs change. Name buttons retain their
`inVisibleRect` tracking area as AppKit updates the clipping rectangle. Back to
top only changes visibility when crossing the threshold. Animations stay enabled.

Ignored `work/list-scroll-performance/` contains before/after source snapshots,
executable hashes, the native `scrollPerformance` fixture and timing/review data.
The 2,000-row fixture exercises paired boards, repeated public provider marks,
long names, three languages and both themes at 600/900×720 points. The original
comparison has 24 frames per phase (shown/refreshed/settled); all 24 pairs are
pixel-identical outside the scrollbar strip. Native review confirms preserved
layout, legible sticky headings and intact row colors/icons. The table realizes
17–18 rows, reaches the final row, and returns to the first row after refresh.
Timing includes 240 scroll/layout/display steps plus deferred main-actor work;
these debug-build measurements are main-thread work, not display FPS. An initial
sample confirms synchronous image loading in the previous cell body. English
timings are repeated without sampling because the first run has tail-latency
variation. Native environment is macOS 27.0.1 (26A434), actual 1× scale.

Two additional unprofiled English trials alternate the before/after order.
At 900 points the mean of per-run median work drops from 5.19 to 3.90 ms in
light mode and 6.90 to 3.94 ms in dark mode (25% and 43%). At 600 points the
corresponding improvements are 9% and 23%. Tail latency still varies: one narrow
light trial has a higher p95 after the change, so these results do not claim
every frame is faster or guarantee a display frame rate. All 48 original/repeat
image pairs remain identical outside the scrollbar. The complete `./test.sh`
gate passes, including three new cache reuse/replacement/fallback checks;
`git diff --check` passes too.

Windows implementation is unchanged. Native Windows screenshots/scroll timing
and a source-matched CI visual artifact are unavailable; no cross-platform
performance or visual verification, or protected release approval, is claimed.

## Sticky desktop table header background — 2026-10-18

Mac's custom table header now paints an explicit theme-aware background at
96% opacity and opts out of AppKit vibrancy. It declares its remaining alpha
correctly, while keeping header dimensions, labels and filter controls intact.
Windows already paints an opaque header outside its scrolling rows; this change
does not alter that implementation.

Ignored `work/sticky-table-header/` retains 24 native Mac frames per phase,
the frozen before/after sources, executable and fixture hashes, and review data.
The new `stickyHeader` scenario captures the initial view and two scroll
checkpoints (174.5 and 175.5 points) with 80 model rows. Coverage includes
English at 600/900 points, Simplified/Traditional Chinese at 900 points, both
themes and a 720-point viewport, on macOS 27.0.1 (26A434) at actual 1× scale.
Visual review finds readable headings with no row text bleeding into them;
the header pixels remain identical across all three checkpoints in each case.
The baseline native capture did not reproduce full transparency, so the exact
system/compositor condition behind the report remains unconfirmed. The new
explicit background removes reliance on the system control background color.
Existing name truncation at the 600-point viewport remains unchanged.

Native Windows screenshots and a source-matched CI visual artifact remain
unavailable; no cross-platform visual verification or release approval is claimed.
The complete `./test.sh` gate passes, including 382 Swift tests and Windows
shared tests; `git diff --check` also passes.

## Introduction tagline subtitle — 2026-10-18

The subtitle now uses the closing sentence of the introduction. All mobile
languages split at the semicolon into two rows below the title/grouping row.
Mac and Windows reserve one full-width line for the subtitle below the brand
and freshness row; compact desktop panels put navigation below it, while wide
panels retain navigation in the top row. This prevents the longer English copy
from pushing the title or freshness out of the viewport. The help action and
mobile 44-point target remain available.

Ignored `work/subtitle-tagline/` stores the native fixture, before captures,
final Mac captures, source hashes, simulator results and mini-program captures.
The first Mac attempt kept the long caption beside the title and clipped the
600-point header; `after/` is that rejected attempt, and `final/` is the corrected
layout. Mac environment: macOS 27.0.1 (26A434), actual 1× scale. Windows Release
cross-compilation passes with zero warnings or errors. Native Windows visual
coverage and a source-matched CI artifact are unavailable; no protected release
approval is claimed.

The focused iPhone and iPad subtitle/help checks pass in Chinese/light and
English/dark, with four original simulator captures retained (iOS/iPadOS 27.0,
iPhone 18 Pro at 3×, iPad Pro 11-inch M5 at 2×). The mini-program's Chinese and
English captures confirm two full rows; all 124 mini-program checks pass.
An earlier broader `testReadableSubtitleAndSourceIcons` run stopped at its
metadata-to-column-heading gap assertion (17.33 points versus a 16-point limit);
that unrelated assertion is retained in `phone.xcresult`. It is not reported as
a passing broader visual regression. The focused subtitle case checks complete
localized text, viewport bounds, a separate grouping control, the 44-point touch
target and the existing help action.

Final Mac coverage contains 54 frames per phase: Simplified/Traditional Chinese
and English, both themes, compact 600/900-point and wide 1200/1400-point panels,
with shown/refreshed/settled checkpoints. `source-record.json`,
`frame-review.json` and `verification.json` retain source/executable hashes and
validation details. The complete `./test.sh` gate passes, including 382 Swift
tests, all 124 mini-program checks and Windows shared tests.

## Desktop score percentages inside name backgrounds — 2026-10-18

Mac and Windows move the percentage from below the score into the top-right
corner of the colored model/company background. SwiftUI uses a geometry overlay;
WPF uses a Canvas that measures to zero. The badge follows the actual fill edge,
keeps a four-point right inset and ignores pointer input. Names remain centered;
column widths, row heights, score baselines and copy controls are unchanged.
Leading/tied/rounded-100 values retain their existing hiding rules. Fills too
narrow to accommodate the badge plus logo/spacing clearance omit the badge;
zero-width fills show none.

Ignored `work/desktop-score-share/` retains source snapshots/hashes, the fixture,
`review.html`, `review.json` and 48 native Mac frames per phase. Cases cover three
languages, both themes, 600/900/1100×720-point viewports, model/company rows,
long names, ties, rounded-100 values, half-width and zero-width backgrounds,
and shown/refreshed/settled checkpoints. Review confirms separated name/badge
ink and no percentages below score cells. All sixteen refreshed/settled pairs
differ only in the fading scrollbar strip. Native environment: macOS 27.0.1
(26A434), actual 1× scale. Existing name truncation at 600 points remains.

Mac builds pass; Windows Release cross-compilation passes with zero warnings or
errors. Native Windows screenshots/actual DPI and a source-matched CI
`native-visual-comparison` artifact remain unavailable. No protected release
approval or installed-client replacement is claimed.

## Centered desktop model names — 2026-10-18

Mac and Windows now center each single-line model name together with its logo
within the model column. Existing truncation, copy handling, score backgrounds
and row spacing are retained.

Ignored `work/desktop-name-center/` retains source hashes, the shared fixture,
`review.html`, `review.json` and 36 original Mac frames per phase. Before/after
captures cover English/Simplified/Traditional Chinese, light/dark, 600/900×720-point
viewports and shown/refreshed/settled checkpoints on macOS 27.0.1 (26A434), actual
1× scale. Review confirms centered short names and unchanged adjacent columns.
All twelve refreshed/settled pairs differ only in the fading scrollbar strip.
At 600 points, the pre-existing narrow name columns still show only initials;
this change does not resolve that separate width limitation.

Mac builds pass; Windows Release cross-compilation passes with zero warnings or
errors. Native Windows screenshots/actual DPI and a source-matched CI
`native-visual-comparison` artifact remain unavailable. No protected release
approval or installed-client replacement is claimed.

## Centered Apple subtitle and circled help — 2026-10-17

Mac and iOS now center the subtitle's visible ink on the title, including Chinese single-line captions and width-constrained English rows. The Mac layout uses the same normalized ink coordinates for both children. The shared vector help mark encloses its question mark in a circle and keeps the existing help action and mobile touch target.

Ignored `work/subtitle-center-circle/` retains matching source files, hashes, the fixture and native before/after originals. Mac captures cover English/Simplified/Traditional Chinese, light/dark and 600/900×720-point content viewports, with shown/refreshed/settled frames (36 per phase). All twelve refreshed/settled content pairs are identical outside the fading native scrollbar strip. Review confirms centered captions, complete circles and no new header clipping. Correcting the English heading also removes about four pixels of excess height above the subsequent content; narrow-table ellipses remain unchanged. Four iPhone before/after pairs cover Chinese/English and both themes at 360×780 points, 3×, on iOS 27.0; an initial blank Chinese launch frame was replaced after the header appeared.

Two final iPad Pro 11-inch M5 screenshots also confirm the paired-board header in Chinese/light and English/dark at 834×1210 points, 2×. The three focused AppFeatureCopy tests pass, checking centered ink bounds and native rendering at natural/narrow widths in all languages and appearances. Mac and arm64 iOS Simulator builds pass. Windows native/DPI captures, a source-matched CI artifact, physical iOS devices and large Dynamic Type are outside this local validation. No protected release approval or installed Mac application replacement is claimed.

## Obsidian/platinum application theme — 2026-10-17

The approved metallic logo now has a matching application theme. Shared Apple
controls use deep steel (`#414D5C`) in light appearance and bright platinum
(`#D1DCE8`) in dark appearance. Mac filter headers and setup links use the explicit
brand accent, including exported setup prompts. iPhone/iPad category selection and
About actions use the same accent and silver reflection surfaces. WeChat updates
shells, navigation/refresher backgrounds, category glass, filters, sheet selection,
dialogs, capture actions, About and exported images. WPF updates panel colors,
actions, selected filters and segmented selection gradients. Source blue/purple,
provider identity and semantic quota/status colors are intentionally retained;
native desktop table surfaces and control rendering remain platform-specific.

Ignored `work/platinum-theme/` retains the fixture, source hashes, native Mac
before/after captures, frame checks and review. Each phase contains 48 original
PNGs: eight cases, both appearances and shown/refreshed/settled checkpoints.
Cases cover English/Simplified/Traditional Chinese, normal/failed refresh, empty
quota setup, many quotas and active source filters at 600/900×720 points. Both
phases use the same final fixture with alternating source metadata so filtered
rankings remain populated. The first baseline attempt failed the blank-frame
check on an empty filtered ranking; the preserved original baseline executable
was rerun successfully with the corrected fixture before comparison. Native
review checks contrast, alignment, clipping, long names and control states.
Mac native table chrome and semantic data colors are preserved intentionally.
The capture host is macOS 27.0.1 (26A434), actual 1× backing scale; all sixteen
refreshed/settled content pairs are stable, with twelve differing only in the
fading native scrollbar strip.

All 106 WeChat tests and its production build pass. Official WeChat DevTools
readback confirms `rgb(65,77,92)` on light category actions against
`rgb(244,245,247)`, and `rgb(209,220,232)` on dark actions against
`rgb(16,18,22)`, including dark About actions and selected filter sheet entries.
The console error query returned no matching logs. Shared Apple UI compilation
and four existing brand render/layout tests pass. WPF Release cross-compilation
passes with zero warnings/errors. Current native Windows/DPI captures, iPhone/iPad
native screenshots and a source-matched CI `native-visual-comparison` artifact
remain unavailable; those visual environments are not signed off. No installed
app replacement, release publishing or protected release approval is claimed.

## Mobile attribute hints — 2026-10-17

WeChat flags now show a localized country name on tap; model source icons show Open, Closed or Unknown. The 44px-high button areas retain the existing columns, and cube drags suppress accidental hints. iPhone/iPad use native anchored popovers, dismissed by tapping outside; exported images retain plain symbols. The existing unknown-country explanation is preserved.

Ignored `work/attribute-hints/` retains a frozen mobile source snapshot, hashes, `Phone-Final.xcresult`, eight original native screenshots and `review.json`. The iPhone 18 Pro / iOS 27.0 simulator uses a 402×874-point viewport at actual 3× scale. Its focused UI test passes all four values and dismissal in Chinese/light and English/dark; review confirms readable, anchored popovers. An initial accessibility wrapper exposed the country control as an Other element; the final control retains native Button semantics and a localized label. The final test passes with zero failures.

All 105 mini-program tests and the production build pass; the final focused page run passes 44 tests. Official WeChat DevTools taps read back United States and Closed with icon:none and 1800ms duration; touch areas measure 42×44 and 38×44px, with no matching console errors. Native captures are only 93×200 pixels at the current simulator zoom and do not certify visual legibility. No new iPad or physical-device capture is claimed.

## Polished platinum brand artwork — 2026-10-17

The user-selected **黑曜铂银 / Obsidian platinum silver — mirror finish** artwork replaces the preceding cobalt icon. `assets/brand/platinum-silver-source.png` preserves the exact approved built-in ImageGen output, with the original prompt alongside it. Application PNG/ICO/ICNS exports resize that master and apply the existing platform padding/corner masks; `app-icon.svg` embeds the same master. Regeneration no longer approximates the icon using flat colors. Transparent header marks retain the original vector geometry with reflected light/dark bands, cylindrical rod highlights and narrow bevels. Apple and mini-program wordmark letters use matching neutral silver stops, with deeper steel on light surfaces. Windows retains its native neutral title text and uses the shared transparent PNGs. Monochrome menu-bar artwork is byte-identical to the prior version.

Ignored `work/platinum-brand/review.html`, `review.json`, source hashes, fixture and originals retain 36 native Mac before/after pairs at 600/900 × 720 points, three languages, both themes and shown/refreshed/settled checkpoints. Actual environment: macOS 27.0.1 (26A434), 1× backing scale. Native review confirms the silver title/mark, preserved layout and spacing, legible thin strokes, and unclipped adjacent controls. Every header is stable across all three checkpoints. All four focused Swift brand rendering/layout tests, 106 mini-program tests, nine iOS asset/script checks, the mini-program production build and Windows Release cross-compilation pass; Windows has zero warnings/errors. The asset checks verify neutral metal plus separate bright/dark reflections, correct icon sizes and opacity, valid ICO/ICNS containers, exact master preservation and synchronized runtime copies.

Windows native screenshots/actual DPI, iPhone/iPad native captures, WeChat native simulator captures and a source-matched CI `native-visual-comparison` artifact remain unavailable. Generated assets, unit tests and cross-compilation do not replace these checks. No protected release approval or installed-client update is claimed.

## Deep space cobalt brand palette — 2026-10-17

The selected **深空钴蓝 / Deep space cobalt** palette replaces the green brand artwork with a midnight-blue tile (`#080F24` → `#172D50`), cobalt/ice-blue connections (`#4A80EC` → `#9BCBFF`) and cold-white nodes (`#EDF5FF`). The canonical SVG matches the approved candidate exactly. Network geometry, title contours, sizing and platform padding are unchanged; monochrome menu assets remain byte-identical. All color SVG/PNG/ICO/ICNS exports, the shared Kit resources and the iOS app-icon catalog are synchronized. Light-surface header artwork uses deeper cobalt for contrast; Apple and mini-program wordmark letters and Canvas exports use the matching light/dark palettes.

Ignored `work/cobalt-brand/review.html`, `review.json`, source hashes and fixture retain 36 native Mac before/after pairs at 600/900 × 720 points, three languages, both themes and shown/refreshed/settled checkpoints. Actual environment: macOS 27.0.1 (26A434), 1× backing scale. Review confirms blue branding, preserved proportions and alignment, readable titles and unclipped neighboring controls. Every header is stable across all three checkpoints. All four focused native brand rendering/layout tests, 106 mini-program tests, its production build, nine iOS asset/script checks and Windows Release cross-compilation pass; Windows reports zero warnings/errors.

Current Windows native screenshots/actual DPI, iPhone/iPad native captures, WeChat native simulator captures and a source-matched CI `native-visual-comparison` artifact remain unavailable. Cross-compilation and generated artwork do not substitute for those visual checks. No protected release approval or installed-client update is claimed.

## OpenAI renewed-login priority — 2026-10-17

The current Codex login returned HTTP 200 from the usage endpoint while the same account's older AI BenchGauge profile returned HTTP 401 `token_revoked`, despite its JWT expiry still being in the future. Discovery already selected the newer Codex token, but the managed quota source unconditionally took precedence. It now yields to a newer, unexpired token only when the selected account, saved profile and authorization binding match. The usage endpoint still validates that token; older, expired, opaque or unscoped candidates cannot override the profile. Neither client's credential file or refresh token is copied or changed by this selection.

The corrected shared client loads the live account's quota and entitlement date. All 54 related Swift tests pass, including end-to-end discovery → merge → managed-source selection → HTTP validation, exhausted weekly quota, revoked replacement tokens and interrupted account changes. Ignored `work/openai-login-investigation/` retains a credential-free HTTP status comparison, live summary, test logs and linked native `review.html`. Each synthetic phase has 36 original Mac frames at 600/900 × 820 points, three languages, light/dark and shown/refreshed/settled. These represent the former reauthentication status and the repaired authenticated usage state, including zero weekly quota; they are not historical live-account screenshots. Review confirms readable quota values, preserved controls and the existing exhaustion style; all twelve refreshed/settled quota bands match on macOS 27.0.1 (26A434), actual 1× backing scale.

Current Windows native screenshots, actual DPI verification and a source-matched CI `native-visual-comparison` artifact remain unavailable. No cross-platform visual sign-off, protected release approval or replacement of the running application is claimed.

## Kimi expired plan status — 2026-10-17

The configured Kimi key returned HTTP 200 with `{}` after the user's plan expired. The client previously parsed that response as zero windows, which the formatter displayed as a failed query. It now maps only this successful empty object to the existing dimmed `未订购` / `未訂購` / `Not subscribed` presentation and missing-plan ordering. HTTP authentication errors, empty bytes, unknown bodies and network failures retain their existing behavior. A later successful quota response restores the normal card.

Ignored `work/kimi-expired-plan/` retains the credential-free live-check summary, 86 passing Swift quota regression tests, passing Windows shared harness, native metadata and a linked `review.html`. Synthetic fixtures reproduce the former failed-query status and the corrected status; they are not historical live-account screenshots. Each phase has 36 original native Mac frames at 600/900 × 820 points, covering three languages, both themes and shown/refreshed/settled checkpoints. On macOS 27.0.1 (26A434), actual 1× backing scale, review confirms readable neutral status text and ordering after the funded metered card; all twelve refreshed/settled quota bands match. Supplemental bands are unscaled crops and full originals remain available.

Current Windows native screenshots, actual Windows DPI review and a source-matched CI `native-visual-comparison` artifact are unavailable. No protected release approval or replacement of the running app is claimed.

## Score proportions below values — 2026-10-17

WeChat, Mac, iPhone/iPad and Windows show a small muted integer percentage below each score, relative to the first entry of that source after filtering and company aggregation. Leaders, ties and ratios rounding to 100% are omitted; invalid or zero baselines produce no annotation. CSS absolute positioning, SwiftUI overlays and a zero-size WPF Canvas keep the existing score alignment, row heights and column widths. WeChat and Apple image exports use the same calculations as their live views. These percentages describe relative source scores, not normalized model ability or cross-source comparisons.

Ignored `work/score-share/review.html`, `review.json`, source snapshots and fixture retain 36 native Mac before/after pairs at 1100×720 points, macOS 27.0.1 (26A434), actual 1× scale. The fixture includes tied leaders, a near tie rounding to 100%, lower and zero scores, three languages, model/company grouping, both themes and shown/refreshed/settled checkpoints. Review confirms subordinate labels and preserved score/row positions. All twelve refreshed/settled pairs differ only in the native scrollbar strip, outside the score content. The Apple export rendering test passes its wide/narrow, language and theme matrix; those native SwiftUI renders are retained under `work/score-share/apple-exports/` and are not mobile device captures.

All 103 mini-program tests and its production build pass. Official WeChat DevTools readback confirms independent baselines (97% on the second AA row, 99% on the second Arena row), absolute positioning, 7px annotation text and unchanged 48px rows, with no console errors. Original simulator screenshots are only 93×200 pixels at the current display zoom, so they do not certify visual legibility. Three focused Swift calculation/filtering tests and the Windows shared harness pass; Windows Release cross-compilation has zero warnings/errors. An isolated iOS simulator app builds the current shared Kit/UI sources for arm64 and x86_64 with Xcode 27; its manifest excludes desktop-only dependencies after the full package graph attempt stalled during resolution. Current Windows native screenshots, actual DPI validation, mobile device screenshots and a source-matched CI `native-visual-comparison` artifact remain unavailable. No protected release approval or client distribution is claimed.

## Country and source header centering — 2026-10-15

The mini-program positions each filter caret absolutely beside a centred label. Windows replaces the horizontal caption/caret stack with a centred caption and a zero-width Canvas overlay. iPhone/iPad use equal-width caret slots on both sides of the title, with only the right caret visible, so native Menu labels keep the caption centred over its column. Menus and filtering callbacks are unchanged. Mac already draws the centred title and caret separately and needs no implementation change.

Mini-program production build and simulator before/after inspection pass. Mac and shared SwiftUI compilation pass. WPF Release cross-compilation passes with zero warnings/errors. Ignored `work/header-centering/mac/macos` contains 18 original native Mac frames from the saved synthetic fixture, covering three languages, both themes and shown/refreshed/settled checkpoints at 850×720 points, macOS 27.0.1 (26A434), actual 1× scale. Review confirms centred captions and separate carets; all refreshed/settled pairs match. This is a current-state check of the unchanged Mac implementation.

The isolated iOS simulator build passes. Original iPhone 18 Pro / iOS 27 / 3× Chinese-light before/after captures use the same 20-row synthetic data at 402×874 points. Review confirms that both caption centres align with their body columns and that the right carets remain visible; symmetric caret slots slightly widen mobile filter columns. The mobile harness freezes unrelated scrolling code because concurrent workspace edits changed its cube API. The initial overlay attempt was discarded after native Menu labels omitted its carets. iPad native capture did not complete; rotation, other mobile languages/themes and Dynamic Type were not reviewed for the final layout.

Current-change Windows native before/after captures and a source-matched CI `native-visual-comparison` artifact are unavailable on this Mac host. Windows visual alignment and other DPI settings remain unverified; compilation does not substitute for native visual review. No protected release approval is claimed.

## Desktop brand initial height — 2026-10-15

The A-shaped mark now uses the adjacent I's painted height and vertical position in the Chinese and English Apple titles and Windows WPF header. Its aspect ratio, visible gap and the remaining title's native positions are preserved. Width-based sizing previously made the mark extend below I. The Apple title views are shared with mobile; mobile native screenshots were not repeated for this desktop report.

Ignored `work/desktop-initial-height/review.html` and `review.json` retain 36 native Mac before/after pairs, source snapshots and pixel measurements. Both phases use the same synthetic fixture, 850×720 content viewport, macOS 27.0.1 (26A434) and actual 1× backing scale. English, Simplified/Traditional Chinese, light/dark and normal/failed refresh cover shown/refreshed/settled frames. All measured mark/I bottoms match; English tops match, and Chinese dark tops differ by one antialiased raster pixel. Every refreshed/settled header pair is stable. Full-window differences also include concurrent help-control and filter-caption changes in the shared checkout; some body images settle asynchronously. Review confirms the shorter mark, preserved proportions and intact title spacing.

All four existing BrandHeadingTests/BrandLogoTests pass, including native frame/baseline compatibility and rendering at multiple font sizes. Windows WPF Release cross-compilation passes with zero warnings/errors. Current-change Windows native captures, actual Windows DPI review and a source-matched CI/native-visual-comparison artifact remain unavailable. No Windows visual sign-off or protected release approval is claimed.

## Quieter subtitle ampersand — 2026-10-13

Mac and iPhone/iPad use a shared `FeatureSubtitle` to color only `&` at 55% opacity within one attributed Text. Windows applies the same opacity to the ampersand's native FormattedText range. Both preserve the full localized caption, font, continuous spacing and accessibility text; the question mark retains its preceding 55% treatment.

Ignored `work/quiet-ampersand/review.html` and `review.json` retain 72 before/after native Mac pairs from the same synthetic fixture and 850×720 viewport. Three languages, both themes, model/company grouping, normal/failed refresh and shown/refreshed/settled frames are covered on macOS 27.0.1 (26A434), 1×. All 24 refreshed/settled pairs match. Review confirms a softer ampersand, complete captions and preserved bottom alignment. Attributed-text rasterization introduces minor antialiasing differences across the caption; normal text retains its original ink level, while the light-theme ampersand changes from approximately RGB 128 to RGB 186.

Mac compilation, shared mobile SwiftUI type-checking and Windows WPF Release cross-build pass; Windows has zero warnings/errors. Mobile native captures were not repeated for this text-color edit. Windows native screenshots/DPI verification remain unavailable; no CI artifact or protected release approval is claimed.

## Quieter subtitle help icon — 2026-10-13

Mac, iPhone/iPad and Windows render only the subtitle's question-mark icon at 55% opacity. Subtitle text, icon sizing, button geometry, actions and accessibility labels are unchanged.

Ignored `work/quiet-help/review.html` and `review.json` retain 72 before/after native Mac pairs using the same synthetic fixture and 850×720 viewport. English/Simplified/Traditional Chinese, both themes, model/company grouping, normal/failed refresh and shown/refreshed/settled frames are covered on macOS 27.0.1 (26A434), 1×. Header pixel differences are restricted to the question-mark rectangle: x=197…207 / y=21…31 for Chinese and x=348…358 / y=25…36 for English. All 24 refreshed/settled pairs match. Review confirms a softer icon in both themes with unchanged title/subtitle text and alignment.

Mac compilation, shared mobile SwiftUI type-checking and Windows WPF Release cross-build pass; Windows reports zero warnings/errors. Mobile native screenshots and click tests were not repeated for this opacity-only edit. Windows native screenshots/DPI verification remain unavailable; no CI artifact or protected release approval is claimed.

## Bottom-aligned subtitle without app version — 2026-10-13

Mac, Windows and iPhone/iPad live headers remove the displayed app version and place the feature subtitle, including its help control, beside the title's visible bottom edge. Apple layouts now contain two children; Windows measures/arranges only the subtitle and help button. Mobile subtitle scaling no longer reserves room for a version line. Background update behavior and bundle/version metadata remain in place; README copy no longer advertises the removed version-click action.

Ignored `work/header-subtitle-bottom/review.html`, `mac-review.json`, `mac-settled.json` and source snapshots retain native evidence. Mac has 72 before and 72 after original frames from the same synthetic fixture and 850×720 viewport: three languages, both themes, model/company grouping, normal/failed refresh and three checkpoints. Environment is macOS 27.0.1 (26A434), 1×. All 24 refreshed/settled pairs match. The preserved before executable predates a concurrent source-time presentation update, so full-window differences also include that update; this comparison verifies header placement, not those body changes. Review confirms complete subtitles at the title's lower right and no app version text.

iPhone 18 Pro / iOS 27.0 (402×874 points, 3×) and iPad Pro 11-inch M5 / iPadOS 27.0 (834×1210 points, 2×) each retain 12 original after PNGs and passing xcresult bundles. Chinese/light and English/dark cover portrait/landscape plus shown/refreshed/settled frames. The temporary visual harness verifies the version element is absent, the title remains accessible and the help control remains hittable within the viewport. Review confirms complete English and Chinese captions beside the title's visible bottom. The frozen portable snapshot preserves header source exactly; subsequent primary-checkout spacing/time-row changes are outside this validation.

Mac compilation, shared mobile SwiftUI type-checking, iOS simulator test build and both native capture tests pass. Windows WPF Release cross-build has zero warnings/errors; native Windows screenshots/DPI validation are unavailable. Physical devices, other OS versions and large Dynamic Type were not recaptured. No CI native artifact, protected release approval or public distribution is claimed.

## Model source badges — 2026-10-13

Mac, iPhone/iPad and Windows model rows distinguish Open with a green unlocked-padlock badge and Closed with a slate-blue locked-padlock badge. Both retain localized text and adapt their foreground/background colors to light and dark appearance. Missing metadata and company rows remain neutral dashes. Apple live views and exported images share `ModelOpennessBadge`; mobile source-column sizing measures the badge so the icon stays inside its column.

Ignored `work/openness-badges/review.html`, `review.json` and `source-hashes.json` retain 120 before/after pairs (240 original native PNGs). Mac uses the same synthetic fixture and 850×720 viewport in both phases, covering English/Simplified/Traditional Chinese, light/dark, model/company grouping, normal/failed refresh and shown/refreshed/settled frames. Environment: macOS 27.0.1 (26A434), 1×. All 24 after refreshed/settled pairs are identical. Native review confirms visible lock silhouettes, readable status text and separated badge backgrounds. Existing long-name truncation at the forced desktop width remains visible.

Isolated iPhone 18 Pro / iOS 27.0 (402×874 points, 3×) and iPad Pro 11-inch M5 / iPadOS 27.0 (834×1210 points, 2×) captures cover Chinese/light and English/dark, portrait/landscape, model/company grouping, long names and three refresh checkpoints. Each device's before/after visual harness passes; both after source-filter/intersection tests also pass. Originals retain their orientation metadata in the review directory and xcresult bundles. Review confirms complete badge labels alongside scores/countries in compact and paired layouts; phone long names retain the existing two-line truncation.

Six focused Swift tests pass, including classification/cache compatibility, source filters and export rendering. Export previews cover all three languages, both themes, wide/narrow layouts and configured/unconfigured App Store links. Mac and iOS simulator builds pass. Windows WPF Release cross-build passes with zero warnings/errors; real Windows native screenshots/DPI validation remain unavailable. Physical-device review, other OS versions and large Dynamic Type were not obtained for this change. No CI native artifact, protected release approval or distribution is claimed.

## Model and company logo separation — 2026-10-13

The exact shared fixture `work/model-logos/fixture.json` contains official Wan, Dreamina, SkyReels and Grok PNGs, separate provider PNGs, a missing-image/long-name row and refresh-error state. The before app is the previously captured source-filter native executable; the after app is built from the isolated local snapshot with the new shared Kit. Both use the same 850×720 content viewport and fixture hash. `before/macos` and `after/macos` contain 36 original PNGs each: English, simplified/traditional Chinese, light/dark, model/company grouping and shown/refreshed/settled frames. OS: macOS 27.0.1 (26A434), actual scale 1×. `native-review.json` records pixel differences; `mac-review.png` is a review aid, not a substitute for originals.

Native review confirms model rows retain family-specific marks and company rows return to provider marks. Colors follow model marks. Initial fallback, white logo tiles, supported themes and refresh-error content remain visible. At the forced narrow width, existing English company purchase links wrap and model names truncate with their existing help text; this remains a documented layout limitation unrelated to logo selection.

The iPhone 18 Pro (iOS 27, 402×874 pt / 3×) and iPad Pro 11 M5 (iPadOS 27, 834×1210 pt / 2×) native UI suites pass model/company switching and refresh-error frames in Chinese/light and English/dark. Original attachments and xcresult bundles remain in `work/model-logos`. The iPad English company purchase controls can leave Alibaba’s label wrapping into narrow character columns; this pre-existing company-row layout limitation remains unresolved and the logo test does not certify that layout. Wan's official purple mark appears on both Wan rows; the Alibaba row uses the separate orange provider mark. Windows uses the same Swift engine projection and shared Kit; a real WPF capture is unavailable locally, so Windows visual parity remains unverified. No protected release or visual-review approval is implied.

# Native visual comparison

## Source filter dropdown (2026-10-13)

Mac, Windows and iPhone/iPad source headers now carry the same downward caret as country. Menus offer All/Open/Closed/Unknown, check the current choice and tint an active source filter. Choices are independent per leaderboard and intersect country filters before company aggregation, so a company's strongest matching model determines its filtered score. Unknown source metadata remains unavailable, and company rows retain their dash. Mobile and Windows remember choices using their existing preference stores; Mac follows its existing in-session country-filter behavior. Windows sends both filters to the shared engine and rejects replies for an outdated filter selection.

Ignored `work/source-filter/review.html` and `review.json` retain 174 original Mac PNGs: 36 before and 36 after baseline frames using the exact same fixture and viewport, plus 90 filtered-state frames and 12 empty/intersection/independent-board frames. English/Simplified/Traditional Chinese, light/dark, failed refresh, long model names, company grouping, and shown/refreshed/settled checkpoints are covered at 850×720 points. Environment is macOS 27.0.1 (26A434), 1×. All 36 baseline differences stay inside the table-header band (y=116…130); all 46 after refreshed/settled pairs are identical. Review confirms visible carets, active tint, readable status values, and unchanged model-row layout. The deliberately narrow English company fixture still wraps purchase links; production preferred sizing continues to use all cached model/company names and links, independent of filters. Wider/other-DPI native Windows comparison remains outstanding.

The empty-left-board dark fixture exposed a sparse sampling gap in Mac sharing capture. Sampling now includes the interior of the right name column, preserving existing blank-capture rejection thresholds. The same normal sharing-capture path now renders all three checkpoints in both themes; the capture harness does not bypass that validation.

Native iPhone 18 Pro / iOS 27.0 / 3× and iPad Pro 11-inch M5 / iPadOS 27.0 / 2× menu tests pass in English/light. They verify all four source options, country intersections producing no matches, reset, company grouping, and the iPad's independent right-board selection. Both original source-column/company tests also pass. Their unmodified native screenshots and test results are retained in `work/source-filter/phone-retry.xcresult` and `pad.xcresult`. Other mobile themes/languages, rotation and large text were not recaptured for this change. Shared-engine JSON round trips pass for open/closed/unknown, country intersection, and a company score reduced from 100 to its matching open model's 80. Windows WPF Release cross-build passes with zero warnings/errors. No Windows desktop/VM or source-matched cloud native artifact is available locally, and no protected release publishing or approval is claimed.

The primary checkout's complete tests passed, but the parallel coverage task repeatedly changed inputs during subsequent validation/build checks. To avoid invalidating that task or overriding gates, a detached Git worktree at `work/source-filter/build-snapshot/ai-benchgauge` freezes the working files from 01:53. Its full script/Swift/Windows tests pass with an unchanged signature; the returned result is retained in `build-snapshot/full-test-result.json`. Its normal iOS SDK check, development signing/installation and Mac packaging/deep-strict signature verification pass. The Mac bundle was copied into the usual outputs location and restarted. The iPhone installation receipt matches this checked snapshot; automatic launch was blocked by the locked phone, so it needs to be opened after unlocking. `installed-ui-source-comparison.json` confirms all 11 feature source files still match the primary checkout. The parallel task's later unrelated changes are preserved there; this installation is not claimed to include them. The snapshot is retained for reproducibility and no commits or pushes were made.

## Desktop dual-board subtitle (2026-10-13)

Mac and Windows live headers add `双榜对照` / `雙榜對照` / `Dual boards` immediately right of the app title, with the 9-point version below. The subtitle’s visible top and the version’s visible bottom use the title’s actual glyph bounds, matching the mobile arrangement. The version retains its check-for-updates action and Windows update arrow. Mac uses CoreText and a SwiftUI layout; WPF measures native FormattedText geometry for its caption panel.

Ignored `work/desktop-subtitle/review.html` compares 72 native before and 72 native after Mac originals from identical fixtures and viewports. Before uses the preserved executable from the preceding manufacturer-asset review, whose relevant header source is unchanged; the pre-edit files are retained in `before-source/`. Both phases cover English/Simplified/Traditional Chinese, light/dark, 850/1100-point widths, normal/failed refresh, and shown/refreshed/settled checkpoints, including an update arrow. `review.json` records fixture/source/image hashes, dimensions and native metadata. Actual environment is macOS 27.0.1 (26A434) at 1× backing scale. All 72 after frames align both edges within one raster pixel; all 24 refreshed/settled pairs are identical. Native review confirms complete captions and unobstructed grouping/category controls and freshness labels.

Full project checks pass, and the Windows WPF Release cross-build has zero warnings/errors. Local Mac packaging and deep/strict signature verification pass, and the installed app was restarted successfully. The successful full-test result is preserved in `work/desktop-subtitle/package-test-result.json`, so simultaneous coverage checks cannot replace the validation used by this packaging flow. No Windows desktop or VM is available locally, so current Windows native captures and real DPI validation remain outstanding. No source-matched cloud CI artifact or protected release approval is claimed.

## Mobile header edge alignment (2026-10-13)

The live iPhone/iPad version uses a 9-point base size (previously 12). The right-hand subtitle and version now align their visible top/bottom edges with the title’s actual glyph bounds. Chinese caption whitespace shrinks from 19 to 11 raster pixels on the 3× phone and from 13 to 7 on the 2× iPad. English larger text can select a smaller complete heading to keep the captions visible. Desktop and export-card headers are unchanged.

Ignored `work/header-edges/review.html` compares 24 native before and 24 native after originals; `review.json` records hashes, dimensions, EXIF orientation and edge measurements. Before captures are retained from the immediately preceding brand-discovery review with identical fixtures and viewports. Both device capture tests pass: iPhone 18 Pro / iOS 27.0 / 3× (402×874 points) and iPad Pro 11-inch M5 / iPadOS 27.0 / 2× (834×1210 points), each in portrait/landscape and Chinese/light or English/dark, shown/refreshed/settled. All 24 after frames have top and bottom edge differences of at most one raster pixel; all eight refreshed/settled product comparisons are identical excluding native status-bar clocks. Two additional original phone screenshots confirm complete Chinese and English headers at `accessibility-medium`; standard text size was restored. Other OS versions, the largest accessibility sizes and physical iPad visual review remain uncovered. Final full project checks and the iOS SDK build pass. The local iPhone was installed and opened successfully; its installation receipt matches the current source fingerprint.

## Automatic manufacturer assets (2026-10-13)

Mac, iPhone/iPad and Windows render the shared 64×64 PNG carried by each leaderboard row before trying a bundled logo. Unavailable or invalid images produce an initial inside the existing white icon tile. Dark appearance now uses explicit dark ink on that tile so the initial stays visible. New manufacturers receive a shared extracted color or a stable fallback wash; existing brand hues retain their theme and per-model treatment. Company rows keep the flagship's shared asset, and offline/export views use the same snapshot bytes. Windows receives PNG Base64, color and initial through the shared engine protocol.

Ignored `work/brand-discovery/review.html` links 48 original before/after pairs (96 native frames), with file hashes, sizes, EXIF orientation and source hashes in `review.json`. Before and after use the same brand payloads: one shared PNG and long model name, one new manufacturer without an image, plus existing brands. Mac covers English and Simplified Chinese, light/dark, normal/failed refresh and shown/refreshed/settled frames at 920×720 points. Both mobile devices cover Chinese/light and English/dark, portrait/landscape and the same three checkpoints; the fixture is offline to exercise saved images and failure placeholders. All 16 refreshed/settled comparisons are identical after excluding mobile system status bars. Review confirms visible PNGs, readable initials on white tiles in dark appearance, background washes, unchanged row alignment, and preserved source captions on failures.

Actual native environments: macOS 27.0.1 (26A434), 1× backing scale; iPhone 18 Pro / iOS 27.0, 402×874 points at 3×; iPad Pro 11-inch M5 / iPadOS 27.0, 834×1210 points at 2×. Mobile devices passed the focused native capture test in both phases. Windows WPF cross-build succeeds, but no native Windows environment or new CI visual artifact was available, so Windows visual parity remains unverified. Full checks pass: 131 script tests, 325 Swift tests and Windows signature/update plus brand-protocol checks. The local Mac bundle and paired physical iPhone were updated after validation. Existing Mac 20-point and mobile 18-point icon tiles are retained. No protected release publishing was invoked.

Shared FC production requests also verify both real video boards: 20 rows each return valid shared PNGs, including Utopai Studios, Skywork AI and Sapiens AI, whose colors were extracted automatically. Responses remain below 48 KiB. `final-live-video.json` and the corresponding original PNGs are retained in the ignored review directory.

## Mobile dual-board subtitle (2026-10-13)

iPhone and iPad live headers now show `双榜对照` / `雙榜對照` / `Dual boards` immediately right of the app title, above the version. This states the product's two-source comparison feature without asserting exclusivity among competing apps. A custom descendant alignment guide keeps the version's visible glyph bottom aligned with the title. Compact headers retain both labels when space is tight: English portrait and larger text move the model/company control onto a following row. Wide iPad keeps its paired-board header and centered 360-point category control. Desktop headers and the export-card title are outside this change.

Ignored `work/mobile-subtitle/review.html` retains 24 native before and 24 final after originals, with source/image hashes, dimensions, EXIF orientation and measurements in `review.json`. Before frames come from the preceding source-column review with identical fixture data and viewports. Each device covers Chinese/light and English/dark, portrait/landscape, and shown/refreshed/settled frames. Actual environments are iPhone 18 Pro / iOS 27.0 at 3× (402×874 points) and iPad Pro 11-inch M5 / iPadOS 27.0 at 2× (834×1210 points). Review confirms complete subtitle text, readable controls and no header clipping. The title/version visible bottoms differ by at most one raster pixel in all 24 after frames. All eight refreshed/settled product comparisons are identical after excluding native status-bar clocks. Two additional original phone snapshots at `accessibility-medium` confirm the responsive header in Chinese/light and English/dark; the simulator's standard text size was restored afterward.

Both devices passed the focused native screenshot test on the final source; the native SDK build passed. The complete local gate passed 124 script checks, 321 Swift tests and 39 Windows harness cases. An initial gate run exhausted an existing asynchronous test's two-second deadline while concurrent ImageRenderer work held MainActor for 2.8 seconds. The final run after native tests passed without changing production behavior or that test's deadline. The signed development app was installed and opened on the configured physical iPhone at 00:05:23 Asia/Shanghai, with its receipt matching the current source fingerprint. Other iOS runtimes, narrow iPad windows, the largest accessibility sizes and physical iPad visual review were not obtained. No protected release publishing was invoked.

## Model source column (2026-10-12)

Mac, iPhone/iPad and Windows tables add a source column between score and country: `Source` / `源码` / `源碼`, with localized Open/Closed values. Missing source metadata and company aggregation rows show `—`. The parser follows Artificial Analysis's explicit public-weight fields and Arena's recognized licenses, including restricted public-weight licenses; the help text explains that usage restrictions may apply. The coding-agent source currently lacks this metadata. Unknown licenses remain unavailable rather than becoming a closed-source assertion. Optional Codable fields retain compatibility with old caches. Shared FC contributions acquire the field automatically on ordinary refreshes.

Ignored `work/model-openness/review.html` links 120 original native screenshots with hashes, source hashes, environment and validation recorded in `review.json`. Mac before/after each contain 36 frames: English/Simplified/Traditional Chinese, both appearances, 850/1100-point widths, and shown/refreshed/settled checkpoints. Both phases use the same fixture and the before phase uses the preserved original executable. Actual environment is macOS 27.0.1 (26A434), 1× backing scale. Narrow fixed viewports intentionally truncate long model names; the production popover's preferred width expands to accommodate the added columns. Review confirms readable status values and full country headers on both boards.

iPhone 18 Pro / iOS 27.0 at actual 3× and iPad Pro 11-inch M5 / iPadOS 27.0 at 2× each retain 12 before and 12 after frames, covering Chinese/light and English/dark, both orientations and three checkpoints. Mobile before originals come from the preceding version-alignment review with the same names, scores and viewports; the after fixture adds explicit open, closed and unknown fields. PNG pixels and EXIF orientation are preserved. All 20 refreshed/settled comparisons across Mac and mobile are identical after excluding mobile status-bar clocks. Source captions, category placement and version bottom alignment remain readable. Each mobile device passed two focused native tests, including source values and company aggregation behavior.

The full local gate passed 124 script checks, 321 Swift tests and 39 Windows harness cases. Native iOS SDK build and Windows WPF Release cross-build passed; WPF reported zero warnings/errors. Mac release packaging and deep/strict signature verification passed, and the local app was restarted. The physical iPhone installation at 23:44:09 Asia/Shanghai matched the current source fingerprint. The shared function deployment completed at 23:38:22; smoke checks verified populated source fields for newly contributed coding/image boards. General/video caches without the field retain `—` until the next successful refresh under the existing global gate. No refresh restriction was bypassed.

Windows native WPF/real DPI captures and source-matched cloud CI artifacts are unavailable. Large Dynamic Type, narrow iPad windowing and Mac empty/error/company captures for this column were not obtained. This local review does not constitute protected release approval.

## iOS version label bottom alignment (2026-10-12)

The iPhone/iPad version label now aligns with the title's visible glyph bottom rather than its font baseline or center. The Chinese outline exposes its actual path bottom; the English title and version use CoreText glyph bounds relative to SwiftUI's first baseline. Scaled metrics preserve the existing text-size behavior. The change covers the phone header and both iPad header layouts. Desktop header alignment is unchanged.

Ignored `work/ios-version-alignment/review.html` links 24 native before and 24 native after originals from the same fixtures/viewports. iPhone 18 Pro / iOS 27.0 uses actual 3× scale; iPad Pro 11-inch M5 / iPadOS 27.0 uses 2×. Chinese/light and English/dark cover portrait/landscape and shown/refreshed/settled frames. Before captures are retained from the immediately preceding category-tab review, whose title/header code is preserved in source snapshots. Original PNG pixels and orientation are retained. Review confirms readable titles, unchanged category placement, and no clipping. Visible-bottom measurements for every after frame differ by at most one raster pixel, compared with a 3-point Chinese / approximately 6-point English gap before. `review.json` retains measurements and source/original-image hashes.

Both devices passed the existing focused native screenshot test. The full gate passed 123 script checks, 318 Swift tests and 39 Windows cases; the native SDK build passed. The development app was installed and opened on the configured physical iPhone at 23:23:23 Asia/Shanghai, with its receipt matching the current source fingerprint. Large Dynamic Type and narrow iPad windowing were not captured in this run. No cloud CI or human release approval was invoked.

## iOS category tab width and centering (2026-10-12)

The phone category control no longer stops at 360 points: each of its four native segments gets one quarter of the available content width, matching both edges of the cube viewport in portrait and landscape. The iPad category remains 360 points wide and is centered independently of the leading model/company control. Its responsive fallback keeps the category centered on a separate row in narrower windows. Segment widths are still assigned only when UIKit creates the control; the phone's width identity recreates it after rotation without changing the saved selection.

`work/ios-category-tabs/review.html` retains 24 native before and 24 native after captures, using the same fixtures and viewports on iPhone 18 Pro / iOS 27.0 at actual 3× scale and iPad Pro 11-inch M5 / iPadOS 27.0 at 2×. Captures cover Chinese/light and English/dark, both orientations, and shown/refreshed/settled frames. Original PNG pixels and EXIF orientation are preserved; diagnostic header crops honor orientation without replacing the originals. All 16 refreshed/settled product comparisons are pixel-identical after excluding the native status-bar clock. Review confirms centered iPad tabs, full-width phone tabs, unchanged readable titles and source descriptions, and no clipping.

Each device passed both focused native tests, including equal segment widths, rotation, category selection, phone viewport-edge alignment and iPad's 360-point width/window-center assertions. The full gate passed 123 script checks, 318 Swift tests and 39 Windows cases. The development build was installed and opened on the configured physical iPhone at 23:07:11 Asia/Shanghai; its receipt matched the complete current source fingerprint. Reviewed source hashes and original screenshot hashes are retained in `work/ios-category-tabs/review.json`. Narrow iPad windowing and other display runtimes were not captured in this run. No cloud CI or human release approval was invoked.

## iOS exported image download attribution (2026-10-12)

Copied and saved leaderboard images no longer promote the GitHub repository. Before App Store publication they retain the localized app name and iPhone/iPad attribution. Setting the real numeric `appStoreID` in `config/app.json` and regenerating the Xcode project enables the localized App Store download prompt and direct `apps.apple.com/app/id…` address. The current ID stays `null`, as the publisher confirmed that the app is not yet listed. The license sheet retains its project-source link.

Ignored evidence lives in `work/ios-store-footer/review.html`, with PNG hashes and native metadata in `review.json`. Three before images and 24 after variants use the actual shared SwiftUI ImageRenderer on macOS, covering English/Simplified/Traditional Chinese, 1000/440-point widths, both themes, and unpublished/configured states. The configured variants use synthetic ID `1234567890` solely for layout review. The existing narrow English export title truncation is outside the changed footer.

Native iPhone 18 Pro / iOS 27.0 (3× display) and iPad Pro 11-inch M5 / iPadOS 27.0 (2× display) each passed four language/theme export combinations (English/Simplified Chinese × light/dark). Eight original exported PNGs were retained directly from the app's actual copy-image action, at the renderer's 2× export scale. Test result bundles also retain the native clipboard-feedback screenshots. The UI-test runner cannot read the app's clipboard on this OS, so Debug-only fixture capture retains exported pixels inside the app sandbox; Release builds exclude that capture path. Review confirms full footer text, preserved blue/purple source explanations, and no GitHub download address.

The final full gate passed 123 script checks, 318 Swift tests and 39 Windows cases. Each device's focused native export test passed. The development build was installed and opened on the configured physical iPhone at 22:54:56 Asia/Shanghai; the installation receipt matched the complete current source fingerprint and the reviewed files remained unchanged. An intermediate expanded visual matrix held MainActor long enough to exceed an unrelated async store test's deadline; the extended matrix is now opt-in for capture, with the ordinary regression gate retaining its previous three export layouts. No cloud CI or human release approval was invoked.

## Mobile source labels and refresh failures (2026-10-12)

The iPhone/iPad source explanation now keeps its emphasized label in semibold
system blue for Artificial Analysis and system purple for Arena, matching the
desktop source colors. The explanatory detail retains its secondary color.
Refresh failures have a separate orange button below the explanation; both
buttons open the source details, including the failure reason. Source labels
remain present with cached data, with no cached board, and while refreshing.
Exported leaderboard images retain the same source emphasis colors.

`LeaderboardSourceDescriptionTests` adds deterministic native captures for both
sources in normal, cached-offline and empty-offline states, light/dark themes,
and shown/refreshed/settled checkpoints. Its behavioral regression checks that
the source-help and source-error buttons coexist, preserve the original source
label, and remain available after opening and closing error details.

Ignored `work/mobile-source-label/` preserves the Xcode result bundles, 36
original native iPhone before frames and 36 after frames, attachment manifests,
source hashes, review report and full-size original-image links. The iPhone 18
Pro simulator runs iOS 27.0 at actual 3× scale (1206×2622 pixels / 402×874 points).
Reviewed frames show readable blue/purple labels and secondary descriptions in
every state, with an independent orange failure row and no clipping. All 12
refreshed/settled product regions are pixel-identical after excluding the native
status bar's changing clock. The local gate passed 120 script checks, 315 Swift
tests and 39 Windows harness cases. The simulator build and both iPhone UI tests
passed. The signed app was installed and launched on the configured physical
iPhone; its deployment fingerprint matched the reviewed source at installation.
Subsequent concurrent leaderboard-service edits changed the checkout after that
installation; this review and its preserved test logs apply to the installed
build, with the mobile view and fixture source hashes still unchanged.

The iPad Pro 11-inch (M5), iPadOS 27.0, actual 2× scale (1668×2420 pixels /
834×1210 points), supplied 36 after frames using the same fixtures. Both UI tests
passed on a serial retry after the initial runner failed during startup. Native
review shows both source labels and independent failure rows together in the
two-board layout. Current iPad before captures and source-matched cloud CI
artifacts are unavailable; this local review is not protected release approval.

## Chinese brand title centering (2026-10-12)

The visible glyphs in `AI 天梯` now share a vertical center instead of a font
baseline. CoreText positions each outline by its own ink bounds; WPF does the
same with native `FormattedText` geometry. Latin remains 21 points/DIPs and the
Chinese calligraphy remains 25, retaining the taller Chinese lettering. Visible
horizontal gaps and the existing header height are preserved. The shared Apple
title implementation also applies to iOS.

Ignored `work/brand-title-center/{before,after}/macos` contains 36 original native
AppKit frames per phase, covering English, Simplified Chinese and Traditional
Chinese, light/dark appearances, 600/1100-point viewports, and shown/refreshed/
settled checkpoints. `fixture.json` preserves the common content; `review.html`
links full-size originals and `review.json` records environment and pixel checks.
Actual environment: macOS 27.0.1 (26A434), 1× backing scale, local uncommitted
source. Fixture SHA-256:
`d742606abefcfdcc842699ae6874b1e9fd1bf18b9eaca873dde1cd1d24f6c2ae`.

Reviewed native frames show vertically centered Latin and calligraphy with no
clipping. All 12 after groups are stable across their three checkpoints. English
frames are pixel-identical to before; Chinese differences stay within the title
glyph area, with the version, controls and table unchanged. Windows and iOS
native captures and source-matched CI artifacts are unavailable; this local Mac
review does not constitute protected release approval.

The local packaging gate passed with 120 script checks, 315 Swift tests and 39
Windows harness cases. The Windows WPF Release cross-build also passed with no
warnings or errors. Release packaging and deep/strict signature verification
passed; all 186 application input files match the packaged source, and the local
Mac application was restarted with the reviewed title change.

## Menu-bar logo appearance (2026-10-12)

The monochrome logo embedded in the status title now draws its alpha mask with
`NSColor.labelColor` resolved from the status button's effective appearance.
The attachment image disables caching, so an existing label adapts immediately
when the menu bar changes appearance. The icon-only state retains AppKit's native
template rendering; attachment size and baseline alignment are unchanged.

`Tests/fixtures/status-icon-appearance.json` covers task text, quota text in
English/Chinese, icon-only, highlighted, appearance changes without a data refresh,
and both directions between icon-only and text. Ignored
`work/status-icon-appearance/{before-targeted,after-final}/macos` preserve 48
original native AppKit frames per phase, at 420-point content width, both
appearances and shown/refreshed/settled checkpoints. `review.html` links the
unscaled originals and `review.json` records source hashes and pixel checks.
Fixture SHA-256: `9f4cb66b77b2b83ed053828d44a6bcf5b19153c646ae9fc011981244cb75cb6e`.
Actual environment: macOS 27.0.1 (26A434), 1× backing scale, local uncommitted source.

Reviewed native frames show a readable light logo on the dark bar and a dark logo
on the light bar, including highlighted and live appearance-change states. All
before/after differences stay within the 15×12-pixel glyph region. Text, task
colors, spacing and baseline positions are unchanged; native icon-only frames are
pixel-identical. Every refreshed frame equals its settled frame. Current Windows
native captures and a source-matched CI `native-visual-comparison` artifact are
unavailable; this Mac-specific review is not protected release approval.

The local packaging gate passed in an isolated copy of the application and shared
helper source, avoiding concurrent edits in the working checkout: 119 script
checks passed (one skipped), 315 Swift tests and 39 Windows harness cases passed.
Release packaging and deep/strict signature verification passed. The reviewed
source hashes match the packaged fix, and the local Mac application was restarted.

## Equal-spaced Slide Xiaxing title (2026-10-12)

Chinese branding now uses upright system semibold “AI” at 21 pt with 演示夏行楷 / Slide Xiaxing “天梯” at 25 pt. The four glyphs share a baseline and a 2.5-point gap measured between their actual ink edges, independent of font side bearings. Apple renders the CoreText outlines in a shared accessible SwiftUI view; WPF positions native text glyphs by their measured geometry. English lettering retains its existing font. The renamed 4,888-byte subset and complete upstream OFL license are bundled offline on all platforms. Shared visual fixtures now include long-version Chinese/English headers at 600/1100/1440 points.

Ignored `work/brand-xiaxing/{before,after}/macos` retain 90 original native AppKit/SwiftUI frames per phase: 15 cases, both themes and shown/refreshed/settled checkpoints. All 60 phase/case/theme groups have identical checkpoint pixels. `review.html` links unscaled originals; `stability.json` records equality. Fixture SHA-256: `2f6e88784b369304629e8b6c999c511b8fb2a2b6479b6b61f524a1cdf52c8abf`. Actual environment: macOS 27.0.1 (26A434), 2× backing scale, baseline `9b3e015` and local updated source. Reviewed native originals show equal gaps, readable title/version text, intact controls and no title clipping across Simplified/Traditional Chinese and 600/900/1100/1440-point viewports. The more compact Chinese title reduces the narrow header's line height; existing table-name truncation remains. English header pixels are unchanged; unrelated quota/row regions differ in four English captures.

Validation: 107 script checks, 283 shared Swift tests plus the UI/updater suites, and 39 Windows harness cases pass; syntax validation, signed Mac packaging and WPF cross-compilation pass. The capture wrapper now copies the bundled font resources into its native test app, fixing the missing-resource crash.

[Windows capture run 38211163782](https://github.com/cloydlau/ai-benchgauge/actions/runs/38211163782) produced 810 real WPF client-area frames at revision `738ede4153394ccc22d233cfe687467517f5b84a`, retained in its `native-visual-windows` artifact and ignored `work/brand-xiaxing/full-windows`. Actual OS: Windows Server 2022 (10.0.20348), DPI scale 1 (100%); fixture SHA-256 `064b15e3636106698582191562d366234f584f567afb15a9cd688f949156cbcc`. All title cases are stable across checkpoints. Reviewed native Chinese title frames at 600/900/1100/1440 show upright AI, equal gaps and intact version alignment in both themes. Earlier native frames from baseline `9b3e015` provide the Windows before reference at 900/1100 points. The capture harness now shows the account dialog's owner before assigning it, fixing an existing WPF ownership exception. The xAI starting/waiting dialogs animate across checkpoints; capture success is not blanket UI approval. Windows 10/11 and other real DPI scales remain unverified.

[iOS run 38210425783](https://github.com/cloydlau/ai-benchgauge/actions/runs/38210425783) built both Release SDKs successfully at title revision `5f523fe72724708d89a2e5534a4f14066d9c2b3f`; the complete log is in `ios-sdk-build-log` and ignored `work/brand-xiaxing/current-ios-sdk`. Simulator suites remain failing: iPad's country-filter assertion and iPhone's photo-save feedback timeout. This host has no full Xcode and iPhone automatic deployment is not enabled, so no local device update or iOS visual sign-off is claimed.

The Mac CI compiler also rejected two inherited weak-reference captures in the task monitor; nested tasks now explicitly recapture the weak actor reference, preserving existing behavior and compiling on the runner's Swift version. Complete local tests pass. [Follow-up desktop run 38212361784](https://github.com/cloydlau/ai-benchgauge/actions/runs/38212361784), at revision `d532213de01a0937dc63cdf0d53c6089efa8b000`, also completed all 810 Windows frames (Windows Server 2022, 100% DPI) in its `native-visual-windows` artifact. They are retained locally in `work/brand-xiaxing/paired/windows`. The full Mac CI capture did not produce a completed comparison during this verification; the source-matched `native-visual-comparison` artifact remains missing. Local native Mac before/after evidence and the reviewed Windows title frames provide the available visual coverage. Full repository CI still lacks `CALMMIT_REPOSITORY` / `CALMMIT_SHA` configuration. No protected release approval is claimed.

## Chinese title calligraphy (2026-10-12)

Only the Chinese brand characters **天梯** now use Long Cang calligraphy at 25 points; Latin branding retains Snell Roundhand (Mac/iOS) or Segoe Script (Windows) at 21 points. Actual mixed-font ink bounds align the desktop version label. A renamed 4,080-byte SIL OFL font subset is bundled offline on all platforms, with license notices.

Ignored `work/brand-calligraphy/{before,after}/macos` retain 36 original native AppKit/SwiftUI frames per phase, covering Simplified Chinese, Traditional Chinese and English, both themes, 600/900 × 600-point viewports, and shown/refreshed/settled checkpoints. All 24 phase/case/theme groups are stable. Reviewed originals show readable calligraphy, intact version spacing and no header clipping; English keeps its existing lettering. `review.html` links original frames and `review.json` records stability. Fixture SHA-256: `70783aed3645fc4016ceb694d48e5d44647c1c43fcbeeaa3f073ffc6ea01f027`. Actual environment: macOS 27.0.1 (26A434), 1× backing scale, local uncommitted font changes based on `cb18e5b`. Before uses the saved name-localization executable; after uses the rebuilt font-enabled executable.

Validation: the complete CI check passes, including 107 script checks, 283 Swift tests and 39 Windows harness cases, signed Mac packaging and the iOS device SDK build. The current update is installed on the local iPhone. WPF cross-compilation succeeds with zero warnings/errors. Current-change native Windows captures and a source-matched CI/native-visual-comparison artifact are unavailable on this Mac host; no Windows native visual sign-off or protected release approval is claimed.

## AI 天梯 / AI BenchGauge name localization (2026-10-11)

The selected app language now controls the Mac/Windows/iOS header brand: Simplified and Traditional Chinese use **AI 天梯**, English uses **AI BenchGauge**. Mac window titles and status help, Windows tray labels, and packaged Apple main-bundle display names use the same naming policy. Apple home-screen/Dock naming follows the OS per-app language; the in-app selector controls the interface. Stable internal IDs and user-data paths are retained.

Ignored `work/brand-localization/{before,after}/macos` retain 36 original native AppKit/SwiftUI frames per phase, covering three languages, both themes, and 600/900 × 600-point viewports. All 24 phase/case/theme groups are stable across shown/refreshed/settled frames. Original images show readable localized headers and intact title/version spacing; existing narrow leaderboard-name truncation remains. `review.html` links original frames and `review.json` records stability. Fixture SHA-256: `70783aed3645fc4016ceb694d48e5d44647c1c43fcbeeaa3f073ffc6ea01f027`. Actual environment: macOS 27.0.1 (26A434), 1× backing scale, local uncommitted source based on `1d813915`. Before uses the saved pre-brand-change debug executable; after uses the freshly rebuilt executable.

Validation: 107 script checks, 283 Swift tests and 39 Windows harness cases pass. The Mac bundle is built and signed; the iOS device SDK build passes and the update is installed on the local iPhone. Runtime Foundation probes using the actual packaged Mac and iOS Info.plist/localized resources resolve English/Japanese to AI BenchGauge and Simplified/Traditional Chinese to AI 天梯. The local Mac application is restarted. Windows WPF cross-compilation succeeds with zero warnings/errors. Current-change native Windows captures and a source-matched CI/native-visual-comparison artifact are unavailable on this Mac host; no Windows native visual sign-off or protected release approval is claimed. Store metadata drafts and the mobile feature distinction are recorded in `docs/releasing.md`.

## OpenAI entitlement date retention (2026-10-11)

OpenAI usage refreshes independently of the ChatGPT account check. A timeout, rejected HTTP response, malformed body or oversized check response previously replaced a dated card with usage only. Both direct-token and app-managed quota paths now persist API entitlement dates by account ID and reuse only future dates on temporary check failures, including after an application restart. Fresh usage keeps its current percentages; help identifies the cached date. A successful account check replaces the date or invalidates it if no matching entitlement exists. Usage resets and billing renewal dates never seed the cache; cancellation still propagates.

A live Foundation request using the local account returned an entitlement boundary of `2026-10-16T13:40:13Z`. The shared engine then projected `OpenAI · 7d 92% · 至10月16日` with fresh usage. Python's separate HTTP stack received an HTML 403; that result alone does not establish the native application's failing status. The original loss is reproducible with a successful usage response followed by a rejected/timeout account check.

`Tests/fixtures/openai-plan-expiry.json` covers fresh, cached and unavailable dates at 600/900 × 600 points, three languages and both themes. Ignored `work/openai-expiry/before/macos` and `after/macos` each retain 108 original native AppKit/SwiftUI shown/refreshed/settled frames; all 36 checkpoint groups per phase are pixel-stable. `review.html` links originals and `review.json` records fixture hash, source and environment. Fixture SHA-256: `bc0c1675ad6d34420c86af0873a477f02ac721ce3a14211602738c66710ec40c`. Actual environment: macOS 27.0.1 (26A434), 1× backing scale, local uncommitted source based on `e7d6154`; the saved before binary predates the current fix. Reviewed quota bands retain readable dates, percentages and add-model controls in every language/theme/width. Existing leaderboard-name truncation at narrow widths remains. Layout code is unchanged; these fixtures verify presentation of the resolved data, while transport regressions verify the actual failure transition.

Validation: all 102 script tests, 283 Swift tests and 39 Windows harness cases pass on the final source. Syntax validation and signed local Mac packaging pass.

Current-change Windows WPF captures and source-matched CI/native-visual-comparison artifacts are unavailable on this local macOS host. No Windows native visual sign-off or protected release approval is claimed. Live on-screen inspection through CUA also timed out; the engine projection and native synthetic fixtures provide the available verification.

## Querying quotas sort last (2026-10-10)

Pending quota cards now form a final stable group after all resolved/error cards, including depleted balances. Pending cards retain their stored relative order regardless of provider or current selection; completed queries immediately rejoin the existing billing/expiry groups. The shared sorter serves both Mac cards and Windows engine projections. Query failures are not pending queries and keep their existing placement.

`Tests/fixtures/quota-pending-last.json` covers current OpenAI and metered DeepSeek pending cards alongside healthy/exhausted plans, funded/zero balances, a missing plan and a failed query, at 600/900 × 820 points in all three languages and both themes. Ignored `work/quota-pending-last/before/macos` and `after/macos` preserve 36 original native AppKit/SwiftUI captures each, with shown/refreshed/settled checkpoints. `review.html` links every original side by side; `review.json` records stability and environment. Fixture SHA-256: `e7c24202348b4b53c3fca56795b3dcc82367f1e183aa91c25c582e03cb4fe3a2`. Actual environment: macOS 27.0.1 (26A434), 2× backing scale; saved pre-change native binary and after-change local source are based on `c4e2b7d`. All twelve case/theme groups in each phase have identical checkpoint pixels. Reviewed originals show pending chips after resolved cards, retained current-provider outline, readable quota labels and clean wrapping/add-model placement. Existing narrow leaderboard-name truncation is unchanged.

Regression tests cover every provider/current-selection combination against resolved groups, mixed and all-pending stable order, and successful/failed query transitions. All 102 script tests, 268 Swift tests and the 39 Windows update harness cases pass; syntax checks pass. Current-change Windows WPF captures and source-matched CI/native-visual-comparison artifacts are unavailable. No Windows visual sign-off or protected release approval is claimed.

## Session-backed Codex model metadata (2026-10-10)

Model resolution now reads only model/provider metadata from the most recently user-interacted local desktop chat in `state_5.sqlite`, excluding archived chats, CLI/extension sessions and subagents. User recency takes precedence over background update times. This is not foreground-tab detection. Missing/locked/unsupported stores fall back to the global default. macOS reconciles the label every two seconds; credentials and quota query sources remain separate.

Presentation is unchanged. `Tests/fixtures/codex-session-model.json` supplies an actual 6.1 model against a saved 5.6 account label, plus default fallback and unknown-route cases. Ignored `work/codex-session-model/macos` contains 30 original AppKit shown/refreshed/settled captures: three languages for 6.1, both themes, 420 × 22 points, macOS 27.0.1 (26A434), actual 2× backing scale, local uncommitted source based on `fb41b97`. Fixture SHA-256: `ed1090b0ec43fa6b2b00e18933f627ddd58f4d0441efb826707d2d732100bb6f`. All ten case/theme groups are pixel-stable across checkpoints; reviewed originals show readable labels/quota, intact spacing and no clipping. Unknown routing does not borrow OpenAI quota. These are post-change presentation captures, not a before/after style comparison or a screenshot of the user's live status bar; the live CUA read timed out.

The debug `--codex-model-status` path reads the same production resolver without credentials/network calls and returned `model=gpt-6.1-sol provider=openai` from the local store. Six isolated SQLite regression tests include model switching, recency, filters, provider routes, old schema and database locks; all 102 script tests, 266 Swift tests and the Windows update harness pass. Current-change Windows WPF captures and source-matched CI artifacts remain unavailable. No Windows visual sign-off or protected release approval is claimed.

## Nonzero menu-bar task counts (2026-10-08)

Mac menu-bar task digits now use semibold orange for running, green for completed unread, and red for errors when positive. Dynamic colors adapt to the native light/dark appearance. Zero and unavailable counts keep their default text appearance; zero errors and the entire task block when Codex is closed remain hidden. Each update rebuilds the attributed title so a count returning to zero loses its highlight.

`Tests/fixtures/codex-task-colors.json` covers zero, each positive count separately, all positive counts, unavailable counts and Codex closed in three languages and both appearances. Running/unread/error scenarios refresh to zero. Ignored `work/codex-task-colors/` preserves 126 original before and 126 after native status-button frames and `review.json`. Fixture SHA-256: `c4640d19e461d15dd4c382e453ee72bf8beb3d40fb59bb90f8334244355121b8`; actual macOS 27.0 (26A428), 1× backing scale, local-source captures. Content width is 420 points; native text buttons are 22 points high and icon-only buttons retain their intrinsic 31-point capture height. The baseline uses the saved pre-change native bundle; after uses the changed local source.

All 42 groups per phase have stable refreshed/settled frames; static states also match their shown frame. Native attributed-title checks verify that only positive digits receive explicit colors, and refreshed zero/unavailable/closed states have no stale highlights. Original-pixel inspection confirms readable digits, symbols and spacing in both appearances. Light differences remain within the centered label, whose width changes slightly with semibold digits. The baseline dark capture flattened white native text against a light background; the capture harness now resolves its dynamic background inside the button's appearance context. Thus dark before/after pixel differences include that capture correction and are not exclusively product changes.

Syntax checks, the full script/Swift/Windows harness test gates and signed local Mac packaging pass; the local application was restarted. Current-change Windows native captures and a source-matched CI artifact are unavailable; this Mac menu-bar change does not claim Windows visual verification or protected release approval.

## Add-model dismissal (2026-10-08)

The Mac add-model form disabled its Done button while an account request was pending. Done now remains available, Escape closes the sheet, and dismissal explicitly clears the parent presentation state. Closing or leaving the form cancels its owned verification task and clears the key. Cancelled or late results cannot update a reopened form; the account-saving path also checks cancellation after verification before persisting anything.

`Tests/fixtures/add-model-dismissal.json` covers idle and checking forms in English, simplified/traditional Chinese and both appearances at 480 × 560 points. Ignored `work/add-model-dismissal/` holds original native before/after Mac frames and the comparison report. The baseline uses the saved pre-fix native bundle; after uses the changed local source. Fixture SHA-256: `575986046fa059a6331447b74a20a08ca321f8a2de1f8c32b70b86175a21de04`; actual macOS 27.0 (26A428), 1× backing scale. The app-bundle suite also opens a real SwiftUI sheet and sends mouse and Escape events: all 24 dismissal checks pass across the 12 language/theme/state combinations. These interaction checks run in the native app bundle because the Command Line Tools testing helper has no Launch Services bundle proxy for SwiftUI sheets. The form lifecycle regressions remain in the Swift Testing suite.

Current-change Windows native captures and a source-matched CI artifact are unavailable; no Windows visual sign-off or protected release approval is claimed. This change fixes Mac presentation only.

The 36 before/after pairs use the same fixture; shown/refreshed/settled frames are stable in all 12 groups. Idle frames are unchanged, and checking-state differences stay within the Done button. Original-pixel review confirms the available close control and intact descriptions/spacing in all languages and themes. Full script, Swift and Windows harness tests, syntax checks and signed local Mac packaging pass.

## Four billing/status groups (2026-10-08)

The shared sorter now orders cards as plans, metered providers, explicitly unsubscribed plans, then metered providers with known nonpositive balances in every currency. A subscribed plan with exhausted usage stays in the first group. Missing/failed/pending amounts are not treated as zero, and a positive balance in any currency keeps the provider in the metered group. Plan expiry ordering and stable within-group ties remain; the current provider is not pinned. Mac and Windows share the sorter.

`Tests/fixtures/quota-billing-priority.json` interleaves the four groups, includes unknown metered usage and an exhausted subscribed plan, and reverses the input in a second scenario. Ignored `work/quota-billing-priority-review/` holds 72 real before and 72 after Mac frames, three languages, 600/900×820-point content, both themes and shown/refreshed/settled checkpoints. Both sets use fixture SHA-256 `460ad8248e78d6ccedd8a491b5a251f50e5650dffdc0bd4eaffcf1025c914d4e`, macOS 26.6.2 (25G83) and actual 2× scale; the baseline uses the previous shared sorter, and after uses the changed local source. `review.json` records matching capture metadata and all 24 groups stable per phase; `review.html` links original frames. Original-pixel quota-band review shows the requested order in all languages/themes, with readable labels and intact wrapping/add-model controls. Existing leaderboard-name truncation remains. Some raster differences extend into otherwise unchanged table/footer content, so pixel-identical surroundings are not claimed.

Validation passes: 97 script tests, 231 Swift tests and 39 Windows harness cases, syntax validation and signed Mac packaging. New regressions cover all 24 permutations of the four groups, both missing-plan providers, unknown amounts, mixed currencies, nonpositive balances and stable ties. The local app was restarted. Calmmit performed the code commit automatically; no manual push was issued. Current-change Windows native captures and source-matched CI artifacts are unavailable; no Windows visual sign-off or protected release approval is claimed.

## Qwen session and usage recovery (2026-10-08)

Qwen's card previously mapped every missing/unparseable usage result to `未连接`, even when the saved website connection flag was true. This checkout's local connection flag is true; the authenticated page itself could not be inspected because CUA returned `timeoutReached -10005`. The official site's current public analytics bundle supports both Chinese and English usage labels, while the old parser recognized only Chinese. The user confirmed that the authenticated window displays `套餐已失效`: the session exists, but the plan is expired. That fixed rendered reason maps to the requested `未订购` label; it does not ask the user to sign in again.

The shared source now supplies a separate unavailable status: an established website connection with no readable quota yields query failure, not a connection prompt. The parser accepts the current bilingual usage labels, keeps each period's percentage/reset together, and excludes credit-pack percentages from the plan. Only fixed rendered login, missing/expired-plan or usage-error messages determine those specific failures, including the exact expired-plan heading reported by the user. Mac keeps polling while the login window is open, applies its captured result directly to the card, and lets failure cards reopen the usage window. Windows forwards the persisted connection state to the engine and receives explicit capture/authentication outcomes rather than treating any capture response as successful login. Explicit invalid-login or no-plan results clear cached quotas, while transient reads retain the existing bounded cache behavior. Credentials are not exported or changed.

`Tests/fixtures/qwen-connection-state.json` adds healthy usage, never connected, connected query failure, login expiry and no-plan states in three languages, both themes and a 900×820-point viewport. Ignored `work/qwen-connection-review/after/macos/` contains 90 original native Mac frames; `review.html` links originals and `review.json` records metadata. Fixture SHA-256 `89d477886a7f6ff8c09c3f4749f247c8694efdd8c71fe72beaf34cb1d888ca87`; actual macOS 26.6.2 (25G83), actual 2× backing scale, local uncommitted source. All 30 shown/refreshed/settled groups are stable. Original-pixel quota bands show readable labels, logos and adjacent controls without clipping; existing table-name truncation remains. Affected-state native before captures, Windows native captures and a source-matched CI artifact are unavailable. No full cross-platform or live-account visual sign-off is claimed.

Validation: 97 script tests, 228 Swift tests and 39 Windows harness cases pass; syntax validation and a full WPF cross-build pass (zero warnings/errors). Regression cases cover established-connection failures, fixed login/plan messages, English/traditional usage, pool association, out-of-range percentages and credit-pack isolation. A live shared-engine refresh with the saved connection flag returns Qwen query failure rather than a connect prompt; that engine has no access to the native WebKit page. Signed local Mac packaging passes, and the application was restarted with the final build.

## GLM subscription copy (2026-10-08)

The specific missing-plan status is shortened to `未订购` / `未訂購` / `Not subscribed`. Help explains that the plan may have expired or not been purchased, and directs the user to check the GLM key and subscription account in CC Switch. Recovery routing is unchanged.

Ignored `work/glm-copy-review/` preserves 54 before and 54 after native Mac frames using the same GLM recovery fixture, three languages, both themes and shown/refreshed/settled checkpoints. The baseline reuses the previous GLM review's saved captures. Metadata records fixture SHA-256 `252812ddcc44cff5e6b32d6b618f11381c0852012c699d0e25d5f4533477fc0d`, macOS 26.6.2 (25G83), actual 2× scale and 900×820-point content. All 18 checkpoint groups are stable per phase. Original-pixel quota bands show the shortened labels and adjacent controls fitting without clipping. The saved baseline also has raster differences in some unchanged table/footer content; this comparison is not pixel-identical outside the edited label. Windows native captures and a source-matched CI artifact remain unavailable; no cross-platform visual sign-off is claimed.

Validation: 97 script tests, 224 Swift tests and 39 Windows harness cases pass with the final wording. Syntax validation passes.

## GLM query diagnosis and recovery (2026-10-08)

The actual CC Switch GLM key received HTTP 200 with `success=false`, business code 500, and the monitor API's fixed reason that this account has no Coding Plan. The app previously collapsed that into a generic query failure, and the card's default click opened the provider homepage. No credentials were changed during diagnosis.

The shared client now maps that specific reason to `未找到 Coding Plan` and fixed, localized help for checking the key/subscription account in CC Switch. A configuration issue opens CC Switch; a transient GLM query/network failure rereads the provider configuration and retries only that provider. The Mac card shows pending status during retry. Mac and Windows use the same recovery decision. Successful GLM cards retain their existing website action. Unknown upstream messages remain redacted generic failures, and empty successful quota payloads cannot masquerade as valid usage.

A live shared-engine refresh returns the explicit no-plan label, `glmConfiguration`, and no homepage fallback. A following immediate targeted retry is accepted despite the ordinary quota cadence, and other providers' displayed quota runs remain unchanged. This verifies query/projection routing; native CC Switch activation was not separately observed through CUA. The account/plan mismatch still requires the user to check the saved GLM key and its subscribed account; the app cannot create a missing subscription.

`Tests/fixtures/glm-recovery-state.json` supplies three states (no plan, retryable failure and healthy usage), all three languages, and a 900×820-point viewport. Ignored `work/glm-recovery-review/before/` and `after/` preserve 54 original native AppKit/SwiftUI frames each, both themes, shown/refreshed/settled. Fixture SHA-256 `252812ddcc44cff5e6b32d6b618f11381c0852012c699d0e25d5f4533477fc0d`; actual macOS 26.6.2 (25G83), actual 2× scale, local uncommitted source. `review.html` links all originals; `review.json` records stability and pixel bounds. All 18 checkpoint groups are stable per phase. Every difference is confined to the no-plan quota band's label; healthy/retry appearance and all table/footer pixels match. Original-pixel quota-band inspection sheets supplement full-frame review: the no-plan labels and add-model controls fit in all languages/themes without clipping. Existing leaderboard model-name truncation remains.

Validation passes: 97 script tests, 224 Swift tests, 39 Windows harness cases, syntax validation, signed Mac packaging and a full WPF cross-build (zero warnings/errors). The local application was restarted with the updated build. Current-change Windows native before/after captures and source-matched CI/native-visual-comparison artifacts are missing; no Windows visual sign-off, broader DPI coverage or protected release approval is claimed.

## Login-expiry wording (2026-10-08)

The shared expired-login state is now `登录失效`, with `登錄失效` in traditional Chinese and `Login expired` in English. The menu-bar label, quota cards, help assertions, shared WPF visual fixture and current README/architecture descriptions use the same state. The login actions and model retention behavior are unchanged. `work/login-expiry-review/before/` preserves the previous native Mac fixture frames; `after/` captures the new wording with the same `Tests/fixtures/menubar-state.json`. The original menu-bar capture limitations above remain: missing Windows native/CI comparison coverage, intrinsic button heights rather than matched-height viewports, and dark-background contrast not certified. This wording change is not full visual sign-off or protected release approval.

The full checks pass (97 script tests, 222 Swift tests and 39 Windows harness cases), as do syntax validation and signed Mac packaging. The freshly built local app was restarted.

## Current model and quota recovery (2026-10-08)

CC Switch held an expired OpenAI token while the same Codex account had a renewed one. Account deduplication discarded the renewed login. The shared merger now retains the selected CC Switch provider ID/model metadata and uses an unexpired Codex token only when its exact account ID matches and its expiry is newer. It does not write either client's credentials; app-managed login precedence remains intact. The menu bar retains the current model with localized checking, sign-in or failure state when no amount is available. A live shared-engine query after the local packaged app was restarted returned `gpt-6.1-sol · 7d 96%`.

`Tests/fixtures/menubar-state.json` covers healthy quota, reauthorization, pending query, failed query, missing configuration, long model names and no current provider in all three languages. Ignored `work/menubar-review/before/` and `after/` preserve 126 original native AppKit status-button frames each. `review.html` links each shown/refreshed/settled original; `review.json` records the environment and fixture hash. Both sets use fixture SHA-256 `71ae2a223d89f5e7c964e296a973003014c7dc5b4420087716b50bd66f90dc45`, actual macOS 26.6.2 (25G83), actual 2× backing scale, and local source with the capture harness. All 42 checkpoint groups are stable in each set. Light-theme originals show model labels, localized states, quota and deliberate long-name truncation without clipping; healthy and no-current states retain their labels/icon behavior.

These local captures have a fixed 420-point width but retain intrinsic native heights (22 points for text, 31 for icon-only); they are not a fully matched-height viewport comparison. The dark glyph captures flatten onto the capture helper's light background, so they do not verify actual dark menu-bar background contrast. Supplemental contact sheets preserve original pixels and pad shorter images without resizing. The live CUA channel timed out when inspecting the restarted app, so the actual on-screen status label was not independently observed; the live engine projection, packaged build and process restart were verified. Current-change Windows WPF before/after captures, source-matched CI/native-visual-comparison artifacts and complete dark-theme visual review remain missing. No full visual sign-off or release approval is claimed.

Validation: 97 script tests, 222 Swift tests and the Windows test harness (13 signature/configuration, 17 update presentation, 9 signed-update cases) pass; syntax validation and signed local Mac packaging pass. Regression cases cover renewed same-account credentials, stale/expired local tokens, different/missing account IDs and unavailable-quota model retention.

## Pay-as-you-go quota ordering local review (2026-10-01)

`work/quota-order-review/review.html` and `review.json` preserve 72 original native Mac frames before and 72 after, from the same saved 12-case regression fixture. The input deliberately puts DeepSeek ahead of xAI. Cases cover xAI with no subscription date, query failure, pending query and expired login, in three languages, both themes and 600/900 content widths. Actual environment is macOS 27.0 (26A428), backing scale 1×, local uncommitted source; shown/refreshed/settled are identical within each case/theme.

Before, undated xAI follows DeepSeek; after, xAI precedes it in all four states while the dated Kimi plan remains first. All 24 native case/theme quota bands were reviewed for label readability, alignment, controls and clipping. Full-frame pixel differences are confined to the quota band; existing narrow model-title truncation remains unchanged. Supplemental inspection sheets contain only unscaled crops from those originals; the comparison report always links the original full frames. Shared CI layout fixtures include these states in their expected projected order; those WPF fixtures do not exercise the engine's sorting. The local Mac regression fixture exercises the actual shared sorter.

The full Swift run passes 213 core tests, including 384 plan/metered status and input-order combinations, plus stable expiry/tie ordering. Mac and Windows builds pass. **Current-change Windows native before/after captures, a source-matched CI run and its `native-visual-comparison` artifact remain missing.** No Windows 10/11 or additional real DPI coverage is claimed. This local review is not protected human release approval.

## xAI subscription connection local review (2026-10-01)

`work/xai-app-query-review/review.html` and `review.json` preserve before/after native Mac captures with the same 18-case fixture: weekly-reset-only, missing subscription date, API date, cached API date, and the new connection dialog, in three languages and both themes. Each set has 108 original shown/refreshed/settled frames. Actual environment is macOS 27.0 (26A428), backing scale 1×, local uncommitted source. The saved baseline has no connection dialog; its corresponding cases show the former quota panel. The offline dialog fixture deliberately leaves the external website area blank.

Native review found and corrected the dialog's dark background and stretched retry button. Header, instructions and status fit all three languages; the query button remains compact. Verification, account mismatch and paused-query messages have dedicated fixture scenarios. All checkpoints within each case/theme are stable. Existing narrow table-title truncation remains. Concurrent localized-title and footer changes are recorded as shared-workspace differences rather than attributed to this feature. The production component was also opened against the actual official website: it reached the Cloudflare verification page, so real account-date retrieval is still unverified.

Mac and Windows builds and the account-identity rejection tests pass. **Current-change Windows native before/after captures, a source-matched CI run and its `native-visual-comparison` artifact are missing.** Windows 10/11 and additional real DPI settings are not certified. This local report does not replace the protected human release review.

Run `.github/workflows/visual-parity.yml` to capture the real WPF window on a Windows desktop and the real AppKit / SwiftUI view on macOS. The workflow uploads both sets of PNGs, capture metadata, and a standalone `native-visual-comparison` HTML report. The main Checks workflow calls it on every PR and push to main, without path filters that could skip a shared-core or resource change. The release workflow calls the same workflow for the tagged revision with human review required.

The report supports side-by-side images, opacity overlays and a pixel difference view. Select the case, checkpoint and appearance; both native platforms have light/dark captures. These are native screenshots, not a browser imitation of the Windows interface. Compare layout and missing features; native typography and anti-aliasing do not require pixel equality.

## Required development and release procedure

1. For a desktop interface change, capture before and after the change with the same fixture. Add a scenario if the affected state is not covered. Keep both artifacts or local captures for review.
2. Open the CI run's **comparison** job summary and download `native-visual-comparison`. Open `comparison.html` offline; review shown/refreshed/settled, both Mac themes, languages and widths for the affected states. Use side-by-side, overlay and difference views to inspect alignment, clipping, spacing and missing features. Different native font rasterization is not automatically a bug.
3. Link the run/report and record intentional differences and unresolved problems in the PR template. `AGENTS.md` makes this part of subsequent UI development. A green capture job verifies the capture set, not aesthetic acceptance.
4. Every release tag captures its own revision again. After the report is ready, `review-policy` verifies that the repository environment **native-visual-review** exists and has a required human reviewer. A missing environment, empty reviewer list or API failure blocks the release; it cannot silently become an unprotected environment.
5. The **review** job waits for the environment's reviewer. Review the report linked from the waiting job (or comparison job summary), record review notes in the GitHub approval comment, then approve or reject it. The `publish` job needs the entire visual workflow to succeed. Capture failure, rejection or cancellation prevents publishing. Agents must never approve or bypass the environment on behalf of a human.

The environment is configured in **Settings → Environments → native-visual-review** with the repository owner as required reviewer. Preserve required reviewers when editing its settings; an explicit administrator bypass is outside this procedure and must not be used to skip visual review. GitHub controls this waiting job through its [environment approval rules](https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments). CI only reads environment policy; it cannot create reviewers or approve its own run.

To test the gate without publishing a release, run **Native visual comparison** manually with `require_review=true`. It should capture both platforms, verify policy and wait for human review; cancel this rehearsal after confirming that behavior. With the default `false`, manual runs only generate the report. CI artifacts are retained for 30 days; save reviewed release evidence before that expires when needed.

## Current coverage

`Tests/fixtures/visual-state.json` supplies public, synthetic data to both interfaces. It covers 20 rows, long English and Chinese names, three languages, 600, 900 and 1100 logical-pixel content widths, normal quotas, six quotas, missing CC Switch, installed-empty CC Switch, refresh errors with cached rows, and window mode. The add-model action has additional six-quota cases in English and traditional Chinese, and a narrow wrapping case. Each case captures three checkpoints: shown, refreshed and settled. Both Mac and Windows capture native light and dark appearances. Windows follows the app appearance setting in normal use.

The report checks the fixture SHA-256 (with CRLF normalized to LF), both client dimensions, actual PNG dimensions, both Mac themes and every frame. In CI both captures must record the exact `GITHUB_SHA`; an older capture cannot be reused as this revision. It refuses mismatched fixtures, incomplete/duplicate metadata or incomplete capture sets. Local reports without a verified source revision are explicitly marked as such and are not release evidence. Capture metadata records OS, real DPI/backing scale, timezone and the capture method.

The Windows runner is **Windows Server 2022 at its reported DPI**, usually 100%. This does not certify Windows 10/11, 125%/150% scaling, multiple monitors or every language/font installation. Do not simulate DPI by scaling a PNG and describe it as a native capture. Obtain those screenshots on the relevant desktop with the same fixture. The three checkpoints do not constitute a continuous animation recording. Company grouping, other categories, opened menus and update/auth dialogs remain to be added.

## Local capture

On a Mac with an active desktop:

```sh
zsh Scripts/capture-macos-visual.sh
```

This builds a separate debug application in `work/visual-parity/NativeVisual.app`. Its debug-only `--visual-test` path skips normal startup, account refreshes, timers and updater startup. It briefly shows fixture windows and captures their native content without the normal sharing redaction. It does not replace the installed app.

On Windows with .NET 10 and an unlocked desktop:

```powershell
dotnet build apps/windows/BenchGauge/BenchGauge.csproj -c Release -o work/visual-app
work/visual-app/AI-BenchGauge.exe --visual-test
```

The Windows visual path supplies fixture state directly, does not start the engine or save user preferences, and copies the visible client area from the desktop. A missing/blank desktop or clipped window fails the run. Only on an isolated CI runner (`CI=true`) does it temporarily select a sufficiently large supported display mode; it restores that mode afterward. Local Windows users must provide a large enough desktop themselves.

Place the PNGs and metadata under `work/visual-parity/macos/` and `work/visual-parity/windows/`, then run:

```sh
node Scripts/visual-report.mjs
```

Open `work/visual-parity/comparison.html`. The HTML embeds all captured images and works offline. Generated media stays under ignored `work/`; no screenshots are committed automatically.

## Kimi quota-source correction (2026-10-01)

The shared quota reader now recognizes OpenCode connection settings, merges identical Kimi keys across tools, reuses local login for a keyless entry, and treats automatic CLI OAuth as a fallback when a configured key exists. Distinct keys retain separate source labels. The fixture adds configured, pending, reauthentication, distinct-source and duplicate-reproduction cases in all three languages, at 600/900 point content widths and both Mac themes. `kimiDuplicateBefore` reproduces the reported states using synthetic data; it is not evidence from a historical pre-fix build. This correction does not change styles.

Mac captures and review metadata are under ignored `work/kimi-visual-review/`. Native review of representative original frames found readable state/source labels without quota clipping, including the narrow viewport; existing narrow leaderboard-name truncation remains. The captures use macOS 27.0 (26A428), actual backing scale 1×, and local uncommitted source. Swift regression tests, Windows shared tests and WPF cross-compilation pass. Current-revision Windows native screenshots, a CI run and its `native-visual-comparison` artifact are still missing; this is not complete cross-platform visual verification or release approval.

## xAI reset-date review (2026-10-01)

The initial correction showed a future usage reset as **重置 / Resets** when the subscription date was unavailable. The subsequent copy correction uses the same neutral **至 / to** date format as every other quota card. A reported plan/monthly boundary still takes priority, and missing or past weekly reset dates are omitted. The fixture covers weekly reset, known subscription date and no date in all three languages, at 600/900 content widths.

Ignored `work/xai-date-review/` contains the same saved fixture for real before/after builds, `review.html`, source hashes and capture metadata in `review.json`. Each build has 54 original Mac frames on macOS 27.0 (26A428), actual 1× backing scale, from local uncommitted source. Shown/refreshed/settled frames match within all case/theme groups. Review found readable dates and controls without quota clipping in both themes; narrow leaderboard-name truncation remains. Swift tests, Windows shared tests and WPF cross-compilation pass. **Current-change Windows native captures, a source-matched CI run and its `native-visual-comparison` artifact remain missing.** This is local Mac development evidence, not complete cross-platform verification or release review.

The xAI date-copy follow-up has real before/after Mac evidence under ignored `work/xai-date-format-review/`, recorded in `review.json` with source hashes, the identical saved fixture, OS and actual scale. Both builds have 54 frames covering the same three states, languages, viewports and themes; shown/refreshed/settled frames match within every case/theme. Review confirms the corrected **至 / to** format without quota clipping. Swift tests and WPF cross-compilation pass. Current-change Windows native captures, a source-matched CI run and its `native-visual-comparison` artifact remain missing; this does not constitute cross-platform verification or release review.

## xAI subscription-date source correction (2026-10-01)

The weekly reset fallback above was incorrect for a subscription-date card and has been removed. A weekly-only response now omits the plan date. This earlier iteration accepted a user-confirmed date when the subscription endpoint was unavailable. **That workaround has been withdrawn:** the user requires the date to be read automatically. The old manually entered record was removed, and legacy manual records are ignored by the reader. Only dates obtained from a successful subscription query may supply the current date or its account-scoped cache fallback. The local account's October 24 date has not yet been fetched; the subscription endpoint returns a Cloudflare challenge (403).

`work/xai-subscription-review/` records 72 before and 72 after native Mac frames with the same saved 12-case fixture, three languages, both themes and 600/900 content viewports. The before run reuses the saved native debug binary from the preceding copy-change capture, with that source's hashes and its binary hash recorded; after uses the tested current debug binary. `review.json` records macOS 27.0 (26A428), actual 1× scale, fixture/source hashes and identical shown/refreshed/settled frames per case/theme. Review confirms the confirmed/API date labels are readable without quota clipping and weekly-only/no-date states do not fabricate a plan boundary. Existing narrow leaderboard truncation remains. Swift tests and WPF cross-compilation pass. **Current-change Windows native captures, a source-matched CI run and its `native-visual-comparison` artifact remain missing.** This is not cross-platform verification or release approval.

The automatic-only correction is recorded in ignored `work/xai-auto-date-review/review.json` and `review.html`: 72 original frames per before/after build, an identical updated 12-case fixture, three languages, both themes, 600/900 × 820 content viewports, macOS 27.0 (26A428), actual 1× scale and source/binary hashes. The baseline uses the saved add-model-scope native binary. Shown/refreshed/settled and before/after pixels match for identical synthetic API, cached API and missing-date inputs; the correction changes accepted data sources rather than card geometry. Native review confirms readable quotas/dates and controls; existing narrow leaderboard-name truncation remains. Regression tests reject legacy manual records, preserve usage after subscription failures and follow a different date returned by the provider. The real-account subscription request remains blocked by Cloudflare; no real October 24 reading is claimed. **Windows native captures, a source-matched CI run and its `native-visual-comparison` artifact remain missing.** WPF cross-compilation passes but does not verify Windows visuals or approve a release.

## Initial findings (2026-10-01)

The initial Windows baseline differed structurally from Mac: independent Windows board scroll areas and duplicated ranks, 25-DIP versus 32-point rows, missing company tint bars/medals/country columns, generic dropdowns and buttons, larger quota padding without provider logos, a left-aligned empty-state link instead of a centred placeholder, large unused vertical space, and no dark theme. These differences are visible in captures and supported by the view code. Capture and review the affected states before changing those styles; then rerun the same cases for a before/after comparison.

## Add-model action review (2026-10-01)

The action is now the last item in the quota flow, labelled **+ Add model / + 添加模型**, instead of a separate Mac header row or the first Windows quota item. The Mac empty-state prompt keeps the action alongside it. Both platforms retain their existing native controls and typography.

Local before/after captures are under `work/visual-parity/add-model-before/macos/` and `work/visual-parity/add-model-after/macos/`. `work/visual-parity/add-model-review.html` shows the original PNGs side by side; `add-model-review.json` records the fixture hash, viewport, OS and scale. Each set has 84 frames: 14 cases, two themes and three checkpoints, on macOS 27.0 (26A428), backing scale 1×. Shown, refreshed and settled pixels are identical within every case/theme. Native review found the trailing button aligned with the quota chips, readable text and plus icons in all supported languages/themes, natural wrapping at 600 points, and no action clipping in empty/error states. Existing long leaderboard names still truncate in narrow columns.

Windows WPF cross-compilation and the visual-process checks pass. **Current-revision Windows native before/after captures, a CI run and its `native-visual-comparison` artifact are still missing.** This local Mac report is explicitly uncommitted development evidence, not a complete cross-platform visual verification or release approval. Existing older Windows artifacts must not be reused for the changed fixture. Windows retains its fixed light theme and no CC Switch open guide in the installed-empty fixture; those existing differences remain unresolved. The native Windows layout is also being revised in the shared workspace, so its final geometry requires a fresh capture.

## Add-model dialog display name review (2026-10-01)

The earlier copy revision renamed the optional field to **Display name / 显示名称 / 顯示名稱**, with Personal / Work examples and a persistent explanation that it distinguishes model accounts and defaults to the provider name when blank. The dialog title matches the Add model action. Mac shows examples as a native text-field placeholder; Windows shows them in the persistent helper text and tooltip. Windows uses its native window title, while Mac has an inline sheet heading.

The shared fixture includes the real add-model form in English, simplified Chinese and traditional Chinese at a 520 × 580 content viewport, with empty synthetic credentials and no stored personal accounts. Both capture paths use the actual production form. Optional `BENCHGAUGE_VISUAL_ROOT` and `BENCHGAUGE_VISUAL_FIXTURE` environment variables allow independent capture directories and a saved affected-case fixture; defaults retain the full CI fixture and output paths.

Local Mac evidence is in `work/visual-parity/display-name-before/` and `display-name-after/`, with `display-name-review.html` and `display-name-review.json`. Each set contains 18 original native frames (three languages, two themes, shown/refreshed/settled), using the same saved fixture. Captures record macOS 27.0 (26A428), actual 1× backing scale and an uncommitted local source. All three checkpoints are identical within each language/theme. Review found the label, example and helper readable without clipping, with consistent field alignment, native controls and room for the added explanation. This fixture covers the empty add form; populated-account and validation-error dialog states remain outside this change's visual coverage.

Windows WPF builds with zero warnings/errors and the eight visual-process checks pass. **Windows native before/after captures for this dialog, a current-revision CI run and its `native-visual-comparison` artifact are still missing.** Windows 10/11 and other actual DPI settings have not been reproduced. The local Mac report does not constitute cross-platform verification or release review.

## Windows panel style review (2026-10-01)

The WPF renderer now shares ranks and scrolling between sources, uses 32-DIP paired rows, matches the Mac brand palette and deterministic model shade, adds medals/country badges and compact quota logos, centres the segmented controls and CC Switch guide, anchors the footer, and supports the system app appearance. Default height fits the available desktop; the additional `short-zh-900` fixture captures a 900 × 600 content viewport.

PR #1 records native before/after CI reports, source revisions, actual OS/DPI and visual findings. That branch uses its own saved 11-case fixture; the 600-width and add-model/dialog scenarios being developed in this working tree require a separate source-matched capture. Fonts, vector flags/medals, name truncation, some column padding, attribution and freshness details remain platform differences. Windows 10/11 and actual 125%/150% scaling are not covered by the Server 2022 / 100% captures. The generated before/after/Mac report remains ignored under `work/visual-parity/style-after/`.

## Optional display name removal review (2026-10-01)

The optional display-name field and its explanation have been removed from both native add-model forms. New entries use the provider name automatically; users only select the provider and enter its key. Existing stored labels remain readable, without a storage migration.

Local Mac before/after evidence is under `work/visual-parity/remove-display-name-before/` and `remove-display-name-after/`, with `remove-display-name-review.html` and `remove-display-name-review.json`. Both sets use the same saved three-language dialog fixture and 520 × 580 content viewport, on macOS 27.0 (26A428), actual backing scale 1×, from uncommitted local source. All 36 native frames were captured; shown/refreshed/settled pixels match within each language/theme. Review of both themes and all three languages found the provider, key and action buttons aligned with no remaining name field, unexplained gap or clipped text. Populated-account and validation-error dialog states remain outside this field-removal capture. Mac retains its inline heading and placeholder; Windows retains a native window title and key label.

Mac builds and native captures succeed; Windows WPF builds with zero warnings/errors. **Current-change Windows native before/after captures, a source-matched CI run and its `native-visual-comparison` artifact remain missing.** This does not verify Windows 10/11 or additional actual DPI settings, and is not release review.

## Add-model coverage copy review (2026-10-01)

Both add-model forms now explain the inclusion priority (official providers in the four category Top 20 lists from both sources), supported official account query methods, separate product/plan/region quota pools, local login detection and retention of accounts after providers leave the rankings. The provider-specific description remains next to the selection.

Ignored `work/add-model-scope-review/` contains `review.html`, `review.json` and real before/after Mac captures from the same saved three-language fixture and 520 × 580 content viewport. All 36 frames use macOS 27.0 (26A428), actual 1× backing scale and uncommitted local source, with source hashes recorded. Shown/refreshed/settled frames match within each case/theme. Review found the explanatory text and controls readable without clipping in both themes. Mac retains an inline title and key placeholder; Windows retains a native title and key label. Populated-account and validation-error screenshots remain outside this empty-form coverage.

Mac builds, WPF cross-compilation and the eight visual-process checks pass. **Current-change Windows native captures, a source-matched CI run and its `native-visual-comparison` artifact remain missing.** The local Mac evidence is not complete cross-platform verification or release review.

## Windows text and icon polish review (2026-10-01)

The follow-up WPF polish centres the visible native glyph bounds at actual DPI, separates quota logos/text into a centred grid with equal-height chips, uses fixed vector camera/power/chevron icons, aligns footer text and spacing, restores the xAI quota logo, and confines narrow English country captions to their columns. The branch fixture now has 19 cases, including 600-width normal and six-quota states in all three languages. Other account/dialog fixture changes in this shared working tree remain separate.

Real before/after evidence uses the identical saved fixture SHA-256 `3179edf9fbf96098decc448564eb2bd52c532c499f94393c42cf04a70847f5da`. Before source `1f3d2e1914eac1f0ed6fb40035e12e32d402811b` is in [run 36815782711](https://github.com/cloydlau/ai-benchgauge/actions/runs/36815782711); after source `873883a267400812cb07ddc210363795640e4ff1` is in [run 36816474524](https://github.com/cloydlau/ai-benchgauge/actions/runs/36816474524) with its [native-visual-comparison artifact](https://github.com/cloydlau/ai-benchgauge/actions/runs/36816474524/artifacts/11141478190). Each revision contains 114 Windows and 114 Mac frames: 19 cases, two themes and three state checkpoints. Actual environments are Windows Server 2022 build 20348 / 100% DPI and macOS 15.7.9 build 24G830 / 1× backing scale. The original-pixel before/after/Mac report and evidence stay ignored under `work/visual-parity/polish-after/`.

Native review found centred model/quota content, consistent footer controls and readable quota wrapping without clipping across these captured widths, themes and languages. All 38 Windows case/theme groups are stable across shown/refreshed/settled; Mac refreshed/settled pairs are identical, with five initial-display groups changing as asynchronous logos resolve. Existing Mac first-English-case scroll overflow remains unresolved. Native fonts, flags/medals, truncation and narrow column allocation remain documented differences in [PR #1](https://github.com/cloydlau/ai-benchgauge/pull/1). [Full Checks](https://github.com/cloydlau/ai-benchgauge/actions/runs/36816479578), WPF cross-compilation and eight visual-process checks pass. Windows 10/11, actual 125%/150% DPI, opened menus, company grouping/other categories, installed-empty and account/update/auth dialogs remain outside this evidence. This is development review, not protected human release approval.

## Windows automatic width review (2026-10-01)

The Windows popover formerly used a fixed 900-DIP width. It now follows the Mac sizing policy: native model/company text metrics, logo/link padding, both name columns, an 850 minimum and a screen-work-area cap. The bridge supplies layout names across every cached category/grouping, preventing short-category width collapse. Explicitly resized window mode remains supported. Native WPF smoke checks the desktop cap, unnecessary truncation when the desktop allows full names, and stable cached-name sizing after switching to short rows.

Source-matched before `f3bd3d78f616476ea4fb8821ea606988bd937867` is in [run 36817599093](https://github.com/cloydlau/ai-benchgauge/actions/runs/36817599093). After `29c2e9b5ad7f098d791e1a12ca68e785931b5d20` is in [run 36817596529](https://github.com/cloydlau/ai-benchgauge/actions/runs/36817596529) and its [native-visual-comparison artifact](https://github.com/cloydlau/ai-benchgauge/actions/runs/36817596529/artifacts/11142037104). Both use fixture SHA-256 `6da62380bd3ca03bec56b15732dc6b8d5a3fb0d54fe177ea0ecae08e431432b0`: 23 cases, both themes, three checkpoints, 138 original Windows and 138 Mac PNGs per revision. Actual environments remain Server 2022 build 20348 / 100% DPI and macOS 15.7.9 build 24G830 / 1×. The new 1440-wide cases show every fixture model title fully readable, without clipping header/quotas/footer, across the supported languages and themes.

Ignored `work/visual-parity/width-after/before-after.html` preserves every same-viewport control pair. A separately labelled 900 → 1440 native viewport example demonstrates the extra name space; 1440 is not the production default. Default adaptive-width behavior is checked separately by native smoke. All 46 Windows case/theme groups are stable; Mac refreshed/settled pairs are identical and 22 initial groups change as logos resolve. Native fonts, flags/medals and truncation at constrained widths remain different; prior first-English-900 Mac overflow remains unresolved. [Full Checks](https://github.com/cloydlau/ai-benchgauge/actions/runs/36817599692), local WPF/engine builds and eight visual-process checks pass. Windows 10/11, actual 125%/150% DPI and other previously listed states remain outside this coverage. [PR #1](https://github.com/cloydlau/ai-benchgauge/pull/1) records the limits and protected human release gate; no release approval is inferred from capture success.

## 智衡 localized-title review (2026-10-01)

Historical review; superseded by the English-only title restoration below.

The panel heading displays **智衡** in both simplified and traditional Chinese, and **AI BenchGauge** in English. Existing language selectors update the heading immediately. The actual Mac and Windows window titles also follow the selected language. Chinese uses each platform's native system Chinese font; English retains the existing script font.

Local before/after evidence is under `work/visual-parity/zhiheng-title-before/` and `zhiheng-title-after/`, with `zhiheng-title-review.html` and `zhiheng-title-review.json`. The same saved 18-case synthetic fixture covers three languages, 600/900/1100/1440 content widths, a short viewport, window mode, empty/installed-empty/error states and wrapped quotas. Each set contains 108 original native frames on macOS 27.0 (26A428), actual backing scale 1×, from local uncommitted source. All shown/refreshed/settled frames match within their case/theme. English title regions match before/after. Chinese title regions are identical across the captured languages, widths and states within each theme; native review confirms readable glyphs, aligned version text and no title clipping. Existing narrow table-name truncation and concurrent shared-workspace table edits are outside this title change.

Mac builds and native captures succeed. Windows WPF builds with zero warnings/errors. **Current-change Windows native before/after title captures, a source-matched CI run and its `native-visual-comparison` artifact are still missing.** Windows 10/11 and additional real DPI settings are not verified. This local report is not release review; the captures do not exercise a live click on the language selector or include title-bar pixels.

## Relative quota freshness review (2026-10-01)

Windows now receives successful quota-data timestamps and shows just now / minutes / hours / days ago in all three languages. Reading state, failed reads and cached fallback retain the prior successful time; cached Qwen preserves its actual capture time. Unknown data time remains pending. Board freshness uses the oldest visible board fetch rather than source publication time, matching Mac.

Before source `df4ff76a8bcd75a03d4b129ccdac31b403bcf758`: [run 36820104439](https://github.com/cloydlau/ai-benchgauge/actions/runs/36820104439), [native-visual-comparison artifact](https://github.com/cloydlau/ai-benchgauge/actions/runs/36820104439/artifacts/11142709598). After source `07c73f69f1230c3a6f983502be2c80faccbde2e0`: [run 36820775557](https://github.com/cloydlau/ai-benchgauge/actions/runs/36820775557), [native-visual-comparison artifact](https://github.com/cloydlau/ai-benchgauge/actions/runs/36820775557/artifacts/11143252322). Identical fixture SHA-256 `65dcf9688ee78342ff9d6c1f9d91ffc4a30884920fa7444780c3df480b34bf74`: 41 cases × two themes × shown/refreshed/settled = 246 Windows + 246 Mac original frames per revision. Windows Server 2022 build 20348, actual 100% DPI; macOS 15.7.9 build 24G830, actual 1×. Eighteen added cases cover now/minutes/hours/days/stale/unknown in English, simplified and traditional Chinese at matching 600/900/1440 × 820 viewports.

[Full Checks run 36820777862](https://github.com/cloydlau/ai-benchgauge/actions/runs/36820777862) passed Mac tests/packaging, Windows tests/runtime closure/native UI smoke, installer creation and install/uninstall, plus both native capture/report jobs. Original headers and narrow panels were reviewed for label fit and age semantics in both themes. All 82 Windows checkpoint groups are stable. All Mac refreshed/settled pairs match; 79 groups change from shown as asynchronous logo placeholders resolve. Every Windows frame and Mac refreshed/settled frame is unchanged below the header relative to before. Ignored `work/visual-parity/freshness-after/` records review evidence and the original-pixel report. Native font weights, flags, English Boards/Quotas versus Rankings/Quota wording and screen-constrained name truncation remain differences. Existing initial-English-900 Mac scroll overflow remains unresolved. Windows 10/11, actual 125%/150% and multiple monitors remain unverified; three checkpoints are not continuous video. Release publishing still requires a human to approve the protected `native-visual-review` environment; no release approval is claimed.

## 智衡 calligraphy-title review (2026-10-01)

Historical review; superseded by the English-only title restoration below.

Both Chinese headings now use the bundled **Ma Shan Zheng** brush-calligraphy face at 21 points/DIPs, replacing the system Chinese face. Mac registers the full font for the application process only; WPF embeds the identical font and uses its regular weight rather than synthesizing bold. The existing glyph-ink centering aligns the title with its version label. English retains its existing script face. The OS-drawn window title bars retain their native chrome typography.

The complete, unmodified font comes from upstream commit `6bfdbe288f5935c6e9072cdd6ab1aa102a006aab` with SHA-256 `b844c59bf20bf530e41c20d6ff12b383b23a2e553b9b68cc89f070869213155d`. Both 智 and 衡 have actual mapped glyphs. Its full copyright and SIL OFL 1.1 notice are bundled on both platforms and listed in the Mac notice sheet. `docs/third-party-notices.md` records its provenance. Font licensing does not establish trademark availability for the application name.

Local before/after evidence is under `work/visual-parity/calligraphy-title-before/` and `calligraphy-title-after/`, with `calligraphy-title-review.html` and `calligraphy-title-review.json`. Both use the same saved 21-case fixture (three languages, 600/900/1100/1440 widths, short/window/empty/error/wrapped-quota states and version-label fixtures). Each set has 126 original native frames, captured on macOS 27.0 (26A428), actual backing scale 1×, from uncommitted local source. Shown/refreshed/settled pixels match within all 84 case/theme/phase groups. The four Chinese title pixel groups cover both themes and narrow/wide header layouts; reviewed originals show readable brush strokes, version alignment and no title clipping. English title regions are unchanged. Existing narrow table truncation and concurrent table edits remain outside this font change.

Mac debug/release builds and signed app packaging succeed. Packaging checks confirm the exact font and full license in the app; WPF builds with zero warnings/errors, and its generated font resource contains the exact source bytes at the intended URI. Eight visual-process checks pass. The packaging check skips the full suite and uses these focused build/resource/capture checks. **Current-change Windows native before/after font screenshots, a source-matched CI run and its `native-visual-comparison` artifact remain missing.** Windows 10/11 and other actual DPI settings are not verified. This is not cross-platform visual sign-off or release approval.

## Title and version centre review (2026-10-01)

The WPF header draws the title and version with native FormattedText in equal 27-DIP slots, centred by visible glyph bounds at actual DPI. This avoids the difference between TextBlock and FormattedText baselines. Text keeps its existing family/weight/colour, exposes UI Automation names, and the version button retains its update handler and hit area. Mac replaces first-baseline layout with CoreText glyph-centre alignment guides.

Before source `6eabac1eecc051ff5fbd546cce6ab8444094d30b`: [run 36822088232](https://github.com/cloydlau/ai-benchgauge/actions/runs/36822088232), [native-visual-comparison artifact](https://github.com/cloydlau/ai-benchgauge/actions/runs/36822088232/artifacts/11143384310). After source `974f2c77d22c96c9d3a3a57928f5b473687f405a`: [run 36822636047](https://github.com/cloydlau/ai-benchgauge/actions/runs/36822636047), [native-visual-comparison artifact](https://github.com/cloydlau/ai-benchgauge/actions/runs/36822636047/artifacts/11143343807). Shared fixture SHA-256 `6fa2ead9e6f33e75239e522d322beae819ff3abd5e9b41c128573396ed99a0ae`: 44 cases × two themes × shown/refreshed/settled = 264 Windows + 264 Mac original frames per revision. Three added long-version/arrow cases use the actual production header in all supported languages. Both native capture entries pass the override to the real view; review confirms it appears in the PNGs. Windows Server 2022 build 20348 at actual 100% DPI; macOS 15.7.9 build 24G830 at actual 1×, with matching content viewports.

Original default/long headers were reviewed in all three languages and both themes. Sampled Windows visible glyph-centre differences improve from 2.5px to 0.5px; current Mac differences are 0.5px at 1×. All 88 Windows checkpoint groups are stable. All Mac refreshed/settled pairs match; 85 groups change from shown as asynchronous logos resolve. Every Windows frame and every Mac refreshed/settled frame is unchanged below the 42px header. Ignored `work/visual-parity/title-after/` contains raw-pixel bounds, review evidence and original-image before/after report; its header-only view crops the display region at 1:1 and can switch to the full native window. [Full Checks run 36822639331](https://github.com/cloydlau/ai-benchgauge/actions/runs/36822639331) passed both platforms' tests/builds, native UI/runtime checks, installer creation and install/uninstall, and native capture/report jobs.

Native font shapes, flags/medals, muted version colour and narrow-name truncation remain platform differences. Existing initial-English-900 Mac scroll overflow remains unresolved. Other local workspace changes are outside this saved branch fixture; the current local Mac CJK title path was separately compiled and captured. Windows 10/11, actual 125%/150% and multiple monitors remain unverified. Three checkpoints are not continuous video. The protected `native-visual-review` environment still requires human release approval; no approval or release is claimed here.

## English-only title restoration (2026-10-01)

All application headings and desktop window titles now use **AI BenchGauge** in every language. The previous Chinese name, custom Chinese title-font code, bundled font and its notices have been removed from production sources and packaging. Existing English script fonts and header/version alignment are retained. The mobile heading, preview assertions and documentation also follow the English-only title; the local environment has no iOS simulator SDK, so mobile native rendering remains unverified.

Before/after native Mac evidence uses the same saved 21-case fixture in ignored `work/visual-parity/english-only-title-fixture.json`, with 126 original frames per build. The comparison is saved in `english-only-title-review.html` and `english-only-title-review.json`. Coverage includes all three languages, both themes, 600/900/1100/1440 content widths, version variants, short/window views, quotas and empty/error states. Actual environment is macOS 27.0 (26A428), backing scale 1×, local uncommitted source. All shown/refreshed/settled groups are identical within each build. Native review found the English script title readable in both Chinese languages and themes, including 600-wide wrapped quotas and the longer version fixture. Chinese header height now follows the existing English font metrics. English title regions match the baseline. Existing constrained table-name truncation and English-heading truncation in the crowded 1100-wide English layout remain unchanged.

Mac packaging and Windows cross-compilation pass. The Mac package has no previous Chinese font or font-license entry. **Current-change Windows native before/after captures, a source-matched CI run and its `native-visual-comparison` artifact are missing.** No Windows 10/11 or additional real DPI coverage is claimed. This local change is not protected human release approval.


## Codex task counts in the macOS status item (2026-10-08)

The local macOS status item now appends running, completed unread and failed task counts. The existing model/quota label and panel remain intact; no task panel is added. Hover text names the three counts in the selected language.

The monitor connects as a passive `benchgauge` client to the already running desktop IPC router (`thread-stream-state-changed` version 11). It follows visible local desktop threads, retaining only runtime/turn status metadata. It never creates an app-server, resumes or starts a task, changes read state, handles approvals or reads authentication credentials. The read-only local SQLite projection supplies the latest persisted turn for unloaded tasks; the desktop read-state file supplies account-scoped local unread IDs. Archived threads, subprocess/agent tasks and remote hosts are excluded. Persisted `inProgress` alone is never counted as running. Waiting for approval/input is excluded from execution; failed tasks stay failed until a subsequent turn replaces the failure or the task is archived. Recoverable tool errors are excluded.

This desktop IPC/read-state storage is a private, versioned integration, not an OpenAI public monitoring API. Missing files, disconnected desktop, malformed/unsupported data and unresolved stream revisions display dashes. Partial frames and snapshot backpressure are handled off the main actor. The app rechecks local task/read state every second and reconnects automatically.

Native before captures are in ignored `work/codex-tasks-before/macos` (126 frames); after captures are in `work/codex-tasks-after/macos` (174 frames). The shared menu-bar fixture adds zero, execution-to-unread/failure transitions, multi-digit and unavailable scenarios in both languages and themes, with shown/refreshed/settled frames. Captured on macOS 27.0 (26A428), actual backing scale 1, status viewport 420 × 22. The reviewed native captures show aligned symbols/text and intact spacing without clipped counts, including `1234 / 567 / 89`. Capture revision is the current uncommitted work based on `2281837580fe7d6f4afdc0f9948884140cc445fd`.

The production reader was checked against the desktop's own thread listing: both reported 3 running local tasks; completed unread and failed were both 0 at the check. macOS receives the feature in this change. Windows task-status transport and genuine Windows tray captures are not implemented/verified here; no cross-platform visual signoff or release approval is claimed. There is no CI artifact for this local capture.


## Codex task updates from local events (2026-10-08)

Task counts now consume a long-lived local IPC stream through a socket readability source. A runtime transition updates the status item as soon as its frame is consumed; unchanged counts do not trigger a UI update. Read-only database scans no longer run every second. Native file notifications observe the thread/history databases and their WALs, the unread file, and the directories that contain replacement/new files. Bursts coalesce to at most four store reads per second; atomic unread-file replacement reattaches its observer. macOS app launch/termination notifications start and stop the connection. Replacement owners get a follower-status response without waiting for a timer.

Timers are reconciliation/recovery only: every 5 seconds with executing tasks, every 30 seconds when idle; failed connections retry after 2, 4, 8, 16 and at most 30 seconds. File/socket events remain live at both cadences, so a new task or marking a completed task read does not wait 30 seconds. A missing handshake has a deadline, invalid stream revisions reconcile promptly, and cancellation releases observation sources, descriptors and retry tasks. This is entirely local and makes no cloud API requests or quota-consuming model calls.

The transport tests use a real isolated Unix socket plus real temporary SQLite/unread files. They check an idle-to-active push and a failed turn arriving within 500 ms without another database read, owner replacement, EOF invalidation, unread-file atomic replacement, discovery of a new task while idle and desktop lifecycle notifications. The menu-bar layout and fixture presentation are unchanged; the previous native captures still document the presentation, while this change is verified as a lifecycle/transport change. Windows task transport remains outside this Mac-only implementation; no Windows visual review or release approval is claimed.

## Unsubscribed and zero-balance quota cards (2026-10-08)

Confirmed unsubscribed plans and wallets with no positive funds now use neutral gray text, monochrome dimmed logos, neutral backgrounds and gray current-provider outlines. The entire card retains its configuration/website click action; a healthy refresh restores its normal presentation. A positive alternative wallet, a pending/failed query, an unknown balance and usage-window warning states keep their prior presentation. The shared Swift predicate is encoded in the Windows engine response, and the WPF card consumes the same decision instead of guessing from translated labels. Both logo renderers preserve the mark's detail and transparency when removing color.

`work/inactive-quota-review/fixture.json` selects the new shared `inactiveQuotas` and `restoredQuotas` scenarios. Before/after original native Mac captures are saved under that directory, with 72 frames per phase: English, simplified/traditional Chinese, 600/900-point widths, both themes and shown/refreshed/settled checkpoints. Actual environment: macOS 27.0 (26A428), backing scale 1×, 820-point content height, fixture SHA-256 `ec7e8cadfebbb0a18b8fad9e6ec4fd5c4deb3d19339f348c155ac91bc81a3c8a`. The baseline is based on `b9f4d158f8e79bd02de13a5fa45ed534e35308b9`; the after capture uses the local updated source. `review.html` links original full frames and `review.json` records metadata/stability. All 24 case/theme groups are stable in each phase; changes stay inside the inactive quota band, while restored scenarios are pixel-identical to their baseline. Inspection includes unsubscribed GLM/Qwen, zero/negative balances, a funded alternative wallet, a healthy plan and a failed query. Labels, gray outlines and wrapping remain intact at both widths; existing narrow leaderboard-name truncation is unchanged. The default shared CI fixture also includes these scenarios.

The local environment has no Windows desktop. WPF cross-build validation is available, but current-change Windows native captures and a source-matched `native-visual-comparison` artifact remain unavailable; the GitHub Actions API check returned HTTP 403 (rate limit exceeded). No Windows visual sign-off, extra DPI coverage or protected release approval is claimed.

Validation passes: the complete test entry (97 script tests, 244 shared-core tests, the other Swift suites including Mac transport/updater tests, and 39 Windows harness cases), syntax validation and WPF cross-build with zero warnings/errors. The classifier covers absent subscriptions, zero/negative wallets, positive alternative wallets, non-finite/unknown balances and recovery without changing query-failure or usage-warning semantics.

## Task-count unavailability diagnosis (2026-10-08)

The three dashes are the unavailable projection, not zero tasks. The reported original process had no task-monitor diagnostic logs, so its exact triggering failure could not be recovered. Fresh reads and a 30-second persistent stream check returned valid task counts. The application now also reconciles desktop process presence from its existing periodic tick, recovering a missed startup/workspace notification without a quota/API request; unchanged presence does not reread task databases. Safe unified-log diagnostics record initialization/presence, aggregate counts, synchronization state and error type/code, never thread contents, identifiers or credentials. The debug `--codex-task-watch` command observes the same event stream for 30 seconds instead of stopping at the first snapshot.

After signed packaging and restart, the real application process's monitor logged `running=1, unread=0, failed=0`, and its status-item update logged `▶ 1  ✓ 0  ! 0`. A fresh debug read and the desktop's local thread listing agreed (one active task, no completed unread or failed tasks). This verifies the running app's data-to-status-item path; it is not a live desktop screenshot. The CUA app read timed out. The status-item layout remains unchanged, so prior native menu-bar fixture captures remain the presentation reference. Full script/Swift/Windows-harness tests and syntax validation pass; Windows task transport/visual coverage remain outside this Mac-only change.

## Recurring task-store failure (2026-10-08)

The subsequent production log captures the real recurrence: PID 55407 displayed valid idle/unread counts at 21:31:40, then store `ReadError` failures from 21:36:40 to 21:54:47. The old catch block disconnected its otherwise live IPC connection on every store failure and increased connection backoff to 30 seconds. The same process recovered at 21:55:19 without a restart. The previous error logged only an enum type/code; it cannot distinguish the missing unread entry from either SQLite prepare failure, so the exact original failing store operation remains unproven.

The reader now accepts an absent unread-state entry as empty, matching the desktop's own default, while rejecting present malformed/unknown versions. Store errors preserve live IPC subscriptions/snapshots and retry locally after one second; counts remain unavailable while the store is untrustworthy. Logs identify the safe operation stage and SQLite result code and record recovery without any thread content/identifiers. An integration regression holds a real SQLite exclusive writer lock, observes unavailable counts, pushes a runtime change while locked, then rolls back without another file event. Counts recover within two seconds on the existing single-client connection, and subsequent completion correctly uses the unread marker. Core regressions cover absent/empty unread maps and incompatible versions. This changes transport/recovery only; native presentation and Windows coverage are unchanged.

Complete script/Swift/Windows-harness tests and syntax checks pass. Signed local packaging and restart produced PID 26670; its monitor and actual status-item logs at 22:04:00 agree on `running=2, unread=1, failed=0`. A separate 30-second reader stream agrees and stays valid after initialization. This confirms current recovery and the production data-to-status-item path, not a reproduction of the original failing store operation or a native screenshot.

## Task-count visibility when Codex is closed (2026-10-08)

The entire task-count label and its tooltip entry now require a running, nonterminated Codex desktop bundle. An absent installation, an installed but closed desktop, and a CLI/app-server helper alone all hide the block. Desktop launch/termination notifications update visibility immediately; the existing presence reconciliation tick remains a fallback. Termination clears old counts, and in-flight monitor updates cannot repopulate them while the desktop is closed. An open desktop still shows genuine zero counts or unavailable-state dashes when appropriate. Other status-item content remains visible; with no other label, AppKit uses the existing centered icon-only presentation.

`Tests/fixtures/codex-task-presence.json` exercises absent/closed states with unavailable and stale zero values, launch, termination with old positive values, a running-but-unavailable reader, and icon-only fallback. Real original AppKit captures in ignored `work/codex-task-presence/before/macos` and `after/macos` contain 72 frames each: English/Chinese, both appearances, shown/refreshed/settled, 420 × 22-point buttons, actual 1× backing scale, macOS 27.0 (26A428). Fixture SHA-256 is `debf742d19e5825d6275ae9b9f53154aaf4ca3d900e53f91df357cf59be5da67`; baseline is based on `db24d94374778a85d4a82f5caf41c87a84a89645`, after is the local working tree. `review.html` links unscaled originals and `review.json` records pixel comparisons; all 24 case/appearance groups have stable refreshed/settled frames. Actual button-label/tooltip assertions check visibility, and metadata retains the text at each checkpoint. Reviewed originals show the block disappearing/appearing without orphan separators and the remaining label/icon centered. The dark button fixture inherits the desktop status-bar background; no additional theme-color change is claimed. Windows task transport/captures and a source-matched CI artifact remain unavailable; no Windows visual sign-off or protected release approval is claimed.

The exclusive-lock recovery test now explicitly invokes the next store reconciliation before pushing a runtime update. This isolates its transport/error recovery assertion from macOS filesystem-notification coalescing under CI load; the independent atomic-replacement test continues to check actual file wakeups and latency. That test also exposed delayed invalidation while the reader waited for socket chunks after a store error. The monitor now publishes unavailable counts immediately on the store error and drains existing socket bytes without waiting in that case, keeping recovery/push processing responsive.

Complete tests (97 script cases, all Swift suites including 9 Mac updater/transport cases and 244 shared-core cases, and 39 Windows harness cases), syntax checks and signed local packaging pass. The restarted production PID 97280 detected the running desktop and rendered `▶ 1  ✓ 2  ! 0` at 22:16:27, agreeing with a fresh reader. Closed/absent/launch/termination visibility is verified through the original native fixtures; the user's live Codex process was not terminated to test it.

## Nonzero task errors only (2026-10-08)

The status item now appends the exclamation mark/error count only for a positive failed-task count. Zero errors and unknown errors omit that segment; running and completed-unread counters retain their existing behavior. The tooltip likewise omits a zero-error entry. A running Codex desktop remains necessary to display the task block at all.

`Tests/fixtures/codex-task-failures.json` covers 0 → 2 errors, 2 → 0 recovery and unavailable counts in English/Chinese and both appearances. Ignored `work/codex-task-failures/` holds 36 before and 36 after original native AppKit frames, plus `review.html` and text/pixel checks in `review.json`. Before uses the saved native app from the previous presence capture, whose task formatting matches the pre-change code. After uses this local source. Fixture SHA-256: `5f2845305d2411391a5fd483a2a2ad8d8a6320b1fd387a4da31909b69585eb4d`; actual macOS 27.0 (26A428), 1× backing scale and 420 × 22-point buttons. All 36 after labels have the expected error visibility, zero-error tooltip entries are absent, and positive-error frames are pixel-identical to the baseline. Reviewed original frames show clean spacing when the segment is omitted. Windows task transport/native captures and source-matched CI artifacts remain unavailable; no Windows visual sign-off or protected release approval is claimed.

Full tests and syntax validation pass; signed packaging and local restart pass. Production PID 83978 logged `running=1, unread=0, failed=0` and rendered `▶ 1  ✓ 0` at 22:22:54, matching a fresh reader and confirming that the real app no longer displays `! 0`.

### 动态国家资料（本地核对，2026-10-13）

本次使用 `work/country-discovery/fixture.json`：Utopai Studios / 美国、Skywork AI 与 Sapiens AI / 新加坡、动态厂商 / 日本与英国、国家未知的厂商；模型与公司两种分组，中英与繁中，浅深两种主题，刷新失败仍保留数据。Mac 的前后原生截图使用同一 850×720 内容视口，三帧（shown/refreshed/settled），保存在 `work/country-discovery/before` 和 `after`，附实际 OS、1x DPI 和 fixture hash。核对国家列和筛选行为；原有长名称省略仍存在，未在本次调整。

iPhone 18 Pro（iOS 27，402×874 pt、3x）和 iPad Pro 11 M5（iOS 27，834×1210 pt、2x）分别完成动态国家 UI 用例，中英文/浅深色及模型/公司分组共 12 张原始截图，各保留刷新前后及稳定帧，测试结果在 `work/country-discovery/phone.xcresult` 与 `pad.xcresult`。美国、新加坡、日本的旗帜与未知占位没有新增遮挡或重叠。

共享服务读取两张视频榜共 40 条记录均有国家元数据，排名、分数、榜单时间戳保持一致。引擎离线验证日本/未知筛选及公司分组，以及筛选后仍保留英国等其他国家菜单选项。Windows WPF 编译通过，新增国家筛选及译名使用引擎数据；当前本机无 Windows WPF 运行环境，没有本次 Windows 原生前后截图或 CI 原生视觉审阅记录，不能宣称已完成 Windows 视觉验证。Windows 原六国旗帜保留，其他 ISO 国家显示两字母码是当前平台差异。

## Desktop subtitle: board comparison and quota tracking (2026-10-13)

Mac and Windows use `双榜对照 & 余量追踪` / `雙榜對照 & 餘量追蹤` / `Dual boards & quota tracking`. The existing subtitle/version glyph alignment stays in place. The longer English caption switches to the existing two-row header below 1300 points so it does not overlap the centered controls; Chinese keeps the 1100-point breakpoint.

`work/desktop-subtitle/fixture.json` covers English/Simplified/Traditional Chinese at 850, 1100 and 1300 points, plus empty/error states and a long version. Mac before/after native AppKit/SwiftUI captures use matching fixtures and content viewports, light/dark themes and shown/refreshed/settled frames (72 originals each), with OS and actual 1× backing scale in metadata. Review confirms complete captions with no new clipping or overlap. Windows WPF compiles successfully, but a Windows native runtime/capture is unavailable locally; no Windows visual verification, CI visual-review record or protected release approval is claimed.
## Model mark priority (2026-10-13)

Shared manufacturer PNGs previously replaced bundled product marks in model rows. Mac, iPhone/iPad and the Windows engine now apply the same priority: an explicit model PNG, then a recognized bundled product mark, then the provider image or existing fallback. Company rows retain their provider PNGs. Recognized bundled products include Claude, Gemini, Qwen, Kimi, DeepSeek and MiniMax; other families keep their shared images, including the distinct Wan, Grok, Dreamina and SkyReels marks.

`work/model-logo-priority` retains 36 native Mac before and 36 after originals with the same fixture and 850×720-point viewport. The fixture contains actual cached provider PNGs alongside explicit model PNGs, a long missing-image row and refresh failure. English/Simplified/Traditional Chinese, both themes, model/company grouping and shown/refreshed/settled frames are covered. All 18 company comparisons are pixel-identical; model differences are confined to the first three rows' icon tiles. Review confirms restored Qwen, Claude and Gemini marks and unchanged explicit model marks, alignment and row colors. Original image hashes, fixture hash and source hashes are retained in `native-review.json` and `source-hashes.json`.

The full script/Swift/Windows test gate passes with all supported coverage metrics at 100%. An actual engine JSON round trip confirms bundled model selection, explicit model PNG preservation and separate company PNGs. iPhone/iPad views compile and their unit tests pass; mobile native screenshots were not recaptured for this priority change. Native Windows/DPI captures are unavailable locally, so Windows visual parity remains unverified. No protected release publishing or human approval is implied.

## Brand mark rotation (2026-10-13)

The canonical neural-network nodes and accent endpoints are rotated 90° counterclockwise around the 256-point canvas center. The output is above the three input nodes. All SVGs, PNG sizes, Windows ICO frames, Mac ICNS frames and the iOS asset catalog are regenerated from that geometry. Platform padding and backgrounds retain their existing treatment.

Ignored `work/logo-rotation/review.html` and `review.json` retain 48 native Mac before/after pairs, using the same native executable, status-icon fixture and 420×22-point viewport. Captures cover icon-only, task/quota text, highlighted, appearance-switch and icon/text lifecycle states, with shown/refreshed/settled frames in light and dark. Actual environment: macOS 27.0.1 (26A434), 1×. Review confirms the upright rotated mark stays inside the status button and labels remain identical; pixel differences are confined to the glyph. Windows native captures and a source-matched CI visual artifact are unavailable locally, so Windows native visual parity is not certified. No protected release publishing or human approval is implied.

## Unified feature subtitle and quota help (2026-10-13)

All four native clients use “双榜对照 & 余量追踪” (with Traditional Chinese and English translations). The trailing question-mark control explains the feature and its availability in the PC edition. Mobile makes the complete caption tappable as well as its icon; the desktop has an accessible help button next to the caption. Shared Swift copy keeps Mac/iPhone/iPad wording consistent, and the WPF text matches it. The explanation is informational and dismissible.

Ignored `work/quota-platform-help/` retains the shared fixture and original Mac header comparisons: 850/1100/1300-point widths, English/Simplified/Traditional Chinese, normal/empty/error/long-version states, light/dark and shown/refreshed/settled frames. The added help-dialog scenarios capture the actual AppKit alert content (native dimensions recorded with each PNG), rather than a browser recreation. Header alignment and complete caption visibility remain intact; Mac captures use actual 1× backing scale. Windows compiles but has no available native WPF runtime or original captures locally, so its visual/interaction behavior remains unverified on a Windows machine. No CI visual-review approval or protected release approval is implied.

The iPhone 18 Pro (iOS 27, 402×874 pt / 3×) and iPad Pro 11 M5 (iPadOS 27, 834×1210 pt / 2×) each passed the Chinese/light and English/dark help interaction test: full subtitle, tap, exact explanation, dismissal and return. Original heading/dialog attachments remain in `work/quota-platform-help`. The English phone moves model/company selection below the title to retain the whole caption; the title/subtitle/version retain their visible glyph alignment. An initial test-only query hit XCTest's 128-character identifier limit and was corrected to use an exact label predicate.

## Uniform mobile name backgrounds (2026-10-13)

The name background now has a 36-point minimum height, filling the existing 44-point row while retaining the four-point outer inset above and below. Longer names keep their intrinsic multiline height. Background gaps therefore stay at eight points instead of growing when a single-line name shares a row with the minimum touch target. The existing first-row alignment gives the same eight-point gap below the table divider.

`work/colored-name-gaps/review.html` and `review.json` retain original native iPhone 18 Pro (402×874 points, 3×) and iPad Pro 11 M5 (834×1210 points, 2×) screenshots in both themes. A synthetic 20-row fixture starts with single-, two- and three-line names and returns to single-line rows. iPad before/after measurements show 14/8/14/20-point gaps becoming eight throughout. iPhone after measurements confirm 24-pixel gaps and iPad after confirms 16-pixel gaps; both header gaps equal eight points. The attempted iPhone baseline was affected by another installation on the shared simulator and is excluded from before evidence. SDK build succeeds. This change is confined to the shared mobile card; desktop rendering is outside its scope.

## Mobile model logo tiles (2026-10-13)

The shared iPhone/iPad renderer now matches the desktop tile proportions: a 20-point white tile, 2.5-point logo inset and a continuous five-point corner radius. The complete tile is clipped to its rounded shape and has the same half-point boundary stroke. Transparent circular source marks therefore sit within an even white surround instead of filling a smaller square with prominent white corners. Shared/model/company mark priority and desktop rendering are unchanged.

`work/mobile-logo-corners/fixture.json` uses real cached Xiaomi MiMo and StepFun marks, bundled versions and an unknown-provider text fallback. `testMobileLogoCornerFrames` covers Chinese/light and English/dark, model/company grouping and shown/refreshed/settled screenshots. The saved native baseline comes from the prior colored-name-gaps build and reproduces the 18-point/no-inset logo treatment; unrelated header changes are outside this logo comparison. The source-matched after build uses an isolated copy of the current Swift package because Xcode's recursive file watcher scans the large ignored `work/` tree. Source/fixture hashes and original captures remain in that ignored directory.

The iOS arm64 simulator build and nine iOS configuration tests pass. The iPhone 18 Pro native UI test passes with twelve original after frames (402×874 points, actual 3× backing scale, iOS 27.0), including refresh and grouping changes. Reviewed captures show even white surrounds around Xiaomi/StepFun, consistently rounded boundaries, intact bundled/text fallbacks and no adjacent-text overlap. The single usable native baseline reproduces the reported corners in Chinese/light/model mode; other baseline capture attempts were interrupted by slow simulator installation. Other themes/states have after coverage only. Original attachments, hashes and review notes remain under `work/mobile-logo-corners/`; iPad uses the same compiled renderer but has no native capture in this verification. No desktop change or protected release approval is implied.


## Source metadata and column headings (2026-10-13)

Live cards no longer repeat the leaderboard name below its source tab. Source explanations move into the model-name column heading; the metadata row contains only the summary on the left and explicitly labeled source/fetch times on the right. The source time comes first. Wide layouts join the pair with a middle dot; narrow layouts stack both labels. A hidden maximum-width sample keeps both sides in the same layout even when one source date is missing. Missing source publication remains `—`, while a pending card also has no fetch yet. Coding-agent batch timestamps retain their existing `materializedAt` interpretation. Source details include complete dates and explain missing timestamps. Exported images keep their source titles because they have no tabs.

Mobile uses a 12-point vertical rhythm: the source tab to metadata content and metadata content to column headings both have 24 points including inner/outer padding. Source help, refresh, openness/country filters, scroll and copy actions remain available. Windows engine projection now preserves a missing source timestamp instead of substituting the fetch date; a real engine JSON round trip verifies both missing and known source times.

Ignored `work/board-header` retains 54 before and 54 final original native Mac frames from matching fixtures, viewports, languages and light/dark appearances, plus 72 final source-time frames across all four categories. Captures use macOS 27.0.1 and actual 1× scale; the native metadata retains the precise environment. `review.html`, `native-review.json` and source hashes retain the comparison evidence. Native iPhone 18 Pro (402×874 points, 3×) and iPad Pro 11-inch M5 (834×1210 points, 2×), both on iOS 27, pass source-time and cached/pending failure interaction tests; their xcresult bundles and original attachments remain in the same directory. Explicit missing source dates, known coding dates, long names and both languages are covered. The initial Chinese mobile captures inherited the simulator's dark appearance; the normal-state spacing captures set light appearance explicitly before Chinese and use the app's dark override for English.

Three focused Swift formatting/presentation tests, the actual engine timestamp projection and 39 Windows harness cases pass. Wider parallel Swift tests initially hit two existing async deadlines while ImageRenderer held MainActor; both affected async cases pass in isolated rechecks. Windows WPF Release compiles without warnings or errors, but native Windows/DPI screenshots and a source-matched CI artifact remain unavailable. No Windows visual verification or protected release approval is claimed for this change. Development-device installation follows the full source-matched check gate.

## Icon-only phone source status (2026-10-13)

Interactive iPhone boards omit the visible Open/Closed text beside the lock glyph. The hidden sizing badge uses the same compact mode, so it does not continue reserving space for a full label. The Source heading and filter remain readable; unavailable and company statuses remain a dash. The shared badge's default retains visible text for desktop, iPad and exported images. Its accessibility representation keeps localized status text and the existing element identifiers, including when the visual title is omitted.

`work/mobile-openness-icons/` retains twelve native after frames, source hashes, original result attachments and review notes. The matching before fixture/viewport uses the prior twelve original frames under `work/mobile-logo-corners/after`. Environment: iPhone 18 Pro, iOS 27.0, 402×874 points at actual 3× scale. Chinese/light and English/dark, model/company grouping, shown/refreshed/settled frames all render compact lock badges without clipped icons or overlapping neighboring columns. Concurrent header/name changes are outside this source-status comparison. The native simulator build passes; both the screenshot test and the existing openness/company aggregation test pass, retaining exact accessible Open/Closed/unknown labels. A failed attempt on the shared default simulator was interrupted by concurrent installations and is excluded. Desktop and iPad retain the default rendering and have no new native visual sign-off in this mobile-only change.

## Brand palette C — Deep sea teal (2026-10-13)

The user-selected C palette changes the canonical tile to `#0B222B` → `#173E43`, the connections/output ring to `#56B9BA` → `#65D5C5`, and node ink to `#C2F2DB`. The accent follows the upward inference path. Neural-network geometry, rotation and platform padding remain identical. All eleven SVG/PNG/ICO/ICNS exports and the iOS asset catalog are regenerated; the monochrome menu PNGs are byte-identical to the baseline.

Ignored `work/logo-palette-20261013/` retains the approved comparison, baseline assets and before/after native AppKit `NSImageView` resource captures at a 900×320-point viewport in both appearances. These decode the actual ICNS at 32/48/64/128/256 points; they verify icon resources, rather than an installed app window. The canonical Mac PNG is byte-identical to the approved C preview. The seven Windows ICO PNG frames validate at 16–256 px, the iOS RGB image is opaque 1024×1024 and identical to its asset-catalog copy, and all nine iOS configuration/icon tests pass. The existing pixel test now compares node ink after AppKit's calibrated-color conversion instead of requiring the old white nodes. Windows WPF native appearance and installation of these resources on the running Mac app/physical phone are not verified by these resource checks. No protected release or native visual-review approval is implied.

## Smaller phone filter chevrons (2026-10-13)

The interactive iPhone Source/Country headers share an eight-point medium-weight downward chevron, replacing the larger caption2 symbol on that layout. Non-phone layouts retain caption2; desktop clients are unchanged. The filter labels, accessibility identifiers and menu actions remain in place.

`work/mobile-filter-chevrons/` retains source hashes, native result attachments and review notes. The matching before fixture/viewport uses `work/mobile-openness-icons/after`; concurrent header/name changes are outside this arrow comparison. Native environment: iPhone 18 Pro, iOS 27.0, 402×874 points at actual 3× scale. Four light/dark and model/company states include shown/refreshed/settled frames, plus all/filtered states from the menu/intersection test (14 native originals). Review confirms the smaller symbols align with header text without clipping or overlap. The arm64 simulator build, screenshot test and Source/Country filter/intersection test pass. No new desktop or iPad native sign-off is claimed for this phone-only adjustment.

The fixed source passed all tests and 100% script/Swift coverage and was signed, installed and launched on the configured physical iPhone at 2026-10-14 00:03:09 Asia/Shanghai. `work/board-header/installation-evidence` retains genuine gate, signing and installation records; `verified-layout-source.tar.gz` retains the exact app and shared-library source. Primary check receipts were not changed to claim that subsequent parallel edits were tested. Only the owned snapshot updater and source checkout were removed.

## iOS leaderboard bottom safe area (2026-10-14)

The compact cube viewport now continues through the bottom container safe area. Ranking content and its footer reserve the measured bottom inset plus eight points, so scrolling to the end leaves the controls above the Home indicator. The wide iPad scroll view also extends to the bottom with its own inset. The root background explicitly covers all safe areas, and iOS 26+ system scroll-edge effects are hidden at both compact cube edges, where the header is outside the scroll view; the wide layout hides only the bottom effect and preserves its existing top behavior.

Native originals and XCTest results are retained under ignored `work/ios-safe-bottom/`. The initial twenty-row fixture was captured before the change on iPhone 18 Pro / iOS 27.0 (402×874 points, actual 3×); the first baseline run stopped on an incorrect static-text query for the button-backed final model name, rather than a production failure. The corrected test verifies final-row and footer hit testing, footer clearance, and the viewport reaching the physical screen bottom. It passes in light/dark on this iPhone and on iPad Pro 11-inch M5 / iOS 27.0 (834×1210 points, actual 2×). The simulator's Home indicator is not rendered in these captures; clearance is verified against screen bounds. These are native iOS checks; no desktop or protected-release approval is implied.

The additional long-name twenty-row scenario (`phone-wrapped.xcresult`, `pad-wrapped.xcresult`) passes in both appearances on both devices. Its intermediate phone capture visibly carries ranking-row content all the way to the physical lower edge; its final capture shows the final row and footer entirely above the reserved inset. Ordinary one-line and wrapped-name originals are kept separately. A preliminary sixty-entry fixture was rejected by the new test because this product intentionally displays only the top twenty; the final scenario exercises those twenty with two-line names, without changing the product's limit.

The final source preserves the wide layout's top scroll-edge treatment (`pad-final-source.xcresult`) and also passes the phone test again (`phone-final-source.xcresult`). Full tests and all enforced Swift/script coverage metrics pass on the frozen source. The signed development app was installed on the configured physical iPhone at 2026-10-14 00:26:50 Asia/Shanghai; auto-launch was prevented by the phone being locked. The actual install receipt and complete gate/signing logs are retained in `work/ios-safe-bottom/installation-evidence`, with the exact app/shared-library source in `verified-source.tar.gz`. Only the owned frozen updater was stopped; the primary workspace's update configuration remains unchanged.

## iOS source tabs and table headings (2026-10-14)

The phone cube tabs now consistently identify the comparison method: Task benchmarks / User votes (任务测评 / 用户盲测). The model-name column heading uses the exact source name previously shown in the tab, such as Artificial Analysis, Text Arena or Artificial Analysis 编程. Source descriptions, timestamp pairs, selected-face behavior and the bottom-safe-area fix remain in place. The iPad table uses the same actual-source heading; desktop clients are unchanged.

Ignored `work/board-tab-labels/` retains native phone/iPad originals and XCTest results, with shown/refreshed/settled General/Coding frames in Chinese/light and English/dark. The matching twenty-row metadata fixtures use iPhone 18 Pro / iOS 27.0 at 402×874 points (actual 3×), and iPad Pro 11-inch M5 / iOS 27.0 at 834×1210 points (actual 2×). The earlier `work/board-header/*-final-originals` captures retain the previous tab/heading labels; intervening branding and safe-area updates are outside this text exchange. The first lightweight preview package omitted Resources/Brand and therefore crashed while constructing the English heading; the owned preview package now copies both Fonts and Brand exactly like Package.swift. No production branding code was changed. Phone label/spacing checks and cached/empty source-error checks pass; all full-suite tests and enforced script/Swift coverage metrics pass. No desktop or protected-release approval is implied.

The complete-resource phone and iPad metadata tests both pass, with twelve original frames each. The development app was signed and installed on the configured physical iPhone at 2026-10-14 00:36:58 Asia/Shanghai. The phone was locked, so automatic launch was unavailable. Genuine test/check/install records are retained under `work/board-tab-labels/installation-evidence`; the primary updater remains enabled.

## Centered phone company purchase links (2026-10-14)

On interactive iPhone company rows, the name/link HStack now uses center alignment instead of first-text-baseline alignment. Plan/Usage links consequently center against the whole two-line name rather than its first line. Single-line rows keep centered contents. Non-phone layouts retain their existing baseline alignment; link destinations and actions are unchanged.

`work/mobile-purchase-center/` retains the Microsoft AI, Black Forest Labs, Anthropic and xAI fixture, source hash, original native before/after captures and review notes. Captures use the same iPhone 18 Pro viewport (402×874 points, actual 3× scale, iOS 27.0), Chinese/light and English/dark, normal/extra-extra-large Dynamic Type and three settling frames per state (12 originals before, 12 valid originals after). Reviewed single-line, two-line/truncated, single-link and two-link rows show centered links without overlap. Concurrent header/branding differences are outside this purchase-row comparison. The native arm64 build passes. An initial verification copy omitted the new Brand resource declaration from Package.swift; its invalid after captures are preserved separately and excluded. The final captures use the complete manifest. No new desktop/iPad native visual sign-off is claimed for this phone-only adjustment.

## Header A cutout correction (2026-10-14)

The title now uses only the neural-network A. Both header PNGs have transparent backgrounds and are cropped to the network's painted bounds, 284×332 px (142:166 aspect). The square application icon is not used in the wordmark. Light surfaces use deeper teal for legibility; dark surfaces retain the selected C palette's mint. Chinese keeps the original A's visible width and 2.5-point glyph gap. English retains native attributed-text rendering and original advances/baseline; the first A is transparent and the cropped mark fits before I without overlap. Both platforms preserve the artwork aspect ratio and center it on the original A's ink.

`work/header-logo/cutout-before/macos/` and `after/macos/` retain 36 original native AppKit/SwiftUI pairs at 850/1300×720 points, English/Simplified/Traditional Chinese, light/dark and shown/refreshed/settled checkpoints. The remaining-title region is pixel-identical in all 36 pairs; hashes and exact comparison regions are recorded in `cutout-review.json`. The comparison excludes the replaced A, age labels captured on different dates, and unrelated concurrent table changes. Native iPhone 18 Pro (iOS 27, 402×874 pt, 3×) Chinese/light and English/dark screenshots show the network alone with no square tile. Five native resource/title regression tests pass, validating original title/baseline footprint across three sizes and four alignments, transparent corners and painted outer bounds. Mac and iOS simulator builds and Windows Release cross-build pass (Windows: zero warnings/errors). Windows WPF screenshots are unavailable locally, so its native visual parity is not certified. No protected release or human visual-review approval is implied.


## Complete rankings and return to top (2026-10-14)

The shared service and native fallback parsers retain all valid source rows, and company aggregation retains every company. Mac preserves its twenty-row preferred viewport and Windows preserves the existing panel dimensions; additional rows scroll within the table. Both expose native scrollbars and a return-to-top control after scrolling. iPhone/iPad reuse their scroll containers and add the same action. iPad uses system scroll geometry on iOS 18+ / macOS 15+, with a preference-based fallback on older supported systems. The mini-program retains its existing return-to-top action and now displays complete lists.

Ignored `work/full-ranking/review.html` and `review.json` retain the native comparison, source context, image hashes and live-refresh results. Mac has 24 before and 24 after baseline originals using the same synthetic 31/26-row fixture and 1000×720-point viewport, plus 40 originals exercising scroll-to-last and return-to-top. English/Chinese, model/company and both appearances are covered on macOS 27.0.1 (26A434), actual 1× backing scale. Native assertions verify 31 table rows, unchanged viewport size, a reachable control at the lower right, and restoration of row one. Refreshed/settled differences are confined to native scrollbar fading. An intermediate control mounted inside the native table container was misplaced; the final pass-through overlay fixes its position and preserves table hit testing.

Native iPhone 18 Pro (402×874 points, actual 3×) and iPad Pro 11-inch M5 (834×1210 points, actual 2×), iOS 27, pass the forty-row model/company tail-and-return test. Six original attachments per device and their successful xcresult bundles are retained. The phone's English fixture inherits the simulator's dark appearance; Chinese company mode explicitly requests dark. Existing English phone header truncation is outside this table change. The iPad's first preference-only implementation failed to reveal the control; the final native test passes after system geometry tracking was added. Early dedicated-simulator attempts were stopped during slow simulator startup and are excluded from successful evidence; those two temporary simulators were removed.

241 script tests, 59 service/mini-program checks, 361 Swift tests and the 39-case Windows harness pass in their recorded runs. Shared mobile SwiftUI and iOS simulator builds pass. WPF Release cross-compilation passes with zero warnings/errors; native Windows screenshots and real DPI validation remain unavailable. Full coverage-mode checks are not green: background watcher/adapter tests time out, and an earlier coverage inventory lacked a concurrently added generated policy file. No complete-CI, protected release or client distribution approval is claimed. The shared FC parser is deployed; AA refreshes return 32/39/102/33 rows, while Arena HTTP 403 keeps the prior twenty-row cache until a normal refresh succeeds.


## Bounded long-ranking rendering (2026-10-14)

Complete rankings now retain all logical rows while limiting live views to the viewport and nearby rows. The mini-program follows Watrek's stream-layout strategy: stable total height, absolute global row offsets, twelve-row buffers, a six-row edge threshold, overlap reuse and synchronous native scroll-event updates. Full raw data stays outside the Vue-to-WeChat bridge. Windows uses a native recycling VirtualizingStackPanel with pixel scrolling and lightweight index items; row controls are constructed only for realized containers. iPhone/iPad retain the first two measured rows for heading spacing and use LazyVStack for the remaining interactive rows. Filtered/company rows, country options and score-width formatting are cached until relevant source data or preferences change. Explicit image exports still render all rows. Mac retains native NSTableView recycling.

Ignored `work/virtual-ranking/review.html` and `review.json` retain the six native Mac before/after pairs, hashes, fixture and actual platform metadata. The same 5000-row fixture uses 1000×720 points on macOS 27.0.1 at actual 1× backing scale. Native checks find sixteen realized rows both initially and at the final row, then restore row one with the existing control. Refreshed frames are pixel-identical in both appearances; settled light is identical and settled dark differs only in scrollbar fading. Shown-frame differences reflect asynchronous logo arrival. The compact shared native CI fixture adds a 5000-row `virtualRanking` scenario with realized-container, last-row and return-to-top assertions on both desktop harnesses.

The actual WeChat developer-tool renderer passes a synthetic 2000-row model/company scenario: both boards together mount seventy-six row nodes, the cards sent through the bridge remain roughly 17 KB, rank 2000 is reachable and the control returns to rank one. The automator's enhanced-scroll-view `scrollTo` helper did not move the native viewport; the successful run changes the real `scroll-top` target and verifies physical scroll position plus rendered ranks. Request mocking and prior storage are restored in the finally block. A 10000-row controller test and window math through 100000 rows cover jumps, tail clamps, resizing, buffer hysteresis and overlap identity.

Thirty-seven focused script tests, the 5000-row Swift presentation cache test, mini-program build, iOS simulator build and Windows Release cross-build pass in their recorded runs. Native iPad tests pass forty-row tail/return and thousand-row model/company rendering, initially realizing forty-two/forty-nine rows per source. Windows native screenshots/execution, real-device performance and full CI coverage are unavailable in this local verification; no FPS guarantee, client distribution or protected release approval is claimed.

The final native iPhone run (`phone-active.xcresult`) passes all three selected tests with zero failures: forty-row model/company tail and return, thousand-row bounded rendering and return, and source switching at both the top and a scrolled comparison rank. It creates twenty-five/thirty source rows initially and forty-three/fifty-one after scrolling in model/company mode. Intermediate attempts exposed duplicate return-to-top buttons on inactive cube faces; only the active face now mounts that action, with an assertion requiring exactly one accessible control. The final implementation retains ScrollViewReader's normal top target; temporary UIKit probes and full scroll-window resets were removed. Both compact and long-row original screenshots are retained. Phone/iPad use iOS 27 simulators at 402×874 points/actual 3× and 834×1210 points/actual 2× respectively. These checks bound row-view creation; they do not measure real-device frame rate.


## Ranking column order (2026-10-14)

All clients now display rank, name, country, source and score in that order. Both desktop source groups retain their shared rank column. Country/source filter headers, arrows, tooltips and Mac native header hit targets move with their fields; interactive rows, placeholders and the shared iPhone/iPad image-export view use the same order. Existing field widths are permuted with their fields, preserving total table width and the name-column space.

Ignored `work/column-order/review.html` and `review.json` retain 36 native Mac before/after pairs at the same 1000×720-point viewport and fixture, shown/refreshed/settled checkpoints, English/Simplified/Traditional Chinese, model/company modes, active filters, setup-empty and cached-error scenarios in light/dark. Settled changes remain within the reordered fields. Mac debug, iOS simulator and Windows Release cross-builds pass; Windows reports zero warnings/errors, but native Windows screenshots and actual DPI validation remain unavailable. The actual WeChat renderer confirms ascending x coordinates for rank/name/country/source/score in both the header and a data row, and the mini-program build passes. No client distribution or protected release approval is implied.

Native iPhone 18 Pro and iPad Pro 11-inch M5 filter regressions pass with zero failures (`phone-final.xcresult`, `pad-final.xcresult`). They verify open/closed/unknown/all, country intersections and company/model switching, with original all/reset frames retained. Both use iOS 27 simulators at actual 3×/2× scale respectively. The first attempts stopped on an obsolete StaticText-only lookup for the semantic source badge; the scoped test locator now matches its accessibility identifier across element types and retains the exact status assertions. A concurrent Mac shared-presentation refactor arrived after captures; its unrelated changes are preserved, the requested column order/header indices remain intact, and the exact captured Mac source plus hash are retained under `work/column-order/captured-source`. This comparison does not certify that separate refactor.
## Shared Mac / iPhone / iPad presentation rules (2026-10-14)

Mac now uses `LeaderboardPresentation` and `LeaderboardCountryFilter` for source titles and descriptions, model/company filtering and aggregation, country choices, rank medals and relative ages. The compact Mac header tooltip shares the same source explanation while retaining its shorter form. Native controls and mobile row-presentation caching remain platform-specific. The Debug capture path supplies the category directly to `applyVisualFixture`, avoiding the live refresh previously triggered by `selectCategory` during category captures.

Ignored `work/shared-presentation/` holds the original Mac rules, the refactored source snapshot, fixture, native originals, source hashes and `review.html` / `review.json`. Both comparison builds use the same corrected Debug category injection; the original Mac rules are compiled with the updated shared library, whose existing default behavior is retained and tested. The fixture covers all eight boards, three languages, four categories, model/company grouping, both themes and a 1100×720-point viewport at actual 1× backing scale on macOS 27.0.1 (26A434). All 144 before/after frame pairs are compared; all 48 settled frames are pixel-identical. Some initial frames differ during native drawing. Neither corrected capture creates the refresh cache, confirming the category fixture no longer starts a live refresh. Concurrent column-width/caret work is preserved in current sources but excluded from this refactor comparison; the combined current Mac sources separately compile.

71 focused Swift tests plus the separately compiled combined-country/openness regression pass. The latter checks filtering before company aggregation and preservation of the original snapshot. iOS simulator app compilation, 23 release/iOS script checks, a final 17-check iOS/visual-policy run, syntax and diff checks pass. Native Windows captures and a source-matched CI visual artifact are unavailable; no Windows visual verification, protected review approval or installed-client update is claimed.


## Smaller country/source text headers (2026-10-14)

Country and source retain their text labels and filter carets, with dedicated smaller header typography: 9.5 points on Mac/Windows, 10 points on iPhone and 11 points on iPad (Apple mobile headers follow Dynamic Type), and 18 rpx in the mini-program. Primary headers, scores, model names and body flags/openness badges keep their existing typography. Mac country/source widths become 36/56 points, returning 44 points to each name column while preserving preferred panel dimensions. Windows narrows those columns and header padding; Apple mobile columns continue measuring the shared smaller labels while respecting body badge widths. The mini-program keeps 29-pixel Chinese attribute columns at its 375-pixel fixture width and accommodates full English/three-character Traditional labels in wider columns.

Ignored `work/filter-header/review.html` and `review.json` retain 36 native Mac before/after pairs using identical synthetic fixtures and 1000×720-point viewports, light/dark, English/Simplified/Traditional Chinese, model/company, selected filters, setup-empty and cached-error scenarios at shown/refreshed/settled checkpoints. Full Open/Closed badges remain visible in the narrower columns. Native iPhone/iPad screenshots show complete text labels and more room for names. Mac/iOS simulator, mini-program and Windows Release cross-builds pass; Windows reports zero warnings/errors but lacks local native WPF/DPI validation. Final WeChat native readback passes in all three languages, with preferences restored. iPhone/iPad filter assertions reach reset with no assertion failures, but both automation runners stall waiting for SpringBoard idle during teardown and were interrupted; these xcresult bundles are not green-suite evidence. No full-CI, real-device or protected-release approval is claimed.

## Quiet automatic refresh on mobile (2026-10-14)

iPhone/iPad no longer render refresh-failure buttons, warning-coloured timestamps/update badges or failure reasons in source-detail sheets. Successful refreshes still replace cached rows; failed requests retain the previous rows and their original timestamps. The mini-program follows the same rule and separates its manually initiated pull indicator from automatic request activity. The initial no-cache loading/empty states remain independent of failure reporting.

Ignored `work/silent-refresh/` contains before/after native iPhone screenshots, source hashes and `QuietRefresh.xcresult`. The native iPhone 18 Pro simulator (iOS 27, 402×874 pt, actual 3× scale) passes the source-description test with both cached/offline and empty/offline fixtures on AA and Arena: saved rows remain available, failure controls are absent and source sheets contain no network/failure instructions. Four native attachments preserve those cases. The comparison also includes concurrent narrower attribute columns; that column work is not attributed to this failure-presentation change. The final UI-test target compiles after updating the remaining legacy error-button assertions.

Three Swift cache/store tests pass, including failure-to-recovery behavior with unchanged old timestamps until a successful response. All 25 mini-program checks, nine iOS script checks, the iOS simulator app/UI-test builds, the mini-program build and syntax/diff checks pass. Mini-program native failure-presentation verification was not repeated for this change. Physical-device installation remains queued behind the complete repository check gate; no installed-client update or release approval is claimed.

## Mini-program sharing restores all settings (2026-10-15)

Menu sharing now encodes a versioned preference snapshot: category, model/company grouping, active task/vote board, language, appearance preference and all eight boards' country/openness filters. The receiving page applies it before the first render, replaces conflicting local preferences, clears filters absent from the snapshot and persists the result. System-mode links also carry the sender's rendered appearance; receiver system changes or an explicit appearance choice resume local behavior. About-page forwarding and cold-start back navigation preserve the same context. Both Vue Mini pages explicitly enable `canShareToOthers`; previously the framework did not register the menu callback despite the source hook.

All 38 mini-program tests, the production build, syntax and diff checks pass. Tests cover the category/grouping/source/language/theme matrix, all board filters, already-decoded and encoded query parameters, default-filter resets, malformed/future links, old category/face links, local memory, repeated forwarding and about-page navigation. Generated paths remain below 1024 characters for the tested full-filter matrix.

Ignored `work/share-settings/` retains source hashes, an original preferences backup, native results and the received-page screenshot. The actual WeChat developer-tool menu callback returns the state link; native launches over deliberately conflicting receiver preferences restore Video/Companies/User votes/English/Dark plus active and off-category filters. Re-forwarding retains the snapshot. Native system-appearance verification on a light-system receiver shows the sender's dark appearance while preserving the system option; about forwarding and cold-start back retain it. Original preferences and pages are restored after each verification. These checks inspect share metadata and local launches; no message is sent to a contact. No physical-device distribution or release is claimed.

## Mini-program brand initial alignment (2026-10-15)

The cropped A-shaped mark and native I now share an inline baseline. The mark retains I's measured painted height and the existing visible-edge gap; the remaining Chinese/English glyph layout and Canvas exports retain their geometry. Both leaderboard and about templates use the same initial group. This change is confined to the mini-program.

Original WeChat DevTools 2.02.2609231 simulator captures are in ignored work/weapp-brand-alignment/. The simulator viewport is 375×812 CSS pixels and the official MCP capture returns its current 82% display size, 308×666 pixels. Reviewed evidence includes before/after Simplified Chinese light and English light, plus final English dark and Traditional Chinese light. The header is the comparison target; unrelated table styling and content changed concurrently. Chinese dark attempts captured an incomplete compile, then failed with APPID_ERROR (TLS connection disconnected) and no project window; those attempts are not successful visual evidence. The about template passes the build but has no separate final native screenshot in this run.

Validation: all 57 mini-program tests pass; the production build verifies both pages, assets and relative runtime modules. Generated images are not added to Git.


## Mini-program subtitle and grouping padding (2026-10-15)

The leaderboard subtitle increases from 15 to 20 rpx, removes fixed width caps and ellipsis, and wraps whole phrases when the native navigation row needs more space. The help icon stays with the last phrase at a 4-rpx gap. Model/company segments regain 22-rpx horizontal padding and intrinsic widths, including narrow screens. English places the full caption below its title; the header can grow to fit without clipping.

Ignored `work/weapp-header-spacing/` retains original native WeChat before/after captures, source snapshots and `review.json`. At the 375-CSS-pixel simulator width, the subtitle measures 10 px, each segment has 11 px horizontal padding, the grouping control grows from 56 to 84 px, and the text/help gap measures 2 px. Original tool PNGs are 308×666 pixels at the simulator's current display size. Reviewed captures cover Simplified Chinese dark, Traditional Chinese light/dark and English dark. All show complete caption phrases, a nearby help icon and separated controls. The initial system-info request timed out and one interaction during refresh failed; neither is counted as verification. Final reads and captures succeeded. Language/theme preferences were restored to Simplified Chinese/dark.

All 69 mini-program tests and the production build pass. Other viewport widths and physical devices were not captured. Full-frame differences also include changing live board content and concurrent body edits; this report verifies the header.
# Two-line feature subtitle (2026-10-16)

Mac, Windows, iPhone/iPad and WeChat now place the feature caption immediately beside the title in two rows: the ampersand ends the first row, and quota tracking plus its help mark occupy the second. Apple native captions use native font outlines trimmed to the title's painted height; WPF scales two ink-trimmed rows into the same native title span. The mini-program binds the caption's total height to the title and fits both together beside grouping and the WeChat capsule. Its exported comparison also uses two caption rows. Compact Apple headers keep the caption beside the title in every width fallback.

Ignored `work/subtitle-two-lines/review.html` and `review.json` retain 36 original native Mac before/after pairs, identical synthetic fixtures and 850/1300×720-point viewports, three languages, light/dark, and shown/refreshed/settled frames. Metadata records macOS 27.0.1 (26A434), actual 1× scale, the source revision and source hashes. Reviewed frames show complete rows and aligned caption/title edges; trimming the former Chinese caption's line box reclaims one point in the compact header. Native WeChat readback confirms a 32px title and 32px caption in Chinese, with a complete English two-row caption at the smaller shared fit. Seventy-four mini-program tests and its build pass; shared native glyph-bound/render tests pass in all languages and appearances. Mac and iOS simulator builds pass, and Windows Release cross-build reports zero warnings/errors.

Windows native screenshots, actual Windows DPI coverage and a source-matched CI visual artifact are unavailable in this local run. A native iPhone 18 Pro Chinese/light original confirms the inline pair and complete two-row caption at actual 3× scale on iOS 27.0. The English launch-frame capture is blank and excluded. iPad native visual review remains separate from the successful simulator SDK build. No protected release approval or client distribution is claimed.
# Feature subtitle row spacing (2026-10-16)

All feature captions retain the title's overall height while reserving 20% of that span between the two rows. Apple native and Windows captions scale the text into the remaining 80%; WeChat and its export use 40% per row. The ampersand and help mark retain their first/second-row positions. Native WeChat readback confirms a 32px caption with a 12.8px font, reduced from 16px.

Ignored `work/subtitle-air/review.html` and `review.json` compare 36 original native Mac after frames with the matching preceding two-line-caption captures, three languages, light/dark, 850/1300×720-point viewports, shown/refreshed/settled checkpoints, macOS 27.0.1 at actual 1× backing scale. Text is smaller with a visible central gap and unchanged outer alignment; time-dependent freshness ages advance between capture dates. Seventy-eight mini-program tests and the production build pass, the two native caption ink-bound/render tests pass, Mac builds, and Windows Release compiles with zero warnings/errors. iOS consumes the same tested native artwork. No new Windows/iPad native screenshots or source-matched CI visual artifact are available, and no protected release approval is claimed.

## Chinese feature subtitle restored to one line (2026-10-16)

Simplified and Traditional Chinese use one complete `双榜对照 & 余量追踪 ?` / `雙榜對照 & 餘量追蹤 ?` line beside the title, aligned to its painted bottom. English retains two rows. The shared Apple caption uses its native 12-point text size for Chinese; Windows also bottom-aligns a single native caption. WeChat fits the wider Chinese title/caption pair beside grouping and the capsule, and its exported image follows the same language-specific row choice.

Ignored `work/subtitle-single-line/review.html`, `review.json`, `source.json` and original captures retain 36 native Mac before/after pairs with the same synthetic fixture, three languages, both themes, 850/1300×720-point viewports and shown/refreshed/settled frames. Actual environment: macOS 27.0.1 (26A434), 2× backing scale. Header review confirms complete Chinese captions, the help mark on the same line and no overlap with adjacent controls; English keeps its two-row arrangement. Both focused shared native caption tests, mini-program tests (78) and production build pass; Windows Release cross-compilation passes with zero warnings/errors. All twelve header states in each capture phase remain pixel-identical across shown/refreshed/settled checkpoints.

Windows native screenshots/actual DPI, new iPhone/iPad and WeChat native captures, and a source-matched CI visual artifact remain unavailable. The shared Apple view compiles for Mac and the mobile UI target; this does not substitute for device visual review. No protected release approval or distribution is claimed.

## Narrow subtitle sizing (2026-10-16)

Chinese subtitles retain one line and reduce their type size when constrained. The shared Apple caption accepts the proposed width, scales text and symbols together down to 65% while preserving its painted bottom edge, and allows the existing smaller-title fallbacks to handle further constraints. The phone/iPad header no longer fixes the caption at its intrinsic width; the Mac heading forwards available width. WeChat prioritizes reducing the Chinese caption before shrinking the title, with responsive help-icon sizing. Its existing header test now includes 280–430px viewports.

Both focused shared native tests, all 78 mini-program tests and the production build pass. `work/subtitle-narrow/captions/` retains twelve native SwiftUI ImageRenderer originals covering three languages, both themes, natural and constrained widths (Chinese: 78px), with geometry assertions checking the complete ink bounds and bottom alignment. These are shared-view renders on Mac, not iOS device screenshots. `work/subtitle-narrow/review.html`, `review.json` and `source.json` retain 36 Mac before/after original pairs using the previous matching synthetic fixture and 850/1300×720-point viewports, macOS 27.0.1 (26A434), actual 2× backing scale. Header review confirms the complete single-line Chinese caption at supported desktop widths.

This adjustment leaves WPF unchanged. Current Windows native screenshots/DPI, iPhone/iPad and WeChat native simulator/device captures, and a source-matched CI visual artifact remain unavailable. No protected release approval or distribution is claimed.

## WeChat grouping control matches capsule height (2026-10-16)

The model/company switch binds its outer height to the native WeChat menu capsule measurement, including resizing. At a 32px capsule it uses an 80px Chinese / 120px English width with 12.8px / 10.88px text, centered inside a 2px inset. The title/caption fit now reserves this measured control width. Chinese captions shrink first and retain a 6.5px font at the tested 320px-and-wider viewports before the title consumes the remaining space.

All 78 mini-program tests and the production build pass. The existing header check covers 280–430px widths, 28/32/36px capsule heights and all three languages, checking exact grouping/capsule height equality and positive title/caption dimensions. Logs are retained under ignored `work/grouping-capsule/`. The official WeChat MCP and its skill are unavailable in this session, so no native simulator screenshot, interaction review or physical-device visual verification is claimed.

## Gentler mini-program cube entrance (2026-10-16)

The first-entrance rotation is halved: initial tilt is 8.1° instead of 16.2°, and peak tilt is 12.6° instead of 25.2°, mirrored for either saved board. Vertical travel drops from 12px to 6px and the scale change from 1.5% to 0.75%. Existing timings, opacity, hint and interruption behavior stay in place.

All 78 mini-program tests and production build pass, including both saved faces, selection preservation and touch/background cancellation. Logs remain in ignored `work/cube-gentler-entrance/`. Native WeChat tools are unavailable in this session; no simulator recording or physical-device motion review is claimed.

## GPT expiry does not inherit a monthly usage reset (2026-10-17)

Official GPT cards now require an explicit active subscription and a non-placeholder entitlement date. A missing plan boundary no longer falls back to the monthly usage reset for its date phrase, deadline color or sorting. Verified dates are preserved without rolling forward; Kimi monthly periods retain their existing behavior.

`work/openai-expiry-fix/review.md`, source hashes, fixture and logs retain local evidence. All 67 focused tests pass. The wider Swift run passes 457 of 458 tests, with an unrelated xAI invalid-grant classification failure in the concurrently modified refresh path. Native Mac review covers three languages, light/dark, 600×600 and 900×600 content viewports, macOS 27.0.1 (26A434), actual 1× scale. All 12 settled frames show quota text without an invented date; quota/header pixels are identical across all 36 checkpoints, with full-frame changes confined to the fading table scrollbar. The new scenario is included in `Tests/fixtures/openai-plan-expiry.json`.

Windows native captures/actual DPI and a matching source-revision CI artifact remain unavailable. The original account's live entitlement response was not captured. No Windows visual sign-off, protected release approval or installed-app update is claimed.
## Unknown country help and cached model identities (2026-10-17)

Missing country values now expose a question-mark button and a generic explanation in Mac, Windows, iPhone/iPad and WeChat. Exact model IDs repair cached display-name mismatches before choosing that unknown state. Verified public-weight metadata fills the exact InternLM2.5 20B Chat release; explicit source classifications and ambiguous coding combinations retain their existing handling. The Mac question mark preserves the prior row height.

Ignored `work/country-help/review.html` and `native-review.json` retain the synthetic fixture, before/after native Mac bundles, source hashes and original captures. Each phase contains 36 frames: English/Simplified/Traditional, light/dark, model/company grouping, 1100×720-point content viewports, shown/refreshed/settled checkpoints. Actual environment is macOS 27.0.1 (26A434), 1× backing scale. Review covers an unassigned community project, an ID-resolved Yi Lightning row, existing flags, long names and empty company placeholders. Shown/refreshed frames match; settled differences are confined to the fading native scrollbar at the right edge. Intentional differences include the resolved company row and its country/brand identity.

The official WeChat simulator successfully opens the country explanation after a real button tap; its retained original capture is only 93×200 pixels at the current simulator display size, so it is evidence of the opened modal, not a detailed typography review. Rebuilt about-page data confirms removal of both requested phrases. Windows WPF cross-compiles with zero warnings/errors. Current Windows native screenshots/actual DPI, new iPhone/iPad native captures, and a source-matched CI artifact are unavailable. No protected review approval, installed-client replacement or release publishing is claimed. The cache audit and unresolved metadata are documented in `docs/cached-metadata-audit.md`.


## Unavailable quota results sort after confirmed results (2026-10-17)

Network errors, failed queries, expired logins, unconfigured accounts and empty quota responses now sort after confirmed quota/balance results, before pending queries. Status is checked before provider billing type, so neither a failed plan nor a failed metered wallet inherits usable-result priority. Confirmed groups retain their existing order and expiry sorting. Unavailable results keep stored order, including the current provider; a successful retry returns the card to its normal billing group. Retained successful cached values keep their data-based priority.

All 35 focused Swift catalog/formatting tests pass, including every supported provider, both current-selection states, both input orders, stable failures and recovery. Eight visual-fixture checks and the Windows shared harness (39 cases) pass. The shared bridge supplies Windows with the same sorted projection. The new `quotaErrorSort` scenario is included in the default shared visual fixture.

Ignored `work/quota-error-sort/review.html`, `review.json`, source hashes and the identical synthetic fixture retain 36 original native Mac before frames and 36 after frames. Captures cover English/Simplified/Traditional Chinese, light/dark and 600/900 × 820-point content viewports, with shown/refreshed/settled checkpoints. On macOS 27.0.1 (26A434), actual 1× backing scale, review confirms errors follow confirmed results and all cards wrap without overlapping the table. All twelve reviewed header/quota bands are stable across the three checkpoints. Supplemental crop sheets preserve native pixels; full originals remain linked.

Windows native screenshots, actual Windows DPI coverage and a source-matched CI `native-visual-comparison` artifact are unavailable in this local run. No Windows visual sign-off, protected release approval or installed-client replacement is claimed.

## Mini-program cube top boundary (2026-10-17)

The rotating faces now start below the visible source tabs. Their scroll views retain the original viewport and scroll offsets, while clipping excludes the source-tab spacer from each face and its shadow. As tabs collapse, the face boundary rises by the same amount; no spacer rotates above the date/summary row.

Official WeChat DevTools MCP captures in ignored `work/weapp-cube-top/` cover the canonical mini-program, a 375×812 CSS viewport, and original 510×1105 simulator output at the current IDE display size. `before-top-turn.png` and `after-dark-turn.png` are the English dark comparison. Simplified Chinese light captures cover top resting/turning, reverse turning, and resting/turning after a native 500px scroll. Reviewed originals show the face starting at content, intact dates/table headings, and tabs returning after back-to-top. Runtime measurements confirm a 50px face inset at the top and 0px after scrolling. Held rotation frames use the page's actual cube handlers through MCP; these are simulator checks, not a physical-device motion review.

All 113 mini-program tests and the production build pass. Logs remain alongside the ignored captures. This change affects only the mini-program; no desktop visual changes or release publishing are claimed.

## Mini-program proportional name backgrounds (2026-10-17)

Name backgrounds now form left-aligned score bars. The leader retains its full original cell width; subsequent backgrounds use the exact score/leader ratio, capped at 100%. Text, icons and purchase actions keep their original layout width. Zero scores produce no fill, and an unusable baseline retains the prior full background. Search results retain the unsearched leader as their baseline. The exported comparison uses the same ratio and rounded bars, including zero-width handling.

Reviewed official WeChat simulator originals remain under ignored `work/weapp-score-bars/`: English dark before/after at the top; Simplified Chinese light top and 900px scrolled model rows; company rows with purchase buttons; and Qwen search results. Native geometry confirms all first-column bars start at x=44 CSS pixels: the first spans 186px and the second spans 180.75px for a 97.1847% score ratio. Original output is 510×1105 at the current IDE display size, with a 375×812 CSS viewport. Short bars leave longer names readable over the cell background; buttons retain their hit areas. This is mini-program simulator evidence, not a physical-device or desktop review.

All 115 mini-program tests and the production build pass. Regression checks cover ratios, zero/invalid baselines, search stability, and exported bar geometry without changing name wrapping. Build/test logs remain beside the ignored captures. Focused lint additionally reports two existing unused imports (`canReplace`, `latestTimestamp`) in the shared, concurrently edited leaderboard module. No release publishing is claimed.


## Optional Codex task status (2026-10-17)

The existing macOS task-count projection is now opt-in through a footer switch. New and upgraded installs default off; both choices persist across launches. Disabled status removes running/unread/failed counts, unavailable placeholders, highlight attributes and task tooltip content. Re-enabling restores the existing projection when the desktop app is running. Narrow panels use a two-row footer so the switch, language picker and quit control remain reachable. Windows does not currently implement task counting; this change adds no inactive Windows switch.

The two new preference tests and eight existing task-status tests pass, as do eight visual-fixture checks. Existing menu-bar fixtures explicitly enable task status to preserve their coverage. `Tests/fixtures/codex-task-toggle.json` covers enabled/disabled footer states and both directions of menu-bar transitions, three languages, light/dark, and 600/900 × 720-point content viewports. The native test clicks the actual NSSwitch twice in every footer state, checks its bounds, verifies AppState and persisted preferences, and restores the original choice. The status-button cases assert text/tooltip visibility and nonzero color highlights at shown/refreshed/settled checkpoints.

Ignored `work/codex-task-toggle/review.html`, source hashes, `review.json`, and original captures retain the identical synthetic before/after fixture: 144 original frames per phase, comprising 24 footer and 24 status-button states. Final evidence is in `verified/`; the earlier `after/` run predates the narrow-footer layout repair and is excluded from final verification. On macOS 27.0.1 (26A434), actual 1× scale, review confirms complete footer controls and immediate task-block transitions. Supplemental crop sheets retain native pixels and link to complete originals.

Windows native screenshots, actual Windows DPI verification and a source-matched CI `native-visual-comparison` artifact are unavailable on this host. No Windows visual sign-off, protected release approval or installed-client replacement is claimed.

## Proportional name backgrounds on the remaining native clients (2026-10-17)

Mac, Windows and iPhone/iPad now match the mini-program's left-aligned score backgrounds. The leader retains the original full cell width; subsequent bars use the exact score/leader ratio, capped at one. Zero scores remove the fill; invalid baselines preserve the previous full fill. Background layout is independent of names, logos and purchase actions. SwiftUI shares `LeaderboardScoreBackground` and its ratio rule, including the Apple exported comparison view. WPF uses proportional background-only grid columns while retaining the full transparent hit target, existing margins and name layout.

Ignored `work/native-score-bars/review.html`, `review.json`, source snapshots, fixture and logs retain the local evidence. Mac has 36 before and 36 after original native frames: English/Simplified/Traditional Chinese, model/company grouping, light/dark, and shown/refreshed/settled checkpoints. Both phases use the same fixture and 1100×720 content viewport on macOS 27.0.1 (26A434), actual 1× scale. Reviewed originals show unchanged full leader/tie backgrounds, progressively shorter lower backgrounds and intact names/links. Across all twelve cases, refreshed/settled changes are confined to the native fading scrollbar. Source snapshots differ only in this background implementation.

Three focused Swift tests pass: exact ratio boundaries, existing score annotations, and native Apple export rendering. The export matrix retains 24 original renders across three languages, both themes, wide/narrow layouts and both App Store credit states. These native SwiftUI images confirm the shared exported row layout; they are not mobile device screenshots. Mac and both before/after universal iOS Simulator SDK builds pass. The Windows shared harness passes its existing 39 cases plus the new ratio boundaries; final WPF Release cross-compilation has zero warnings/errors.

Native phone/pad capture did not complete: local disk exhaustion interrupted simulator capture and a test link. Only a phone baseline exists and it is excluded from after-validation. Task-generated build caches and the two temporary devices were cleaned up; the focused Swift/export rerun then passed using full Xcode. The initial Command Line Tools test attempt also lacked the SwiftUI State macro plugin. No current Windows native screenshots/actual DPI review, complete mobile before/after captures, physical-device review or source-matched CI artifact is claimed. The build snapshots isolate this change from concurrent work. No installed client replacement, release publishing or protected approval is claimed.

### 2026-10-17 — Mobile bars span all columns after rank

Scope: the mini-program and iPhone/iPad shared leaderboard now place the proportional brand fill behind the entire region after rank, including name, country, source (model grouping) and score. Rank remains outside the brand fill. Company grouping uses the same extent without a source column. Name wrapping, controls, column widths and exact score ratios are preserved. Mac and Windows implementations are unchanged by this follow-up. The mini-program canvas export and Apple mobile image export match their mobile rows.

Evidence in ignored `work/mobile-row-bars/`: original 510×1105 mini-program simulator captures `before-dark.png`, `after-dark.png`, `after-light.png`, `after-company.png`; inspected all originals. The runtime reports a 312 CSS-pixel track from x=44 to x=356, rank x=19…41 and score x=319…356. Lower bars share x=44 and scale by score; the leader reaches the score edge. Company purchase links and model source icons remain visible and aligned. These are actual DevTools simulator captures, not phone captures.

Validation: 115 mini-program tests and the normal production build passed. The focused canvas export suite passed again after extending its proportional-width assertion to model/company grouping in both themes (410, 205 and 0 export pixels for 100%, 50% and zero). Shared SwiftUI compilation and the native ImageRenderer layout matrix passed using the full Xcode toolchain: English/Simplified/Traditional Chinese, published-fixture/unpublished credits, narrow/wide and light/dark (24 images). Reviewed the narrow Chinese light and wide English dark originals under `work/native-score-bars/unit-source/work/ios/previews/`; before copies are retained in `work/mobile-row-bars/`. These native image exports verify the shared rendering path, but live iPhone/iPad simulator or physical-device interaction remains unverified in this follow-up. No desktop visual change or release approval is asserted.

## Desktop score percentage colors (2026-10-17)

Mac and Windows now color the small score percentage blue for Artificial Analysis boards and purple for Arena boards, matching the mobile source convention. The desktop score remains secondary text; percentage font size, placement, hiding rules, score bars and column layout are unchanged. Mac image export captures this same native view.

Ignored `work/pc-share-color/` retains the frozen source, same synthetic fixture as the earlier score-bar review, native before/after Mac app bundles and 36 original frames per phase. Captures cover English/Simplified/Traditional Chinese, model/company grouping, light/dark, and shown/refreshed/settled checkpoints at 1100×720 points on macOS 27.0.1 (26A434), actual 1× backing scale. The before view source hash matches the pre-edit working view. Reviewed full English model light/dark, Simplified Chinese model light and Traditional Chinese company dark originals show visible blue/purple annotations without shifting score text or controls. `review.html` links the complete original comparisons and `review.json` records pixel comparison results and environment metadata.

Both native Mac compilation and Windows WPF Release cross-compilation pass; Windows reports zero warnings/errors. The isolated Mac source also emits an existing weak-self capture warning in AppState. Native Windows captures, actual Windows DPI coverage and a source-matched CI `native-visual-comparison` artifact remain unavailable on this host. No Windows visual sign-off, installed-client replacement, release publishing or protected review approval is claimed.

## Desktop single-line model centering (2026-10-17)

Mac and Windows center each model's logo/name group within the name column when there is spare horizontal space. Constrained names keep the existing single-line truncation behavior; company names and purchase links keep their previous alignment. Score background tracks, columns, scores and mobile layouts are unchanged.

Ignored `work/pc-model-center/` retains the identical synthetic fixture, original before sources, frozen final Mac sources, hashes, build logs, `review.html` and `review.json`. Each phase has 42 original native Mac frames: English/Simplified/Traditional Chinese model views at 600/1100×720 points, an English company control at 1100×720, both appearances, and shown/refreshed/settled checkpoints. On macOS 27.0.1 (26A434), actual 1× backing scale, reviewed originals confirm centered short names, preserved long-name truncation and unchanged company rows. The narrow viewport's pre-existing severe name truncation remains visible in both phases. All refreshed/settled differences are confined to the native scrollbar strip; company before/after frames are identical.

Native Mac compilation and Windows WPF Release cross-compilation pass (Windows: zero warnings/errors). Windows native before/after screenshots, actual Windows DPI and a source-matched CI `native-visual-comparison` artifact remain unavailable on this host; Windows visual alignment is not signed off. No installed-client replacement, release publishing or protected review approval is claimed.

## Clear Codex task-count toggle label (2026-10-17)

The Mac footer now says “Codex 任务统计” / “Codex 任務統計” / “Codex task counts”, including compact layouts. Its tooltip explicitly describes running, unread and failed task counts in the menu bar; the accessibility label also names the menu bar. Toggle state, persistence and counting behavior are unchanged. Windows currently has no equivalent Codex footer control.

Ignored `work/codex-task-label/` retains the identical synthetic fixture, before source, source hash, build log and native before/after originals (36 per phase): three languages, 600/900×720-point viewports, both themes, shown/refreshed/settled. The Mac build and native fixture interactions pass, including clicking and persisting both switch states in every case. Reviewed originals show complete labels and controls; 600-point layouts use the existing stacked footer. Refreshed/settled differences remain confined to the fading scrollbar. Actual environment: macOS 27.0.1 (26A434), 1× backing scale. No Windows native capture or source-matched CI artifact is available; no release approval or installed-client replacement is claimed.

## Native row logo padding and iOS appearance selection (2026-10-18)

The iOS Debug app entry applied a second `preferredColorScheme`, overriding the saved appearance selected in the page. The page now owns the preference; UI fixtures set only its initial saved value. Real menu choices can subsequently select light, dark or system appearance. Mac, Windows and iPhone/iPad row logos now display the original artwork without an added white tile, inset or boundary stroke, matching the mini-program's treatment. The 20-point native layout slot and aspect ratio are preserved. Missing-logo letter placeholders retain a white background for readability.

Ignored `work/ios-logo-theme/review.html` and `review.json` retain original native screenshots, source hashes, result bundles and comparisons. The iPhone 18 Pro runs iOS 27.0 at actual 3× (1206×2622 pixels); the iPad Pro 11-inch M5 runs iPadOS 27.0 at 2× (1668×2420). One focused appearance test passes on each device, covering English/dark and Chinese/light starts, both explicit theme choices, return to system mode and the About sheet. Pixel checks inspect the rendered background. The old iPad implementation fails after selecting Light from a dark start, reproducing the reported issue. The preliminary before-phone bundle failed before tests because the isolated review project omitted localization files; that attempt is excluded from evidence.

Four successful logo-test runs retain 24 before and 24 after originals across the two devices, Chinese/light and English/dark, model/company grouping and shown/refreshed/settled checkpoints. Fixtures include cached MiMo/StepFun images, bundled marks and a missing-logo fallback. All 16 refreshed/settled comparisons are identical below the status bar. Before/after differences below that bar are confined to the logo columns: text, scores and layout do not shift. Reviewed originals show the extra white surrounds removed while preserving rounded artwork and readable names. The theme-specific runs retain another 24 after originals and one valid baseline image.

Mac retains 60 updated native AppKit/SwiftUI frames in `work/ios-logo-theme/after-mac/macos`, compared with the 60 earlier originals in `work/desktop-name-alignment/before/macos`. Both use fixture SHA-256 `31d620116eae774cc0f19694e88dde1528885ccecfa350108bc9d509343b72a8`, matching 900/1100×720-point viewports, three languages, light/dark themes, model/company modes and empty/error scenarios. Actual environment: macOS 27.0.1 (26A434), 1× backing scale, local uncommitted sources. All 20 refreshed/settled content comparisons are identical after excluding the rightmost 12 pixels containing the fading native scrollbar; full frames retain that animation. Review confirms unpadded row artwork, restored left alignment for model names and existing long-name truncation. The retained baseline also precedes the name-alignment correction, so its text-position differences are intentional.

Windows WPF Release cross-compilation passes with zero warnings/errors. Windows native screenshots, a source-matched cloud CI artifact and physical-device installation are not part of this run. The repository-wide check had unrelated watcher-test timeouts and was interrupted after failure; this focused review does not count as a passing full gate or authorize protected release publishing.


## Remove the extra desktop metadata row (2026-10-18)

Mac and Windows remove the explanatory source summaries and updated/fetched timestamps immediately above the table header. Mac preferred panel height no longer reserves that row; the WPF table now consists of the header and scrolling rows. This removes the extra band rather than leaving an empty layout slot.

Ignored `work/desktop-header-row/review.html` and `review.json` retain source hashes, original source snapshots, build logs and 60 after native Mac frames, paired with the 60 immediate baseline originals in `work/ios-logo-theme/after-mac/macos`. The identical fixture hash is `31d620116eae774cc0f19694e88dde1528885ccecfa350108bc9d509343b72a8`; both phases use 900/1100×720-point viewports, English/Simplified/Traditional Chinese, model/company grouping, both themes and quota empty/error states. Actual environment is macOS 27.0.1 (26A434), 1× backing scale, local uncommitted sources. Review confirms the table header moves up, the description/time band is gone, and neighboring controls and long-name truncation remain intact. All 20 refreshed/settled content comparisons are identical outside the rightmost 12 pixels containing the fading native scrollbar; full originals retain that animation.

Native Mac compilation and Windows WPF Release cross-compilation pass (Windows: zero warnings/errors). Native Windows screenshots, actual Windows DPI review and a source-matched CI artifact are unavailable; Windows visual approval is not claimed. These captures do not replace the installed application or constitute protected release approval.


## ECI source tab caption — 2026-10-18

The ECI method caption now reads “能力指数” / “能力指數” /
“Capability index” in the shared Apple presentation, Windows source tabs and
mini-program cube tabs. Source titles and links still identify Epoch AI / ECI.
This keeps the Chinese caption at four characters alongside the existing
task-benchmark and user-vote captions.

The existing mini-program page tests and production build pass. The official
WeChat DevTools MCP confirms the canonical `apps/weapp` project is imported
and reuses its window, but `automation_runtime_info(currentPage)` times out;
no simulator visual verification is claimed. Native Windows screenshots are
unavailable on this macOS host. Mac before/after capture evidence is retained
in ignored `work/eci-tab-label/`; captures use the same fixture and viewport,
with Simplified/Traditional Chinese and English, light/dark themes, and
850/1100-point widths. Capture status and review are recorded in that folder.


## Desktop leaderboard visibility (2026-10-18)

The footer now has a localized, checkable leaderboard menu. Each category defaults to all its sources (three for General); at least one stays selected. Selection persists per category. Mac uses one to three source groups in the native table, hiding unused AppKit columns; WPF builds only the selected column groups. The former second-source picker is removed. Headers, filters, score precision, source links, timestamps and exported screenshots follow the selection.

Both desktop request paths filter before fetching, including the Windows bridge's shared-cache read. Disabling a source cancels its requests and rejects late results. Per-source throttles retain other sources' refresh limits; cancelling an unfinished request allows that source to be fetched when re-enabled. Windows sends its current selection to the engine, guards old UI responses, and the engine ignores older selection request IDs.

Ignored `work/desktop-board-selection/` retains the fixture, before/after source snapshots, build logs, original native Mac captures, hashes, `review.html`, `review.json` and frame comparisons. Each phase has 54 originals: English/Simplified/Traditional Chinese, 600/850/1100/1200/1300/1400×850-point viewports, both appearances, model/company rows, quota empty/error states and shown/refreshed/settled checkpoints. The fixture SHA-256 is `0620962e631bd3d4432d3ea41078aa1685db96ffc349128eadf94d36b2b22983`. macOS 27.0.1 (26A434) uses actual 1× backing scale; Original PNG pixel dimensions match the 1× content viewport; the PNGs have no DPI tag. Binary/source hashes are recorded in the review. Native assertions verify the selected column count and viewport fit or usable horizontal scrolling. At 600 points, overflow is scrollable; refreshed/settled frames pan to the right and assert a nonzero scroll offset. All 36 refreshed/settled content comparisons are identical outside the native scrollbar strips.

Reviewed originals confirm three sources fill the table, AA+Epoch keeps the correct filters and two-decimal ECI scores, and single-source views fill the width without empty source columns. The three-to-one fixture changes selection between shown and refreshed frames. Footer controls stay visible at 850 points. Existing long-name truncation remains and is more frequent with three sources at a fixed viewport. Completely empty leaderboard/skeleton rendering is outside this native capture set.

Windows WPF Release cross-compilation passes with zero warnings/errors, and the shared harness verifies defaults, persistence, minimum selection, category isolation and invalid preference recovery. Native Windows screenshots, actual Windows OS/DPI comparison and a source-matched cloud CI artifact are unavailable; Windows visual approval is not claimed. The shared CI fixture and both native capture runners include the new selection scenarios. No protected release approval is asserted.

Final verification: `./test.sh --coverage` passes on the final source state. The existing 59-file Swift business scope remains 100% for lines (9212/9212), functions (1453/1453) and regions (4566/4566); script coverage checks and the Windows shared harness also pass. The final WPF Release cross-build has zero warnings/errors.


## ECI relative score presentation — 2026-10-18

All clients now supply ECI's leading filtered/grouped score to the same ratio
formatters as the other sources. Percent captions and proportional name fills
use the unsearched leader; searching does not rebase the result. Original ECI
scores retain two decimal places. Existing invalid-baseline and rounded-100%
caption omission rules apply equally to ECI.

Regression coverage includes an ECI leader above 100, model/company grouping,
openness filtering, model search, virtualized page rows and mobile paging.
Native Mac before/after originals and review metadata are retained in ignored
`work/eci-relative-scores/`, using identical fixtures and 850/1100×720-point
viewports, three languages, both themes and shown/refreshed/settled checkpoints.
Windows native screenshots and a source-matched cloud CI visual artifact are
unavailable on this host; Windows visual approval is not claimed. Mini-program
runtime connection failures, if any, are recorded with the task evidence.

## ECI scoring-method label — 2026-10-18

The ECI method caption now reads “难度校准” / “難度校準” /
“Calibrated tests”, alongside the existing task-benchmark and user-vote
captions. “Capability index” names the resulting metric rather than the scoring
method. ECI is also based on task benchmarks; its summary now explains that it
estimates general capability while accounting for benchmark difficulty and
discrimination. This is a description of its distinguishing calculation, not a
claim that ECI and task benchmarking are disjoint evaluation categories.

Methodology: https://epoch.ai/data/eci-documentation/methodology

Native local Mac before/after evidence is kept in ignored
`work/eci-method-label/`, using the same fixture and viewport in each pair,
with English, simplified/traditional Chinese, light/dark themes and
shown/refreshed/settled frames. Source hashes and actual OS/backing scale
are recorded with the comparison. Other uncommitted working-tree changes are
kept separate from this commit. Windows native screenshots and a source-matched
CI comparison artifact remain unavailable; no protected release approval or
Windows visual verification is claimed.

## Country and source distributions — 2026-10-18

Each selected leaderboard now has an independent model-count summary below its
ranking. Country uses descending horizontal bars (five named countries, the
remaining known countries as Other, and Unknown separately). Source openness
uses a 100% stacked bar with open, closed and unknown counts. Missing metadata
stays in the denominator; scores do not weight the counts. Search, country and
openness filters, and company aggregation do not change the full-board summary.
Hong Kong, Macao and Taiwan follow the shared China normalization policy.

Mac keeps the virtualized table and reserves its scrolling tail for a native
SwiftUI chart host beside the AppKit document view. The fixed footer and sticky
header retain their positions. WPF uses a final item in its virtualized list;
the bridge supplies counts from raw models before company aggregation. iPhone,
iPad and mini-program charts precede About, language and appearance controls.

Local native before/after fixtures, originals and verification metadata are in
ignored `work/board-distributions/`. Scenarios cover one/two/three boards,
850–1600 point widths, all supported languages, light/dark themes, empty data,
company mode and long names, with shown/refreshed/settled frames. iPhone/iPad
use offline model fixtures; the mini-program is checked in the canonical
DevTools project with cached leaderboard data. See that directory's report
for completed checks and any remaining environment coverage.

Windows cross-compilation and shared checks can run on this Mac. Native Windows
screenshots, actual Windows OS/DPI comparison and a source-matched cloud CI
artifact remain unavailable; no Windows visual approval or protected release
approval is claimed.

The six `distribution-*` cases in the shared `Tests/fixtures/visual-state.json`
also exercise these tails in future native comparisons. Country bars follow the
platform's restrained accent styling; the source palette and counting policy
are shared. Mac retains its existing minimum placeholder-row count, while WPF
retains its variable list length. Empty chart text remains readable even while
the Mac ranking is showing a loading skeleton.

## Arena official dataset attribution — 2026-10-19

Mac and Windows source descriptions, About where available, and shared-image exports retain Arena's author/dataset credit, official Hugging Face link, CC BY 4.0 link, processing description and non-endorsement statement. iPhone/iPad and mini-program help, About and exports carry the same notice. Arena dataset publication dates retain date precision; acquisition time stays separate. Legacy website snapshots are not labelled as licensed dataset records.

The shared fixture adds six cases: Arena only at 850×720 and all general boards at 1100×720, English/Simplified/Traditional Chinese, both themes. The native Mac fixture reader now preserves sourceNote through reconstruction so these cases exercise the actual conditional notice. Ignored `work/arena-dataset/` retains capture intent, the fixture, original native captures, metadata, hashes, `review.html` and `verification.json`. Each phase contains 36 originals with shown/refreshed/settled checkpoints. macOS 27.0.1 (26A434) reports actual 1× backing scale. Reviewed English minimum-width/light, Chinese minimum-width/dark and Traditional Chinese three-board/dark originals show complete notice lines without clipping. All twelve final refreshed/settled pairs are pixel-identical.

The retained before binary predates the earlier Epoch attribution and concurrent workspace edits; it is an older baseline, not a source-matched full-workspace before build. Windows native WPF screenshots, real Windows DPI review, a source-matched CI comparison artifact, mini-program live simulator review and separate phone/tablet native visual review are unavailable in this run. Build checks and Canvas export bounds tests do not replace those reviews. No protected visual release approval is implied. Backend acquisition and OSS migration are independently verified against all rows of the official four Parquet snapshots; see [migration record](arena-dataset-migration.md).
