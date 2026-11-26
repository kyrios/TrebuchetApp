#!/bin/zsh
# Release gate: everything we ship runs on the macOS versions Trebuchet supports (v2.1.1 shipped an ntdll.so and a
# winemetal.so built for macOS 27.2 only; on older macOS the game could not start: "Symbol not found: _pipe2").
#   audit-minos.sh <folder>   (a payload bin/, an unpacked release, or an app bundle)
#  1. every Mach-O: minimum macOS (LC_BUILD_VERSION minos, or LC_VERSION_MIN_MACOSX) <= MAX_MINOS (default 14.0);
#  2. ntdll.so: minimum macOS <= 10.15, as CrossOver 26.3's own ntdll.so;
#  3. ntdll.so: every undefined symbol is in .github/audit/ntdll-imports-crossover-26.3.txt (CrossOver 26.3's own ntdll
#     imports plus the ones our patch needs and that exist on 10.15), so no newer libSystem call slips in.
#  Exception (2.1.2): the DXMT text-fix winemetal.so may be newer than MAX_MINOS only when the shipped run-aoe2.sh has the
#  runtime gate that uses it on a new-enough macOS alone (else CrossOver's DXMT, minos 14.0). Never ntdll.so.
#  4. an app bundle (<folder>/Contents/Info.plist): LSMinimumSystemVersion == APP_MIN (default 26.0, the declared
#     minimum since 2.2.1; sign-app.sh copies it into the appcast item), and no Mach-O needs a newer macOS than that.
#     APP_MIN=any skips the equality (CI's audit of an older published release, which declared 14.0).
# Any hit fails the release. Exit 0 = clean.
set -euo pipefail
root=${1:?folder}; here=${0:A:h}
MAX_MINOS=${MAX_MINOS:-14.0}; NTDLL_MINOS=10.15; APP_MIN=${APP_MIN:-26.0}
allowed=$here/../audit/ntdll-imports-crossover-26.3.txt
le() { [[ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1)" == "$1" ]]; }   # $1 <= $2
minos() { otool -l "$1" 2>/dev/null | awk '/LC_BUILD_VERSION/{b=1} b&&/minos/{print $2; exit} /LC_VERSION_MIN_MACOSX/{v=1} v&&/version/{print $2; exit}'; }
fail=0; n=0; gated=0
gate='macho_minos "$PREFIX/dxmt-textfix/x86_64-unix/winemetal.so"'
while IFS= read -r -d '' r; do grep -qF -- "$gate" "$r" && gated=1; done < <(find "$root" -name run-aoe2.sh -type f -print0)
while IFS= read -r -d '' f; do
  file -b "$f" | grep -q Mach-O || continue
  n=$((n+1)); m=$(minos "$f"); rel=${f#$root/}
  [[ -n $m ]] || { print "FAIL $rel: no minimum macOS version found"; fail=1; continue; }
  if ! le "$m" "$MAX_MINOS"; then
    if [[ $rel == */dxmt/x86_64-unix/winemetal.so || $rel == dxmt/x86_64-unix/winemetal.so ]] && (( gated )); then
      print "note $rel: built for macOS $m; allowed, run-aoe2.sh uses it only on macOS >= $m (else CrossOver's DXMT)"
    else print "FAIL $rel: built for macOS $m (must be <= $MAX_MINOS)"; fail=1; fi
  fi
  if [[ ${f:t} == ntdll.so ]]; then
    le "$m" "$NTDLL_MINOS" || { print "FAIL $rel: ntdll.so built for macOS $m (must be <= $NTDLL_MINOS, as CrossOver's)"; fail=1; }
    extra=$(nm -u "$f" | sort -u | comm -23 - <(sort -u "$allowed") | tr '\n' ' ')
    [[ -z ${extra// /} ]] || { print "FAIL $rel: imports symbols CrossOver 26.3's ntdll does not: $extra"; fail=1; }
  fi
done < <(find "$root" -type f -print0)
(( n > 0 )) || { print "FAIL: no Mach-O file under $root"; exit 1; }
declared=
if [[ -f $root/Contents/Info.plist ]]; then
  declared=$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$root/Contents/Info.plist" 2>/dev/null || true)
  [[ -n $declared ]] || { print "FAIL Contents/Info.plist: no LSMinimumSystemVersion"; fail=1; }
  if [[ -n $declared && $APP_MIN != any && $declared != "$APP_MIN" ]]; then print "FAIL Contents/Info.plist: LSMinimumSystemVersion $declared (must be $APP_MIN)"; fail=1; fi
  [[ -z $declared ]] || le "$MAX_MINOS" "$declared" || { print "FAIL: binaries may need macOS $MAX_MINOS, more than the declared $declared"; fail=1; }
fi
(( fail )) && exit 1
print "audit-minos: clean ($n Mach-O files, <= macOS $MAX_MINOS; ntdll <= $NTDLL_MINOS with CrossOver's imports${declared:+; app declares macOS $declared})"
