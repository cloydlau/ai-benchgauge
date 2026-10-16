# Development and release checks

Leaderboard country policy: normalize Hong Kong (`HK`), Macao (`MO`) and Taiwan (`TW`) to China (`CN`). Use China's flag and country label for rows, company aggregation, filters, exports, cached metadata and shared links. Apply the shared `fc/leaderboard-policy.json` rule to upstream data and preserve this behavior in every client.

For changes to a desktop interface, obtain real Windows WPF and Mac AppKit / SwiftUI screenshots using the same fixture and content viewport. Follow [docs/visual-comparison.md](docs/visual-comparison.md).

- Capture before and after a style fix and compare each affected state's shown, refreshed and settled frames. Add fixture scenarios for newly changed states; the existing fixture is not exhaustive.
- Review layout, alignment, clipping, spacing, controls, quotas, empty/error states, long names, supported languages and themes. Record intentional platform differences and unresolved differences in the PR.
- Link the CI run and its `native-visual-comparison` artifact, including the source revision, OS and actual DPI. Do not substitute a browser imitation, scaled PNG, unit tests or successful capture for native visual review.
- If a reported issue depends on Windows 10/11 or display scaling, reproduce it on that OS and real scaling before claiming it fixed. Server 2022 / 100% is only the current CI coverage.
- Do not claim a visual fix is verified without the relevant captures. Continue available implementation and capture work; explicitly report missing environment coverage.
- Release publishing depends on the `native-visual-review` protected environment. Only a human may approve it after reviewing that run's report. Agents must not approve or bypass this gate, remove required reviewers, or manufacture a review record.

Generated comparison screenshots stay in ignored `work/` and CI artifacts. Existing privacy/media commit checks remain applicable to any screenshots submitted to Git history.

## WeChat DevTools MCP

For mini-program runtime and UI debugging, use the connected official `wechat-devtools` MCP. The canonical IDE project is this repository's `apps/weapp` directory (not `dist`, the repository root, an old checkout, or an ignored preview fixture). Resolve it to an absolute path from the current checkout and pass it as `project` on every project-specific tool call.

Use the installed official `wechatide-skill` and read its current `SKILL.md` version. Start with `check_wechatide_status` (pass that version) and `project_list`. Import the canonical directory with `project_import` only if missing, then use `open_project_window` to open or reuse its window. Confirm the project and page with `automation_runtime_info` before interactions. Use console/network reads and the automation tools to verify the actual simulator; report connection or compile failures as failures. Keep using the repository's normal build/watch workflow for generated files.

The host MCP connection is in `~/.codex/config.toml` and uses the DevTools-owned MCP token. Never put that token in this repository or logs. The four mini-programs share one connection and select projects explicitly. Follow the existing media intent/review rules before screenshots or recordings.
