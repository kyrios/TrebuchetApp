#!/bin/zsh
# Tests the MANIFEST gate of install.sh and run-aoe2.sh. Everything happens in a scratch folder.
# /Applications/CrossOver.app is only read (APFS clones), the game is never started (AOE2_DRYRUN),
# Steam is never started (pgrep stub), no notification is shown (osascript stubbed in the scratch copy).
#   zsh test/manifest_gate_test.sh <release dir containing bin/, scripts/, MANIFEST>
# Exit 0 = all cases behaved as expected.
set -u
R=${1:?release dir (e.g. the unpacked aoe2-mac-softfault/ of a release tarball)}; R=${R:A}
CX=${CX_APP:-/Applications/CrossOver.app}
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fail=1; fi; }
inst() {  # $1 prefix name, $2 CrossOver app, $3 release dir
  PREBUILT=$3/bin PREFIX=$T/$1 LAUNCHER_DIR=$T/la-$1 CX_APP=$2 zsh $3/scripts/install.sh >$T/$1.out 2>&1
}

# install gate
inst ok "$CX" "$R";                                               check "install on the exact CrossOver build" '[[ -f $T/ok/MANIFEST ]]'
icon_sha() { shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1; }
appname=$(sed -n 's/^APP_NAME=//p' $R/scripts/names.conf 2>/dev/null | head -1); appname=${appname:-AoE2 DE (Part A)}
check "launcher carries our own icon (no game art)" '[[ -n $(icon_sha $R/scripts/AppIcon.icns) && $(icon_sha "$T/la-ok/$appname.app/Contents/Resources/AppIcon.icns") == $(icon_sha $R/scripts/AppIcon.icns) ]]'
cp -cR "$CX" $T/cx-new; /usr/libexec/PlistBuddy -c "Set :CFBundleVersion 99.0.0.1" $T/cx-new/Contents/Info.plist
inst new $T/cx-new "$R";                                          check "install refused on another CrossOver version" '[[ ! -e $T/new ]] && grep -q "Nothing installed" $T/new.out'
cp -cR "$CX" $T/cx-mod; printf X >> $T/cx-mod/Contents/SharedSupport/CrossOver/lib/wine/x86_64-unix/ntdll.so
inst mod $T/cx-mod "$R";                                          check "install refused on a changed stock file" '[[ ! -e $T/mod ]] && grep -q "differs" $T/mod.out'
cp -cR "$R" $T/rel-bad; printf X >> $T/rel-bad/bin/x87sidecar
inst bad "$CX" $T/rel-bad;                                        check "install refused on a damaged release file" '[[ ! -e $T/bad ]] && grep -q "damaged" $T/bad.out'

# launcher gate (dry runs against a fake bottle)
P=$T/ok; sed -i '' 's#/usr/bin/osascript#: #' $P/run-aoe2.sh
mkdir -p $T/shim "$T/bottles/B/drive_c/Program Files (x86)/Steam/steamapps/common/AoE2DE"; printf '#!/bin/zsh\nexit 1\n' > $T/shim/pgrep; chmod +x $T/shim/pgrep
print "\"Version\" = \"$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' $CX/Contents/Info.plist)\"" > $T/bottles/B/cxbottle.conf
/usr/bin/python3 -I -c "
import struct,sys;d=bytearray(4096);d[0:2]=b'MZ';struct.pack_into('<I',d,0x3c,0x80);d[0x80:0x84]=b'PE\0\0';struct.pack_into('<H',d,0x86,1);struct.pack_into('<H',d,0x94,240);struct.pack_into('<Q',d,0x80+24+24,0x140000000);sh=0x80+24+240;d[sh:sh+8]=b'.text\0\0\0';struct.pack_into('<II',d,sh+8,0x1000,0x1000);open(sys.argv[1],'wb').write(d)" "$T/bottles/B/drive_c/Program Files (x86)/Steam/steamapps/common/AoE2DE/AoE2DE_s.exe"
run() { env PATH=$T/shim:$PATH CX_BOTTLE_PATH=$T/bottles AOE2_BOTTLE=B AOE2_DRYRUN=1 "$@" zsh $P/run-aoe2.sh soft 2>&1; }
o=$(run CX_APP="$CX");     check "launcher: everything matches -> patched start" '[[ $o == *"mode soft"* ]]'
o=$(run CX_APP=$T/cx-new); check "launcher: CrossOver updated -> normal start"   '[[ $o == *"CrossOver is now"* && $o == *"mode stock"* ]]'
so="$P/SoftFault-CrossOver.app/Contents/SharedSupport/CrossOver/lib/wine/x86_64-unix/ntdll.so"; cp -p "$so" $T/so.bak; printf X >> "$so"
o=$(run CX_APP="$CX");     check "launcher: our file modified -> normal start"   '[[ $o == *"differs from the release"* && $o == *"mode stock"* ]]'
cp -p $T/so.bak "$so"; mv $P/MANIFEST $P/MANIFEST.x
o=$(run CX_APP="$CX");     check "launcher: no MANIFEST -> normal start"         '[[ $o == *"no MANIFEST"* && $o == *"mode stock"* ]]'
exit $fail
