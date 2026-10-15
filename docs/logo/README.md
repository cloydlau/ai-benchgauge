# AI BenchGauge logo

The selected **D — Neural network** mark uses three input nodes, two intermediate
nodes and one output. The selected **C — Deep sea teal** palette pairs an ink-teal
tile with mint nodes and a teal-to-mint gradient following the upward inference
path. All platforms use this
same geometry, rotated 90° counterclockwise so the output node sits above the
three input nodes. The wordmark remains localized as AI BenchGauge / AI 天梯.

The canonical design and current assets live in [`assets/brand`](../../assets/brand/).
The older gauge artwork and its generation scripts have been removed.

| Asset | Use |
| --- | --- |
| `design.json`, `app-icon.svg`, `mark.svg` | Shared geometry and vector artwork |
| `app-icon-ios.png` | Opaque 1024 px iPhone / iPad artwork; the OS applies its icon mask |
| `app-icon-macos.png`, `AI-BenchGauge.icns` | Mac icon with the platform's outer padding |
| `app-icon-windows.png`, `AI-BenchGauge.ico` | Windows executable, window and tray; 16–256 px frames |
| `header-logo.png`, `header-logo-dark.png` | Network alone for the title's A, transparent and cropped to 142:166 painted bounds; deeper teal on light surfaces, mint on dark surfaces |
| `menu-template.svg`, `menu-template*.png` | Transparent monochrome Mac menu-bar glyph |

Regenerate with `swift Scripts/brand-assets.swift` on macOS, then run
`swift Scripts/ios-icon.swift` to synchronize the iOS asset catalog. Deployment
copies this canonical artwork so it cannot reintroduce the old column icon.
The generator also synchronizes the cropped header marks into the shared Kit
resource bundle. The title uses the original A's horizontal slot and preserves
the mark's aspect ratio; it never uses the square application icon as a letter.

Palette: tile `#0B222B` → `#173E43`, accent `#56B9BA` → `#65D5C5`, ink `#C2F2DB`.
