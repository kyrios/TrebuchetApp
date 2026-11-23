#!/bin/zsh
# Start AoE2 DE directly (not through Steam's Play button).
#   run-aoe2.sh soft    Part A: patched ntdll + x87sidecar soft-fault delivery
#   run-aoe2.sh stock   unmodified CrossOver, same launch path (for A/B tests)
# Environment:
#   AOE2_BOTTLE  CrossOver bottle name (default "Age of Empires II Definitive Edition")
#   AOE_HUD=1    show the Metal performance HUD
#   AOE2_NO_REORDER=1  start without the health-bar speed-up (plain Part A)
#   AOE2_NO_F54A=1     start without the stutter fix (Rosetta clean-up in small steps)
#   AOE2_NO_MSYNC=1    do not use MSync (CrossOver setting) when this launcher starts Steam
#   AOE2_NO_TEXTFIX=1  use CrossOver's own DXMT instead of our DXMT build with the menu-text fix
#   AOE2_FASTQPC=1     turn ON the faster clock (F59): optional, opt-in, default off pending the user's choice
#   Defaults per fix: defaults.conf next to this script. AOE2_<NAME>=1 forces a fix on, AOE2_NO_<NAME>=1 off.
#   Each switch affects only its own fix. Everything off: Steam's Play button or "run-aoe2.sh stock".
#   None of these switches touches the MANIFEST gate: on any CrossOver mismatch the start is stock.
#
# Version-bound fixes (grade C: tied to a macOS/Rosetta build; grade D: tied to a game build) are listed
# in rules.manifest next to this script. Each one checks its own target and switches itself off on any
# other version; this launcher then SAYS so (one notification per fix, and logs/reports-*.log).
#   AOE2_ARGS="..."  extra game switches (e.g. SKIPINTRO GAM=x); single player tests only
#   AOE2_BACKEND=wined3d|bottle|dxvk|d3dmetal|dxmt
#                graphics backend for the game (default dxmt, measured fastest and smoothest
#                with Part A; fallback d3dmetal, conservative wined3d; "bottle" keeps the
#                bottle's own setting)
#
# Steam is started first (in the normal CrossOver) if it is not running, and the game
# waits until Steam is signed in (up to 10 minutes).
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
  /usr/bin/osascript -e "display notification \"$1\" with title \"$app_title\"" >/dev/null 2>&1
}
app_title=$(sed -n 's/^APP_NAME=//p' "$PREFIX/names.conf" 2>/dev/null | head -1); app_title=${app_title:-AoE2 DE (Part A)}
bundle_version() { [[ -f "$1/Contents/Info.plist" ]] && /usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$1/Contents/Info.plist" 2>/dev/null; }

# --- graphics backend for the game process ------------------------------------
# CrossOver's bin/wine overwrites inherited variables with the bottle's
# [EnvironmentVariables] (CX_GRAPHICS_BACKEND, WINEDXVK, ...), so a plain export would
# not win. CX_ENV is applied after the bottle's settings. It is set only on the two
# game commands below, so the bottle and Steam keep their own backend.
backend=${AOE2_BACKEND:-dxmt}
game_cxenv=${CX_ENV:-}
# Every start skips the intro video (the game's own SKIPINTRO option). Under CrossOver the intro never plays: it fails at
# once, or the game hangs on "Opening video..." with a black window. Added to the player's own AOE2_ARGS, never replacing
# them, never twice.
if [[ " ${AOE2_ARGS:-} " != *" SKIPINTRO "* ]]; then AOE2_ARGS="${AOE2_ARGS:+$AOE2_ARGS }SKIPINTRO"; fi
# The game is started directly, not through Steam's Play button. Steam sets these two for every game it launches; with
# them Steamworks treats this start as Steam's and does not ask Steam to start a second copy (it does that when the game
# folder has no steam_appid.txt, which is the normal case). Only the game gets them, never Steam itself.
steam_ids="SteamAppId=813780 SteamGameId=813780"
case "$backend" in
  bottle) ;;
  wined3d) game_cxenv="CX_GRAPHICS_BACKEND=wined3d WINEDXVK=0${game_cxenv:+ $game_cxenv}" ;;
  dxvk|d3dmetal|dxmt) game_cxenv="CX_GRAPHICS_BACKEND=$backend${game_cxenv:+ $game_cxenv}" ;;
  *) echo "unknown AOE2_BACKEND '$backend' (wined3d|bottle|dxvk|d3dmetal|dxmt)"; exit 2 ;;
esac

run_stock() {
  local log="$PREFIX/logs/run-stock-$stamp.log"
  echo "mode stock, backend $backend, log: $log"
  [[ -n "${AOE2_DRYRUN:-}" ]] && return 0
  CX_ENV="$steam_ids${game_cxenv:+ $game_cxenv}" "$stock_app/Contents/SharedSupport/CrossOver/bin/wine" --no-update --bottle "$bottle" "$exe" ${=AOE2_ARGS:-} > "$log" 2>&1
}

fallback() {
  notify "Part A not used: $1 Starting normally."
  run_stock
  exit $?
}

if pgrep -if "^C:.Program Files \(x86\).Steam.steamapps.common.AoE2DE.AoE2DE_s\.exe" >/dev/null; then
  notify "AoE2 is already running."; exit 1
fi
[[ -n "${AOE_HUD:-}" ]] && export MTL_HUD_ENABLED=1

# --- FIRST: is everything exactly what this release was built for? (MANIFEST, fails closed) ---
# Checked before Steam is started, so a CrossOver update never runs our files. On any mismatch
# the start below is the normal CrossOver one (Steam + game through /Applications CrossOver).
manifest_problem() {
  local mf="$PREFIX/MANIFEST" want k p h f
  [[ -f "$mf" ]] || { echo "the install has no MANIFEST (reinstall)"; return 0; }
  want=$(awk '$1=="built_for_cx"{print $2}' "$mf")
  local have=$(bundle_version "$stock_app") copyv=$(bundle_version "$copy_app")
  ver_ok() { [[ "$1" == "$2" || ( "$2" != *.*.*.* && "$1" == "$2".* ) ]]; }
  ver_ok "$have" "$want" || { echo "CrossOver is now ${have:-unknown}; this release is built for $want"; return 0; }
  ver_ok "$copyv" "$want" || { echo "the patched CrossOver copy is ${copyv:-missing}, expected $want (reinstall)"; return 0; }
  while read -r k p h; do
    case "$k" in
      stock) f="$stock_app/Contents/SharedSupport/CrossOver/$p" ;;
      ours)  case "$p" in copy:*) f="$copy_app/Contents/SharedSupport/CrossOver/${p#copy:}" ;; prefix:*) f="$PREFIX/${p#prefix:}" ;; *) continue ;; esac ;;
      *) continue ;;
    esac
    [[ "$(shasum -a 256 "$f" 2>/dev/null | cut -d' ' -f1)" == "$h" ]] || { echo "${p} differs from the release ($k file)"; return 0; }
  done < "$mf"
  return 1
}
gate_reason=
[[ "$1" == soft ]] && gate_reason=$(manifest_problem)

# --- Steam must run and be signed in before the game starts --------------------
# Steam runs in the normal CrossOver (as when started from CrossOver). The game then
# joins Steam's wineserver; the version check below makes sure they match.
stock_wine="$stock_app/Contents/SharedSupport/CrossOver/bin/wine"
steam_running() { pgrep -if "^C:.Program Files \(x86\).Steam.steam\.exe" >/dev/null; }
steam_signed_in() {
  steam_running >/dev/null || return 1
  local u
  u=$(env -u MTL_HUD_ENABLED "$stock_wine" --no-update --bottle "$bottle" \
      reg query 'HKCU\Software\Valve\Steam\ActiveProcess' /v ActiveUser 2>/dev/null \
      | tr -d '\r' | awk '/ActiveUser/ {print $NF}')
  [[ -n "$u" && "$u" != "0x0" && "$u" != "0" ]]
}
# --- version-bound rules: names and status from rules.manifest (falls back to built-in names) ---
rules_mf="$PREFIX/rules.manifest"
rule_field() {   # rule_field <id> <key>  -> value from rules.manifest ("rule <id> key=value key=\"two words\" ...")
  [[ -f "$rules_mf" ]] || return 1
  local line; line=$(grep -E "^rule $1 " "$rules_mf" | head -1); [[ -n "$line" ]] || return 1
  if [[ "$line" =~ " $2=\"([^\"]*)\"" ]]; then print -r -- "$match[1]"
  elif [[ "$line" =~ " $2=([^ ]*)" ]]; then print -r -- "$match[1]"; fi
}
rule_off() {     # rule_off <id> <reason>: the fix found a version it was not made for; warn, keep the rest on
  local name=$(sed -n "s/^FIX_${1:u}=//p" "$PREFIX/names.conf" 2>/dev/null | head -1)
  [[ -n "$name" ]] || name=$(rule_field "$1" name); [[ -n "$name" ]] || name="$1"
  local what=$(rule_field "$1" target); case "$what" in game) what="game version" ;; rosetta) what="macOS/Rosetta version" ;; *) what="version" ;; esac
  echo "rule $1: OFF ($2)" >> "$PREFIX/logs/reports-$stamp.log"
  notify "$name is off: it does not match this $what. The game runs normally; the other fixes stay on."
}
# --- per-fix switches (each fix on by default except F59; AOE2_NO_<FIX>=1 turns one fix off) ---
# Defaults come from defaults.conf next to this script (shipped with the release: "NAME=1" on, "NAME=0" off),
# so a fix that passes its checks is turned on by editing data, not code. For each NAME:
# AOE2_NO_<NAME>=1 forces it off, AOE2_<NAME>=1 forces it on (the launcher app sets one of the two).
typeset -A dflt; dflt=(REORDER 1 F54A 1 TEXTFIX 1 MSYNC 0 FASTQPC 0 UCRT_OFFER 0 T4 0 T13 0)
if [[ -f "$PREFIX/defaults.conf" ]]; then
  while IFS='=' read -r k v; do
    [[ "$k" =~ '^[A-Z0-9_]+$' && "$v" =~ '^[01]$' ]] && dflt[$k]=$v
  done < "$PREFIX/defaults.conf"
fi
sw() { local on=${dflt[$1]:-0} no="AOE2_NO_$1" yes="AOE2_$1"; [[ -n "${(P)no:-}" ]] && on=0; [[ -n "${(P)yes:-}" ]] && on=1; print $on; }
want_reorder=$(sw REORDER); want_f54a=$(sw F54A); want_textfix=$(sw TEXTFIX)
want_msync=$(sw MSYNC); want_fastqpc=$(sw FASTQPC); want_ucrt_offer=$(sw UCRT_OFFER); want_t4=$(sw T4); want_t13=$(sw T13)
unset AOE_SUBST_COUNT AOE_SUBST_LIST AOE_RECLAIM_TEST_MUTATE AOE_RECLAIM_BUDGET_US AOE2_FASTQPC AOE2_FAST_CARET AOE2_FAST_SETCURSOR AOE2_FAST_KMTMEM   # set below, only for the patched start
# MSync is a mode of the bottle's wineserver: every process of the bottle must match it. The launcher
# chooses it only when it starts Steam itself; otherwise it follows the server that is already running.
server_msync() {   # prints on|off for the running wineserver of this bottle, or none
  local p e
  for p in $(pgrep -f '/wineserver$' 2>/dev/null); do
    e=$(ps -E -ww -o command= -p $p 2>/dev/null)
    [[ "$e" == *"/Bottles/$bottle"* ]] || continue
    [[ "$e" == *WINEMSYNC=1* ]] && { echo on; return; }
    echo off; return
  done
  echo none
}
ensure_steam() {
  if grep -qE '"WantsOfflineMode"[[:space:]]+"1"' "$bottles/$bottle/drive_c/Program Files (x86)/Steam/config/loginusers.vdf" 2>/dev/null; then
    notify "Steam is in offline mode, so multiplayer won't connect. In Steam choose Steam > Go Online, then start the game."
  fi
  # A running Steam is trusted anyway (see below); check that first and skip the 0.8 s `wine reg query`.
  steam_running && return 0
  steam_signed_in && return 0
  if [[ -n "${AOE2_DRYRUN:-}" ]]; then echo "Steam not running or not signed in (dry run: not starting it)"; return 0; fi
  # Steam already open: trust it (its ActiveUser value is not always set).
  steam_running && return 0
  notify "Starting Steam first. The game starts when Steam is ready."
  local steam_cxenv=""
  [[ "$(server_msync)" == none ]] && (( want_msync )) && steam_cxenv="WINEMSYNC=1"
  CX_ENV="$steam_cxenv" env -u MTL_HUD_ENABLED nohup "$stock_wine" --no-update --bottle "$bottle" \
    "C:/Program Files (x86)/Steam/steam.exe" > "$PREFIX/logs/steam-$stamp.log" 2>&1 &!
  # Ready = ActiveUser set, or Steam's UI (steamwebhelper renderer) up for 30 s.
  # Up to 10 minutes for updates and sign-in.
  local ui=0
  for i in {1..200}; do
    sleep 3
    if steam_signed_in; then sleep 8; return 0; fi
    if pgrep -if '^C:.Program Files \(x86\).Steam.bin.cef.*steamwebhelper\.exe --type=renderer' >/dev/null; then
      (( ui += 3 )); (( ui >= 30 )) && return 0
    fi
  done
  notify "Steam is not signed in after 10 minutes. Sign in to Steam and start the launcher again."
  exit 1
}
ensure_steam
# MSync for the game = the mode of the running server (a mismatch is never allowed).
msync=off
case "$(server_msync)" in
  on)   msync=on
        (( want_msync )) || echo "msync: AOE2_NO_MSYNC=1 ignored for this start: the bottle's wineserver already runs with MSync (quit Steam to change it)" >> "$PREFIX/logs/reports-$stamp.log" ;;
  off)  (( want_msync )) && echo "msync: not used for this start: the bottle's wineserver runs without it (Steam was started elsewhere). Quit Steam and start this launcher to use it." >> "$PREFIX/logs/reports-$stamp.log" ;;
  none) (( want_msync )) && msync=on ;;   # dry run without Steam: the start would use it
esac
[[ $msync == on ]] && game_cxenv="WINEMSYNC=1${game_cxenv:+ $game_cxenv}"

case "$1" in
  stock) run_stock; exit $? ;;
  soft) [[ -n "$gate_reason" ]] && fallback "$gate_reason." ;;
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
# --- stutter fix F54a (on unless AOE2_NO_F54A=1): Rosetta's clean-up in steps of at most 2 ms. ---
# The sidecar checks the exact Rosetta build itself and keeps the stock clean-up on any other build.
f54a=off
if (( want_f54a )); then export AOE_RECLAIM_BUDGET_US=2000 AOE_RECLAIM_LOG="$PREFIX/logs/reclaim-$stamp.log"; f54a=on; fi
# --- faster clock F59 (opt-in: AOE2_FASTQPC=1) ---
fastqpc=off
(( want_fastqpc )) && [[ -e "$PREFIX/.has-fastqpc" ]] && { export AOE2_FASTQPC=1; fastqpc=on; }
# --- T4 (caret/cursor answered in the client; release win32u.so, only if shipped): AOE2_T4=1 / AOE2_NO_T4=1 ---
t4=off
(( want_t4 )) && [[ -e "$PREFIX/.has-t4" ]] && { export AOE2_FAST_CARET=1 AOE2_FAST_SETCURSOR=1 AOE2_FAST_KMTMEM=1; t4=on; }
log="$PREFIX/logs/run-soft-$stamp.log"
# --- reorder of the DLC wrapper at translation time (on unless AOE2_NO_REORDER=1) ---
# Each health bar on screen makes the game ask "DLC 8 owned AND setting 14 on", with the
# slow, anti-tamper-protected DLC lookup first. Rosetta is shown the same function with the
# cheap setting check first (same result). Game memory is not written. mk_reorder.py finds
# the function in this game build; if it cannot (game update), this start is plain Part A.
reorder=off
if (( want_reorder )); then
  if subst=$(/usr/bin/python3 -I "$PREFIX/mk_reorder.py" exe "$unix_exe" 2>/dev/null) && [[ "$subst" == *AOE_SUBST_NEW=* ]]; then
    eval "$subst"; reorder=on
  else
    rule_off reorder "pattern not found in this game build"
  fi
fi
# --- T13 (hitch): the stack-cookie check shown to Rosetta in a tighter, identical form (default from defaults.conf) ---
# mk_rules.py finds the check by fingerprint in this game build; if it cannot (game update), T13 is off and the player is told.
# The sidecar reads AOE_SUBST_LIST; the reorder's single entry above becomes the list's first entry.
t13=off
if (( want_t13 )); then
  t13_out=$(/usr/bin/python3 -I "$PREFIX/mk_rules.py" "$unix_exe" T13 2>/dev/null)
  if [[ "$t13_out" == *AOE_SUBST_LIST=* ]]; then
    export AOE_SUBST_LIST="$(print -r -- "$t13_out" | sed -n 's/^AOE_SUBST_LIST=//p' | head -1)"; t13=on
    echo "rule t13: on ($(print -r -- "$t13_out" | grep -m1 '^RULESET'))" >> "$PREFIX/logs/reports-$stamp.log"
  else
    t13_why=$(print -r -- "$t13_out" | sed -n 's/^WARN rule T13: //p' | head -1)
    rule_off t13 "${t13_why:-the locator could not run (python3 missing or failed)}"
  fi
fi
# --- report (never change): the bottle's C runtime (UCRT) ----------------------------
# Logged at every start. One notification per version found, with an offer pointing to the README.
# This launcher never changes the bottle; the move is the user's own, reversible step.
ucrt_dll="$bottles/$bottle/drive_c/windows/system32/ucrtbase.dll"
ucrt_ver=$(/usr/bin/python3 -I -c "import sys,re;d=open(sys.argv[1],'rb').read().decode('utf-16le','ignore');m=re.search(r'FileVersion\W+([0-9][0-9.]+)',d);print(m.group(1) if m else '?')" "$ucrt_dll" 2>/dev/null)
echo "ucrt: ${ucrt_ver:-not found} ($ucrt_dll)" >> "$PREFIX/logs/reports-$stamp.log"
if (( want_ucrt_offer )) && [[ "$ucrt_ver" == 10.0.10137.* && ! -e "$PREFIX/.ucrt-notice-$ucrt_ver" ]]; then
  notify "Your bottle uses the 2015 C runtime ($ucrt_ver). Optional update: README, “Optional: current C runtime”. Nothing was changed."
  : > "$PREFIX/.ucrt-notice-$ucrt_ver"
fi

# --- DXMT set (our build with the menu-text fix unless AOE2_NO_TEXTFIX=1). Two complete sets live next to the
# copy (dxmt-textfix, dxmt-crossover; both hash-checked by the MANIFEST gate above); the chosen one is copied
# into the copy before the start. Never mixed. Only matters with the dxmt backend.
textfix=off; dxmt_set=dxmt-crossover
if [[ -d "$PREFIX/dxmt-textfix" ]] && (( want_textfix )); then dxmt_set=dxmt-textfix; textfix=on; fi
dxmt_same() { [[ "$(cd "$1" 2>/dev/null && find . -type f | LC_ALL=C sort | xargs shasum -a 256 2>/dev/null)" == "$(cd "$2" && find . -type f | LC_ALL=C sort | xargs shasum -a 256)" ]]; }
echo "mode soft, CrossOver $copy_ver, textfix $textfix, .text $AOE_SOFTFAULT_PC-$AOE_SOFTFAULT_END, reorder $reorder, t13 $t13, f54a $f54a, fastqpc $fastqpc, t4 $t4, msync $msync, backend $backend, log: $log"
[[ -n "${AOE2_DRYRUN:-}" ]] && exit 0
if [[ -d "$PREFIX/$dxmt_set" ]] && ! dxmt_same "$R/lib/dxmt" "$PREFIX/$dxmt_set"; then
  rm -rf "$R/lib/dxmt" && cp -cR "$PREFIX/$dxmt_set" "$R/lib/dxmt" && dxmt_same "$R/lib/dxmt" "$PREFIX/$dxmt_set" \
    || fallback "could not switch the DXMT files."
  echo "dxmt: copy now uses $dxmt_set" >> "$PREFIX/logs/reports-$stamp.log"
fi
# Every start: the copy's seal must be valid (switching the DXMT set above, or a copy prepared by 2.1, breaks it), else
# macOS may call the copy "damaged". Re-seal ad hoc only when needed (verify ~0.6 s, re-seal ~1 s). Ours only.
/usr/bin/codesign --verify --deep --strict "$copy_app" >/dev/null 2>&1 || /usr/bin/codesign --force --deep --sign - "$copy_app" >/dev/null 2>&1 \
  || echo "seal: could not re-seal the CrossOver copy" >> "$PREFIX/logs/reports-$stamp.log"
# Every start: clear the quarantine flag inside Trebuchet's own folder (idempotent, fast). A copy that 2.1 prepared from a
# browser-downloaded CrossOver, or files copied out of a downloaded Trebuchet, would otherwise make Gatekeeper call the
# copy "damaged". Only $PREFIX; never /Applications/CrossOver.app or the bottle. Apple's xattr by path.
/usr/bin/xattr -dr com.apple.quarantine "$PREFIX" 2>/dev/null || true
CX_ENV="$steam_ids${game_cxenv:+ $game_cxenv}" "$R/bin/wine" --no-update --bottle "$bottle" "$exe" ${=AOE2_ARGS:-} > "$log" 2>&1 &
wine_pid=$!

# Backend self-check (read-only): which backend DLL the game process has mapped.
# lsof lists the files the process has open; nothing in the game is touched.
case "$backend" in
  dxmt)     backend_dll="lib/dxmt/x86_64-windows/d3d11.dll" ;;
  dxvk)     backend_dll="lib/dxvk/x86_64-windows/d3d11.dll" ;;
  d3dmetal) backend_dll="lib64/apple_gptk/wine/x86_64-windows/d3d11.dll" ;;
  wined3d)  backend_dll="lib/wine/x86_64-windows/wined3d.dll" ;;
  *)        backend_dll= ;;
esac
backend_seen=
# --- report (never change): the game window, read without any new permission ------------------
# lsappinfo (front app) and the on-screen window list (CGWindowList via JXA; owner, layer, bounds,
# front-to-back order) need no Accessibility or Screen Recording permission. The KEY-window status
# itself is only readable with Accessibility, so it is logged as "not checked".
window_report() {
  local front gpid res
  local fasn=$(lsappinfo front 2>/dev/null)
  front=$(lsappinfo info -only name "$fasn" 2>/dev/null | sed -n '1s/^"\([^"]*\)".*/\1/p')
  local fpid=$(lsappinfo info -only pid "$fasn" 2>/dev/null | sed -n 's/.*pid = \([0-9]*\).*/\1/p')
  gpid=$(pgrep -if "^C:.Program Files \(x86\).Steam.steamapps.common.AoE2DE.AoE2DE_s\.exe" | head -1)
  res=$(/usr/bin/osascript -l JavaScript - "$gpid" 2>/dev/null <<'JXA'
function run(argv){ObjC.import("CoreGraphics");ObjC.import("AppKit");
var a=ObjC.deepUnwrap(ObjC.castRefToObject($.CGWindowListCopyWindowInfo($.kCGWindowListOptionOnScreenOnly|$.kCGWindowListExcludeDesktopElements,0)));
var top=null; for(var i=0;i<a.length;i++){ if(a[i].kCGWindowLayer===0){top=a[i];break;} }
if(!top) return "no normal window on screen";
var b=top.kCGWindowBounds, f=$.NSScreen.mainScreen.frame;
var full=(b.X>=0&&b.Y>=0&&b.X+b.Width<=f.size.width&&b.Y+b.Height<=f.size.height);
var out="topmost normal window: "+top.kCGWindowOwnerName+" (pid "+top.kCGWindowOwnerPID+", game pid "+argv[0]+"), "+b.Width+"x"+b.Height+(full?" fully on screen":" NOT fully on screen");
// overlap: windows listed before the game's window (front-to-back order) that intersect it
var gi=-1; for(var j=0;j<a.length;j++){ if(String(a[j].kCGWindowOwnerPID)===String(argv[0])&&a[j].kCGWindowLayer===0){gi=j;break;} }
if(gi<0) return out+"; overlap: game window not found";
var g=a[gi].kCGWindowBounds, ov=[];
for(var k=0;k<gi;k++){ var w=a[k], wb=w.kCGWindowBounds; if(!wb||w.kCGWindowAlpha===0||w.kCGWindowOwnerName==="Window Server") continue;
  if(w.kCGWindowLayer>0&&wb.Width>=f.size.width&&wb.Height>=f.size.height) continue; // invisible full-screen system layers (Dock etc.)
  var ix=Math.min(g.X+g.Width,wb.X+wb.Width)-Math.max(g.X,wb.X), iy=Math.min(g.Y+g.Height,wb.Y+wb.Height)-Math.max(g.Y,wb.Y);
  if(ix>0&&iy>0) ov.push(w.kCGWindowOwnerName+" layer "+w.kCGWindowLayer+" "+Math.round(ix)+"x"+Math.round(iy)); }
return out+"; overlap: "+(ov.length?ov.join(", "):"none");}
JXA
)
  echo "window: front app ${front:-?} (pid ${fpid:-?}$([[ -n "$gpid" && "$fpid" == "$gpid" ]] && echo ", = the game" || echo ", NOT the game")); ${res:-window list unreadable}; key status not checked (needs Accessibility)" >> "$PREFIX/logs/reports-$stamp.log"
}
check_backend() {
  local gpid
  gpid=$(pgrep -if "^C:.Program Files \(x86\).Steam.steamapps.common.AoE2DE.AoE2DE_s\.exe" | head -1)
  [[ -n "$gpid" ]] || return 1
  /usr/sbin/lsof -Fn -p "$gpid" 2>/dev/null | grep -qF "$backend_dll"
}

# Watch the first 90 s for the patch's own fatal errors.
for i in {1..45}; do
  if [[ -n "$backend_dll" && -z "$backend_seen" ]] && (( i % 5 == 0 )) && check_backend; then
    backend_seen=1; echo "backend check: $backend ($backend_dll) loaded after ~$((i*2)) s" >> "$PREFIX/logs/backend-$stamp.log"
    window_report
  fi
  if [[ $f54a == on && -z "${f54a_seen:-}" && -s "$AOE_RECLAIM_LOG" ]]; then
    if grep -q '^\[reclaimcap\] not installed' "$AOE_RECLAIM_LOG"; then
      f54a_seen=1; rule_off f54a "$(sed -n 's/^\[reclaimcap\] not installed: //p' "$AOE_RECLAIM_LOG" | head -1)"
    elif grep -q '^\[reclaimcap\] installed' "$AOE_RECLAIM_LOG"; then
      f54a_seen=1; echo "rule f54a: on ($(grep -m1 '^\[reclaimcap\] sites' "$AOE_RECLAIM_LOG" | cut -c1-60))" >> "$PREFIX/logs/reports-$stamp.log"
    fi
  fi
  if grep -qE "software fault (bridge|translator|entries)" "$log" 2>/dev/null; then
    kill $wine_pid 2>/dev/null
    pkill -if "^C:.Program Files \(x86\).Steam.steamapps.common.AoE2DE.AoE2DE_s\.exe" 2>/dev/null
    sleep 3
    unset AOE_SOFTFAULT_PC AOE_SOFTFAULT_END WINELOADER AOELAB_SIDECAR_PATH AOE2_SOFTFAULT
    unset AOE_SUBST_PC AOE_SUBST_ORIG AOE_SUBST_NEW AOE_SUBST_LIST AOE_RECLAIM_BUDGET_US AOE_RECLAIM_LOG AOE2_FASTQPC AOE2_FAST_CARET AOE2_FAST_SETCURSOR AOE2_FAST_KMTMEM
    fallback "the patched start failed ($(grep -oE 'cannot [^(]*|software fault entries missing' "$log" | head -1))."
  fi
  kill -0 $wine_pid 2>/dev/null || break
  sleep 2
done
[[ $f54a == on && -z "${f54a_seen:-}" ]] && echo "rule f54a: no status line in $AOE_RECLAIM_LOG after 90 s (install not confirmed)" >> "$PREFIX/logs/reports-$stamp.log"
if [[ -n "$backend_dll" && -z "$backend_seen" ]] && kill -0 $wine_pid 2>/dev/null; then
  echo "backend check: $backend ($backend_dll) NOT seen in the first 90 s" >> "$PREFIX/logs/backend-$stamp.log"
  notify "Graphics backend $backend not confirmed in the first 90 s. See logs/backend-$stamp.log."
fi
wait $wine_pid
