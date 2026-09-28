#!/bin/zsh
set -euo pipefail

ROOT=${0:A:h:h}
APP="$ROOT/outputs/AI-BenchGauge.app"

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

node "$ROOT/Scripts/test.mjs" --gate

build_args=(-c release --package-path "$ROOT" --cache-path "$ROOT/work/swiftpm-cache"
  --manifest-cache local --disable-build-manifest-caching --disable-sandbox -debug-info-format none)
if [[ "${APP_UNIVERSAL:-0}" == "1" ]]; then
  build_args+=(--arch arm64 --arch x86_64)
fi
export CLANG_MODULE_CACHE_PATH="$ROOT/work/clang-modules"
swift build "${build_args[@]}" --product leaderboard-menu
BIN="$(swift build "${build_args[@]}" --show-bin-path)/leaderboard-menu"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/apps/macos/Sources/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$BIN" "$APP/Contents/MacOS/leaderboard-menu"
rm -rf "$APP/Contents/Resources/logos"
cp -R "$ROOT/assets/logos" "$APP/Contents/Resources/logos"
rm -rf "$APP/Contents/Resources/Licenses"
cp -R "$ROOT/apps/macos/Sources/Resources/Licenses" "$APP/Contents/Resources/Licenses"
# Keep the application notice identical to the repository's license.
cp "$ROOT/LICENSE" "$APP/Contents/Resources/Licenses/AI-BenchGauge.txt"
FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
mkdir -p "$APP/Contents/Frameworks"
rm -rf "$FRAMEWORK"
ditto "$ROOT/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" "$FRAMEWORK"
# Preserve Sparkle helper entitlements and sign from the innermost components out.
sign_args=(--force --sign "${APP_SIGNING_IDENTITY:--}" --preserve-metadata=identifier,entitlements,flags)
if [[ "${APP_SIGNING_IDENTITY:--}" != "-" ]]; then
  sign_args+=(--timestamp --options runtime)
fi
codesign "${sign_args[@]}" "$FRAMEWORK/Versions/B/Autoupdate"
for component in "$FRAMEWORK/Versions/B/XPCServices/"*.xpc "$FRAMEWORK/Versions/B/Updater.app"; do
  codesign "${sign_args[@]}" "$component"
done
codesign "${sign_args[@]}" "$FRAMEWORK"
codesign "${sign_args[@]}" "$APP"
codesign --verify --deep --strict "$APP"

printf 'Built %s\n' "$APP"
notify success "构建成功" "已生成 outputs/AI-BenchGauge.app"
