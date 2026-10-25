# AI BenchGauge logo

The selected **Obsidian platinum silver / 黑曜铂银 — mirror finish** artwork pairs a
black satin tile with polished silver nodes and connections. Softbox highlights,
dark reflections, narrow bevels and contact shadows give the mark its metallic
depth. The topology remains three input nodes, two intermediate nodes and one
output above them. The wordmark remains localized as AI BenchGauge / AI 天梯.

`logo.png` is the exact 1254×1254 artwork approved by the user.
Application icons use this master directly, with only platform sizing, padding
and corner masking. Do not recreate it from a flat palette. The built-in
`image_gen` tool produced the artwork; its original prompt is retained alongside
the source in `logo.prompt.txt`.

The canonical design and current assets live in [`assets/brand`](../../assets/brand/).
The older gauge artwork and its generation scripts have been removed.

| Asset | Use |
| --- | --- |
| `logo.png` | Approved rendered application-icon master |
| `design.json` | Master-artwork reference, material and small-mark geometry |
| `app-icon.svg` | Self-contained wrapper embedding the approved raster artwork |
| `mark.svg` | Transparent small-mark vector adaptation with silver reflection bands |
| `app-icon-ios.png` | Opaque 1024 px iPhone / iPad artwork; the OS applies its icon mask |
| `app-icon-macos.png`, `AI-BenchGauge.icns` | Mac icon with the platform's outer padding |
| `app-icon-windows.png`, `AI-BenchGauge.ico` | Windows executable, window and tray; 16–256 px frames |
| `header-logo.png`, `header-logo-dark.png` | Network alone for the title's A, transparent and cropped to 142:166 painted bounds; deeper steel on light surfaces, brighter silver on dark surfaces |
| `menu-template.svg`, `menu-template*.png` | Transparent monochrome Mac menu-bar glyph |

Regenerate with `swift Scripts/brand-assets.swift` on macOS, then run
`swift Scripts/ios-icon.swift` to synchronize the iOS asset catalog. Deployment
copies this canonical artwork so it cannot reintroduce the old column icon.
The generator also synchronizes the cropped header marks into the shared Kit
resource bundle. The title uses the original A's horizontal slot and preserves
the mark's aspect ratio; it never uses the square application icon as a letter.

Transparent header marks preserve the original network's nodes, line widths and
proportions. Cylindrical rod highlights, reflected dark bands and fine bevels
adapt the approved material to small sizes without a black tile behind the A.
Monochrome menu-bar artwork keeps its existing silhouette and template behavior.

Official leaderboard-source marks live separately in [`partners/`](partners/README.md).
Their provenance and rights remain distinct from the BenchGauge artwork. Run
`node Scripts/source-logos.mjs` to synchronize Apple exports; the mini-program
build renders the same canonical assets into its package.
Both mobile clients reuse these marks in About and before the source-tab
captions in Usage, General, Coding, Image and Video.

Wordmark letters use neutral steel/silver reflection bands at 0%, 42%, 50% and
100% of their height: `#303945` / `#8894A2` / `#414D5C` / `#6C7888` on light
surfaces and `#F5F7FA` / `#A5AFBC` / `#E0E6EE` / `#8D99A8` on dark surfaces.
Apple titles, mini-program SVGs and Canvas exports use the same stops. Windows
keeps its native neutral text styling and consumes the same header PNGs.
Regenerate the mini-program's matching wordmark SVGs with `swift Scripts/weapp-brand-glyphs.swift`.

## Application theme

The approved icon is paired with a neutral obsidian/platinum interface. Functional
text and button accents use solid colors for contrast; metallic reflection bands
are limited to artwork and decorative selection surfaces.

| Token | Light | Dark |
| --- | --- | --- |
| Action / selected filter | `#414D5C` | `#D1DCE8` |
| Page background | `#F4F5F7` | `#101216` |
| Mobile card | `#FFFFFF` | `#1B1F26` |
| Control surface | `#E7EAF0` | `#272E38` |
| Primary ink | `#20262F` | `#F2F5FA` |
| Secondary ink | `#687382` | `#A2ACBA` |
| Divider | `#DFE3E9` | `#343B46` |

Apple shared controls use `Sources/LeaderboardKit/BrandTheme.swift`; WeChat shell,
about, navigation, dialogs and image exports use the corresponding palette. WPF
uses its panel palette and a silver selection gradient. Native Mac table surfaces
and Windows white ranking surfaces retain platform conventions. Source identity
blue/purple, organization marks, Open/Closed badges and quota/status colors keep
their meaning independently of the application accent.
