#!/bin/zsh
# Start AoE2 DE directly (not through Steam's Play button).
#   run-aoe2.sh soft    Part A: patched ntdll + x87sidecar soft-fault delivery
#   run-aoe2.sh stock   unmodified CrossOver, same launch path (for A/B tests)
# Environment:
#   AOE2_BOTTLE  CrossOver bottle name (default "Age of Empires II Definitive Edition")
#   AOE_HUD=1    show the Metal performance HUD
# The .text range of AoE2DE_s.exe is read from the PE header at every start,
# so game updates need no rebuild.
setopt no_bg_nice
PREFIX=${0:A:h}
bottle=${AOE2_BOTTLE:-"Age of Empires II Definitive Edition"}
exe="C:/Program Files (x86)/Steam/steamapps/common/AoE2DE/AoE2DE_s.exe"
unix_exe="${CX_BOTTLE_PATH:-$HOME/Library/Application Support/CrossOver/Bottles}/$bottle/drive_c/Program Files (x86)/Steam/steamapps/common/AoE2DE/AoE2DE_s.exe"
mkdir -p "$PREFIX/logs"
log="$PREFIX/logs/run-$1-$(date +%Y%m%d-%H%M%S).log"

if pgrep -f "AoE2DE/AoE2DE_s.exe" >/dev/null; then
  echo "AoE2 is already running. Close it first."; exit 1
fi

case "$1" in
  soft)
    R="$PREFIX/SoftFault-CrossOver.app/Contents/SharedSupport/CrossOver"
    range=$(/usr/bin/python3 -I - "$unix_exe" <<'EOF'
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
    if [[ -z "$range" ]]; then echo "Could not read .text of AoE2DE_s.exe"; exit 1; fi
    export AOE_SOFTFAULT_PC=${range% *} AOE_SOFTFAULT_END=${range#* }
    export WINELOADER="$R/bin/wineloader"
    export AOELAB_SIDECAR_PATH="$PREFIX/x87sidecar"
    export AOE2_SOFTFAULT=1 ;;
  stock)
    R=/Applications/CrossOver.app/Contents/SharedSupport/CrossOver ;;
  *) echo "usage: $0 soft|stock"; exit 2 ;;
esac
[[ -n "${AOE_HUD:-}" ]] && export MTL_HUD_ENABLED=1
echo "mode $1, .text ${AOE_SOFTFAULT_PC:-} ${AOE_SOFTFAULT_END:-}, log: $log"
"$R/bin/wine" --no-update --bottle "$bottle" "$exe" > "$log" 2>&1
