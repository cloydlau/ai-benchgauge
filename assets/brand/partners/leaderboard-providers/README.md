# Leaderboard provider marks

Canonical source artwork for the providers found missing during the 2026-10-31 audit of all 29 available shared board snapshots. Each folder has one `logo.svg` or `logo.png`; `sources.json` pins its download URL, reference page, original/download hash, conversion, retrieval date and permission status. JPEG images are losslessly saved as source PNGs after decoding; ICO sources use their largest frame. No artwork is AI generated.

Run `node Scripts/sync-provider-logos.mjs` to normalize these sources through `fc/brands.mjs normalizeLogo` into 64×64 transparent, proportion-preserving PNGs embedded in `fc/brand-catalog.json`. Run with `--check` to verify hashes, PNGs and colors without network or writes; the metadata regression invokes this check in the normal test gate. Edit sources and provenance together.

The service enriches existing cached boards on reads, so metadata changes do not require an origin refresh or a new ranking timestamp. All clients and their image exports consume the same embedded marks. There are no parallel platform-specific master copies. Alibaba's corporate mark is stored under `companyLogos.qwen` and remains distinct from the existing Qwen product artwork.

Xiaohongshu's official favicon identifies its dots studio; iFLYTEK's official open-platform header logo identifies the service operated by Synlan (the site's privacy policy names that operator). Genmo uses the avatar from its official GitHub organization. Other sources are the marks already linked by Artificial Analysis or the official vendor site's favicon. These are identification assets; do not claim the repository MIT license grants rights to them. See `NOTICE.txt`.

Canonical PNG sources are stripped of nonessential metadata before their source hashes are pinned. On 2026-11-01, Deepgram, Kokoro, Zyphra, StyleTTS, Metavoice, Typesafe and Synlan were cleaned without changing decoded pixels or normalized runtime artwork; original download hashes remain in `downloadSHA256`. This keeps the provenance stable through Calmmit’s strict commit metadata cleanup.
