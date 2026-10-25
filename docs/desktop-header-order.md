# Desktop board heading order — 2026-10-25

Mac AppKit and Windows WPF board headings now read introduction, source name,
then license: `用户盲测 · Text Arena · CC BY 4.0`. The introduction keeps its
existing 10-point regular font; the source and license keep their existing
11-point semibold font and source tint. The selected timestamp stays separate.
Name-column measurements use the same ordered fragments as the rendered heading.

When space is limited, Artificial Analysis can abbreviate to AA. The
introduction precedes the source whenever both fit; the license is the last
optional fragment. At very narrow widths, the source identity remains visible.

Local native comparison evidence is retained in ignored
`work/desktop-header-order/`. Before captures use source revision
`2494dc36a51dd832b3d4e29e05f82fd62ae83402`; after captures use the edited working
tree. `provenance.json` records source, binary and fixture SHA-256 hashes.
Both runs use the same fixture and content viewports: 1600×720 for General
and Usage, plus 850×720 for narrow General, in English, Simplified Chinese
and Traditional Chinese, with light/dark and shown/refreshed/settled frames.
Actual capture environment is macOS 27.0.1 (26A434), 1× backing scale.

All 54 before/after frame pairs have matching dimensions and fixture hashes.
RGB differences are confined to header text; the body, timestamps, filters and
other controls are unchanged. Reviewed native originals show the introduction
first and the license last in the wide General and Usage views, readable long
English headings, and retained source identities with stacked timestamps in
the narrow view. At 850 points across three boards, some introductions and
licenses do not fit and are omitted. `verification.json` retains per-frame
change bounds. Windows Release cross-compilation passed with zero warnings
and zero errors.

Windows native capture and a source-matched CI artifact are unavailable on this
Mac. Windows native visual verification and protected release approval are not
claimed.
