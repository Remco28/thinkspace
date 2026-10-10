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
cp packaging/thinkspace.desktop packaging/thinkspace-mime.xml packaging/thinkspace.svg "$out/"
(command -v convert >/dev/null && convert -background none -resize 256x256 packaging/thinkspace.svg "$out/thinkspace.png") || true
cat > "$out/install.sh" <<'INSTALL'
#!/usr/bin/env bash
# Installs Thinkspace for the current user. Remove with: ./install.sh --remove
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
prefix="${HOME}/.local"
if [ "${1:-}" = "--remove" ]; then
  rm -rf "$prefix/share/thinkspace" "$prefix/bin/thinkspace" \
         "$prefix/share/applications/thinkspace.desktop" \
         "$prefix/share/icons/hicolor/scalable/apps/thinkspace.svg" \
         "$prefix/share/mime/packages/thinkspace-mime.xml"
  echo "Removed."; exit 0
fi
mkdir -p "$prefix/share/thinkspace" "$prefix/bin" "$prefix/share/applications" \
         "$prefix/share/icons/hicolor/scalable/apps" "$prefix/share/mime/packages"
rm -rf "$prefix/share/thinkspace/app"
cp -r "$here/app" "$prefix/share/thinkspace/app"
ln -sf "$prefix/share/thinkspace/app/thinkspace" "$prefix/bin/thinkspace"
cp "$here/thinkspace.svg" "$prefix/share/icons/hicolor/scalable/apps/thinkspace.svg"
cp "$here/thinkspace-mime.xml" "$prefix/share/mime/packages/thinkspace-mime.xml"
sed "s|^Exec=.*|Exec=$prefix/bin/thinkspace %F|" "$here/thinkspace.desktop" > "$prefix/share/applications/thinkspace.desktop"
update-mime-database "$prefix/share/mime" >/dev/null 2>&1 || true
update-desktop-database "$prefix/share/applications" >/dev/null 2>&1 || true
echo "Installed. Run 'thinkspace' or find it in your applications menu."
echo "Pasting images needs xclip (X11) or wl-clipboard (Wayland):  sudo apt install xclip wl-clipboard"
INSTALL
chmod +x "$out/install.sh"
tar -C dist -czf dist/thinkspace-linux-x64.tar.gz thinkspace-linux-x64
echo "Built dist/thinkspace-linux-x64.tar.gz ($(du -h dist/thinkspace-linux-x64.tar.gz | cut -f1))"
