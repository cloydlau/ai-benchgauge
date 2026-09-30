# Native visual comparison

Run `.github/workflows/visual-parity.yml` to capture the real WPF window on a Windows desktop and the real AppKit / SwiftUI view on macOS. The workflow uploads both sets of PNGs, capture metadata, and a standalone `native-visual-comparison` HTML report. Changes to either desktop interface trigger this workflow after it is merged.

The report supports side-by-side images, opacity overlays and a pixel difference view. Select the case, checkpoint and Mac theme. These are native screenshots, not a browser imitation of the Windows interface. Compare layout and missing features; native typography and anti-aliasing do not require pixel equality.

## Current coverage

`tests/fixtures/visual-state.json` supplies public, synthetic data to both interfaces. The first fixture covers 20 rows, long English and Chinese names, three languages, 900 and 1100 logical-pixel content widths, normal quotas, six quotas, missing CC Switch, refresh errors with cached rows, and window mode. Each case captures three checkpoints: shown, refreshed and settled. Mac captures both light and dark appearances. Windows currently uses its existing fixed light appearance.

The report checks the fixture SHA-256 (with CRLF normalized to LF) and the Windows client dimensions before combining images. It refuses mismatched fixtures or incomplete capture sets. Capture metadata records OS, real DPI/backing scale, timezone and the capture method.

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

## First-pass differences

The committed Windows interface and Mac interface currently differ structurally: independent Windows board scroll areas and duplicated ranks, 25-DIP versus 32-point rows, missing company tint bars/medals/country columns, generic dropdowns and buttons, larger quota padding without provider logos, a left-aligned empty-state link instead of a centred placeholder, large unused vertical space, and no dark theme. These differences are visible in captures and supported by the view code. Capture and review the affected states before changing those styles; then rerun the same cases for a before/after comparison.
