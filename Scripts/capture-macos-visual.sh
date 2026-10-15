#!/bin/zsh
set -euo pipefail
ROOT=${0:A:h:h}
cd "$ROOT"
swift build -c debug --product leaderboard-menu
BIN=$(swift build -c debug --show-bin-path)
CAPTURE_ROOT="${BENCHGAUGE_VISUAL_ROOT:-$ROOT/work/visual-parity}"
APP="$CAPTURE_ROOT/NativeVisual.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN/leaderboard-menu" "$APP/Contents/MacOS/leaderboard-menu"
cp "$ROOT/apps/macos/Sources/Resources/Info.plist" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.cloydlau.ai-benchgauge.visual-tests' "$APP/Contents/Info.plist"
cp "$ROOT/config/app.json" "$APP/Contents/Resources/app.json"
cp "$ROOT/assets/brand/AI-BenchGauge.icns" "$APP/Contents/Resources/AI-BenchGauge.icns"
ditto "$ROOT/assets/brand" "$APP/Contents/Resources/brand"
ditto "$ROOT/Sources/LeaderboardKit/Resources/Fonts" "$APP/Contents/Resources/Fonts"
cp -R "$ROOT/assets/localizations/"*.lproj "$APP/Contents/Resources/"
ditto "$ROOT/assets/logos" "$APP/Contents/Resources/logos"
ditto "$ROOT/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
codesign --force --sign - "$APP"
"$APP/Contents/MacOS/leaderboard-menu" --visual-test
