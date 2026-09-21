#!/bin/zsh
# Kills the running instance and opens the freshly built bundle.
# `open` alone only activates an already-running app, so the old binary would
# keep serving the old UI until it is quit.
set -euo pipefail

ROOT=${0:A:h:h}
APP="$ROOT/outputs/AI-Leaderboards.app"

pkill -f "$APP/Contents/MacOS/leaderboard-menu" 2>/dev/null || true
sleep 1
open "$APP"

printf 'Relaunched %s\n' "$APP"
