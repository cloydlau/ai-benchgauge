# AI Leaderboard Menubar

A native macOS menu-bar app for comparing two AI leaderboards:

- Artificial Analysis Intelligence Index
- Code Arena | WebDev

The app shows the top 20 models from each leaderboard with separate score columns. Coding Plan and pay-as-you-go API purchase links appear inline next to each model name; when a provider has both a mainland China site and an international site, the entry becomes a small menu. It refreshes when its menu-bar icon is clicked and updates itself daily. Failed daily updates retry hourly until local midnight.

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

- Artificial Analysis does not publish a leaderboard update timestamp in its server-rendered page, so the app displays its index version and fetch time.
- Code Arena exposes a vote cutoff timestamp, which the app displays when available.
- Leaderboard data is cached under Application Support and remains available when a source temporarily fails.
