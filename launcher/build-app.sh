#!/bin/zsh
# Build the launcher app (name and bundle id from scripts/names.conf) from Sources/*.swift (maintainers; needs the Xcode command line tools).
# Output: $OUT (default ./build)/<APP_NAME>.app, ad-hoc signed. Players never compile anything.
# PAYLOAD=<release folder with MANIFEST and bin/> (from mk-release) embeds everything the app needs into
# Contents/Resources/Trebuchet: MANIFEST, bin/ (ntdll.so/.dll, x87sidecar, dxmt/, FEATURES) and scripts/
# (install.sh, run-aoe2.sh, rules, defaults, names). On first Launch the app runs scripts/install.sh from there
# (NO_LAUNCHER=1) to prepare its CrossOver copy in ~/Library/Application Support/Trebuchet.
# The release signs the Mach-O files in bin/ one by one, then the app (see .github/scripts/sign-payload.sh).
set -euo pipefail
here=${0:A:h}
OUT=${OUT:-$here/build}
name=$(sed -n 's/^APP_NAME=//p' "$here/../scripts/names.conf" | head -1); name=${name:-AoE2 DE (Part A)}
app="$OUT/$name.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
# Sparkle (automatic updates): on when launcher/sparkle-public-key.txt holds the EdDSA public key. The framework comes
# from Sparkle's release archive, pinned by hash, cached in launcher/.sparkle-<version> (git-ignored).
SPARKLE_VERSION=2.10.1
SPARKLE_SHA256=1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27
pub=$(tr -d '[:space:]' < "$here/sparkle-public-key.txt" 2>/dev/null || true)
sparkle=()
if [[ -n $pub ]]; then
  cache=${SPARKLE_CACHE:-$here/.sparkle-$SPARKLE_VERSION}
  if [[ ! -d $cache/Sparkle.framework ]]; then
    mkdir -p "$cache"
    curl -fsSL -o "$cache/sparkle.tar.xz" "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz"
    echo "$SPARKLE_SHA256  $cache/sparkle.tar.xz" | shasum -a 256 -c >/dev/null || { echo "Sparkle archive hash mismatch"; exit 1; }
    tar -xf "$cache/sparkle.tar.xz" -C "$cache" ./Sparkle.framework
    rm "$cache/sparkle.tar.xz"
  fi
  sparkle=(-F "$cache" -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks -D SPARKLE)
fi
swiftc -O -parse-as-library -target arm64-apple-macos14.0 $sparkle \
  -o "$app/Contents/MacOS/AoE2Launcher" "$here"/Sources/*.swift
if [[ -n $pub ]]; then mkdir -p "$app/Contents/Frameworks"; ditto "$cache/Sparkle.framework" "$app/Contents/Frameworks/Sparkle.framework"; fi
cp "$here/../scripts/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"
# Licence texts travel inside the app too (LGPL/MIT notices next to the binaries they cover).
cp -R "$here/../LICENSES" "$app/Contents/Resources/LICENSES"
if [[ -n "${PAYLOAD:-}" ]]; then
  t="$app/Contents/Resources/Trebuchet"
  [[ -f "$PAYLOAD/MANIFEST" && -f "$PAYLOAD/bin/ntdll.so" ]] || { echo "PAYLOAD has no MANIFEST or bin/"; exit 1; }
  mkdir -p "$t/bin" "$t/scripts"
  cp -p "$PAYLOAD/MANIFEST" "$t/MANIFEST"
  for f in ntdll.so ntdll.dll x87sidecar FEATURES win32u.so; do [[ -f "$PAYLOAD/bin/$f" ]] && cp -p "$PAYLOAD/bin/$f" "$t/bin/$f"; done
  [[ -d "$PAYLOAD/bin/dxmt" ]] && cp -pR "$PAYLOAD/bin/dxmt" "$t/bin/dxmt"
  for f in install.sh run-aoe2.sh mk_reorder.py mk_rules.py rules.manifest defaults.conf names.conf; do cp -p "$here/../scripts/$f" "$t/scripts/$f"; done
  chmod 755 "$t/bin/x87sidecar" "$t/bin/ntdll.so" "$t"/scripts/*.sh
  find "$t" -name .DS_Store -delete
fi
cat > "$app/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key><string>AoE2Launcher</string>
	<key>CFBundleIconFile</key><string>AppIcon</string>
	<key>CFBundleIdentifier</key><string>__BUNDLE__</string>
	<key>CFBundleName</key><string>__NAME__</string>
	<key>CFBundleDisplayName</key><string>__NAME__</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>__VERSION__</string>
	<key>CFBundleVersion</key><string>__VERSION__</string>
	<key>LSMinimumSystemVersion</key><string>14.0</string>
	<key>LSApplicationCategoryType</key><string>public.app-category.strategy-games</string>
	<key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF
bid=$(sed -n 's/^BUNDLE_ID=//p' "$here/../scripts/names.conf" | head -1); bid=${bid:-io.github.kyrios.trebuchet}
ver=${VERSION:-2.1}
sed -i '' "s#__NAME__#$name#g; s#__BUNDLE__#$bid#g; s#__VERSION__#$ver#g" "$app/Contents/Info.plist"
if [[ -n $pub ]]; then
  pb=/usr/libexec/PlistBuddy; plist="$app/Contents/Info.plist"
  # SPARKLE_TEST_FEED (local update tests only): a file:// feed. Such a build is marked TrebuchetTestFeed, and the
  # release signing (sign-app.sh) refuses any app whose feed is not the GitHub Pages one.
  feed=https://kyrios.github.io/TrebuchetApp/appcast.xml
  if [[ -n ${SPARKLE_TEST_FEED:-} ]]; then feed=$SPARKLE_TEST_FEED; $pb -c "Add :TrebuchetTestFeed bool true" "$plist"; fi
  $pb -c "Add :SUFeedURL string $feed" "$plist"
  $pb -c "Add :SUPublicEDKey string $pub" "$plist"
  $pb -c "Add :SUEnableAutomaticChecks bool true" "$plist"
  $pb -c "Add :SUAutomaticallyUpdate bool true" "$plist"
  $pb -c "Add :SUScheduledCheckInterval integer 86400" "$plist"
fi
# The payload files keep their exact tested bytes (MANIFEST hashes); only the release signs them (sign-app.sh).
codesign -s - -f "$app"
echo "built: $app"
