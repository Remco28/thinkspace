#!/usr/bin/env bash
# Launch Thinkspace on a virtual display with the inspector on THINKSPACE_DEBUG_PORT
# (default 47651). Then: curl localhost:47651/state, /screenshot, POST /do.
# Usage: tool/run_headless.sh [debug|release]
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/development/flutter/bin:$PATH"
mode="${1:-debug}"
export THINKSPACE_DEBUG_PORT="${THINKSPACE_DEBUG_PORT:-47651}"
[ -x "build/linux/x64/$mode/bundle/thinkspace" ] || flutter build linux "--$mode"
exec xvfb-run -a -s "-screen 0 1440x900x24" "build/linux/x64/$mode/bundle/thinkspace"
