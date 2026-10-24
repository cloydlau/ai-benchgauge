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

## Native build cache lifecycle

Use the managed build entry points (`./test.sh`, `./make-app.sh`, `Scripts/ios-build.mjs`, `Scripts/ios-deploy.mjs`). They serialize native builds and track rebuildable caches with a 7-day idle limit and 20 GiB target. Do not create additional persistent Swift scratch directories or Xcode DerivedData trees per task.

For one-off native captures or checks, use `node Scripts/build-cache.mjs run temporary -- <command> [args]`. The child receives `BENCHGAUGE_TEMP_CACHE`; put Swift `--scratch-path` / module caches and Xcode `-derivedDataPath` below that directory. Export screenshots, reports and any deliverable outside it before the command exits. It is automatically reclaimed on success or failure. Do not put source copies, user data, release archives or crash symbols there. Do not nest another managed build entry point inside this command (it already holds the native-build lock).

Only the explicitly registered caches are eligible for automatic eviction. Unregistered `work/` directories, simulator devices/runtimes, release archives, reports and installed applications require separate review. Never infer that a directory is disposable from its name. See [docs/build-cache.md](docs/build-cache.md).

## WeChat DevTools MCP

For mini-program runtime and UI debugging, use the connected official `wechat-devtools` MCP. The canonical IDE project is this repository's `apps/weapp` directory (not `dist`, the repository root, an old checkout, or an ignored preview fixture). Resolve it to an absolute path from the current checkout and pass it as `project` on every project-specific tool call.

Use the installed official `wechatide-skill` and read its current `SKILL.md` version. Start with `check_wechatide_status` (pass that version) and `project_list`. Import the canonical directory with `project_import` only if missing, then use `open_project_window` to open or reuse its window. Confirm the project and page with `automation_runtime_info` before interactions. Use console/network reads and the automation tools to verify the actual simulator; report connection or compile failures as failures. Keep using the repository's normal build/watch workflow for generated files.

The host MCP connection is in `~/.codex/config.toml` and uses the DevTools-owned MCP token. Never put that token in this repository or logs. The four mini-programs share one connection and select projects explicitly. Follow the existing media intent/review rules before screenshots or recordings.

## 品牌资源目录

品牌资源统一维护在仓库根目录 `assets/brand/`；正式主图固定命名 `logo.png` 或 `logo.svg`。设计提示词用 `logo.prompt.txt`，平台导出图用 `app-icon-<platform>.*`，其他产品标志放 `partners/`。更新资源时同步该目录的 README、构建复制/生成入口及消费者引用。运行目录、资源包和 `dist` 中的同图仅为导出副本，不作为新的源图维护点；未选定设计仅在仓库外预览；只有用户选定或明确要求存档，才允许加入版本库。

<!-- calmmit:agents:start sha256=999991842f72e6a33393720385570fa40538f51681837806ddaa2efc93322644 -->

## Calmmit 约定引用

开始任务前，请阅读并遵守 [Calmmit AGENTS.md](../calmmit/AGENTS.md) 中适用于本仓库的约定；业务命令使用本仓库已有的 Calmmit 入口。无法读取原文时请明确说明，不推测其内容。
<!-- calmmit:agents:end -->
