#!/usr/bin/env bash
# Proves packaging/install.sh leaves no trace: snapshot, install, use,
# uninstall, snapshot, compare. Runs the real installer against a stand-in
# package in a throwaway home folder, with GNOME settings kept in a throwaway
# file, so nothing on this computer changes.
#
#   tool/test_install.sh
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/thinkspace-install-test.XXXXXX")"
trap 'rm -rf "$work"' EXIT

# A stand-in package: the real installer and packaging files, a stub program.
pkg="$work/pkg"
mkdir -p "$pkg/app" "$pkg/licenses"
cp "$repo/packaging/install.sh" "$repo/packaging/io.github.remco28.thinkspace.desktop" \
  "$repo/packaging/thinkspace-mime.xml" "$pkg/"
cp -r "$repo/packaging/icons" "$pkg/icons"
printf '#!/bin/sh\necho stub\n' >"$pkg/app/thinkspace"
chmod +x "$pkg/app/thinkspace"
echo MIT >"$pkg/licenses/Thinkspace-MIT.txt"

schema=org.gnome.settings-daemon.plugins.media-keys
ours=/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/thinkspace-screenshot/
theirs=/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/
have_gnome=no
gsettings list-keys "$schema" >/dev/null 2>&1 && have_gnome=yes

fails=0
pass() { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }

# A new account: only the folders every desktop login has.
new_home() {
  home="$work/home-$1"
  mkdir -p "$home/.config" "$home/.cache"
}

# Run a command as the person in the sandbox. Every location is redirected:
# HOME, each XDG folder the installer or GNOME settings use, and the settings
# store itself.
as_person() {
  case "$home" in "$work"/*) ;; *) echo "sandbox escaped: $home" >&2; exit 1 ;; esac
  env -u XDG_DATA_HOME -u XDG_STATE_HOME -u XDG_CACHE_HOME \
    HOME="$home" XDG_CONFIG_HOME="$home/.config" GSETTINGS_BACKEND=keyfile "$@"
}

# What is on the "computer": every file and folder in the home folder (with
# link targets), and the shortcut settings by value. The settings file itself
# is left out of the listing, since its values are compared instead.
snap() {
  (cd "$home" && find . -mindepth 1 -printf '%y %p %l\n' | grep -v '^[df] ./.config/glib-2.0' | sort)
  if [ "$have_gnome" = yes ]; then
    echo "setting custom-keybindings=$(as_person gsettings get $schema custom-keybindings)"
    for key in name command binding; do
      echo "setting $key=$(as_person gsettings get "$schema.custom-keybinding:$ours" $key)"
    done
  fi
}

# Use the app: settings and unsaved work appear, and the screenshot shortcut
# is set the way lib/io/screenshot_shortcut.dart sets it.
use_app() {
  local data="$home/.local/share/thinkspace"
  mkdir -p "$data/recovery"
  echo '{}' >"$data/prefs.json"
  echo '{}' >"$data/recovery/window-1.thinkspace"
  if [ "$have_gnome" = yes ]; then
    local entry="$schema.custom-keybinding:$ours" list
    as_person gsettings set "$entry" name "'Thinkspace screenshot'"
    as_person gsettings set "$entry" command "\"'$home/.local/share/thinkspace/app/thinkspace' --capture\""
    as_person gsettings set "$entry" binding "'<Control>Print'"
    list="$(as_person gsettings get $schema custom-keybindings)"
    case "$list" in
      "@as []") list="['$ours']" ;;
      *) list="${list%]}, '$ours']" ;;
    esac
    as_person gsettings set $schema custom-keybindings "$list"
  fi
}

install_() { as_person "$pkg/install.sh" >/dev/null; }
remove_() { as_person "$pkg/install.sh" --remove "$@" >/dev/null; }

echo "Check the check"
new_home check
snap >"$work/a"
touch "$home/.cache/stray"
snap >"$work/b"
if diff -q "$work/a" "$work/b" >/dev/null; then fail "a stray file goes unnoticed"; else pass "a stray file is noticed"; fi
if [ "$have_gnome" = yes ]; then
  as_person gsettings set $schema custom-keybindings "['$theirs']"
  snap >"$work/c"
  if diff -q "$work/b" "$work/c" >/dev/null; then fail "a changed setting goes unnoticed"; else pass "a changed setting is noticed"; fi
else
  echo "  skip  GNOME settings (schemas not installed)"
fi

echo "Install, use, uninstall: only your settings and unsaved work stay"
new_home keep
snap >"$work/before"
install_
use_app
remove_
snap >"$work/after"
extra="$(diff "$work/before" "$work/after" | grep '^[<>]' || true)"
allowed='^> [df] \./\.local( |/share |/share/thinkspace( |/prefs\.json |/recovery( |/window-1\.thinkspace )))'
if [ -z "$(printf '%s\n' "$extra" | grep -v '^$' | grep -Ev "$allowed" || true)" ]; then
  pass "nothing else is left"
else
  fail "left behind:"; printf '%s\n' "$extra" | grep -Ev "$allowed"
fi
[ -f "$home/.local/share/thinkspace/recovery/window-1.thinkspace" ] && pass "unsaved work kept" || fail "unsaved work lost"
snap >"$work/after1"
if remove_ && diff -q "$work/after" "$work/after1" >/dev/null && snap | diff -q "$work/after" - >/dev/null; then
  pass "uninstalling twice changes nothing"
else
  fail "the second uninstall failed or changed something"
fi

echo "Install, use, uninstall --purge: as before the install"
new_home purge
snap >"$work/before"
install_
use_app
remove_ --purge
snap >"$work/after"
diff "$work/before" "$work/after" >/dev/null && pass "no trace" || { fail "traces:"; diff "$work/before" "$work/after" || true; }

echo "What you had before stays, exactly"
new_home yours
mkdir -p "$home/.local/bin" "$home/.local/share/applications"
echo tool >"$home/.local/bin/othertool"
printf '[Desktop Entry]\nName=Other\n' >"$home/.local/share/applications/other.desktop"
if [ "$have_gnome" = yes ]; then
  as_person gsettings set $schema custom-keybindings "['$theirs']"
  as_person gsettings set "$schema.custom-keybinding:$theirs" binding "'<Super>e'"
fi
snap >"$work/before"
install_
use_app
remove_ --purge
snap >"$work/after"
diff "$work/before" "$work/after" >/dev/null && pass "your files, folders and shortcuts are as they were" ||
  { fail "changed:"; diff "$work/before" "$work/after" || true; }

echo "Upgrade over an earlier install, then uninstall --purge"
new_home upgrade
snap >"$work/before"
install_
use_app
install_
[ -f "$home/.local/share/thinkspace/prefs.json" ] && pass "upgrade keeps your settings" || fail "upgrade lost your settings"
if [ "$have_gnome" = yes ]; then
  case "$(as_person gsettings get $schema custom-keybindings)" in
    *"$ours"*) pass "upgrade keeps the screenshot shortcut" ;;
    *) fail "upgrade dropped the screenshot shortcut" ;;
  esac
fi
remove_ --purge
snap >"$work/after"
diff "$work/before" "$work/after" >/dev/null && pass "no trace" || { fail "traces:"; diff "$work/before" "$work/after" || true; }

echo "Uninstall after a half-finished install"
new_home half
snap >"$work/before"
install_
rm -rf "$home/.local/share/thinkspace/app" "$home/.local/bin/thinkspace"
remove_ --purge && pass "uninstall succeeds" || fail "uninstall failed"
snap >"$work/after"
diff "$work/before" "$work/after" >/dev/null && pass "no trace" || { fail "traces:"; diff "$work/before" "$work/after" || true; }

if [ "$fails" -gt 0 ]; then
  echo "$fails check(s) failed"
  exit 1
fi
echo "All checks passed"
