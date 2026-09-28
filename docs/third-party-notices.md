# License notice inventory

The footer opens one license sheet from two entries: **MIT License** selects
the application license, and **Open-source notices** selects third-party
notices. Complete notices are bundled locally and are selectable and scrollable.

## Current software inventory

- `Package.swift` declares no external package dependencies. `LeaderboardCore`
  and `leaderboard-menu` are this repository's own targets.
- The application license is the repository's `LICENSE`, MIT, copyright
  2026 Cloyd Lau. Packaging copies it into `Resources/Licenses/AI-BenchGauge.txt`.
- The executable dynamically links the macOS system frameworks, Swift runtime,
  and `/usr/lib/libsqlite3.dylib`; no copies of those libraries are shipped.
  [SQLite's deliverable code is public domain](https://sqlite.org/copyright.html).
- CC Switch, Codex CLI, and qianwen CLI are external integrations, not bundled
  dependencies. Their source code and executables are not distributed in this app.

`ThirdParty.json` is currently empty for the software inventory above. This is
**not a completed provenance audit of the bundled brand images**.

## Brand image provenance still needs confirmation

The 31 PNGs in `Resources/logos` have no original download URLs, package versions,
or license records. Their introduction in commit
`9341a69f55c4c8515e92c456f86c7218c3aef51c` describes official favicons and
Iconify, but does not identify the source of each file. Similarity to a brand
mark does not establish which icon collection supplied it.

An audit compared the PNG byte hashes with `@lobehub/icons-static-png` 1.97.1:
none matched. Some rendered marks look similar, which is insufficient to
attribute the existing images to that library. Do not list Lobe Icons as a
confirmed dependency on that basis.

The upstream collections investigated have different terms:

- [Lobe Icons](https://github.com/lobehub/lobe-icons/blob/master/LICENSE): MIT;
  retaining the copyright and full license notice would be required for its
  distributed assets.
- [SVG Logos](https://github.com/gilbarbara/logos/blob/master/LICENSE.txt) and
  [Simple Icons](https://github.com/simple-icons/simple-icons/blob/develop/LICENSE.md):
  CC0 1.0; neither was confirmed as the source of every bundled image.
- [Hugeicons](https://github.com/iconify/icon-sets/blob/master/json/hugeicons.json):
  MIT in Iconify's metadata. The `grok` and `grok-02` shapes examined do not match
  the bundled `spacexai.png`. The development notification script's fallback
  URLs do not demonstrate use in the distributed application.

Confirm the original sources before describing the image notice inventory as
complete. Open-source license notices also do not grant rights in brand trademarks.

## Adding a required notice

Place its unabridged upstream copyright/license text in
`Sources/LeaderboardMenu/Resources/Licenses/`, then add an entry to
`ThirdParty.json` with `id`, `name`, `license`, `source` (an HTTPS project URL),
`englishDescription`, `chineseDescription`, and `file` (the local notice filename).
The sheet lists all entries; each retains its own full text and source link.
Record the exact source version and included resources here as well.

SwiftPM copies this directory for `swift run`. `Scripts/make-app.sh` copies it
into the signed `.app`, overriding the application notice with the current
repository `LICENSE`. Check that every manifest entry has a nonempty local
notice before release.
