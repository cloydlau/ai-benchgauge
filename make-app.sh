#!/bin/zsh
set -euo pipefail
ROOT=${0:A:h}
exec "$ROOT/Scripts/make-app.sh" "$@"
