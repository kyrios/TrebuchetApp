#!/bin/zsh
# Release gate: no offline-diagnostic code in anything we ship.
#   audit-diagnostics.sh <folder>   (a payload bin/, an unpacked release, or an app bundle)
# Checks every Mach-O and PE file under <folder>:
#  1. allowlist: every aoe_/AOE_/AOE2_ name (strings + symbols) must be listed in .github/audit/aoe-allowlist.txt;
#  2. denylist backstop: names of our offline diagnostics, with or without the prefix (trap counter, VM/text dumps,
#     page watch, rip sampler, server/syscall counters, block log, pointer probe, the parked cursor-position cache).
# Any hit fails the release. Exit 0 = clean.
set -euo pipefail
root=${1:?folder}; here=${0:A:h}
allow=$here/../audit/aoe-allowlist.txt
deny='trapcount|TRAPCOUNT|TRAPHIST|VMDUMP|TEXTDUMP|PAGEWATCH|RIPSAMPLE|SRVCOUNT|SYSCOUNT|BLOCKLOG|PTRPROBE|THREADINFO_LOG|aoe_sys[_a-z]|aoe_vm[_a-z]|aoe_tc[_a-z]|aoe_lc[_a-z]|aoe_fast_cursorpos|aoe_driver_cursor|AOE2_R4|AOE2_VPROT|AOE2_VMUTEX|AOE2_FASTSYSCALL|AOE_SOFTFAULT_SYSCALL'
typeset -A ok; while read -r n; do [[ -z $n || $n == \#* ]] && continue; ok[$n]=1; done < $allow
fail=0; n=0
while IFS= read -r -d '' f; do
  t=$(file -b "$f")
  [[ $t == *Mach-O* || $t == *PE32* ]] || continue
  n=$((n+1))
  s=$(strings -a "$f"; if [[ $t == *Mach-O* ]]; then nm -a "$f" 2>/dev/null | awk '{print $NF}' || true; fi)
  bad=$(print -r -- "$s" | { grep -oE "$deny" || true; } | sort -u | tr '\n' ' ')
  [[ -n $bad ]] && { print "FAIL ${f#$root/}: diagnostic names: $bad"; fail=1; }
  ids=$(print -r -- "$s" | { grep -oE '(^|[^A-Za-z0-9])_?(aoe_|AOE2?_)[A-Za-z0-9_]+' || true; } | sed -E 's/^[^A-Za-z_]//; s/^_+//' | sort -u)
  for id in ${=ids}; do
    [[ -n ${ok[$id]:-} ]] || { print "FAIL ${f#$root/}: '$id' is not on the reviewed allowlist"; fail=1; }
  done
done < <(find "$root" -type f -print0)
(( n > 0 )) || { print "FAIL: no Mach-O or PE file found under $root"; exit 1; }
(( fail )) && exit 1
print "audit-diagnostics: clean ($n binaries)"
