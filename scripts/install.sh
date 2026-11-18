#!/bin/zsh
# Install Part A next to (not into) CrossOver:
#   - APFS clone of /Applications/CrossOver.app with the patched ntdll
#   - the x87sidecar
#   - a launcher app "AoE2 DE (Part A)" in ~/Applications (found by Spotlight)
# Your /Applications/CrossOver.app and your bottle stay unchanged.
set -euo pipefail
here=${0:A:h}
WORK=${WORK:-$PWD/work}
PREFIX=${PREFIX:-"$HOME/Library/Application Support/aoe2-mac-softfault"}
CX_APP=${CX_APP:-/Applications/CrossOver.app}
mkdir -p "$PREFIX"

app="$PREFIX/SoftFault-CrossOver.app"
rm -rf "$app"
cp -cR "$CX_APP" "$app"
lib="$app/Contents/SharedSupport/CrossOver/lib/wine"
cp "$WORK/build/dlls/ntdll/ntdll.so" "$lib/x86_64-unix/ntdll.so"
cp "$WORK/build/dlls/ntdll/x86_64-windows/ntdll.dll" "$lib/x86_64-windows/ntdll.dll"
codesign -s - -f "$lib/x86_64-unix/ntdll.so"
cp "$WORK/sidecar/build/bin/x87sidecar" "$PREFIX/x87sidecar"
cp "$here/run-aoe2.sh" "$PREFIX/run-aoe2.sh"
chmod +x "$PREFIX/run-aoe2.sh"

# Launcher app
la="$HOME/Applications/AoE2 DE (Part A).app"
rm -rf "$la"
mkdir -p "$la/Contents/MacOS" "$la/Contents/Resources"
icon=$(find "$HOME/Applications/CrossOver" -path "*Age of Empires II Definitive Edition.app/Contents/Resources/*.icns" 2>/dev/null | head -1 || true)
[[ -n "$icon" ]] && cp "$icon" "$la/Contents/Resources/AppIcon.icns"
cat > "$la/Contents/MacOS/launch" <<EOF
#!/bin/zsh
exec "$PREFIX/run-aoe2.sh" soft
EOF
chmod +x "$la/Contents/MacOS/launch"
cat > "$la/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key><string>launch</string>
	<key>CFBundleIconFile</key><string>AppIcon</string>
	<key>CFBundleIdentifier</key><string>local.aoe2de.parta</string>
	<key>CFBundleName</key><string>AoE2 DE (Part A)</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleVersion</key><string>1.0</string>
	<key>LSUIElement</key><true/>
</dict>
</plist>
EOF
codesign -s - -f --deep "$la"
mdimport "$la" 2>/dev/null || true
echo "Installed. Start \"AoE2 DE (Part A)\" from Spotlight or ~/Applications."
