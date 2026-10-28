#!/bin/zsh
# Sets the marketing version and the build number together so they never drift.
# The build number is what Sparkle-style updaters compare, and it must only
# ever move forward.
#
# Usage: Scripts/bump-version.sh [YYYYMMDD] (defaults to today's Beijing date)
set -euo pipefail

ROOT=${0:A:h:h}
exec node "$ROOT/Scripts/bump-version.mjs" "$@"
