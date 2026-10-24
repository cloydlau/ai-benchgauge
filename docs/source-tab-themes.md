# Source brand themes

The selected source tab uses a solid brand fill and a contrasting label. The
mini-program, iOS, Mac and Windows read the same `SourceTabThemes.json`; mappings use complete
board kinds, never segment positions. Mobile category icons and the selected
category label follow the current source's `accent`, including live appearance
changes; unselected labels stay secondary and the glass selection stays neutral.
Unknown sources use the application palette.
Tencent is restored on 2026-10-24 with its official Tencent Cloud blues.

Colors checked against official sources on 2026-10-23:

| Source | Light fill / label | Dark fill / label | Official basis |
| --- | --- | --- | --- |
| Artificial Analysis | `#8842FD` / white | `#C394FF` / `#43003B` | [Brand kit](https://artificialanalysis.ai/brand-kit/): Purple, Purple Light, Plum |
| Arena | `#1A1919` / `#FCFAF7` | `#FCFAF7` / `#1A1919` | [Brand announcement](https://arena.ai/blog/lmarena-is-now-arena) and its official stylesheet: `--color-neutral-black`, `--color-neutral-10` |
| Epoch AI | `#70EFD1` / `#072B33` | Same | [ECI website](https://epoch.ai/eci): `.button-primary` uses `--color-teal-300`, `--color-teal-900` |
| OpenRouter | `#7624F4` / `#FCFCFE` | `#C8FF00` / `#03080A` | [Brand assets](https://openrouter.ai/brand) and official website tokens: Grape / Cloud, Volt / Ink |
| Vercel AI Gateway | Black / white | White / black | [Geist colors](https://vercel.com/geist/colors) |
| Tencent Cloud | `#0052D9` / white | `#00A4FF` / `#101216` | [Tencent Cloud](https://cloud.tencent.com/) and its official portal stylesheet (`full.df73a28ab3829ca0322a.css`), checked 2026-10-24 |

All label/fill pairs meet a 4.5:1 contrast ratio. Official CSS observations are
saved in ignored `work/source-tab-themes/`; these are evidence, not runtime
dependencies. No website request is made to choose a tab color.

Validation: all 161 mini-program tests and its production build passed. The iOS
light/dark tab-drag tests passed; screenshots of all five sources in both schemes
were reviewed for fill, label contrast and clipping. Evidence is in ignored
`work/source-tab-themes/iPhone.xcresult` and `verified-attachments/`. Mini-program
simulator screenshots remain unverified because the developer tools login expired.


Source headings, source publication times and relative-share hints now use the
catalog's `accent` field. The selected mobile tab still uses `background` and
`foreground`; a tab label's contrast color must not be reused as page text.
Epoch uses official `--color-teal-700` (`#026B70`) for light-surface text and
`--color-teal-300` (`#70EFD1`) for dark-surface text. Other source accents match
the corresponding tab fill. Text accents meet 4.5:1 contrast against card,
page and desktop header surfaces in both appearances. Local fetch-time
fallbacks remain secondary. Per-model organization colors are retained.

Mini-program canvas exports use the same source identity mapping; iOS exports
resolve the palette against the export appearance. Windows embeds the catalog
in its shared assembly. Exact source IDs cover every category and do not depend
on a column index or name prefix. Unknown sources use the fallback.
