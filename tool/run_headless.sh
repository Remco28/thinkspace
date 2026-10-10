#!/usr/bin/env bash
# Launch Thinkspace on a virtual X display (:99) with the inspector enabled.
#   tool/run_headless.sh [debug|release]
# Then:  tool/ts state | tool/ts shot out.png | tool/ts do '{"cmd":"sample"}'
# The same display carries a real clipboard:  DISPLAY=:99 xclip -selection clipboard -t image/png -i pic.png
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/development/flutter/bin:$PATH"
mode="${1:-debug}"
export THINKSPACE_DEBUG_PORT="${THINKSPACE_DEBUG_PORT:-47651}"
export DISPLAY=:99
[ -x "build/linux/x64/$mode/bundle/thinkspace" ] || flutter build linux "--$mode"
pgrep -x Xvfb >/dev/null || { Xvfb :99 -screen 0 1440x900x24 >/dev/null 2>&1 & sleep 1; }
exec "build/linux/x64/$mode/bundle/thinkspace"
