#!/bin/zsh
set -euo pipefail

ROOT=${0:A:h:h}
APP="$ROOT/outputs/AI-Leaderboards.app"
BIN="$ROOT/.build/release/leaderboard-menu"

env CLANG_MODULE_CACHE_PATH="$ROOT/work/clang-modules" \
  swift build \
    -c release \
    --package-path "$ROOT" \
    --cache-path "$ROOT/work/swiftpm-cache" \
    --manifest-cache local \
    --disable-build-manifest-caching
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/Sources/LeaderboardMenu/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$BIN" "$APP/Contents/MacOS/leaderboard-menu"
rm -rf "$APP/Contents/Resources/logos"
cp -R "$ROOT/Sources/LeaderboardMenu/Resources/logos" "$APP/Contents/Resources/logos"
codesign --force --sign - "$APP"

printf 'Built %s\n' "$APP"
