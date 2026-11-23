#!/bin/zsh
# Install Part A next to (not into) CrossOver:
#   - APFS clone of /Applications/CrossOver.app with the patched ntdll
#   - the x87sidecar
#   - a launcher app "AoE2 DE (Part A)" in ~/Applications (found by Spotlight)
# Your /Applications/CrossOver.app and your bottle stay unchanged.
#
# Inputs: either a build from build.sh ($WORK, default ./work) or prebuilt files
# ($PREBUILT = directory with ntdll.so, ntdll.dll, x87sidecar; used by get.sh).
# Both need a MANIFEST (release: next to bin/; source build: $WORK/MANIFEST, written by build.sh).
# If CrossOver is not exactly the build the MANIFEST names, nothing is installed.
#
# The Trebuchet app runs this same script from inside its bundle (Contents/Resources/Trebuchet/scripts) with
# PREBUILT=<bundle>/Contents/Resources/Trebuchet/bin, PREFIX=~/Library/Application Support/Trebuchet and NO_LAUNCHER=1:
# then nothing is written outside PREFIX, and "step: ..." lines report progress to the app.
# On success PREFIX/.prepared holds what the copy was made from (payload MANIFEST hash + CrossOver build);
# the app re-runs this script when that no longer matches.
set -euo pipefail
here=${0:A:h}
WORK=${WORK:-$PWD/work}
PREFIX=${PREFIX:-"$HOME/Library/Application Support/aoe2-mac-softfault"}
CX_APP=${CX_APP:-/Applications/CrossOver.app}
die() { print -u2 "Error: $1"; exit 1; }
sha() { shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1; }
cx_ver() { /usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$1/Contents/Info.plist" 2>/dev/null; }
# A version without a build number (e.g. 26.3.0 for a source build) matches by prefix.
ver_ok() { [[ "$1" == "$2" || ( "$2" != *.*.*.* && "$1" == "$2".* ) ]]; }

if [[ -n "${PREBUILT:-}" ]]; then
  so="$PREBUILT/ntdll.so" dll="$PREBUILT/ntdll.dll" sc="$PREBUILT/x87sidecar"
  mf_in="${MANIFEST:-$PREBUILT/../MANIFEST}"
else
  so="$WORK/build/dlls/ntdll/ntdll.so" dll="$WORK/build/dlls/ntdll/x86_64-windows/ntdll.dll" sc="$WORK/sidecar/build/bin/x87sidecar"
  mf_in="${MANIFEST:-$WORK/MANIFEST}"
fi
# Payload id: every file this script installs from (prebuilt binaries + these scripts + MANIFEST), so any change
# in a new app version triggers a fresh copy.
payload_id() {
  { [[ -n "${PREBUILT:-}" ]] && (cd "$PREBUILT" && find . -type f ! -name '.*' ! -path './*.app/*' | LC_ALL=C sort | while read -r f; do print "$f $(sha "$f")"; done)
    print "MANIFEST $(sha "$mf_in")"
    for f in run-aoe2.sh find-game.sh mk_reorder.py mk_rules.py rules.manifest defaults.conf names.conf install.sh; do [[ -f "$here/$f" ]] && print "$f $(sha "$here/$f")"; done
  } | shasum -a 256 | cut -d' ' -f1
}
# --payload-id: print the id and stop. The app runs this at each Launch and compares it with PREFIX/.prepared.
[[ "${1:-}" == --payload-id ]] && { payload_id; exit 0; }

# --- gate: refuse unless CrossOver is exactly the build this release was made for ------
# MANIFEST lines: "built_for_cx <CFBundleVersion>", "stock <path under SharedSupport/CrossOver> <sha256>",
# "src <file name in bin/> <sha256>". Fails closed: nothing is installed on any mismatch.
[[ -f "$mf_in" ]] || die "no MANIFEST ($mf_in). Nothing installed."
want_cx=$(awk '$1=="built_for_cx"{print $2}' "$mf_in")
have_cx=$(cx_ver "$CX_APP")
[[ -n "$want_cx" ]] || die "MANIFEST has no built_for_cx. Nothing installed."
ver_ok "$have_cx" "$want_cx" || die "CrossOver ${have_cx:-unknown} found at $CX_APP; this release is built for $want_cx. Nothing installed."
cxroot="$CX_APP/Contents/SharedSupport/CrossOver"
while read -r k p h; do
  [[ "$k" == stock ]] || continue
  [[ "$(sha "$cxroot/$p")" == "$h" ]] || die "CrossOver file $p differs from CrossOver $want_cx. Nothing installed."
done < "$mf_in"
typeset -A srcfile; srcfile=(ntdll.so "$so" ntdll.dll "$dll" x87sidecar "$sc")
[[ -n "${PREBUILT:-}" && -f "$PREBUILT/win32u.so" ]] && srcfile[win32u.so]="$PREBUILT/win32u.so"
while read -r k p h; do
  [[ "$k" == src ]] || continue
  f=${srcfile[$p]:-}
  [[ -z "$f" && "$p" == dxmt/* && -n "${PREBUILT:-}" ]] && f="$PREBUILT/$p"   # DXMT text-fix set (release only)
  [[ -n "$f" && "$(sha "$f")" == "$h" ]] || die "release file $p is damaged or not the one this MANIFEST lists. Nothing installed."
done < "$mf_in"

step() { print "step: $1"; }
step "Preparing Trebuchet for CrossOver ${have_cx}"
mkdir -p "$PREFIX"
rm -f "$PREFIX/.prepared"
app="$PREFIX/SoftFault-CrossOver.app"
rm -rf "$app"
step "Copying CrossOver (APFS clone)"
cp -cR "$CX_APP" "$app"
step "Adding Trebuchet's files"
lib="$app/Contents/SharedSupport/CrossOver/lib/wine"
cp "$so" "$lib/x86_64-unix/ntdll.so"
cp "$dll" "$lib/x86_64-windows/ntdll.dll"
codesign -v "$lib/x86_64-unix/ntdll.so" 2>/dev/null || codesign -s - -f "$lib/x86_64-unix/ntdll.so"   # keep a valid (Developer ID) signature
if [[ -n "${srcfile[win32u.so]:-}" ]]; then cp "${srcfile[win32u.so]}" "$lib/x86_64-unix/win32u.so"; codesign -v "$lib/x86_64-unix/win32u.so" 2>/dev/null || codesign -s - -f "$lib/x86_64-unix/win32u.so"; fi
cp -p "$sc" "$PREFIX/x87sidecar"
# keep the tested bytes: sign only if the file carries no valid signature
codesign -v "$PREFIX/x87sidecar" 2>/dev/null || codesign -s - -f "$PREFIX/x87sidecar"
# DXMT: two complete sets next to the copy, never mixed. "textfix" = our v0.72 + label-fix build (release only),
# "crossover" = CrossOver's own set as shipped. run-aoe2.sh copies the chosen set into the copy at each start.
dxroot="$app/Contents/SharedSupport/CrossOver/lib/dxmt"
rm -rf "$PREFIX/dxmt-crossover" "$PREFIX/dxmt-textfix"
cp -cR "$dxroot" "$PREFIX/dxmt-crossover"
if [[ -n "${PREBUILT:-}" && -d "$PREBUILT/dxmt" ]]; then cp -cR "$PREBUILT/dxmt" "$PREFIX/dxmt-textfix"; fi
# Installed manifest for the launcher: CrossOver build + stock hashes + hashes of OUR installed files
# (after signing). run-aoe2.sh checks it at every start, before anything else.
# Gatekeeper: replacing ntdll breaks the copy's CodeWeavers seal. On Macs that track provenance (and for a quarantined
# CrossOver) a broken seal makes macOS call the copy "damaged". Re-seal the copy ad hoc (no hardened runtime), so it is
# internally consistent again. This rewrites only the bundle's main executable and seal, not ntdll (its hashes below stay).
/usr/bin/codesign --force --deep --sign - "$app" >/dev/null 2>&1 || die "could not re-seal Trebuchet's CrossOver copy."
{
  grep -E '^(built_for_cx|stock) ' "$mf_in"
  print "ours copy:lib/wine/x86_64-unix/ntdll.so $(sha "$lib/x86_64-unix/ntdll.so")"
  print "ours copy:lib/wine/x86_64-windows/ntdll.dll $(sha "$lib/x86_64-windows/ntdll.dll")"
  [[ -n "${srcfile[win32u.so]:-}" ]] && print "ours copy:lib/wine/x86_64-unix/win32u.so $(sha "$lib/x86_64-unix/win32u.so")"
  print "ours prefix:x87sidecar $(sha "$PREFIX/x87sidecar")"
  for set in dxmt-crossover dxmt-textfix; do
    [[ -d "$PREFIX/$set" ]] || continue
    (cd "$PREFIX/$set" && find . -type f | LC_ALL=C sort) | while read -r f; do print "ours prefix:$set/${f#./} $(sha "$PREFIX/$set/$f")"; done
  done
} > "$PREFIX/MANIFEST"
cp "$here/run-aoe2.sh" "$PREFIX/run-aoe2.sh"
# Version-bound rules (names, grades, where their patterns live). Its hash is listed too, so the
# launcher's gate notices a changed file. A future signed update channel replaces this line's check.
cp "$here/mk_reorder.py" "$PREFIX/mk_reorder.py"
cp "$here/mk_rules.py" "$PREFIX/mk_rules.py"
cp "$here/find-game.sh" "$PREFIX/find-game.sh"
cp "$here/rules.manifest" "$PREFIX/rules.manifest"
print "ours prefix:rules.manifest $(sha "$PREFIX/rules.manifest")" >> "$PREFIX/MANIFEST"
for f in mk_reorder.py mk_rules.py find-game.sh; do print "ours prefix:$f $(sha "$PREFIX/$f")" >> "$PREFIX/MANIFEST"; done
cp "$here/defaults.conf" "$PREFIX/defaults.conf"
cp "$here/names.conf" "$PREFIX/names.conf"
# Which fixes are compiled into the shipped binaries (the app shows their switches only then)
find "$PREFIX" -maxdepth 1 -name ".has-*" -delete; [[ -n "${PREBUILT:-}" && -f "$PREBUILT/FEATURES" ]] && for f in $(<"$PREBUILT/FEATURES"); do : > "$PREFIX/.has-${f:l}"; done
print "ours prefix:defaults.conf $(sha "$PREFIX/defaults.conf")" >> "$PREFIX/MANIFEST"
chmod +x "$PREFIX/run-aoe2.sh"
# Gatekeeper: the CrossOver copy is an APFS clone of the player's CrossOver, so it inherits a quarantine flag if that
# CrossOver was downloaded with a browser; our files copied out of a downloaded Trebuchet carry one too. The copy's seal is
# broken on purpose (our ntdll replaces CrossOver's), so a quarantined copy is reported as "damaged" on its first start.
# Only Trebuchet's own folder is cleared; /Applications/CrossOver.app and the bottle are never touched.
/usr/bin/xattr -dr com.apple.quarantine "$PREFIX" 2>/dev/null || true   # Apple's xattr by path: a Python xattr earlier in PATH has no -r
print "payload $(payload_id)\ncrossover $have_cx" > "$PREFIX/.prepared"
step "Ready"
if [[ -n "${NO_LAUNCHER:-}" ]]; then exit 0; fi

# Launcher app: the prebuilt SwiftUI app from the release (one launcher, Launch + Settings), else a small script app.
app_name=$(sed -n 's/^APP_NAME=//p' "$here/names.conf" 2>/dev/null | head -1); app_name=${app_name:-AoE2 DE (Part A)}
la="${LAUNCHER_DIR:-$HOME/Applications}/$app_name.app"
rm -rf "$la"
# Remove launchers of earlier versions (other name), but only if they are ours (bundle id check).
old_ids=$(sed -n 's/^OLD_BUNDLE_IDS=//p' "$here/names.conf" 2>/dev/null | head -1)
sed -n 's/^OLD_APP_NAMES=//p' "$here/names.conf" 2>/dev/null | tr ',' '\n' | while read -r old; do
  o="${LAUNCHER_DIR:-$HOME/Applications}/$old.app"
  [[ -n "$old" && -d "$o" && "$o" != "$la" ]] || continue
  bid=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$o/Contents/Info.plist" 2>/dev/null || true)
  [[ ",$old_ids," == *",$bid,"* ]] && { rm -rf "$o"; echo "Removed the old launcher \"$old\"."; }
done
prebuilt_app="${PREBUILT:+$PREBUILT/$app_name.app}"
if [[ -n "$prebuilt_app" && -d "$prebuilt_app" ]]; then
  mkdir -p "${la:h}"; cp -cR "$prebuilt_app" "$la"
  # bottle: the app picks it (Settings > Game, automatic = first bottle with the game)
else
  mkdir -p "$la/Contents/MacOS" "$la/Contents/Resources"
  # Our own icon (scripts/AppIcon.icns, built from launcher/icon-source/). No game art.
  cp "$here/AppIcon.icns" "$la/Contents/Resources/AppIcon.icns"
  # Find the bottle that holds the game (first match), unless AOE2_BOTTLE is set.
  bottles="$HOME/Library/Application Support/CrossOver/Bottles"
  bottle=${AOE2_BOTTLE:-}
  if [[ -z "$bottle" ]]; then
    for b in "$bottles"/*(N/); do
      if zsh "$here/find-game.sh" "$b" >/dev/null 2>&1; then bottle=${b:t}; break; fi
    done
  fi
  if [[ -z "$bottle" ]]; then
    echo "Note: no CrossOver bottle with Steam + AoE2 DE found. The launcher will use the bottle"
    echo "      \"Age of Empires II Definitive Edition\"; set AOE2_BOTTLE and re-run to change it."
    bottle="Age of Empires II Definitive Edition"
  fi
  echo "Bottle: $bottle"
  cat > "$la/Contents/MacOS/launch" <<EOF
#!/bin/zsh
export AOE2_BOTTLE="$bottle"
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

fi
codesign -v --deep "$la" 2>/dev/null || codesign -s - -f --deep "$la"   # keep the release signature
mdimport "$la" 2>/dev/null || true
echo "Installed. Start \"$app_name\" from Spotlight or ~/Applications."
