#!/bin/zsh
# 监听源码和未提交改动。防抖节流后先按目的拆成原子提交并推送，再重建并重启菜单栏应用。
# Ctrl-C 停止。
#
#   ./dev.sh
#
# WATCH_DEBOUNCE_MS  默认 60000
# WATCH_THROTTLE_MS  默认 60000
# WATCH_AUTOCOMMIT=0 关闭自动提交
# COMMIT_PUSH=0 或 WATCH_AUTOPUSH=0 关闭自动推送
# DESKTOP_NOTIFY=0   关闭桌面通知
set -euo pipefail
ROOT=${0:A:h}
exec node "$ROOT/Scripts/watch.mjs"
