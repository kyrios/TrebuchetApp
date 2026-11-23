#!/bin/zsh
# One-line installer for aoe2-mac-softfault (prebuilt release, no compiler needed):
#   curl -fsSL https://raw.githubusercontent.com/kyrios/TrebuchetApp/main/scripts/get.sh | zsh
#
# Checks: Apple Silicon, Rosetta, CrossOver at /Applications/CrossOver.app in the version the
# release was built for. Then downloads the release, verifies its SHA-256, and runs install.sh.
# Nothing in /Applications/CrossOver.app or in your bottle is changed.
set -euo pipefail
REPO=kyrios/TrebuchetApp
TAG=v2.0.1
ASSET=aoe2-mac-softfault-$TAG.tar.gz
SHA256=356546f79edae0b79905da76e7c1e1e94df601f3c4deaa3ef547e8c58fadf3ae
CX_VERSION=26.3.0.39832
CX_APP=${CX_APP:-/Applications/CrossOver.app}

die() { print -u2 "Error: $1"; exit 1; }
[[ $(uname -m) == arm64 ]] || die "this needs an Apple Silicon Mac."
/usr/bin/pgrep -q oahd || /usr/bin/arch -x86_64 /usr/bin/true 2>/dev/null || die "Rosetta is not installed (softwareupdate --install-rosetta)."
[[ -d "$CX_APP" ]] || die "CrossOver not found at $CX_APP."
have=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$CX_APP/Contents/Info.plist" 2>/dev/null || true)
[[ "$have" == "$CX_VERSION" ]] || die "this release is built for CrossOver $CX_VERSION, you have ${have:-unknown}. See the README for building from source."

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
echo "Downloading $ASSET ..."
curl -fsSL -o "$tmp/$ASSET" "https://github.com/$REPO/releases/download/$TAG/$ASSET"
got=$(shasum -a 256 "$tmp/$ASSET" | cut -d' ' -f1)
[[ "$got" == "$SHA256" ]] || die "checksum mismatch ($got)."
tar -xzf "$tmp/$ASSET" -C "$tmp"
PREBUILT="$tmp/aoe2-mac-softfault/bin" CX_APP="$CX_APP" zsh "$tmp/aoe2-mac-softfault/scripts/install.sh"
cat <<MSG

Done. Start "Trebuchet" with Spotlight and press Launch. It starts Steam first if needed and waits for sign-in.
  Switch single fixes on or off:  Trebuchet > Settings
  Uninstall:  rm -rf "\$HOME/Library/Application Support/aoe2-mac-softfault" "\$HOME/Applications/Trebuchet.app"
MSG
