#!/bin/zsh
# One-line installer for Trebuchet (the alternative to downloading Trebuchet.dmg from the website):
#   curl -fsSL https://raw.githubusercontent.com/kyrios/TrebuchetApp/main/scripts/get.sh | zsh
#
# Checks Apple Silicon, Rosetta and CrossOver, downloads the release DMG, verifies its SHA-256 and copies
# Trebuchet.app to /Applications (or ~/Applications if /Applications is not writable). The app prepares its own
# copy of CrossOver on the first Launch. Nothing in your CrossOver app or in your bottle is changed.
set -euo pipefail
REPO=kyrios/TrebuchetApp
TAG=v2.1
ASSET=Trebuchet-${TAG#v}.dmg
SHA256=__SET_AT_RELEASE__
CX_VERSION=26.3.0.39832
CX_APP=${CX_APP:-/Applications/CrossOver.app}

die() { print -u2 "Error: $1"; exit 1; }
[[ $(uname -m) == arm64 ]] || die "this needs an Apple Silicon Mac."
/usr/bin/pgrep -q oahd || /usr/bin/arch -x86_64 /usr/bin/true 2>/dev/null || die "Rosetta is not installed (softwareupdate --install-rosetta)."
[[ -d "$CX_APP" ]] || die "CrossOver not found at $CX_APP."
have=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$CX_APP/Contents/Info.plist" 2>/dev/null || true)
[[ "$have" == "$CX_VERSION" ]] || die "this release is built for CrossOver $CX_VERSION, you have ${have:-unknown}."

tmp=$(mktemp -d)
mnt=$tmp/mnt
trap '[[ -d "$mnt" ]] && /usr/bin/hdiutil detach -quiet "$mnt" 2>/dev/null; rm -rf "$tmp"' EXIT
echo "Downloading $ASSET ..."
curl -fsSL -o "$tmp/$ASSET" "https://github.com/$REPO/releases/download/$TAG/$ASSET"
got=$(shasum -a 256 "$tmp/$ASSET" | cut -d' ' -f1)
[[ "$got" == "$SHA256" ]] || die "checksum mismatch ($got)."
mkdir "$mnt"
/usr/bin/hdiutil attach -quiet -nobrowse -readonly -mountpoint "$mnt" "$tmp/$ASSET"
dest=${DEST:-/Applications}; [[ -w $dest ]] || { dest=$HOME/Applications; mkdir -p "$dest"; }
if pgrep -qf "$dest/Trebuchet.app/Contents/MacOS/"; then die "Trebuchet is running. Quit it and run this again."; fi
rm -rf "$dest/Trebuchet.app"
/usr/bin/ditto "$mnt/Trebuchet.app" "$dest/Trebuchet.app"
/usr/bin/hdiutil detach -quiet "$mnt"
/usr/bin/codesign --verify --strict --deep "$dest/Trebuchet.app" || die "the copied app does not verify."
cat <<MSG

Done: $dest/Trebuchet.app
Start "Trebuchet" with Spotlight and press Launch. The first Launch prepares Trebuchet for CrossOver (a few seconds).
  Switch single fixes on or off:  Trebuchet > Settings
  Uninstall:  Trebuchet > Settings > Game > Reset Trebuchet, then move Trebuchet to the Trash.
MSG
