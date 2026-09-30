# Native visual comparison

Run `.github/workflows/visual-parity.yml` to capture the real WPF window on a Windows desktop and the real AppKit / SwiftUI view on macOS. The workflow uploads both sets of PNGs, capture metadata, and a standalone `native-visual-comparison` HTML report. The main Checks workflow calls it on every PR and push to main, without path filters that could skip a shared-core or resource change. The release workflow calls the same workflow for the tagged revision with human review required.

The report supports side-by-side images, opacity overlays and a pixel difference view. Select the case, checkpoint and Mac theme. These are native screenshots, not a browser imitation of the Windows interface. Compare layout and missing features; native typography and anti-aliasing do not require pixel equality.

## Required development and release procedure

1. For a desktop interface change, capture before and after the change with the same fixture. Add a scenario if the affected state is not covered. Keep both artifacts or local captures for review.
2. Open the CI run's **comparison** job summary and download `native-visual-comparison`. Open `comparison.html` offline; review shown/refreshed/settled, both Mac themes, languages and widths for the affected states. Use side-by-side, overlay and difference views to inspect alignment, clipping, spacing and missing features. Different native font rasterization is not automatically a bug.
3. Link the run/report and record intentional differences and unresolved problems in the PR template. `AGENTS.md` makes this part of subsequent UI development. A green capture job verifies the capture set, not aesthetic acceptance.
4. Every release tag captures its own revision again. After the report is ready, `review-policy` verifies that the repository environment **native-visual-review** exists and has a required human reviewer. A missing environment, empty reviewer list or API failure blocks the release; it cannot silently become an unprotected environment.
5. The **review** job waits for the environment's reviewer. Review the report linked from the waiting job (or comparison job summary), record review notes in the GitHub approval comment, then approve or reject it. The `publish` job needs the entire visual workflow to succeed. Capture failure, rejection or cancellation prevents publishing. Agents must never approve or bypass the environment on behalf of a human.

The environment is configured in **Settings → Environments → native-visual-review** with the repository owner as required reviewer. Preserve required reviewers when editing its settings; an explicit administrator bypass is outside this procedure and must not be used to skip visual review. GitHub controls this waiting job through its [environment approval rules](https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments). CI only reads environment policy; it cannot create reviewers or approve its own run.

To test the gate without publishing a release, run **Native visual comparison** manually with `require_review=true`. It should capture both platforms, verify policy and wait for human review; cancel this rehearsal after confirming that behavior. With the default `false`, manual runs only generate the report. CI artifacts are retained for 30 days; save reviewed release evidence before that expires when needed.

## Current coverage

`Tests/fixtures/visual-state.json` supplies public, synthetic data to both interfaces. The first fixture covers 20 rows, long English and Chinese names, three languages, 900 and 1100 logical-pixel content widths, normal quotas, six quotas, missing CC Switch, refresh errors with cached rows, and window mode. Each case captures three checkpoints: shown, refreshed and settled. Mac captures both light and dark appearances. Windows currently uses its existing fixed light appearance.

The report checks the fixture SHA-256 (with CRLF normalized to LF), both client dimensions, actual PNG dimensions, both Mac themes and every frame. In CI both captures must record the exact `GITHUB_SHA`; an older capture cannot be reused as this revision. It refuses mismatched fixtures, incomplete/duplicate metadata or incomplete capture sets. Local reports without a verified source revision are explicitly marked as such and are not release evidence. Capture metadata records OS, real DPI/backing scale, timezone and the capture method.

The Windows runner is **Windows Server 2022 at its reported DPI**, usually 100%. This does not certify Windows 10/11, 125%/150% scaling, multiple monitors or every language/font installation. Do not simulate DPI by scaling a PNG and describe it as a native capture. Obtain those screenshots on the relevant desktop with the same fixture. The three checkpoints do not constitute a continuous animation recording. Company grouping, other categories, opened menus, installed-but-empty CC Switch and update/auth dialogs remain to be added.

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

## Initial findings (2026-10-01)

The committed Windows interface and Mac interface currently differ structurally: independent Windows board scroll areas and duplicated ranks, 25-DIP versus 32-point rows, missing company tint bars/medals/country columns, generic dropdowns and buttons, larger quota padding without provider logos, a left-aligned empty-state link instead of a centred placeholder, large unused vertical space, and no dark theme. These differences are visible in captures and supported by the view code. Capture and review the affected states before changing those styles; then rerun the same cases for a before/after comparison.
