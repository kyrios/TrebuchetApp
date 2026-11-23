#!/bin/zsh
# Trebuchet 2.1+: sign, notarize and pack the tested app as Trebuchet.dmg. Nothing is rebuilt: the payload inside
# the app (Wine, the sidecar, DXMT, scripts) keeps its bytes; only signatures are added, then the MANIFEST lines of the
# signed files are updated.
#   sign-app.sh <unsigned app zip (ditto) or .app> <out dir>
# Env:
#   TAG (e.g. v2.1); SIGN_IDENTITY ("-" = ad hoc, for a local dry run)
#   NOTARY_KEY (path to the .p8), NOTARY_KEY_ID, NOTARY_ISSUER: all three or none (without them nothing is notarized)
#   DMG_BACKGROUND: a .tiff (1x + 2x); default .github/dmg/background.tiff made from background{,@2x}.png
#   DMGBUILD: the dmgbuild command (pinned in .github/dmg/requirements.txt)
#   (an app with Sparkle.framework also gets appcast-item.xml; the workflow adds its EdDSA signature)
# Order: inner Mach-O files → MANIFEST → app → notarize + staple the app → DMG → sign → notarize + staple the DMG.
set -euo pipefail
IN=${1:?app zip or .app}; OUT=${2:?out dir}; mkdir -p "$OUT"; OUT=${OUT:A}
TAG=${TAG:?tag}; ID=${SIGN_IDENTITY:--}
here=${0:A:h}; repo=${here:h:h}
W=$(mktemp -d)
if [[ $IN == *.zip ]]; then ditto -x -k "$IN" "$W"; else ditto "$IN" "$W/${IN:t}"; fi
A=$(print -l "$W"/*.app(N) | head -1); [[ -d $A ]] || { echo "no app in $IN"; exit 1; }
T=$A/Contents/Resources/Trebuchet; B=$T/bin
[[ -f $T/MANIFEST && -d $B ]] || { echo "the app carries no payload ($T)"; exit 1; }
# A release never carries a test update feed: Sparkle apps must point at the GitHub Pages feed, with no test marker.
if [[ -d $A/Contents/Frameworks/Sparkle.framework ]]; then
  feed=$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$A/Contents/Info.plist" 2>/dev/null || true)
  [[ $feed == https://kyrios.github.io/TrebuchetApp/appcast.xml ]] || { echo "SUFeedURL is '$feed', not the release feed"; exit 1; }
  /usr/libexec/PlistBuddy -c 'Print :TrebuchetTestFeed' "$A/Contents/Info.plist" >/dev/null 2>&1 && { echo "test-feed build"; exit 1; }
  [[ -n "$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$A/Contents/Info.plist" 2>/dev/null)" ]] || { echo "no SUPublicEDKey"; exit 1; }
fi
ts=(--timestamp); [[ $ID == - ]] && ts=()
sign() { codesign -f -s "$ID" --options runtime $ts "$@"; }

# 1. Before signing: every payload file the MANIFEST lists must still have its tested hash.
while read -r kind rel hash; do
  [[ $kind == src ]] || continue
  [[ "$(shasum -a 256 "$B/$rel" | cut -d' ' -f1)" == "$hash" ]] || { echo "payload differs from its MANIFEST: $rel"; exit 1; }
done < $T/MANIFEST
echo "payload matches its MANIFEST"

# 2. Inner code first: our Mach-O files in the payload, then Sparkle (if embedded), then the app.
for f in $B/x87sidecar $B/ntdll.so $B/win32u.so $B/dxmt/x86_64-unix/winemetal.so; do [[ -f $f ]] && sign "$f"; done
S=$A/Contents/Frameworks/Sparkle.framework
if [[ -d $S ]]; then
  V=$S/Versions/B
  # Sparkle's own order (its docs): XPC services (the Downloader keeps its entitlements), Autoupdate, Updater.app, framework.
  for x in $V/XPCServices/*.xpc(N); do sign --preserve-metadata=entitlements "$x"; done
  [[ -e $V/Autoupdate ]] && sign "$V/Autoupdate"
  [[ -d $V/Updater.app ]] && sign "$V/Updater.app"
  sign "$S"
fi

# 3. MANIFEST: new hashes for the signed payload files; every other line stays as built (stock CrossOver hashes too).
tmp=$(mktemp)
while IFS= read -r line; do
  set -- ${=line}
  if [[ $1 == src ]]; then print -r -- "src $2 $(shasum -a 256 "$B/$2" | cut -d' ' -f1)"; else print -r -- "$line"; fi
done < $T/MANIFEST > $tmp
diff $T/MANIFEST $tmp | grep '^>' | cut -c1-80 || true
mv $tmp $T/MANIFEST; chmod 644 $T/MANIFEST

sign "$A/Contents/MacOS/"*
sign "$A"
codesign --verify --strict --deep --verbose=2 "$A"

notarize() {   # <file>: submit, wait, fail with Apple's log unless Accepted
  local res sid
  res=$(xcrun notarytool submit "$1" --key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER" --wait --output-format json)
  print -r -- "$res"
  sid=$(print -r -- "$res" | plutil -extract id raw - 2>/dev/null || true)
  [[ "$(print -r -- "$res" | plutil -extract status raw -)" == Accepted ]] || {
    [[ -n $sid ]] && xcrun notarytool log "$sid" --key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER" || true
    echo "notarization not accepted: $1"; exit 1; }
}
staple() { for i in 1 2 3 4 5; do xcrun stapler staple "$1" && xcrun stapler validate "$1" && return 0; sleep 20; done; return 1; }

# 4. Notarize and staple the app itself (so a copy in /Applications carries its ticket offline).
if [[ -n ${NOTARY_KEY:-} ]]; then
  ditto -c -k --keepParent "$A" "$W/app.zip"; notarize "$W/app.zip"; rm "$W/app.zip"
  staple "$A"; spctl -a -vv "$A"
fi

# 5. The disk image: the designed background, the app and an Applications link (layout in .github/dmg/settings.py).
bg=${DMG_BACKGROUND:-}
if [[ -z $bg ]]; then
  bg=$W/background.tiff
  tiffutil -cathidpicheck "$repo/.github/dmg/background.png" "$repo/.github/dmg/background@2x.png" -out "$bg"
fi
ver=${TAG#v}
dmg=$OUT/Trebuchet-$ver.dmg
rm -f "$dmg"
${=DMGBUILD:-dmgbuild} -s "$repo/.github/dmg/settings.py" -D app="$A" -D background="$bg" "Trebuchet $ver" "$dmg"
codesign -f -s "$ID" $ts "$dmg"
if [[ -n ${NOTARY_KEY:-} ]]; then notarize "$dmg"; staple "$dmg"; spctl -a -vv -t open --context context:primary-signature "$dmg"; fi

# 6. Sparkle: the appcast item for this DMG, without its signature. The release workflow adds the EdDSA signature in a
#    separate step that alone sees the key (sign_update), and GitHub Pages gets the item only when the release is published.
if [[ -d $A/Contents/Frameworks/Sparkle.framework ]]; then
  build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$A/Contents/Info.plist")
  minos=$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$A/Contents/Info.plist")
  cat > "$OUT/appcast-item.xml" <<EOF
    <item>
      <title>Trebuchet $ver</title>
      <pubDate>$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')</pubDate>
      <sparkle:version>$build</sparkle:version>
      <sparkle:shortVersionString>$ver</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$minos</sparkle:minimumSystemVersion>
      <link>https://github.com/kyrios/TrebuchetApp/releases/tag/$TAG</link>
      <enclosure url="https://github.com/kyrios/TrebuchetApp/releases/download/$TAG/${dmg:t}" type="application/x-apple-diskimage" __SPARKLE_SIGNATURE__/>
    </item>
EOF
  cat "$OUT/appcast-item.xml"
fi

cd "$OUT"; shasum -a 256 "${dmg:t}" > SHA256SUMS; cat SHA256SUMS
rm -rf "$W"
