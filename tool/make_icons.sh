#!/usr/bin/env bash
# Regenerates every icon size from packaging/logo-original.png.
# Needs python3 + Pillow (to drop stray specks) and ImageMagick `convert`.
set -euo pipefail
cd "$(dirname "$0")/.."
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
python3 -I tool/clean_logo.py packaging/logo-original.png "$tmp/clean.png"
# Trim to the artwork, pad a little, make it square.
convert "$tmp/clean.png" -trim +repage "$tmp/trim.png"
read -r w h <<<"$(identify -format '%w %h' "$tmp/trim.png")"
side=$(( (w > h ? w : h) * 106 / 100 ))
convert "$tmp/trim.png" -background none -gravity center -extent "${side}x${side}" "$tmp/square.png"
mkdir -p packaging/icons
for s in 16 32 48 64 128 256 512; do
  convert "$tmp/square.png" -filter Lanczos -resize ${s}x${s} -strip "packaging/icons/thinkspace-$s.png"
done
