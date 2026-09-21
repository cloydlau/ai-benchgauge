#!/bin/zsh
# Sets the marketing version and the build number together so they never drift.
# The build number is what Sparkle-style updaters compare, and it must only
# ever move forward.
#
# Usage: Scripts/bump-version.sh 1.1
set -euo pipefail

ROOT=${0:A:h:h}
PLIST="$ROOT/Sources/LeaderboardMenu/Resources/Info.plist"
version=${1:-}

if [[ -z "$version" ]]; then
  print -u2 "usage: Scripts/bump-version.sh <version>   e.g. 1.1"
  exit 1
fi

plutil -replace CFBundleShortVersionString -string "$version" "$PLIST"
plutil -replace CFBundleVersion -string "$version" "$PLIST"
plutil -lint "$PLIST" >/dev/null

printf 'Version -> %s (build %s)\n' "$version" "$version"
