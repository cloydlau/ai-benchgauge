#!/bin/zsh
# 启动时先运行完整单元测试，再打开最新应用；缺少构建或源码较新时先重建。
# 随后监听源码、测试、脚本和未提交改动。防抖节流后先测试，再按目的提交并推送，最后重建重启。
# Ctrl-C 停止。
#
#   ./dev.sh
#
# WATCH_DEBOUNCE_MS  默认 60000
# WATCH_THROTTLE_MS  默认 60000
# WATCH_AUTOCOMMIT=0 关闭自动提交
# COMMIT_PUSH=0 或 WATCH_AUTOPUSH=0 关闭自动推送
# DESKTOP_NOTIFY=0   关闭桌面通知
# TEST_AUTO_REPAIR=0 关闭测试失败后的一次 Codex 修复
set -euo pipefail
ROOT=${0:A:h}
exec node "$ROOT/Scripts/watch.mjs"
