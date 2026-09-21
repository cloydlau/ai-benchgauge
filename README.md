# AI Leaderboard Menubar

A native macOS menu-bar app for comparing paired AI leaderboards across four categories:

- 综合：Artificial Analysis Intelligence Index / Arena | Text
- 编程：Artificial Analysis Intelligence Index / Code Arena | WebDev
- 图片：Artificial Analysis 文生图 / Arena 文生图
- 视频：Artificial Analysis 文生视频 / Arena 文生视频

The app shows the top 20 models from each leaderboard with separate score columns. Switching categories loads the corresponding pair from cache when available, otherwise it fetches both sources. Coding Plan and pay-as-you-go API purchase links appear inline next to each model name; when a provider has both a mainland China site and an international site, the entry becomes a small menu. It refreshes when its menu-bar icon is clicked and updates itself daily. Failed daily updates retry hourly until local midnight.

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
