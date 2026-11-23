#!/bin/zsh
# Sign, notarize and pack a tested release payload (the unsigned tarball the maintainer built with
# mk-release and the game gate tested). Nothing is rebuilt: Wine, the sidecar, DXMT and the app keep
# their bytes; only signatures are added, then the MANIFEST lines of the signed files are updated.
#   sign-payload.sh <dir with aoe2-mac-softfault/> <out dir>
# Env: TAG (e.g. v2.0); SIGN_IDENTITY ("-" = ad hoc, for a local dry run); NOTARY_KEY (path to the .p8),
# NOTARY_KEY_ID, NOTARY_ISSUER (all three or none: without them nothing is notarized).
# Order as in mk-release: sign every Mach-O first, then hash (MANIFEST), then notarize and staple.
set -euo pipefail
W=${1:?payload dir}; OUT=${2:?out dir}; W=${W:A}; mkdir -p "$OUT"; OUT=${OUT:A}
TAG=${TAG:?tag}; ID=${SIGN_IDENTITY:--}
D=$W/aoe2-mac-softfault; B=$D/bin
[[ -f $D/MANIFEST && -d $B ]] || { echo "no payload in $W"; exit 1; }

# 1. Before signing: every file the MANIFEST lists must still have its tested hash.
while read -r kind rel hash; do
  [[ $kind == src ]] || continue
  [[ "$(shasum -a 256 "$B/$rel" | cut -d' ' -f1)" == "$hash" ]] || { echo "payload differs from its MANIFEST: $rel"; exit 1; }
done < $D/MANIFEST
echo "payload matches its MANIFEST"
# 1b. Release gate: no offline-diagnostic code in any shipped binary (Wine, the sidecar, DXMT, the app).
zsh "${0:A:h}/audit-diagnostics.sh" "$B"

# 2. Sign: every Mach-O we ship, hardened runtime + secure timestamp; the app last (inner binary first).
ts=(--timestamp); [[ $ID == - ]] && ts=()
for f in $B/x87sidecar $B/ntdll.so $B/win32u.so $B/dxmt/x86_64-unix/winemetal.so; do
  [[ -f $f ]] && codesign -f -s "$ID" --options runtime $ts "$f"
done
for a in $B/*.app(N); do
  codesign -f -s "$ID" --options runtime $ts "$a/Contents/MacOS/"*
  codesign -f -s "$ID" --options runtime $ts "$a"
  codesign --verify --strict --deep "$a"
done

# 3. MANIFEST: new hashes for the signed files; every other line stays as built (stock CrossOver hashes too).
tmp=$(mktemp)
while IFS= read -r line; do
  set -- ${=line}
  if [[ $1 == src ]]; then print -r -- "src $2 $(shasum -a 256 "$B/$2" | cut -d' ' -f1)"; else print -r -- "$line"; fi
done < $D/MANIFEST > $tmp
diff $D/MANIFEST $tmp | grep '^>' | cut -c1-80 || true
mv $tmp $D/MANIFEST; chmod 644 $D/MANIFEST

# 4. Notarize all signed binaries in one submission; staple the app (plain Mach-O files can't hold a ticket;
#    Gatekeeper looks theirs up online).
if [[ -n ${NOTARY_KEY:-} ]]; then
  ditto -c -k --keepParent $B $OUT/notarize.zip
  res=$(xcrun notarytool submit $OUT/notarize.zip --key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER" --wait --output-format json)
  print -r -- "$res"
  sid=$(print -r -- "$res" | plutil -extract id raw - 2>/dev/null || true)
  [[ "$(print -r -- "$res" | plutil -extract status raw -)" == Accepted ]] || {
    [[ -n $sid ]] && xcrun notarytool log "$sid" --key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER" || true
    echo "notarization not accepted"; exit 1; }
  rm $OUT/notarize.zip
  for a in $B/*.app(N); do
    for i in 1 2 3 4 5; do xcrun stapler staple "$a" && break; [[ $i == 5 ]] && exit 1; sleep 20; done
    for i in 1 2 3 4 5; do xcrun stapler validate "$a" && break; [[ $i == 5 ]] && exit 1; sleep 20; done
    spctl -a -vv "$a"
  done
fi

# 5. Pack exactly as mk-release does (fixed times and owners, sorted names, no metadata).
find $D -exec touch -h -t 202611220000 {} +
cd $W
COPYFILE_DISABLE=1 tar --uid 0 --gid 0 --uname root --gname wheel --no-xattrs --no-mac-metadata -n \
  --null -T <(find aoe2-mac-softfault -print0 | LC_ALL=C sort -z) -cf - | gzip -n -9 > "$OUT/aoe2-mac-softfault-$TAG.tar.gz"
cd $OUT; shasum -a 256 "aoe2-mac-softfault-$TAG.tar.gz" > SHA256SUMS; cat SHA256SUMS
