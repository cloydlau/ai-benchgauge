#!/bin/zsh
set -euo pipefail

ROOT=${0:A:h:h}
APP="$ROOT/outputs/AI-BenchGauge.app"

notify() {
  if [[ -n "${CALMMIT_NOTIFY_OWNER:-}" || "${DESKTOP_NOTIFY:-}" == "0" ]]; then
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

node "$ROOT/Scripts/validate-app-config.mjs"
if [[ "${BENCHGAUGE_SKIP_TESTS:-0}" != "1" ]]; then
  node "$ROOT/Scripts/test.mjs" --gate
fi

exec node "$ROOT/Scripts/build-cache.mjs" run macos -- zsh "$ROOT/Scripts/package-macos.sh"
