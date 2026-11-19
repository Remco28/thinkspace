#!/usr/bin/env bash
# Installs Thinkspace for the current user, in ~/.local (no root needed).
#
#   ./install.sh                    install, or upgrade in place
#   ./install.sh --remove           uninstall; your settings and unsaved work stay
#   ./install.sh --remove --purge   uninstall and delete those too
#
# Everything it changes is listed in the README, "What the installer changes".
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
prefix="$HOME/.local"
# Where the app keeps your settings and unsaved work (lib/io/paths.dart).
data="${XDG_DATA_HOME:-$HOME/.local/share}/thinkspace"
# The installer's record of the folders it created, so removal takes away
# those and only those, once they are empty.
ledger_dir="${XDG_STATE_HOME:-$HOME/.local/state}/thinkspace/install"
ledger="$ledger_dir/created-folders"
caches="$ledger_dir/created-caches"
shortcut_schema=org.gnome.settings-daemon.plugins.media-keys
shortcut_path=/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/thinkspace-screenshot/

# Make a folder and any missing parents, writing each new one to the ledger.
make_dir() {
  local d="$1" missing=() i
  while [ ! -d "$d" ]; do missing+=("$d"); d="$(dirname "$d")"; done
  for ((i = ${#missing[@]} - 1; i >= 0; i--)); do
    mkdir "${missing[i]}"
    created+=("${missing[i]}")
  done
}

# Is this a folder, or a desktop cache file, the install created?
ours() { [ -f "$ledger" ] && grep -qxF "$1" "$ledger"; }
our_cache() { [ -f "$caches" ] && grep -qxF "$1" "$caches"; }

# The screenshot shortcut, if the app set one (lib/io/screenshot_shortcut.dart):
# take our entry out of GNOME's list of custom shortcuts and reset its keys.
# The person's other shortcuts stay exactly as they are.
remove_shortcut() {
  local list rest key
  if ! command -v gsettings >/dev/null 2>&1 ||
    ! list="$(gsettings get "$shortcut_schema" custom-keybindings 2>/dev/null)"; then
    echo "Screenshot shortcut: nothing to do (no GNOME keyboard settings)."
    return
  fi
  case "$list" in
    *"'$shortcut_path'"*)
      rest="$(printf '%s' "$list" | sed -e "s#'$shortcut_path'##" \
        -e 's/\[, /[/' -e 's/, ,/,/' -e 's/, \]/]/' -e 's/^\[\]$/@as []/')"
      gsettings set "$shortcut_schema" custom-keybindings "$rest"
      echo "Screenshot shortcut: removed."
      ;;
    *) echo "Screenshot shortcut: none was set." ;;
  esac
  for key in name command binding; do
    gsettings reset "$shortcut_schema.custom-keybinding:$shortcut_path" "$key" \
      2>/dev/null || true
  done
}

uninstall() {
  local purge="$1" d
  rm -rf "$prefix/share/thinkspace/app" "$prefix/share/thinkspace/licenses"
  rm -f "$prefix/bin/thinkspace" \
    "$prefix/share/applications/thinkspace.desktop" \
    "$prefix/share/applications/io.github.remco28.thinkspace.desktop" \
    "$prefix/share/icons/hicolor/scalable/apps/thinkspace.svg" \
    "$prefix"/share/icons/hicolor/*/apps/thinkspace.png \
    "$prefix/share/mime/packages/thinkspace-mime.xml"
  echo "Removed the program, its menu entry, icons and file type."
  remove_shortcut

  if [ "$purge" = yes ]; then
    rm -rf "$data"
    echo "Deleted your Thinkspace settings and unsaved work."
  elif [ -n "$(ls -A "$data" 2>/dev/null)" ]; then
    echo "Kept your Thinkspace settings and unsaved work in $data"
    echo "  (./install.sh --remove --purge deletes them too)."
  fi

  # The desktop's caches: in a folder this install created, the cache is
  # ours once nothing else is there; anywhere else it is refreshed.
  if ours "$prefix/share/mime" &&
    [ -z "$(ls -A "$prefix/share/mime/packages" 2>/dev/null)" ]; then
    rm -rf "$prefix/share/mime"
  else
    update-mime-database "$prefix/share/mime" >/dev/null 2>&1 || true
  fi
  local apps="$prefix/share/applications" icons="$prefix/share/icons/hicolor"
  update-desktop-database "$apps" >/dev/null 2>&1 || true
  # Only its heading left: no other app needs the cache this install made.
  if our_cache "$apps/mimeinfo.cache" &&
    [ -z "$(grep -v '^\[MIME Cache\]$' "$apps/mimeinfo.cache" 2>/dev/null | grep -v '^$')" ]; then
    rm -f "$apps/mimeinfo.cache"
  fi
  if our_cache "$icons/icon-theme.cache" &&
    [ -z "$(find "$icons" -type f ! -name icon-theme.cache 2>/dev/null)" ]; then
    rm -f "$icons/icon-theme.cache"
  else
    gtk-update-icon-cache -q -t "$icons" >/dev/null 2>&1 || true
  fi

  # The folders the install created, deepest first, each only if empty.
  rm -f "$caches"
  if [ -f "$ledger" ]; then
    local folders
    folders="$(sort -r "$ledger")"
    rm -f "$ledger"
    while IFS= read -r d; do
      [ -n "$d" ] && rmdir "$d" 2>/dev/null || true
    done <<<"$folders"
  fi
  echo "Done."
}

case "${1:-}" in
  --remove)
    case "${2:-}" in
      "") uninstall no ;;
      --purge) uninstall yes ;;
      *) echo "Unknown option: $2" >&2; exit 2 ;;
    esac
    exit 0
    ;;
  "") ;;
  *) echo "Usage: ./install.sh [--remove [--purge]]" >&2; exit 2 ;;
esac

created=()
make_dir "$prefix/share/thinkspace"
make_dir "$prefix/bin"
make_dir "$prefix/share/applications"
make_dir "$prefix/share/mime/packages"
for f in "$here"/icons/thinkspace-*.png; do
  n="$(basename "$f" .png)"
  n="${n#thinkspace-}"
  make_dir "$prefix/share/icons/hicolor/${n}x${n}/apps"
done
make_dir "$ledger_dir"
# Merge with what an earlier install recorded: those folders are still ours.
{ cat "$ledger" 2>/dev/null || true; printf '%s\n' "${created[@]+"${created[@]}"}"; } |
  grep -v '^$' | sort -u >"$ledger.new"
mv "$ledger.new" "$ledger"
# The desktop's cache files, made below if they are not there yet.
for f in "$prefix/share/applications/mimeinfo.cache" \
  "$prefix/share/icons/hicolor/icon-theme.cache"; do
  [ -e "$f" ] || echo "$f"
done | { cat "$caches" 2>/dev/null || true; cat; } | sort -u >"$caches.new"
mv "$caches.new" "$caches"

# Tidy up files from version 0.1.0, which used another name and an SVG icon.
rm -f "$prefix/share/applications/thinkspace.desktop" \
  "$prefix/share/icons/hicolor/scalable/apps/thinkspace.svg"
# The program is replaced whole; your settings beside it are left alone.
rm -rf "$prefix/share/thinkspace/app" "$prefix/share/thinkspace/licenses"
cp -r "$here/app" "$prefix/share/thinkspace/app"
cp -r "$here/licenses" "$prefix/share/thinkspace/licenses"
ln -sf "$prefix/share/thinkspace/app/thinkspace" "$prefix/bin/thinkspace"
for f in "$here"/icons/thinkspace-*.png; do
  n="$(basename "$f" .png)"
  n="${n#thinkspace-}"
  cp "$f" "$prefix/share/icons/hicolor/${n}x${n}/apps/thinkspace.png"
done
gtk-update-icon-cache -q -t "$prefix/share/icons/hicolor" >/dev/null 2>&1 || true
cp "$here/thinkspace-mime.xml" "$prefix/share/mime/packages/thinkspace-mime.xml"
sed "s|^Exec=.*|Exec=$prefix/bin/thinkspace %F|" "$here/io.github.remco28.thinkspace.desktop" \
  >"$prefix/share/applications/io.github.remco28.thinkspace.desktop"
update-mime-database "$prefix/share/mime" >/dev/null 2>&1 || true
update-desktop-database "$prefix/share/applications" >/dev/null 2>&1 || true
echo "Installed. Run 'thinkspace' or find it in your applications menu."
echo "Pasting images needs xclip (X11) or wl-clipboard (Wayland):  sudo apt install xclip wl-clipboard"
