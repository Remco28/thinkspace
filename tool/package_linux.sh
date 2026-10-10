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
cat > "$out/install.sh" <<'INSTALL'
#!/usr/bin/env bash
# Installs Thinkspace for the current user. Remove with: ./install.sh --remove
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
prefix="${HOME}/.local"
if [ "${1:-}" = "--remove" ]; then
  rm -rf "$prefix/share/thinkspace" "$prefix/bin/thinkspace" \
         "$prefix/share/applications/thinkspace.desktop" \
         "$prefix/share/applications/io.github.remco28.thinkspace.desktop" \
         "$prefix/share/icons/hicolor/scalable/apps/thinkspace.svg" \
         "$prefix"/share/icons/hicolor/*/apps/thinkspace.png \
         "$prefix/share/mime/packages/thinkspace-mime.xml"
  echo "Removed."; exit 0
fi
mkdir -p "$prefix/share/thinkspace" "$prefix/bin" "$prefix/share/applications" \
         "$prefix/share/mime/packages"
# Tidy up files from version 0.1.0, which used another name and an SVG icon.
rm -f "$prefix/share/applications/thinkspace.desktop" \
      "$prefix/share/icons/hicolor/scalable/apps/thinkspace.svg"
rm -rf "$prefix/share/thinkspace/app"
cp -r "$here/app" "$prefix/share/thinkspace/app"
rm -rf "$prefix/share/thinkspace/licenses"
cp -r "$here/licenses" "$prefix/share/thinkspace/licenses"
ln -sf "$prefix/share/thinkspace/app/thinkspace" "$prefix/bin/thinkspace"
for f in "$here"/icons/thinkspace-*.png; do
  n="$(basename "$f" .png)"; n="${n#thinkspace-}"
  mkdir -p "$prefix/share/icons/hicolor/${n}x${n}/apps"
  cp "$f" "$prefix/share/icons/hicolor/${n}x${n}/apps/thinkspace.png"
done
gtk-update-icon-cache -q -t "$prefix/share/icons/hicolor" >/dev/null 2>&1 || true
cp "$here/thinkspace-mime.xml" "$prefix/share/mime/packages/thinkspace-mime.xml"
sed "s|^Exec=.*|Exec=$prefix/bin/thinkspace %F|" "$here/io.github.remco28.thinkspace.desktop" \
  > "$prefix/share/applications/io.github.remco28.thinkspace.desktop"
update-mime-database "$prefix/share/mime" >/dev/null 2>&1 || true
update-desktop-database "$prefix/share/applications" >/dev/null 2>&1 || true
echo "Installed. Run 'thinkspace' or find it in your applications menu."
echo "Pasting images needs xclip (X11) or wl-clipboard (Wayland):  sudo apt install xclip wl-clipboard"
INSTALL
chmod +x "$out/install.sh"
tar -C dist -czf dist/thinkspace-linux-x64.tar.gz thinkspace-linux-x64
echo "Built dist/thinkspace-linux-x64.tar.gz ($(du -h dist/thinkspace-linux-x64.tar.gz | cut -f1))"
