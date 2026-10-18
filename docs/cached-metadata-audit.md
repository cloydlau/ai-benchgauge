# Cached leaderboard metadata — 2026-10-17

The eight existing shared snapshots contain 896 leaderboard rows. Evaluation of the saved GET responses with the repaired code resolves 43 of 49 missing country values and 14 of 20 missing openness values. Cross-board appearances count separately. This evaluates the local implementation; it does not assert that the shared service or installed clients have been deployed.

| Board | Rows | Missing country before → after | Missing openness before → after |
| --- | ---: | ---: | ---: |
| AA task benchmarks | 32 | 1 → 1 | 0 → 0 |
| Arena text | 416 | 48 → 5 | 1 → 0 |
| AA coding agents | 40 | 0 → 0 | 19 → 6 |
| Code Arena WebDev | 143 | 0 → 0 | 0 → 0 |
| AA image | 102 | 0 → 0 | 0 → 0 |
| Arena image | 82 | 0 → 0 | 0 → 0 |
| AA video | 33 | 0 → 0 | 0 → 0 |
| Arena video | 48 | 0 → 0 | 0 → 0 |

## Repairs

Country lookup now accepts an exact, case-insensitive model ID when the source organization is absent. Display names remain an exact fallback; known source organizations and coding-agent lead-model rules retain priority. This repairs examples such as `Yi Lightning` / `yi-lightning`, without assigning a country to unrelated fine-tunes. The verified display name `Trinity Large Preview` is mapped to the existing Arcee AI identity; [Arcee's model card](https://huggingface.co/arcee-ai/Trinity-Large-Preview) identifies that exact release. Local Swift and mini-program caches use the same identity/country fallback, including filters and company standings. Existing China normalization remains in effect.

Unassigned country cells are question-mark buttons in Mac, iPhone/iPad, Windows and WeChat views. The generic explanation describes developer-headquarters attribution, community/collaborative projects and insufficient evidence. It does not infer a country from a model's language, base model or hosting provider. Empty/loading rows and unknown openness indicators retain their existing treatment.

Thirteen coding rows omit `Claude` from the lead-model label, such as `Claude Code - Sonnet 5.5 (max)`. Read-time matching restores that prefix only for the named Claude Code families, and still requires unique evidence from the reference boards. Inference settings can differ; dates, versions, model sizes and composite names remain distinct. Explicit source classifications win and conflicting references remain unknown.

`internlm2_5-20b-chat` has a verified public-weight release in [InternLM's official model repository](https://huggingface.co/internlm/internlm2_5-20b-chat). An exact-ID policy fills its missing openness in service responses and client display/filter/export paths. The app's existing “open” classification denotes publicly available weights, including custom licenses; this does not classify the license as OSI approved. Explicit source values are preserved. The underlying saved ranking and its timestamps are not rewritten.

## Remaining unknowns

Six country rows remain unassigned: OpenChat 3.5, OpenChat 3.5 (0106), OpenHermes 2.5 Mistral 7B, Dolphin 2.2.1 Mistral 7B, RWKV-4 Raven 14B and Beam 1.0 / Reflection. The first five lack a verified single developer/headquarters mapping; Reflection's existing lookup is unsuccessful. A failed lookup is not evidence that a developer inherently has no headquarters. All six receive the same generic explanation.

Six coding rows retain unknown openness:

- Three Devin Fusion combinations contain multiple named models; there is no unique matching classification for the complete combination.
- Step 5 Preview has conflicting open/closed values across the reference boards.
- DeepSeek V4 Pro 0813 and DeepSeek V4 Flash 0731 lack exact matching evidence for those dated versions.

## Local caches

The actual WeChat simulator cache contained 895 rows across all eight boards, with an older 39-row coding snapshot. Country fallback resolves its repairable gaps without clearing storage. Its older coding openness fields remain absent in storage and require a normal updated service response; raw stored values are distinguished from resolved display metadata.

The Mac cache contained 528 rows across six boards. Text boards match the shared row counts, but coding/video boards contain only 20 rows each and both image boards are absent. The truncated snapshots also lack openness fields. A normal successful shared-service GET can replace them; the audit does not fabricate missing rankings or overwrite the user's cache. No Windows installation or physical-device cache was available locally.

## Evidence and delivery

Ignored `work/country-help/` retains sanitized shared and local snapshots, before/after audit JSON, test/build logs, the synthetic native fixture, before/after Mac app bundles and original screenshots. No upstream refresh endpoint was invoked. No shared-service deployment, app installation or release publishing is included.

Validation passes: 160 focused JavaScript checks covering shared service, country identity, metadata auditing and the mini-program; the Swift country, company, logo, openness, filter and presentation checks; the mini-program production build; the Mac build; Windows WPF Release cross-compilation with zero warnings/errors; and the Windows shared test harness. The actual WeChat country button opens its generic explanation. Native Mac originals cover three languages and both themes; Windows native UI/DPI and new physical/mobile captures remain unavailable. See `docs/visual-comparison.md` for capture scope and limitations.

The two requested about-page phrases, “词元为累计研发投入” and “构建时自动更新”, and their English/Traditional equivalents are removed. The actual WeChat about-page data was read back after rebuilding to confirm the removal.
