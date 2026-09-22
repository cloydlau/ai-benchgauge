#!/bin/zsh
# Kills the running instance and opens the freshly built bundle.
# `open` alone only activates an already-running app, so the old binary would
# keep serving the old UI until it is quit.
set -euo pipefail

ROOT=${0:A:h:h}
APP="$ROOT/outputs/AI-Leaderboards.app"

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
  notify failure "重启失败" "restart.sh 退出码 $exit_code"
  exit $exit_code
}
trap on_err ERR

pkill -f "$APP/Contents/MacOS/leaderboard-menu" 2>/dev/null || true
sleep 1
open "$APP"

printf 'Relaunched %s\n' "$APP"
notify success "已重启" "菜单栏应用已重新打开。"
