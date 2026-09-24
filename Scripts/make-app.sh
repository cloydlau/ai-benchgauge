#!/bin/zsh
set -euo pipefail

ROOT=${0:A:h:h}
APP="$ROOT/outputs/AI-BenchGauge.app"
BIN="$ROOT/.build/release/leaderboard-menu"

notify() {
  if [[ -n "${LOCAL_CI_NOTIFY_OWNER:-}" || "${DESKTOP_NOTIFY:-}" == "0" ]]; then
    return 0
  fi
  node "$ROOT/Scripts/desktop-notify.mjs" --wait "$1" "$2" "$3" || true
}

on_err() {
  # zsh treats status as a read-only alias of $?.
  local exit_code=$?
  trap - ERR
  notify failure "构建失败" "make-app.sh 退出码 $exit_code"
  exit $exit_code
}
trap on_err ERR

env CLANG_MODULE_CACHE_PATH="$ROOT/work/clang-modules" \
  swift build \
    -c release \
    --package-path "$ROOT" \
    --cache-path "$ROOT/work/swiftpm-cache" \
    --manifest-cache local \
    --disable-build-manifest-caching \
    --disable-sandbox \
    -debug-info-format none
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/Sources/LeaderboardMenu/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$BIN" "$APP/Contents/MacOS/leaderboard-menu"
rm -rf "$APP/Contents/Resources/logos"
cp -R "$ROOT/Sources/LeaderboardMenu/Resources/logos" "$APP/Contents/Resources/logos"
codesign --force --sign - "$APP"

printf 'Built %s\n' "$APP"
notify success "构建成功" "已生成 outputs/AI-BenchGauge.app"
