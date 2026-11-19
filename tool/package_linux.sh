#!/usr/bin/env bash
# Build a release bundle and wrap it as dist/thinkspace-linux-x64.tar.gz
# with an install.sh that puts it in ~/.local (no root needed).
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/development/flutter/bin:$PATH"
flutter build linux --release
out=dist/thinkspace-linux-x64
rm -rf dist && mkdir -p "$out"
cp -r build/linux/x64/release/bundle "$out/app"
cp packaging/io.github.remco28.thinkspace.desktop packaging/thinkspace-mime.xml "$out/"
cp -r packaging/icons "$out/icons"
# The fonts are under the SIL Open Font License, which asks that the licence text travel with them.
mkdir -p "$out/licenses"
cp LICENSE "$out/licenses/Thinkspace-MIT.txt"
cp assets/fonts/OFL-*.txt "$out/licenses/"
cp packaging/install.sh "$out/install.sh"
chmod +x "$out/install.sh"
tar -C dist -czf dist/thinkspace-linux-x64.tar.gz thinkspace-linux-x64
echo "Built dist/thinkspace-linux-x64.tar.gz ($(du -h dist/thinkspace-linux-x64.tar.gz | cut -f1))"
