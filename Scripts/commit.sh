#!/bin/zsh
# 自动拆分原子提交，并以当前 Codex 模型署名。
#
#   Scripts/commit.sh
#   Scripts/commit.sh -m "feat(menu): …"
#   Scripts/commit.sh --identity
#   Scripts/commit.sh --dry-run
set -euo pipefail
ROOT=${0:A:h:h}
exec node "$ROOT/Scripts/commit.mjs" "$@"
