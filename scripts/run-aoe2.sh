#!/bin/zsh
# Start AoE2 DE directly (not through Steam's Play button).
#   run-aoe2.sh soft    Part A: patched ntdll + x87sidecar soft-fault delivery
#   run-aoe2.sh stock   unmodified CrossOver, same launch path (for A/B tests)
# Environment:
#   AOE2_BOTTLE  CrossOver bottle name (default "Age of Empires II Definitive Edition")
#   AOE_HUD=1    show the Metal performance HUD
#
# Safety: "soft" falls back to an unmodified start (and shows a notification) when
#   - the bottle was upgraded by a different CrossOver version than the patched copy,
#   - a wineserver of a different CrossOver version is running (e.g. Steam after an update),
#   - the game's .text range cannot be read,
#   - the patched start fails early (bridge address taken, sidecar not starting).
# The .text range of AoE2DE_s.exe is read from the PE header at every start,
# so game updates need no rebuild.
setopt no_bg_nice
PREFIX=${0:A:h}
bottle=${AOE2_BOTTLE:-"Age of Empires II Definitive Edition"}
bottles=${CX_BOTTLE_PATH:-$HOME/Library/Application Support/CrossOver/Bottles}
exe="C:/Program Files (x86)/Steam/steamapps/common/AoE2DE/AoE2DE_s.exe"
unix_exe="$bottles/$bottle/drive_c/Program Files (x86)/Steam/steamapps/common/AoE2DE/AoE2DE_s.exe"
copy_app="$PREFIX/SoftFault-CrossOver.app"
stock_app=${CX_APP:-/Applications/CrossOver.app}
mkdir -p "$PREFIX/logs"
stamp=$(date +%Y%m%d-%H%M%S)

notify() {
  echo "$1"
  /usr/bin/osascript -e "display notification \"$1\" with title \"AoE2 DE (Part A)\"" >/dev/null 2>&1
}
bundle_version() { [[ -f "$1/Contents/Info.plist" ]] && /usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$1/Contents/Info.plist" 2>/dev/null; }

run_stock() {
  local log="$PREFIX/logs/run-stock-$stamp.log"
  echo "mode stock, log: $log"
  [[ -n "${AOE2_DRYRUN:-}" ]] && return 0
  "$stock_app/Contents/SharedSupport/CrossOver/bin/wine" --no-update --bottle "$bottle" "$exe" > "$log" 2>&1
}

fallback() {
  notify "Part A not used: $1 Starting normally."
  run_stock
  exit $?
}

if pgrep -f "AoE2DE/AoE2DE_s.exe" >/dev/null; then
  notify "AoE2 is already running."; exit 1
fi
[[ -n "${AOE_HUD:-}" ]] && export MTL_HUD_ENABLED=1

case "$1" in
  stock) run_stock; exit $? ;;
  soft) ;;
  *) echo "usage: $0 soft|stock"; exit 2 ;;
esac

# --- checks -------------------------------------------------------------------
copy_ver=$(bundle_version "$copy_app")
[[ -z "$copy_ver" ]] && fallback "patched CrossOver copy not found."
bottle_ver=$(sed -n 's/^"Version" = "\(.*\)"/\1/p' "$bottles/$bottle/cxbottle.conf" 2>/dev/null)
if [[ -n "$bottle_ver" && "$bottle_ver" != "$copy_ver" ]]; then
  fallback "the bottle is now on CrossOver $bottle_ver, Part A is built for $copy_ver. Rebuild Part A for the new version."
fi
# A running wineserver from another CrossOver build (e.g. Steam started after a CrossOver update)
for ws in ${(f)"$(ps -axo comm= | grep '/wineserver$')"}; do
  ws_app=${ws%%/Contents/*}
  [[ "$ws_app" == "$copy_app" ]] && continue
  ws_ver=$(bundle_version "$ws_app")
  if [[ -n "$ws_ver" && "$ws_ver" != "$copy_ver" ]]; then
    fallback "Steam or another Wine program is running in CrossOver $ws_ver. Quit it first to use Part A."
  fi
done

range=$(/usr/bin/python3 -I - "$unix_exe" <<'EOF' 2>/dev/null
import struct, sys
d = open(sys.argv[1], 'rb').read(4096)
pe = struct.unpack_from('<I', d, 0x3c)[0]
n = struct.unpack_from('<H', d, pe + 6)[0]
osz = struct.unpack_from('<H', d, pe + 20)[0]
base = struct.unpack_from('<Q', d, pe + 24 + 24)[0]
sh = pe + 24 + osz
for i in range(n):
    name, vs, va = struct.unpack_from('<8sII', d, sh + 40 * i)
    if name.rstrip(b'\0') == b'.text':
        print('0x%x 0x%x' % (base + va, base + va + vs))
EOF
)
[[ -z "$range" ]] && fallback "could not read the game's code range."

# --- patched start ------------------------------------------------------------
R="$copy_app/Contents/SharedSupport/CrossOver"
export AOE_SOFTFAULT_PC=${range% *} AOE_SOFTFAULT_END=${range#* }
export WINELOADER="$R/bin/wineloader"
export AOELAB_SIDECAR_PATH="$PREFIX/x87sidecar"
export AOE2_SOFTFAULT=1
log="$PREFIX/logs/run-soft-$stamp.log"
echo "mode soft, CrossOver $copy_ver, .text $AOE_SOFTFAULT_PC-$AOE_SOFTFAULT_END, log: $log"
[[ -n "${AOE2_DRYRUN:-}" ]] && exit 0
"$R/bin/wine" --no-update --bottle "$bottle" "$exe" > "$log" 2>&1 &
wine_pid=$!

# Watch the first 90 s for the patch's own fatal errors.
for i in {1..45}; do
  if grep -qE "software fault (bridge|translator|entries)" "$log" 2>/dev/null; then
    kill $wine_pid 2>/dev/null
    pkill -f "AoE2DE/AoE2DE_s.exe" 2>/dev/null
    sleep 3
    unset AOE_SOFTFAULT_PC AOE_SOFTFAULT_END WINELOADER AOELAB_SIDECAR_PATH AOE2_SOFTFAULT
    fallback "the patched start failed ($(grep -oE 'cannot [^(]*|software fault entries missing' "$log" | head -1))."
  fi
  kill -0 $wine_pid 2>/dev/null || break
  sleep 2
done
wait $wine_pid
