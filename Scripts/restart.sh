#!/bin/zsh
# Kills the running instance and opens the freshly built bundle.
# `open` alone only activates an already-running app, so the old binary would
# keep serving the old UI until it is quit.
set -euo pipefail

ROOT=${0:A:h:h}
APP="$ROOT/outputs/AI-BenchGauge.app"
# The running instance may still come from the repository's previous location.
# Match the exact bundle/executable suffix so moving the checkout cannot leave
# Launch Services reactivating the old process while we wait for the new path.
APP_PROCESS_PATTERN='[/]AI-BenchGauge[.]app/Contents/MacOS/leaderboard-menu$'

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
  notify failure "重启失败" "restart.sh 退出码 $exit_code"
  exit $exit_code
}
trap on_err ERR

running_pids() {
  local pids
  if pids=$(pgrep -f "$APP_PROCESS_PATTERN"); then
    print -r -- "$pids"
    return 0
  else
    local exit_code=$?
    # pgrep returns 1 when there is no matching process; other codes mean
    # process inspection failed, so a restart cannot be verified.
    if (( exit_code == 1 )); then
      return 0
    fi
    print -u2 "无法检查应用进程（pgrep 退出码 $exit_code）"
    return "$exit_code"
  fi
}

old_pids=$(running_pids)
if [[ -n "$old_pids" ]]; then
  pkill -f "$APP_PROCESS_PATTERN"
  for attempt in {1..20}; do
    current_pids=$(running_pids)
    [[ -z "$current_pids" ]] && break
    sleep 0.25
  done
  if [[ -n "$current_pids" ]]; then
    print -u2 "旧应用进程仍在运行：$current_pids"
    exit 1
  fi
fi

launched=false
launch_error=''
for attempt in {1..6}; do
  if launch_error=$(open "$APP" 2>&1); then
    launched=true
    break
  fi
  # Launch Services may still be releasing the old instance after its PID exits.
  sleep 0.5
done
if [[ "$launched" != true ]]; then
  print -u2 "$launch_error"
  exit 1
fi
for attempt in {1..20}; do
  new_pids=$(running_pids)
  [[ -n "$new_pids" ]] && break
  sleep 0.25
done
if [[ -z "$new_pids" ]]; then
  print -u2 "应用未启动：$APP"
  exit 1
fi

printf 'Relaunched %s (PID %s)\n' "$APP" "$new_pids"
notify success "已重启" "菜单栏应用已重新打开。"
