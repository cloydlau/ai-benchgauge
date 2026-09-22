# AI Leaderboard Menubar

A native macOS menu-bar app for comparing paired AI leaderboards across four categories:

- 综合：Artificial Analysis Intelligence Index / Arena | Text
- 编程：Artificial Analysis Coding Agent Index / Code Arena | WebDev
- 图片：Artificial Analysis 文生图 / Arena 文生图
- 视频：Artificial Analysis 文生视频 / Arena 文生视频

The app shows the top 20 models from each leaderboard with separate score columns. Switching categories loads the corresponding pair from cache when available, otherwise it fetches both sources. The last selected category is remembered locally and restored the next time the app opens. Coding Plan and pay-as-you-go API purchase links appear inline next to each model name; when a provider has both a mainland China site and an international site, the entry becomes a small menu. It refreshes when its menu-bar icon is clicked and updates itself daily. Failed daily updates retry hourly until local midnight.

If CC Switch is installed, Codex provider quotas from its local database appear in a strip above the table. Those figures are account balances, not scores for a ranked model, so they are not another table column.

## Requirements

- macOS 14 or later
- Swift 6 and Command Line Tools

## Build

```bash
./Scripts/make-app.sh
```

The script creates an ad-hoc signed app bundle at:

```text
outputs/AI-Leaderboards.app
```

## Notes

- Artificial Analysis does not publish a leaderboard update timestamp in its server-rendered pages, so the app displays its index version when available and fetch time.
- Arena leaderboards expose a vote cutoff timestamp, which the app displays when available.
- For the image and video categories, the more specific 文生图 and 文生视频 boards are used instead of aggregate media rankings.
- Leaderboard data is cached under Application Support and remains available when a source temporarily fails.

## Local CI

本地流程只做四件事：按目的拆分提交并推送、识别当前模型名称和头像、桌面通知、改完代码后防抖节流自动重启。不跑测试，也不做 code review。

```bash
./dev.sh
```

`./dev.sh` 监听 `Sources/`、`Package.swift` 和两个 `make-app.sh`，同时检查 git 里还有没有未提交改动和未推送提交。变更停止 1 分钟，并且距上次运行至少 1 分钟后，先按目的拆成原子提交并推送到上游，再在源码有变化时重建并重启。启动时如果只有未推送提交，会立刻推送。`WATCH_DEBOUNCE_MS` 和 `WATCH_THROTTLE_MS` 可改这两个间隔，`WATCH_AUTOCOMMIT=0` 关闭自动提交，`COMMIT_PUSH=0` 或 `WATCH_AUTOPUSH=0` 关闭自动推送。构建失败后，同一份源码签名不会空转重试；提交失败后，同一份 git 状态也不会空转重试；推送失败后，同一提交也不会空转重试。再保存一次，或重启 `./dev.sh`，才会重新调度。

```bash
Scripts/commit.sh                 # 立刻暂存全部改动并拆成原子提交
Scripts/commit.sh --dry-run       # 只打印拆分计划
Scripts/commit.sh --identity      # 查看模型名称、邮箱和头像
Scripts/commit.sh -m "feat(menu): …"
```

作者是 Codex 配置里的当前模型，邮箱按厂商填写，头像 URL 写在 `Model-Avatar` trailer 里，桌面通知会尽量带上这个图标。`COMMIT_SPLIT=0` 合并成一个提交。`COMMIT_CODEX_MESSAGE=0` 不调用模型，按用途分组。`Scripts/commit.sh` 的 `COMMIT_PUSH` 仍默认关闭。`COMMIT_COAUTHOR=1` 才把本人恢复为 committer，并加上 `Co-authored-by`。`DESKTOP_NOTIFY=0` 关闭桌面通知。
