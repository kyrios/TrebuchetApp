#!/bin/zsh
# Build the launcher app (name and bundle id from scripts/names.conf) from Sources/*.swift (maintainers; needs the Xcode command line tools).
# Output: $OUT (default ./build)/<APP_NAME>.app, ad-hoc signed. The release ships this prebuilt app;
# install.sh copies it to ~/Applications. Players never compile anything.
set -euo pipefail
here=${0:A:h}
OUT=${OUT:-$here/build}
name=$(sed -n 's/^APP_NAME=//p' "$here/../scripts/names.conf" | head -1); name=${name:-AoE2 DE (Part A)}
app="$OUT/$name.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
swiftc -O -parse-as-library -target arm64-apple-macos14.0 \
  -o "$app/Contents/MacOS/AoE2Launcher" "$here"/Sources/*.swift
cp "$here/../scripts/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"
# Licence texts travel inside the app too (LGPL/MIT notices next to the binaries they cover).
cp -R "$here/../LICENSES" "$app/Contents/Resources/LICENSES"
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
	<key>CFBundleShortVersionString</key><string>2.0</string>
	<key>CFBundleVersion</key><string>2.0</string>
	<key>LSMinimumSystemVersion</key><string>14.0</string>
	<key>LSApplicationCategoryType</key><string>public.app-category.strategy-games</string>
	<key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF
bid=$(sed -n 's/^BUNDLE_ID=//p' "$here/../scripts/names.conf" | head -1); bid=${bid:-io.github.kyrios.trebuchet}
sed -i '' "s#__NAME__#$name#g; s#__BUNDLE__#$bid#g" "$app/Contents/Info.plist"
codesign -s - -f "$app"
echo "built: $app"
