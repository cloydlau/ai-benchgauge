#!/bin/zsh
set -euo pipefail
ROOT=${0:A:h}
exec node "$ROOT/Scripts/test.mjs" "$@"
